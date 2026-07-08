// kinds_academy.ts — the three Academy session kinds (CONTRACTS §12.1):
// elenchus, thoughtExperiment, argumentLab.
//
// Conforms to the engine's declarative kind registry (§11.2): each kind =
// { initialState(courseUnit, opts?), instructionBlock(state, ctx), onOps
// (state, ops) } using the engine's own KindDef/KindContext types, plus the
// Academy completion guard canComplete(state) (§12.8) — the engine consults
// it before honoring a completeSession op. Registered in engine.ts
// KIND_REGISTRY; authored spec shapes (§12.5) are defined and exported here.

import type { KindContext, KindDef, ReadingSpan } from "./engine.ts";

// ---------------------------------------------------------------------------
// Authored spec shapes (course JSON additions, CONTRACTS §12.5)
// ---------------------------------------------------------------------------

export interface ClassicMove {
  definition: string;
  counterexample: string;
}

export interface ElenchusSpec {
  id: string;
  openingQuestion: string;
  span: ReadingSpan;
  passageIds?: string[];
  classicMoves?: ClassicMove[];
  relatedClaims?: string[];
  reflectionPrompt?: string;
}

export interface ThoughtExperimentNode {
  id: string;
  text: string;
  options?: { label: string; next: string }[];
  terminal?: boolean;
}

export interface ThoughtExperimentPump {
  id: string;
  afterNode: string;
  variation: string;
  testsPrinciple: string;
}

export interface ThoughtExperimentSpec {
  id: string;
  title: string;
  setup: string;
  philosophicalPayload: string;
  sourceRefs?: string[];
  nodes: ThoughtExperimentNode[];
  pumps?: ThoughtExperimentPump[];
  interrogation?: string[];
  relatedClaims?: string[];
}

export interface ArgumentPremise {
  id: string;
  text: string;
  stated: boolean;
  supports: string;
}

export interface ArgumentLabSpec {
  id: string;
  title: string;
  source: { bookID: string; passageIds?: string[] };
  conclusion: { id: string; text: string };
  premises: ArgumentPremise[];
  mode: "hunt" | "collapse";
  hiddenPremiseId?: string;
  removedPremiseId?: string | null;
  pedagogicalPoint?: string;
  elicitationQuestions?: string[];
  relatedClaims?: string[];
}

export type AcademySpec = ElenchusSpec | ThoughtExperimentSpec | ArgumentLabSpec;

// ---------------------------------------------------------------------------
// elenchus — thesis → definition → counterexample → revision → (loop) →
// reflection. Aporia is a designed success state. (§12.1)
// ---------------------------------------------------------------------------

export type ElenchusPhase =
  | "thesis" | "definition" | "counterexample" | "revision" | "reflection";

export interface ElenchusState {
  phase: ElenchusPhase;
  thesis: string | null;
  currentDefinition: string | null;
  revisions: number;
  counterexamplesSurvived: number;
  outcome: "aporia" | "robust" | null;
  specId: string | null;
}

export const MAX_REVISIONS = 4;

export const elenchus: KindDef = {
  initialState(_unit, opts) {
    const spec = opts?.spec as ElenchusSpec | undefined;
    const state: ElenchusState = {
      phase: "thesis",
      thesis: null,
      currentDefinition: null,
      revisions: 0,
      counterexamplesSurvived: 0,
      outcome: null,
      specId: spec?.id ?? null,
    };
    return state;
  },

  instructionBlock(state, ctx: KindContext) {
    const s = state as ElenchusState;
    const spec = ctx.spec as ElenchusSpec | undefined;
    const lines: string[] = [
      `SESSION TYPE: Elenchus (the Socratic gauntlet). Phase: ${s.phase}.`,
      "This session's goal is a genuine elenchus: extract the student's definition, test it with counterexamples, and drive toward either a robust position or productive aporia. Aporia is a SUCCESS state — knowing what you don't know — and must never be framed as failure.",
      "You speak less than 40% of the tokens. Your instrument is the question. One counterexample at a time; let it land before the next.",
    ];
    switch (s.phase) {
      case "thesis":
        lines.push(
          spec?.openingQuestion
            ? `Open with the authored question: "${spec.openingQuestion}". When the student states a position, emit {op:"recordThesis", thesis} and advancePhase.`
            : `Invite the student to state a position they actually hold on the unit's question. When they do, emit {op:"recordThesis", thesis} and advancePhase.`,
        );
        break;
      case "definition":
        lines.push(
          `The thesis on the table: "${s.thesis ?? ""}". Extract the definition doing the work inside it — what do they MEAN by the key term? Do not supply the definition; pull it out of them. When a working definition is stated, emit {op:"reviseDefinition", definition} and advancePhase.`,
        );
        break;
      case "counterexample":
        lines.push(
          `Working definition: "${s.currentDefinition ?? ""}" (revision ${s.revisions} of ${MAX_REVISIONS}; counterexamples survived: ${s.counterexamplesSurvived}).`,
          "Produce ONE counterexample that this definition cannot digest — concrete, vivid, preferably from the assigned text (cite via citations[]) or ordinary life. Ask the student what the definition says about the case; do not answer for them.",
          "If the definition SURVIVES an honest counterexample, say so plainly — surviving is information — and either try one more angle or, if it has survived repeatedly, emit {op:\"declareOutcome\", outcome:\"robust\"}.",
        );
        if (spec?.classicMoves?.length) {
          lines.push(
            "Authored spine — the classical moves for this text (use them when the student's definition walks into one; do not force them):",
            ...spec.classicMoves.map((m) => `- definition "${m.definition}" → counterexample: ${m.counterexample}`),
          );
        }
        break;
      case "revision":
        lines.push(
          `The student is revising after a counterexample bit. Help them state the NEW definition precisely — what exactly changed and what the change concedes. Then emit {op:"reviseDefinition", definition} and advancePhase (back to counterexample).`,
          s.revisions >= MAX_REVISIONS - 1
            ? `This is the final permitted revision (cap ${MAX_REVISIONS}). After testing it you MUST emit {op:"declareOutcome"} — "robust" if it held, "aporia" if the definitions keep dying. Do not extend the loop.`
            : "",
        );
        break;
      case "reflection":
        lines.push(
          s.outcome === "aporia"
            ? "Outcome: APORIA. Sit with the student in the productive discomfort briefly — then the reflection: name concretely what the dismantling taught. Which definitions died, and what killed each one? What does the student now know that they didn't this morning (even if it is the shape of their own not-knowing)? Thank them for the contradiction — you mean it."
            : "Outcome: ROBUST. The definition survived. The reflection names what it survived and why, and what would still test it. Guard against triumph: a position that survived four counterexamples is a position worth holding lightly.",
          spec?.reflectionPrompt ? `Authored reflection prompt: "${spec.reflectionPrompt}"` : "",
          "End with the student saying, in their own words, what they now think. Only then emit {op:\"completeSession\"}.",
        );
        break;
    }
    if (s.phase !== "reflection") {
      lines.push("completeSession is NOT available in this phase; the session ends only from reflection.");
    }
    lines.push(
      "If the student genuinely asserts (not merely explores) a philosophical position along the way, you may emit commitmentOps — the thesis and the final position are the usual candidates.",
      ctx.pace === "relaxed"
        ? "Intensity: gentle — counterexamples come with footholds; the aporia landing is cushioned, never softened into agreement."
        : ctx.pace === "intensive"
        ? "Intensity: rigorous — let silences sit; counterexamples come bare; do not rescue a dying definition early."
        : "",
    );
    return lines.filter(Boolean).join("\n");
  },

  onOps(state, ops) {
    const s = state as ElenchusState;
    for (const op of ops) {
      switch (op.op) {
        case "recordThesis":
          if (typeof op.thesis === "string" && s.phase === "thesis") {
            s.thesis = op.thesis;
            s.phase = "definition";
          }
          break;
        case "reviseDefinition":
          if (typeof op.definition === "string" &&
              (s.phase === "definition" || s.phase === "revision")) {
            s.currentDefinition = op.definition;
            if (s.phase === "revision") s.revisions += 1;
            s.phase = "counterexample";
          }
          break;
        case "declareOutcome":
          if ((op.outcome === "aporia" || op.outcome === "robust") && s.outcome === null) {
            s.outcome = op.outcome;
            if (op.outcome === "robust") s.counterexamplesSurvived += 1;
            s.phase = "reflection";
          }
          break;
        case "advancePhase":
          // Generic step used for thesis→definition handoff when the model
          // pairs it with recordThesis, and counterexample→revision.
          if (s.phase === "counterexample") s.phase = "revision";
          break;
      }
      // Hard cap (§12.1 / DECISIONS A13): force an outcome at the revision cap.
      if (s.revisions >= MAX_REVISIONS && s.outcome === null) {
        s.outcome = "aporia";
        s.phase = "reflection";
      }
    }
  },

  canComplete: (s) => (s as ElenchusState).phase === "reflection",
};

// ---------------------------------------------------------------------------
// thoughtExperiment — authored branching nodes render client-side; the
// professor enters at interrogation/debrief. (§12.1, DECISIONS A10)
// ---------------------------------------------------------------------------

export interface ThoughtExperimentState {
  specId: string | null;
  nodeId: string;
  path: Array<{ nodeId: string; choice: string }>;
  pumpsApplied: string[];
  phase: "run" | "interrogation" | "debrief";
}

export const thoughtExperiment: KindDef = {
  initialState(_unit, opts) {
    const spec = opts?.spec as ThoughtExperimentSpec | undefined;
    const state: ThoughtExperimentState = {
      specId: spec?.id ?? null,
      nodeId: "start",
      path: [],
      pumpsApplied: [],
      phase: "run",
    };
    return state;
  },

  instructionBlock(state, ctx: KindContext) {
    const s = state as ThoughtExperimentState;
    const spec = ctx.spec as ThoughtExperimentSpec | undefined;
    const pathSummary = s.path.map((p) => `${p.nodeId} → "${p.choice}"`).join("; ") || "(none yet)";
    const lines: string[] = [
      `SESSION TYPE: Thought-Experiment Lab — "${spec?.title ?? s.specId}". Phase: ${s.phase}.`,
      `The student's choices so far: ${pathSummary}. Pumps applied: ${s.pumpsApplied.join(", ") || "none"}.`,
    ];
    switch (s.phase) {
      case "run":
        lines.push(
          "The client renders the authored scenario and choices; your turns during the run are MINIMAL — acknowledge the choice in one sentence, apply authored pumps via {op:\"applyPump\", pumpId} when the spec directs, and record choices via {op:\"recordChoice\", nodeId, choice}. Do NOT interrogate yet; let the experiment do its work. When branches/pumps are exhausted, advancePhase.",
        );
        break;
      case "interrogation":
        lines.push(
          "Now the real work: interrogate WHY they chose. Use the authored interrogation questions as your spine, in order, adapting to their actual path:",
          ...((spec?.interrogation ?? []).map((q, i) => `${i + 1}. ${q}`)),
          "Hunt the PRINCIPLE behind their choices: make them state it, then test whether it survives the pump variations they already faced. If their choices across pumps were inconsistent, put the two choices side by side and ask what changed — that inconsistency is the payload, not a mistake.",
          "If the student genuinely asserts the principle as their position, emit a commitmentOp. When the principle has been stated and tested, advancePhase.",
        );
        break;
      case "debrief":
        lines.push(
          `Debrief: name the philosophical payload — ${spec?.philosophicalPayload ?? "(see spec)"} — and connect it to the student's OWN path (their choices, not the textbook's). Cite the canonical source passage(s) via citations[] where the spec provides sourceRefs. Name which philosophers would have taken each of their branches. Then completeSession.`,
        );
        break;
    }
    return lines.filter(Boolean).join("\n");
  },

  onOps(state, ops) {
    const s = state as ThoughtExperimentState;
    for (const op of ops) {
      switch (op.op) {
        case "recordChoice":
          if (typeof op.nodeId === "string" && typeof op.choice === "string") {
            s.path.push({ nodeId: op.nodeId, choice: op.choice });
            s.nodeId = op.nodeId;
          }
          break;
        case "applyPump":
          if (typeof op.pumpId === "string" && !s.pumpsApplied.includes(op.pumpId)) {
            s.pumpsApplied.push(op.pumpId);
          }
          break;
        case "advancePhase":
          s.phase = s.phase === "run" ? "interrogation" : "debrief";
          break;
      }
    }
  },

  canComplete: (s) => (s as ThoughtExperimentState).phase === "debrief",
};

// ---------------------------------------------------------------------------
// argumentLab — deterministic argument map; hidden-premise hunt or collapse.
// (§12.1, DECISIONS A11)
// ---------------------------------------------------------------------------

export interface ArgumentLabState {
  specId: string | null;
  /** Spec mode; collapse-mode sessions skip hunt/reveal (mapPresented→collapse). */
  mode: "hunt" | "collapse";
  phase: "mapPresented" | "hunt" | "reveal" | "collapse" | "rebuild";
  attempts: number;
  found: boolean;
}

export const argumentLab: KindDef = {
  initialState(_unit, opts) {
    const spec = opts?.spec as ArgumentLabSpec | undefined;
    const state: ArgumentLabState = {
      specId: spec?.id ?? null,
      mode: spec?.mode === "collapse" ? "collapse" : "hunt",
      phase: "mapPresented",
      attempts: 0,
      found: false,
    };
    return state;
  },

  instructionBlock(state, ctx: KindContext) {
    const s = state as ArgumentLabState;
    const spec = ctx.spec as ArgumentLabSpec | undefined;
    const hidden = spec?.premises?.find((p) => p.id === spec?.hiddenPremiseId);
    const lines: string[] = [
      `SESSION TYPE: Argument Lab — "${spec?.title ?? s.specId}" (mode: ${spec?.mode ?? "hunt"}). Phase: ${s.phase}. Attempts: ${s.attempts}.`,
      "The client renders the argument map deterministically from the spec; you do not restate the whole map. Citations always point at the ORIGINAL source passages.",
    ];
    switch (s.phase) {
      case "mapPresented":
        lines.push(
          "Orient briefly: whose argument, where it lives in the text (cite), and what the map shows. In hunt mode: one premise slot is dashed and empty — the author never wrote it down, and the argument doesn't reach its conclusion without it. Invite the hunt, then advancePhase.",
        );
        break;
      case "hunt":
        lines.push(
          `THE HIDDEN PREMISE (known to you, NEVER to be stated before reveal): "${hidden?.text ?? "(see spec)"}".`,
          "HARD RULE: you never state, paraphrase-closely, or multiple-choice the hidden premise in this phase. You narrow with questions: 'What has to be true for that premise to reach the conclusion? It isn't written down. That's the point.' Use the authored elicitation questions:",
          ...((spec?.elicitationQuestions ?? []).map((q, i) => `${i + 1}. ${q}`)),
          "When the student proposes a candidate, test it against the map: does the argument now go through? Record attempts via {op:\"recordHuntResult\", found, attempts}. When they find it (or after honest exhaustion — attempts ≥ 4), advancePhase to reveal.",
        );
        break;
      case "reveal":
        lines.push(
          "Reveal: state the hidden premise exactly, credit the student's nearest miss ('your candidate was two-thirds of it'), and show WHY it is load-bearing — what the conclusion loses without it. Pedagogical point:",
          spec?.pedagogicalPoint ?? "",
          "Then advancePhase to rebuild (or collapse, if the spec continues).",
        );
        break;
      case "collapse":
        lines.push(
          `A premise has been removed (client greys it out: "${spec?.premises?.find((p) => p.id === spec?.removedPremiseId)?.text ?? "(see spec)"}"). Ask what broke — not whether it broke. The student should articulate which inferences no longer go through and what the conclusion would need instead. Then advancePhase.`,
        );
        break;
      case "rebuild":
        lines.push(
          "Rebuild: the student restates the argument whole, in their own words, premises numbered. Then the graduation question: which premise would THEY attack, and is that an attack on a premise or on an inference? If they assert a position on the argument's conclusion, a commitmentOp may be warranted. Then completeSession.",
        );
        break;
    }
    return lines.filter(Boolean).join("\n");
  },

  onOps(state, ops) {
    const s = state as ArgumentLabState;
    // Per-mode phase order (§12.1): hunt runs mapPresented→hunt→reveal→rebuild;
    // collapse skips the hunt and runs mapPresented→collapse→rebuild.
    const order: ArgumentLabState["phase"][] = s.mode === "collapse"
      ? ["mapPresented", "collapse", "rebuild"]
      : ["mapPresented", "hunt", "reveal", "rebuild"];
    for (const op of ops) {
      switch (op.op) {
        case "recordHuntResult":
          if (typeof op.attempts === "number") s.attempts = op.attempts;
          if (typeof op.found === "boolean") s.found = op.found;
          break;
        case "advancePhase": {
          const i = order.indexOf(s.phase);
          s.phase = order[Math.min(i + 1, order.length - 1)];
          break;
        }
      }
    }
  },

  canComplete: (s) => (s as ArgumentLabState).phase === "rebuild",
};

export const academyKinds = { elenchus, thoughtExperiment, argumentLab };
