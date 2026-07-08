import SwiftUI

/// The essay cycle (SCOPE §3.2.5): prompt + rubric on top, an autosaving
/// editor below, live word count against the assignment target, and Submit
/// firing a `kind=essay` session turn.
struct EssayEditorView: View {
    @Environment(AppModel.self) private var app
    let route: EssayRoute

    @State private var text = ""
    @State private var loaded = false
    @State private var lastSaved: Date?
    @State private var saveTask: Task<Void, Never>?
    @State private var showingSubmission = false
    @State private var rubricExpanded = false

    private var assignment: Assignment { route.assignment }
    private var tint: Color { Theme.tint(for: route.course.personaId) }

    private var wordCount: Int {
        text.split { $0.isWhitespace || $0.isNewline }.count
    }

    var body: some View {
        ScrollView {
            VStack(alignment: .leading, spacing: 18) {
                promptCard
                rubricCard
                editor
            }
            .padding()
        }
        .background(Theme.paper)
        .navigationTitle("Assignment")
        .navigationBarTitleDisplayMode(.inline)
        .toolbar {
            ToolbarItem(placement: .confirmationAction) {
                Button("Submit") { showingSubmission = true }
                    .fontWeight(.semibold)
                    .disabled(text.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty)
            }
        }
        .fullScreenCover(isPresented: $showingSubmission) {
            EssaySubmissionView(route: route, essayBody: text)
        }
        .task { loadDraft() }
        .onChange(of: text) { scheduleAutosave() }
    }

    // MARK: sections

    private var promptCard: some View {
        VStack(alignment: .leading, spacing: 8) {
            HStack {
                Text(assignment.kind.capitalized).overline(tint)
                Spacer()
                Text("~\(assignment.lengthWords) words").overline()
            }
            Text(assignment.prompt)
                .font(.body)
                .fontDesign(.serif)
                .lineSpacing(3)
                .foregroundStyle(Theme.ink)
                .fixedSize(horizontal: false, vertical: true)
        }
        .bulletinCard(tint: tint)
    }

    private var rubricCard: some View {
        VStack(alignment: .leading, spacing: 10) {
            Button {
                withAnimation { rubricExpanded.toggle() }
            } label: {
                HStack {
                    Text("Rubric").overline(tint)
                    Spacer()
                    Image(systemName: rubricExpanded ? "chevron.up" : "chevron.down")
                        .font(.caption)
                        .foregroundStyle(Theme.inkSecondary)
                }
            }
            .buttonStyle(.plain)

            ForEach(assignment.rubric, id: \.name) { criterion in
                VStack(alignment: .leading, spacing: 4) {
                    HStack {
                        Text(criterion.name)
                            .font(.subheadline.weight(.semibold))
                            .fontDesign(.serif)
                            .foregroundStyle(Theme.ink)
                        Spacer()
                        Text("\(Int(criterion.weight * 100))%")
                            .font(.caption.monospacedDigit())
                            .foregroundStyle(Theme.inkSecondary)
                    }
                    if rubricExpanded {
                        ForEach(criterion.descriptors.sorted(by: { $0.key < $1.key }), id: \.key) { grade, descriptor in
                            HStack(alignment: .top, spacing: 8) {
                                Text(grade)
                                    .font(.caption.weight(.bold))
                                    .fontDesign(.serif)
                                    .foregroundStyle(tint)
                                    .frame(width: 16, alignment: .leading)
                                Text(descriptor)
                                    .font(.caption)
                                    .fontDesign(.serif)
                                    .foregroundStyle(Theme.inkSecondary)
                            }
                        }
                    }
                }
                if criterion.name != assignment.rubric.last?.name {
                    Rectangle().fill(Theme.rule).frame(height: 1)
                }
            }
        }
        .bulletinCard()
    }

    private var editor: some View {
        VStack(alignment: .leading, spacing: 8) {
            HStack {
                Text("Your draft").overline(tint)
                Spacer()
                Text("\(wordCount) / \(assignment.lengthWords) words")
                    .font(.caption.monospacedDigit())
                    .fontDesign(.default)
                    .foregroundStyle(wordCountColor)
                if lastSaved != nil {
                    Text("· saved")
                        .font(.caption)
                        .foregroundStyle(Theme.inkSecondary)
                }
            }
            TextEditor(text: $text)
                .font(.body)
                .fontDesign(.serif)
                .lineSpacing(4)
                .frame(minHeight: 320)
                .scrollContentBackground(.hidden)
                .padding(10)
                .background(RoundedRectangle(cornerRadius: 10).fill(Theme.card))
                .overlay(RoundedRectangle(cornerRadius: 10).strokeBorder(Theme.rule, lineWidth: 1))
        }
    }

    private var wordCountColor: Color {
        let target = Double(assignment.lengthWords)
        let count = Double(wordCount)
        if count < target * 0.5 { return Theme.inkSecondary }
        if count <= target * 1.25 { return tint }
        return .orange
    }

    // MARK: autosave (Documents/essays/<assignmentId>.txt)

    private static func draftURL(for assignmentId: String) -> URL {
        let docs = FileManager.default.urls(for: .documentDirectory, in: .userDomainMask)[0]
        let dir = docs.appendingPathComponent("essays", isDirectory: true)
        try? FileManager.default.createDirectory(at: dir, withIntermediateDirectories: true)
        return dir.appendingPathComponent("\(assignmentId).txt")
    }

    private func loadDraft() {
        guard !loaded else { return }
        loaded = true
        let url = Self.draftURL(for: assignment.id)
        if let saved = try? String(contentsOf: url, encoding: .utf8) {
            text = saved
        }
    }

    private func scheduleAutosave() {
        saveTask?.cancel()
        let snapshot = text
        let url = Self.draftURL(for: assignment.id)
        saveTask = Task {
            try? await Task.sleep(nanoseconds: 700_000_000)
            guard !Task.isCancelled else { return }
            try? snapshot.write(to: url, atomically: true, encoding: .utf8)
            lastSaved = Date()
        }
    }
}

// MARK: - Submission flow

/// Streams the professor's grading turn, then hands the `recordGrade`
/// payload to FeedbackView.
private struct EssaySubmissionView: View {
    @Environment(AppModel.self) private var app
    @Environment(\.dismiss) private var dismiss

    let route: EssayRoute
    let essayBody: String

    @State private var viewModel: SessionViewModel?

    private var tint: Color { Theme.tint(for: route.course.personaId) }

    var body: some View {
        NavigationStack {
            Group {
                if app.requiresSignIn {
                    // Grading is a live session call; the draft stays saved.
                    SignInView(inline: true)
                } else if let record = viewModel?.gradeRecord {
                    FeedbackView(course: route.course,
                                 assignment: route.assignment,
                                 record: record,
                                 essayBody: essayBody) {
                        dismiss() // Resubmit: back to the editor
                    }
                } else {
                    grading
                }
            }
            .background(Theme.paper)
            .navigationTitle("Submission")
            .navigationBarTitleDisplayMode(.inline)
            .toolbar {
                ToolbarItem(placement: .cancellationAction) {
                    Button("Close") { dismiss() }
                }
            }
        }
        .task(id: app.requiresSignIn) {
            guard !app.requiresSignIn, viewModel == nil else { return }
            let enrollmentId = app.userStore.enrollment(for: route.course.id)?.id.uuidString
                ?? UUID().uuidString
            let vm = SessionViewModel(
                course: route.course, unit: route.unitNumber - 1, kind: .essay,
                enrollmentId: enrollmentId,
                client: app.makeSessionClient(assignmentId: route.assignment.id))
            viewModel = vm
            await vm.start(essayBody: essayBody)
        }
    }

    private var grading: some View {
        ScrollView {
            VStack(alignment: .leading, spacing: 16) {
                HStack(spacing: 10) {
                    MonogramPortrait(persona: app.persona(route.course.personaId), size: 44)
                    VStack(alignment: .leading, spacing: 2) {
                        Text(app.persona(route.course.personaId)?.name ?? "Professor")
                            .font(.subheadline.weight(.semibold))
                            .fontDesign(.serif)
                        Text(viewModel?.isStreaming == true ? "Reading your draft…" : "Submitted")
                            .font(.caption)
                            .fontDesign(.serif)
                            .italic()
                            .foregroundStyle(Theme.inkSecondary)
                    }
                }

                if let say = viewModel?.messages.last(where: { $0.role == .professor })?.text,
                   !say.isEmpty {
                    Text(say)
                        .font(.body)
                        .fontDesign(.serif)
                        .lineSpacing(4)
                        .foregroundStyle(Theme.ink)
                        .bulletinCard(tint: tint)
                }

                if let error = viewModel?.errorMessage {
                    Label(error, systemImage: "exclamationmark.triangle")
                        .font(.footnote)
                        .foregroundStyle(.red)
                }

                if viewModel?.isStreaming == true {
                    ProgressView().frame(maxWidth: .infinity)
                }

                // Ended without a grade (e.g. empty-draft guardrail).
                if viewModel?.isStreaming == false && viewModel?.gradeRecord == nil
                    && viewModel?.endOfSession == true {
                    Button("Back to draft") { dismiss() }
                        .buttonStyle(.bordered)
                        .tint(tint)
                }
            }
            .padding()
        }
    }
}
