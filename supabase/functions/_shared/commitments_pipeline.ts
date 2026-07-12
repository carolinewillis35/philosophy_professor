// Commitment Map pipeline — DB wiring around commitments.ts (CONTRACTS
// §12.2–§12.4). Mirrors profile.ts: the pure logic lives in commitments.ts;
// this module owns persistence and the MODEL_LIGHT calls.
//
// The session function wires it in at three points:
//   1. per-turn: persistCommitmentOps() folds validated envelope.commitmentOps
//      into the commitments table (service role);
//   2. prompt assembly: buildUserCommitmentDigest() renders the digest
//      injected after the profile digest (≥3 non-abandoned commitments);
//   3. completeSession: runCommitmentPipeline() — extraction sweep
//      (MODEL_LIGHT) → fold → recompute/reconcile tensions → worldview
//      snapshot when anything material changed.

import {
  anthropicClient,
  MAX_TOKENS_SUMMARY,
  MODEL_LIGHT,
} from "./anthropic.ts";
import type { UsageSink } from "./budget.ts";
import { COMMITMENT_OP_SCHEMA } from "./envelope.ts";
import {
  buildCommitmentDigest,
  changeEvent,
  type ClaimEdge,
  type Commitment,
  type CommitmentOp,
  computeTensions,
  foldOp,
  isSurfaceable,
  type OpenTension,
  pickTensionForDigest,
  validateCommitmentOps,
} from "./commitments.ts";

// deno-lint-ignore no-explicit-any
type Db = any;

/** Digest gate (§12.2): user must hold ≥3 non-abandoned commitments. */
export const MIN_COMMITMENTS_FOR_DIGEST = 3;

/** Cap on ops accepted from one post-session extraction sweep (§12.4.1). */
export const MAX_SWEEP_OPS = 5;

// ---------------------------------------------------------------------------
// Row mapping
// ---------------------------------------------------------------------------

interface CommitmentRow {
  id: string;
  user_id: string;
  claim: string;
  domain: string;
  ontology_id: string | null;
  strength: string;
  affirm_count: number;
  first_asserted: string;
  last_affirmed: string;
  source_refs: unknown;
}

function rowToCommitment(r: CommitmentRow): Commitment {
  return {
    id: r.id,
    userId: r.user_id,
    claim: r.claim,
    domain: r.domain as Commitment["domain"],
    ontologyId: r.ontology_id,
    strength: r.strength as Commitment["strength"],
    affirmCount: r.affirm_count,
    firstAsserted: r.first_asserted,
    lastAffirmed: r.last_affirmed,
    sourceRefs: Array.isArray(r.source_refs)
      ? r.source_refs as Commitment["sourceRefs"]
      : [],
  };
}

const normClaim = (s: string) => s.trim().toLowerCase();

// ---------------------------------------------------------------------------
// Catalog loads (claims / claim_edges — small, cached per request by callers)
// ---------------------------------------------------------------------------

export interface ClaimRow {
  id: string;
  claim: string;
  domain: string;
}

export async function loadClaims(db: Db): Promise<ClaimRow[]> {
  const { data, error } = await db.from("claims").select("id, claim, domain");
  if (error) throw new Error(`claims load failed: ${error.message}`);
  return (data ?? []) as ClaimRow[];
}

export async function loadClaimEdges(db: Db): Promise<ClaimEdge[]> {
  const { data, error } = await db.from("claim_edges").select("from_id, to_id, kind");
  if (error) throw new Error(`claim_edges load failed: ${error.message}`);
  return ((data ?? []) as { from_id: string; to_id: string; kind: ClaimEdge["kind"] }[])
    .map((e) => ({ fromId: e.from_id, toId: e.to_id, kind: e.kind }));
}

async function loadUserCommitments(db: Db, userId: string): Promise<CommitmentRow[]> {
  const { data, error } = await db
    .from("commitments")
    .select("*")
    .eq("user_id", userId);
  if (error) throw new Error(`commitments load failed: ${error.message}`);
  return (data ?? []) as CommitmentRow[];
}

// ---------------------------------------------------------------------------
// 1. Per-turn fold (§12.2) — also reused by the post-session sweep
// ---------------------------------------------------------------------------

export interface SourceRef {
  sessionId: string;
  turnSeq: number;
}

export interface PersistResult {
  /** ontologyIds that received an op (for sweep conflict-skipping). */
  touchedOntologyIds: string[];
  /** normalized claim texts that received an op. */
  touchedClaims: string[];
  /** any row's strength changed, or a new row was inserted (snapshot gate). */
  strengthChanged: boolean;
}

/**
 * Persist validated commitment ops via foldOp semantics: match an existing
 * row by (user_id, ontology_id) when the op carries an ontologyId (falling
 * back to normalized-claim match, upgrading that row's mapping), else by
 * lower(trim(claim)) equality; append the source ref. Never deletes — the
 * arc is the product.
 */
export async function persistCommitmentOps(
  db: Db,
  userId: string,
  ops: CommitmentOp[],
  ref: SourceRef,
): Promise<PersistResult> {
  const result: PersistResult = {
    touchedOntologyIds: [],
    touchedClaims: [],
    strengthChanged: false,
  };
  if (ops.length === 0) return result;

  const rows = await loadUserCommitments(db, userId);
  for (const op of ops) {
    const byOntology = op.ontologyId
      ? rows.find((r) => r.ontology_id === op.ontologyId)
      : undefined;
    const existing = byOntology ??
      rows.find((r) => normClaim(r.claim) === normClaim(op.claim));

    const now = new Date().toISOString();
    const folded = foldOp(
      existing ? { strength: existing.strength as Commitment["strength"], affirmCount: existing.affirm_count } : null,
      op,
      now,
    );

    let eventCommitmentId: string;
    let ledger: ReturnType<typeof changeEvent>;
    if (existing) {
      const priorStrength = existing.strength as Commitment["strength"];
      const sourceRefs = [
        ...(Array.isArray(existing.source_refs) ? existing.source_refs : []),
        ref,
      ];
      const update: Record<string, unknown> = {
        strength: folded.strength,
        affirm_count: folded.affirmCount,
        last_affirmed: folded.lastAffirmed,
        source_refs: sourceRefs,
      };
      // A claim-matched row gains the canonical mapping when the op has one.
      if (op.ontologyId && !existing.ontology_id) update.ontology_id = op.ontologyId;
      const { error } = await db.from("commitments").update(update).eq("id", existing.id);
      if (error) throw new Error(`commitment update failed: ${error.message}`);
      if (folded.strength !== existing.strength) result.strengthChanged = true;
      existing.strength = folded.strength;
      existing.affirm_count = folded.affirmCount;
      existing.source_refs = sourceRefs;
      if (op.ontologyId && !existing.ontology_id) existing.ontology_id = op.ontologyId;
      eventCommitmentId = existing.id;
      ledger = changeEvent(priorStrength, folded.strength);
    } else {
      const insert = {
        user_id: userId,
        claim: op.claim,
        domain: op.domain,
        ontology_id: op.ontologyId ?? null,
        strength: folded.strength,
        affirm_count: folded.affirmCount,
        last_affirmed: folded.lastAffirmed,
        source_refs: [ref],
      };
      const { data, error } = await db.from("commitments").insert(insert).select().single();
      if (error) throw new Error(`commitment insert failed: ${error.message}`);
      rows.push(data as CommitmentRow);
      result.strengthChanged = true;
      eventCommitmentId = (data as CommitmentRow).id;
      ledger = changeEvent(null, folded.strength);
    }

    // §14.1 events ledger — the changelog of your mind. Never fails the fold.
    {
      const { error: evErr } = await db.from("commitment_events").insert({
        user_id: userId,
        commitment_id: eventCommitmentId,
        event: ledger.event,
        prior_strength: ledger.priorStrength,
        evidence: op.evidence ?? "",
        session_id: ref.sessionId,
      });
      if (evErr) console.error("commitment event insert failed:", evErr.message);
    }

    if (op.ontologyId) result.touchedOntologyIds.push(op.ontologyId);
    result.touchedClaims.push(normClaim(op.claim));
  }
  return result;
}

// ---------------------------------------------------------------------------
// 2. Prompt-injection digest (§12.2)
// ---------------------------------------------------------------------------

interface TensionRow {
  id: string;
  commitment_a: string;
  commitment_b: string;
  via: unknown;
  status: OpenTension["status"];
  created_at: string;
}

export interface CommitmentDigestResult {
  digest: string;
  /** The digest carried an open tension (the session's one commitment move). */
  carriedTension: boolean;
  /** Id of the tension the digest raised — the ONLY tension
   * markTensionReconciled may resolve this session (§14.2). */
  raisedTensionId: string | null;
}

/**
 * Build the commitment digest for prompt injection, or null when the gate
 * fails (<3 non-abandoned commitments). When the digest carries a tension it
 * is marked 'raised' (raised_in = sessionId) so pickTensionForDigest's
 * oldest-UNRAISED-first ordering holds across sessions.
 */
export async function buildUserCommitmentDigest(
  db: Db,
  userId: string,
  sessionId: string,
  commitmentMoveUsed: boolean,
): Promise<CommitmentDigestResult | null> {
  const rows = await loadUserCommitments(db, userId);
  const commitments = rows.map(rowToCommitment);
  const live = commitments.filter((c) => c.strength !== "abandoned");
  if (live.length < MIN_COMMITMENTS_FOR_DIGEST) return null;

  let picked: OpenTension | null = null;
  if (!commitmentMoveUsed) {
    const { data: tData, error: tErr } = await db
      .from("commitment_tensions")
      .select("id, commitment_a, commitment_b, via, status, created_at")
      .eq("user_id", userId)
      .eq("status", "open");
    if (tErr) throw new Error(`tensions load failed: ${tErr.message}`);
    const byId = new Map(commitments.map((c) => [c.id, c]));
    const open: OpenTension[] = ((tData ?? []) as TensionRow[]).map((t) => ({
      id: t.id,
      commitmentA: t.commitment_a,
      commitmentB: t.commitment_b,
      via: (Array.isArray(t.via) ? t.via : []) as ClaimEdge[],
      status: t.status,
      createdAt: t.created_at,
    }));
    picked = pickTensionForDigest(open.filter((t) => isSurfaceable(t, byId)));

    if (picked) {
      const { error: rErr } = await db
        .from("commitment_tensions")
        .update({ status: "raised", raised_in: sessionId })
        .eq("id", picked.id);
      if (rErr) console.error("tension raise-mark failed:", rErr.message);
    }
  }

  const byId = new Map(commitments.map((c) => [c.id, c]));
  const a = picked ? byId.get(picked.commitmentA) : undefined;
  const b = picked ? byId.get(picked.commitmentB) : undefined;
  const tension = picked && a && b ? { a, b, via: picked.via } : null;

  return {
    digest: buildCommitmentDigest(commitments, tension, commitmentMoveUsed),
    carriedTension: tension !== null,
    raisedTensionId: tension !== null && picked ? picked.id : null,
  };
}

// ---------------------------------------------------------------------------
// 3. Post-session pipeline (§12.4): sweep → fold → tensions → snapshot
// ---------------------------------------------------------------------------

const SWEEP_SCHEMA = {
  type: "object",
  properties: {
    commitmentOps: { type: "array", items: COMMITMENT_OP_SCHEMA },
  },
  required: ["commitmentOps"],
  additionalProperties: false,
} as const;

/**
 * Extraction sweep (§12.4.1): one MODEL_LIGHT pass over the transcript with
 * the ontology domain-slice (id + claim only) in context, emitting
 * commitmentOps-shaped JSON for anything the in-turn ops missed.
 */
async function extractionSweep(
  transcript: string,
  ontologySlice: ClaimRow[],
  usage?: UsageSink,
): Promise<CommitmentOp[]> {
  const slice = ontologySlice
    .map((c) => `${c.id}: ${c.claim}`)
    .join("\n")
    .slice(0, 16_000);

  const client = anthropicClient();
  const stream = client.messages.stream({
    model: MODEL_LIGHT,
    max_tokens: MAX_TOKENS_SUMMARY,
    output_config: { format: { type: "json_schema" as const, schema: SWEEP_SCHEMA } },
    system:
      "You extract philosophical commitments from a teaching-session " +
      "transcript. Emit one op per position THE STUDENT actually took: " +
      "assert (stated as their view), lean (inclined but hedged), explore " +
      "(entertained seriously), affirm (re-stated a position they already " +
      "hold), abandon (explicitly gave one up). Be conservative: positions " +
      "merely discussed, quoted, or steel-manned are NOT commitments. State " +
      "each claim in ONE sentence in the student's own terms. Set ontologyId " +
      `only when it confidently matches a canonical claim listed below. At ` +
      `most ${MAX_SWEEP_OPS} ops; an empty list is a fine answer.`,
    messages: [{
      role: "user",
      content: `CANONICAL CLAIMS (id: claim):\n${slice}\n\nTRANSCRIPT:\n${
        transcript.slice(0, 24_000)
      }`,
    }],
  });
  const final = await stream.finalMessage();
  usage?.add(final.usage);
  const text = final.content
    .filter((b: { type: string }) => b.type === "text")
    // deno-lint-ignore no-explicit-any
    .map((b: any) => b.text as string)
    .join("");
  const parsed = JSON.parse(text) as { commitmentOps: unknown[] };
  return Array.isArray(parsed.commitmentOps) ? parsed.commitmentOps as CommitmentOp[] : [];
}

/**
 * Recompute tensions (§12.4.3) and reconcile the commitment_tensions rows:
 * new pairs insert as 'open' (a dissolved pair that re-emerges reopens);
 * 'open'/'raised' rows whose pair vanished (incl. an abandoned side) become
 * 'dissolved'; 'reconciled' rows are kept. Returns true when anything changed.
 */
async function reconcileTensions(db: Db, userId: string): Promise<boolean> {
  const rows = await loadUserCommitments(db, userId);
  const edges = await loadClaimEdges(db);
  const candidates = computeTensions(rows.map(rowToCommitment), edges);
  const candidateByKey = new Map(
    candidates.map((c) => [`${c.commitmentA}|${c.commitmentB}`, c]),
  );

  const { data: tData, error: tErr } = await db
    .from("commitment_tensions")
    .select("id, commitment_a, commitment_b, via, status, created_at")
    .eq("user_id", userId);
  if (tErr) throw new Error(`tensions load failed: ${tErr.message}`);
  const existing = (tData ?? []) as TensionRow[];
  const existingByKey = new Map(
    existing.map((t) => {
      const [a, b] = t.commitment_a < t.commitment_b
        ? [t.commitment_a, t.commitment_b]
        : [t.commitment_b, t.commitment_a];
      return [`${a}|${b}`, t];
    }),
  );

  let changed = false;

  for (const [key, cand] of candidateByKey) {
    const row = existingByKey.get(key);
    if (!row) {
      const { error } = await db.from("commitment_tensions").insert({
        user_id: userId,
        commitment_a: cand.commitmentA,
        commitment_b: cand.commitmentB,
        via: cand.via,
        status: "open",
      });
      if (error) throw new Error(`tension insert failed: ${error.message}`);
      changed = true;
    } else if (row.status === "dissolved") {
      const { error } = await db.from("commitment_tensions")
        .update({ status: "open", via: cand.via })
        .eq("id", row.id);
      if (error) throw new Error(`tension reopen failed: ${error.message}`);
      changed = true;
    }
    // open / raised / reconciled rows whose pair persists are kept as-is.
  }

  for (const [key, row] of existingByKey) {
    if (candidateByKey.has(key)) continue;
    if (row.status !== "open" && row.status !== "raised") continue; // keep reconciled/dissolved
    const { error } = await db.from("commitment_tensions")
      .update({ status: "dissolved" })
      .eq("id", row.id);
    if (error) throw new Error(`tension dissolve failed: ${error.message}`);
    changed = true;
  }

  return changed;
}

/** Worldview snapshot (§12.4.5): ~120-word MODEL_LIGHT summary, professor-
 * register, receipts not psychology. */
async function writeWorldviewSnapshot(
  db: Db,
  userId: string,
  usage?: UsageSink,
): Promise<void> {
  const rows = await loadUserCommitments(db, userId);
  const commitments = rows.map(rowToCommitment);
  const live = commitments.filter((c) => c.strength !== "abandoned");
  const abandoned = commitments.filter((c) => c.strength === "abandoned");

  const { data: tData } = await db
    .from("commitment_tensions")
    .select("commitment_a, commitment_b, via, status")
    .eq("user_id", userId)
    .in("status", ["open", "raised"]);
  const byId = new Map(commitments.map((c) => [c.id, c]));
  const openTensions = ((tData ?? []) as TensionRow[])
    .map((t) => ({
      a: byId.get(t.commitment_a)?.claim ?? "(gone)",
      b: byId.get(t.commitment_b)?.claim ?? "(gone)",
      via: Array.isArray(t.via) ? t.via : [],
    }));

  const positionLines = live
    .map((c) => `- [${c.strength}, x${c.affirmCount}] (${c.domain}) ${c.claim}`)
    .join("\n");
  const abandonedLines = abandoned
    .map((c) => `- (abandoned) ${c.claim}`)
    .join("\n");
  const tensionLines = openTensions
    .map((t) => `- "${t.a}" vs. "${t.b}"`)
    .join("\n");

  const client = anthropicClient();
  const stream = client.messages.stream({
    model: MODEL_LIGHT,
    max_tokens: MAX_TOKENS_SUMMARY,
    system:
      "Write a worldview snapshot in a professor's register — about 120 " +
      "words, plain text. Describe the positions this student actually " +
      "holds, how firmly, where they moved, and what pulls against what — " +
      "receipts, not psychology. Tensions are questions to examine, never " +
      "verdicts of incoherence; an abandoned position is progress. Output " +
      "ONLY the snapshot text.",
    messages: [{
      role: "user",
      content: `LIVE POSITIONS:\n${positionLines || "(none)"}\n\nABANDONED:\n${
        abandonedLines || "(none)"
      }\n\nOPEN TENSIONS:\n${tensionLines || "(none)"}`,
    }],
  });
  const final = await stream.finalMessage();
  usage?.add(final.usage);
  const summary = final.content
    .filter((b: { type: string }) => b.type === "text")
    // deno-lint-ignore no-explicit-any
    .map((b: any) => b.text as string)
    .join("")
    .trim();
  if (!summary) return;

  const { error } = await db.from("worldview_snapshots").insert({
    user_id: userId,
    summary,
    major_positions: live.map((c) => ({
      claim: c.claim,
      domain: c.domain,
      strength: c.strength,
      affirmCount: c.affirmCount,
      ontologyId: c.ontologyId,
    })),
    open_tensions: openTensions,
  });
  if (error) throw new Error(`worldview snapshot insert failed: ${error.message}`);
}

export interface CommitmentPipelineInput {
  userId: string;
  sessionId: string;
  /** seq of the closing professor turn (used as the sweep ops' source ref). */
  turnSeq: number;
  /** Full session transcript ("STUDENT: …\nPROFESSOR: …"). */
  transcript: string;
  /** ontologyIds already given an op in-turn this session (in-turn wins). */
  touchedOntologyIds: string[];
  /** normalized claim texts already given an op in-turn this session. */
  touchedClaims: string[];
  /** Domains to slice the ontology by (empty ⇒ whole ontology). */
  domains: string[];
  /** Any in-turn fold this session changed a strength (snapshot gate). */
  strengthChangedInTurn: boolean;
  /** Preloaded claims catalog (request-scoped cache); loaded when omitted. */
  claims?: ClaimRow[];
  usage?: UsageSink;
}

/** The §12.4 completeSession job. Never throws into the turn path — callers
 * wrap it like updateReaderProfile. */
export async function runCommitmentPipeline(
  db: Db,
  input: CommitmentPipelineInput,
): Promise<void> {
  const claims = input.claims ?? await loadClaims(db);
  const knownIds = new Set(claims.map((c) => c.id));

  // 1. Extract (MODEL_LIGHT) with the domain slice (id + claim only).
  const domains = new Set(input.domains);
  const slice = domains.size > 0 ? claims.filter((c) => domains.has(c.domain)) : claims;
  let sweepOps: CommitmentOp[] = [];
  try {
    sweepOps = await extractionSweep(input.transcript, slice, input.usage);
  } catch (e) {
    console.error("commitment sweep failed (continuing):", e);
  }

  // In-turn ops win on conflict: skip sweep ops whose ontologyId or
  // normalized claim already got an op this session. validateCommitmentOps
  // is applied per-op (its 2-op cap is a per-TURN envelope rule, §12.2).
  const touchedIds = new Set(input.touchedOntologyIds);
  const touchedClaims = new Set(input.touchedClaims);
  const accepted: CommitmentOp[] = [];
  for (const raw of sweepOps) {
    if (accepted.length >= MAX_SWEEP_OPS) break;
    const [op] = validateCommitmentOps([raw], knownIds);
    if (!op) continue;
    if (op.ontologyId && touchedIds.has(op.ontologyId)) continue;
    if (touchedClaims.has(normClaim(op.claim))) continue;
    accepted.push(op);
  }

  // 2. Fold.
  let strengthChanged = input.strengthChangedInTurn;
  if (accepted.length > 0) {
    const folded = await persistCommitmentOps(db, input.userId, accepted, {
      sessionId: input.sessionId,
      turnSeq: input.turnSeq,
    });
    strengthChanged = strengthChanged || folded.strengthChanged;
  }

  // 3./4. Recompute + reconcile tensions.
  const tensionsChanged = await reconcileTensions(db, input.userId);

  // 5. Snapshot when drift is material (any strength change or tension change).
  if (strengthChanged || tensionsChanged) {
    await writeWorldviewSnapshot(db, input.userId, input.usage);
  }
}
