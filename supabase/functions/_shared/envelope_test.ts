// deno test supabase/functions/_shared/envelope_test.ts
import { assertEquals, assertThrows } from "jsr:@std/assert@1";
import { minimalEnvelope, parseEnvelope } from "./envelope.ts";
import { validateCommitmentOps } from "./commitments.ts";

Deno.test("v1 envelope still parses (new fields optional)", () => {
  const v1 = {
    say: "Read it again.",
    citations: [{ passageId: "frankenstein-1818:4:12", quote: "dreary night", why: "tone" }],
    stateOps: [{ op: "requireEvidence", value: true }],
    uiHints: { showPassagePicker: false, checkInQuestion: null, endOfSession: false },
  };
  const parsed = parseEnvelope(JSON.stringify(v1));
  assertEquals(parsed.say, "Read it again.");
  assertEquals(parsed.speakers, undefined);
  assertEquals(parsed.profileOps, undefined);
  assertEquals(parsed.uiHints.adjudicationRequired, undefined);
});

Deno.test("v2 roundtrip: speakers + profileOps + recordPosition + adjudicationRequired", () => {
  const v2 = {
    say: "VOSS: The sentence is doing the work.\n\nARKADY: No — the soul is.",
    speakers: [
      {
        personaId: "voss",
        say: "The sentence is doing the work.",
        citations: [{ passageId: "dubliners:3:19", quote: "the word paralysis", why: "her evidence" }],
      },
      { personaId: "arkady", say: "No — the soul is.", citations: [] },
    ],
    citations: [{ passageId: "dubliners:3:19", quote: "the word paralysis", why: "shared exhibit" }],
    stateOps: [
      { op: "recordPosition", side: "voss", statement: "The form carries the meaning." },
      { op: "advancePhase" },
    ],
    profileOps: [
      {
        op: "evidence",
        kind: "seminar_turn",
        dimension: "form",
        signal: "Sided with the formal reading and cited a sentence-level receipt unprompted.",
        weight: 0.7,
      },
    ],
    uiHints: {
      showPassagePicker: false,
      checkInQuestion: null,
      endOfSession: false,
      adjudicationRequired: true,
    },
  };
  const raw = JSON.stringify(v2);
  const parsed = parseEnvelope(raw);

  assertEquals(parsed.speakers?.length, 2);
  assertEquals(parsed.speakers?.[0].personaId, "voss");
  assertEquals(parsed.speakers?.[0].citations[0].quote, "the word paralysis");
  assertEquals(parsed.profileOps?.length, 1);
  assertEquals(parsed.profileOps?.[0].dimension, "form");
  assertEquals(parsed.uiHints.adjudicationRequired, true);

  const pos = parsed.stateOps[0];
  assertEquals(pos.op, "recordPosition");
  if (pos.op === "recordPosition") {
    assertEquals(pos.side, "voss");
    assertEquals(pos.statement, "The form carries the meaning.");
  }
  assertEquals(parsed.stateOps[1].op, "advancePhase");

  // Roundtrip: re-serialize and re-parse without loss.
  assertEquals(parseEnvelope(JSON.stringify(parsed)), parsed);
});

Deno.test("malformed v2 fields are rejected", () => {
  const base = {
    say: "x",
    citations: [],
    stateOps: [],
    uiHints: { showPassagePicker: false, checkInQuestion: null, endOfSession: false },
  };
  // speakers item missing citations
  assertThrows(() =>
    parseEnvelope(JSON.stringify({
      ...base,
      speakers: [{ personaId: "voss", say: "hm" }],
    }))
  );
  // profileOps wrong op
  assertThrows(() =>
    parseEnvelope(JSON.stringify({
      ...base,
      profileOps: [{ op: "erase", kind: "seminar_turn", dimension: "form", signal: "s", weight: 1 }],
    }))
  );
  // recordPosition missing statement
  assertThrows(() =>
    parseEnvelope(JSON.stringify({
      ...base,
      stateOps: [{ op: "recordPosition", side: "voss" }],
    }))
  );
  // adjudicationRequired non-boolean
  assertThrows(() =>
    parseEnvelope(JSON.stringify({
      ...base,
      uiHints: { ...base.uiHints, adjudicationRequired: "yes" },
    }))
  );
});

Deno.test("commitmentOps: valid ops + Academy stateOps decode (§12.1/§12.2)", () => {
  const academy = {
    say: "So the thesis is on the table.",
    citations: [],
    stateOps: [
      { op: "recordThesis", thesis: "Justice is paying what you owe." },
      { op: "declareOutcome", outcome: "aporia" },
      { op: "recordChoice", nodeId: "n2", choice: "keep the ring" },
      { op: "applyPump", pumpId: "p1" },
      { op: "recordHuntResult", found: true, attempts: 2 },
      { op: "reviseDefinition", definition: "Justice is giving each their due." },
    ],
    commitmentOps: [
      {
        op: "assert",
        claim: "There are moral facts independent of what anyone believes.",
        domain: "ethics",
        ontologyId: "ethics.moral-realism",
        evidence: "Said a whole society can be wrong about justice.",
      },
      { op: "abandon", claim: "Justice is the advantage of the stronger.", domain: "political" },
    ],
    uiHints: { showPassagePicker: false, checkInQuestion: null, endOfSession: false },
  };
  const parsed = parseEnvelope(JSON.stringify(academy));
  assertEquals(parsed.commitmentOps?.length, 2);
  assertEquals(parsed.commitmentOps?.[0].ontologyId, "ethics.moral-realism");
  assertEquals(parsed.commitmentOps?.[1].evidence, undefined);
  assertEquals(parsed.stateOps[0].op, "recordThesis");
  assertEquals(parsed.stateOps[4].op, "recordHuntResult");
  // Roundtrip without loss.
  assertEquals(parseEnvelope(JSON.stringify(parsed)), parsed);

  // v1 envelopes still decode with the new field absent.
  assertEquals(parseEnvelope(JSON.stringify(minimalEnvelope("x"))).commitmentOps, undefined);
});

Deno.test("commitmentOps: unknown op rejected; bad domain dropped server-side (profileOps pattern)", () => {
  const base = {
    say: "x",
    citations: [],
    stateOps: [],
    uiHints: { showPassagePicker: false, checkInQuestion: null, endOfSession: false },
  };
  // Unknown op verb → rejected at parse (mirrors profileOps op !== 'evidence').
  assertThrows(() =>
    parseEnvelope(JSON.stringify({
      ...base,
      commitmentOps: [{ op: "proclaim", claim: "c", domain: "ethics" }],
    }))
  );
  // Non-string ontologyId → rejected at parse.
  assertThrows(() =>
    parseEnvelope(JSON.stringify({
      ...base,
      commitmentOps: [{ op: "assert", claim: "c", domain: "ethics", ontologyId: 7 }],
    }))
  );
  // Malformed Academy stateOps → rejected at parse.
  assertThrows(() =>
    parseEnvelope(JSON.stringify({ ...base, stateOps: [{ op: "recordThesis" }] }))
  );
  assertThrows(() =>
    parseEnvelope(JSON.stringify({
      ...base,
      stateOps: [{ op: "declareOutcome", outcome: "victory" }],
    }))
  );

  // Bad domain is a *string*, so it parses (like an unknown profile dimension)
  // and is dropped by server-side validation (commitments.ts).
  const parsed = parseEnvelope(JSON.stringify({
    ...base,
    commitmentOps: [
      { op: "assert", claim: "stars decide", domain: "astrology" },
      { op: "lean", claim: "the mind is physical", domain: "mind" },
    ],
  }));
  assertEquals(parsed.commitmentOps?.length, 2);
  const valid = validateCommitmentOps(parsed.commitmentOps, new Set());
  assertEquals(valid.length, 1);
  assertEquals(valid[0].domain, "mind");
});

Deno.test("minimalEnvelope is a valid envelope", () => {
  const env = minimalEnvelope("");
  assertEquals(parseEnvelope(JSON.stringify(env)), env);
});
