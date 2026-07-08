import SwiftUI

struct CourseDetailView: View {
    @Environment(AppModel.self) private var app
    let course: Course

    @State private var showSignIn = false

    private var persona: Persona? { app.persona(course.personaId) }
    private var tint: Color { Theme.tint(for: course.personaId) }
    private var enrollment: Enrollment? { app.userStore.enrollment(for: course.id) }

    var body: some View {
        ScrollView {
            VStack(alignment: .leading, spacing: 22) {
                hero

                if let persona {
                    ProfessorCard(persona: persona)
                }

                VStack(alignment: .leading, spacing: 10) {
                    SectionHeading(text: "Reading List")
                    ForEach(course.texts, id: \.bookID) { text in
                        HStack(alignment: .top, spacing: 10) {
                            Image(systemName: "book.closed")
                                .foregroundStyle(tint)
                                .font(.footnote)
                                .padding(.top, 3)
                            VStack(alignment: .leading, spacing: 2) {
                                Text(text.title)
                                    .font(.subheadline.weight(.medium))
                                    .fontDesign(.serif)
                                    .foregroundStyle(Theme.ink)
                                Text("\(text.author) · \(text.license == "public-domain-us" ? "Public domain" : text.license)")
                                    .font(.caption)
                                    .fontDesign(.default)
                                    .foregroundStyle(Theme.inkSecondary)
                            }
                        }
                    }
                }

                VStack(alignment: .leading, spacing: 12) {
                    SectionHeading(text: "Syllabus")
                    ForEach(course.units) { unit in
                        UnitRow(course: course, unit: unit,
                                isCurrent: enrollment?.currentUnit == unit.number - 1,
                                isEnrolled: enrollment != nil)
                    }
                }

                enrollButton
                    .padding(.top, 4)
            }
            .padding(.horizontal)
            .padding(.bottom, 32)
        }
        .background(Theme.paper)
        .navigationTitle(course.title)
        .navigationBarTitleDisplayMode(.inline)
        .academyDestinations()
        .sheet(isPresented: $showSignIn) {
            SignInView()
                .presentationDetents([.medium, .large])
        }
        .onChange(of: app.auth.signedIn) {
            // Complete the pending enrollment right after sign-in.
            if app.auth.signedIn, showSignIn {
                showSignIn = false
                app.userStore.enroll(in: course.id)
            }
        }
    }

    private var hero: some View {
        VStack(alignment: .leading, spacing: 8) {
            HStack(spacing: 8) {
                Text(course.difficulty.capitalized).overline(tint)
                Text("·").foregroundStyle(Theme.inkSecondary)
                Text("\(course.estWeeks) weeks").overline()
                if app.freeCourseIDs.contains(course.id) {
                    Text("·").foregroundStyle(Theme.inkSecondary)
                    Text("Free").overline(tint)
                }
            }
            Text(course.title)
                .font(.largeTitle.weight(.semibold))
                .fontDesign(.serif)
                .foregroundStyle(Theme.ink)
            Text(course.description)
                .font(.body)
                .fontDesign(.serif)
                .foregroundStyle(Theme.ink.opacity(0.92))
                .lineSpacing(3)
        }
        .padding(.top, 8)
    }

    @ViewBuilder
    private var enrollButton: some View {
        if enrollment != nil {
            Label("Enrolled — see My Courses to continue", systemImage: "checkmark.seal.fill")
                .font(.subheadline.weight(.medium))
                .fontDesign(.serif)
                .foregroundStyle(tint)
                .frame(maxWidth: .infinity)
                .padding(.vertical, 14)
                .background(RoundedRectangle(cornerRadius: 12).fill(tint.opacity(0.10)))
        } else {
            Button {
                // Browsing is open to everyone; enrolling needs an account
                // in live mode (mock mode never shows sign-in).
                if app.requiresSignIn {
                    showSignIn = true
                } else {
                    app.userStore.enroll(in: course.id)
                }
            } label: {
                Text("Enroll")
                    .font(.headline)
                    .fontDesign(.serif)
                    .frame(maxWidth: .infinity)
                    .padding(.vertical, 6)
            }
            .buttonStyle(.borderedProminent)
            .tint(tint)
        }
    }
}

// MARK: - Syllabus unit row

private struct UnitRow: View {
    @Environment(AppModel.self) private var app
    let course: Course
    let unit: Unit
    let isCurrent: Bool
    let isEnrolled: Bool

    private var tint: Color { Theme.tint(for: course.personaId) }

    var body: some View {
        VStack(alignment: .leading, spacing: 8) {
            HStack(alignment: .firstTextBaseline) {
                Text("Unit \(unit.number)").overline(isCurrent ? tint : Theme.inkSecondary)
                if isCurrent {
                    Text("· current").overline(tint)
                }
                Spacer()
            }
            Text(unit.title)
                .font(.headline)
                .fontDesign(.serif)
                .foregroundStyle(Theme.ink)

            ForEach(unit.reading, id: \.self) { span in
                Label(readingLabel(span), systemImage: "book")
                    .font(.caption)
                    .fontDesign(.default)
                    .foregroundStyle(Theme.inkSecondary)
            }

            HStack(spacing: 12) {
                Label("\(unit.lectureOutline.count) lecture segments", systemImage: "text.book.closed")
                Label("\(unit.assignments.count) assignment\(unit.assignments.count == 1 ? "" : "s")", systemImage: "square.and.pencil")
            }
            .font(.caption)
            .fontDesign(.default)
            .foregroundStyle(Theme.inkSecondary)

            if isEnrolled {
                sessionLinks
            }
        }
        .bulletinCard(tint: isCurrent ? tint : nil)
    }

    /// Lecture and seminar always; the Academy kinds (§12.1) appear when
    /// the unit carries their authored spec.
    private var sessionLinks: some View {
        let unitIndex = unit.number - 1
        return VStack(alignment: .leading, spacing: 8) {
            HStack(spacing: 10) {
                NavigationLink(value: SessionRoute(course: course, unit: unitIndex, kind: .lecture)) {
                    Label("Lecture", systemImage: SessionKind.lecture.symbolName)
                }
                NavigationLink(value: SessionRoute(course: course, unit: unitIndex, kind: .seminar)) {
                    Label("Seminar", systemImage: SessionKind.seminar.symbolName)
                }
            }
            HStack(spacing: 10) {
                if unit.elenchusSpecs?.isEmpty == false {
                    NavigationLink(value: SessionRoute(course: course, unit: unitIndex, kind: .elenchus)) {
                        Label("Elenchus", systemImage: SessionKind.elenchus.symbolName)
                    }
                }
                if unit.thoughtExperiments?.isEmpty == false {
                    NavigationLink(value: SessionRoute(course: course, unit: unitIndex, kind: .thoughtExperiment)) {
                        Label("Experiment", systemImage: SessionKind.thoughtExperiment.symbolName)
                    }
                }
                if unit.argumentLabs?.isEmpty == false {
                    NavigationLink(value: SessionRoute(course: course, unit: unitIndex, kind: .argumentLab)) {
                        Label("Argument Lab", systemImage: SessionKind.argumentLab.symbolName)
                    }
                }
            }
        }
        .font(.caption.weight(.semibold))
        .buttonStyle(.bordered)
        .tint(tint)
    }

    private func readingLabel(_ span: ReadingSpan) -> String {
        let book = app.shortBookTitle(span.bookID)
        if span.chStart == span.chEnd {
            return "\(book), section \(span.chStart + 1)"
        }
        return "\(book), sections \(span.chStart + 1)–\(span.chEnd + 1)"
    }
}
