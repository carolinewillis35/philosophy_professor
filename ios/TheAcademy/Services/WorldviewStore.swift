import Foundation
import Observation

/// The user's Commitment Map as the Worldview page reads it (§12.3, §12.7).
/// Mock mode loads the fixture snapshot from the bundle; a live
/// implementation fetches the same shapes from `commitments` /
/// `commitment_tensions` and performs the RLS-permitted owner writes
/// (update strength to 'abandoned', delete). Contest mutations here are
/// local, mirroring exactly what RLS lets the owner do.
@Observable
@MainActor
final class WorldviewStore {

    private(set) var commitments: [Commitment] = []
    private(set) var tensions: [CommitmentTension] = []
    private(set) var timeline: [WorldviewEvent] = []
    private(set) var readerProfile: ReaderProfileDigest?
    private(set) var isLoaded = false

    func loadIfNeeded() {
        guard !isLoaded else { return }
        defer { isLoaded = true }
        guard
            let url = Bundle.main.resourceURL?
                .appendingPathComponent("Fixtures/worldview.json"),
            let data = try? Data(contentsOf: url)
        else { return }
        let decoder = JSONDecoder()
        decoder.dateDecodingStrategy = .iso8601
        guard let fixture = try? decoder.decode(WorldviewFixture.self, from: data) else { return }
        commitments = fixture.commitments
        tensions = fixture.tensions
        timeline = fixture.timeline.sorted { $0.date > $1.date }
        readerProfile = fixture.readerProfile
    }

    // MARK: derived

    var liveCommitments: [Commitment] {
        commitments.filter { $0.strength != .abandoned }
    }

    func commitments(in domain: ClaimDomain) -> [Commitment] {
        commitments
            .filter { $0.domain == domain }
            .sorted { $0.strength > $1.strength }
    }

    var openTensions: [CommitmentTension] {
        tensions.filter { $0.status == .open || $0.status == .raised }
    }

    func commitment(_ id: String) -> Commitment? {
        commitments.first { $0.id == id }
    }

    // MARK: contest (the owner-permitted writes, §12.3 RLS)

    /// "I no longer hold that" — sets strength to abandoned (never deletes;
    /// the arc is the product) and dissolves tensions that leaned on it.
    func abandon(_ commitment: Commitment) {
        guard let index = commitments.firstIndex(where: { $0.id == commitment.id }),
              commitments[index].strength != .abandoned else { return }
        let from = commitments[index].strength
        commitments[index].strength = .abandoned
        for i in tensions.indices
        where tensions[i].commitmentA == commitment.id || tensions[i].commitmentB == commitment.id {
            tensions[i].status = .dissolved
        }
        timeline.insert(WorldviewEvent(
            id: UUID().uuidString, date: Date(), claim: commitment.claim,
            fromStrength: from, toStrength: .abandoned,
            note: "Abandoned from the Worldview page."), at: 0)
    }

    /// "I never held that" — owner delete; the row and its tensions go.
    func delete(_ commitment: Commitment) {
        commitments.removeAll { $0.id == commitment.id }
        tensions.removeAll { $0.commitmentA == commitment.id || $0.commitmentB == commitment.id }
    }

    // MARK: export (§12.7 markdown share sheet)

    func exportMarkdown() -> String {
        var lines: [String] = ["# My Worldview", ""]
        for domain in ClaimDomain.allCases {
            let positions = commitments(in: domain)
            guard !positions.isEmpty else { continue }
            lines.append("## \(domain.displayName)")
            for c in positions {
                let affirmations = c.affirmCount == 1 ? "affirmed once" : "affirmed \(c.affirmCount) times"
                lines.append("- **\(c.strength.displayName)** — \(c.claim) _(\(affirmations))_")
            }
            lines.append("")
        }
        let open = openTensions
        if !open.isEmpty {
            lines.append("## Open tensions")
            for tension in open {
                if let a = commitment(tension.commitmentA), let b = commitment(tension.commitmentB) {
                    lines.append("- “\(a.claim)” pulls against “\(b.claim)” — \(tension.via)")
                }
            }
            lines.append("")
        }
        if !timeline.isEmpty {
            lines.append("## How it has moved")
            let formatter = DateFormatter()
            formatter.dateStyle = .medium
            for event in timeline.sorted(by: { $0.date < $1.date }) {
                let move = event.fromStrength.map { "\($0.displayName) → \(event.toStrength.displayName)" }
                    ?? event.toStrength.displayName
                lines.append("- \(formatter.string(from: event.date)): \(move) — \(event.claim)")
            }
            lines.append("")
        }
        lines.append("_Exported from The Academy. Positions are recorded in your own words; nothing here is graded._")
        return lines.joined(separator: "\n")
    }
}
