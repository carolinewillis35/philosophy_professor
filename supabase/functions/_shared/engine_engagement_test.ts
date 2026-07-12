// deno test --allow-env supabase/functions/_shared/engine_engagement_test.ts
//
// Engagement kind wiring (CONTRACTS §13): registry registration, the clinic's
// op-validated map construction, phase gating, and the dailyQuestion
// single-reply contract.
import { assert, assertEquals } from "jsr:@std/assert@1";
import {
  applyStateOps,
  type CourseUnit,
  initialState,
  instructionBlock,
  KIND_REGISTRY,
} from "./engine.ts";
import {
  CLINIC_MAX_PREMISES,
  type ClinicState,
  type DailyQuestionSpec,
} from "./kinds_engagement.ts";

const unit: CourseUnit = { number: 0, title: "", reading: [] };

const dailySpec: DailyQuestionSpec = {
  id: "dq-001",
  question: "Is a perfect copy of you — memories, habits, loves — you?",
  domain: "mind",
  personaId: "whitmore",
  options: [
    { id: "yes", label: "Yes — that's all I am", ontologyId: "mind.physicalism" },
    { id: "no", label: "No — a copy is a twin, not me", ontologyId: null },
  ],
};

Deno.test("engagement kinds are registered with canComplete guards", () => {
  for (const kind of ["dailyQuestion", "argumentClinic"] as const) {
    assert(KIND_REGISTRY[kind], `${kind} missing from KIND_REGISTRY`);
    assert(typeof KIND_REGISTRY[kind].canComplete === "function");
  }
});

Deno.test("dailyQuestion: single-reply contract in the instruction block (§13.2)", () => {
  const state = initialState("dailyQuestion", unit, { spec: dailySpec });
  assertEquals(state.questionId, "dq-001");
  assertEquals(state.replied, false);
  state.optionId = "yes";

  const block = instructionBlock("dailyQuestion", state, { unit, pace: "standard", spec: dailySpec });
  assert(block.includes("EXACTLY ONCE"), "must state the one-reply rule");
  assert(block.includes("120 words"), "must carry the length cap");
  assert(block.includes('"Yes — that\'s all I am"'), "must surface the tapped option");
  assert(block.includes("'assert'"), "must state the tap-never-asserts rule");

  // completeSession is never refused — the reply turn ends the session.
  const r = applyStateOps("dailyQuestion", state, [{ op: "completeSession" }]);
  assert(r.completeSession);
  assertEquals(r.completionRefused, false);
  assertEquals(r.state.replied, true);
});

Deno.test("argumentClinic: map construction is op-validated (§13.3)", () => {
  let state = initialState("argumentClinic", unit, {});
  assertEquals(state.phase, "intake");
  assertEquals(state.mapVersion, 0);

  // addPremise before a conclusion exists is ignored.
  let r = applyStateOps("argumentClinic", state, [
    { op: "addPremise", id: "p1", text: "orphan", stated: true, supports: "c" },
  ]);
  assertEquals((r.state as ClinicState).userArgument.premises.length, 0);

  r = applyStateOps("argumentClinic", r.state, [
    { op: "setConclusion", text: "We should move to the city." },
    { op: "advancePhase" },
  ]);
  state = r.state;
  assertEquals(state.phase, "excavation");
  assertEquals(state.userArgument.conclusion.text, "We should move to the city.");
  assertEquals(state.mapVersion, 1);

  r = applyStateOps("argumentClinic", state, [
    { op: "addPremise", id: "p1", text: "Careers matter more than proximity to family.", stated: false, supports: "c" },
    { op: "addPremise", id: "p2", text: "The city has better jobs.", stated: true, supports: "c" },
    // Bad supports ref and duplicate id are both ignored:
    { op: "addPremise", id: "p3", text: "dangling", stated: true, supports: "p9" },
    { op: "addPremise", id: "p1", text: "dupe", stated: true, supports: "c" },
  ]);
  state = r.state;
  assertEquals(state.userArgument.premises.length, 2);
  assertEquals(state.userArgument.premises[0].stated, false);
  assertEquals(state.mapVersion, 3);

  // revisePremise sharpens in place; markCrux requires a known id.
  r = applyStateOps("argumentClinic", state, [
    { op: "revisePremise", id: "p2", text: "The city has better jobs in my field." },
    { op: "markCrux", id: "p1", kind: "value" },
    { op: "markCrux", id: "p7", kind: "fact" }, // unknown id → ignored
    // deno-lint-ignore no-explicit-any
    { op: "markCrux", id: "p1", kind: "bogus" } as any, // unknown kind → ignored
  ]);
  state = r.state;
  assertEquals(state.userArgument.premises[1].text, "The city has better jobs in my field.");
  assertEquals(state.cruxes, [{ id: "p1", kind: "value" }]);
});

Deno.test("argumentClinic: premise cap (§13.3)", () => {
  let r = applyStateOps("argumentClinic", initialState("argumentClinic", unit, {}), [
    { op: "setConclusion", text: "c" },
  ]);
  for (let i = 1; i <= CLINIC_MAX_PREMISES + 2; i++) {
    r = applyStateOps("argumentClinic", r.state, [
      { op: "addPremise", id: `p${i}`, text: `premise ${i}`, stated: true, supports: "c" },
    ]);
  }
  assertEquals((r.state as ClinicState).userArgument.premises.length, CLINIC_MAX_PREMISES);
});

Deno.test("argumentClinic: completeSession gated on handback (§13.3)", () => {
  let r = applyStateOps("argumentClinic", initialState("argumentClinic", unit, {}), [
    { op: "setConclusion", text: "The claim at issue." },
  ]);

  // Attempting to complete from intake is refused.
  r = applyStateOps("argumentClinic", r.state, [{ op: "completeSession" }]);
  assertEquals(r.completeSession, false);
  assertEquals(r.completionRefused, true);

  // Walk the phases: intake → excavation → map → crux → handback.
  for (const expected of ["excavation", "map", "crux", "handback"]) {
    r = applyStateOps("argumentClinic", r.state, [{ op: "advancePhase" }]);
    assertEquals(r.state.phase, expected);
  }
  // advancePhase past the end stays at handback.
  r = applyStateOps("argumentClinic", r.state, [{ op: "advancePhase" }]);
  assertEquals(r.state.phase, "handback");

  r = applyStateOps("argumentClinic", r.state, [{ op: "completeSession" }]);
  assert(r.completeSession);
  assertEquals(r.completionRefused, false);
});

Deno.test("argumentClinic: guardrails live in the instruction block (§13.4)", () => {
  const state = initialState("argumentClinic", unit, {});
  const block = instructionBlock("argumentClinic", state, { unit, pace: "standard" });
  assert(block.includes("never referee the relationship"));
  assert(block.includes("never give life advice"));
  assert(block.includes("citations array stays EMPTY"));
});
