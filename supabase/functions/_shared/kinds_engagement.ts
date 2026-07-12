// kinds_engagement.ts — the engagement session kinds (CONTRACTS §13 + §14.4):
// dailyQuestion, argumentClinic, steelman.
//
// All are STANDALONE kinds (§13.1): no enrollment, no course unit, no
// retrieval — citations stay empty by contract. They conform to the engine's
// declarative kind registry (KindDef) and are registered in engine.ts
// KIND_REGISTRY.

import type { KindContext, KindDef } from "./engine.ts";

// ---------------------------------------------------------------------------
// dailyQuestion — the sixty-second ritual (§13.2)
// ---------------------------------------------------------------------------

export interface DailyQuestionOption {
  id: string;
  label: string;
  /** Canonical claim id the tap maps to; null when the option is unmapped. */
  ontologyId: string | null;
}

export interface DailyQuestionSpec {
  id: string;
  question: string;
  domain: string;
  personaId: string;
  options: DailyQuestionOption[];
  relatedClaims?: string[];
}

export interface DailyQuestionState {
  questionId: string | null;
  optionId: string | null;
  replied: boolean;
}

export const dailyQuestion: KindDef = {
  initialState(_unit, opts) {
    const spec = opts?.spec as DailyQuestionSpec | undefined;
    const state: DailyQuestionState = {
      questionId: spec?.id ?? null,
      optionId: null, // stamped by the session function from the start request
      replied: false,
    };
    return state;
  },

  instructionBlock(state, ctx: KindContext) {
    const s = state as DailyQuestionState;
    const spec = ctx.spec as DailyQuestionSpec | undefined;
    const option = spec?.options.find((o) => o.id === s.optionId);
    return [
      `SESSION TYPE: Daily Question — the sixty-second ritual.`,
      `Today's question: "${spec?.question ?? "(see transcript)"}"`,
      option
        ? `The student tapped: "${option.label}". Their one-sentence why (if any) is the user turn.`
        : "The student's position and one-sentence why are in the user turn.",
      "You reply EXACTLY ONCE, then the session is over. The reply contract (§13.2):",
      "- At most 120 words. This is a coffee-length exchange, not a seminar.",
      "- Make ONE move, no more: sharpen their stated position, OR name the tradition it belongs to and its best enemy, OR complicate it with the cost it carries. Pick whichever their sentence earns.",
      "- You may END on a question only as food for thought — nothing that demands an answer. The ritual must stay small; the student walks away thinking, not typing.",
      "- No retrieval ran; the citations array stays EMPTY. Name thinkers freely, quote nobody.",
      "- The tap has already been recorded on their worldview at 'lean' strength. Emit a commitmentOps upgrade (op 'assert') ONLY if their typed sentence itself asserts the position in their own words — a bare tap or a hedge never earns 'assert'.",
      "- Emit {op:\"completeSession\"} and uiHints.endOfSession = true in THIS SAME turn.",
    ].join("\n");
  },

  onOps(state, _ops) {
    // Any professor turn IS the single reply (§13.2).
    (state as DailyQuestionState).replied = true;
  },

  // The one reply completes the session; the server additionally forces
  // completion after the reply turn (§13.4 "the ritual stays small").
  canComplete: () => true,
};

// ---------------------------------------------------------------------------
// argumentClinic — "Bring me an argument" (§13.3)
// ---------------------------------------------------------------------------

export type ClinicPhase = "intake" | "excavation" | "map" | "crux" | "handback";

export type CruxKind = "fact" | "value" | "definition";

export interface ClinicPremise {
  id: string;
  text: string;
  /** false = an unstated load-bearer the professor excavated. */
  stated: boolean;
  /** "c" or an existing premise id. */
  supports: string;
}

export interface ClinicState {
  phase: ClinicPhase;
  userArgument: {
    conclusion: { id: "c"; text: string } | null;
    premises: ClinicPremise[];
  };
  cruxes: Array<{ id: string; kind: CruxKind }>;
  /** Bumped on every map mutation; the client re-renders on change. */
  mapVersion: number;
}

export const CLINIC_MAX_PREMISES = 8;

const CLINIC_PHASES: ClinicPhase[] = [
  "intake",
  "excavation",
  "map",
  "crux",
  "handback",
];

const CRUX_KINDS: CruxKind[] = ["fact", "value", "definition"];

export const argumentClinic: KindDef = {
  initialState(_unit, _opts) {
    const state: ClinicState = {
      phase: "intake",
      userArgument: { conclusion: null, premises: [] },
      cruxes: [],
      mapVersion: 0,
    };
    return state;
  },

  instructionBlock(state, _ctx: KindContext) {
    const s = state as ClinicState;
    const mapSummary = s.userArgument.conclusion
      ? `Conclusion c: "${s.userArgument.conclusion.text}". Premises: ${
        s.userArgument.premises.map((p) =>
          `${p.id}${p.stated ? "" : " (unstated)"}: "${p.text}" → ${p.supports}`
        ).join("; ") || "(none yet)"
      }. Cruxes: ${s.cruxes.map((c) => `${c.id}=${c.kind}`).join(", ") || "none"}.`
      : "The map is empty.";
    const lines: string[] = [
      `SESSION TYPE: Argument Clinic ("Bring me an argument"). Phase: ${s.phase}.`,
      "The student brought a LIVE argument from their own life — a disagreement, a take they read, a decision. Your job is what philosophers actually do: extract the structure, find where the reasoning actually lives, and hand judgment back. You build the map incrementally with stateOps; the client renders it deterministically.",
      `Current map: ${mapSummary}`,
    ];
    switch (s.phase) {
      case "intake":
        lines.push(
          "INTAKE: Get the actual claim at issue on the table. People bring feelings, summaries, and other people's words — you want the proposition in dispute. At most TWO clarifying questions; then state the claim back in one clean sentence, confirm it's theirs, and emit {op:\"setConclusion\", text} + advancePhase.",
        );
        break;
      case "excavation":
        lines.push(
          "EXCAVATION: Pull out the premises ONE at a time, in the arguer's own terms, confirming each with the student ('is that what's doing the work?') before emitting {op:\"addPremise\", id:\"p1\", text, stated, supports}. Premises actually said get stated:true; the load-bearing assumptions nobody said out loud get stated:false — those are usually the find.",
          `Ids are p1, p2, … (cap ${CLINIC_MAX_PREMISES}); supports is "c" or an earlier premise's id. Use {op:"revisePremise", id, text} when a premise sharpens. When the structure is on the table, advancePhase.`,
        );
        break;
      case "map":
        lines.push(
          "MAP: The whole structure is now rendered in front of the student. Walk it ONCE, briefly — what rests on what, which premises were never actually said. Do not re-litigate; the map speaks. Then advancePhase.",
        );
        break;
      case "crux":
        lines.push(
          "CRUX: Locate where the disagreement REALLY lives. For each genuine fault line emit {op:\"markCrux\", id, kind} — kind is \"fact\" (an empirical question), \"value\" (a genuine evaluative divergence), or \"definition\" (the parties mean different things by a word). Very often the discovery is that the fight was about something else entirely — say so plainly when it's true; that discovery IS the payload. Then advancePhase.",
        );
        break;
      case "handback":
        lines.push(
          "HANDBACK: Name what would settle it — which crux needs empirical work, which needs a definition agreed on, which is a genuinely evaluative choice no fact can make for them. Then hand judgment back: the map is theirs, the verdict is theirs. If the STUDENT asserted their own position on the issue along the way, a commitmentOps entry may be warranted — never for the other party's side. Then completeSession.",
        );
        break;
    }
    lines.push(
      "GUARDRAILS (§13.4, hard lines):",
      "- You dissect ARGUMENTS. You never referee the relationship, never say who is right, never give life advice. 'I can map the reasoning; the judgment stays yours' is the register.",
      "- If the material turns therapy-adjacent (grief, self-harm, abuse), stop mapping: name the limit plainly and point at the human step — a person they trust, or professional help. Structure extraction is the wrong tool there and you say so.",
      "- No retrieval ran; the citations array stays EMPTY. Name frameworks and thinkers freely; excerpt nobody.",
    );
    return lines.join("\n");
  },

  onOps(state, ops) {
    const s = state as ClinicState;
    const premiseIds = () => new Set(s.userArgument.premises.map((p) => p.id));
    for (const op of ops) {
      switch (op.op) {
        case "setConclusion":
          // Settable in intake (first pass) or excavation (sharpened restatement).
          if (
            typeof op.text === "string" && op.text.trim() &&
            (s.phase === "intake" || s.phase === "excavation")
          ) {
            s.userArgument.conclusion = { id: "c", text: op.text.trim() };
            s.mapVersion += 1;
          }
          break;
        case "addPremise": {
          const valid = typeof op.id === "string" && /^p\d+$/.test(op.id) &&
            !premiseIds().has(op.id) &&
            typeof op.text === "string" && op.text.trim() &&
            typeof op.stated === "boolean" &&
            typeof op.supports === "string" &&
            (op.supports === "c" || premiseIds().has(op.supports)) &&
            s.userArgument.premises.length < CLINIC_MAX_PREMISES &&
            s.userArgument.conclusion !== null;
          if (valid) {
            s.userArgument.premises.push({
              id: op.id,
              text: op.text.trim(),
              stated: op.stated,
              supports: op.supports,
            });
            s.mapVersion += 1;
          }
          break;
        }
        case "revisePremise": {
          const target = s.userArgument.premises.find((p) => p.id === op.id);
          if (target && typeof op.text === "string" && op.text.trim()) {
            target.text = op.text.trim();
            s.mapVersion += 1;
          }
          break;
        }
        case "markCrux": {
          const known = op.id === "c" || premiseIds().has(op.id as string);
          if (known && CRUX_KINDS.includes(op.kind as CruxKind)) {
            const existing = s.cruxes.find((c) => c.id === op.id);
            if (existing) existing.kind = op.kind as CruxKind;
            else s.cruxes.push({ id: op.id as string, kind: op.kind as CruxKind });
            s.mapVersion += 1;
          }
          break;
        }
        case "advancePhase": {
          const i = CLINIC_PHASES.indexOf(s.phase);
          s.phase = CLINIC_PHASES[Math.min(i + 1, CLINIC_PHASES.length - 1)];
          break;
        }
      }
    }
  },

  canComplete: (s) => (s as ClinicState).phase === "handback",
};

// ---------------------------------------------------------------------------
// steelman — state the opposing view so well its holders would sign it
// (§14.4)
// ---------------------------------------------------------------------------

export type SteelmanPhase = "brief" | "attempt" | "probe" | "verdict" | "debrief";

export interface SteelmanState {
  phase: SteelmanPhase;
  /** The student's OWN commitment under examination (stamped at start). */
  targetClaim: string | null;
  targetOntologyId: string | null;
  probeRounds: number;
  level: number | null;
}

export const MAX_PROBE_ROUNDS = 2;

export const STEELMAN_LEVELS: Record<number, string> = {
  1: "strawman — the opponent wouldn't recognize it",
  2: "sketch — recognizable but missing its best premise",
  3: "competent — a holder would nod",
  4: "signable — a holder would sign it as their own statement",
};

const STEELMAN_PHASES: SteelmanPhase[] = [
  "brief",
  "attempt",
  "probe",
  "verdict",
  "debrief",
];

export const steelman: KindDef = {
  initialState(_unit, _opts) {
    const state: SteelmanState = {
      phase: "brief",
      targetClaim: null, // stamped by the session function from the start request
      targetOntologyId: null,
      probeRounds: 0,
      level: null,
    };
    return state;
  },

  instructionBlock(state, _ctx: KindContext) {
    const s = state as SteelmanState;
    const lines: string[] = [
      `SESSION TYPE: Steelman. Phase: ${s.phase}. Probe rounds used: ${s.probeRounds} of ${MAX_PROBE_ROUNDS}.`,
      `The student's own position under examination: "${s.targetClaim ?? "(see transcript)"}".`,
      "The exercise: the student states the best case AGAINST their own position — so well that people who actually hold the opposing view would sign it. The rarest skill on the internet. You grade the ARGUMENT they produce, never the person.",
    ];
    switch (s.phase) {
      case "brief":
        lines.push(
          "BRIEF: Frame the exercise. Name the position they hold, name what the opposing camp actually believes (its best self, not its caricature), and state the bar: would its holders sign what you're about to say? Then advancePhase and invite the attempt.",
        );
        break;
      case "attempt":
        lines.push(
          "ATTEMPT: The student states their steelman. LISTEN WHOLE — do not interrupt the first attempt with corrections. When they've finished a complete statement, advancePhase to probe.",
        );
        break;
      case "probe":
        lines.push(
          "PROBE: Find where the steelman is still a strawman — the missing strongest premise, the uncharitable framing, the opponent's best move rendered weak. ONE probe at a time; let the student revise. A probe names the gap; it does not fill it for them.",
          s.probeRounds >= MAX_PROBE_ROUNDS - 1
            ? `This is the final probe round (cap ${MAX_PROBE_ROUNDS}). After their revision you MUST advancePhase to verdict.`
            : "When the steelman stops improving (or the rounds cap out), advancePhase to verdict.",
        );
        break;
      case "verdict":
        lines.push(
          "VERDICT: Grade the final steelman via {op:\"recordSteelmanScore\", level, justification}. The rubric:",
          ...Object.entries(STEELMAN_LEVELS).map(([n, d]) => `  ${n}: ${d}`),
          "Level 4 is rare and you say so when you give it. The justification is one sentence naming what earned the level — or exactly what would raise it. Grade the argument, not the person; level 1 is named 'strawman', never 'failure'.",
        );
        break;
      case "debrief":
        lines.push(
          `Verdict delivered${s.level ? ` (level ${s.level})` : ""}. DEBRIEF: what does the strongest opposing case teach about the student's OWN position — which of their premises it presses hardest, what they'd have to give up to defect. If the exercise genuinely moved them, that is a live commitmentOps moment (an affirm under fire, or an honest abandon — both are progress and you say so). Then completeSession.`,
        );
        break;
    }
    lines.push(
      "No retrieval ran; the citations array stays EMPTY. Name the opposing tradition's thinkers freely; excerpt nobody.",
    );
    return lines.filter(Boolean).join("\n");
  },

  onOps(state, ops) {
    const s = state as SteelmanState;
    for (const op of ops) {
      switch (op.op) {
        case "recordSteelmanScore":
          if (
            s.level === null &&
            Number.isInteger(op.level) && op.level >= 1 && op.level <= 4 &&
            (s.phase === "probe" || s.phase === "verdict")
          ) {
            s.level = op.level;
            s.phase = "debrief";
          }
          break;
        case "advancePhase": {
          const i = STEELMAN_PHASES.indexOf(s.phase);
          // debrief is reached ONLY through recordSteelmanScore.
          const next = STEELMAN_PHASES[Math.min(i + 1, STEELMAN_PHASES.length - 1)];
          if (next !== "debrief") s.phase = next;
          break;
        }
      }
    }
    // A professor turn spent probing counts a round (the instruction block
    // caps the loop at MAX_PROBE_ROUNDS).
    if (s.phase === "probe") s.probeRounds += 1;
  },

  canComplete: (s) => (s as SteelmanState).phase === "debrief",
};

export const engagementKinds = { dailyQuestion, argumentClinic, steelman };
