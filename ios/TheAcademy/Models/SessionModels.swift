import Foundation

// MARK: - Session kinds (CONTRACTS §3 sessions.kind + §12.1 Academy kinds)

enum SessionKind: String, Codable, Hashable, CaseIterable {
    case lecture, seminar, closeReading, officeHours, essay, quiz
    // Academy kinds (CONTRACTS §12.1, migration 0004).
    case elenchus, thoughtExperiment, argumentLab

    var displayName: String {
        switch self {
        case .lecture: return "Lecture"
        case .seminar: return "Seminar"
        case .closeReading: return "Close Reading"
        case .officeHours: return "Office Hours"
        case .essay: return "Essay"
        case .quiz: return "Quiz"
        case .elenchus: return "Elenchus"
        case .thoughtExperiment: return "Thought Experiment"
        case .argumentLab: return "Argument Lab"
        }
    }

    var symbolName: String {
        switch self {
        case .lecture: return "text.book.closed"
        case .seminar: return "bubble.left.and.bubble.right"
        case .closeReading: return "text.magnifyingglass"
        case .officeHours: return "door.left.hand.open"
        case .essay: return "square.and.pencil"
        case .quiz: return "checklist"
        case .elenchus: return "questionmark.circle"
        case .thoughtExperiment: return "arrow.triangle.branch"
        case .argumentLab: return "square.stack.3d.up"
        }
    }
}

// MARK: - Session state shapes (CONTRACTS §12.1, sessions.state jsonb)

/// elenchus state: the definition-under-fire loop.
struct ElenchusState: Decodable, Hashable {
    var phase: ElenchusPhase = .thesis
    var thesis: String?
    var currentDefinition: String?
    var revisions: Int = 0
    var counterexamplesSurvived: Int = 0
    /// nil while live; aporia or robust once the professor declares.
    var outcome: ElenchusOutcome?
    var specId: String?

    init() {}

    private enum CodingKeys: String, CodingKey {
        case phase, thesis, currentDefinition, revisions, counterexamplesSurvived, outcome, specId
    }

    init(from decoder: Decoder) throws {
        let c = try decoder.container(keyedBy: CodingKeys.self)
        phase = try c.decodeIfPresent(ElenchusPhase.self, forKey: .phase) ?? .thesis
        thesis = try c.decodeIfPresent(String.self, forKey: .thesis)
        currentDefinition = try c.decodeIfPresent(String.self, forKey: .currentDefinition)
        revisions = try c.decodeIfPresent(Int.self, forKey: .revisions) ?? 0
        counterexamplesSurvived = try c.decodeIfPresent(Int.self, forKey: .counterexamplesSurvived) ?? 0
        outcome = try c.decodeIfPresent(ElenchusOutcome.self, forKey: .outcome)
        specId = try c.decodeIfPresent(String.self, forKey: .specId)
    }
}

enum ElenchusPhase: String, Decodable, Hashable, CaseIterable {
    case thesis, definition, counterexample, revision, reflection

    var displayName: String {
        switch self {
        case .thesis: return "Thesis"
        case .definition: return "Definition"
        case .counterexample: return "Counterexample"
        case .revision: return "Revision"
        case .reflection: return "Reflection"
        }
    }
}

enum ElenchusOutcome: String, Decodable, Hashable {
    /// Aporia is a success state — you now know what you don't know (§12.8).
    case aporia
    case robust
}

/// thoughtExperiment state: authored branch walk, then interrogation.
struct ThoughtExperimentState: Decodable, Hashable {
    var specId: String?
    var nodeId: String = "start"
    var path: [ThoughtExperimentChoice] = []
    var pumpsApplied: [String] = []
    var phase: ThoughtExperimentPhase = .run

    init() {}

    private enum CodingKeys: String, CodingKey {
        case specId, nodeId, path, pumpsApplied, phase
    }

    init(from decoder: Decoder) throws {
        let c = try decoder.container(keyedBy: CodingKeys.self)
        specId = try c.decodeIfPresent(String.self, forKey: .specId)
        nodeId = try c.decodeIfPresent(String.self, forKey: .nodeId) ?? "start"
        path = try c.decodeIfPresent([ThoughtExperimentChoice].self, forKey: .path) ?? []
        pumpsApplied = try c.decodeIfPresent([String].self, forKey: .pumpsApplied) ?? []
        phase = try c.decodeIfPresent(ThoughtExperimentPhase.self, forKey: .phase) ?? .run
    }
}

struct ThoughtExperimentChoice: Codable, Hashable {
    let nodeId: String
    let choice: String
}

enum ThoughtExperimentPhase: String, Decodable, Hashable {
    case run, interrogation, debrief
}

/// argumentLab state: deterministic map plus hunt/collapse progress.
struct ArgumentLabState: Decodable, Hashable {
    var specId: String?
    var phase: ArgumentLabPhase = .mapPresented
    var attempts: Int = 0
    var found: Bool = false

    init() {}

    private enum CodingKeys: String, CodingKey { case specId, phase, attempts, found }

    init(from decoder: Decoder) throws {
        let c = try decoder.container(keyedBy: CodingKeys.self)
        specId = try c.decodeIfPresent(String.self, forKey: .specId)
        phase = try c.decodeIfPresent(ArgumentLabPhase.self, forKey: .phase) ?? .mapPresented
        attempts = try c.decodeIfPresent(Int.self, forKey: .attempts) ?? 0
        found = try c.decodeIfPresent(Bool.self, forKey: .found) ?? false
    }
}

enum ArgumentLabPhase: String, Decodable, Hashable {
    case mapPresented, hunt, reveal, collapse, rebuild
}

// MARK: - Session Edge Function request body (CONTRACTS §4, §12.1)

struct SessionRequest: Encodable {
    var action: String                      // "start" | "turn"
    var sessionId: String?                  // required for "turn"
    var enrollmentId: String?               // required for "start"
    var kind: SessionKind
    var unit: Int?                          // required for "start"
    var userText: String?
    var userAnnotations: [UserAnnotation]?
    var essayBody: String?
    /// thoughtExperiment run-phase turns carry the tapped branch (§12.1):
    /// `userText` is the choice label; `{nodeId, choice}` is echoed by the
    /// server into `path` via the `recordChoice` stateOp.
    var nodeId: String?
    var choice: String?

    static func start(enrollmentId: String, kind: SessionKind, unit: Int,
                      essayBody: String? = nil) -> SessionRequest {
        SessionRequest(action: "start", sessionId: nil, enrollmentId: enrollmentId,
                       kind: kind, unit: unit, userText: nil,
                       userAnnotations: nil, essayBody: essayBody,
                       nodeId: nil, choice: nil)
    }

    static func turn(sessionId: String, kind: SessionKind, userText: String?,
                     annotations: [UserAnnotation]? = nil,
                     essayBody: String? = nil,
                     nodeId: String? = nil, choice: String? = nil) -> SessionRequest {
        SessionRequest(action: "turn", sessionId: sessionId, enrollmentId: nil,
                       kind: kind, unit: nil, userText: userText,
                       userAnnotations: annotations, essayBody: essayBody,
                       nodeId: nodeId, choice: choice)
    }
}

struct UserAnnotation: Encodable {
    let passageId: String
    let quote: String
    let note: String?
}

// MARK: - SSE events (CONTRACTS §4)

enum SessionEvent {
    case session(sessionId: String, kind: SessionKind, unit: Int)
    case sayDelta(String)
    case envelope(Envelope)
    /// `code` per §4.3 (e.g. "budget_exceeded"); nil for plain errors.
    case error(code: String?, message: String)
    case done
}

/// Error codes the client treats specially (CONTRACTS §4.3).
enum SessionErrorCode {
    static let budgetExceeded = "budget_exceeded"
}

// MARK: - Local view models

/// Local stand-in for the `enrollments` row; persisted on-device until the
/// Supabase backend is wired up.
struct Enrollment: Codable, Identifiable, Hashable {
    let id: UUID
    let courseId: String
    var pace: Pace
    var currentUnit: Int
    var startedAt: Date

    init(courseId: String, pace: Pace) {
        self.id = UUID()
        self.courseId = courseId
        self.pace = pace
        self.currentUnit = 0
        self.startedAt = Date()
    }
}

enum Pace: String, Codable, CaseIterable, Identifiable {
    case relaxed, standard, intensive
    var id: String { rawValue }
    var displayName: String { rawValue.capitalized }
}

enum Intensity: String, Codable, CaseIterable, Identifiable {
    case gentle, standard, rigorous
    var id: String { rawValue }
    var displayName: String { rawValue.capitalized }
}

/// Local shape of `reading_progress` (CONTRACTS §3), keyed by bookID.
struct ReadingProgress: Codable, Hashable {
    var ch: Int
    var charOffset: Int
    var updatedAt: Date
}

/// One bubble in the session transcript.
struct TurnMessage: Identifiable {
    enum Role { case user, professor }

    let id = UUID()
    let role: Role
    var text: String
    var citations: [Citation] = []
    var isStreaming = false
    /// Set when the professor's `applyPump` fired on this turn: the id of the
    /// authored intuition pump to render as a "the dial turns" card (§12.7).
    var pumpId: String?
}
