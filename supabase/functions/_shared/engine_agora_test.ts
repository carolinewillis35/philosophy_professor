// deno test --allow-env supabase/functions/_shared/engine_agora_test.ts
//
// E-M4 "the Agora" wiring (CONTRACTS §16): the symposium kind's phase
// machine, adjudication capture, the undecided path, and the no-winner /
// no-crowd instruction guarantees.
import { assert, assertEquals } from "jsr:@std/assert@1";
import {
  applyStateOps,
  type CourseUnit,
  initialState,
  instructionBlock,
  KIND_REGISTRY,
} from "./engine.ts";
import type { SymposiumSpec } from "./kinds_agora.ts";

const unit: CourseUnit = { number: 0, title: "", reading: [] };

const spec: SymposiumSpec = {
  id: "sym-001",
  question: "Does a promise bind you once keeping it helps no one?",
  personaA: "whitmore",
  personaB: "lindqvist",
  positionA: { label: "Yes — the promise IS the reason", ontologyId: "ethics.deontology" },
  positionB: { label: "No — promises serve lives, not the reverse", ontologyId: null },
  crux: "whether the act of promising creates a reason independent of outcomes",
  volleys: [
    { speaker: "whitmore", say: "Number the premises with me." },
    { speaker: "lindqvist", say: "First ask who taught you to keep ledgers." },
    { speaker: "whitmore", say: "Genealogy is not refutation." },
    { speaker: "lindqvist", say: "And a ledger is not a life." },
  ],
};

Deno.test("symposium is registered with a canComplete guard", () => {
  assert(KIND_REGISTRY.symposium);
  assert(typeof KIND_REGISTRY.symposium.canComplete === "function");
});

Deno.test("symposium: ruled path — recordPosition jumps to cross_examination (§16.2)", () => {
  let state = initialState("symposium", unit, { spec });
  assertEquals(state.phase, "question_presented");
  assertEquals(state.symposiumId, "sym-001");

  // Complete early is refused.
  let r = applyStateOps("symposium", state, [{ op: "completeSession" }]);
  assertEquals(r.completionRefused, true);

  r = applyStateOps("symposium", state, [{ op: "advancePhase" }]);
  assertEquals(r.state.phase, "exchange");
  assertEquals(r.state.volley, 1); // an exchange turn is a volley

  r = applyStateOps("symposium", r.state, [{ op: "advancePhase" }]);
  assertEquals(r.state.phase, "adjudication");

  r = applyStateOps("symposium", r.state, [
    { op: "recordPosition", side: "whitmore", statement: "The promise created the reason; outcomes came later." },
  ]);
  assertEquals(r.state.phase, "cross_examination");
  assertEquals(r.state.position.side, "whitmore");

  r = applyStateOps("symposium", r.state, [{ op: "advancePhase" }]);
  assertEquals(r.state.phase, "joint_debrief");
  r = applyStateOps("symposium", r.state, [{ op: "completeSession" }]);
  assert(r.completeSession);
});

Deno.test("symposium: undecided path — advancePhase through adjudication, no position (§16.2)", () => {
  let r = applyStateOps("symposium", initialState("symposium", unit, { spec }), [
    { op: "advancePhase" }, // exchange
  ]);
  r = applyStateOps("symposium", r.state, [{ op: "advancePhase" }]); // adjudication
  r = applyStateOps("symposium", r.state, [{ op: "advancePhase" }]); // cross_examination
  assertEquals(r.state.phase, "cross_examination");
  assertEquals(r.state.position, null);

  const block = instructionBlock("symposium", r.state, { unit, pace: "standard", spec });
  assert(block.includes("no ruling"), "undecided cross-exam variant must be addressed");

  r = applyStateOps("symposium", r.state, [{ op: "advancePhase" }]);
  r = applyStateOps("symposium", r.state, [{ op: "completeSession" }]);
  assert(r.completeSession);
});

Deno.test("symposium: instruction carries the §16.6 guarantees", () => {
  const state = initialState("symposium", unit, { spec });
  const block = instructionBlock("symposium", state, { unit, pace: "standard", spec });
  assert(block.includes("NO WINNER IS EVER DECLARED"));
  assert(block.includes("Never mention crowd numbers"));
  assert(block.includes("you do not know it and never ask for it"), "the before-tap stays private");

  // Authored volleys are the spine of the exchange phase.
  const r = applyStateOps("symposium", state, [{ op: "advancePhase" }]);
  const exchange = instructionBlock("symposium", r.state, { unit, pace: "standard", spec });
  assert(exchange.includes("Number the premises with me."), "authored volleys are the spine");
});

Deno.test("symposium: recordPosition outside adjudication/exchange is ignored", () => {
  const state = initialState("symposium", unit, { spec });
  // question_presented: ruling before the arguments is not a thing.
  const r = applyStateOps("symposium", state, [
    { op: "recordPosition", side: "whitmore", statement: "premature" },
  ]);
  assertEquals(r.state.position, null);
  assertEquals(r.state.phase, "question_presented");
});
