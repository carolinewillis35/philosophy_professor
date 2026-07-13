import Foundation

// MARK: - The News, Read Philosophically (CONTRACTS §15.2)

/// One lens of an authored pair (`content/news/lenses.json`) — mirrors
/// `NewsLens` in kinds_life.ts.
struct NewsLens: Decodable, Hashable {
    let name: String
    let ontologyId: String
    let oneLiner: String
}

/// Two genuinely opposed frameworks and where they characteristically split.
/// Mirrors `LensPair` in kinds_life.ts.
struct LensPair: Decodable, Hashable {
    let id: String
    let domain: String
    let a: NewsLens
    let b: NewsLens
    let splitHint: String
}

/// The week's cached brief (`news_briefs.doc`, bundled as
/// `Fixtures/news-brief.json` in mock mode) — mirrors `NewsBrief` in
/// kinds_life.ts. Self-contained: the lens pair is embedded at generation
/// time (A25), so the client renders lens names and sources from it alone.
struct NewsBrief: Decodable, Hashable {
    let headline: String
    let summary: String
    let question: String
    let domain: String
    let sourceUrls: [String]
    let lensPairId: String
    let lensPair: LensPair
}

/// The newsRead state machine (§15.2): brief → lensA → lensB → split →
/// position. `advancePhase` walks it; a session may complete from `position`
/// only. Client mirror of `NewsPhase` in kinds_life.ts.
enum NewsPhase: String, Decodable, Hashable, CaseIterable {
    case brief, lensA, lensB, split, position

    /// Generic strip label; the lens phases prefer the pair's actual lens
    /// names where they fit (§15.5).
    var displayName: String {
        switch self {
        case .brief: return "Brief"
        case .lensA: return "Lens A"
        case .lensB: return "Lens B"
        case .split: return "The Split"
        case .position: return "Your Position"
        }
    }
}
