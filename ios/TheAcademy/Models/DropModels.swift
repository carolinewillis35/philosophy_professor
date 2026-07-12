import Foundation

// MARK: - Weekly drops (CONTRACTS §14.3)

/// One entry of the drop bank (`content/drops/drops.json`, bundled as
/// `Fixtures/drops.json`; live mode reads the same doc shape from the
/// `drops` table). The experiment reuses the §12.5 ThoughtExperimentSpec
/// exactly — the drop RUNS the existing thoughtExperiment kind, standalone.
struct Drop: Decodable, Identifiable, Hashable {
    let id: String
    let personaId: String
    let teaser: String
    let experiment: ThoughtExperimentSpec
}

/// The bank asset wrapper: `{ "version": 1, "drops": [...] }`.
struct DropBank: Decodable {
    let version: Int
    let drops: [Drop]
}

/// The `drop_aggregate` RPC payload (§14.3): first-choice distribution over
/// ALL users' responses. `byFirstChoice` is null under the small-crowd
/// suppression (total < 10) — and the whole thing exists only AFTER the
/// caller has answered (§13.4/§14.6).
struct DropAggregate: Decodable, Hashable {
    let total: Int
    let byFirstChoice: [String: Int]?
}

// MARK: - Deterministic weekly selection (§14.3: no cron, A16 pattern —
// mirrors the daily rotation in DailyQuestionModels)

extension Drop {
    /// Whole weeks since 1970-01-01 for the device's local calendar date:
    /// `floor(daysSinceEpoch / 7)`. Client and server compute the same index
    /// from the same `localDate`.
    static func weeksSinceEpoch(for date: Date = Date(),
                                calendar: Calendar = .current) -> Int {
        DailyQuestion.daysSinceEpoch(for: date, calendar: calendar) / 7
    }

    /// This week's drop: bank sorted by id, indexed by the local-date week
    /// count. Stable for a given week, rotates with the calendar.
    static func thisWeek(in drops: [Drop], date: Date = Date(),
                         calendar: Calendar = .current) -> Drop? {
        guard !drops.isEmpty else { return nil }
        let sorted = drops.sorted { $0.id < $1.id }
        return sorted[weeksSinceEpoch(for: date, calendar: calendar) % sorted.count]
    }
}
