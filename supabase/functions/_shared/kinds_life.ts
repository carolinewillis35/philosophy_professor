// kinds_life.ts — the E-M3 "Life" session kinds (CONTRACTS §15):
// newsRead, practice, practiceReview.
//
// All are STANDALONE kinds (§13.1). newsRead teaches from a cached weekly
// brief (the model NEVER searches — §15.2/A25); practice runs the Stoic wing
// with Prof. Bede; practiceReview reads a 7-day entries digest.

import type { KindContext, KindDef } from "./engine.ts";

// ---------------------------------------------------------------------------
// newsRead — the news, read philosophically (§15.2)
// ---------------------------------------------------------------------------

export interface NewsLens {
  name: string;
  ontologyId: string;
  oneLiner: string;
}

export interface LensPair {
  id: string;
  domain: string;
  a: NewsLens;
  b: NewsLens;
  splitHint: string;
}

export interface NewsBrief {
  headline: string;
  summary: string;
  question: string;
  domain: string;
  sourceUrls: string[];
  lensPairId: string;
  /** The full pair, embedded at generation time so the brief is
   * self-contained (A25). */
  lensPair: LensPair;
}

/** The spec handed to newsRead's instructionBlock. */
export interface NewsReadSpec {
  brief: NewsBrief;
}

export type NewsPhase = "brief" | "lensA" | "lensB" | "split" | "position";

export interface NewsReadState {
  phase: NewsPhase;
  week: number | null;
}

const NEWS_PHASES: NewsPhase[] = ["brief", "lensA", "lensB", "split", "position"];

export const newsRead: KindDef = {
  initialState(_unit, _opts) {
    const state: NewsReadState = {
      phase: "brief",
      week: null, // stamped by the session function
    };
    return state;
  },

  instructionBlock(state, ctx: KindContext) {
    const s = state as NewsReadState;
    const spec = ctx.spec as NewsReadSpec | undefined;
    const brief = spec?.brief;
    const pair = brief?.lensPair;
    const lines: string[] = [
      `SESSION TYPE: The News, Read Philosophically. Phase: ${s.phase}.`,
      `This week's story: "${brief?.headline ?? "(see brief)"}". The live question: "${brief?.question ?? ""}".`,
      `Brief (your ONLY source on the story — you did not search and you invent no facts beyond it): ${brief?.summary ?? ""}`,
      pair
        ? `The two authored lenses: A = ${pair.a.name} ("${pair.a.oneLiner}") vs B = ${pair.b.name} ("${pair.b.oneLiner}"). Where they characteristically split: ${pair.splitHint}`
        : "",
      "EVEN-HANDED BY CONSTRUCTION: each lens gets its full phase; you never rank the lenses, never hint at a house verdict, and you steer the STUDENT to do the reasoning in both.",
    ];
    switch (s.phase) {
      case "brief":
        lines.push(
          "BRIEF: Present the story neutrally in 3-4 sentences from the brief — facts, then the philosophical question inside them. No framing that favors either lens. Confirm the student has the question, then advancePhase.",
        );
        break;
      case "lensA":
        lines.push(
          `LENS A — ${pair?.a.name ?? "(A)"}: the student reasons the question through this framework. What would it say here, and WHY — which feature of the case does it seize on? You supply the framework's discipline, not its conclusion. When the reading is on the table, advancePhase.`,
        );
        break;
      case "lensB":
        lines.push(
          `LENS B — ${pair?.b.name ?? "(B)"}: same work, other framework — and do it just as well; a weak lens B is a violation of the even-handedness contract. When the reading is on the table, advancePhase.`,
        );
        break;
      case "split":
        lines.push(
          "THE SPLIT: name precisely where the two readings diverge and WHY — which premise, which weighting, which picture of the person. The split is the payload: the student should leave seeing that the disagreement is structured, not noise. Then advancePhase.",
        );
        break;
      case "position":
        lines.push(
          "POSITION: the student MAY take a position — if they genuinely do, commitmentOps apply (their words, their claim). DECLINING to take one is a legitimate philosophical outcome; say so plainly, without relief or disappointment. Then completeSession.",
        );
        break;
    }
    lines.push(
      "No retrieval ran; the citations array stays EMPTY. The canon is discussed, never excerpted; the story's sources render client-side from the brief.",
      "NEVER present crowd numbers, poll results, or 'most people think' framing on this question — not from the brief, not from memory (§14.6/§15.2).",
    );
    return lines.filter(Boolean).join("\n");
  },

  onOps(state, ops) {
    const s = state as NewsReadState;
    for (const op of ops) {
      if (op.op === "advancePhase") {
        const i = NEWS_PHASES.indexOf(s.phase);
        s.phase = NEWS_PHASES[Math.min(i + 1, NEWS_PHASES.length - 1)];
      }
    }
  },

  canComplete: (s) => (s as NewsReadState).phase === "position",
};

// ---------------------------------------------------------------------------
// practice — the Stoic wing (§15.3): morning / evening / visualization
// ---------------------------------------------------------------------------

export type PracticeMode = "morning" | "evening" | "visualization";

export interface PracticeExerciseDoc {
  id: string;
  prompt?: string; // morning
  title?: string; // visualization
  exercise?: string; // visualization
  debrief?: string; // visualization
  questions?: string[]; // examen
}

export interface PracticeSpec {
  mode: PracticeMode;
  exercise: PracticeExerciseDoc;
}

export interface PracticeState {
  mode: PracticeMode;
  exerciseId: string | null;
  localDate: string | null;
  /** evening: examen questions asked so far; visualization: steps walked. */
  step: number;
}

export const EXAMEN_QUESTIONS = [
  "What disturbed you today?",
  "Was it in your control?",
  "What would you do differently?",
];

export const practice: KindDef = {
  initialState(_unit, opts) {
    const spec = opts?.spec as PracticeSpec | undefined;
    const state: PracticeState = {
      mode: spec?.mode ?? "morning",
      exerciseId: spec?.exercise?.id ?? null,
      localDate: null, // stamped by the session function
      step: 0,
    };
    return state;
  },

  instructionBlock(state, ctx: KindContext) {
    const s = state as PracticeState;
    const spec = ctx.spec as PracticeSpec | undefined;
    const ex = spec?.exercise;
    const lines: string[] = [
      `SESSION TYPE: Practice (the Stoic wing). Mode: ${s.mode}. Step: ${s.step}.`,
      "This is TRAINING, not therapy — and never diagnosis. The register is the gymnasium: concrete, brief, about the day. If the student brings distress beyond the philosophical (grief that isn't abstract, harm, crisis), stop the exercise, name the limit plainly, and point at the human step — a person they trust, or professional help.",
    ];
    switch (s.mode) {
      case "morning":
        lines.push(
          `Today's intention prompt: "${ex?.prompt ?? "(see exercises)"}".`,
          "TWO beats, no more. If the student has NOT yet stated an intention (no user turn in the transcript): present today's prompt in one or two lines, in your register, and stop — no completeSession yet. Once they HAVE stated it: reply EXACTLY ONCE — at most 80 words, Stoic register, sharpen the intention toward what is in their control or name the obstacle it will meet before noon; nothing that demands an answer — and emit {op:\"completeSession\"} + uiHints.endOfSession = true in that SAME turn.",
        );
        break;
      case "evening":
        lines.push(
          "THE EXAMEN — three fixed questions, ONE per turn, in order. Ask, then listen; do not editorialize between answers beyond a single acknowledging line:",
          ...EXAMEN_QUESTIONS.map((q, i) => `  ${i + 1}. ${q}`),
          `Questions asked so far: ${s.step}. After each of your turns that ASKS one, emit {op:"advancePhase"} (it counts the question).`,
          s.step >= EXAMEN_QUESTIONS.length
            ? "All three are answered. Reflect briefly — one pattern you actually heard across the three answers, about the DAY, never about the student's worth. Then completeSession."
            : "The examen is about the day, never about the self's worth.",
        );
        break;
      case "visualization":
        lines.push(
          `Today's exercise: "${ex?.title ?? ""}" — walk it in 2-3 turns, from the authored text (your words may frame, the exercise leads): ${ex?.exercise ?? "(see exercises)"}`,
          `Steps walked: ${s.step}. Emit {op:"advancePhase"} after each turn that advances the exercise.`,
          s.step >= 2
            ? `Close with the authored debrief, in your register: ${ex?.debrief ?? ""} Then completeSession.`
            : "Never morbid for its own sake: the loss is rehearsed so the having is felt.",
        );
        break;
    }
    lines.push(
      "No retrieval ran; the citations array stays EMPTY. Marcus, Epictetus, Seneca may be invoked, never excerpted.",
      "No mood tracking, no scores, no streak talk — the practice is its own ledger.",
    );
    return lines.filter(Boolean).join("\n");
  },

  onOps(state, ops) {
    const s = state as PracticeState;
    for (const op of ops) {
      if (op.op === "advancePhase") s.step += 1;
    }
  },

  // morning is force-completed by the server on its single reply (§15.3);
  // evening completes after the third question; visualization after 2 steps.
  canComplete: (s) => {
    const st = s as PracticeState;
    if (st.mode === "morning") return true;
    if (st.mode === "evening") return st.step >= EXAMEN_QUESTIONS.length;
    return st.step >= 2;
  },
};

// ---------------------------------------------------------------------------
// practiceReview — the weekly look-back (§15.3)
// ---------------------------------------------------------------------------

export interface PracticeReviewState {
  phase: "review" | "reflection";
}

export const practiceReview: KindDef = {
  initialState(_unit, _opts) {
    const state: PracticeReviewState = { phase: "review" };
    return state;
  },

  instructionBlock(state, ctx: KindContext) {
    const s = state as PracticeReviewState;
    const lines: string[] = [
      `SESSION TYPE: Practice Review (weekly). Phase: ${s.phase}.`,
      ctx.practiceDigestPresent
        ? "The student's last seven days of practice entries are in <context> as the practice digest. Work from what is THERE — quote their own words back sparingly and exactly; invent nothing."
        : "No practice digest is available — the student has no entries this week. Say so without reproach and make THIS conversation the week's single entry: what disturbed them this week, and was it in their control?",
    ];
    if (s.phase === "review") {
      lines.push(
        "REVIEW: name the patterns you actually see — what disturbed them repeatedly, where something outside their control was treated as inside it, which intentions kept reappearing unmet. Two or three observations, receipts attached, about the days, never about their worth. Then advancePhase.",
      );
    } else {
      lines.push(
        "REFLECTION: the student names ONE adjustment for next week — theirs, in their words, small enough to fail visibly. You may sharpen it toward what is in their control; you do not assign it. Then completeSession.",
      );
    }
    lines.push(
      "Training, not therapy (the §15.3 line holds here too): distress beyond the philosophical → name the limit, point at the human step.",
      "No retrieval ran; the citations array stays EMPTY.",
    );
    return lines.filter(Boolean).join("\n");
  },

  onOps(state, ops) {
    const s = state as PracticeReviewState;
    for (const op of ops) {
      if (op.op === "advancePhase" && s.phase === "review") s.phase = "reflection";
    }
  },

  canComplete: (s) => (s as PracticeReviewState).phase === "reflection",
};

// ---------------------------------------------------------------------------
// Practice digest (§15.3) — pure, testable
// ---------------------------------------------------------------------------

export interface PracticeEntryRow {
  mode: string;
  entry: string;
  local_date: string;
}

/** ≤~200-token digest of the last week's entries for practiceReview. */
export function buildPracticeDigest(entries: PracticeEntryRow[]): string | null {
  if (entries.length === 0) return null;
  const lines = entries
    .slice(0, 14) // hard cap; newest-first input expected
    .map((e) => {
      const text = e.entry.length > 160 ? `${e.entry.slice(0, 157)}…` : e.entry;
      return `- ${e.local_date} [${e.mode}] ${text}`;
    });
  return `PRACTICE DIGEST (last 7 days, ${entries.length} entries):\n${lines.join("\n")}`;
}

export const lifeKinds = { newsRead, practice, practiceReview };
