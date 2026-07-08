import Foundation

// MARK: - Course JSON (CONTRACTS §7)

struct Course: Codable, Identifiable, Hashable {
    let id: String
    let title: String
    let personaId: String
    let description: String
    let difficulty: String
    let estWeeks: Int
    let texts: [CourseText]
    let units: [Unit]
}

struct CourseText: Codable, Hashable {
    let bookID: String
    let title: String
    let author: String
    let source: String
    let sourceUrl: String
    let license: String
    let licenseNote: String?
}

/// Inclusive chapter span into a book (CONTRACTS §2).
struct ReadingSpan: Codable, Hashable {
    let bookID: String
    let chStart: Int
    let chEnd: Int
}

struct Unit: Codable, Hashable, Identifiable {
    var id: Int { number }
    let number: Int
    let title: String
    let reading: [ReadingSpan]
    let lectureOutline: [String]
    let seminarQuestionBank: [String]
    let closeReadingPassages: [String]?
    let assignments: [Assignment]
    let recapNotes: String?
    // Academy authored specs (CONTRACTS §12.5) — all optional arrays.
    let elenchusSpecs: [ElenchusSpec]?
    let thoughtExperiments: [ThoughtExperimentSpec]?
    let argumentLabs: [ArgumentSpec]?
}

struct Assignment: Codable, Hashable, Identifiable {
    let id: String
    let kind: String
    let prompt: String
    let lengthWords: Int
    let rubric: [RubricCriterion]
}

struct RubricCriterion: Codable, Hashable {
    let name: String
    let weight: Double
    let descriptors: [String: String]
}

// MARK: - Authored spec schemas (CONTRACTS §12.5)

/// The authored spine of an elenchus: known definitions and the classical
/// counterexamples that dismantle them.
struct ElenchusSpec: Codable, Hashable, Identifiable {
    let id: String
    let openingQuestion: String
    let span: ReadingSpan
    let passageIds: [String]
    let classicMoves: [ClassicMove]
    let relatedClaims: [String]?
    let reflectionPrompt: String

    struct ClassicMove: Codable, Hashable {
        let definition: String
        let counterexample: String
    }
}

/// An authored, branching thought experiment. Nodes render client-side with
/// no API call per branch (DECISIONS A10); the professor enters only at
/// interrogation/debrief.
struct ThoughtExperimentSpec: Codable, Hashable, Identifiable {
    let id: String
    let title: String
    let setup: String
    let philosophicalPayload: String
    let sourceRefs: [String]?
    let nodes: [Node]
    let pumps: [Pump]?
    let interrogation: [String]
    let relatedClaims: [String]?

    struct Node: Codable, Hashable, Identifiable {
        let id: String
        let text: String
        let options: [Option]?
        let terminal: Bool?

        var isTerminal: Bool { terminal ?? (options?.isEmpty ?? true) }
    }

    struct Option: Codable, Hashable {
        let label: String
        let next: String
    }

    /// Intuition pumps: authored variations that stress the chosen principle.
    struct Pump: Codable, Hashable, Identifiable {
        let id: String
        let afterNode: String
        let variation: String
        let testsPrinciple: String
    }

    func node(_ id: String) -> Node? { nodes.first { $0.id == id } }
    func pump(_ id: String) -> Pump? { pumps?.first { $0.id == id } }
    var startNode: Node? { node("start") ?? nodes.first }
}

/// A source argument reconstructed as premises converging on a conclusion.
/// Rendered deterministically by ArgumentMapView (DECISIONS A11) — no LLM in
/// the render path.
struct ArgumentSpec: Codable, Hashable, Identifiable {
    let id: String
    let title: String
    let source: Source
    let conclusion: Statement
    let premises: [Premise]
    /// hunt: find the unstated premise; collapse: a premise is removed.
    let mode: Mode
    let hiddenPremiseId: String?    // hunt mode
    let removedPremiseId: String?   // collapse mode
    let pedagogicalPoint: String
    let elicitationQuestions: [String]
    let relatedClaims: [String]?

    enum Mode: String, Codable, Hashable {
        case hunt, collapse
    }

    struct Source: Codable, Hashable {
        let bookID: String
        let passageIds: [String]
    }

    struct Statement: Codable, Hashable, Identifiable {
        let id: String
        let text: String
    }

    struct Premise: Codable, Hashable, Identifiable {
        let id: String
        let text: String
        let stated: Bool
        /// id of the statement this premise supports (the conclusion or
        /// another premise).
        let supports: String
    }
}

// MARK: - Persona registry (content/personas/personas.json)

struct Persona: Codable, Identifiable, Hashable {
    let id: String
    let name: String
    let title: String
    let portrait: String?
    let blurb: String

    /// "Sokratis Vlachos" -> "SV"
    var monogram: String {
        let parts = name.split(separator: " ").filter { !$0.hasSuffix(".") }
        let initials = parts.suffix(2).compactMap { $0.first }
        return String(initials).uppercased()
    }
}
