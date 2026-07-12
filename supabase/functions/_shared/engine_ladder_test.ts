// deno test --allow-env supabase/functions/_shared/engine_ladder_test.ts
//
// E-M2 "the Ladder" wiring (CONTRACTS §14): the steelman kind's phase
// machine + rubric op, the changelog event derivation, and the
// tension-reconcile / steelman-score op extraction.
import { assert, assertEquals } from "jsr:@std/assert@1";
import {
  applyStateOps,
  type CourseUnit,
  initialState,
  instructionBlock,
  KIND_REGISTRY,
} from "./engine.ts";
import { changeEvent } from "./commitments.ts";
import { MAX_PROBE_ROUNDS } from "./kinds_engagement.ts";

const unit: CourseUnit = { number: 0, title: "", reading: [] };

Deno.test("steelman is registered with a canComplete guard", () => {
  assert(KIND_REGISTRY.steelman);
  assert(typeof KIND_REGISTRY.steelman.canComplete === "function");
});

Deno.test("steelman: phase machine, probe cap, debrief only via score (§14.4)", () => {
  let state = initialState("steelman", unit, {});
  state.targetClaim = "Moral facts are mind-independent.";
  assertEquals(state.phase, "brief");
  assertEquals(state.level, null);

  // completeSession before debrief is refused.
  let r = applyStateOps("steelman", state, [{ op: "completeSession" }]);
  assertEquals(r.completeSession, false);
  assertEquals(r.completionRefused, true);

  // brief → attempt → probe via advancePhase.
  r = applyStateOps("steelman", state, [{ op: "advancePhase" }]);
  assertEquals(r.state.phase, "attempt");
  r = applyStateOps("steelman", r.state, [{ op: "advancePhase" }]);
  assertEquals(r.state.phase, "probe");
  assertEquals(r.state.probeRounds, 1); // a turn spent probing counts a round

  // advancePhase can NOT reach debrief (verdict is the ceiling).
  r = applyStateOps("steelman", r.state, [{ op: "advancePhase" }]);
  assertEquals(r.state.phase, "verdict");
  const stuck = applyStateOps("steelman", r.state, [{ op: "advancePhase" }]);
  assertEquals(stuck.state.phase, "verdict");

  // The score op grades and moves to debrief; the payload is extracted.
  r = applyStateOps("steelman", r.state, [
    { op: "recordSteelmanScore", level: 3, justification: "A holder would nod; missing the modal premise." },
  ]);
  assertEquals(r.state.phase, "debrief");
  assertEquals(r.state.level, 3);
  assertEquals(r.steelmanScore?.level, 3);

  // A second score is ignored (level already set).
  const again = applyStateOps("steelman", r.state, [
    { op: "recordSteelmanScore", level: 4, justification: "no" },
  ]);
  assertEquals(again.state.level, 3);

  // completeSession from debrief goes through.
  r = applyStateOps("steelman", r.state, [{ op: "completeSession" }]);
  assert(r.completeSession);
});

Deno.test("steelman: out-of-range levels rejected; instruction carries the rubric", () => {
  let state = initialState("steelman", unit, {});
  state.targetClaim = "x";
  state.phase = "verdict";
  const r = applyStateOps("steelman", state, [
    { op: "recordSteelmanScore", level: 5, justification: "too generous" },
  ]);
  assertEquals(r.state.level, null);
  assertEquals(r.steelmanScore, null);

  const block = instructionBlock("steelman", state, { unit, pace: "standard" });
  assert(block.includes("signable"), "rubric levels must be in the instruction");
  assert(block.includes("argument, not the person"));
  assert(block.includes(`${MAX_PROBE_ROUNDS}`));
});

Deno.test("markTensionReconciled: payload extracted, empty resolution dropped (§14.2)", () => {
  const state = initialState("seminar", unit, {});
  let r = applyStateOps("seminar", state, [
    { op: "markTensionReconciled", resolution: "Subordinated liberty to the harm principle." },
  ]);
  assertEquals(r.tensionResolution, "Subordinated liberty to the harm principle.");
  r = applyStateOps("seminar", state, [
    { op: "markTensionReconciled", resolution: "   " },
  ]);
  assertEquals(r.tensionResolution, null);
});

Deno.test("changeEvent derives the §14.1 ledger verbs", () => {
  assertEquals(changeEvent(null, "leaned"), { event: "leaned", priorStrength: null });
  assertEquals(changeEvent("leaned", "asserted"), { event: "asserted", priorStrength: "leaned" });
  assertEquals(changeEvent("asserted", "asserted"), { event: "affirmed", priorStrength: null });
  assertEquals(changeEvent("asserted", "abandoned"), { event: "abandoned", priorStrength: "asserted" });
});
