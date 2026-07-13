import Foundation

// MARK: - Dinner-party packs (CONTRACTS §16.4)

/// One pack of table questions (`content/packs/packs.json`, bundled as
/// `Fixtures/packs.json`; live mode reads the same doc shape from the
/// `packs` table). The packs exist to push philosophy OFF the screen —
/// export is the point, and NOTHING about their use is tracked (§16.6).
struct Pack: Decodable, Identifiable, Hashable {
    let id: String
    let title: String
    let blurb: String
    let cards: [Card]

    /// One card: the question, and the one move that keeps a real table
    /// talking when it stalls.
    struct Card: Decodable, Hashable {
        let question: String
        let followUp: String
    }
}

/// The bank asset wrapper: `{ "version": 1, "packs": [...] }`.
struct PackBank: Decodable {
    let version: Int
    let packs: [Pack]
}

extension Pack {
    /// Whole-pack export as clean plain text (§16.4/§16.5) — designed to be
    /// sent to a group chat or printed, not to link back to the app.
    var exportText: String {
        var lines: [String] = [title, ""]
        for card in cards {
            lines.append("Q: \(card.question)")
            lines.append("If the table stalls: \(card.followUp)")
            lines.append("")
        }
        return lines.joined(separator: "\n").trimmingCharacters(in: .whitespacesAndNewlines)
    }
}
