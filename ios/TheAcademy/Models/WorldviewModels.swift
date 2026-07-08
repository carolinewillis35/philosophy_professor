import Foundation

// MARK: - Commitment Map (CONTRACTS §12.3 shapes, client-side mirror)

/// The six fixed claim domains (§12.6).
enum ClaimDomain: String, Codable, Hashable, CaseIterable, Identifiable {
    case ethics, epistemology, metaphysics, mind, political, aesthetics

    var id: String { rawValue }

    var displayName: String {
        switch self {
        case .ethics: return "Ethics"
        case .epistemology: return "Epistemology"
        case .metaphysics: return "Metaphysics"
        case .mind: return "Mind"
        case .political: return "Political"
        case .aesthetics: return "Aesthetics"
        }
    }

    var symbolName: String {
        switch self {
        case .ethics: return "scalemass"
        case .epistemology: return "eye"
        case .metaphysics: return "circle.hexagongrid"
        case .mind: return "brain.head.profile"
        case .political: return "building.columns"
        case .aesthetics: return "paintpalette"
        }
    }
}

/// Strength ladder (§12.2): explore → lean → assert, upward only; abandon is
/// terminal and never deleted server-side — the arc is the product.
enum CommitmentStrength: String, Codable, Hashable, Comparable {
    case explored, leaned, asserted, abandoned

    var displayName: String {
        switch self {
        case .explored: return "Exploring"
        case .leaned: return "Leaning"
        case .asserted: return "Asserted"
        case .abandoned: return "Abandoned"
        }
    }

    private var rank: Int {
        switch self {
        case .abandoned: return 0
        case .explored: return 1
        case .leaned: return 2
        case .asserted: return 3
        }
    }

    static func < (lhs: Self, rhs: Self) -> Bool { lhs.rank < rhs.rank }
}

/// One row of the user's `commitments` table (§12.3).
struct Commitment: Codable, Identifiable, Hashable {
    let id: String
    let claim: String
    let domain: ClaimDomain
    let ontologyId: String?
    var strength: CommitmentStrength
    var affirmCount: Int
    let firstAsserted: Date
    var lastAffirmed: Date
}

/// One row of `commitment_tensions` (§12.3): two positions that pull against
/// each other, via the ontology's edges.
struct CommitmentTension: Codable, Identifiable, Hashable {
    let id: String
    let commitmentA: String   // Commitment.id
    let commitmentB: String
    /// Human-readable rendering of the claim_edges path that produced it.
    let via: String
    var status: TensionStatus
}

enum TensionStatus: String, Codable, Hashable {
    case open, raised, reconciled, dissolved
}

/// One beat of the strength-change timeline ("you moved from X to Y").
struct WorldviewEvent: Codable, Identifiable, Hashable {
    let id: String
    let date: Date
    let claim: String
    let fromStrength: CommitmentStrength?
    let toStrength: CommitmentStrength
    let note: String?
}

// MARK: - Reader profile digest (§11.3, folded into Worldview per DECISIONS A14)

/// The attention slice of `reader_profiles.dimensions`, enough to draw the
/// radar. The full pipeline stays server-side; this is its display shape.
struct ReaderProfileDigest: Codable, Hashable {
    /// dimension -> score 0..1, keys per §11.1 (character|form|image|structure|context|sound)
    let attention: [String: Double]
    let strengths: [String]
    let growthEdges: [String]
    let narrativeSummary: String

    static let dimensionOrder = ["character", "form", "image", "structure", "context", "sound"]
}

// MARK: - Fixture container (mock mode)

/// Shape of `Fixtures/worldview.json` — a plausible mid-course snapshot.
struct WorldviewFixture: Codable {
    let commitments: [Commitment]
    let tensions: [CommitmentTension]
    let timeline: [WorldviewEvent]
    let readerProfile: ReaderProfileDigest
}
