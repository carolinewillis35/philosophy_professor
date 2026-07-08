// deno test --allow-env supabase/functions/_shared/engine_academy_test.ts
//
// Academy kind wiring (CONTRACTS §12.1): registry registration, op-driven
// phase transitions, and the canComplete completion guard (§12.8).
import { assert, assertEquals } from "jsr:@std/assert@1";
import {
  applyStateOps,
  type CourseUnit,
  initialState,
  instructionBlock,
  KIND_REGISTRY,
} from "./engine.ts";
import type { ArgumentLabSpec, ElenchusSpec } from "./kinds_academy.ts";

const unit: CourseUnit = {
  number: 1,
  title: "What Is Justice?",
  reading: [{ bookID: "republic-jowett", chStart: 0, chEnd: 0 }],
};

const elenchusSpec: ElenchusSpec = {
  id: "wij-elenchus-what-is-justice",
  openingQuestion: "What is justice?",
  span: { bookID: "republic-jowett", chStart: 0, chEnd: 0 },
  classicMoves: [{ definition: "returning what one owes", counterexample: "the madman's weapon" }],
};

Deno.test("Academy kinds are registered with canComplete guards", () => {
  for (const kind of ["elenchus", "thoughtExperiment", "argumentLab"] as const) {
    assert(KIND_REGISTRY[kind], `${kind} missing from KIND_REGISTRY`);
    assert(typeof KIND_REGISTRY[kind].canComplete === "function");
  }
});

Deno.test("elenchus: phase machine + completeSession gated on reflection (§12.8)", () => {
  let state = initialState("elenchus", unit, { spec: elenchusSpec });
  assertEquals(state.phase, "thesis");
  assertEquals(state.specId, "wij-elenchus-what-is-justice");

  let r = applyStateOps("elenchus", state, [
    { op: "recordThesis", thesis: "Justice is paying what you owe." },
  ]);
  assertEquals(r.state.phase, "definition");

  r = applyStateOps("elenchus", r.state, [
    { op: "reviseDefinition", definition: "Giving back what one has received." },
  ]);
  assertEquals(r.state.phase, "counterexample");

  // completeSession from a non-reflection phase is dropped, even when the
  // same envelope declares the outcome (aporia must end in a reflection turn).
  r = applyStateOps("elenchus", r.state, [
    { op: "declareOutcome", outcome: "aporia" },
    { op: "completeSession" },
  ]);
  assertEquals(r.completeSession, false);
  assertEquals(r.completionRefused, true);
  assertEquals(r.state.phase, "reflection");
  assertEquals(r.state.outcome, "aporia");

  // From reflection, completion is honored.
  r = applyStateOps("elenchus", r.state, [{ op: "completeSession" }]);
  assertEquals(r.completeSession, true);
  assertEquals(r.completionRefused, false);
});

Deno.test("elenchus: revision cap forces aporia + reflection (DECISIONS A13)", () => {
  let state = initialState("elenchus", unit, { spec: elenchusSpec });
  state = applyStateOps("elenchus", state, [
    { op: "recordThesis", thesis: "t" },
  ]).state;
  state = applyStateOps("elenchus", state, [
    { op: "reviseDefinition", definition: "d0" },
  ]).state;
  for (let i = 1; i <= 4; i++) {
    state = applyStateOps("elenchus", state, [{ op: "advancePhase" }]).state; // -> revision
    state = applyStateOps("elenchus", state, [
      { op: "reviseDefinition", definition: `d${i}` },
    ]).state;
  }
  assertEquals(state.revisions, 4);
  assertEquals(state.outcome, "aporia");
  assertEquals(state.phase, "reflection");
});

Deno.test("thoughtExperiment: choices recorded; completion only from debrief", () => {
  let state = initialState("thoughtExperiment", unit, {
    spec: { id: "te1", title: "Ring of Gyges", setup: "...", philosophicalPayload: "...", nodes: [] },
  });
  assertEquals(state.phase, "run");

  let r = applyStateOps("thoughtExperiment", state, [
    { op: "recordChoice", nodeId: "n2", choice: "keep the ring" },
    { op: "applyPump", pumpId: "p1" },
  ]);
  assertEquals(r.state.path, [{ nodeId: "n2", choice: "keep the ring" }]);
  assertEquals(r.state.pumpsApplied, ["p1"]);

  r = applyStateOps("thoughtExperiment", r.state, [{ op: "advancePhase" }]);
  assertEquals(r.state.phase, "interrogation");
  r = applyStateOps("thoughtExperiment", r.state, [
    { op: "advancePhase" },
    { op: "completeSession" },
  ]);
  // pre-ops phase was interrogation: refused.
  assertEquals(r.completeSession, false);
  assertEquals(r.completionRefused, true);
  assertEquals(r.state.phase, "debrief");
  r = applyStateOps("thoughtExperiment", r.state, [{ op: "completeSession" }]);
  assertEquals(r.completeSession, true);
});

Deno.test("argumentLab: hunt vs collapse phase orders; completion from rebuild", () => {
  const huntSpec: ArgumentLabSpec = {
    id: "lab-hunt",
    title: "t",
    source: { bookID: "republic-jowett" },
    conclusion: { id: "c", text: "..." },
    premises: [{ id: "p1", text: "...", stated: false, supports: "c" }],
    mode: "hunt",
    hiddenPremiseId: "p1",
  };
  let state = initialState("argumentLab", unit, { spec: huntSpec });
  assertEquals(state.mode, "hunt");
  const phases: string[] = [state.phase];
  for (let i = 0; i < 3; i++) {
    state = applyStateOps("argumentLab", state, [{ op: "advancePhase" }]).state;
    phases.push(state.phase);
  }
  assertEquals(phases, ["mapPresented", "hunt", "reveal", "rebuild"]);
  let r = applyStateOps("argumentLab", state, [
    { op: "recordHuntResult", found: true, attempts: 2 },
    { op: "completeSession" },
  ]);
  assertEquals(r.state.found, true);
  assertEquals(r.state.attempts, 2);
  assertEquals(r.completeSession, true);

  const collapseSpec: ArgumentLabSpec = { ...huntSpec, id: "lab-collapse", mode: "collapse", hiddenPremiseId: undefined, removedPremiseId: "p1" };
  state = initialState("argumentLab", unit, { spec: collapseSpec });
  const cPhases: string[] = [state.phase];
  for (let i = 0; i < 2; i++) {
    state = applyStateOps("argumentLab", state, [{ op: "advancePhase" }]).state;
    cPhases.push(state.phase);
  }
  assertEquals(cPhases, ["mapPresented", "collapse", "rebuild"]);
  r = applyStateOps("argumentLab", state, [{ op: "completeSession" }]);
  assertEquals(r.completeSession, true);
});

Deno.test("instructionBlock: commitment-move line follows the digest gate (§12.2)", () => {
  const state = initialState("elenchus", unit, { spec: elenchusSpec });
  const base = { unit, pace: "standard", spec: elenchusSpec };
  const without = instructionBlock("elenchus", state, base);
  assert(!without.includes("COMMITMENTS:"));
  const withDigest = instructionBlock("elenchus", state, {
    ...base,
    commitmentDigestPresent: true,
  });
  assert(withDigest.includes("never a verdict of incoherence"));
  const used = instructionBlock("elenchus", { ...state, _commitmentMoveUsed: true }, {
    ...base,
    commitmentDigestPresent: true,
  });
  assert(used.includes("already made your one commitment move"));
});
