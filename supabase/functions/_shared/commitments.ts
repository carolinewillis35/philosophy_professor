// commitments.ts — The Commitment Map core (CONTRACTS §12.2–§12.4).
//
// Standalone module: pure functions over plain data, no imports. The session
// engine wires it in at three points:
//   1. per-turn: validateCommitmentOps() on envelope.commitmentOps, then
//      foldOps() and persist (service role);
//   2. prompt assembly: buildCommitmentDigest() after the profile digest
//      (only when the user has ≥3 non-abandoned commitments);
//   3. completeSession job: extraction sweep (MODEL_LIGHT) → foldOps() →
//      computeTensions() → reconcile tension rows → snapshot when material.

export type Domain =
  | "ethics" | "epistemology" | "metaphysics" | "mind" | "political" | "aesthetics";

export type Strength = "asserted" | "leaned" | "explored" | "abandoned";

export interface CommitmentOp {
  op: "assert" | "lean" | "explore" | "affirm" | "abandon";
  claim: string;
  domain: Domain;
  ontologyId?: string;
  evidence?: string;
}

export interface Commitment {
  id: string;                 // uuid
  userId: string;
  claim: string;
  domain: Domain;
  ontologyId: string | null;
  strength: Strength;
  affirmCount: number;
  firstAsserted: string;      // ISO timestamps
  lastAffirmed: string;
  sourceRefs: Array<{ sessionId: string; turnSeq: number }>;
}

export interface ClaimEdge {
  fromId: string;
  toId: string;
  kind: "entails" | "conflicts" | "supports";
}

export interface TensionCandidate {
  commitmentA: string;        // commitment ids (A < B lexically, for dedupe)
  commitmentB: string;
  via: ClaimEdge[];           // the edge path that produced it (1 or 2 edges)
}

export interface OpenTension extends TensionCandidate {
  id: string;
  status: "open" | "raised" | "reconciled" | "dissolved";
  createdAt: string;
}

const DOMAINS: ReadonlySet<string> = new Set([
  "ethics", "epistemology", "metaphysics", "mind", "political", "aesthetics",
]);

export const MAX_COMMITMENT_OPS_PER_TURN = 2;

/** Server-side validation (§12.2): known domain, known ontologyId when
 * present, non-empty claim; extras beyond the cap are dropped in order. */
export function validateCommitmentOps(
  ops: unknown,
  knownClaimIds: ReadonlySet<string>,
): CommitmentOp[] {
  if (!Array.isArray(ops)) return [];
  const out: CommitmentOp[] = [];
  for (const raw of ops) {
    if (out.length >= MAX_COMMITMENT_OPS_PER_TURN) break;
    if (typeof raw !== "object" || raw === null) continue;
    const o = raw as Record<string, unknown>;
    if (!["assert", "lean", "explore", "affirm", "abandon"].includes(o.op as string)) continue;
    if (typeof o.claim !== "string" || o.claim.trim().length === 0) continue;
    if (!DOMAINS.has(o.domain as string)) continue;
    if (o.ontologyId !== undefined &&
        (typeof o.ontologyId !== "string" || !knownClaimIds.has(o.ontologyId))) {
      // Unknown ontology mapping: keep the op, drop the bad mapping.
      delete o.ontologyId;
    }
    out.push({
      op: o.op as CommitmentOp["op"],
      claim: (o.claim as string).trim(),
      domain: o.domain as Domain,
      ontologyId: o.ontologyId as string | undefined,
      evidence: typeof o.evidence === "string" ? o.evidence : undefined,
    });
  }
  return out;
}

const STRENGTH_RANK: Record<Exclude<Strength, "abandoned">, number> = {
  explored: 0,
  leaned: 1,
  asserted: 2,
};

/** Strength transitions (§12.2): explore→lean→assert upward only via explicit
 * ops; affirm bumps affirmCount + lastAffirmed; abandon marks (never deletes).
 * Returns the updated commitment fields for an existing row, or the fields
 * for a new row when `existing` is null. In-turn ops and the post-session
 * sweep both funnel through here; callers pass ops in emission order. */
/** Commitment-event verbs (§14.1) — the strength name IS the event name. */
export type CommitmentEvent = Strength | "affirmed";

/** Derive the §14.1 ledger event for a fold: first insert and every strength
 * CHANGE log the new strength's verb (with the prior strength when there was
 * one); a fold that leaves strength unchanged is an 'affirmed'. */
export function changeEvent(
  prior: Strength | null,
  next: Strength,
): { event: CommitmentEvent; priorStrength: Strength | null } {
  if (prior === null) return { event: next, priorStrength: null };
  if (prior === next) return { event: "affirmed", priorStrength: null };
  return { event: next, priorStrength: prior };
}

export function foldOp(
  existing: Pick<Commitment, "strength" | "affirmCount"> | null,
  op: CommitmentOp,
  now: string,
): { strength: Strength; affirmCount: number; lastAffirmed: string } {
  const opStrength: Strength =
    op.op === "assert" ? "asserted"
    : op.op === "lean" ? "leaned"
    : op.op === "explore" ? "explored"
    : op.op === "abandon" ? "abandoned"
    : existing?.strength ?? "explored"; // affirm keeps current strength

  if (!existing) {
    return {
      strength: op.op === "affirm" ? "asserted" : opStrength,
      affirmCount: 1,
      lastAffirmed: now,
    };
  }
  if (op.op === "abandon") {
    return { strength: "abandoned", affirmCount: existing.affirmCount, lastAffirmed: now };
  }
  if (op.op === "affirm") {
    // Re-affirming a previously abandoned position revives it as asserted.
    const strength = existing.strength === "abandoned" ? "asserted" : existing.strength;
    return { strength, affirmCount: existing.affirmCount + 1, lastAffirmed: now };
  }
  // assert / lean / explore: upward-only ratchet (a stray weaker op never
  // downgrades; movement DOWN happens only via explicit abandon).
  const current = existing.strength === "abandoned"
    ? -1
    : STRENGTH_RANK[existing.strength as Exclude<Strength, "abandoned">];
  const proposed = STRENGTH_RANK[opStrength as Exclude<Strength, "abandoned">];
  const strength = proposed >= current ? opStrength : existing.strength;
  return { strength, affirmCount: existing.affirmCount + 1, lastAffirmed: now };
}

/** Tension computation (§12.4): for every pair of non-abandoned commitments
 * with ontology ids, flag (a) a direct `conflicts` edge, or (b) a 1-hop
 * entailment conflict (A entails X, X conflicts B). 1 hop MAXIMUM —
 * conservative by contract. Pairs are deduped (lexical order, shortest via
 * kept, direct beating 1-hop). */
export function computeTensions(
  commitments: ReadonlyArray<Pick<Commitment, "id" | "ontologyId" | "strength">>,
  edges: ReadonlyArray<ClaimEdge>,
): TensionCandidate[] {
  const live = commitments.filter((c) => c.strength !== "abandoned" && c.ontologyId);
  const conflicts = new Map<string, Set<string>>(); // claim -> claims it conflicts with
  const entails = new Map<string, Set<string>>();
  for (const e of edges) {
    const bucket = e.kind === "conflicts" ? conflicts : e.kind === "entails" ? entails : null;
    if (!bucket) continue;
    if (!bucket.has(e.fromId)) bucket.set(e.fromId, new Set());
    bucket.get(e.fromId)!.add(e.toId);
    if (e.kind === "conflicts") { // symmetric
      if (!bucket.has(e.toId)) bucket.set(e.toId, new Set());
      bucket.get(e.toId)!.add(e.fromId);
    }
  }
  const conflictsBetween = (a: string, b: string) => conflicts.get(a)?.has(b) ?? false;

  const found = new Map<string, TensionCandidate>();
  const record = (a: typeof live[number], b: typeof live[number], via: ClaimEdge[]) => {
    const [ca, cb] = a.id < b.id ? [a, b] : [b, a];
    const key = `${ca.id}|${cb.id}`;
    const prior = found.get(key);
    if (!prior || via.length < prior.via.length) {
      found.set(key, { commitmentA: ca.id, commitmentB: cb.id, via });
    }
  };

  for (let i = 0; i < live.length; i++) {
    for (let j = i + 1; j < live.length; j++) {
      const a = live[i], b = live[j];
      const aId = a.ontologyId!, bId = b.ontologyId!;
      if (aId === bId) continue;
      if (conflictsBetween(aId, bId)) {
        record(a, b, [{ fromId: aId, toId: bId, kind: "conflicts" }]);
        continue;
      }
      // 1-hop: A entails X, X conflicts B
      for (const x of entails.get(aId) ?? []) {
        if (conflictsBetween(x, bId)) {
          record(a, b, [
            { fromId: aId, toId: x, kind: "entails" },
            { fromId: x, toId: bId, kind: "conflicts" },
          ]);
          break;
        }
      }
      // symmetric direction: B entails Y, Y conflicts A
      for (const y of entails.get(bId) ?? []) {
        if (conflictsBetween(y, aId)) {
          record(a, b, [
            { fromId: bId, toId: y, kind: "entails" },
            { fromId: y, toId: aId, kind: "conflicts" },
          ]);
          break;
        }
      }
    }
  }
  return [...found.values()];
}

/** Surfacing eligibility (§12.4.4): both sides asserted with affirmCount ≥ 2. */
export function isSurfaceable(
  tension: TensionCandidate,
  byId: ReadonlyMap<string, Pick<Commitment, "strength" | "affirmCount">>,
): boolean {
  const a = byId.get(tension.commitmentA);
  const b = byId.get(tension.commitmentB);
  return !!a && !!b &&
    a.strength === "asserted" && b.strength === "asserted" &&
    a.affirmCount >= 2 && b.affirmCount >= 2;
}

/** Digest selection: oldest unraised open tension first (§12.2). */
export function pickTensionForDigest(tensions: ReadonlyArray<OpenTension>): OpenTension | null {
  const open = tensions
    .filter((t) => t.status === "open")
    .sort((a, b) => a.createdAt.localeCompare(b.createdAt));
  return open[0] ?? null;
}

/** The ~150-token commitment digest injected after the profile digest.
 * Framing contract: a tension is a question to examine, never a verdict.
 * Only call when the user has ≥3 non-abandoned commitments. */
export function buildCommitmentDigest(
  commitments: ReadonlyArray<Commitment>,
  tension: { a: Commitment; b: Commitment; via: ClaimEdge[] } | null,
  commitmentMoveUsed: boolean,
): string {
  const live = commitments
    .filter((c) => c.strength !== "abandoned")
    .sort((x, y) =>
      (STRENGTH_RANK[y.strength as Exclude<Strength, "abandoned">] ?? -1) -
      (STRENGTH_RANK[x.strength as Exclude<Strength, "abandoned">] ?? -1) ||
      y.affirmCount - x.affirmCount)
    .slice(0, 6);
  const lines = [
    "<commitments>",
    "Positions this student actually holds (their words, tracked across sessions):",
    ...live.map((c) => `- [${c.strength}, x${c.affirmCount}] (${c.domain}) ${c.claim}`),
  ];
  if (tension && !commitmentMoveUsed) {
    const viaNote = tension.via.length === 2
      ? ` (classically, the first entails something in tension with the second — via ${tension.via[0].toId})`
      : "";
    lines.push(
      "",
      "ONE open tension you may raise this session (at most one commitment move per session):",
      `- "${tension.a.claim}" vs. "${tension.b.claim}"${viaNote}`,
      "Frame it Socratically: these two things you hold pull against each other — which gives?",
      "Never a verdict of incoherence. If the student abandons a position, that is progress; say so.",
    );
  } else {
    lines.push("", "No commitment move this session" +
      (commitmentMoveUsed ? " (already used)." : " (no eligible tension)."));
  }
  lines.push("</commitments>");
  return lines.join("\n");
}
