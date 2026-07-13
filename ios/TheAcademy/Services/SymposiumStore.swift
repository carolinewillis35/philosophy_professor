import Foundation
import Observation

/// The monthly Symposium (§16.1–§16.3): this month's spec from the bundled
/// bank, the local record of the user's response row, and the mock movement
/// aggregate. Records persist locally keyed by (symposiumId, month); in live
/// mode the `symposium_responses` unique constraint is the real gate and
/// this remains the optimistic cache — exactly the DropStore pattern.
///
/// The ordering honesty (§16.6): `before` is captured by the before-tap,
/// BEFORE any argument is heard; `after` lands only when a `recordPosition`
/// op does; the MOVEMENT screen hangs on `completed`, never earlier.
@Observable
@MainActor
final class SymposiumStore {

    /// The local mirror of one `symposium_responses` row.
    struct ResponseRecord: Codable {
        let symposiumId: String
        let month: Int
        /// Captured at the before-tap — before any argument is heard.
        let before: SymposiumStance
        /// "a"/"b" once the student rules; nil is a completed session that
        /// stayed undecided — a position, not a failure (§16.6).
        var after: SymposiumStance?
        var completed: Bool
    }

    private(set) var symposia: [SymposiumSpec] = []
    /// Every recorded response, newest month first — the local
    /// `symposium_responses`.
    private(set) var history: [ResponseRecord] = []
    /// Mock of the `symposium_movement` RPC payloads, keyed by symposium id.
    /// The fixture includes one suppressed entry (total < 10 ⇒
    /// moved/byBefore/byAfter null) so both movement states render.
    private var movements: [String: SymposiumMovement] = [:]

    private let defaults = UserDefaults.standard
    private static let historyKey = "symposiumResponseHistory"

    func load(bank: [SymposiumSpec]) {
        symposia = bank.sorted { $0.id < $1.id }
        loadMovementFixture()
        reloadResponseState()
    }

    /// Deterministic §16.1 monthly rotation over the sorted bank.
    var thisMonthSymposium: SymposiumSpec? {
        SymposiumSpec.thisMonth(in: symposia)
    }

    /// This month's response for a symposium — the before-tap seeds it; the
    /// MOVEMENT gate hangs on its `completed` (§16.6). Last cycle's response
    /// is not this cycle's.
    func response(for symposium: SymposiumSpec) -> ResponseRecord? {
        history.first {
            $0.symposiumId == symposium.id && $0.month == SymposiumSpec.monthsSinceEpoch()
        }
    }

    func reloadResponseState() {
        guard let data = defaults.data(forKey: Self.historyKey),
              let decoded = try? JSONDecoder().decode([ResponseRecord].self, from: data)
        else { return }
        history = decoded.sorted { $0.month > $1.month }
    }

    /// The before-tap (§16.2/§16.6): captures the arrival position BEFORE
    /// the session starts — that ordering is the data's honesty. Idempotent
    /// per (symposiumId, month), like the server's unique constraint.
    func recordBefore(symposium: SymposiumSpec, stance: SymposiumStance) {
        guard response(for: symposium) == nil else { return }
        history.insert(ResponseRecord(
            symposiumId: symposium.id,
            month: SymposiumSpec.monthsSinceEpoch(),
            before: stance, after: nil, completed: false), at: 0)
        history.sort { $0.month > $1.month }
        saveHistory()
    }

    /// A `recordPosition` op landed (§16.2): map the ruled side onto
    /// "a"/"b" and mirror the server's after-position update locally.
    func recordAfter(symposium: SymposiumSpec, ruledSide: String) {
        update(symposium: symposium) { $0.after = symposium.stance(forSide: ruledSide) }
    }

    /// The session completed: mark the row — the MOVEMENT gate. Completing
    /// without a ruling leaves `after` nil (still undecided; still counted).
    func recordCompletion(symposium: SymposiumSpec, ruledSide: String?) {
        update(symposium: symposium) {
            if let ruledSide { $0.after = symposium.stance(forSide: ruledSide) }
            $0.completed = true
        }
    }

    /// The movement (§16.3): mock-mode stand-in for the `symposium_movement`
    /// RPC. The UI enforces the RPC's hard gate — reachable ONLY after the
    /// caller's own completed response.
    func movement(for symposiumId: String) -> SymposiumMovement? {
        movements[symposiumId]
    }

    /// Dev affordance for `-demo-symposium`: a fresh response this month
    /// regardless of whether one was already recorded.
    func resetForDemo() {
        history.removeAll { $0.month == SymposiumSpec.monthsSinceEpoch() }
        saveHistory()
    }

    private func update(symposium: SymposiumSpec,
                        _ mutate: (inout ResponseRecord) -> Void) {
        guard let i = history.firstIndex(where: {
            $0.symposiumId == symposium.id && $0.month == SymposiumSpec.monthsSinceEpoch()
        }) else { return }
        mutate(&history[i])
        saveHistory()
    }

    private func saveHistory() {
        if let data = try? JSONEncoder().encode(history) {
            defaults.set(data, forKey: Self.historyKey)
        }
    }

    private func loadMovementFixture() {
        guard
            let url = Bundle.main.resourceURL?
                .appendingPathComponent("Fixtures/symposium-movement.json"),
            let data = try? Data(contentsOf: url),
            let decoded = try? JSONDecoder().decode([String: SymposiumMovement].self, from: data)
        else { return }
        movements = decoded
    }
}
