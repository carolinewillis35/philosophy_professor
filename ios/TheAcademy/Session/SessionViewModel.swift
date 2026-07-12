import Foundation
import Observation

/// Drives one live or mock session: consumes the `AsyncStream<SessionEvent>`,
/// renders `say` deltas as they arrive, and reconciles the streamed text with
/// `envelope.say` when the envelope lands (CONTRACTS §4). For the Academy
/// kinds (§12.1) it mirrors the server's session state client-side by
/// applying the kind-specific stateOps, so the phase strip, node cards, and
/// argument map track the engine.
@Observable
@MainActor
final class SessionViewModel {

    /// nil for the standalone kinds (§13.1) — no course, no unit doc.
    let course: Course?
    let unit: Int
    let kind: SessionKind
    let enrollmentId: String
    /// The professor in the room: the course's persona, or the one the
    /// student picked for a standalone session (§13.1).
    let personaId: String?
    /// Non-nil when this session runs a weekly drop (§14.3): the standalone
    /// thoughtExperiment kind against the drop's own spec.
    let drop: Drop?
    /// Non-nil for steelman sessions (§14.4): the student's own live
    /// commitment the exercise takes aim at.
    let steelmanTarget: SteelmanTarget?

    private let client: SessionClient

    // Voice mode: professor turns are spoken from the streamed deltas only —
    // envelope reconciliation never re-speaks (no double-speak), and only the
    // `say` prose is voiced, never citations (DECISIONS #11).
    private let voice: ProfessorVoice?
    private let voiceEnabled: () -> Bool

    private(set) var messages: [TurnMessage] = []
    private(set) var sessionId: String?
    private(set) var isStreaming = false
    private(set) var hasStarted = false
    private(set) var checkInQuestion: String?
    private(set) var showPassagePicker = false
    private(set) var endOfSession = false
    private(set) var gradeRecord: GradeRecord?
    private(set) var errorMessage: String?
    /// §4.3 budget notice — rendered as a gentle in-session card, not an alert.
    private(set) var budgetNotice: String?

    // MARK: Academy kind state (client mirror of sessions.state, §12.1)

    private(set) var elenchusState = ElenchusState()
    private(set) var experimentState = ThoughtExperimentState()
    private(set) var labState = ArgumentLabState()
    /// argumentClinic (§13.3): the user's map, folded from stateOps.
    private(set) var clinicState = ClinicMapState()
    /// steelman (§14.4): phase + level, folded from advancePhase and
    /// recordSteelmanScore.
    private(set) var steelmanState = SteelmanState()
    /// The verdict's one-sentence justification — display only; the state
    /// shape itself mirrors the server's.
    private(set) var steelmanJustification: String?

    var inputText = ""

    init(course: Course?, unit: Int, kind: SessionKind,
         personaId: String? = nil,
         enrollmentId: String, client: SessionClient,
         drop: Drop? = nil,
         steelmanTarget: SteelmanTarget? = nil,
         voice: ProfessorVoice? = nil,
         voiceEnabled: @escaping () -> Bool = { false }) {
        self.course = course
        self.unit = unit
        self.kind = kind
        self.personaId = personaId ?? course?.personaId
        self.enrollmentId = enrollmentId
        self.client = client
        self.drop = drop
        self.steelmanTarget = steelmanTarget
        self.voice = voice
        self.voiceEnabled = voiceEnabled

        elenchusState.specId = elenchusSpec?.id
        experimentState.specId = experimentSpec?.id
        experimentState.nodeId = experimentSpec?.startNode?.id ?? "start"
        labState.specId = argumentSpec?.id
        steelmanState.targetClaim = steelmanTarget?.claim
        steelmanState.targetOntologyId = steelmanTarget?.ontologyId
    }

    var currentUnit: Unit? {
        course?.units.first { $0.number == unit + 1 }
    }

    // Authored specs for this unit (§12.5) — the deterministic render
    // sources. A weekly drop carries its own spec (§14.3) and wins.
    var elenchusSpec: ElenchusSpec? { currentUnit?.elenchusSpecs?.first }
    var experimentSpec: ThoughtExperimentSpec? {
        drop?.experiment ?? currentUnit?.thoughtExperiments?.first
    }
    var argumentSpec: ArgumentSpec? { currentUnit?.argumentLabs?.first }

    /// The authored node currently on the table (thoughtExperiment run phase).
    var currentExperimentNode: ThoughtExperimentSpec.Node? {
        experimentSpec?.node(experimentState.nodeId)
    }

    /// The clinic's live map in the shape the deterministic renderer already
    /// consumes (§13.3): the user's argument as a synthesized ArgumentSpec —
    /// same conclusion/premise shape, nothing hidden, nothing removed.
    var clinicSpec: ArgumentSpec? {
        guard kind == .argumentClinic, let conclusion = clinicState.conclusion else { return nil }
        return ArgumentSpec(
            id: "clinic-map", title: "Your argument",
            source: ArgumentSpec.Source(bookID: "", passageIds: []),
            conclusion: ArgumentSpec.Statement(id: "c", text: conclusion),
            premises: clinicState.premises,
            mode: .hunt, hiddenPremiseId: nil, removedPremiseId: nil,
            pedagogicalPoint: "", elicitationQuestions: [], relatedClaims: nil)
    }

    /// Choice buttons replace the keyboard while the branch walk is live.
    var usesChoiceInput: Bool {
        kind == .thoughtExperiment && experimentState.phase == .run && !endOfSession
    }

    /// The node card stays on the table through the run, and the terminal
    /// node (the case's ending) remains visible under interrogation.
    var showsExperimentNode: Bool {
        kind == .thoughtExperiment
            && (experimentState.phase == .run || currentExperimentNode?.isTerminal == true)
    }

    /// Lecture-mode "Continue" affordance (CONTRACTS §9 / SCOPE §3.2.1).
    var canContinueLecture: Bool {
        kind == .lecture && hasStarted && !isStreaming && !endOfSession
    }

    var canSend: Bool {
        hasStarted && !isStreaming && !endOfSession
            && !inputText.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty
    }

    // MARK: intents

    func start(essayBody: String? = nil) async {
        guard !hasStarted else { return }
        hasStarted = true
        let request: SessionRequest
        if let drop {
            // §14.3: the drop runs the thoughtExperiment kind standalone —
            // the start carries dropId + localDate; the server loads the
            // spec from `drops` and the drop's persona.
            request = .startDrop(dropId: drop.id,
                                 localDate: DailyQuestion.localDateString(),
                                 personaId: personaId ?? drop.personaId)
        } else if kind == .steelman {
            // §14.4: aimed at one of the student's own live commitments.
            request = .startSteelman(targetClaim: steelmanTarget?.claim ?? "",
                                     targetOntologyId: steelmanTarget?.ontologyId,
                                     personaId: personaId ?? "whitmore")
        } else if kind.isStandalone {
            // Standalone kinds (§13.1) start with user + persona, no
            // enrollment.
            request = .startStandalone(kind: kind, personaId: personaId ?? "whitmore")
        } else {
            request = .start(enrollmentId: enrollmentId, kind: kind, unit: unit,
                             essayBody: essayBody)
        }
        await consume(client.send(request))
    }

    func sendUserText() async {
        let text = inputText.trimmingCharacters(in: .whitespacesAndNewlines)
        guard !text.isEmpty, !isStreaming else { return }
        stopVoice() // sending interrupts the professor mid-sentence
        inputText = ""
        messages.append(TurnMessage(role: .user, text: text))
        await consume(client.send(.turn(
            sessionId: sessionId ?? "", kind: kind, userText: text)))
    }

    /// Thought-experiment branch tap (§12.1): the choice label becomes the
    /// user's turn text, `{nodeId, choice}` rides along, and the next node
    /// renders from the spec — deterministic, no model in the branch path.
    func selectChoice(_ option: ThoughtExperimentSpec.Option) async {
        guard kind == .thoughtExperiment, !isStreaming,
              experimentState.phase == .run,
              let node = currentExperimentNode else { return }
        stopVoice()
        let fromNodeId = node.id
        messages.append(TurnMessage(role: .user, text: option.label))
        experimentState.path.append(
            ThoughtExperimentChoice(nodeId: fromNodeId, choice: option.label))
        if experimentSpec?.node(option.next) != nil {
            experimentState.nodeId = option.next
        }
        await consume(client.send(.turn(
            sessionId: sessionId ?? "", kind: kind, userText: option.label,
            nodeId: fromNodeId, choice: option.label)))
    }

    func continueLecture() async {
        guard canContinueLecture else { return }
        await consume(client.send(.turn(
            sessionId: sessionId ?? "", kind: kind, userText: nil)))
    }

    /// Silence the professor (leaving the view, mic opening, toggle off).
    func stopVoice() {
        voice?.stopSpeaking()
    }

    // MARK: stream consumption

    private func consume(_ stream: AsyncStream<SessionEvent>) async {
        isStreaming = true
        checkInQuestion = nil
        errorMessage = nil

        var professorIndex: Int?

        for await event in stream {
            switch event {
            case .session(let id, _, _):
                sessionId = id

            case .sayDelta(let delta):
                if professorIndex == nil {
                    messages.append(TurnMessage(role: .professor, text: "", isStreaming: true))
                    professorIndex = messages.count - 1
                }
                if let i = professorIndex {
                    messages[i].text += delta
                }
                if voiceEnabled() {
                    voice?.enqueue(delta: delta)
                }

            case .envelope(let envelope):
                // Reconcile: streamed text is replaced by the authoritative
                // envelope.say; citations become quote panels.
                if professorIndex == nil {
                    messages.append(TurnMessage(role: .professor, text: "", isStreaming: true))
                    professorIndex = messages.count - 1
                }
                if let i = professorIndex {
                    messages[i].text = envelope.say
                    messages[i].citations = envelope.citations
                    messages[i].isStreaming = false
                }
                apply(envelope, professorIndex: professorIndex)
                // Speak only the unspoken tail of the streamed buffer;
                // envelope.say itself is never fed to the voice, so
                // reconciliation cannot double-speak.
                if voiceEnabled() {
                    voice?.flush()
                }

            case .error(let code, let message):
                if code == SessionErrorCode.budgetExceeded {
                    // Daily budget ran out (§4.3): a kind, in-voice note —
                    // never a scary alert, never a hard lockout of the UI.
                    budgetNotice = message
                } else {
                    errorMessage = message
                }
                if let i = professorIndex, messages[i].text.isEmpty {
                    messages.remove(at: i)
                    professorIndex = nil
                }

            case .done:
                break
            }
        }

        if let i = professorIndex, messages.indices.contains(i) {
            messages[i].isStreaming = false
        }
        isStreaming = false
    }

    private func apply(_ envelope: Envelope, professorIndex: Int?) {
        checkInQuestion = envelope.uiHints.checkInQuestion
        showPassagePicker = envelope.uiHints.showPassagePicker
        if envelope.uiHints.endOfSession { endOfSession = true }
        // envelope.commitmentOps are decoded but deliberately unused: the
        // server validates and persists them (§12.2); the client only reads
        // the resulting Worldview rows.

        for op in envelope.stateOps {
            switch op {
            case .recordGrade(let record):
                gradeRecord = record
            case .completeSession:
                endOfSession = true
            case .advancePhase:
                advancePhase()
            case .recordThesis(let thesis):
                elenchusState.thesis = thesis
            case .reviseDefinition(let definition):
                if elenchusState.currentDefinition != nil {
                    elenchusState.revisions += 1
                }
                elenchusState.currentDefinition = definition
            case .declareOutcome(let outcome):
                // The engine forces reflection once an outcome is declared;
                // a session may only complete from reflection (A13).
                elenchusState.outcome = outcome
                elenchusState.phase = .reflection
            case .recordChoice(let nodeId, let choice):
                // Server echo of the client-side walk; guard the duplicate.
                let echo = ThoughtExperimentChoice(nodeId: nodeId, choice: choice)
                if experimentState.path.last != echo {
                    experimentState.path.append(echo)
                }
            case .applyPump(let pumpId):
                if !experimentState.pumpsApplied.contains(pumpId) {
                    experimentState.pumpsApplied.append(pumpId)
                }
                // "The dial turns": the variation card rides on this turn.
                if let i = professorIndex, messages.indices.contains(i) {
                    messages[i].pumpId = pumpId
                }
            case .recordHuntResult(let found, let attempts):
                labState.found = found
                labState.attempts = attempts
            // argumentClinic (§13.3): fold the map ops; the panel re-renders
            // on every mapVersion bump.
            case .setConclusion(let text):
                clinicState.conclusion = text
                clinicState.mapVersion += 1
            case .addPremise(let premise):
                guard clinicState.premises.count < 8,
                      !clinicState.premises.contains(where: { $0.id == premise.id })
                else { break }
                clinicState.premises.append(premise)
                clinicState.mapVersion += 1
            case .revisePremise(let id, let text):
                if let i = clinicState.premises.firstIndex(where: { $0.id == id }) {
                    let old = clinicState.premises[i]
                    clinicState.premises[i] = ArgumentSpec.Premise(
                        id: old.id, text: text, stated: old.stated, supports: old.supports)
                    clinicState.mapVersion += 1
                }
            case .markCrux(let id, let kind):
                if id == "c" || clinicState.premises.contains(where: { $0.id == id }) {
                    clinicState.cruxes[id] = kind
                    clinicState.mapVersion += 1
                }
            // steelman (§14.4): the verdict — debrief is reached ONLY here.
            case .recordSteelmanScore(let level, let justification):
                if steelmanState.level == nil, (1...4).contains(level) {
                    steelmanState.level = level
                    steelmanState.phase = .debrief
                    steelmanJustification = justification.isEmpty ? nil : justification
                }
            case .advanceSegment, .pushQuestion, .popQuestion,
                 .setDepth, .requireEvidence, .writeMemory,
                 .markTensionReconciled:
                // Server-side session state (markTensionReconciled persists
                // to `commitment_tensions`, §14.2 — the Worldview page reads
                // the resulting row); nothing to mirror locally.
                break
            }
        }
    }

    /// Generic phase step (§12.1) resolved against this session's kind.
    private func advancePhase() {
        switch kind {
        case .elenchus:
            // thesis → definition → counterexample ⇄ revision; reflection is
            // reached only via declareOutcome (A13).
            switch elenchusState.phase {
            case .thesis: elenchusState.phase = .definition
            case .definition: elenchusState.phase = .counterexample
            case .counterexample: elenchusState.phase = .revision
            case .revision: elenchusState.phase = .counterexample
            case .reflection: break
            }
        case .thoughtExperiment:
            switch experimentState.phase {
            case .run: experimentState.phase = .interrogation
            case .interrogation: experimentState.phase = .debrief
            case .debrief: break
            }
        case .argumentLab:
            let mode = argumentSpec?.mode ?? .hunt
            switch (labState.phase, mode) {
            case (.mapPresented, .hunt): labState.phase = .hunt
            case (.mapPresented, .collapse): labState.phase = .collapse
            case (.hunt, _): labState.phase = .reveal
            case (.reveal, _), (.collapse, _): labState.phase = .rebuild
            case (.rebuild, _): break
            }
        case .argumentClinic:
            // intake → excavation → map → crux → handback (§13.3).
            let phases = ClinicPhase.allCases
            if let i = phases.firstIndex(of: clinicState.phase),
               i + 1 < phases.count {
                clinicState.phase = phases[i + 1]
            }
        case .steelman:
            // brief → attempt → probe → verdict (§14.4); debrief is reached
            // ONLY through recordSteelmanScore, mirroring the kind's onOps.
            switch steelmanState.phase {
            case .brief: steelmanState.phase = .attempt
            case .attempt: steelmanState.phase = .probe
            case .probe: steelmanState.phase = .verdict
            case .verdict, .debrief: break
            }
        default:
            break
        }
    }
}
