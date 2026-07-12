import Foundation
import Observation

/// The sixty-second ritual (§13.2): today's question from the bundled bank,
/// the one-round-trip submit (tap + optional sentence in, single professor
/// reply out), and the answered-today state. Answered state persists locally
/// keyed by local date; in live mode the `daily_answers` unique constraint is
/// the real gate and this remains the optimistic cache.
@Observable
@MainActor
final class DailyQuestionStore {

    /// Today's completed exchange, kept for the calm answered card.
    struct AnsweredRecord: Codable {
        let localDate: String
        let questionId: String
        let optionId: String
        let optionLabel: String
        let sentence: String
        let reply: String
        let personaId: String
    }

    private(set) var bank: [DailyQuestion] = []
    /// Non-nil once today's question has been answered (this local date).
    private(set) var answered: AnsweredRecord?
    private(set) var isSubmitting = false
    /// The professor's reply as it streams; reconciled to `envelope.say`.
    private(set) var streamingReply = ""
    private(set) var errorMessage: String?

    private let defaults = UserDefaults.standard
    private static let answerKey = "dailyQuestionAnswer"

    func load(bank: [DailyQuestion]) {
        self.bank = bank.sorted { $0.id < $1.id }
        reloadAnsweredState()
    }

    /// Deterministic §13.2 rotation over the sorted bank.
    var todayQuestion: DailyQuestion? {
        DailyQuestion.today(in: bank)
    }

    func question(withId id: String) -> DailyQuestion? {
        bank.first { $0.id == id }
    }

    /// Yesterday's answer is not today's: the record only counts when its
    /// local date is the current one.
    func reloadAnsweredState() {
        guard
            let data = defaults.data(forKey: Self.answerKey),
            let record = try? JSONDecoder().decode(AnsweredRecord.self, from: data),
            record.localDate == DailyQuestion.localDateString()
        else {
            answered = nil
            return
        }
        answered = record
    }

    /// One round trip (§13.2): the tap and sentence were collected FIRST;
    /// the start request carries them, the professor replies once, and the
    /// session completes in the same turn.
    func submit(question: DailyQuestion, option: DailyQuestion.Option,
                sentence: String, client: SessionClient) async {
        guard !isSubmitting, answered == nil else { return }
        isSubmitting = true
        errorMessage = nil
        streamingReply = ""

        let localDate = DailyQuestion.localDateString()
        let trimmed = sentence.trimmingCharacters(in: .whitespacesAndNewlines)
        var reply = ""

        for await event in client.send(.startDailyQuestion(
            questionId: question.id, optionId: option.id,
            localDate: localDate, sentence: trimmed.isEmpty ? nil : trimmed)) {
            switch event {
            case .sayDelta(let delta):
                streamingReply += delta
            case .envelope(let envelope):
                reply = envelope.say
                streamingReply = envelope.say
            case .error(_, let message):
                errorMessage = message
            case .session, .done:
                break
            }
        }

        if !reply.isEmpty {
            let record = AnsweredRecord(
                localDate: localDate, questionId: question.id,
                optionId: option.id, optionLabel: option.label,
                sentence: trimmed, reply: reply, personaId: question.personaId)
            answered = record
            if let data = try? JSONEncoder().encode(record) {
                defaults.set(data, forKey: Self.answerKey)
            }
        }
        isSubmitting = false
    }

    /// Dev affordance for `-demo-daily`: a fresh card regardless of whether
    /// today was already answered.
    func resetForDemo() {
        defaults.removeObject(forKey: Self.answerKey)
        answered = nil
        streamingReply = ""
        errorMessage = nil
    }
}
