import SwiftUI

/// The streamed professor session: lecture, seminar, close reading, office
/// hours — plus the Academy kinds (§12.1): elenchus (phase strip + aporia
/// beat), thought experiment (authored node cards with choice buttons), and
/// argument lab (deterministic map pinned on top). Prose streams into
/// professor bubbles; citations render as distinct QuotePanels; uiHints
/// drive check-in chips and the lecture Continue affordance.
struct SessionView: View {
    @Environment(AppModel.self) private var app
    let route: SessionRoute

    @State private var viewModel: SessionViewModel?
    @FocusState private var inputFocused: Bool

    var body: some View {
        Group {
            if app.requiresSignIn {
                // Live mode, signed out: sessions need an account (§4.1);
                // browsing stays open elsewhere.
                SignInView(inline: true)
            } else if let viewModel {
                SessionContent(viewModel: viewModel, inputFocused: $inputFocused)
            } else {
                ProgressView()
                    .frame(maxWidth: .infinity, maxHeight: .infinity)
            }
        }
        .background(Theme.paper)
        .navigationTitle(route.drop?.experiment.title
                         ?? route.practiceMode?.displayName
                         ?? (route.course == nil
                             ? route.kind.displayName
                             : "\(route.kind.displayName) · Unit \(route.unit + 1)"))
        .navigationBarTitleDisplayMode(.inline)
        .toolbar {
            ToolbarItem(placement: .topBarTrailing) {
                voiceRepliesToggle
            }
        }
        .academyDestinations()
        .task(id: app.requiresSignIn) {
            guard !app.requiresSignIn, viewModel == nil else { return }
            let enrollmentId = route.course
                .flatMap { app.userStore.enrollment(for: $0.id)?.id.uuidString }
                ?? UUID().uuidString
            // The professor's voice follows this session's persona — the
            // course's, or the one picked for a standalone session (§13.1).
            app.professorVoice.persona = route.resolvedPersonaId.flatMap { app.persona($0) }
            let userStore = app.userStore
            let vm = SessionViewModel(course: route.course, unit: route.unit,
                                      kind: route.kind,
                                      personaId: route.resolvedPersonaId,
                                      enrollmentId: enrollmentId,
                                      client: app.makeSessionClient(
                                        course: route.course, unit: route.unit,
                                        dropSpec: route.drop?.experiment,
                                        newsBrief: route.newsBrief,
                                        practiceMode: route.practiceMode,
                                        practiceExercise: route.practiceExercise),
                                      drop: route.drop,
                                      steelmanTarget: route.steelmanTarget,
                                      newsBrief: route.newsBrief,
                                      practiceMode: route.practiceMode,
                                      practiceExerciseId: route.practiceExercise?.id,
                                      voice: app.professorVoice,
                                      voiceEnabled: { userStore.voiceReplies })
            viewModel = vm
            await vm.start()
        }
        .onDisappear {
            // Leaving the room: silence the professor and close the mic.
            viewModel?.stopVoice()
            app.professorVoice.stopSpeaking()
            app.speechTranscriber.stop()
        }
    }

    /// "Voice replies" toggle: professor turns are spoken while they stream.
    private var voiceRepliesToggle: some View {
        Button {
            app.userStore.voiceReplies.toggle()
            if !app.userStore.voiceReplies {
                app.professorVoice.stopSpeaking()
            }
        } label: {
            Image(systemName: app.userStore.voiceReplies
                  ? "speaker.wave.2.fill" : "speaker.slash")
                .foregroundStyle(app.userStore.voiceReplies
                                 ? Theme.tint(for: route.resolvedPersonaId)
                                 : Theme.inkSecondary)
        }
        .accessibilityLabel(app.userStore.voiceReplies
                            ? "Turn off voice replies" : "Turn on voice replies")
    }
}

private struct SessionContent: View {
    @Environment(AppModel.self) private var app
    @Bindable var viewModel: SessionViewModel
    var inputFocused: FocusState<Bool>.Binding

    private var persona: Persona? { viewModel.personaId.flatMap { app.persona($0) } }
    private var tint: Color { Theme.tint(for: viewModel.personaId) }

    var body: some View {
        VStack(spacing: 0) {
            // Argument lab: the map is the blackboard — pinned, collapsible,
            // rendered deterministically from the spec (§12.7 / A11).
            if viewModel.kind == .argumentLab, let spec = viewModel.argumentSpec {
                ArgumentMapPanel(spec: spec, phase: viewModel.labState.phase, tint: tint)
            }

            // Argument clinic (§13.3): the user's own argument grows on the
            // blackboard as the professor's stateOps build it.
            if viewModel.kind == .argumentClinic, let spec = viewModel.clinicSpec {
                // Observation re-renders this on every mapVersion bump: the
                // spec is recomputed from clinicState each time it changes.
                ClinicMapPanel(spec: spec, cruxes: viewModel.clinicState.cruxes,
                               tint: tint)
            }

            ScrollViewReader { proxy in
                ScrollView {
                    LazyVStack(alignment: .leading, spacing: 16) {
                        sessionHeader

                        // Elenchus: where the definition stands (§12.7).
                        if viewModel.kind == .elenchus {
                            ElenchusPhaseStrip(state: viewModel.elenchusState, tint: tint)
                        }

                        // Clinic: intake → excavation → map → crux →
                        // handback (§13.3).
                        if viewModel.kind == .argumentClinic {
                            ClinicPhaseStrip(phase: viewModel.clinicState.phase, tint: tint)
                        }

                        // Steelman: brief → attempt → probe → verdict →
                        // debrief (§14.4/§14.5).
                        if viewModel.kind == .steelman {
                            SteelmanPhaseStrip(phase: viewModel.steelmanState.phase, tint: tint)
                        }

                        // News read: brief → lens A → lens B → the split →
                        // your position (§15.2/§15.5), lens names from the
                        // pair where they fit.
                        if viewModel.kind == .newsRead {
                            NewsPhaseStrip(phase: viewModel.newsPhase,
                                           pair: viewModel.newsBrief?.lensPair,
                                           tint: tint)
                        }

                        ForEach(viewModel.messages) { message in
                            MessageBubble(message: message, persona: persona, tint: tint,
                                          pump: pump(for: message))
                                .id(message.id)
                        }

                        // The aporia beat — a designed success state, not an
                        // error (§12.8): rendered once the outcome lands.
                        if viewModel.kind == .elenchus {
                            if viewModel.elenchusState.outcome == .aporia {
                                AporiaCard(tint: tint)
                            } else if viewModel.elenchusState.outcome == .robust {
                                RobustOutcomeCard(tint: tint)
                            }
                        }

                        // The steelman verdict beat (§14.5): the earned rung
                        // on the four-rank ladder, once the score lands.
                        if viewModel.kind == .steelman,
                           let level = viewModel.steelmanState.level {
                            SteelmanVerdictCard(level: level,
                                                justification: viewModel.steelmanJustification,
                                                tint: tint)
                        }

                        // Thought experiment: the current authored node as a
                        // card with tappable choices (§12.7 / A10); the
                        // terminal node stays visible under interrogation.
                        if viewModel.showsExperimentNode,
                           let spec = viewModel.experimentSpec,
                           let node = viewModel.currentExperimentNode,
                           !viewModel.isStreaming || node.isTerminal {
                            ExperimentNodeCard(spec: spec, node: node, tint: tint,
                                               isBusy: viewModel.isStreaming) { option in
                                Task { await viewModel.selectChoice(option) }
                            }
                        }

                        if let question = viewModel.checkInQuestion, !viewModel.endOfSession {
                            CheckInChip(question: question, tint: tint) {
                                inputFocused.wrappedValue = true
                            }
                        }

                        if let error = viewModel.errorMessage {
                            Label(error, systemImage: "exclamationmark.triangle")
                                .font(.footnote)
                                .foregroundStyle(.red)
                        }

                        if let notice = viewModel.budgetNotice {
                            budgetNoticeCard(notice)
                        }

                        if viewModel.endOfSession {
                            endBanner
                        }

                        // The CROWD (§14.3): reachable ONLY from a completed
                        // drop run — the aggregate exists after your answer,
                        // never before.
                        if viewModel.endOfSession, let drop = viewModel.drop {
                            crowdLink(drop)
                        }

                        // A completed re-encounter (§15.4): the side-by-side
                        // of both runs — growth or consistency, never graded.
                        if viewModel.endOfSession, let drop = viewModel.drop,
                           let prior = app.drops.priorResponse(for: drop),
                           let current = app.drops.completion,
                           current.dropId == drop.id {
                            compareLink(drop: drop, prior: prior, current: current)
                        }

                        // The sources footer (§15.2/§15.5): the story's URLs
                        // render client-side from the brief — the professor
                        // read only the brief; citations stay empty.
                        if viewModel.kind == .newsRead, let brief = viewModel.newsBrief {
                            NewsSourcesFooter(brief: brief, tint: tint)
                        }

                        Color.clear.frame(height: 1).id("bottom")
                    }
                    .padding()
                }
                .onChange(of: viewModel.messages.last?.text) {
                    withAnimation(.easeOut(duration: 0.15)) {
                        proxy.scrollTo("bottom", anchor: .bottom)
                    }
                }
            }

            if viewModel.canContinueLecture {
                continueButton
            }

            // The keyboard yields to choice buttons while a branch walk is
            // live; interrogation/debrief fall back to the chat surface.
            if !viewModel.endOfSession && !viewModel.usesChoiceInput {
                if app.speechTranscriber.isRecording {
                    recordingIndicator
                }
                if let note = app.speechTranscriber.status.userMessage {
                    Text(note)
                        .font(.caption)
                        .fontDesign(.default)
                        .foregroundStyle(Theme.inkSecondary)
                        .padding(.horizontal)
                        .padding(.top, 6)
                }
                inputBar
            }
        }
        .onChange(of: app.speechTranscriber.transcript) {
            // Live transcription fills the input field; the student edits
            // and sends — nothing auto-fires.
            if app.speechTranscriber.isRecording {
                viewModel.inputText = app.speechTranscriber.transcript
            }
        }
        .onChange(of: viewModel.endOfSession) { _, ended in
            // A completed drop run mirrors the server's drop_responses row
            // locally (§14.3) — the record the CROWD gate hangs on.
            if ended, let drop = viewModel.drop {
                app.drops.recordCompletion(drop: drop,
                                           path: viewModel.experimentState.path)
            }
            // A completed practice session mirrors the server's
            // practice_entries row locally (§15.3): the student's words for
            // the day, in the journal.
            if ended, viewModel.kind == .practice,
               let mode = viewModel.practiceMode {
                let words = viewModel.messages
                    .filter { $0.role == .user }
                    .map(\.text)
                    .joined(separator: " — ")
                app.practice.recordEntry(mode: mode,
                                         exerciseId: viewModel.practiceExerciseId,
                                         entry: words)
            }
        }
    }

    /// "Then & now" — the §15.4 side-by-side, offered once the repeat run
    /// is complete.
    private func compareLink(drop: Drop, prior: DropStore.CompletionRecord,
                             current: DropStore.CompletionRecord) -> some View {
        NavigationLink {
            DropCompareView(drop: drop, prior: prior, current: current)
        } label: {
            HStack(spacing: 8) {
                Image(systemName: "arrow.left.arrow.right")
                    .font(.footnote)
                Text("You've been here before — compare your two runs")
                    .font(.footnote.weight(.medium))
                    .fontDesign(.serif)
                Spacer()
                Image(systemName: "chevron.right")
                    .font(.caption2.weight(.semibold))
            }
            .foregroundStyle(tint)
            .padding(.horizontal, 12)
            .padding(.vertical, 9)
            .background(RoundedRectangle(cornerRadius: 10, style: .continuous)
                .fill(tint.opacity(0.08)))
        }
        .buttonStyle(.plain)
    }

    /// "See where the crowd landed" — the only door to the CROWD screen.
    private func crowdLink(_ drop: Drop) -> some View {
        NavigationLink {
            DropCrowdView(drop: drop)
        } label: {
            HStack(spacing: 8) {
                Image(systemName: "person.3")
                    .font(.footnote)
                Text("See where the crowd landed")
                    .font(.footnote.weight(.medium))
                    .fontDesign(.serif)
                Spacer()
                Image(systemName: "chevron.right")
                    .font(.caption2.weight(.semibold))
            }
            .foregroundStyle(tint)
            .padding(.horizontal, 12)
            .padding(.vertical, 9)
            .background(RoundedRectangle(cornerRadius: 10, style: .continuous)
                .fill(tint.opacity(0.08)))
        }
        .buttonStyle(.plain)
    }

    /// Resolve an applied pump's authored variation for its turn (§12.7).
    private func pump(for message: TurnMessage) -> ThoughtExperimentSpec.Pump? {
        guard let pumpId = message.pumpId else { return nil }
        return viewModel.experimentSpec?.pump(pumpId)
    }

    private var recordingIndicator: some View {
        HStack(spacing: 8) {
            Circle()
                .fill(tint)
                .frame(width: 7, height: 7)
                .phaseAnimator([0.3, 1.0]) { dot, phase in
                    dot.opacity(phase)
                } animation: { _ in .easeInOut(duration: 0.7) }
            Text("Listening — tap the mic to stop, then edit or send.")
                .font(.caption)
                .fontDesign(.serif)
                .italic()
                .foregroundStyle(Theme.inkSecondary)
            Spacer()
        }
        .padding(.horizontal)
        .padding(.top, 6)
    }

    private var sessionHeader: some View {
        VStack(alignment: .leading, spacing: 4) {
            HStack(spacing: 10) {
                MonogramPortrait(persona: persona, size: 40)
                VStack(alignment: .leading, spacing: 2) {
                    Text(persona?.name ?? "Professor")
                        .font(.subheadline.weight(.semibold))
                        .fontDesign(.serif)
                        .foregroundStyle(Theme.ink)
                    if let unit = viewModel.currentUnit {
                        Text("Unit \(unit.number): \(unit.title)")
                            .font(.caption)
                            .fontDesign(.serif)
                            .italic()
                            .foregroundStyle(Theme.inkSecondary)
                    }
                }
                Spacer()
            }
            Rectangle().fill(Theme.rule).frame(height: 1).padding(.top, 8)
        }
    }

    /// §4.3 budget limit: a gentle, in-voice note — never an alert.
    private func budgetNoticeCard(_ notice: String) -> some View {
        VStack(alignment: .leading, spacing: 6) {
            Label("Class is out for today", systemImage: "hourglass")
                .font(.subheadline.weight(.semibold))
                .fontDesign(.serif)
                .foregroundStyle(tint)
            Text(notice)
                .font(.footnote)
                .fontDesign(.serif)
                .italic()
                .lineSpacing(3)
                .foregroundStyle(Theme.inkSecondary)
                .fixedSize(horizontal: false, vertical: true)
        }
        .frame(maxWidth: .infinity, alignment: .leading)
        .padding(14)
        .background(RoundedRectangle(cornerRadius: 10).fill(Theme.highlightWash))
    }

    private var endBanner: some View {
        VStack(alignment: .leading, spacing: 4) {
            Label("Session complete", systemImage: "checkmark.seal")
                .font(.subheadline.weight(.semibold))
                .fontDesign(.serif)
                .foregroundStyle(tint)
            Text("Notes from today are kept; your professor will remember.")
                .font(.caption)
                .fontDesign(.serif)
                .italic()
                .foregroundStyle(Theme.inkSecondary)
        }
        .frame(maxWidth: .infinity, alignment: .leading)
        .padding(14)
        .background(RoundedRectangle(cornerRadius: 10).fill(tint.opacity(0.08)))
    }

    private var continueButton: some View {
        Button {
            Task { await viewModel.continueLecture() }
        } label: {
            Label("Continue lecture", systemImage: "arrow.down.to.line")
                .font(.subheadline.weight(.semibold))
                .fontDesign(.serif)
                .frame(maxWidth: .infinity)
                .padding(.vertical, 4)
        }
        .buttonStyle(.borderedProminent)
        .tint(tint)
        .padding(.horizontal)
        .padding(.bottom, 8)
    }

    private var inputBar: some View {
        HStack(spacing: 10) {
            micButton

            TextField(placeholder, text: $viewModel.inputText, axis: .vertical)
                .lineLimit(1...4)
                .font(.body)
                .fontDesign(.serif)
                .focused(inputFocused)
                .padding(.horizontal, 14)
                .padding(.vertical, 9)
                .background(Capsule().fill(Theme.card))
                .overlay(Capsule().strokeBorder(Theme.rule, lineWidth: 1))

            Button {
                app.speechTranscriber.stop()
                Task { await viewModel.sendUserText() }
            } label: {
                Image(systemName: "arrow.up.circle.fill")
                    .font(.title)
                    .foregroundStyle(viewModel.canSend ? tint : Theme.rule)
            }
            .disabled(!viewModel.canSend)
        }
        .padding(.horizontal)
        .padding(.vertical, 10)
        .background(Theme.paper)
    }

    /// Tap to speak: live transcript fills the field; tap again to stop.
    /// The student stays in control — send never auto-fires.
    private var micButton: some View {
        Button {
            if app.speechTranscriber.isRecording {
                app.speechTranscriber.stop()
            } else {
                Task { await app.speechTranscriber.start() }
            }
        } label: {
            Image(systemName: app.speechTranscriber.isRecording ? "mic.fill" : "mic")
                .font(.title3)
                .foregroundStyle(app.speechTranscriber.isRecording ? Theme.card : tint)
                .frame(width: 36, height: 36)
                .background(
                    Circle().fill(app.speechTranscriber.isRecording ? tint : tint.opacity(0.10))
                )
                .overlay(Circle().strokeBorder(tint.opacity(0.35), lineWidth: 1))
        }
        .disabled(viewModel.endOfSession)
        .accessibilityLabel(app.speechTranscriber.isRecording
                            ? "Stop listening" : "Speak to your professor")
    }

    private var placeholder: String {
        switch viewModel.kind {
        case .seminar, .closeReading: return "Your reading…"
        case .lecture: return "Answer, or ask…"
        case .officeHours: return "Ask your professor…"
        case .elenchus: return "Defend it…"
        case .thoughtExperiment: return "Say why…"
        case .argumentLab: return "Name the premise…"
        case .argumentClinic: return "Your argument, as you'd say it…"
        case .steelman: return "Their best case, in your words…"
        case .newsRead: return "Reason it through…"
        case .practice:
            return viewModel.practiceMode == .evening
                ? "About the day, plainly…" : "Stay in the exercise…"
        case .practiceReview: return "What you make of it…"
        default: return "Respond…"
        }
    }
}

// MARK: - Bubbles

private struct MessageBubble: View {
    let message: TurnMessage
    let persona: Persona?
    let tint: Color
    var pump: ThoughtExperimentSpec.Pump?

    var body: some View {
        switch message.role {
        case .professor: professorBubble
        case .user: userBubble
        }
    }

    /// Professor prose is plain serif text — never quote-styled (§9). The
    /// verbatim quotes live in QuotePanels below the prose.
    private var professorBubble: some View {
        VStack(alignment: .leading, spacing: 10) {
            HStack(spacing: 6) {
                Text(persona?.name ?? "Professor").overline(tint)
                if message.isStreaming {
                    Image(systemName: "ellipsis")
                        .font(.caption2)
                        .foregroundStyle(tint)
                        .symbolEffect(.variableColor.iterative, options: .repeating)
                }
            }
            Text(attributed(message.text))
                .font(.body)
                .fontDesign(.serif)
                .lineSpacing(4)
                .foregroundStyle(Theme.ink)
                .fixedSize(horizontal: false, vertical: true)

            ForEach(message.citations) { citation in
                QuotePanel(citation: citation, tint: tint)
            }

            // "The dial turns": the authored variation the professor's
            // applyPump op invoked on this turn (§12.7).
            if let pump {
                PumpCard(pump: pump, tint: tint)
            }
        }
        .frame(maxWidth: .infinity, alignment: .leading)
        .bulletinCard(tint: tint)
    }

    private var userBubble: some View {
        Text(message.text)
            .font(.body)
            .fontDesign(.serif)
            .foregroundStyle(Theme.ink)
            .padding(.horizontal, 14)
            .padding(.vertical, 10)
            .background(RoundedRectangle(cornerRadius: 12, style: .continuous)
                .fill(Theme.highlightWash))
            .frame(maxWidth: .infinity, alignment: .trailing)
            .padding(.leading, 48)
    }

    private func attributed(_ text: String) -> AttributedString {
        (try? AttributedString(
            markdown: text,
            options: .init(interpretedSyntax: .inlineOnlyPreservingWhitespace)))
            ?? AttributedString(text)
    }
}

// MARK: - Check-in chip

private struct CheckInChip: View {
    let question: String
    let tint: Color
    let action: () -> Void

    var body: some View {
        Button(action: action) {
            HStack(alignment: .firstTextBaseline, spacing: 8) {
                Image(systemName: "questionmark.bubble")
                    .font(.footnote)
                Text(question)
                    .font(.footnote.weight(.medium))
                    .fontDesign(.serif)
                    .italic()
                    .multilineTextAlignment(.leading)
            }
            .padding(.horizontal, 14)
            .padding(.vertical, 9)
            .background(Capsule().fill(tint.opacity(0.12)))
            .overlay(Capsule().strokeBorder(tint.opacity(0.4), lineWidth: 1))
            .foregroundStyle(tint)
        }
        .buttonStyle(.plain)
    }
}
