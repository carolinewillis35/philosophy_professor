import Foundation

/// Scripted professor for offline / demo mode. Speaks the same
/// `AsyncStream<SessionEvent>` protocol as `LiveSessionClient`, so the whole
/// session UI works without a backend. The scripts are Academy faculty on
/// Plato's *Republic* (Jowett); every citation quote is a verbatim substring
/// of the bundled `republic-jowett` passages/chapters, mirroring the
/// server-side RAG guarantee.
final class MockSessionClient: SessionClient {

    private var seminarTurn = 0
    private var lectureSegment = 0
    private var chatTurn = 0
    private var elenchusTurn = 0
    private var experimentTurn = 0
    private var interrogationTurn = 0
    private var labTurn = 0
    private var pumpFired = false

    private let assignmentId: String
    /// The current course unit, so the scripted professor can lean on the
    /// authored specs (§12.5) exactly as the engine's kind registry does.
    private let unit: Unit?

    init(assignmentId: String = "wij-u1-response", unit: Unit? = nil) {
        self.assignmentId = assignmentId
        self.unit = unit
    }

    func send(_ request: SessionRequest) -> AsyncStream<SessionEvent> {
        let step = scriptedStep(for: request)
        let isStart = request.action == "start"
        let kind = request.kind
        return AsyncStream { continuation in
            let task = Task {
                if isStart {
                    continuation.yield(.session(
                        sessionId: UUID().uuidString, kind: kind, unit: request.unit ?? 0))
                }
                // Stream `say` in small deltas, like the server scanning
                // partial JSON for the `say` field.
                for delta in Self.deltas(of: step.envelope.say) {
                    try Task.checkCancellation()
                    try? await Task.sleep(nanoseconds: 24_000_000)
                    continuation.yield(.sayDelta(delta))
                }
                try Task.checkCancellation()
                try? await Task.sleep(nanoseconds: 150_000_000)
                continuation.yield(.envelope(step.envelope))
                continuation.yield(.done)
                continuation.finish()
            }
            continuation.onTermination = { _ in task.cancel() }
        }
    }

    private static func deltas(of say: String) -> [String] {
        var deltas: [String] = []
        var current = ""
        for word in say.split(separator: " ", omittingEmptySubsequences: false) {
            current += (current.isEmpty ? "" : " ") + word
            if current.count > 14 {
                deltas.append(deltas.isEmpty ? current : " " + current)
                current = ""
            }
        }
        if !current.isEmpty { deltas.append(deltas.isEmpty ? current : " " + current) }
        return deltas
    }

    // MARK: - Verbatim Republic quotes (exact substrings of bundled passages)

    private enum Quote {
        /// republic-jowett:0:30 — Socrates turns Cephalus's piety into a definition.
        static let cephalus = Citation(
            passageId: "republic-jowett:0:30",
            quote: "but as concerning justice, what is it?—to speak the truth and to pay your debts—no more than this? And even to this are there not exceptions?",
            why: "Socrates distills Cephalus into the session's first definition — and immediately doubts it.")

        /// republic-jowett:0:35 — the deposit of arms counterexample.
        static let madman = Citation(
            passageId: "republic-jowett:0:35",
            quote: "he certainly does not mean, as we were just now saying, that I ought to return a deposit of arms or of anything else to one who asks for it when he is not in his right senses; and yet a deposit cannot be denied to be a debt.",
            why: "The classical counterexample: paying what is owed can be plainly unjust.")

        /// republic-jowett:0:140 — ought the just injure anyone at all?
        static let injure = Citation(
            passageId: "republic-jowett:0:140",
            quote: "But ought the just to injure any one at all?",
            why: "The question that dismantles 'help friends, harm enemies.'")

        /// republic-jowett:0:211 — Socrates isolates Thrasymachus's addition.
        static let stronger = Citation(
            passageId: "republic-jowett:0:211",
            quote: "we are both agreed that justice is interest of some sort, but you go on to say ‘of the stronger’; about this addition I am not so sure, and must therefore consider further.",
            why: "The premise under inspection: the addition 'of the stronger.'")

        /// republic-jowett:1:16 — Glaucon states the Gyges wager.
        static let gyges = Citation(
            passageId: "republic-jowett:1:16",
            quote: "then we shall discover in the very act the just and unjust man to be proceeding along the same road, following their interest, which all natures deem to be their good, and are only diverted into the path of justice by the force of law.",
            why: "Glaucon's wager, which your choices just tested.")

        /// republic-jowett:3:250 — justice as each doing their own business.
        static let ownBusiness = Citation(
            passageId: "republic-jowett:3:250",
            quote: "when the trader, the auxiliary, and the guardian each do their own business, that is justice, and will make the city just.",
            why: "The city-side conclusion the analogy must carry into the soul.")

        /// Known source citations for the argument labs, keyed by passage id.
        static func forPassage(_ id: String) -> Citation? {
            switch id {
            case "republic-jowett:0:30": return cephalus
            case "republic-jowett:0:35": return madman
            case "republic-jowett:0:140": return injure
            case "republic-jowett:0:198", "republic-jowett:0:211": return stronger
            case "republic-jowett:1:16": return gyges
            case "republic-jowett:3:250", "republic-jowett:3:367": return ownBusiness
            default: return nil
            }
        }
    }

    // MARK: - Script routing

    private struct Step { let envelope: Envelope }

    private func scriptedStep(for request: SessionRequest) -> Step {
        switch request.kind {
        case .seminar, .closeReading:
            defer { seminarTurn += 1 }
            return seminarStep(seminarTurn)
        case .lecture:
            defer { lectureSegment += 1 }
            return lectureStep(lectureSegment)
        case .essay:
            return essayStep(essayBody: request.essayBody ?? "")
        case .officeHours, .quiz:
            defer { chatTurn += 1 }
            return officeHoursStep(chatTurn)
        case .elenchus:
            defer { elenchusTurn += 1 }
            return elenchusStep(elenchusTurn, userText: request.userText)
        case .thoughtExperiment:
            return thoughtExperimentStep(request)
        case .argumentLab:
            defer { labTurn += 1 }
            return argumentLabStep(labTurn)
        }
    }

    // MARK: - Elenchus (Prof. Vlachos, "What is justice?", §12.1)

    private var elenchusSpec: ElenchusSpec? { unit?.elenchusSpecs?.first }

    private func elenchusStep(_ turn: Int, userText: String?) -> Step {
        let opening = elenchusSpec?.openingQuestion ?? "What is justice?"
        switch turn {
        case 0:
            return Step(envelope: Envelope(
                say: "Sit. I have one question tonight and I intend to lose gracefully if you can survive it: \(opening.lowercased().hasSuffix("?") ? opening : opening + "?") Cephalus thought he knew, and he was the happiest man in the room. Give me your answer plainly — not a book's answer, yours. We will see together how long it stands.",
                citations: [Quote.cephalus],
                uiHints: UIHints(checkInQuestion: opening)))
        case 1:
            return Step(envelope: Envelope(
                say: "Good — you said it out loud, which already puts you ahead of most of the company at the Piraeus. Now tighten it. A thesis is a flag; a definition is a fence. Say precisely what justice *is*, in one sentence, such that everything just falls inside your fence and nothing unjust does.",
                stateOps: [
                    .recordThesis(thesis: userText ?? "The student's opening position on justice."),
                    .advancePhase
                ],
                uiHints: UIHints(checkInQuestion: "State it as a definition: justice is…")))
        case 2:
            return Step(envelope: Envelope(
                say: "A clean fence. Let us walk its perimeter. A friend, sane, leaves his weapons with you; he returns raving and demands them back. Returning what is owed — your fence says this is just. Do you hand a madman his sword? If not, something just slipped outside the fence. Repair it or replace it.",
                citations: [Quote.madman],
                stateOps: [
                    .reviseDefinition(definition: userText ?? "The student's first definition."),
                    .advancePhase
                ],
                uiHints: UIHints(checkInQuestion: "Does your definition survive the madman's weapon?")))
        case 3:
            return Step(envelope: Envelope(
                say: "You patched it — most people do, and the patch is usually Polemarchus's: good to friends, harm to enemies, each getting what they deserve. But watch the board. We misjudge our friends; and harming a man makes him worse, not better. Can justice be a craft whose product is injustice? Answer that, and mind the fence while you do — it is moving.",
                citations: [Quote.injure],
                stateOps: [
                    .reviseDefinition(definition: userText ?? "The student's revised definition."),
                    .advancePhase
                ],
                uiHints: UIHints(checkInQuestion: "Can the just make anyone worse and remain just?")))
        case 4:
            return Step(envelope: Envelope(
                say: "Stop. Look at what happened tonight, because it is the opposite of failure. You walked in with a definition; we now know it dies to a madman's sword. You revised; the revision dies to a misjudged friend. This is aporia — the honest wall. You have not learned what justice is, but you have learned two things it is not, and you learned them from your own mouth, not mine. Tell me plainly: which of your definitions do you mourn, and what exactly killed it?",
                stateOps: [.declareOutcome(outcome: .aporia)],
                uiHints: UIHints(checkInQuestion: elenchusSpec?.reflectionPrompt ?? "Which definition died, and what killed it?")))
        default:
            return Step(envelope: Envelope(
                say: "That is a real reflection — you named the corpse and the weapon. Keep both; Book II begins where your fence fell. Socrates spent his whole life at this wall and called it the beginning of wisdom. We are done for tonight.",
                stateOps: [
                    .writeMemory(note: "Survived first aporia without retreating to 'it's all relative'; revises definitions rather than abandoning the question."),
                    .completeSession
                ],
                uiHints: UIHints(endOfSession: true)))
        }
    }

    // MARK: - Thought experiment (authored nodes client-side, §12.1 / A10)

    private var experimentSpec: ThoughtExperimentSpec? { unit?.thoughtExperiments?.first }

    private func thoughtExperimentStep(_ request: SessionRequest) -> Step {
        // Run phase: the client rendered the node and sent {nodeId, choice}.
        if let nodeId = request.nodeId, let choice = request.choice, let spec = experimentSpec {
            let nextNodeId = spec.node(nodeId)?.options?.first { $0.label == choice }?.next
            let nextNode = nextNodeId.flatMap { spec.node($0) }
            var ops: [StateOp] = [.recordChoice(nodeId: nodeId, choice: choice)]

            if let nextNode, nextNode.isTerminal {
                // Branches exhausted -> interrogation (§12.1).
                ops.append(.advancePhase)
                interrogationTurn = 0
                return Step(envelope: Envelope(
                    say: "Hold there — that is an ending, and endings are where the thinking starts. \(spec.interrogation.first ?? "Why that road and not the other?")",
                    stateOps: ops))
            }
            // Fire an authored intuition pump when one is waiting past this node.
            if !pumpFired, let nextNodeId,
               let pump = spec.pumps?.first(where: { $0.afterNode == nextNodeId }) {
                pumpFired = true
                ops.append(.applyPump(pumpId: pump.id))
                return Step(envelope: Envelope(
                    say: "Before you settle in — the dial turns. Same case, one screw tightened. Does your answer hold, or was it calibrated to the easier numbers?",
                    stateOps: ops))
            }
            return Step(envelope: Envelope(
                say: "Noted — no commentary yet; the case is not done with you. Keep choosing.",
                stateOps: ops))
        }

        // Non-choice turns: start, then interrogation -> debrief.
        defer { experimentTurn += 1 }
        let spec = experimentSpec
        switch experimentTurn {
        case 0:
            return Step(envelope: Envelope(
                say: "No lecture tonight. A case instead — \(spec?.title ?? "an old one"), and it is not hypothetical to the person inside it, which for the next while is you. Read it slowly. Then choose; the choosing is the argument."))
        default:
            defer { interrogationTurn += 1 }
            let questions = spec?.interrogation ?? []
            if interrogationTurn == 0, questions.count > 1 {
                return Step(envelope: Envelope(
                    say: "Say more than that — you were the one wearing it. \(questions[interrogationTurn + 1])",
                    uiHints: UIHints(checkInQuestion: questions[interrogationTurn + 1])))
            }
            return Step(envelope: Envelope(
                say: "Enough. Here is what the case was for: Glaucon deleted detection to see what your justice is made of, and your path through it is now evidence — your own, on the table. Whether it confirmed his wager or beat it, you can no longer claim the question is academic. \(spec?.philosophicalPayload.components(separatedBy: ". ").first.map { $0 + "." } ?? "")",
                citations: [Quote.gyges],
                stateOps: [
                    .advancePhase,
                    .writeMemory(note: "Ring of Gyges: chose deliberately and defended the choice under the pump; does not hide behind 'it depends.'"),
                    .completeSession
                ],
                uiHints: UIHints(endOfSession: true)))
        }
    }

    // MARK: - Argument lab (map renders client-side, §12.1 / A11)

    private var argumentSpec: ArgumentSpec? { unit?.argumentLabs?.first }

    private func argumentLabStep(_ turn: Int) -> Step {
        let spec = argumentSpec
        let isHunt = spec?.mode == .hunt
        let sourceCitation = spec?.source.passageIds.compactMap { Quote.forPassage($0) }.first
        switch turn {
        case 0:
            let question = spec?.elicitationQuestions.first
                ?? "Walk the premises to the conclusion. Where does the walk stop?"
            return Step(envelope: Envelope(
                say: isHunt
                    ? "The argument is on the table — \(spec?.title ?? "the reconstruction"), premises numbered, conclusion at the bottom. One premise is missing: the arguer never said it, and the argument does not go through without it. It is the dashed slot. \(question)"
                    : "The argument is on the table — \(spec?.title ?? "the reconstruction"), premises numbered, conclusion at the bottom. I have greyed one premise out. \(question)",
                citations: sourceCitation.map { [$0] } ?? [],
                stateOps: [.advancePhase],
                uiHints: UIHints(checkInQuestion: question)))
        case 1:
            if isHunt {
                let hidden = spec?.premises.first { $0.id == spec?.hiddenPremiseId }
                return Step(envelope: Envelope(
                    say: "There it is — you found the load-bearing silence. Stated aloud: \(hidden?.text ?? "the premise the arguer could not afford to say."). Notice it was never argued for, only leaned on; the premise an arguer never says is usually the one he cannot afford to say. Now: would the arguer accept it if you read it back to him?",
                    stateOps: [
                        .recordHuntResult(found: true, attempts: 1),
                        .advancePhase
                    ],
                    uiHints: UIHints(checkInQuestion: "Would he accept the premise if you read it to him?")))
            }
            return Step(envelope: Envelope(
                say: "Exactly — with that premise gone, nothing connects the halves. You have two fine descriptions and no argument; the walk from premises to conclusion stops mid-air. So try the repair: state the missing bridge in your own words, as charitably as you can, and then tell me what it would cost to defend it.",
                stateOps: [.advancePhase],
                uiHints: UIHints(checkInQuestion: "Rebuild the bridge: what premise restores the argument, and at what price?")))
        default:
            return Step(envelope: Envelope(
                say: "Good work at the bench. The lesson travels: \(spec?.pedagogicalPoint.components(separatedBy: ". ").first.map { $0 + "." } ?? "every argument has a premise it is quietly standing on.") Next time you meet an argument in the wild, reconstruct it before you fight it — aim at the joint, not the armor.",
                stateOps: [
                    .writeMemory(note: "Reads argument maps quickly; found the hidden premise on the first pass. Push toward charity in reconstruction."),
                    .completeSession
                ],
                uiHints: UIHints(endOfSession: true)))
        }
    }

    // MARK: - Seminar (Prof. Vlachos on Republic, Book I)

    private func seminarStep(_ turn: Int) -> Step {
        switch turn {
        case 0:
            return Step(envelope: Envelope(
                say: "You did the reading — I will take that on faith, for now. Then you watched Socrates do a curious thing to a kind old man: Cephalus offers piety and comfortable habits, and Socrates hands him back a definition with a crack already showing. Look at the panel. What exactly does Socrates do to Cephalus's answer before he doubts it — and why does he need to do that first?",
                citations: [Quote.cephalus],
                stateOps: [
                    .pushQuestion(question: "What does Socrates do to Cephalus's answer before doubting it?")
                ],
                uiHints: UIHints(checkInQuestion: "What does Socrates do to the answer before he doubts it?")))
        case 1:
            return Step(envelope: Envelope(
                say: "Yes — he *sharpens* it into a definition before he breaks it. You cannot refute a mood; you can refute a fence. Now go one exchange deeper. Polemarchus inherits the argument and Socrates asks him a question that seems almost gentle. Read it in the panel. Why is that little question fatal to 'help friends, harm enemies' — what does it force Polemarchus to say about what justice *produces*?",
                citations: [Quote.injure],
                stateOps: [
                    .requireEvidence(value: true),
                    .setDepth(depth: 1)
                ],
                uiHints: UIHints(checkInQuestion: "Why is 'ought the just to injure any one at all?' fatal?")))
        case 2:
            return Step(envelope: Envelope(
                say: "There it is: if harming makes men worse, then justice-as-harming manufactures injustice, and no craft produces its own opposite. You moved from an impression to a premise, and from a premise to a kill — that is the entire discipline. Before next time, reread Thrasymachus's entrance and mark where his confidence outruns his argument. We are done for today.",
                stateOps: [
                    .writeMemory(note: "Tracks the structure of an exchange well; needs prompting to quote the line rather than summarize it."),
                    .completeSession
                ],
                uiHints: UIHints(endOfSession: true)))
        default:
            return Step(envelope: Envelope(
                say: "We are past time, and past-time thinking is rarely close thinking. Bring the marked passage to office hours.",
                uiHints: UIHints(endOfSession: true)))
        }
    }

    // MARK: - Lecture (Book I: definitions and their funerals)

    private func lectureStep(_ segment: Int) -> Step {
        switch segment {
        case 0:
            return Step(envelope: Envelope(
                say: "Welcome. This course has one question and ten books to fail to answer it in, which tells you something about the question. Tonight, Book I: three definitions of justice will be proposed, and all three will be buried by sunset. The claim I intend to defend is that the burials teach more than the definitions — that watching a definition die, precisely, at the exact sentence where it dies, is the whole method of philosophy. When you are ready, we go to the text.",
                stateOps: [.advanceSegment]))
        case 1:
            return Step(envelope: Envelope(
                say: "Take the strongest corpse: Thrasymachus. 'Justice is the interest of the stronger' — a definition with teeth, and Socrates does not laugh at it. Watch instead what he isolates in the panel: not the whole claim, only the *addition*. This is the surgeon's habit — agree to everything you can, so that what remains is exactly the load-bearing part. Before I go on: which premise does the addition smuggle in about rulers, and what happens if a ruler can be wrong?",
                citations: [Quote.stronger],
                stateOps: [.advanceSegment],
                uiHints: UIHints(checkInQuestion: "What must be true of rulers for 'of the stronger' to hold?")))
        default:
            return Step(envelope: Envelope(
                say: "Hold on to the surgeon's habit — isolate the addition, demand the unstated premise — because Book II will aim it at Socrates himself. Your work before seminar: find the sentence in Book I where each definition dies, and copy it out by hand. Not the paragraph. The sentence. Class dismissed.",
                stateOps: [.advanceSegment, .completeSession],
                uiHints: UIHints(endOfSession: true)))
        }
    }

    // MARK: - Essay grading

    private func essayStep(essayBody: String) -> Step {
        guard !essayBody.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty else {
            // Guardrail (CONTRACTS §11): grading requires the student's draft.
            return Step(envelope: Envelope(
                say: "I grade drafts, not intentions. Write the response — imperfect is expected, absent is not — and send it to me again.",
                uiHints: UIHints(endOfSession: true)))
        }
        let sentences = essayBody
            .replacingOccurrences(of: "\n", with: " ")
            .components(separatedBy: ". ")
            .map { $0.trimmingCharacters(in: .whitespaces) }
            .filter { $0.count > 12 }
        let firstAnchor = sentences.first ?? String(essayBody.prefix(80))
        let midAnchor = sentences.count > 2 ? sentences[sentences.count / 2] : (sentences.last ?? firstAnchor)

        return Step(envelope: Envelope(
            say: "I have read it twice — once as a reader, once as your professor; the two rarely agree, and you should want to know where they differ. The rubric below is filled in honestly rather than kindly. Read the margin comments beside your own sentences, then the two directives. Revise and resubmit: the grade is a photograph, not a portrait, and it can be retaken.",
            stateOps: [
                .recordGrade(GradeRecord(
                    assignmentId: assignmentId,
                    grade: "B+",
                    rubric: [
                        RubricScore(name: "Argument", score: 4, max: 5,
                                    justification: "One real claim, stated early and mostly sustained — displaced twice by summary of the dialogue, but recoverable."),
                        RubricScore(name: "Engagement with the text", score: 3, max: 5,
                                    justification: "You cite the exchange once and then argue from memory of it. Every claim after your second paragraph floats free of the words."),
                        RubricScore(name: "Prose", score: 4, max: 5,
                                    justification: "Clean and mostly unpadded. Two hedges ('perhaps', 'seems to suggest') where you had already earned the assertion.")
                    ],
                    marginComments: [
                        MarginComment(anchor: firstAnchor,
                                      comment: "A promising opening — but it names a conclusion before it earns a premise. Invert the order: premise first, verdict second."),
                        MarginComment(anchor: midAnchor,
                                      comment: "Here you drift into summarizing the dialogue. Quote the sentence where the definition dies; make the text carry your point.")
                    ],
                    directives: [
                        "Re-anchor every paragraph to a quoted line or a numbered premise — if a paragraph rests on neither, it goes.",
                        "Cut both hedges and defend the assertion they were hiding; you have the argument for it."
                    ]))
            ],
            uiHints: UIHints(endOfSession: true)))
    }

    // MARK: - Office hours

    private func officeHoursStep(_ turn: Int) -> Step {
        if turn == 0 {
            return Step(envelope: Envelope(
                say: "Office hours. No agenda but yours — though if you have none, I will supply one: which of your beliefs has this week's reading made more expensive to hold? Ask me anything; I will not tell you what to think, but I will happily show you what your thinking commits you to."))
        }
        return Step(envelope: Envelope(
            say: "A fair question, and I notice you asked it instead of answering it — the oldest trick in this building, and I invented it. My advice is unvaried because it is correct: state your position in one sentence, find the strongest thing that could be said against it, and bring both with you next time. A position without its best objection is a slogan."))
    }
}
