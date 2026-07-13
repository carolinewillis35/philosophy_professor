// kinds_agora.ts — the E-M4 "Agora" session kind (CONTRACTS §16): symposium.
//
// Modeled on the platform disputation (§11.2) but QUESTION-anchored: no
// reading span, no passages, citations empty. STANDALONE (§13.1),
// dual-persona (both docs loaded, speakers[] multi-voice envelope).

import type { DisputeVolley, KindContext, KindDef } from "./engine.ts";

// ---------------------------------------------------------------------------
// Authored spec (§16.1)
// ---------------------------------------------------------------------------

export interface SymposiumPosition {
  label: string;
  ontologyId: string | null;
}

export interface SymposiumSpec {
  id: string;
  question: string;
  personaA: string;
  personaB: string;
  positionA: SymposiumPosition;
  positionB: SymposiumPosition;
  crux: string;
  volleys?: DisputeVolley[];
  relatedClaims?: string[];
}

export type SymposiumPhase =
  | "question_presented"
  | "exchange"
  | "adjudication"
  | "cross_examination"
  | "joint_debrief";

export interface SymposiumState {
  symposiumId: string | null;
  month: number | null;
  phase: SymposiumPhase;
  volley: number;
  position: { side: string; statement: string } | null;
}

const SYMPOSIUM_PHASES: SymposiumPhase[] = [
  "question_presented",
  "exchange",
  "adjudication",
  "cross_examination",
  "joint_debrief",
];

export const symposium: KindDef = {
  initialState(_unit, opts) {
    const spec = opts?.spec as SymposiumSpec | undefined;
    const state: SymposiumState = {
      symposiumId: spec?.id ?? null,
      month: null, // stamped by the session function
      phase: "question_presented",
      volley: 0,
      position: null,
    };
    return state;
  },

  instructionBlock(state, ctx: KindContext) {
    const s = state as SymposiumState;
    const spec = ctx.spec as SymposiumSpec | undefined;
    if (!spec) {
      return `SESSION KIND: symposium — SPEC MISSING for "${s.symposiumId}". Apologize in character and end the session with {"op":"completeSession"}.`;
    }
    const labelA = spec.personaA.toUpperCase();
    const labelB = spec.personaB.toUpperCase();
    const volleys = (spec.volleys ?? [])
      .map((v) => `  ${v.speaker.toUpperCase()}: ${v.say}`)
      .join("\n");
    const rejected = s.position?.side
      ? (s.position.side === spec.personaA ? spec.personaB : spec.personaA)
      : null;
    const lines: string[] = [
      `SESSION KIND: symposium — THE MONTHLY EVENT. Phase: ${s.phase}. Volley: ${s.volley}.`,
      `The question before the house: "${spec.question}"`,
      `${labelA} argues: ${spec.positionA.label}`,
      `${labelB} argues: ${spec.positionB.label}`,
      `The crux — where the sides actually part: ${spec.crux}`,
      "TWO voices share this session (speakers[] contract, §11.1): every turn's say carries the labeled dialogue and speakers[] mirrors it. Both argue at FULL strength — a weak side is a violation. NO WINNER IS EVER DECLARED, by either voice or the house (§16.6).",
      "The student took a private position before hearing you; you do not know it and never ask for it.",
    ];
    switch (s.phase) {
      case "question_presented":
        lines.push(
          "QUESTION PRESENTED: one voice frames the question and both state their one-liners, neutrally and briefly — the arguments come next. Then advancePhase.",
        );
        break;
      case "exchange":
        lines.push(
          "EXCHANGE: the debate. The authored volleys are your spine — extend them live, in each professor's own documented manner:",
          volleys || "  (no authored volleys — argue from the crux)",
          "The student may interject at any point; either voice may take them up, neither may recruit them. After 3-4 exchanges (volley counter above), advancePhase to adjudication.",
        );
        break;
      case "adjudication":
        lines.push(
          "ADJUDICATION: the student rules. Ask for their ruling AND their reason in their own words. When they rule for a side, emit {\"op\":\"recordPosition\",\"side\":\"<personaId>\",\"statement\":\"<their reason>\"}. If they remain UNDECIDED, that is a legitimate ruling — say so without pressure or relief, emit NO recordPosition, and advancePhase.",
        );
        break;
      case "cross_examination":
        lines.push(
          rejected
            ? `CROSS-EXAMINATION: ${rejected.toUpperCase()} — the side ruled against — cross-examines the ruling: two or three sharp questions at the statement's weakest joint. The student defends or amends. Pressure the ARGUMENT, never the student. Then advancePhase.`
            : "CROSS-EXAMINATION (no ruling): both voices briefly press the undecided position — what evidence WOULD move you? One question each. Then advancePhase.",
        );
        break;
      case "joint_debrief":
        lines.push(
          "JOINT DEBRIEF: both voices. Name explicitly what EACH side sees and what it misses — including your own side's blind spot. No winner, no consolation prize, no 'the truth is somewhere in between' evasion either. If the student's ruling was genuinely their own position, a commitmentOps entry may be warranted (their words). Then completeSession.",
        );
        break;
    }
    lines.push(
      "No retrieval ran; the citations array stays EMPTY. Traditions may be named, never excerpted.",
      "Never mention crowd numbers, percentages, or what other students ruled — the movement figure exists only after this session ends, elsewhere.",
    );
    return lines.filter(Boolean).join("\n");
  },

  onOps(state, ops) {
    const s = state as SymposiumState;
    for (const op of ops) {
      if (op.op === "advancePhase") {
        const i = SYMPOSIUM_PHASES.indexOf(s.phase);
        s.phase = SYMPOSIUM_PHASES[Math.min(i + 1, SYMPOSIUM_PHASES.length - 1)];
      } else if (op.op === "recordPosition") {
        if (s.phase === "adjudication" || s.phase === "exchange") {
          s.position = { side: op.side, statement: op.statement };
          s.phase = "cross_examination";
        }
      }
    }
    // Volley counter: each professor turn during the exchange is one volley.
    if (s.phase === "exchange") s.volley += 1;
  },

  canComplete: (s) => (s as SymposiumState).phase === "joint_debrief",
};

export const agoraKinds = { symposium };
