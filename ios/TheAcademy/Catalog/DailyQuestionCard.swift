import SwiftUI

/// The Daily Question card at the top of the home surface (§13.2 / §13.5):
/// today's question from the bundled bank, 2–4 option buttons, an optional
/// one-line "why", and — after the single professor reply — a calm answered
/// state with an "added to your worldview" affordance. No streaks, no
/// pressure: answering is the whole ritual.
struct DailyQuestionCard: View {
    @Environment(AppModel.self) private var app

    @State private var selectedOptionId: String?
    @State private var sentence = ""

    private var store: DailyQuestionStore { app.daily }

    /// The question on the card: today's answered one if a record exists
    /// (so the exchange stays readable), else today's from the rotation.
    private var question: DailyQuestion? {
        if let record = store.answered, let q = store.question(withId: record.questionId) {
            return q
        }
        return store.todayQuestion
    }

    private var tint: Color { Theme.tint(for: question?.personaId) }
    private var persona: Persona? { question.flatMap { app.persona($0.personaId) } }

    var body: some View {
        if let question {
            VStack(alignment: .leading, spacing: 12) {
                header(question)

                Text(question.question)
                    .font(.title3.weight(.semibold))
                    .fontDesign(.serif)
                    .lineSpacing(3)
                    .foregroundStyle(Theme.ink)
                    .fixedSize(horizontal: false, vertical: true)

                if let record = store.answered {
                    answeredBody(record)
                } else if store.isSubmitting {
                    submittingBody
                } else {
                    promptBody(question)
                }
            }
            .bulletinCard(tint: tint)
        }
    }

    private func header(_ question: DailyQuestion) -> some View {
        HStack(spacing: 8) {
            Text("The Daily Question").overline(tint)
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
    }

    // MARK: unanswered — tap, one optional sentence, submit

    @ViewBuilder
    private func promptBody(_ question: DailyQuestion) -> some View {
        VStack(alignment: .leading, spacing: 8) {
            ForEach(question.options) { option in
                optionButton(option)
            }
        }

        TextField("In one sentence, why? (optional)", text: $sentence, axis: .vertical)
            .lineLimit(1...3)
            .font(.footnote)
            .fontDesign(.serif)
            .padding(.horizontal, 12)
            .padding(.vertical, 8)
            .background(RoundedRectangle(cornerRadius: 10, style: .continuous)
                .fill(Theme.paper))
            .overlay(RoundedRectangle(cornerRadius: 10, style: .continuous)
                .strokeBorder(Theme.rule, lineWidth: 1))

        if let error = store.errorMessage {
            Label(error, systemImage: "exclamationmark.triangle")
                .font(.caption)
                .foregroundStyle(.red)
        }

        Button {
            guard let option = question.options.first(where: { $0.id == selectedOptionId })
            else { return }
            let why = sentence
            Task {
                await store.submit(question: question, option: option,
                                   sentence: why, client: app.makeSessionClient())
            }
        } label: {
            Text("Submit")
                .font(.subheadline.weight(.semibold))
                .fontDesign(.serif)
                .frame(maxWidth: .infinity)
                .padding(.vertical, 4)
        }
        .buttonStyle(.borderedProminent)
        .tint(tint)
        .disabled(selectedOptionId == nil)
    }

    private func optionButton(_ option: DailyQuestion.Option) -> some View {
        let isSelected = option.id == selectedOptionId
        return Button {
            selectedOptionId = option.id
        } label: {
            HStack(spacing: 8) {
                Image(systemName: isSelected ? "largecircle.fill.circle" : "circle")
                    .font(.footnote)
                    .foregroundStyle(isSelected ? tint : Theme.inkSecondary)
                Text(option.label)
                    .font(.subheadline)
                    .fontDesign(.serif)
                    .foregroundStyle(Theme.ink)
                    .multilineTextAlignment(.leading)
                    .fixedSize(horizontal: false, vertical: true)
                Spacer(minLength: 0)
            }
            .padding(.horizontal, 12)
            .padding(.vertical, 9)
            .background(RoundedRectangle(cornerRadius: 10, style: .continuous)
                .fill(isSelected ? tint.opacity(0.10) : Theme.paper))
            .overlay(RoundedRectangle(cornerRadius: 10, style: .continuous)
                .strokeBorder(isSelected ? tint.opacity(0.6) : Theme.rule,
                              lineWidth: isSelected ? 1.5 : 1))
        }
        .buttonStyle(.plain)
        .accessibilityAddTraits(isSelected ? .isSelected : [])
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
            if !store.streamingReply.isEmpty {
                replyText(store.streamingReply)
            }
        }
    }

    // MARK: answered — calm, complete, no pressure

    @ViewBuilder
    private func answeredBody(_ record: DailyQuestionStore.AnsweredRecord) -> some View {
        VStack(alignment: .leading, spacing: 4) {
            Text("You answered").overline()
            Text(record.optionLabel)
                .font(.subheadline.weight(.medium))
                .fontDesign(.serif)
                .foregroundStyle(Theme.ink)
                .fixedSize(horizontal: false, vertical: true)
            if !record.sentence.isEmpty {
                Text("“\(record.sentence)”")
                    .font(.footnote)
                    .fontDesign(.serif)
                    .italic()
                    .foregroundStyle(Theme.inkSecondary)
                    .fixedSize(horizontal: false, vertical: true)
            }
        }

        Rectangle().fill(Theme.rule).frame(height: 1)

        VStack(alignment: .leading, spacing: 8) {
            Text(persona?.name ?? "Professor").overline(tint)
            replyText(record.reply)
        }

        NavigationLink {
            WorldviewView()
        } label: {
            HStack(spacing: 8) {
                Image(systemName: "point.3.connected.trianglepath.dotted")
                    .font(.footnote)
                Text("Added to your worldview")
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

    private func replyText(_ text: String) -> some View {
        Text(text)
            .font(.subheadline)
            .fontDesign(.serif)
            .lineSpacing(3)
            .foregroundStyle(Theme.ink)
            .fixedSize(horizontal: false, vertical: true)
    }
}
