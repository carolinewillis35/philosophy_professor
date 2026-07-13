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
    private var clinicTurn = 0
    private var steelmanTurn = 0
    private var steelmanTarget: String?
    private var pumpFired = false
    private var newsTurn = 0
    private var practiceTurn = 0
    private var reviewTurn = 0
    private var symposiumTurn = 0

    private let assignmentId: String
    /// The current course unit, so the scripted professor can lean on the
    /// authored specs (§12.5) exactly as the engine's kind registry does.
    private let unit: Unit?
    /// A weekly drop's spec (§14.3): the same thoughtExperiment flow run
    /// standalone, the way the server loads the spec from `drops`.
    private let dropSpec: ThoughtExperimentSpec?
    /// The week's brief (§15.2): the mock teaches from it the way the server
    /// hands the cached brief to the kind's instructionBlock.
    private let newsBrief: NewsBrief?
    /// Practice session inputs (§15.3): the mode and the rotated exercise,
    /// the way the server loads the doc from `practice_exercises`.
    private let practiceMode: PracticeMode?
    private let practiceExercise: PracticeExercise?
    private let examenQuestions: [String]
    /// The month's symposium spec (§16.2): the mock speaks the authored
    /// volleys through the speakers[] contract, the way the server hands the
    /// spec to the kind's instructionBlock.
    private let symposiumSpec: SymposiumSpec?

    init(assignmentId: String = "wij-u1-response", unit: Unit? = nil,
         dropSpec: ThoughtExperimentSpec? = nil,
         newsBrief: NewsBrief? = nil,
         practiceMode: PracticeMode? = nil,
         practiceExercise: PracticeExercise? = nil,
         examenQuestions: [String] = Examen.questions,
         symposiumSpec: SymposiumSpec? = nil) {
        self.assignmentId = assignmentId
        self.unit = unit
        self.dropSpec = dropSpec
        self.newsBrief = newsBrief
        self.practiceMode = practiceMode
        self.practiceExercise = practiceExercise
        self.examenQuestions = examenQuestions.count == 3
            ? examenQuestions : Examen.questions
        self.symposiumSpec = symposiumSpec
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
        case .dailyQuestion:
            return dailyQuestionStep(userText: request.userText)
        case .argumentClinic:
            defer { clinicTurn += 1 }
            return clinicStep(clinicTurn)
        case .steelman:
            if request.action == "start" {
                steelmanTarget = request.targetClaim
            }
            defer { steelmanTurn += 1 }
            return steelmanStep(steelmanTurn)
        case .newsRead:
            defer { newsTurn += 1 }
            return newsReadStep(newsTurn)
        case .practice:
            defer { practiceTurn += 1 }
            return practiceStep(practiceTurn, userText: request.userText)
        case .practiceReview:
            defer { reviewTurn += 1 }
            return practiceReviewStep(reviewTurn)
        case .symposium:
            defer { symposiumTurn += 1 }
            return symposiumStep(symposiumTurn, userText: request.userText)
        }
    }

    // MARK: - Symposium (§16.2: question → exchange → your ruling →
    // cross-examination → joint debrief; TWO voices via the speakers[]
    // contract; the authored volleys are the exchange's spine; NO WINNER is
    // ever declared and citations stay empty — no retrieval runs)

    /// Labeled dialogue + its structural mirror: the say text carries
    /// "NAME: …" per the §11.1 convention, speakers[] one entry per voice in
    /// speaking order.
    private func symposiumVoices(_ parts: [(personaId: String, say: String)])
        -> (say: String, speakers: [Speaker]) {
        (parts.map { "\($0.personaId.uppercased()): \($0.say)" }.joined(separator: "\n\n"),
         parts.map { Speaker(personaId: $0.personaId, say: $0.say) })
    }

    /// An authored volley by index, with a crux-anchored fallback for thin
    /// specs — mirroring the kind's "argue from the crux" posture.
    private func symposiumVolley(_ index: Int, spec: SymposiumSpec)
        -> (personaId: String, say: String) {
        if let volleys = spec.volleys, index < volleys.count {
            return (volleys[index].speaker, volleys[index].say)
        }
        let personaId = index.isMultiple(of: 2) ? spec.personaA : spec.personaB
        return (personaId,
                "Hold the crux in view — \(spec.crux) My side of that divide stands; press it where you think it bends.")
    }

    private func symposiumStep(_ turn: Int, userText: String?) -> Step {
        guard let spec = symposiumSpec else {
            // Guardrail parity with kinds_agora: spec missing ⇒ apologize in
            // character and end the session.
            return Step(envelope: Envelope(
                say: "The house apologizes — tonight's question failed to arrive from the archive, and a symposium without its question is only a dinner. We will reconvene when the record is restored.",
                stateOps: [.completeSession],
                uiHints: UIHints(endOfSession: true)))
        }
        switch turn {
        case 0:
            // QUESTION PRESENTED: one voice frames it; both state their
            // one-liners, neutrally — the arguments come next.
            let (say, speakers) = symposiumVoices([
                (spec.personaA,
                 "The question before the house: \(spec.question) Stated as a position, mine is this — \(spec.positionA.label) That is the line I will argue, at full strength, in a moment."),
                (spec.personaB,
                 "And mine — \(spec.positionB.label) Two of us, one question, and no verdict from the chair, tonight or ever: the ruling belongs to you. Interject whenever you like; the floor hears you. First, the arguments.")
            ])
            return Step(envelope: Envelope(say: say, speakers: speakers,
                                           stateOps: [.advancePhase]))
        case 1:
            // EXCHANGE, first volley pair — the authored spine, verbatim.
            let a = symposiumVolley(0, spec: spec)
            let b = symposiumVolley(1, spec: spec)
            let (say, speakers) = symposiumVoices([a, b])
            return Step(envelope: Envelope(say: say, speakers: speakers))
        case 2:
            let a = symposiumVolley(2, spec: spec)
            let b = symposiumVolley(3, spec: spec)
            let (say, speakers) = symposiumVoices([a, b])
            return Step(envelope: Envelope(say: say, speakers: speakers))
        case 3:
            // Third exchange, then both rest — the floor turns to the
            // student (§16.2 adjudication: undecided is a legitimate ruling).
            let a = symposiumVolley(4, spec: spec)
            let b = symposiumVolley(5, spec: spec)
            let (say, speakers) = symposiumVoices([
                a, b,
                (spec.personaA, "I rest."),
                (spec.personaB,
                 "As do I. The floor is yours: rule for one of us, in your own words and with your reason — or remain undecided, which is a ruling too, and the house will respect it without pressure.")
            ])
            return Step(envelope: Envelope(
                say: say, speakers: speakers,
                stateOps: [.advancePhase],
                uiHints: UIHints(checkInQuestion: "Your ruling, and your reason — or an honest 'still undecided.'")))
        case 4:
            // The student rules: record it (side A for the script; their
            // words as the statement) — then the REJECTED side cross-examines
            // the ruling, not the student.
            let statement = userText?.trimmingCharacters(in: .whitespacesAndNewlines) ?? ""
            let (say, speakers) = symposiumVoices([
                (spec.personaB,
                 "So ruled — and a ruling costs two questions, both mine, since it went against me. First: my side's case did not simply vanish because you preferred another; name the exact point in it where, on your telling, the argument fails. Second: if the strongest consideration on my side weighed twice what it does, would your ruling survive — or was it settled before either of us spoke? Defend the ruling or amend it; both are thinking, and I will take either seriously.")
            ])
            return Step(envelope: Envelope(
                say: say, speakers: speakers,
                stateOps: [.recordPosition(
                    side: spec.personaA,
                    statement: statement.isEmpty ? "The student ruled for the first side." : statement)],
                uiHints: UIHints(checkInQuestion: "Defend the ruling — or amend it.")))
        default:
            // JOINT DEBRIEF: what each side sees and what it misses — from
            // its own advocate. No winner, no consolation, no split-the-
            // difference evasion (§16.6).
            let (say, speakers) = symposiumVoices([
                (spec.personaA,
                 "You defended it under fire, which is the only way a ruling becomes yours. The debrief, then, and we both speak against ourselves. What my side sees: \(spec.positionA.label) What it misses, named by its own advocate: the cost my colleague kept pointing at is real, and my account pays it — quietly, in installments, but it pays."),
                (spec.personaB,
                 "And what mine sees: \(spec.positionB.label) What it misses: the thing my colleague guards does not survive being made negotiable, and I have no better lock for it than the one I spent the evening doubting. Note where we actually parted — \(spec.crux) No winner leaves this room; neither of us conceded, and the house declares nothing. What leaves is the question, sharpened, in your keeping — and where the others landed, if you're curious, waits outside, now that your own ruling is on the record.")
            ])
            return Step(envelope: Envelope(
                say: say, speakers: speakers,
                stateOps: [.advancePhase, .completeSession],
                uiHints: UIHints(endOfSession: true)))
        }
    }

    // MARK: - News, read philosophically (§15.2: brief → lensA → lensB →
    // split → position; even-handed BY CONSTRUCTION — both lenses get a full
    // phase, no ranking, no verdict, no crowd numbers, citations empty)

    private func newsReadStep(_ turn: Int) -> Step {
        let brief = newsBrief
        let a = brief?.lensPair.a
        let b = brief?.lensPair.b
        switch turn {
        case 0: // brief: the story, neutrally, then the question inside it.
            return Step(envelope: Envelope(
                say: "This week's story, plainly. \(brief?.summary.components(separatedBy: ". ").prefix(3).joined(separator: ". ") ?? "A public dispute with a philosophical question inside it.")\n\nThe court's narrow question is the law's business. Ours is the live one underneath it: \(brief?.question ?? "what is actually at issue?") We will read it twice — once through each of two frameworks that careful people actually hold — and then find precisely where they part. I favor neither; that is the whole discipline. Do you have the question?",
                uiHints: UIHints(checkInQuestion: "Do you have the question — in your own words?")))
        case 1: // → lensA: the student reasons; the professor supplies discipline.
            return Step(envelope: Envelope(
                say: "Good. First reading: \(a?.name ?? "the first framework"). Its claim, in one line: \(a?.oneLiner ?? "") Hold the story up to that light. On this view, the question about the app is a question about what the system DOES — take the conversations, the memory of the man, the replies fitted to him, and ask: what work was being done, and would that work count as thinking if you found it anywhere else? Don't tell me your verdict; reason it through as this framework would. Which feature of the case does it seize on first?",
                stateOps: [.advancePhase],
                uiHints: UIHints(checkInQuestion: "What would this framework say here — and why?")))
        case 2: // → lensB: same work, same rigor — the even-handedness contract.
            return Step(envelope: Envelope(
                say: "That is the reading, and you did it honestly — you let the framework be strong. Now the second, and I will hold it to the same standard: \(b?.name ?? "the second framework"). Its claim: \(b?.oneLiner ?? "") This view does not deny a single fact you just used. It asks a different question: not what the system does, but what doing it is like from inside — and it answers: nothing. The replies were fluent; was anything meant? Reason the case through this lens as carefully as you did the first. What does IT seize on?",
                stateOps: [.advancePhase],
                uiHints: UIHints(checkInQuestion: "And this framework — what would it say, and why?")))
        case 3: // → split: the payload — structured disagreement, not noise.
            return Step(envelope: Envelope(
                say: "Now look at where you stood a moment ago and where you stand now, because the two readings did not disagree about the facts — not one. Here is the split, precisely: \(brief?.lensPair.splitHint ?? "the frameworks weigh the same facts by different pictures of the person.") The first framework takes performance as the evidence that matters; the second holds that performance, however complete, is the wrong kind of evidence entirely. That is not noise, and it is not a muddle — it is a structured disagreement about what a mind IS, and the court briefly inherited it. See the joint clearly before we go on.",
                stateOps: [.advancePhase],
                uiHints: UIHints(checkInQuestion: "Can you name the premise the two readings do not share?")))
        case 4: // → position: taking one is optional and said so.
            return Step(envelope: Envelope(
                say: "Last step, and it is genuinely optional. You may take a position — yours, in your words, knowing now exactly what it costs and where its rival bites. Or you may decline: on a question this deep, 'I can now state both sides and I am not done deciding' is a philosophical position with a long and honorable history, and I will say so without relief or disappointment either way. Which is it tonight?",
                stateOps: [.advancePhase],
                uiHints: UIHints(checkInQuestion: "A position — or an honest suspension?")))
        default: // completeSession from position; no verdict, ever.
            return Step(envelope: Envelope(
                say: "Then that is where you stand this week, and notice what you can now do that you could not on Monday: you can state the other reading well enough that its holders would nod. The story will leave the front page; the split will meet you again wearing different clothes. When it does, you have the tools. Same time next week.",
                stateOps: [.completeSession],
                uiHints: UIHints(endOfSession: true)))
        }
    }

    // MARK: - Practice (§15.3: Bede's wing — training, never therapy; no
    // mood tracking, no scores, no streak talk; citations stay empty)

    private func practiceStep(_ turn: Int, userText: String?) -> Step {
        switch practiceMode ?? .morning {
        case .morning: return morningStep(turn, userText: userText)
        case .evening: return eveningStep(turn)
        case .visualization: return visualizationStep(turn)
        }
    }

    /// Two beats (§15.3): the prompt, then ONE reply (≤80 words, Stoic
    /// register) that completes the session in the same turn.
    private func morningStep(_ turn: Int, userText: String?) -> Step {
        if turn == 0 {
            return Step(envelope: Envelope(
                say: "Morning. Today's work: \(practiceExercise?.prompt ?? "One thing is yours to do well today, whatever the weather does. Name it.") One sentence. Set it and go.",
                uiHints: UIHints(checkInQuestion: "Your intention, in a sentence.")))
        }
        let intention = userText?.trimmingCharacters(in: .whitespacesAndNewlines) ?? ""
        return Step(envelope: Envelope(
            say: "Good — it names an action, and the action is yours. Notice the intention already sorts the day: how they respond, how it lands, what the afternoon does with it — none of that is in the sentence, because none of it is in your hands. It will be tested before noon; count on it and want it. The rep is the meeting of the two. Go train.",
            stateOps: [.completeSession],
            uiHints: UIHints(endOfSession: true)))
    }

    /// The examen (§15.3): the 3 fixed questions, one per turn, then a brief
    /// reflection about the DAY — never about the self's worth.
    private func eveningStep(_ turn: Int) -> Step {
        let questions = examenQuestions
        switch turn {
        case 0:
            return Step(envelope: Envelope(
                say: "Evening. The examen — three questions, the same three every night; the sameness is the instrument. Take them one at a time and answer about the day, not about yourself. First: \(questions[0])",
                stateOps: [.advancePhase],
                uiHints: UIHints(checkInQuestion: questions[0])))
        case 1:
            return Step(envelope: Envelope(
                say: "Heard, and set down. Second: \(questions[1])",
                stateOps: [.advancePhase],
                uiHints: UIHints(checkInQuestion: questions[1])))
        case 2:
            return Step(envelope: Envelope(
                say: "That distinction is the whole exercise — keep it. Third: \(questions[2])",
                stateOps: [.advancePhase],
                uiHints: UIHints(checkInQuestion: questions[2])))
        default:
            return Step(envelope: Envelope(
                say: "One pattern from tonight's three answers, and then we close: the thing that disturbed you sat at the edge of your control, and your 'differently' moved the effort back inside the line — toward what you would say and do, not what they would. That is the day examined, which is all the examen asks. The page is written; leave it on the page. Sleep.",
                stateOps: [.completeSession],
                uiHints: UIHints(endOfSession: true)))
        }
    }

    /// The weekly rehearsal (§15.3): the authored exercise walked in 2–3
    /// turns, then its authored debrief. Never morbid for its own sake.
    private func visualizationStep(_ turn: Int) -> Step {
        let ex = practiceExercise
        switch turn {
        case 0:
            return Step(envelope: Envelope(
                say: "This week's rehearsal: \(ex?.title ?? "a small rehearsal of loss"). Do it slowly; the exercise leads and I only pace it.\n\n\(ex?.exercise ?? "Pick up, in your mind, the thing you reach for most without noticing, and consider plainly that it was lent, not deeded.") Take your time in it, then tell me where the picture resisted you.",
                stateOps: [.advancePhase],
                uiHints: UIHints(checkInQuestion: "Where did the picture resist you?")))
        case 1:
            return Step(envelope: Envelope(
                say: "That resistance is the grip you came to train — hold the image one breath past comfortable, and notice you are still standing in it. Nothing in the rehearsal is happening; that is the point of a rehearsal. Set the imagined loss down now, completely, and come back to the room. What do you notice about the real thing, now that you have practiced its absence once?",
                stateOps: [.advancePhase],
                uiHints: UIHints(checkInQuestion: "Back in the room — what do you notice?")))
        default:
            return Step(envelope: Envelope(
                say: "\(ex?.debrief ?? "Nothing was lost in this exercise — only the illusion of permanent ownership, briefly suspended. What returns is not gloom but attention.") That is the week's rep, done. Carry the attention, not the shadow.",
                stateOps: [.completeSession],
                uiHints: UIHints(endOfSession: true)))
        }
    }

    // MARK: - Practice review (§15.3: review → reflection, from the week's
    // digest; patterns about the days, never about the student's worth)

    private func practiceReviewStep(_ turn: Int) -> Step {
        switch turn {
        case 0:
            return Step(envelope: Envelope(
                say: "The week's page is open in front of me — your entries, your words. Three things I actually see. Twice this week what disturbed you was the same meeting wearing different dates; the disturbance is a schedule, not a surprise, and schedules can be trained for. On two evenings you answered 'was it in your control?' with 'partly' — both times the part that wasn't got the worry. And your morning intentions kept naming patience with the same person; an intention that recurs unmet is not a failure, it is a bearing. Receipts on request. What do you make of the 'partly'?",
                uiHints: UIHints(checkInQuestion: "What do you make of the recurring 'partly'?")))
        case 1:
            return Step(envelope: Envelope(
                say: "That is honest, and it points somewhere specific. So: one adjustment for next week — yours, in your words, and small enough to fail visibly. Not a resolution; a rep. Name it.",
                stateOps: [.advancePhase],
                uiHints: UIHints(checkInQuestion: "One adjustment for next week — small enough to fail visibly.")))
        default:
            return Step(envelope: Envelope(
                say: "Good — and note what makes it good: it starts with your own conduct, it fits inside a morning, and next week's page will say plainly whether it happened. I sharpen nothing further; the adjustment is yours, not assigned. The week is reviewed. Close the book and begin the next one at dawn.",
                stateOps: [.completeSession],
                uiHints: UIHints(endOfSession: true)))
        }
    }

    // MARK: - Daily question (§13.2: one reply, then it's over)

    private func dailyQuestionStep(userText: String?) -> Step {
        let sharpen = (userText?.isEmpty == false)
            ? "And you gave a reason — a sentence can be examined; a tap can only be counted. "
            : ""
        return Step(envelope: Envelope(
            say: "A clean answer — and notice it is an answer, not a mood. \(sharpen)Positions like yours have a long ancestry: careful people spent lifetimes defending it, and equally careful people think it fails at exactly one point. That point of failure is the part worth knowing, because holding the position consistently will commit you elsewhere — usually somewhere less comfortable than here. It sits on your worldview as a lean: an inclination honestly recorded, not a conviction claimed. Food for thought, nothing owed: what would have to be true for the other answer to be right?",
            stateOps: [.completeSession],
            uiHints: UIHints(endOfSession: true)))
    }

    // MARK: - Argument clinic (§13.3: the roommate-rent demo, Prof. Whitmore's bench)

    private func clinicStep(_ turn: Int) -> Step {
        switch turn {
        case 0:
            return Step(envelope: Envelope(
                say: "The clinic is open. Bring me an argument — a live one: a disagreement you are actually in, a take you are being pushed on, a decision with sides. Not the polished version; the version you would say out loud. I will pull the structure out where we can both see it. One thing before we start: I map reasoning — I do not referee. The judgment stays yours. So: what is the claim at issue?",
                uiHints: UIHints(checkInQuestion: "What's the actual claim in dispute?")))
        case 1:
            return Step(envelope: Envelope(
                say: "Good — feelings, history, and the other party's tone all arrived with it, which is normal; none of them are the claim. Let me put the proposition itself on the table, in one clean sentence, taking your side of it as the claim under inspection: *Sam should pay a larger share of the rent.* That's the conclusion — node c on the board above. If it's not quite yours, we fix it now; a wrong conclusion ruins the whole map. Assuming it holds: give me the strongest reason in its favor, the one doing the real work.",
                stateOps: [
                    .setConclusion(text: "Sam should pay a larger share of the rent."),
                    .advancePhase
                ],
                uiHints: UIHints(checkInQuestion: "What's the strongest reason in its favor?")))
        case 2:
            return Step(envelope: Envelope(
                say: "On the board: p1 — Sam has the larger bedroom. Now notice what kind of thing that is: a measurement. And a measurement, by itself, proves nothing about what anyone *should* pay; something unspoken is bridging the fact to the ought. That bridge is a premise too, whether or not anyone in the apartment has said it aloud. Say it out loud if you can — what principle connects the size of a room to the size of a rent check?",
                stateOps: [
                    .addPremise(ArgumentSpec.Premise(
                        id: "p1", text: "Sam has the larger bedroom.",
                        stated: true, supports: "c"))
                ],
                uiHints: UIHints(checkInQuestion: "What principle connects the room to the rent?")))
        case 3:
            return Step(envelope: Envelope(
                say: "There it is — p2: whoever gets more of the apartment should pay more of its cost. Stated, and creditable. But look at the board now, because under p2 hangs a premise *nobody* in this dispute has said out loud: p3 — room size is the right measure of who gets more of the apartment. Dashed border, because it's unstated — and it is carrying the entire argument. If Sam works late, hosts nothing, and uses the kitchen twice a week, the argument reads differently, doesn't it? I've also sharpened p1 while we're here: 'larger' was doing quiet work, so let's say how much. The whole machine is now on the table: a measurement, a fairness principle, and the silent assumption connecting them. Walk it once with me before we go on.",
                stateOps: [
                    .addPremise(ArgumentSpec.Premise(
                        id: "p2",
                        text: "Whoever gets more of the apartment should pay more of its cost.",
                        stated: true, supports: "c")),
                    .addPremise(ArgumentSpec.Premise(
                        id: "p3",
                        text: "Room size is the right measure of who gets more of the apartment.",
                        stated: false, supports: "p2")),
                    .revisePremise(id: "p1",
                                   text: "Sam's bedroom is roughly a third larger."),
                    .advancePhase
                ],
                uiHints: UIHints(checkInQuestion: "Does the map match the argument you've actually been having?")))
        case 4:
            return Step(envelope: Envelope(
                say: "Then here is the clinic's real question: where do you and Sam actually diverge? Not p1 — a tape measure settles that, and I doubt either of you disputes it. Not even p2 — I would wager Sam accepts the principle happily. The live wire is p3: what counts as *getting more* of a shared home. That is a definition crux — badged on the board. You two mean different things by 'more,' and until that word is settled you are not disagreeing; you are talking past each other. Which explains something, doesn't it: why the same three sentences keep repeating. The fight was never about money.",
                stateOps: [
                    .advancePhase,
                    .markCrux(id: "p3", kind: .definition)
                ],
                uiHints: UIHints(checkInQuestion: "Does that match where the conversation actually stalls?")))
        default:
            return Step(envelope: Envelope(
                say: "So here is what would settle it — and note that it is not louder repetition of p1. Agree on the measure. Sit down and decide together what 'share of the apartment' means: square feet, waking hours at home, common space, guests — all of it on the table. That is a definition to negotiate, not a fact to prove, which is exactly why the argument kept sliding. You came in with a rent dispute; you leave with one word to settle. Whether Sam's share changes once you've settled it — that judgment was never mine to make. The map is yours; take it home.",
                stateOps: [.advancePhase, .completeSession],
                uiHints: UIHints(endOfSession: true)))
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

    // MARK: - Steelman (§14.4: brief → attempt → probe → verdict → debrief,
    // Prof. Whitmore's bench; citations stay empty — no retrieval runs)

    private func steelmanStep(_ turn: Int) -> Step {
        let target = steelmanTarget ?? "the position you hold"
        switch turn {
        case 0: // brief: frame the target and the bar.
            return Step(envelope: Envelope(
                say: "On the table, in your own words: *\(target)* You hold it; today you argue against it. Not against the lazy version — anyone can beat up the pamphlet. The people on the other side of this have their reasons, and the best of them have thought about it longer than either of us. Your job is to state their case so well they would sign it. That is the bar, and it is the rarest skill on the internet. I will listen to the whole attempt before I touch it. When you are ready: their best case, start to finish.",
                stateOps: [.advancePhase],
                uiHints: UIHints(checkInQuestion: "State the other side's best case — whole.")))
        case 1: // attempt heard whole -> probe: name the gap, don't fill it.
            return Step(envelope: Envelope(
                say: "I let you finish, as promised, and there is a real argument in there — the shape is right. But it is still part strawman, and here is where: you gave the other side its conclusion without its strongest premise. As you tell it, they hold their view out of stubbornness or sentiment; the actual holders hold it because of an argument — the one move their best thinkers reach for first, the one that makes careful people nod along before they catch themselves. That move is missing from your version entirely. I won't supply it; finding it is the exercise. Revise the attempt with their best premise doing the work it actually does.",
                stateOps: [.advancePhase],
                uiHints: UIHints(checkInQuestion: "Where is their strongest premise — and what work does it do?")))
        case 2: // revision -> verdict: the grade lands on the argument.
            return Step(envelope: Envelope(
                say: "Better — genuinely. The strongest premise showed up this time, and you let it be strong instead of introducing it with an apology, which is where most attempts go quiet. Verdict, and remember the grade is on the argument you produced, never on you. Level 3 — competent: a holder would nod. What separates it from level 4, signable, is the last mile of charity: their answer to your own best objection, stated as confidently as they would state it. You told me what they believe and why; you did not yet show me how they win the argument you usually win. That is the rung above you, and it is reachable.",
                stateOps: [
                    .advancePhase,
                    .recordSteelmanScore(
                        level: 3,
                        justification: "A holder would nod: the strongest premise arrived and did real work — signable needs their answer to your own best objection.")
                ],
                uiHints: UIHints(checkInQuestion: "Now the debrief: which of your own premises does their best case press hardest?")))
        default: // debrief: what the opposing case teaches about their own view.
            return Step(envelope: Envelope(
                say: "That is the honest answer, and notice what just happened: you now know which of your own premises carries the load, because you spent an hour leaning on it from the other side. That knowledge is the whole point of the ladder. Your position survived today — held under fire is worth more than held in peace — and if a future steelman converts you instead, that will be progress too, and this page will say so. Climb again when the position feels too comfortable.",
                stateOps: [
                    .writeMemory(note: "Steelman reached competent on the second pass; finds the opposing conclusion easily, still hunts for the opposing premise."),
                    .completeSession
                ],
                uiHints: UIHints(endOfSession: true)))
        }
    }

    // MARK: - Thought experiment (authored nodes client-side, §12.1 / A10;
    // a weekly drop supplies its own spec and runs the same flow, §14.3)

    private var experimentSpec: ThoughtExperimentSpec? {
        dropSpec ?? unit?.thoughtExperiments?.first
    }

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
            // The drop debrief carries no citation — drops run outside the
            // course texts, the way the steelman kind keeps citations empty.
            return Step(envelope: Envelope(
                say: dropSpec == nil
                    ? "Enough. Here is what the case was for: Glaucon deleted detection to see what your justice is made of, and your path through it is now evidence — your own, on the table. Whether it confirmed his wager or beat it, you can no longer claim the question is academic. \(spec?.philosophicalPayload.components(separatedBy: ". ").first.map { $0 + "." } ?? "")"
                    : "Enough. Here is what the case was for: your path through it is now evidence — your own, on the table — and you can no longer claim the question is academic. \(spec?.philosophicalPayload.components(separatedBy: ". ").first.map { $0 + "." } ?? "") When you are curious where other thinkers walked, the crowd is waiting — after your answer, never before.",
                citations: dropSpec == nil ? [Quote.gyges] : [],
                stateOps: [
                    .advancePhase,
                    .writeMemory(note: dropSpec == nil
                        ? "Ring of Gyges: chose deliberately and defended the choice under the pump; does not hide behind 'it depends.'"
                        : "Weekly drop (\(spec?.title ?? "case")): chose deliberately and defended the choice under interrogation."),
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
