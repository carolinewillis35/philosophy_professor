import Foundation
import Observation

/// The Practice Wing (§15.3): the exercise bank with its rotations, the
/// morning two-beat flow (prompt → intention → single Bede reply), and the
/// local journal — the mock-mode mirror of `practice_entries`, kept exactly
/// the way DailyQuestionStore and DropStore keep theirs. Copy law (§15.3):
/// training, never therapy; no mood tracking, no scores; the streak, where
/// shown at all, is a quiet rolling ratio.
@Observable
@MainActor
final class PracticeStore {

    /// Today's completed morning exchange, kept for the calm answered card.
    struct MorningRecord: Codable {
        let localDate: String
        let promptId: String
        let prompt: String
        let intention: String
        let reply: String
    }

    private(set) var morning: [PracticeExercise] = []
    private(set) var examenQuestions: [String] = Examen.questions
    private(set) var visualizations: [PracticeExercise] = []
    private(set) var isLoaded = false

    /// Non-nil once today's intention is set (this local date).
    private(set) var morningRecord: MorningRecord?
    private(set) var isSubmittingMorning = false
    /// Bede's reply as it streams; reconciled to `envelope.say`.
    private(set) var streamingMorningReply = ""
    private(set) var morningError: String?

    /// The journal (§15.3/§15.5): newest first.
    private(set) var entries: [PracticeEntry] = []

    private let defaults = UserDefaults.standard
    private static let morningKey = "practiceMorningRecord"
    private static let entriesKey = "practiceJournalEntries"

    func load(bank: PracticeBank?) {
        guard let bank else { return }
        morning = bank.morning.sorted { $0.id < $1.id }
        examenQuestions = bank.examen.questions.count == 3
            ? bank.examen.questions : Examen.questions
        visualizations = bank.visualizations.sorted { $0.id < $1.id }
        isLoaded = true
        reloadMorningState()
        loadEntries()
    }

    // MARK: rotation (§15.3: A16 arithmetic, same as daily/drop)

    var todayMorningPrompt: PracticeExercise? {
        PracticeExercise.todayMorning(in: morning)
    }

    var thisWeekVisualization: PracticeExercise? {
        PracticeExercise.thisWeekVisualization(in: visualizations)
    }

    // MARK: answered-today / done-this-week states

    /// Yesterday's intention is not today's: the record only counts when its
    /// local date is the current one.
    func reloadMorningState() {
        guard
            let data = defaults.data(forKey: Self.morningKey),
            let record = try? JSONDecoder().decode(MorningRecord.self, from: data),
            record.localDate == DailyQuestion.localDateString()
        else {
            morningRecord = nil
            return
        }
        morningRecord = record
    }

    /// A journal entry for this mode on today's local date.
    func hasEntryToday(_ mode: PracticeMode) -> Bool {
        let today = DailyQuestion.localDateString()
        return entries.contains { $0.mode == mode && $0.localDate == today }
    }

    /// A visualization entry somewhere in the current calendar week.
    var hasVisualizationThisWeek: Bool {
        let week = Drop.weeksSinceEpoch()
        return entries.contains {
            $0.mode == .visualization && weeksSinceEpoch(of: $0.localDate) == week
        }
    }

    /// The quiet rolling ratio (§13.2 pattern, §15.3 copy law): days with at
    /// least one entry out of the last seven. Never a chain, never a guilt
    /// mechanic — nil when there is nothing to say.
    var rollingRatio: (practiced: Int, of: Int)? {
        let calendar = Calendar.current
        let last7 = (0..<7).compactMap {
            calendar.date(byAdding: .day, value: -$0, to: Date())
        }.map { DailyQuestion.localDateString(for: $0) }
        let practiced = last7.filter { day in
            entries.contains { $0.localDate == day }
        }.count
        return practiced > 0 ? (practiced, 7) : nil
    }

    // MARK: the morning flow (§15.3: two beats, calm)

    /// The two-beat morning: start presents the prompt (the card already
    /// shows it, so the presentation is not rendered), the turn carries the
    /// student's ONE intention, Bede replies once (≤80 words) and the
    /// session completes in that same turn — mirroring the DailyQuestionCard
    /// flow.
    func submitMorning(prompt: PracticeExercise, intention: String,
                       client: SessionClient) async {
        guard !isSubmittingMorning, morningRecord == nil else { return }
        let trimmed = intention.trimmingCharacters(in: .whitespacesAndNewlines)
        guard !trimmed.isEmpty else { return }
        isSubmittingMorning = true
        morningError = nil
        streamingMorningReply = ""

        let localDate = DailyQuestion.localDateString()
        var sessionId: String?

        // Beat one: the start presents today's prompt.
        for await event in client.send(.startPractice(
            mode: .morning, exerciseId: prompt.id, localDate: localDate)) {
            switch event {
            case .session(let id, _, _):
                sessionId = id
            case .error(_, let message):
                morningError = message
            case .sayDelta, .envelope, .done:
                break
            }
        }
        guard morningError == nil else {
            isSubmittingMorning = false
            return
        }

        // Beat two: the intention goes in; the single reply comes back.
        var reply = ""
        for await event in client.send(.turn(
            sessionId: sessionId ?? "", kind: .practice, userText: trimmed)) {
            switch event {
            case .sayDelta(let delta):
                streamingMorningReply += delta
            case .envelope(let envelope):
                reply = envelope.say
                streamingMorningReply = envelope.say
            case .error(_, let message):
                morningError = message
            case .session, .done:
                break
            }
        }

        if !reply.isEmpty {
            let record = MorningRecord(
                localDate: localDate, promptId: prompt.id,
                prompt: prompt.prompt ?? "", intention: trimmed, reply: reply)
            morningRecord = record
            if let data = try? JSONEncoder().encode(record) {
                defaults.set(data, forKey: Self.morningKey)
            }
            recordEntry(mode: .morning, exerciseId: prompt.id,
                        entry: trimmed, reply: reply)
        }
        isSubmittingMorning = false
    }

    // MARK: the journal (local mirror of `practice_entries`)

    /// One entry per (mode, local date) — the table's unique constraint,
    /// enforced optimistically here.
    func recordEntry(mode: PracticeMode, exerciseId: String?,
                     entry: String, reply: String = "",
                     localDate: String = DailyQuestion.localDateString()) {
        let trimmed = entry.trimmingCharacters(in: .whitespacesAndNewlines)
        guard !trimmed.isEmpty else { return }
        guard !entries.contains(where: { $0.mode == mode && $0.localDate == localDate })
        else { return }
        entries.insert(PracticeEntry(localDate: localDate, mode: mode,
                                     exerciseId: exerciseId,
                                     entry: trimmed, reply: reply), at: 0)
        entries.sort { $0.localDate > $1.localDate }
        saveEntries()
    }

    /// Dev affordance for `-demo-practice`: a fresh morning regardless of
    /// whether today's intention was already set.
    func resetForDemo() {
        defaults.removeObject(forKey: Self.morningKey)
        morningRecord = nil
        streamingMorningReply = ""
        morningError = nil
        let today = DailyQuestion.localDateString()
        entries.removeAll { $0.mode == .morning && $0.localDate == today }
        saveEntries()
    }

    private func loadEntries() {
        guard
            let data = defaults.data(forKey: Self.entriesKey),
            let decoded = try? JSONDecoder().decode([PracticeEntry].self, from: data)
        else { return }
        entries = decoded.sorted { $0.localDate > $1.localDate }
    }

    private func saveEntries() {
        if let data = try? JSONEncoder().encode(entries) {
            defaults.set(data, forKey: Self.entriesKey)
        }
    }

    private func weeksSinceEpoch(of localDate: String) -> Int? {
        let parts = localDate.split(separator: "-").compactMap { Int($0) }
        guard parts.count == 3 else { return nil }
        var components = DateComponents()
        components.year = parts[0]; components.month = parts[1]; components.day = parts[2]
        guard let date = Calendar.current.date(from: components) else { return nil }
        return Drop.weeksSinceEpoch(for: date)
    }
}
