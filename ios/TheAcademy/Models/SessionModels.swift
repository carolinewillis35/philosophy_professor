import Foundation

// MARK: - Session kinds (CONTRACTS §3 sessions.kind + §12.1 Academy kinds)

enum SessionKind: String, Codable, Hashable, CaseIterable {
    case lecture, seminar, closeReading, officeHours, essay, quiz
    // Academy kinds (CONTRACTS §12.1, migration 0004).
    case elenchus, thoughtExperiment, argumentLab
    // Engagement kinds (CONTRACTS §13/§14, migrations 0005/0006) —
    // standalone: no enrollment, no course unit; bound to user + persona
    // instead.
    case dailyQuestion, argumentClinic, steelman
    // Life kinds (CONTRACTS §15, migration 0007) — also standalone.
    case newsRead, practice, practiceReview

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
        case .dailyQuestion: return "Daily Question"
        case .argumentClinic: return "Argument Clinic"
        case .steelman: return "Steelman"
        case .newsRead: return "Read Philosophically"
        case .practice: return "Practice"
        case .practiceReview: return "Weekly Review"
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
        case .dailyQuestion: return "sun.max"
        case .argumentClinic: return "stethoscope"
        case .steelman: return "shield.lefthalf.filled"
        case .newsRead: return "newspaper"
        case .practice: return "figure.mind.and.body"
        case .practiceReview: return "calendar.badge.clock"
        }
    }

    /// §13.1: not course-bound — sessions carry user + persona instead of an
    /// enrollment.
    var isStandalone: Bool {
        switch self {
        case .dailyQuestion, .argumentClinic, .steelman,
             .newsRead, .practice, .practiceReview:
            return true
        default:
            return false
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

/// argumentClinic phases (§13.3): intake → excavation → map → crux →
/// handback.
enum ClinicPhase: String, Decodable, Hashable, CaseIterable {
    case intake, excavation, map, crux, handback

    var displayName: String {
        switch self {
        case .intake: return "Intake"
        case .excavation: return "Excavation"
        case .map: return "Map"
        case .crux: return "Crux"
        case .handback: return "Handback"
        }
    }
}

/// Where a disagreement really lives (§13.3 markCrux).
enum ClinicCruxKind: String, Decodable, Hashable {
    case fact, value, definition
}

/// argumentClinic state: the client's mirror of the server's ClinicState
/// (kinds_engagement.ts), folded from the four map stateOps plus
/// advancePhase. The map re-renders on every `mapVersion` bump; premises
/// reuse the §12.5 shape so the deterministic renderer consumes them as-is.
struct ClinicMapState: Hashable {
    var phase: ClinicPhase = .intake
    /// The user's claim at issue (map node id "c"); nil until setConclusion.
    var conclusion: String?
    var premises: [ArgumentSpec.Premise] = []
    /// Crux badges keyed by map node id ("c" or a premise id).
    var cruxes: [String: ClinicCruxKind] = [:]
    var mapVersion: Int = 0
}

/// steelman phases (§14.4): brief → attempt → probe → verdict → debrief.
/// Debrief is reached ONLY through recordSteelmanScore, never advancePhase.
enum SteelmanPhase: String, Decodable, Hashable, CaseIterable {
    case brief, attempt, probe, verdict, debrief

    var displayName: String {
        switch self {
        case .brief: return "Brief"
        case .attempt: return "Attempt"
        case .probe: return "Probe"
        case .verdict: return "Verdict"
        case .debrief: return "Debrief"
        }
    }
}

/// steelman state: client mirror of the server's SteelmanState
/// (kinds_engagement.ts, §14.4). The target is the student's OWN commitment;
/// the exercise is the best case AGAINST it.
struct SteelmanState: Decodable, Hashable {
    var phase: SteelmanPhase = .brief
    var targetClaim: String?
    var targetOntologyId: String?
    var probeRounds: Int = 0
    /// nil until the verdict's recordSteelmanScore lands (1–4).
    var level: Int?

    init() {}

    private enum CodingKeys: String, CodingKey {
        case phase, targetClaim, targetOntologyId, probeRounds, level
    }

    init(from decoder: Decoder) throws {
        let c = try decoder.container(keyedBy: CodingKeys.self)
        phase = try c.decodeIfPresent(SteelmanPhase.self, forKey: .phase) ?? .brief
        targetClaim = try c.decodeIfPresent(String.self, forKey: .targetClaim)
        targetOntologyId = try c.decodeIfPresent(String.self, forKey: .targetOntologyId)
        probeRounds = try c.decodeIfPresent(Int.self, forKey: .probeRounds) ?? 0
        level = try c.decodeIfPresent(Int.self, forKey: .level)
    }
}

/// The four named ranks of the steelman ladder (§14.4). Level 1 is
/// "Strawman", never "failure" (§14.6) — the grade is on the argument
/// produced, not the person.
enum SteelmanLevel: Int, CaseIterable, Identifiable {
    case strawman = 1, sketch = 2, competent = 3, signable = 4

    var id: Int { rawValue }

    var displayName: String {
        switch self {
        case .strawman: return "Strawman"
        case .sketch: return "Sketch"
        case .competent: return "Competent"
        case .signable: return "Signable"
        }
    }

    /// The rubric line, verbatim from the kind's STEELMAN_LEVELS.
    var descriptor: String {
        switch self {
        case .strawman: return "the opponent wouldn't recognize it"
        case .sketch: return "recognizable but missing its best premise"
        case .competent: return "a holder would nod"
        case .signable: return "a holder would sign it as their own statement"
        }
    }
}

/// The student's own commitment a steelman session takes aim at (§14.4).
struct SteelmanTarget: Hashable {
    let claim: String
    let ontologyId: String?
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
    /// Standalone starts (§13.1): the student-picked professor
    /// (argumentClinic; dailyQuestion derives it from the question).
    var personaId: String?
    /// dailyQuestion start (§13.2): tap + local date collected FIRST, one
    /// round trip; `userText` carries the optional one-sentence why.
    var questionId: String?
    var optionId: String?
    var localDate: String?
    /// Weekly drop start (§14.3): the server loads the spec from `drops` and
    /// runs the standalone thoughtExperiment kind against it.
    var dropId: String?
    /// steelman start (§14.4): the student's own commitment under
    /// examination; `targetOntologyId` only when the claim is canonical.
    var targetClaim: String?
    var targetOntologyId: String?
    /// practice start extras (§15.3): the mode and the rotated exercise.
    /// The persona is forced to bede server-side.
    var mode: String?
    var exerciseId: String?

    static func start(enrollmentId: String, kind: SessionKind, unit: Int,
                      essayBody: String? = nil) -> SessionRequest {
        SessionRequest(action: "start", sessionId: nil, enrollmentId: enrollmentId,
                       kind: kind, unit: unit, userText: nil,
                       userAnnotations: nil, essayBody: essayBody,
                       nodeId: nil, choice: nil)
    }

    /// §13.1 standalone start (argumentClinic): no enrollment; the session
    /// binds to the user and the picked persona.
    static func startStandalone(kind: SessionKind, personaId: String) -> SessionRequest {
        SessionRequest(action: "start", sessionId: nil, enrollmentId: nil,
                       kind: kind, unit: nil, userText: nil,
                       userAnnotations: nil, essayBody: nil,
                       nodeId: nil, choice: nil, personaId: personaId)
    }

    /// §13.2 dailyQuestion start — the whole ritual in one request: the
    /// server validates the option, records the answer, writes the `lean`
    /// commitment deterministically, and the professor replies once.
    static func startDailyQuestion(questionId: String, optionId: String,
                                   localDate: String,
                                   sentence: String?) -> SessionRequest {
        SessionRequest(action: "start", sessionId: nil, enrollmentId: nil,
                       kind: .dailyQuestion, unit: nil, userText: sentence,
                       userAnnotations: nil, essayBody: nil,
                       nodeId: nil, choice: nil,
                       questionId: questionId, optionId: optionId,
                       localDate: localDate)
    }

    /// §14.3 weekly-drop start: the drop RUNS the existing thoughtExperiment
    /// kind as a standalone session; the server loads the spec from `drops`
    /// and stamps `state.dropId`.
    static func startDrop(dropId: String, localDate: String,
                          personaId: String) -> SessionRequest {
        SessionRequest(action: "start", sessionId: nil, enrollmentId: nil,
                       kind: .thoughtExperiment, unit: nil, userText: nil,
                       userAnnotations: nil, essayBody: nil,
                       nodeId: nil, choice: nil, personaId: personaId,
                       localDate: localDate, dropId: dropId)
    }

    /// §14.4 steelman start: standalone, aimed at one of the student's own
    /// live commitments. Default persona whitmore.
    static func startSteelman(targetClaim: String, targetOntologyId: String?,
                              personaId: String) -> SessionRequest {
        SessionRequest(action: "start", sessionId: nil, enrollmentId: nil,
                       kind: .steelman, unit: nil, userText: nil,
                       userAnnotations: nil, essayBody: nil,
                       nodeId: nil, choice: nil, personaId: personaId,
                       targetClaim: targetClaim,
                       targetOntologyId: targetOntologyId)
    }

    /// §15.2 newsRead start: nothing beyond localDate (+ the optional
    /// student-picked professor) — the server owns the weekly brief.
    static func startNewsRead(localDate: String,
                              personaId: String?) -> SessionRequest {
        SessionRequest(action: "start", sessionId: nil, enrollmentId: nil,
                       kind: .newsRead, unit: nil, userText: nil,
                       userAnnotations: nil, essayBody: nil,
                       nodeId: nil, choice: nil, personaId: personaId,
                       localDate: localDate)
    }

    /// §15.3 practice start: mode + exerciseId + localDate; the server runs
    /// the Stoic wing with Bede, always (evening derives `examen` itself).
    static func startPractice(mode: PracticeMode, exerciseId: String?,
                              localDate: String) -> SessionRequest {
        SessionRequest(action: "start", sessionId: nil, enrollmentId: nil,
                       kind: .practice, unit: nil, userText: nil,
                       userAnnotations: nil, essayBody: nil,
                       nodeId: nil, choice: nil,
                       localDate: localDate,
                       mode: mode.rawValue, exerciseId: exerciseId)
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
