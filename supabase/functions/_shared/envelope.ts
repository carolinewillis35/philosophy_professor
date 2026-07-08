// The envelope — model output contract (CONTRACTS §5 + §11.1 "Envelope v2"
// + §12.2 "commitmentOps").
//
// IMPORTANT: "say" MUST be the FIRST property in the schema. The server
// streams it incrementally by scanning the partial JSON (see sayStream.ts),
// which relies on the say string being the first value emitted.
//
// v2 additions (all OPTIONAL — the four v1 fields stay required, old stored
// turns decode fine):
//   * speakers[]  — per-persona dialogue for disputation turns
//   * profileOps[] — reader-profile evidence writes
//   * uiHints.adjudicationRequired — optional key
//   * stateOps recordPosition / advancePhase
// Academy additions (§12.1–§12.2, same pattern — all OPTIONAL):
//   * commitmentOps[] — Commitment Map writes (max 2 per turn, server-side)
//   * stateOps recordThesis / reviseDefinition / declareOutcome /
//     recordChoice / applyPump / recordHuntResult
// Persisted envelopes carry a server-stamped "v": 2 marker (NOT part of the
// model-facing schema — the session function adds it before writing to turns).
//
// additionalProperties:false everywhere (structured-outputs requirement).

// ---------------------------------------------------------------------------
// Profile vocabulary (§11.1 / §11.3)
// ---------------------------------------------------------------------------

export const PROFILE_DIMENSIONS = [
  "character",
  "form",
  "image",
  "structure",
  "context",
  "sound",
] as const;
export type ProfileDimension = (typeof PROFILE_DIMENSIONS)[number];

// §11.1 lists four model-facing kinds; §11.3's contest flow has the model emit
// kind "contest" from an officeHours turn, and the DB check allows it — so the
// schema accepts all five.
export const PROFILE_EVIDENCE_KINDS = [
  "seminar_turn",
  "annotation",
  "essay_rubric",
  "reading_telemetry",
  "contest",
] as const;
export type ProfileEvidenceKind = (typeof PROFILE_EVIDENCE_KINDS)[number];

// ---------------------------------------------------------------------------
// Commitment vocabulary (§12.2 — mirrors commitments.ts, kept value-identical)
// ---------------------------------------------------------------------------

export const COMMITMENT_DOMAINS = [
  "ethics",
  "epistemology",
  "metaphysics",
  "mind",
  "political",
  "aesthetics",
] as const;
export type CommitmentDomain = (typeof COMMITMENT_DOMAINS)[number];

export const COMMITMENT_OP_KINDS = [
  "assert",
  "lean",
  "explore",
  "affirm",
  "abandon",
] as const;
export type CommitmentOpKind = (typeof COMMITMENT_OP_KINDS)[number];

// ---------------------------------------------------------------------------
// JSON Schema (passed as output_config.format.schema)
// ---------------------------------------------------------------------------

const RUBRIC_ITEM_SCHEMA = {
  type: "object",
  properties: {
    name: { type: "string" },
    score: { type: "number" },
    max: { type: "number" },
    justification: { type: "string" },
  },
  required: ["name", "score", "max", "justification"],
  additionalProperties: false,
} as const;

const MARGIN_COMMENT_SCHEMA = {
  type: "object",
  properties: {
    anchor: {
      type: "string",
      description: "An exact sentence copied verbatim from the student's essay.",
    },
    comment: { type: "string" },
  },
  required: ["anchor", "comment"],
  additionalProperties: false,
} as const;

const CITATION_SCHEMA = {
  type: "object",
  properties: {
    passageId: {
      type: "string",
      description:
        'Passage ID like "frankenstein-1818:4:12" — must be one of the retrieved passages.',
    },
    quote: {
      type: "string",
      description: "Exact verbatim substring of that passage's text.",
    },
    why: {
      type: "string",
      description: "1-line reason shown as caption.",
    },
  },
  required: ["passageId", "quote", "why"],
  additionalProperties: false,
} as const;

const STATE_OP_SCHEMA = {
  anyOf: [
    {
      type: "object",
      properties: { op: { const: "advanceSegment" } },
      required: ["op"],
      additionalProperties: false,
    },
    {
      type: "object",
      properties: {
        op: { const: "pushQuestion" },
        question: { type: "string" },
      },
      required: ["op", "question"],
      additionalProperties: false,
    },
    {
      type: "object",
      properties: { op: { const: "popQuestion" } },
      required: ["op"],
      additionalProperties: false,
    },
    {
      type: "object",
      properties: {
        op: { const: "setDepth" },
        depth: { type: "integer" },
      },
      required: ["op", "depth"],
      additionalProperties: false,
    },
    {
      type: "object",
      properties: {
        op: { const: "requireEvidence" },
        value: { type: "boolean" },
      },
      required: ["op", "value"],
      additionalProperties: false,
    },
    {
      type: "object",
      properties: {
        op: { const: "recordGrade" },
        assignmentId: { type: "string" },
        grade: { type: "string" },
        rubric: { type: "array", items: RUBRIC_ITEM_SCHEMA },
        marginComments: { type: "array", items: MARGIN_COMMENT_SCHEMA },
        directives: {
          type: "array",
          items: { type: "string" },
          description: "Exactly 2 concrete revision directives.",
        },
      },
      required: ["op", "assignmentId", "grade", "rubric", "marginComments", "directives"],
      additionalProperties: false,
    },
    {
      type: "object",
      properties: {
        op: { const: "writeMemory" },
        note: {
          type: "string",
          description: "At most 2 sentences about this student.",
        },
      },
      required: ["op", "note"],
      additionalProperties: false,
    },
    {
      type: "object",
      properties: { op: { const: "completeSession" } },
      required: ["op"],
      additionalProperties: false,
    },
    // --- v2 ops (§11.1) ---
    {
      type: "object",
      properties: {
        op: { const: "recordPosition" },
        side: {
          type: "string",
          description: "personaId of the side the student adjudicated FOR.",
        },
        statement: {
          type: "string",
          description: "The student's stated position, in their words.",
        },
      },
      required: ["op", "side", "statement"],
      additionalProperties: false,
    },
    {
      type: "object",
      properties: { op: { const: "advancePhase" } },
      required: ["op"],
      additionalProperties: false,
    },
    // --- Academy ops (§12.1) ---
    {
      type: "object",
      properties: {
        op: { const: "recordThesis" },
        thesis: {
          type: "string",
          description: "The student's stated position, in their words.",
        },
      },
      required: ["op", "thesis"],
      additionalProperties: false,
    },
    {
      type: "object",
      properties: {
        op: { const: "reviseDefinition" },
        definition: {
          type: "string",
          description: "The current working definition under test.",
        },
      },
      required: ["op", "definition"],
      additionalProperties: false,
    },
    {
      type: "object",
      properties: {
        op: { const: "declareOutcome" },
        outcome: { enum: ["aporia", "robust"] },
      },
      required: ["op", "outcome"],
      additionalProperties: false,
    },
    {
      type: "object",
      properties: {
        op: { const: "recordChoice" },
        nodeId: { type: "string" },
        choice: { type: "string" },
      },
      required: ["op", "nodeId", "choice"],
      additionalProperties: false,
    },
    {
      type: "object",
      properties: {
        op: { const: "applyPump" },
        pumpId: { type: "string" },
      },
      required: ["op", "pumpId"],
      additionalProperties: false,
    },
    {
      type: "object",
      properties: {
        op: { const: "recordHuntResult" },
        found: { type: "boolean" },
        attempts: { type: "integer" },
      },
      required: ["op", "found", "attempts"],
      additionalProperties: false,
    },
  ],
} as const;

const SPEAKER_SCHEMA = {
  type: "object",
  properties: {
    personaId: { type: "string" },
    say: { type: "string" },
    citations: { type: "array", items: CITATION_SCHEMA },
  },
  required: ["personaId", "say", "citations"],
  additionalProperties: false,
} as const;

const PROFILE_OP_SCHEMA = {
  type: "object",
  properties: {
    op: { const: "evidence" },
    kind: { enum: PROFILE_EVIDENCE_KINDS },
    dimension: { enum: PROFILE_DIMENSIONS },
    signal: {
      type: "string",
      description: "One-sentence observation with its receipt.",
    },
    weight: { type: "number", description: "0..1" },
  },
  required: ["op", "kind", "dimension", "signal", "weight"],
  additionalProperties: false,
} as const;

export const COMMITMENT_OP_SCHEMA = {
  type: "object",
  properties: {
    op: { enum: COMMITMENT_OP_KINDS },
    claim: {
      type: "string",
      description: "One-sentence position in the student's own terms.",
    },
    domain: { enum: COMMITMENT_DOMAINS },
    ontologyId: {
      type: "string",
      description:
        'Canonical claim id like "ethics.moral-realism" — ONLY when confidently matched.',
    },
    evidence: {
      type: "string",
      description: "Short paraphrase of what the student said.",
    },
  },
  required: ["op", "claim", "domain"],
  additionalProperties: false,
} as const;

export const ENVELOPE_SCHEMA = {
  type: "object",
  properties: {
    // MUST remain the first property — sayStream.ts streams it incrementally.
    say: {
      type: "string",
      description:
        "Professor's prose. Plain text with light markdown. Never contains " +
        "verbatim quotes longer than ~6 words; quotes go in citations. For " +
        'multi-voice turns: the full dialogue with speaker-label lines ("VOSS: ' +
        '…\\n\\nARKADY: …") so streaming reads naturally; mirror it ' +
        "structurally in speakers[].",
    },
    // OPTIONAL — present only in disputation turns.
    speakers: {
      type: "array",
      items: SPEAKER_SCHEMA,
      description:
        "Per-persona dialogue, in speaking order, mirroring the labeled lines in say.",
    },
    citations: {
      type: "array",
      items: CITATION_SCHEMA,
    },
    stateOps: {
      type: "array",
      items: STATE_OP_SCHEMA,
    },
    // OPTIONAL — reader-profile evidence writes (max 2 per turn honored server-side).
    profileOps: {
      type: "array",
      items: PROFILE_OP_SCHEMA,
    },
    // OPTIONAL — Commitment Map writes (§12.2; max 2 per turn honored server-side).
    commitmentOps: {
      type: "array",
      items: COMMITMENT_OP_SCHEMA,
    },
    uiHints: {
      type: "object",
      properties: {
        showPassagePicker: { type: "boolean" },
        checkInQuestion: { anyOf: [{ type: "string" }, { type: "null" }] },
        endOfSession: { type: "boolean" },
        // OPTIONAL v2 key — set true when the student must adjudicate.
        adjudicationRequired: { type: "boolean" },
      },
      required: ["showPassagePicker", "checkInQuestion", "endOfSession"],
      additionalProperties: false,
    },
  },
  required: ["say", "citations", "stateOps", "uiHints"],
  additionalProperties: false,
} as const;

// ---------------------------------------------------------------------------
// TypeScript types
// ---------------------------------------------------------------------------

export interface Citation {
  passageId: string;
  quote: string;
  why: string;
}

export interface Speaker {
  personaId: string;
  say: string;
  citations: Citation[];
}

export interface ProfileOp {
  op: "evidence";
  kind: ProfileEvidenceKind;
  dimension: ProfileDimension;
  signal: string;
  weight: number;
}

/** Structurally identical to commitments.ts CommitmentOp (§12.2). */
export interface CommitmentOp {
  op: CommitmentOpKind;
  claim: string;
  domain: CommitmentDomain;
  ontologyId?: string;
  evidence?: string;
}

export interface RubricItem {
  name: string;
  score: number;
  max: number;
  justification: string;
}

export interface MarginComment {
  anchor: string;
  comment: string;
}

export type StateOp =
  | { op: "advanceSegment" }
  | { op: "pushQuestion"; question: string }
  | { op: "popQuestion" }
  | { op: "setDepth"; depth: number }
  | { op: "requireEvidence"; value: boolean }
  | {
    op: "recordGrade";
    assignmentId: string;
    grade: string;
    rubric: RubricItem[];
    marginComments: MarginComment[];
    directives: string[];
  }
  | { op: "writeMemory"; note: string }
  | { op: "completeSession" }
  | { op: "recordPosition"; side: string; statement: string }
  | { op: "advancePhase" }
  | { op: "recordThesis"; thesis: string }
  | { op: "reviseDefinition"; definition: string }
  | { op: "declareOutcome"; outcome: "aporia" | "robust" }
  | { op: "recordChoice"; nodeId: string; choice: string }
  | { op: "applyPump"; pumpId: string }
  | { op: "recordHuntResult"; found: boolean; attempts: number };

export interface UiHints {
  showPassagePicker: boolean;
  checkInQuestion: string | null;
  endOfSession: boolean;
  adjudicationRequired?: boolean;
}

export interface Envelope {
  say: string;
  speakers?: Speaker[];
  citations: Citation[];
  stateOps: StateOp[];
  profileOps?: ProfileOp[];
  commitmentOps?: CommitmentOp[];
  uiHints: UiHints;
  /** Server-stamped on persisted envelopes; never emitted by the model. */
  v?: number;
}

// ---------------------------------------------------------------------------
// Validation
// ---------------------------------------------------------------------------

export const KNOWN_OPS = new Set([
  "advanceSegment",
  "pushQuestion",
  "popQuestion",
  "setDepth",
  "requireEvidence",
  "recordGrade",
  "writeMemory",
  "completeSession",
  "recordPosition",
  "advancePhase",
  "recordThesis",
  "reviseDefinition",
  "declareOutcome",
  "recordChoice",
  "applyPump",
  "recordHuntResult",
]);

function isRecord(v: unknown): v is Record<string, unknown> {
  return typeof v === "object" && v !== null && !Array.isArray(v);
}

function validateCitation(c: unknown, where: string): void {
  if (
    !isRecord(c) || typeof c.passageId !== "string" ||
    typeof c.quote !== "string" || typeof c.why !== "string"
  ) {
    throw new Error(`${where} items must be {passageId, quote, why} strings`);
  }
}

/**
 * Parse and validate a raw envelope JSON string (v1 or v2). Throws with a
 * descriptive message if the payload does not conform to CONTRACTS §5/§11.1.
 *
 * NOTE: this validates *shape*, not semantics — citation-quote verification,
 * unknown-op rejection, and profileOps limits happen in the session function.
 */
export function parseEnvelope(raw: string): Envelope {
  let parsed: unknown;
  try {
    parsed = JSON.parse(raw);
  } catch (e) {
    throw new Error(`envelope is not valid JSON: ${(e as Error).message}`);
  }
  if (!isRecord(parsed)) throw new Error("envelope must be a JSON object");

  const { say, speakers, citations, stateOps, profileOps, commitmentOps, uiHints } =
    parsed as Record<string, unknown>;

  if (typeof say !== "string") throw new Error("envelope.say must be a string");

  if (!Array.isArray(citations)) throw new Error("envelope.citations must be an array");
  for (const c of citations) validateCitation(c, "envelope.citations");

  if (speakers !== undefined) {
    if (!Array.isArray(speakers)) throw new Error("envelope.speakers must be an array");
    for (const s of speakers) {
      if (
        !isRecord(s) || typeof s.personaId !== "string" || typeof s.say !== "string" ||
        !Array.isArray(s.citations)
      ) {
        throw new Error("envelope.speakers items must be {personaId, say, citations[]}");
      }
      for (const c of s.citations) validateCitation(c, "speaker.citations");
    }
  }

  if (!Array.isArray(stateOps)) throw new Error("envelope.stateOps must be an array");
  for (const op of stateOps) {
    if (!isRecord(op) || typeof op.op !== "string") {
      throw new Error("envelope.stateOps items must be objects with a string 'op'");
    }
    switch (op.op) {
      case "pushQuestion":
        if (typeof op.question !== "string") throw new Error("pushQuestion requires 'question'");
        break;
      case "setDepth":
        if (typeof op.depth !== "number") throw new Error("setDepth requires numeric 'depth'");
        break;
      case "requireEvidence":
        if (typeof op.value !== "boolean") throw new Error("requireEvidence requires boolean 'value'");
        break;
      case "writeMemory":
        if (typeof op.note !== "string") throw new Error("writeMemory requires 'note'");
        break;
      case "recordPosition":
        if (typeof op.side !== "string" || typeof op.statement !== "string") {
          throw new Error("recordPosition requires 'side' and 'statement' strings");
        }
        break;
      case "recordGrade":
        if (
          typeof op.assignmentId !== "string" || typeof op.grade !== "string" ||
          !Array.isArray(op.rubric) || !Array.isArray(op.marginComments) ||
          !Array.isArray(op.directives)
        ) {
          throw new Error(
            "recordGrade requires assignmentId, grade, rubric[], marginComments[], directives[]",
          );
        }
        break;
      case "recordThesis":
        if (typeof op.thesis !== "string") throw new Error("recordThesis requires 'thesis'");
        break;
      case "reviseDefinition":
        if (typeof op.definition !== "string") {
          throw new Error("reviseDefinition requires 'definition'");
        }
        break;
      case "declareOutcome":
        if (op.outcome !== "aporia" && op.outcome !== "robust") {
          throw new Error("declareOutcome requires outcome 'aporia' or 'robust'");
        }
        break;
      case "recordChoice":
        if (typeof op.nodeId !== "string" || typeof op.choice !== "string") {
          throw new Error("recordChoice requires 'nodeId' and 'choice' strings");
        }
        break;
      case "applyPump":
        if (typeof op.pumpId !== "string") throw new Error("applyPump requires 'pumpId'");
        break;
      case "recordHuntResult":
        if (typeof op.found !== "boolean" || typeof op.attempts !== "number") {
          throw new Error("recordHuntResult requires boolean 'found' and numeric 'attempts'");
        }
        break;
      default:
        // advanceSegment / popQuestion / completeSession / advancePhase carry
        // no payload; unknown ops pass shape validation and are *rejected*
        // (not applied) by engine.applyStateOps.
        break;
    }
  }

  if (profileOps !== undefined) {
    if (!Array.isArray(profileOps)) throw new Error("envelope.profileOps must be an array");
    for (const p of profileOps) {
      if (
        !isRecord(p) || p.op !== "evidence" ||
        typeof p.kind !== "string" || typeof p.dimension !== "string" ||
        typeof p.signal !== "string" || typeof p.weight !== "number"
      ) {
        throw new Error(
          "envelope.profileOps items must be {op:'evidence', kind, dimension, signal, weight}",
        );
      }
    }
  }

  // Mirrors profileOps: the op verb is structural (unknown verbs are rejected
  // here, like op !== 'evidence' above); domain/ontologyId values are semantic
  // and are dropped server-side by validateCommitmentOps (commitments.ts).
  if (commitmentOps !== undefined) {
    if (!Array.isArray(commitmentOps)) {
      throw new Error("envelope.commitmentOps must be an array");
    }
    for (const c of commitmentOps) {
      if (
        !isRecord(c) ||
        !(COMMITMENT_OP_KINDS as readonly string[]).includes(c.op as string) ||
        typeof c.claim !== "string" || typeof c.domain !== "string" ||
        !(c.ontologyId === undefined || typeof c.ontologyId === "string") ||
        !(c.evidence === undefined || typeof c.evidence === "string")
      ) {
        throw new Error(
          "envelope.commitmentOps items must be {op: assert|lean|explore|affirm|abandon, " +
            "claim, domain, ontologyId?, evidence?}",
        );
      }
    }
  }

  if (
    !isRecord(uiHints) ||
    typeof uiHints.showPassagePicker !== "boolean" ||
    typeof uiHints.endOfSession !== "boolean" ||
    !(uiHints.checkInQuestion === null || typeof uiHints.checkInQuestion === "string") ||
    !(uiHints.adjudicationRequired === undefined ||
      typeof uiHints.adjudicationRequired === "boolean")
  ) {
    throw new Error(
      "envelope.uiHints must be {showPassagePicker: bool, checkInQuestion: string|null, " +
        "endOfSession: bool, adjudicationRequired?: bool}",
    );
  }

  return parsed as unknown as Envelope;
}

/** Wrap plain text in a minimal, valid envelope (fallback / no-op path). */
export function minimalEnvelope(say: string, endOfSession = false): Envelope {
  return {
    say,
    citations: [],
    stateOps: [],
    uiHints: { showPassagePicker: false, checkInQuestion: null, endOfSession },
  };
}
