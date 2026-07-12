import Foundation

// MARK: - The envelope (CONTRACTS §5, §12.2)

/// Every professor turn ends with one of these. The client renders streamed
/// `say` deltas immediately and reconciles against `envelope.say` on arrival.
struct Envelope: Decodable {
    let say: String
    let citations: [Citation]
    let stateOps: [StateOp]
    let uiHints: UIHints
    /// OPTIONAL Commitment Map writes (§12.2). Validated and persisted
    /// server-side; the client decodes but never acts on them.
    let commitmentOps: [CommitmentOp]

    init(say: String, citations: [Citation] = [], stateOps: [StateOp] = [],
         uiHints: UIHints = UIHints(), commitmentOps: [CommitmentOp] = []) {
        self.say = say
        self.citations = citations
        self.stateOps = stateOps
        self.uiHints = uiHints
        self.commitmentOps = commitmentOps
    }

    private enum CodingKeys: String, CodingKey { case say, citations, stateOps, uiHints, commitmentOps }

    init(from decoder: Decoder) throws {
        let c = try decoder.container(keyedBy: CodingKeys.self)
        say = try c.decode(String.self, forKey: .say)
        citations = try c.decodeIfPresent([Citation].self, forKey: .citations) ?? []
        stateOps = try c.decodeIfPresent([StateOp].self, forKey: .stateOps) ?? []
        uiHints = try c.decodeIfPresent(UIHints.self, forKey: .uiHints) ?? UIHints()
        commitmentOps = try c.decodeIfPresent([CommitmentOp].self, forKey: .commitmentOps) ?? []
    }
}

/// A verbatim, RAG-verified quotation. The ONLY thing the client may render
/// with quote styling (CONTRACTS §9).
struct Citation: Decodable, Hashable, Identifiable {
    let passageId: String
    let quote: String
    let why: String

    var id: String { passageId + "|" + quote }

    init(passageId: String, quote: String, why: String) {
        self.passageId = passageId
        self.quote = quote
        self.why = why
    }

    /// Passage IDs are `"{bookID}:{ch}:{para}"` (CONTRACTS §2).
    var bookID: String? { components?.bookID }
    var chapterIndex: Int? { components?.ch }

    private var components: (bookID: String, ch: Int)? {
        let parts = passageId.split(separator: ":")
        guard parts.count == 3, let ch = Int(parts[1]) else { return nil }
        return (String(parts[0]), ch)
    }
}

struct UIHints: Decodable, Hashable {
    let showPassagePicker: Bool
    let checkInQuestion: String?
    let endOfSession: Bool

    init(showPassagePicker: Bool = false, checkInQuestion: String? = nil, endOfSession: Bool = false) {
        self.showPassagePicker = showPassagePicker
        self.checkInQuestion = checkInQuestion
        self.endOfSession = endOfSession
    }

    private enum CodingKeys: String, CodingKey { case showPassagePicker, checkInQuestion, endOfSession }

    init(from decoder: Decoder) throws {
        let c = try decoder.container(keyedBy: CodingKeys.self)
        showPassagePicker = try c.decodeIfPresent(Bool.self, forKey: .showPassagePicker) ?? false
        checkInQuestion = try c.decodeIfPresent(String.self, forKey: .checkInQuestion)
        endOfSession = try c.decodeIfPresent(Bool.self, forKey: .endOfSession) ?? false
    }
}

// MARK: - Commitment ops (CONTRACTS §12.2) — decoded, never acted on

/// One Commitment Map write. The session function validates and persists
/// these (service role); the client's Worldview page reads the resulting
/// rows, so nothing here mutates client state.
struct CommitmentOp: Decodable, Hashable {
    let op: String            // assert|lean|explore|affirm|abandon
    let claim: String
    let domain: String        // ethics|epistemology|metaphysics|mind|political|aesthetics
    let ontologyId: String?   // present only when confidently matched
    let evidence: String

    private enum CodingKeys: String, CodingKey { case op, claim, domain, ontologyId, evidence }

    init(op: String, claim: String, domain: String, ontologyId: String? = nil, evidence: String) {
        self.op = op
        self.claim = claim
        self.domain = domain
        self.ontologyId = ontologyId
        self.evidence = evidence
    }

    init(from decoder: Decoder) throws {
        let c = try decoder.container(keyedBy: CodingKeys.self)
        op = try c.decode(String.self, forKey: .op)
        claim = try c.decode(String.self, forKey: .claim)
        domain = try c.decode(String.self, forKey: .domain)
        ontologyId = try c.decodeIfPresent(String.self, forKey: .ontologyId)
        evidence = try c.decodeIfPresent(String.self, forKey: .evidence) ?? ""
    }
}

// MARK: - State ops, discriminated on "op"

enum StateOp: Decodable {
    case advanceSegment
    case pushQuestion(question: String)
    case popQuestion
    case setDepth(depth: Int)
    case requireEvidence(value: Bool)
    case recordGrade(GradeRecord)
    case writeMemory(note: String)
    case completeSession
    // Generic phase step for the multi-phase kinds (CONTRACTS §11.1/§12.1).
    case advancePhase
    // elenchus (§12.1)
    case recordThesis(thesis: String)
    case reviseDefinition(definition: String)
    case declareOutcome(outcome: ElenchusOutcome)
    // thoughtExperiment (§12.1)
    case recordChoice(nodeId: String, choice: String)
    case applyPump(pumpId: String)
    // argumentLab (§12.1)
    case recordHuntResult(found: Bool, attempts: Int)
    // argumentClinic (§13.3) — the professor builds the user's map
    // incrementally; the client folds these into ClinicMapState.
    case setConclusion(text: String)
    case addPremise(ArgumentSpec.Premise)
    case revisePremise(id: String, text: String)
    case markCrux(id: String, kind: ClinicCruxKind)

    private enum CodingKeys: String, CodingKey {
        case op, question, depth, value, note, thesis, definition, outcome,
             nodeId, choice, pumpId, found, attempts,
             text, id, stated, supports, kind
    }

    init(from decoder: Decoder) throws {
        let c = try decoder.container(keyedBy: CodingKeys.self)
        let op = try c.decode(String.self, forKey: .op)
        switch op {
        case "advanceSegment":
            self = .advanceSegment
        case "pushQuestion":
            self = .pushQuestion(question: try c.decode(String.self, forKey: .question))
        case "popQuestion":
            self = .popQuestion
        case "setDepth":
            self = .setDepth(depth: try c.decode(Int.self, forKey: .depth))
        case "requireEvidence":
            self = .requireEvidence(value: try c.decode(Bool.self, forKey: .value))
        case "recordGrade":
            self = .recordGrade(try GradeRecord(from: decoder))
        case "writeMemory":
            self = .writeMemory(note: try c.decode(String.self, forKey: .note))
        case "completeSession":
            self = .completeSession
        case "advancePhase":
            self = .advancePhase
        case "recordThesis":
            self = .recordThesis(thesis: try c.decode(String.self, forKey: .thesis))
        case "reviseDefinition":
            self = .reviseDefinition(definition: try c.decode(String.self, forKey: .definition))
        case "declareOutcome":
            self = .declareOutcome(outcome: try c.decode(ElenchusOutcome.self, forKey: .outcome))
        case "recordChoice":
            self = .recordChoice(nodeId: try c.decode(String.self, forKey: .nodeId),
                                 choice: try c.decode(String.self, forKey: .choice))
        case "applyPump":
            self = .applyPump(pumpId: try c.decode(String.self, forKey: .pumpId))
        case "recordHuntResult":
            self = .recordHuntResult(found: try c.decode(Bool.self, forKey: .found),
                                     attempts: try c.decodeIfPresent(Int.self, forKey: .attempts) ?? 0)
        case "setConclusion":
            self = .setConclusion(text: try c.decode(String.self, forKey: .text))
        case "addPremise":
            self = .addPremise(ArgumentSpec.Premise(
                id: try c.decode(String.self, forKey: .id),
                text: try c.decode(String.self, forKey: .text),
                stated: try c.decodeIfPresent(Bool.self, forKey: .stated) ?? true,
                supports: try c.decodeIfPresent(String.self, forKey: .supports) ?? "c"))
        case "revisePremise":
            self = .revisePremise(id: try c.decode(String.self, forKey: .id),
                                  text: try c.decode(String.self, forKey: .text))
        case "markCrux":
            self = .markCrux(id: try c.decode(String.self, forKey: .id),
                             kind: try c.decode(ClinicCruxKind.self, forKey: .kind))
        default:
            throw DecodingError.dataCorruptedError(
                forKey: .op, in: c,
                debugDescription: "Unknown stateOp \"\(op)\"")
        }
    }
}

/// Payload of `{"op": "recordGrade", ...}` — rubric feedback for an essay.
struct GradeRecord: Decodable, Hashable {
    let assignmentId: String
    let grade: String
    let rubric: [RubricScore]
    let marginComments: [MarginComment]
    let directives: [String]

    init(assignmentId: String, grade: String, rubric: [RubricScore],
         marginComments: [MarginComment], directives: [String]) {
        self.assignmentId = assignmentId
        self.grade = grade
        self.rubric = rubric
        self.marginComments = marginComments
        self.directives = directives
    }

    private enum CodingKeys: String, CodingKey {
        case assignmentId, grade, rubric, marginComments, directives
    }

    init(from decoder: Decoder) throws {
        let c = try decoder.container(keyedBy: CodingKeys.self)
        assignmentId = try c.decode(String.self, forKey: .assignmentId)
        grade = try c.decode(String.self, forKey: .grade)
        rubric = try c.decodeIfPresent([RubricScore].self, forKey: .rubric) ?? []
        marginComments = try c.decodeIfPresent([MarginComment].self, forKey: .marginComments) ?? []
        directives = try c.decodeIfPresent([String].self, forKey: .directives) ?? []
    }
}

struct RubricScore: Decodable, Hashable, Identifiable {
    let name: String
    let score: Double
    let max: Double
    let justification: String
    var id: String { name }

    init(name: String, score: Double, max: Double, justification: String) {
        self.name = name
        self.score = score
        self.max = max
        self.justification = justification
    }
}

/// Comment anchored to an exact sentence of the student's essay.
struct MarginComment: Decodable, Hashable, Identifiable {
    let anchor: String
    let comment: String
    var id: String { anchor }

    init(anchor: String, comment: String) {
        self.anchor = anchor
        self.comment = comment
    }
}
