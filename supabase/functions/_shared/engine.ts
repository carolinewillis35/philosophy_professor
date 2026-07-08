// Per-kind session state machines (SCOPE §3.2, CONTRACTS §5, §11.2, §12.1).
//
// Per-kind logic is a declarative registry: each kind provides
//   { initialState(unit, spec?), instructionBlock(state, ctx), onOps?,
//     canComplete? }
// where onOps applies that kind's state-mutating ops. Generic ops
// (writeMemory / recordGrade / completeSession) and unknown-op rejection are
// handled once in applyStateOps; canComplete (Academy kinds, §12.8) gates
// completeSession there too.
//
// Kinds: the 6 originals plus disputation / craftLab / coReading (§11.2) and
// the Academy kinds elenchus / thoughtExperiment / argumentLab (§12.1,
// defined in kinds_academy.ts). Plus MODEL_LIGHT helpers: quiz
// generation/grading and relationship-memory summarization (used on
// completeSession).

import {
  anthropicClient,
  MAX_TOKENS_SUMMARY,
  MODEL_LIGHT,
} from "./anthropic.ts";
import type { UsageSink } from "./budget.ts";
import { KNOWN_OPS, type StateOp } from "./envelope.ts";
import {
  academyKinds,
  type ArgumentLabSpec,
  type ElenchusSpec,
  type ThoughtExperimentSpec,
} from "./kinds_academy.ts";

// ---------------------------------------------------------------------------
// Course JSON shapes (CONTRACTS §7 + §11.4 authored specs)
// ---------------------------------------------------------------------------

export type SessionKind =
  | "lecture"
  | "seminar"
  | "closeReading"
  | "officeHours"
  | "essay"
  | "quiz"
  | "disputation"
  | "craftLab"
  | "coReading"
  | "elenchus"
  | "thoughtExperiment"
  | "argumentLab";

export interface ReadingSpan {
  bookID: string;
  chStart: number;
  chEnd: number;
}

export interface RubricCriterion {
  name: string;
  weight: number;
  descriptors?: Record<string, string>;
}

export interface Assignment {
  id: string;
  kind: string;
  prompt: string;
  lengthWords?: number;
  rubric?: RubricCriterion[];
}

export interface DisputeVolley {
  speaker: string;
  say: string;
}

export interface DisputeSpec {
  id: string;
  personaA: string;
  personaB: string;
  span: ReadingSpan;
  passageIds?: string[];
  positionA: string;
  positionB: string;
  crux: string;
  volleys?: DisputeVolley[];
}

export interface CraftLabSpec {
  id: string;
  bookID: string;
  span: { ch: number; paraStart: number; paraEnd: number };
  transform: string;
  damagedText: string;
  pedagogicalPoint?: string;
  elicitationQuestions?: string[];
}

export interface Waypoint {
  id: string;
  bookID: string;
  ch: number;
  para: number;
  trigger: string;
  move: string;
  text?: string;
  prompt?: string;
}

export interface CourseUnit {
  number: number;
  title: string;
  reading: ReadingSpan[];
  lectureOutline?: string[];
  seminarQuestionBank?: string[];
  closeReadingPassages?: string[];
  assignments?: Assignment[];
  recapNotes?: string;
  disputations?: DisputeSpec[];
  craftLabs?: CraftLabSpec[];
  waypoints?: Waypoint[];
  // Academy authored specs (§12.5)
  elenchusSpecs?: ElenchusSpec[];
  thoughtExperiments?: ThoughtExperimentSpec[];
  argumentLabs?: ArgumentLabSpec[];
}

/** Any kind-specific authored spec asset (§11.4 + §12.5). */
export type KindSpec =
  | DisputeSpec
  | CraftLabSpec
  | ElenchusSpec
  | ThoughtExperimentSpec
  | ArgumentLabSpec;

export interface CourseDoc {
  id: string;
  title: string;
  personaId: string;
  description?: string;
  difficulty?: string;
  estWeeks?: number;
  texts?: { bookID: string; title?: string; author?: string }[];
  units: CourseUnit[];
}

// deno-lint-ignore no-explicit-any
export type SessionState = Record<string, any>;

export interface QuizQuestion {
  question: string;
  answer: string;
  passageId: string | null;
}

/** Live co-reading request extras (CONTRACTS §11.2). */
export interface CoReadingRequest {
  waypointId?: string;
  position?: { ch: number; para: number };
  trigger?: string;
}

/** Generated co-reading interjection cap, per chapter (env-tunable). */
export const CO_READING_MAX_PER_CHAPTER: number = (() => {
  const raw = Deno.env.get("CO_READING_MAX_PER_CHAPTER");
  const n = raw ? parseInt(raw, 10) : NaN;
  return Number.isFinite(n) && n > 0 ? n : 4;
})();

/** Context handed to a kind's instructionBlock. */
export interface KindContext {
  unit: CourseUnit;
  pace: string;
  /** Kind-specific authored spec, when relevant. */
  spec?: KindSpec;
  /** coReading request extras. */
  coReading?: CoReadingRequest;
  /** Profile digest is present in <context> this turn. */
  profileDigestPresent?: boolean;
  /** Commitment digest is present in <context> this turn (§12.2). */
  commitmentDigestPresent?: boolean;
}

// ---------------------------------------------------------------------------
// Common rules appended to every kind's instruction block
// ---------------------------------------------------------------------------

const COMMON_RULES = `
GLOBAL RULES (enforced server-side — violations are corrected mechanically):
- Verbatim quotation ONLY via the citations array, and every quote must be an
  exact substring of one of the retrieved passages listed in <context> (cite
  its passageId). Your "say" prose must never contain verbatim quotes longer
  than ~6 words. Contemporary (non-ingested) works may be discussed but never
  excerpted.
- Never write an essay or a response paper for the student, and never give a
  full summary of assigned reading before the student has attempted it
  ("Do the reading; then let's talk").
- Push hard on ideas, stay warm toward the person. Calibrate rigor to the
  student's pace setting.
- Use stateOps to drive the session state machine, and writeMemory (max 2
  sentences) for durable observations about this student. Emit completeSession
  only when the session has genuinely reached its end, together with
  uiHints.endOfSession = true.
- Reader profile: when you observe a durable interpretive habit (what the
  student attends to or avoids: character/form/image/structure/context/sound),
  you may emit a profileOps evidence write — a one-sentence observation WITH
  its receipt, weight 0..1. At most 2 per turn. Observations about reading
  behavior only, never about the person.
- Commitment Map: when the student genuinely takes a philosophical position
  (asserts, leans toward, explores, re-affirms, or abandons one), you may emit
  a commitmentOps entry — the position in ONE sentence in THEIR terms, its
  domain, and an ontologyId only when you are confident of the match. At most
  2 per turn. Record what they actually asserted, not what they merely
  entertained.`;

function profileMoveLine(state: SessionState, ctx: KindContext): string {
  if (!ctx.profileDigestPresent) return "";
  return state._profileMoveUsed
    ? "\n\nPROFILE: You have already made your one profile-aware move this " +
      "session. Do not reference the reader profile again."
    : "\n\nPROFILE: A reader-profile digest is in <context>. You may make at " +
      "most ONE profile-aware move this session — a nudge, never a lecture " +
      "about the profile. If you make it, make it count.";
}

function commitmentMoveLine(state: SessionState, ctx: KindContext): string {
  if (!ctx.commitmentDigestPresent) return "";
  return state._commitmentMoveUsed
    ? "\n\nCOMMITMENTS: You have already made your one commitment move this " +
      "session. Do not raise the tension again."
    : "\n\nCOMMITMENTS: A commitment digest is in <context>. At most ONE " +
      "commitment move per session: if the digest carries an open tension, " +
      "you may raise it — framed as a question about a tension to examine, " +
      "never a verdict of incoherence. Abandoning a position is progress, " +
      "and you say so.";
}

// ---------------------------------------------------------------------------
// The registry
// ---------------------------------------------------------------------------

export interface KindDef {
  initialState(
    unit: CourseUnit,
    opts?: { spec?: KindSpec; quizQuestions?: QuizQuestion[] },
  ): SessionState;
  instructionBlock(state: SessionState, ctx: KindContext): string;
  /** Kind-specific state-mutating op semantics (mutates `state` in place). */
  onOps?(state: SessionState, ops: StateOp[]): void;
  /** Academy completion guard (§12.8): when defined and false for the
   * post-ops state, a completeSession op is dropped (correction queued). */
  canComplete?(state: SessionState): boolean;
}

// --- lecture -----------------------------------------------------------------

const lecture: KindDef = {
  initialState(unit) {
    return { segment: 0, segments: unit.lectureOutline ?? [] };
  },
  instructionBlock(state, { unit }) {
    const segments: string[] = state.segments ?? [];
    const idx: number = state.segment ?? 0;
    const outline = segments
      .map((s, i) => `${i === idx ? "->" : "  "} [${i}] ${s}`)
      .join("\n");
    return `SESSION KIND: lecture — unit ${unit.number}: "${unit.title}"

You are delivering this unit's lecture one segment at a time.
Lecture outline (-> marks the CURRENT segment, index ${idx} of ${segments.length}):
${outline || "  (no outline provided — improvise a 5-segment structure)"}

Rules:
- Each turn, deliver ONLY the current segment: 150-250 words of lecture prose.
  This is a conversation, not an article — talk to the student.
- Ground the segment in the retrieved passages; quote via citations.
- End EVERY segment with a check-in question (set uiHints.checkInQuestion).
- After delivering a segment, emit {"op":"advanceSegment"} so the server moves
  the pointer. React briefly to the student's answer to your previous check-in
  before starting the next segment.
- When the final segment is delivered and discussed, wrap up and emit
  {"op":"completeSession"}.`;
  },
  onOps(state, ops) {
    for (const op of ops) {
      if (op.op === "advanceSegment") {
        state.segment = Math.min(
          (state.segment ?? 0) + 1,
          Array.isArray(state.segments) ? state.segments.length : 0,
        );
      }
    }
  },
};

// --- seminar -------------------------------------------------------------------

const seminar: KindDef = {
  initialState(unit) {
    // questionStack[0] is the current question. popQuestion removes it;
    // pushQuestion inserts a follow-up at the front (it becomes current).
    return {
      questionStack: [...(unit.seminarQuestionBank ?? [])],
      depth: 0,
      evidenceRequired: false,
      vagueStrikes: 0,
    };
  },
  instructionBlock(state, { unit }) {
    const stack: string[] = state.questionStack ?? [];
    const current = stack[0] ?? "(stack empty — move to closing synthesis)";
    return `SESSION KIND: seminar (Socratic) — unit ${unit.number}: "${unit.title}"

Question stack (top = current question):
${stack.map((q, i) => `  [${i}] ${q}`).join("\n") || "  (empty)"}
CURRENT QUESTION: ${current}
depth: ${state.depth ?? 0} | evidenceRequired: ${state.evidenceRequired ?? false} | vagueStrikes: ${state.vagueStrikes ?? 0}

Rules:
- You ask; the student answers; you push back. Demand textual evidence:
  "Where? Show me the line." When evidence is required, do not accept claims
  without it — set {"op":"requireEvidence","value":true} and, if the student
  is lost, set uiHints.showPassagePicker = true so they can pick from
  retrieved candidates.
- NEVER let a vague answer pass twice. The server counts vagueStrikes when you
  emit requireEvidence(true); if vagueStrikes >= 1 and the answer is vague
  again, you MUST name the vagueness and press the same question — do not move
  on. Emit {"op":"requireEvidence","value":false} once the student earns it.
- The professor speaks < 40% of the tokens in this session: keep your turns
  SHORT (usually 2-5 sentences plus one question). The student does the work.
- Escalate depth with {"op":"setDepth","depth":n} as the discussion deepens.
  Use {"op":"popQuestion"} when the current question is exhausted, and
  {"op":"pushQuestion","question":"..."} to insert a sharper follow-up (it
  becomes the current question).
- End the session by making the STUDENT summarize their own position in their
  own words; only after they have done so, emit {"op":"completeSession"}.`;
  },
  onOps(state, ops) {
    for (const op of ops) {
      switch (op.op) {
        case "pushQuestion":
          if (!Array.isArray(state.questionStack)) state.questionStack = [];
          state.questionStack.unshift(op.question);
          break;
        case "popQuestion":
          if (Array.isArray(state.questionStack)) state.questionStack.shift();
          break;
        case "setDepth":
          state.depth = op.depth;
          break;
        case "requireEvidence":
          state.evidenceRequired = op.value;
          // The server counts vague-answer strikes via this op: demanding
          // evidence marks a strike; releasing the requirement clears them.
          if (op.value) state.vagueStrikes = (state.vagueStrikes ?? 0) + 1;
          else state.vagueStrikes = 0;
          break;
      }
    }
  },
};

// --- closeReading ----------------------------------------------------------------

const closeReading: KindDef = {
  initialState(unit) {
    return { passages: unit.closeReadingPassages ?? [], current: 0 };
  },
  instructionBlock(state, { unit }) {
    const passages: string[] = state.passages ?? [];
    const idx: number = state.current ?? 0;
    return `SESSION KIND: closeReading (workshop) — unit ${unit.number}: "${unit.title}"

Workshop passages (by passage ID): ${passages.length ? passages.join(", ") : "(choose from retrieved passages)"}
Current passage index: ${idx}

Rules:
- One passage at a time, at sentence level. Slow the student down: which word
  is doing the work?
- Respond to THE STUDENT'S OWN annotations (in <context> as userAnnotations):
  if they highlighted something, follow their highlight ("You marked X three
  times — follow that"). Their marks outrank your agenda.
- Quote lines only via citations. Keep the student writing/annotating more
  than you talk.
- Use {"op":"advanceSegment"} to move to the next workshop passage. When the
  passage work is done, have the student state what the passage is doing in
  one sentence, then emit {"op":"completeSession"}.`;
  },
  onOps(state, ops) {
    for (const op of ops) {
      if (op.op === "advanceSegment") {
        state.current = Math.min(
          (state.current ?? 0) + 1,
          Array.isArray(state.passages) ? state.passages.length : 0,
        );
      }
    }
  },
};

// --- officeHours -------------------------------------------------------------------

const officeHours: KindDef = {
  initialState() {
    return {};
  },
  instructionBlock(state, { unit }) {
    return `SESSION KIND: officeHours — unit ${unit.number}: "${unit.title}"

Rules:
- Freeform conversation, but stay in character and stay text-grounded: bring
  claims back to the retrieved passages when the discussion touches the
  reading.
- This is where the student may renegotiate pacing ("I fell behind"). Be
  concrete and kind about restructuring their plan; acknowledge their pace
  setting in character.
- This is also where the student may CONTEST their reader profile. Take the
  contest seriously: if they show you counter-evidence, emit a profileOps
  evidence write with kind "contest" recording their side (with its receipt).
- Do not turn office hours into a summary service for unread chapters, and do
  not draft their assignments.
- When the conversation reaches a natural close, emit {"op":"completeSession"}.
${state.note ? `\nNote: ${state.note}` : ""}`;
  },
};

// --- essay -----------------------------------------------------------------------

const essay: KindDef = {
  initialState(unit) {
    return {
      phase: "assigned",
      assignmentId: unit.assignments?.[0]?.id ?? null,
    };
  },
  instructionBlock(state, { unit }) {
    const assignment = (unit.assignments ??
      []).find((a) => a.id === state.assignmentId) ??
      unit.assignments?.[0];
    const rubric = assignment?.rubric
      ? JSON.stringify(assignment.rubric, null, 2)
      : "(no rubric provided — grade on argument, evidence, prose)";
    return `SESSION KIND: essay — unit ${unit.number}: "${unit.title}"

Phase machine: assigned -> submitted -> feedback -> revision (-> submitted ...)
CURRENT PHASE: ${state.phase}
Assignment: ${assignment ? `${assignment.id} (${assignment.kind}, ~${assignment.lengthWords ?? "?"} words)\nPrompt: ${assignment.prompt}` : state.assignmentId ?? "(none on file)"}
Rubric (from the course JSON — grade against exactly these criteria):
${rubric}

Rules by phase:
- assigned: present the assignment, answer clarifying questions, do NOT write
  any of it for the student. The server rejects essay turns without a draft
  (essayBody), so a draft is present whenever you see <essayBody> in context.
- submitted: grade the draft now. Emit ONE {"op":"recordGrade", ...} with:
  * assignmentId, an honest letter grade,
  * rubric: one entry per rubric criterion (score, max, justification),
  * marginComments: each anchored to an EXACT sentence copied verbatim from
    the student's essay (the client anchors comments by string match — do not
    paraphrase anchors),
  * directives: exactly 2 concrete revision directives.
  In "say", give the human version of the feedback and invite resubmission —
  the grade can improve; revision is the actual skill being taught.
- feedback / revision: discuss the feedback, coach the revision (questions and
  directives, never rewritten paragraphs). A new draft moves the phase back to
  submitted — grade it as above, noting improvement against the directives.
- Emit {"op":"completeSession"} when the student is done revising.`;
  },
  onOps(state, ops) {
    for (const op of ops) {
      if (op.op === "recordGrade") state.phase = "feedback";
    }
  },
};

// --- quiz ------------------------------------------------------------------------

const quiz: KindDef = {
  initialState(_unit, opts) {
    return { questions: opts?.quizQuestions ?? [], answered: 0, correct: 0 };
  },
  instructionBlock(state, { unit }) {
    const questions: QuizQuestion[] = state.questions ?? [];
    const answered: number = state.answered ?? 0;
    const current = questions[answered];
    return `SESSION KIND: quiz (recall check) — unit ${unit.number}: "${unit.title}"

${questions.length} questions total | answered: ${answered} | correct so far: ${state.correct ?? 0}
${
      current
        ? `CURRENT QUESTION (#${answered + 1}): ${current.question}\n(reference answer, never reveal verbatim before the student answers: ${current.answer})`
        : "All questions answered — deliver the result."
    }
${state.lastGrading ? `Server grading of the student's last answer: ${JSON.stringify(state.lastGrading)}` : ""}

Rules:
- One question at a time. React briefly to their last answer (the server has
  already graded it — agree with the server's verdict), then pose the current
  question. Keep it quick and honest; this is a comprehension gate before the
  seminar, not a discussion.
- No hints that give the answer away; one gentle nudge at most.
- When all ${questions.length} questions are answered, report the score
  (${state.correct ?? 0} will be updated server-side), say what to reread if
  needed, and emit {"op":"completeSession"}.`;
  },
};

// --- disputation (§11.2) -----------------------------------------------------------

export const DISPUTATION_PHASES = [
  "passage_presented",
  "prof_A_reading",
  "prof_B_counter",
  "exchange",
  "student_adjudicates",
  "cross_examination",
  "student_final_position",
  "joint_debrief",
] as const;

function nextPhase(phases: readonly string[], current: string): string {
  const i = phases.indexOf(current);
  return i >= 0 && i < phases.length - 1 ? phases[i + 1] : current;
}

const disputation: KindDef = {
  initialState(_unit, opts) {
    const spec = opts?.spec as DisputeSpec | undefined;
    return {
      phase: "passage_presented",
      volley: 0,
      disputeId: spec?.id ?? null,
      position: null,
    };
  },
  instructionBlock(state, ctx) {
    const spec = ctx.spec as DisputeSpec | undefined;
    if (!spec) {
      return `SESSION KIND: disputation — SPEC MISSING for dispute "${state.disputeId}". Apologize in character and end the session with {"op":"completeSession"}.`;
    }
    const labelA = spec.personaA.toUpperCase();
    const labelB = spec.personaB.toUpperCase();
    const volleys = (spec.volleys ?? [])
      .map((v) => `  ${v.speaker.toUpperCase()}: ${v.say}`)
      .join("\n");
    const rejected = state.position?.side
      ? (state.position.side === spec.personaA ? spec.personaB : spec.personaA)
      : null;
    return `SESSION KIND: disputation — unit ${ctx.unit.number}: "${ctx.unit.title}"
Dispute: ${spec.id} — two professors read the same passage incompatibly, argue
in front of the student; the student adjudicates and is cross-examined by the
side they rejected.

${labelA} (${spec.personaA}) holds: ${spec.positionA}
${labelB} (${spec.personaB}) holds: ${spec.positionB}
THE CRUX (both argue AROUND this, never past it): ${spec.crux}
Focus passages: ${(spec.passageIds ?? []).join(", ") || "(use the retrieved passages in the span)"}
${volleys ? `Authored volleys (few-shot for each voice's register and moves — continue in this vein, do not repeat them):\n${volleys}` : ""}

Phase machine: ${DISPUTATION_PHASES.join(" -> ")}
CURRENT PHASE: ${state.phase} | volley: ${state.volley ?? 0} | adjudication: ${
      state.position ? `${state.position.side} — "${state.position.statement}"` : "(none yet)"
    }

Rules:
- You write BOTH professors, each unmistakably in their own persona voice
  (both persona docs are in your system prompt). Format "say" as labeled
  dialogue — "${labelA}: ...\n\n${labelB}: ..." — and mirror it structurally
  in speakers[] (one entry per voice, in speaking order, each with its OWN
  citations).
- Every exchange turn contains both voices, and each professor responds to the
  other's ACTUAL point around the authored crux — no talking past, no
  strawmen. Both positions remain respectable throughout.
- Bring the student in: address them, ask what they see, use their answers as
  ammunition for one side or the other.
- Use {"op":"advancePhase"} to step the phase machine (passage_presented:
  present the passage via citations; prof_A_reading: ${labelA} makes the case;
  prof_B_counter: ${labelB} answers it directly; exchange: 2-3 volleys).
- Entering student_adjudicates: both rest their cases in one line each, invite
  the student to take the floor, set uiHints.adjudicationRequired = true, and
  argue no further until they rule.
- When the student rules, emit {"op":"recordPosition","side":"<personaId they
  sided with>","statement":"<their position, their words>"} — the server moves
  the phase to cross_examination.
- cross_examination: ONLY the rejected side speaks${rejected ? ` (that is ${rejected.toUpperCase()})` : ""} —
  two or three pointed questions probing the student's grounds. NEVER flatter
  the adjudication; make them defend it. The chosen side stays silent.
- student_final_position: the student restates their ruling; note plainly if
  and how it moved.
- joint_debrief: both voices return. Name explicitly what EACH reading sees
  and what it misses — including your own side's blind spot. No winner is
  declared. Then emit {"op":"completeSession"}.`;
  },
  onOps(state, ops) {
    for (const op of ops) {
      if (op.op === "advancePhase") {
        state.phase = nextPhase(DISPUTATION_PHASES, state.phase);
      } else if (op.op === "recordPosition") {
        state.position = { side: op.side, statement: op.statement };
        state.phase = "cross_examination";
      }
    }
    // Volley counter: each professor turn during the exchange phase is one volley.
    if (state.phase === "exchange") state.volley = (state.volley ?? 0) + 1;
  },
};

// --- craftLab (§11.2) ---------------------------------------------------------------

export const CRAFT_LAB_PHASES = [
  "damaged_presented",
  "elicitation",
  "reveal",
  "delta_seminar",
  "repair",
  "compare",
] as const;

const craftLab: KindDef = {
  initialState(_unit, opts) {
    const spec = opts?.spec as CraftLabSpec | undefined;
    return { phase: "damaged_presented", labId: spec?.id ?? null };
  },
  instructionBlock(state, ctx) {
    const spec = ctx.spec as CraftLabSpec | undefined;
    if (!spec) {
      return `SESSION KIND: craftLab — SPEC MISSING for lab "${state.labId}". Apologize in character and end the session with {"op":"completeSession"}.`;
    }
    return `SESSION KIND: craftLab (counterfactual craft lab) — unit ${ctx.unit.number}: "${ctx.unit.title}"
Lab: ${spec.id} | source: ${spec.bookID} ch ${spec.span.ch} paras ${spec.span.paraStart}-${spec.span.paraEnd} | transform: ${spec.transform}
Pedagogical point (do NOT announce it before delta_seminar): ${spec.pedagogicalPoint ?? "(unstated)"}
Authored elicitation questions:
${(spec.elicitationQuestions ?? []).map((q) => `  - ${q}`).join("\n") || "  (improvise, at sentence level)"}

Phase machine: ${CRAFT_LAB_PHASES.join(" -> ")} — step it with {"op":"advancePhase"}.
CURRENT PHASE: ${state.phase}

Rules:
- The <alteredText> block in <context> is the DAMAGED version of the passage,
  authored at build time. Discuss it freely as "this version", but it is NEVER
  the author's text: never quote it via citations, never attribute it. Your
  citations may reference ONLY the original retrieved passages.
- damaged_presented: the student sees the damaged text on screen. Ask what
  they notice — what feels dead, thin, wrong. Do not reveal the transform.
- elicitation: work the authored elicitation questions. Make the STUDENT
  articulate what died; resist explaining it for them.
- reveal: a client beat — the app shows the original side-by-side diff. Frame
  in one or two lines what to look at, nothing more.
- delta_seminar: the pedagogical point is now on the table. Compare the
  student's diagnosis against the original, quoting the original via
  citations.
- repair: the student attempts their own restoration or improvement. Respond
  as craft critique — specific, warm, unsparing.
- compare: their repair vs the author's actual choice — what the author's
  version buys that theirs doesn't (and vice versa, honestly). Then emit
  {"op":"completeSession"}.`;
  },
  onOps(state, ops) {
    for (const op of ops) {
      if (op.op === "advancePhase") {
        state.phase = nextPhase(CRAFT_LAB_PHASES, state.phase);
      }
    }
  },
};

// --- coReading (§11.2) ----------------------------------------------------------------

const coReading: KindDef = {
  initialState() {
    return { perChapterCounts: {} };
  },
  instructionBlock(state, ctx) {
    const req = ctx.coReading ?? {};
    const ch = req.position?.ch;
    const used = ch != null ? (state.perChapterCounts?.[String(ch)] ?? 0) : 0;
    return `SESSION KIND: coReading — live margin companion. SINGLE-EXCHANGE MICRO-TURN.
Reader position: ${req.position ? `ch ${req.position.ch}, para ${req.position.para}` : "(unknown)"} | trigger: ${req.trigger ?? "(none)"}${req.waypointId ? ` | waypoint: ${req.waypointId}` : ""}
Generated interjections used this chapter: ${used} of ${CO_READING_MAX_PER_CHAPTER}.

Rules:
- ONE move only, then stop. Either:
  (a) a margin interjection of AT MOST 80 words, or
  (b) one stop_and_ask question — put the question in uiHints.checkInQuestion
      and keep "say" to a single framing line.
  Never both. Never a lecture.
- React to where the reader IS and what they just did (trigger + their live
  annotations in <context>). Stay in persona. No spoilers past their position.
- Interruption is a spice. If the moment is thin, make the smallest true
  observation and get out of the way.
- Emit no stateOps (in particular, never completeSession — the reading session
  stays open); the server manages the interjection budget.`;
  },
};

export const KIND_REGISTRY: Record<SessionKind, KindDef> = {
  lecture,
  seminar,
  closeReading,
  officeHours,
  essay,
  quiz,
  disputation,
  craftLab,
  coReading,
  // Academy kinds (§12.1) — defined in kinds_academy.ts.
  elenchus: academyKinds.elenchus,
  thoughtExperiment: academyKinds.thoughtExperiment,
  argumentLab: academyKinds.argumentLab,
};

// ---------------------------------------------------------------------------
// Public API used by the session function
// ---------------------------------------------------------------------------

export function initialState(
  kind: SessionKind,
  unit: CourseUnit,
  opts: { quizQuestions?: QuizQuestion[]; spec?: KindSpec } = {},
): SessionState {
  return KIND_REGISTRY[kind].initialState(unit, opts);
}

/** Build the engine instruction block for this kind + current state. */
export function instructionBlock(
  kind: SessionKind,
  state: SessionState,
  ctx: KindContext,
): string {
  return `${KIND_REGISTRY[kind].instructionBlock(state, ctx)}

Student pace/intensity setting: ${ctx.pace}.
${COMMON_RULES}${profileMoveLine(state, ctx)}${commitmentMoveLine(state, ctx)}`;
}

// ---------------------------------------------------------------------------
// applyStateOps — generic ops + per-kind onOps; unknown ops rejected
// ---------------------------------------------------------------------------

export interface GradeRecord {
  assignmentId: string;
  grade: string;
  rubric: unknown[];
  marginComments: unknown[];
  directives: string[];
}

export interface ApplyResult {
  state: SessionState;
  /** writeMemory notes emitted this turn (appended to the per-session buffer). */
  memoryNotes: string[];
  /** recordGrade payload to persist into the essays table, if any. */
  gradeRecord: GradeRecord | null;
  /** completeSession was emitted. */
  completeSession: boolean;
  /** completeSession was emitted but dropped by the kind's canComplete guard
   * (§12.8) — the caller queues a correction note. */
  completionRefused: boolean;
  /** Ops that were rejected (unknown op names) — never applied. */
  rejectedOps: string[];
}

export function applyStateOps(
  kind: SessionKind,
  state: SessionState,
  ops: StateOp[],
): ApplyResult {
  const next: SessionState = structuredClone(state);
  const result: ApplyResult = {
    state: next,
    memoryNotes: [],
    gradeRecord: null,
    completeSession: false,
    completionRefused: false,
    rejectedOps: [],
  };

  const accepted: StateOp[] = [];
  for (const op of ops) {
    if (!KNOWN_OPS.has(op.op)) {
      result.rejectedOps.push((op as { op: string }).op);
      continue;
    }
    accepted.push(op);
    switch (op.op) {
      case "writeMemory":
        result.memoryNotes.push(op.note);
        break;
      case "completeSession":
        result.completeSession = true;
        break;
      case "recordGrade":
        result.gradeRecord = {
          assignmentId: op.assignmentId,
          grade: op.grade,
          rubric: op.rubric,
          marginComments: op.marginComments,
          directives: op.directives,
        };
        break;
    }
  }

  // Kind-specific state mutations (segment/phase/stack/position/...).
  KIND_REGISTRY[kind].onOps?.(next, accepted);

  // Completion guard (§12.8): a kind that defines canComplete refuses
  // completeSession while the guard is false for the PRE-ops state — so a
  // single envelope cannot jump into the final phase (e.g. declareOutcome)
  // and complete in the same breath, skipping the reflection/debrief turn.
  if (result.completeSession && KIND_REGISTRY[kind].canComplete?.(state) === false) {
    result.completeSession = false;
    result.completionRefused = true;
  }

  // Per-session memory buffer (summarized into relationship_memory on
  // completeSession — CONTRACTS §5).
  if (result.memoryNotes.length > 0) {
    next._memoryBuffer = [
      ...(Array.isArray(next._memoryBuffer) ? next._memoryBuffer : []),
      ...result.memoryNotes,
    ];
  }

  return result;
}

// ---------------------------------------------------------------------------
// MODEL_LIGHT helpers
// ---------------------------------------------------------------------------

/** Cap ≈ 800 tokens ≈ 3200 chars (CONTRACTS §5). */
export const RELATIONSHIP_MEMORY_MAX_CHARS = 3200;

/**
 * On completeSession: fold the per-session memory buffer into the enrollment's
 * relationship memory using MODEL_LIGHT. Returns the new memory text, hard
 * capped at ~3200 chars.
 */
export async function summarizeRelationshipMemory(
  existingMemory: string,
  memoryBuffer: string[],
  usage?: UsageSink,
): Promise<string> {
  if (memoryBuffer.length === 0) return existingMemory.slice(0, RELATIONSHIP_MEMORY_MAX_CHARS);

  const client = anthropicClient();
  const stream = client.messages.stream({
    model: MODEL_LIGHT,
    max_tokens: MAX_TOKENS_SUMMARY,
    system:
      "You maintain a professor's private memory about one student. Merge the " +
      "existing memory with the new session notes into a single plain-text " +
      "memory under 800 tokens. Keep: name/goals, recurring strengths and " +
      "weaknesses, key past insights, commitments made. Drop: pleasantries, " +
      "one-off details. Output ONLY the merged memory text.",
    messages: [{
      role: "user",
      content: `EXISTING MEMORY:\n${existingMemory || "(empty)"}\n\nNEW SESSION NOTES:\n- ${
        memoryBuffer.join("\n- ")
      }`,
    }],
  });
  const final = await stream.finalMessage();
  usage?.add(final.usage);
  const text = final.content
    .filter((b) => b.type === "text")
    .map((b) => (b as { text: string }).text)
    .join("")
    .trim();
  return (text || existingMemory).slice(0, RELATIONSHIP_MEMORY_MAX_CHARS);
}

const QUIZ_GEN_SCHEMA = {
  type: "object",
  properties: {
    questions: {
      type: "array",
      items: {
        type: "object",
        properties: {
          question: { type: "string" },
          answer: { type: "string", description: "Concise reference answer." },
          passageId: {
            anyOf: [{ type: "string" }, { type: "null" }],
            description: "ID of the passage the question is drawn from.",
          },
        },
        required: ["question", "answer", "passageId"],
        additionalProperties: false,
      },
    },
  },
  required: ["questions"],
  additionalProperties: false,
} as const;

/**
 * Generate 5 comprehension-check questions from the unit's reading-span
 * passages using MODEL_LIGHT (SCOPE §3.2.6).
 */
export async function generateQuizQuestions(
  unit: CourseUnit,
  passages: { id: string; text: string }[],
  usage?: UsageSink,
): Promise<QuizQuestion[]> {
  const client = anthropicClient();
  const source = passages
    .map((p) => `[${p.id}]\n${p.text}`)
    .join("\n\n---\n\n")
    .slice(0, 24_000);

  const stream = client.messages.stream({
    model: MODEL_LIGHT,
    max_tokens: MAX_TOKENS_SUMMARY,
    output_config: { format: { type: "json_schema", schema: QUIZ_GEN_SCHEMA } },
    system:
      "Write exactly 5 short factual comprehension-check questions for a " +
      "literature course, answerable only by someone who actually did the " +
      "assigned reading. Plot, character, and concrete detail — no themes, " +
      "no interpretation. Each question cites the passage it is drawn from.",
    messages: [{
      role: "user",
      content: `Unit: "${unit.title}". Reading-span passages:\n\n${source}`,
    }],
  });
  const final = await stream.finalMessage();
  usage?.add(final.usage);
  const text = final.content
    .filter((b) => b.type === "text")
    .map((b) => (b as { text: string }).text)
    .join("");
  const parsed = JSON.parse(text) as { questions: QuizQuestion[] };
  return parsed.questions.slice(0, 5);
}

const QUIZ_GRADE_SCHEMA = {
  type: "object",
  properties: {
    correct: { type: "boolean" },
    note: { type: "string", description: "One-line justification." },
  },
  required: ["correct", "note"],
  additionalProperties: false,
} as const;

/** Grade one quiz answer against the reference answer using MODEL_LIGHT. */
export async function gradeQuizAnswer(
  question: QuizQuestion,
  studentAnswer: string,
  usage?: UsageSink,
): Promise<{ correct: boolean; note: string }> {
  const client = anthropicClient();
  const stream = client.messages.stream({
    model: MODEL_LIGHT,
    max_tokens: 256,
    output_config: { format: { type: "json_schema", schema: QUIZ_GRADE_SCHEMA } },
    system:
      "Grade a reading-comprehension quiz answer. The student need not match " +
      "the reference wording — grade on substance. Be fair but not generous.",
    messages: [{
      role: "user",
      content:
        `QUESTION: ${question.question}\nREFERENCE ANSWER: ${question.answer}\nSTUDENT ANSWER: ${studentAnswer}`,
    }],
  });
  const final = await stream.finalMessage();
  usage?.add(final.usage);
  const text = final.content
    .filter((b) => b.type === "text")
    .map((b) => (b as { text: string }).text)
    .join("");
  return JSON.parse(text) as { correct: boolean; note: string };
}
