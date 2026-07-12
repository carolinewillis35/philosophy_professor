import Foundation
import Observation

/// The weekly drop (§14.3): this week's thought experiment from the bundled
/// bank, the completed-this-week state, and the mock crowd aggregate. The
/// completion record persists locally keyed by (dropId, week); in live mode
/// the `drop_responses` unique constraint is the real gate and this remains
/// the optimistic cache — exactly the DailyQuestionStore pattern.
@Observable
@MainActor
final class DropStore {

    /// This week's completed run, kept so the CROWD screen is reachable
    /// ONLY from a completed run (§14.3/§14.6: aggregates after answering).
    struct CompletionRecord: Codable {
        let dropId: String
        let week: Int
        let firstChoice: String
    }

    private(set) var drops: [Drop] = []
    /// Non-nil once this week's drop has been run (this local week).
    private(set) var completion: CompletionRecord?
    /// Mock of the `drop_aggregate` RPC payloads, keyed by drop id.
    private var aggregates: [String: DropAggregate] = [:]

    private let defaults = UserDefaults.standard
    private static let completionKey = "weeklyDropCompletion"

    func load(bank: [Drop]) {
        drops = bank.sorted { $0.id < $1.id }
        loadAggregateFixture()
        reloadCompletionState()
    }

    /// Deterministic §14.3 rotation over the sorted bank.
    var thisWeekDrop: Drop? {
        Drop.thisWeek(in: drops)
    }

    /// Last cycle's run is not this cycle's: the record only counts when its
    /// week is the current one.
    func reloadCompletionState() {
        guard
            let data = defaults.data(forKey: Self.completionKey),
            let record = try? JSONDecoder().decode(CompletionRecord.self, from: data),
            record.week == Drop.weeksSinceEpoch()
        else {
            completion = nil
            return
        }
        completion = record
    }

    func isCompleted(_ drop: Drop) -> Bool {
        completion?.dropId == drop.id && completion?.week == Drop.weeksSinceEpoch()
    }

    /// Called when the drop session completes: the server writes
    /// `drop_responses` from the kind state's path; this mirrors the row
    /// locally so the CROWD gate can be enforced client-side too.
    func recordCompletion(drop: Drop, path: [ThoughtExperimentChoice]) {
        guard !isCompleted(drop) else { return }
        let record = CompletionRecord(
            dropId: drop.id, week: Drop.weeksSinceEpoch(),
            firstChoice: path.first?.choice ?? "")
        completion = record
        if let data = try? JSONEncoder().encode(record) {
            defaults.set(data, forKey: Self.completionKey)
        }
    }

    /// The crowd (§14.3): mock-mode stand-in for the `drop_aggregate` RPC.
    /// The UI enforces the RPC's hard gate — never shown before the user's
    /// own answer is recorded.
    func aggregate(for dropId: String) -> DropAggregate? {
        aggregates[dropId]
    }

    /// Dev affordance for `-demo-drop`: a fresh run regardless of whether
    /// this week's drop was already completed.
    func resetForDemo() {
        defaults.removeObject(forKey: Self.completionKey)
        completion = nil
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
