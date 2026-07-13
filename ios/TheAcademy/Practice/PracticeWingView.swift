import SwiftUI

/// The Practice Wing (§15.3/§15.5) — Prof. Bede's rooms: the morning
/// intention card, the evening examen, the weekly visualization, the weekly
/// review, and the journal. Calm register throughout; the streak, where it
/// appears at all, is a quiet rolling ratio — never a chain, never a guilt
/// mechanic. Training, not therapy.
struct PracticeWingView: View {
    @Environment(AppModel.self) private var app

    private var store: PracticeStore { app.practice }
    private var tint: Color { Theme.tint(for: "bede") }
    private var persona: Persona? { app.persona("bede") }

    var body: some View {
        ScrollView {
            VStack(alignment: .leading, spacing: 20) {
                header

                if store.isLoaded {
                    MorningIntentionCard()
                    eveningCard
                    visualizationCard
                    weeklyReviewCard
                    journalSection
                } else {
                    ContentUnavailableView("The wing is closed",
                                           systemImage: "figure.mind.and.body",
                                           description: Text("The exercise bank isn't bundled."))
                }
            }
            .padding(.horizontal)
            .padding(.bottom, 24)
        }
        .background(Theme.paper)
        .navigationTitle("The Practice Wing")
        .navigationBarTitleDisplayMode(.inline)
        .academyDestinations()
    }

    private var header: some View {
        VStack(alignment: .leading, spacing: 4) {
            HStack(spacing: 8) {
                Text("Philosophy as a way of life").overline(tint)
                Spacer()
                if let persona {
                    Text(persona.name)
                        .font(.caption)
                        .fontDesign(.serif)
                        .italic()
                        .foregroundStyle(Theme.inkSecondary)
                    MonogramPortrait(persona: persona, size: 26)
                }
            }
            Text("One intention at dawn, three questions at dusk, one rehearsal a week. Training, not therapy — the day is the gymnasium.")
                .font(.footnote)
                .fontDesign(.serif)
                .italic()
                .lineSpacing(3)
                .foregroundStyle(Theme.inkSecondary)
                .fixedSize(horizontal: false, vertical: true)
            // The quiet rolling ratio (§15.3): a fact about the week, not a
            // chain to protect. Absent entirely until there is practice.
            if let ratio = store.rollingRatio {
                Text("Practiced \(ratio.practiced) of the last \(ratio.of) days.")
                    .font(.caption)
                    .fontDesign(.default)
                    .foregroundStyle(Theme.inkSecondary)
                    .padding(.top, 2)
            }
            Rectangle().fill(Theme.rule).frame(height: 1).padding(.top, 6)
        }
        .padding(.top, 4)
    }

    // MARK: evening examen (dusk-context; the session asks the 3 questions)

    private var eveningCard: some View {
        VStack(alignment: .leading, spacing: 12) {
            HStack(spacing: 8) {
                Text("The Evening Examen").overline(tint)
                Spacer()
                Image(systemName: PracticeMode.evening.symbolName)
                    .font(.footnote)
                    .foregroundStyle(tint)
            }
            Text("Three fixed questions about the day")
                .font(.title3.weight(.semibold))
                .fontDesign(.serif)
                .foregroundStyle(Theme.ink)

            VStack(alignment: .leading, spacing: 4) {
                ForEach(store.examenQuestions, id: \.self) { question in
                    Text("· \(question)")
                        .font(.footnote)
                        .fontDesign(.serif)
                        .italic()
                        .foregroundStyle(Theme.inkSecondary)
                }
            }

            Rectangle().fill(Theme.rule).frame(height: 1)

            if store.hasEntryToday(.evening) {
                doneLine("Tonight's page is written.")
            } else {
                NavigationLink(value: SessionRoute(practice: .evening)) {
                    Label("Sit the examen",
                          systemImage: PracticeMode.evening.symbolName)
                        .font(.subheadline.weight(.semibold))
                        .fontDesign(.serif)
                        .frame(maxWidth: .infinity)
                        .padding(.vertical, 4)
                }
                .buttonStyle(.borderedProminent)
                .tint(tint)
            }
        }
        .bulletinCard(tint: tint)
    }

    // MARK: weekly visualization (this week's authored rehearsal)

    @ViewBuilder
    private var visualizationCard: some View {
        if let exercise = store.thisWeekVisualization {
            VStack(alignment: .leading, spacing: 12) {
                HStack(spacing: 8) {
                    Text("This Week's Rehearsal").overline(tint)
                    Spacer()
                    Image(systemName: PracticeMode.visualization.symbolName)
                        .font(.footnote)
                        .foregroundStyle(tint)
                }
                Text(exercise.title ?? "A rehearsal of loss")
                    .font(.title3.weight(.semibold))
                    .fontDesign(.serif)
                    .foregroundStyle(Theme.ink)
                Text("The loss is rehearsed so the having is felt — a few minutes, guided, then set down.")
                    .font(.footnote)
                    .fontDesign(.serif)
                    .italic()
                    .lineSpacing(3)
                    .foregroundStyle(Theme.inkSecondary)
                    .fixedSize(horizontal: false, vertical: true)

                Rectangle().fill(Theme.rule).frame(height: 1)

                if store.hasVisualizationThisWeek {
                    doneLine("This week's rep is done.")
                } else {
                    NavigationLink(value: SessionRoute(practice: .visualization,
                                                       exercise: exercise)) {
                        Label("Walk the exercise",
                              systemImage: PracticeMode.visualization.symbolName)
                            .font(.subheadline.weight(.semibold))
                            .fontDesign(.serif)
                            .frame(maxWidth: .infinity)
                            .padding(.vertical, 4)
                    }
                    .buttonStyle(.borderedProminent)
                    .tint(tint)
                }
            }
            .bulletinCard(tint: tint)
        }
    }

    // MARK: weekly review (practiceReview with Bede)

    private var weeklyReviewCard: some View {
        VStack(alignment: .leading, spacing: 12) {
            HStack(spacing: 8) {
                Text("The Weekly Review").overline(tint)
                Spacer()
                Image(systemName: SessionKind.practiceReview.symbolName)
                    .font(.footnote)
                    .foregroundStyle(tint)
            }
            Text("Sit with the week's page")
                .font(.title3.weight(.semibold))
                .fontDesign(.serif)
                .foregroundStyle(Theme.ink)
            Text("Bede reads the last seven days of entries and names the patterns he actually sees — then you name one adjustment for next week. Yours, not assigned.")
                .font(.footnote)
                .fontDesign(.serif)
                .italic()
                .lineSpacing(3)
                .foregroundStyle(Theme.inkSecondary)
                .fixedSize(horizontal: false, vertical: true)

            Rectangle().fill(Theme.rule).frame(height: 1)

            NavigationLink(value: SessionRoute(standalone: .practiceReview,
                                               personaId: "bede")) {
                Label("Open the review",
                      systemImage: SessionKind.practiceReview.symbolName)
                    .font(.subheadline.weight(.semibold))
                    .fontDesign(.serif)
                    .frame(maxWidth: .infinity)
                    .padding(.vertical, 4)
            }
            .buttonStyle(.borderedProminent)
            .tint(tint)
        }
        .bulletinCard(tint: tint)
    }

    // MARK: the journal (§15.3: date, mode, entry — a record, never a score)

    private var journalSection: some View {
        VStack(alignment: .leading, spacing: 12) {
            SectionHeading(text: "The Journal")
                .padding(.top, 8)
            if store.entries.isEmpty {
                Text("The page is blank — it fills as you practice, one line a day.")
                    .font(.footnote)
                    .fontDesign(.serif)
                    .italic()
                    .foregroundStyle(Theme.inkSecondary)
            } else {
                ForEach(store.entries) { entry in
                    journalRow(entry)
                }
            }
        }
    }

    private func journalRow(_ entry: PracticeEntry) -> some View {
        VStack(alignment: .leading, spacing: 6) {
            HStack(spacing: 8) {
                Image(systemName: entry.mode.symbolName)
                    .font(.caption)
                    .foregroundStyle(tint)
                Text(entry.mode.displayName).overline(tint)
                Spacer()
                Text(DropCompareView.displayDate(entry.localDate))
                    .font(.caption2)
                    .fontDesign(.default)
                    .foregroundStyle(Theme.inkSecondary)
            }
            Text(entry.entry)
                .font(.footnote)
                .fontDesign(.serif)
                .lineSpacing(3)
                .foregroundStyle(Theme.ink)
                .fixedSize(horizontal: false, vertical: true)
        }
        .frame(maxWidth: .infinity, alignment: .leading)
        .bulletinCard()
    }

    private func doneLine(_ text: String) -> some View {
        HStack(spacing: 8) {
            Image(systemName: "checkmark.seal")
                .font(.footnote)
                .foregroundStyle(tint)
            Text(text)
                .font(.footnote.weight(.medium))
                .fontDesign(.serif)
                .foregroundStyle(Theme.ink)
            Spacer(minLength: 0)
        }
    }
}

// MARK: - Morning intention card (§15.3: two beats, mirroring the daily card)

/// Today's rotating prompt (daysSinceEpoch % bank, the daily arithmetic),
/// one intention in a sentence, a single ≤80-word reply from Bede, then a
/// calm done state. No streak talk, no pressure — the rep is the ritual.
struct MorningIntentionCard: View {
    @Environment(AppModel.self) private var app

    @State private var intention = ""

    private var store: PracticeStore { app.practice }
    private var tint: Color { Theme.tint(for: "bede") }
    private var persona: Persona? { app.persona("bede") }

    var body: some View {
        if let prompt = store.todayMorningPrompt {
            VStack(alignment: .leading, spacing: 12) {
                HStack(spacing: 8) {
                    Text("The Morning Intention").overline(tint)
                    Spacer()
                    Image(systemName: PracticeMode.morning.symbolName)
                        .font(.footnote)
                        .foregroundStyle(tint)
                }

                Text(store.morningRecord?.prompt.isEmpty == false
                     ? store.morningRecord!.prompt
                     : prompt.prompt ?? "")
                    .font(.title3.weight(.semibold))
                    .fontDesign(.serif)
                    .lineSpacing(3)
                    .foregroundStyle(Theme.ink)
                    .fixedSize(horizontal: false, vertical: true)

                if let record = store.morningRecord {
                    answeredBody(record)
                } else if store.isSubmittingMorning {
                    submittingBody
                } else {
                    promptBody(prompt)
                }
            }
            .bulletinCard(tint: tint)
        }
    }

    // MARK: unset — one sentence, submit

    @ViewBuilder
    private func promptBody(_ prompt: PracticeExercise) -> some View {
        TextField("Your intention, in a sentence", text: $intention, axis: .vertical)
            .lineLimit(1...3)
            .font(.footnote)
            .fontDesign(.serif)
            .padding(.horizontal, 12)
            .padding(.vertical, 8)
            .background(RoundedRectangle(cornerRadius: 10, style: .continuous)
                .fill(Theme.paper))
            .overlay(RoundedRectangle(cornerRadius: 10, style: .continuous)
                .strokeBorder(Theme.rule, lineWidth: 1))

        if let error = store.morningError {
            Label(error, systemImage: "exclamationmark.triangle")
                .font(.caption)
                .foregroundStyle(.red)
        }

        Button {
            let text = intention
            Task {
                await store.submitMorning(
                    prompt: prompt, intention: text,
                    client: app.makeSessionClient(practiceMode: .morning,
                                                  practiceExercise: prompt))
            }
        } label: {
            Text("Set it")
                .font(.subheadline.weight(.semibold))
                .fontDesign(.serif)
                .frame(maxWidth: .infinity)
                .padding(.vertical, 4)
        }
        .buttonStyle(.borderedProminent)
        .tint(tint)
        .disabled(intention.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty)
    }

    // MARK: submitting — the single reply streams in

    @ViewBuilder
    private var submittingBody: some View {
        VStack(alignment: .leading, spacing: 10) {
            HStack(spacing: 6) {
                Text(persona?.name ?? "Professor").overline(tint)
                Image(systemName: "ellipsis")
                    .font(.caption2)
                    .foregroundStyle(tint)
                    .symbolEffect(.variableColor.iterative, options: .repeating)
            }
            if !store.streamingMorningReply.isEmpty {
                replyText(store.streamingMorningReply)
            }
        }
    }

    // MARK: set — calm, complete, the day begins

    @ViewBuilder
    private func answeredBody(_ record: PracticeStore.MorningRecord) -> some View {
        VStack(alignment: .leading, spacing: 4) {
            Text("Your intention").overline()
            Text("“\(record.intention)”")
                .font(.subheadline.weight(.medium))
                .fontDesign(.serif)
                .italic()
                .foregroundStyle(Theme.ink)
                .fixedSize(horizontal: false, vertical: true)
        }

        Rectangle().fill(Theme.rule).frame(height: 1)

        VStack(alignment: .leading, spacing: 8) {
            Text(persona?.name ?? "Professor").overline(tint)
            replyText(record.reply)
        }
    }

    private func replyText(_ text: String) -> some View {
        Text(text)
            .font(.subheadline)
            .fontDesign(.serif)
            .lineSpacing(3)
            .foregroundStyle(Theme.ink)
            .fixedSize(horizontal: false, vertical: true)
    }
}

// MARK: - Home-surface door (§15.5: Bede's wing on the bulletin)

/// The wing's card on the home surface: what the practice is, whether
/// today's reps are done, and the door in. Quiet — the copy never chases.
struct PracticeWingCard: View {
    @Environment(AppModel.self) private var app

    private var store: PracticeStore { app.practice }
    private var tint: Color { Theme.tint(for: "bede") }
    private var persona: Persona? { app.persona("bede") }

    var body: some View {
        if store.isLoaded {
            VStack(alignment: .leading, spacing: 12) {
                HStack(spacing: 8) {
                    Text("The Practice Wing").overline(tint)
                    Spacer()
                    if let persona {
                        Text(persona.name)
                            .font(.caption)
                            .fontDesign(.serif)
                            .italic()
                            .foregroundStyle(Theme.inkSecondary)
                        MonogramPortrait(persona: persona, size: 26)
                    }
                }

                Text("The gymnasium is open")
                    .font(.title3.weight(.semibold))
                    .fontDesign(.serif)
                    .foregroundStyle(Theme.ink)

                Text("One intention at dawn, three questions at dusk, one rehearsal a week. Training, not therapy.")
                    .font(.footnote)
                    .fontDesign(.serif)
                    .italic()
                    .lineSpacing(3)
                    .foregroundStyle(Theme.inkSecondary)
                    .fixedSize(horizontal: false, vertical: true)

                Rectangle().fill(Theme.rule).frame(height: 1)

                if store.morningRecord != nil {
                    HStack(spacing: 8) {
                        Image(systemName: "checkmark.seal")
                            .font(.footnote)
                            .foregroundStyle(tint)
                        Text("Today's intention is set.")
                            .font(.footnote.weight(.medium))
                            .fontDesign(.serif)
                            .foregroundStyle(Theme.ink)
                        Spacer(minLength: 0)
                    }
                }

                NavigationLink(value: PracticeRoute()) {
                    Label("Enter the wing",
                          systemImage: SessionKind.practice.symbolName)
                        .font(.subheadline.weight(.semibold))
                        .fontDesign(.serif)
                        .frame(maxWidth: .infinity)
                        .padding(.vertical, 4)
                }
                .buttonStyle(.borderedProminent)
                .tint(tint)
            }
            .bulletinCard(tint: tint)
        }
    }
}
