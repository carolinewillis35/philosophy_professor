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

    /// Authored provocation for an untouched TERRITORY tile (§14.5b) — shown
    /// when the domain has no live commitments. The epistemology line is the
    /// CONTRACTS-authored one; the rest are written at its bar.
    var provocation: String {
        switch self {
        case .ethics:
            return "You have no ethics on record — yet you made a hundred moral calls this week with tools you have never once inspected."
        case .epistemology:
            return "You have no epistemology yet; everything you believe rests on a theory of knowledge you haven't met."
        case .metaphysics:
            return "No metaphysics yet — you have never said what is real, and every other answer you hold is waiting on that one."
        case .mind:
            return "Nothing on mind yet — you are thinking with the one instrument you have never turned around to examine."
        case .political:
            return "No politics examined — you live inside answers to questions you haven't asked, and someone else wrote the answers."
        case .aesthetics:
            return "Aesthetics untouched — you already know what you find beautiful; you have never asked what that knowing is."
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
    /// §14.2: how the student reconciled it (set with status 'reconciled').
    var resolution: String?
    var resolvedAt: Date?
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

// MARK: - Commitment events ledger (§14.1) — the changelog of your mind

/// The strength verb a fold recorded.
enum CommitmentEventKind: String, Codable, Hashable {
    case explored, leaned, asserted, affirmed, abandoned

    var displayName: String {
        switch self {
        case .explored: return "Explored"
        case .leaned: return "Leaned"
        case .asserted: return "Asserted"
        case .affirmed: return "Affirmed"
        case .abandoned: return "Abandoned"
        }
    }
}

/// One row of `commitment_events` (§14.1). `priorStrength` is nil on first
/// insert and set on every strength change; `evidence` is the op's evidence
/// line — the argument that moved you. The claim text is joined from
/// `commitments` client-side.
struct CommitmentEvent: Codable, Identifiable, Hashable {
    let id: String
    let commitmentId: String
    let event: CommitmentEventKind
    let priorStrength: CommitmentStrength?
    let evidence: String
    let createdAt: Date
}

// MARK: - Steelman scores (§14.4) — the ladder is derived client-side

/// One row of `steelman_scores`: one graded attempt at the best case against
/// one of the student's own commitments.
struct SteelmanScore: Codable, Identifiable, Hashable {
    let id: String
    let targetOntologyId: String?
    let targetClaim: String
    let level: Int
    let justification: String
    let createdAt: Date
}

/// One rung group of the LADDER screen (§14.5): per-claim max level plus
/// attempt count, computed from `steelman_scores`.
struct SteelmanLadderEntry: Identifiable, Hashable {
    let targetClaim: String
    let maxLevel: Int
    let attempts: Int
    let lastAttempt: Date

    var id: String { targetClaim }
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
/// E-M2 (§14.5) adds the commitment-events ledger and steelman scores.
struct WorldviewFixture: Codable {
    let commitments: [Commitment]
    let tensions: [CommitmentTension]
    let timeline: [WorldviewEvent]
    let readerProfile: ReaderProfileDigest
    let events: [CommitmentEvent]?
    let steelmanScores: [SteelmanScore]?
}
