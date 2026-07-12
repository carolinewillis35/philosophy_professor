import Foundation

// MARK: - Daily Question (CONTRACTS §13.2)

/// One entry of the daily bank (`content/daily/questions.json`, bundled as
/// `Fixtures/daily-questions.json`; live mode reads the same doc shape from
/// the `daily_questions` table).
struct DailyQuestion: Decodable, Identifiable, Hashable {
    let id: String
    let question: String
    let domain: String
    let personaId: String
    let options: [Option]
    let relatedClaims: [String]?

    struct Option: Decodable, Identifiable, Hashable {
        let id: String
        let label: String
        /// Canonical claim id the tap maps to; nil when the option is unmapped.
        let ontologyId: String?
    }
}

/// The bank asset wrapper: `{ "version": 1, "questions": [...] }`.
struct DailyQuestionBank: Decodable {
    let version: Int
    let questions: [DailyQuestion]
}

// MARK: - Deterministic selection (§13.2: no cron, no server round trip)

extension DailyQuestion {
    /// The device's local calendar date as `YYYY-MM-DD` — the `localDate`
    /// the start request carries, and the key the answered state hangs on.
    static func localDateString(for date: Date = Date(),
                                calendar: Calendar = .current) -> String {
        let c = calendar.dateComponents([.year, .month, .day], from: date)
        return String(format: "%04d-%02d-%02d", c.year ?? 1970, c.month ?? 1, c.day ?? 1)
    }

    /// Days since 1970-01-01 for the device's local calendar date. Client and
    /// server compute the same index from the same `localDate`, so today's
    /// question is `bank[daysSinceEpoch % bank.count]` on both sides (§13.2).
    static func daysSinceEpoch(for date: Date = Date(),
                               calendar: Calendar = .current) -> Int {
        let components = calendar.dateComponents([.year, .month, .day], from: date)
        var utc = Calendar(identifier: .gregorian)
        utc.timeZone = TimeZone(identifier: "UTC") ?? .current
        guard let day = utc.date(from: components) else { return 0 }
        return max(0, Int(day.timeIntervalSince1970 / 86_400))
    }

    /// Today's question: bank sorted by id, indexed by the local-date day
    /// count. Stable for a given local date, rotates at local midnight.
    static func today(in bank: [DailyQuestion], date: Date = Date(),
                      calendar: Calendar = .current) -> DailyQuestion? {
        guard !bank.isEmpty else { return nil }
        let sorted = bank.sorted { $0.id < $1.id }
        return sorted[daysSinceEpoch(for: date, calendar: calendar) % sorted.count]
    }
}
