import Foundation
import Observation

/// The weekly drop (§14.3): this week's thought experiment from the bundled
/// bank, the completed-this-week state, and the mock crowd aggregate. The
/// completion records persist locally keyed by (dropId, week); in live mode
/// the `drop_responses` unique constraint is the real gate and this remains
/// the optimistic cache — exactly the DailyQuestionStore pattern.
///
/// §15.4 re-encounters: the same (dropId, week) keying means a PRIOR-week
/// record for this week's drop is a re-encounter — the store keeps the full
/// history so the badge and the side-by-side compare can read both runs.
@Observable
@MainActor
final class DropStore {

    /// One completed run: (dropId, week) plus what the compare view needs —
    /// the date, the first choice, and the whole path (§15.4).
    struct CompletionRecord: Codable {
        let dropId: String
        let week: Int
        let firstChoice: String
        let localDate: String
        let path: [ThoughtExperimentChoice]

        init(dropId: String, week: Int, firstChoice: String,
             localDate: String, path: [ThoughtExperimentChoice]) {
            self.dropId = dropId
            self.week = week
            self.firstChoice = firstChoice
            self.localDate = localDate
            self.path = path
        }

        private enum CodingKeys: String, CodingKey {
            case dropId, week, firstChoice, localDate, path
        }

        /// Pre-§15.4 records carried only (dropId, week, firstChoice).
        init(from decoder: Decoder) throws {
            let c = try decoder.container(keyedBy: CodingKeys.self)
            dropId = try c.decode(String.self, forKey: .dropId)
            week = try c.decode(Int.self, forKey: .week)
            firstChoice = try c.decode(String.self, forKey: .firstChoice)
            localDate = try c.decodeIfPresent(String.self, forKey: .localDate) ?? ""
            path = try c.decodeIfPresent([ThoughtExperimentChoice].self, forKey: .path) ?? []
        }
    }

    private(set) var drops: [Drop] = []
    /// Every recorded run, newest week first — the local `drop_responses`.
    private(set) var history: [CompletionRecord] = []
    /// Mock of the `drop_aggregate` RPC payloads, keyed by drop id.
    private var aggregates: [String: DropAggregate] = [:]

    private let defaults = UserDefaults.standard
    private static let legacyCompletionKey = "weeklyDropCompletion"
    private static let historyKey = "dropResponseHistory"

    func load(bank: [Drop]) {
        drops = bank.sorted { $0.id < $1.id }
        loadAggregateFixture()
        reloadCompletionState()
    }

    /// Deterministic §14.3 rotation over the sorted bank.
    var thisWeekDrop: Drop? {
        Drop.thisWeek(in: drops)
    }

    /// This week's completed run, kept so the CROWD screen is reachable
    /// ONLY from a completed run (§14.3/§14.6: aggregates after answering).
    /// Last cycle's run is not this cycle's.
    var completion: CompletionRecord? {
        history.first { $0.week == Drop.weeksSinceEpoch() }
    }

    func reloadCompletionState() {
        var records: [CompletionRecord] = []
        if let data = defaults.data(forKey: Self.historyKey),
           let decoded = try? JSONDecoder().decode([CompletionRecord].self, from: data) {
            records = decoded
        }
        // Migrate the pre-§15.4 single-record key into the history once.
        if let data = defaults.data(forKey: Self.legacyCompletionKey),
           let legacy = try? JSONDecoder().decode(CompletionRecord.self, from: data) {
            if !records.contains(where: { $0.dropId == legacy.dropId && $0.week == legacy.week }) {
                records.append(legacy)
            }
            defaults.removeObject(forKey: Self.legacyCompletionKey)
        }
        history = records.sorted { $0.week > $1.week }
        saveHistory()
    }

    func isCompleted(_ drop: Drop) -> Bool {
        completion?.dropId == drop.id
    }

    /// §15.4: the most recent PRIOR-cycle run of this drop — the badge and
    /// the compare view hang on this (the current week's run never counts).
    func priorResponse(for drop: Drop) -> CompletionRecord? {
        history
            .filter { $0.dropId == drop.id && $0.week < Drop.weeksSinceEpoch() }
            .max { $0.week < $1.week }
    }

    /// Called when the drop session completes: the server writes
    /// `drop_responses` from the kind state's path; this mirrors the row
    /// locally so the CROWD gate and the re-encounter compare work
    /// client-side too.
    func recordCompletion(drop: Drop, path: [ThoughtExperimentChoice]) {
        guard !isCompleted(drop) else { return }
        let record = CompletionRecord(
            dropId: drop.id, week: Drop.weeksSinceEpoch(),
            firstChoice: path.first?.choice ?? "",
            localDate: DailyQuestion.localDateString(),
            path: path)
        history.insert(record, at: 0)
        history.sort { $0.week > $1.week }
        saveHistory()
    }

    /// The crowd (§14.3): mock-mode stand-in for the `drop_aggregate` RPC.
    /// The UI enforces the RPC's hard gate — never shown before the user's
    /// own answer is recorded.
    func aggregate(for dropId: String) -> DropAggregate? {
        aggregates[dropId]
    }

    /// Dev affordance for `-demo-drop` / `-demo-reencounter`: a fresh run
    /// this week regardless of whether it was already completed. Prior
    /// cycles' records stay — they are the re-encounter.
    func resetForDemo() {
        history.removeAll { $0.week == Drop.weeksSinceEpoch() }
        saveHistory()
    }

    /// Dev affordance for `-demo-reencounter`: seed a plausible prior-cycle
    /// response for this drop (one full bank rotation ago) so the badge and
    /// the compare view have a first run to show.
    func seedPriorResponseForDemo(drop: Drop) {
        guard priorResponse(for: drop) == nil else { return }
        let cycle = max(drops.count, 1)
        let week = Drop.weeksSinceEpoch() - cycle
        guard week >= 0 else { return }
        // Walk the authored spec down its first doors for a plausible path.
        var path: [ThoughtExperimentChoice] = []
        var nodeId = drop.experiment.startNode?.id ?? "start"
        while let node = drop.experiment.node(nodeId),
              let option = node.options?.first, path.count < 6 {
            path.append(ThoughtExperimentChoice(nodeId: nodeId, choice: option.label))
            nodeId = option.next
        }
        let day = Date(timeIntervalSince1970: TimeInterval(week * 7 * 86_400))
        var utc = Calendar(identifier: .gregorian)
        utc.timeZone = TimeZone(identifier: "UTC") ?? .current
        let record = CompletionRecord(
            dropId: drop.id, week: week,
            firstChoice: path.first?.choice ?? "",
            localDate: DailyQuestion.localDateString(for: day, calendar: utc),
            path: path)
        history.append(record)
        history.sort { $0.week > $1.week }
        saveHistory()
    }

    private func saveHistory() {
        if let data = try? JSONEncoder().encode(history) {
            defaults.set(data, forKey: Self.historyKey)
        }
    }

    private func loadAggregateFixture() {
        guard
            let url = Bundle.main.resourceURL?
                .appendingPathComponent("Fixtures/drop-aggregates.json"),
            let data = try? Data(contentsOf: url),
            let decoded = try? JSONDecoder().decode([String: DropAggregate].self, from: data)
        else { return }
        aggregates = decoded
    }
}
