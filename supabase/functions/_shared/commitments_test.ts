// deno test commitments_test.ts
import {
  buildCommitmentDigest,
  computeTensions,
  foldOp,
  isSurfaceable,
  pickTensionForDigest,
  validateCommitmentOps,
  type ClaimEdge,
  type Commitment,
} from "./commitments.ts";
import { assertEquals, assert } from "jsr:@std/assert";

const KNOWN = new Set(["ethics.moral-realism", "metaphysics.hard-determinism",
  "metaphysics.libertarian-free-will", "mind.physicalism",
  "epistemology.moral-knowledge-possible", "ethics.moral-anti-realism"]);

Deno.test("validateCommitmentOps: caps at 2, drops bad domains, strips unknown ontologyIds", () => {
  const ops = validateCommitmentOps([
    { op: "assert", claim: "Moral facts are mind-independent", domain: "ethics", ontologyId: "ethics.moral-realism" },
    { op: "assert", claim: "x", domain: "astrology" },                       // bad domain → dropped
    { op: "lean", claim: "The mind is physical", domain: "mind", ontologyId: "mind.made-up" }, // unknown id → stripped
    { op: "explore", claim: "one too many", domain: "ethics" },              // over cap → dropped
  ], KNOWN);
  assertEquals(ops.length, 2);
  assertEquals(ops[0].ontologyId, "ethics.moral-realism");
  assertEquals(ops[1].ontologyId, undefined);
  assertEquals(ops[1].op, "lean");
});

Deno.test("foldOp: upward ratchet, affirm bumps, abandon marks, affirm revives", () => {
  const now = "2026-07-07T00:00:00Z";
  const fresh = foldOp(null, { op: "assert", claim: "c", domain: "ethics" }, now);
  assertEquals(fresh, { strength: "asserted", affirmCount: 1, lastAffirmed: now });

  const noDowngrade = foldOp({ strength: "asserted", affirmCount: 2 },
    { op: "explore", claim: "c", domain: "ethics" }, now);
  assertEquals(noDowngrade.strength, "asserted");
  assertEquals(noDowngrade.affirmCount, 3);

  const affirmed = foldOp({ strength: "leaned", affirmCount: 1 },
    { op: "affirm", claim: "c", domain: "ethics" }, now);
  assertEquals(affirmed, { strength: "leaned", affirmCount: 2, lastAffirmed: now });

  const abandoned = foldOp({ strength: "asserted", affirmCount: 3 },
    { op: "abandon", claim: "c", domain: "ethics" }, now);
  assertEquals(abandoned.strength, "abandoned");

  const revived = foldOp({ strength: "abandoned", affirmCount: 3 },
    { op: "affirm", claim: "c", domain: "ethics" }, now);
  assertEquals(revived.strength, "asserted");
});

const EDGES: ClaimEdge[] = [
  { fromId: "metaphysics.hard-determinism", toId: "metaphysics.libertarian-free-will", kind: "conflicts" },
  { fromId: "mind.physicalism", toId: "metaphysics.hard-determinism", kind: "entails" }, // deliberately strong, for the 1-hop test
  { fromId: "ethics.moral-realism", toId: "epistemology.moral-knowledge-possible", kind: "entails" },
];

function c(id: string, ontologyId: string, strength: Commitment["strength"] = "asserted", affirmCount = 2): Commitment {
  return { id, userId: "u", claim: `claim ${id}`, domain: "metaphysics", ontologyId,
    strength, affirmCount, firstAsserted: "2026-06-01T00:00:00Z",
    lastAffirmed: "2026-07-01T00:00:00Z", sourceRefs: [] };
}

Deno.test("computeTensions: direct conflict detected symmetrically", () => {
  const tensions = computeTensions(
    [c("a", "metaphysics.libertarian-free-will"), c("b", "metaphysics.hard-determinism")], EDGES);
  assertEquals(tensions.length, 1);
  assertEquals(tensions[0].via.length, 1);
});

Deno.test("computeTensions: 1-hop entailment conflict, abandoned excluded, no 2-hop", () => {
  // physicalism entails hard-determinism, which conflicts with libertarian free will → 1-hop tension
  const oneHop = computeTensions(
    [c("a", "mind.physicalism"), c("b", "metaphysics.libertarian-free-will")], EDGES);
  assertEquals(oneHop.length, 1);
  assertEquals(oneHop[0].via.length, 2);

  const withAbandoned = computeTensions(
    [c("a", "mind.physicalism", "abandoned"), c("b", "metaphysics.libertarian-free-will")], EDGES);
  assertEquals(withAbandoned.length, 0);

  // moral-realism entails moral-knowledge-possible; nothing conflicts with the latter → no tension
  const none = computeTensions(
    [c("a", "ethics.moral-realism"), c("b", "metaphysics.libertarian-free-will")], EDGES);
  assertEquals(none.length, 0);
});

Deno.test("isSurfaceable: requires asserted + affirm_count>=2 on both sides", () => {
  const t = { commitmentA: "a", commitmentB: "b", via: [] as ClaimEdge[] };
  const byId = new Map<string, { strength: Commitment["strength"]; affirmCount: number }>([
    ["a", { strength: "asserted", affirmCount: 2 }],
    ["b", { strength: "asserted", affirmCount: 1 }],
  ]);
  assertEquals(isSurfaceable(t, byId), false);
  byId.set("b", { strength: "asserted", affirmCount: 2 });
  assertEquals(isSurfaceable(t, byId), true);
  byId.set("b", { strength: "leaned", affirmCount: 5 });
  assertEquals(isSurfaceable(t, byId), false);
});

Deno.test("pickTensionForDigest: oldest open first; raised/reconciled skipped", () => {
  const mk = (id: string, status: "open" | "raised", createdAt: string) =>
    ({ id, commitmentA: "a", commitmentB: "b", via: [], status, createdAt });
  const picked = pickTensionForDigest([
    mk("t1", "raised", "2026-06-01"), mk("t2", "open", "2026-06-20"), mk("t3", "open", "2026-06-10"),
  ]);
  assertEquals(picked?.id, "t3");
});

Deno.test("buildCommitmentDigest: tension framed as question, move-used suppresses", () => {
  const a = c("a", "metaphysics.libertarian-free-will");
  const b = c("b", "mind.physicalism");
  const digest = buildCommitmentDigest([a, b, c("d", "ethics.moral-realism")],
    { a, b, via: EDGES.slice(0, 1) }, false);
  assert(digest.includes("which gives?"));
  assert(digest.includes("Never a verdict of incoherence"));
  const suppressed = buildCommitmentDigest([a, b], null, true);
  assert(suppressed.includes("already used"));
});
