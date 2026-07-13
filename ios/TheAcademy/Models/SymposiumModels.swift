import Foundation

// MARK: - The monthly Symposium (CONTRACTS §16.1/§16.2)

/// One side's one-liner (`positionA`/`positionB` of the authored spec).
struct SymposiumPosition: Decodable, Hashable {
    let label: String
    /// Canonical claim id the position maps to; nil when unmapped.
    let ontologyId: String?
}

/// One authored volley of the exchange — the debate's spine (§16.1); the
/// server extends it live, the mock speaks it verbatim.
struct SymposiumVolley: Decodable, Hashable {
    let speaker: String
    let say: String
}

/// One entry of the symposium bank (`content/symposia/symposia.json`,
/// bundled as `Fixtures/symposia.json`; live mode reads the same doc shape
/// from the `symposia` table) — the client mirror of the server's
/// SymposiumSpec (kinds_agora.ts).
struct SymposiumSpec: Decodable, Identifiable, Hashable {
    let id: String
    let question: String
    let personaA: String
    let personaB: String
    let positionA: SymposiumPosition
    let positionB: SymposiumPosition
    let crux: String
    let volleys: [SymposiumVolley]?
    let relatedClaims: [String]?
}

/// The bank asset wrapper: `{ "version": 1, "symposia": [...] }`.
struct SymposiumBank: Decodable {
    let version: Int
    let symposia: [SymposiumSpec]
}

/// A position relative to the two sides — the before-tap's vocabulary and
/// the `symposium_responses` check constraint. "Undecided" is a position,
/// not a failure to have one (§16.6).
enum SymposiumStance: String, Codable, Hashable {
    case a, b, undecided
}

// MARK: - Session state mirror (§16.2, sessions.state jsonb)

/// The five phases: question → exchange → your ruling → cross-examination →
/// debrief. The client mirror of the server's SymposiumPhase.
enum SymposiumPhase: String, CaseIterable, Hashable {
    case questionPresented, exchange, adjudication, crossExamination, jointDebrief

    var displayName: String {
        switch self {
        case .questionPresented: return "The Question"
        case .exchange: return "The Exchange"
        case .adjudication: return "Your Ruling"
        case .crossExamination: return "Cross-Examination"
        case .jointDebrief: return "Debrief"
        }
    }
}

/// The student's ruling as the `recordPosition` op carries it: the persona
/// they sided with, and their reason in their own words.
struct SymposiumRuling: Hashable {
    let side: String
    let statement: String
}

/// Client mirror of the server's SymposiumState (kinds_agora.ts), folded
/// from advancePhase and recordPosition.
struct SymposiumClientState: Hashable {
    var phase: SymposiumPhase = .questionPresented
    /// nil until the student rules; staying undecided emits no ruling.
    var position: SymposiumRuling?
}

// MARK: - Movement aggregate (§16.3)

/// The `symposium_movement` RPC payload: completed responses only, callable
/// only after the caller's own completion. Under 10 completed responses the
/// suppressed case leaves `moved`/`byBefore`/`byAfter` null and `total` is
/// all anyone sees (§16.3).
struct SymposiumMovement: Decodable, Hashable {
    let total: Int
    /// Count whose after-position is non-null and differs from before.
    let moved: Int?
    /// Distribution keyed "a"/"b"/"undecided".
    let byBefore: [String: Int]?
    /// Distribution keyed "a"/"b" — only those who ruled.
    let byAfter: [String: Int]?
}

// MARK: - Deterministic monthly selection (§16.1: A16 pattern — mirrors the
// daily/weekly rotation in DailyQuestionModels/DropModels)

extension SymposiumSpec {
    /// `monthsSinceEpoch("YYYY-MM-DD") = YYYY*12 + (MM-1)` — client and
    /// server compute the same index from the same local date.
    static func monthsSinceEpoch(for date: Date = Date(),
                                 calendar: Calendar = .current) -> Int {
        let c = calendar.dateComponents([.year, .month], from: date)
        return (c.year ?? 1970) * 12 + ((c.month ?? 1) - 1)
    }

    /// This month's symposium: bank sorted by id, indexed by the local-date
    /// month count. Stable for a given month, rotates with the calendar.
    static func thisMonth(in bank: [SymposiumSpec], date: Date = Date(),
                          calendar: Calendar = .current) -> SymposiumSpec? {
        guard !bank.isEmpty else { return nil }
        let sorted = bank.sorted { $0.id < $1.id }
        return sorted[monthsSinceEpoch(for: date, calendar: calendar) % sorted.count]
    }

    /// Map a ruled side (a persona id) onto the response row's vocabulary.
    func stance(forSide side: String) -> SymposiumStance {
        side == personaA ? .a : .b
    }

    /// The one-liner for a stance, for display (nil for undecided).
    func position(for stance: SymposiumStance) -> SymposiumPosition? {
        switch stance {
        case .a: return positionA
        case .b: return positionB
        case .undecided: return nil
        }
    }

    /// The persona holding a stance's side (nil for undecided).
    func personaId(for stance: SymposiumStance) -> String? {
        switch stance {
        case .a: return personaA
        case .b: return personaB
        case .undecided: return nil
        }
    }
}
