# Decisions log — The Academy

Resolutions for the `[DECISION]` flags in `SCOPE.md`, plus build-time choices.
Platform decisions inherited from The Seminar (models, embeddings, envelope
streaming, voice, portraits, EPUB handling) carry over unchanged and are
recorded in that repo's decisions log; the table below is Academy-specific.

| # | Decision | Choice | Rationale |
|---|---|---|---|
| A1 | First ingested text | `republic-jowett` (Gutenberg #1497, Jowett translation) | Anchors M1 (Elenchus on justice, *What Is Justice?*). Jowett died 1893; translation 1871/1894 — unambiguously PD-US. Pipeline confirmed: Jowett's long Introduction/Analysis is front matter and is excluded; Books I–X chapterize as ch 0–9, 510 passages |
| A2 | Plato translation | Jowett throughout MVP | Clear PD status, readable, and the standard free edition; Bloom/Grube/Reeve are NOT PD |
| A3 | Nietzsche translations | Thomas Common (*Zarathustra*, PG #1998), Helen Zimmern (*Beyond Good and Evil*, PG #4363), Ludovici — all pre-1930 ✅. **Kaufmann is NOT public domain — never ingest** | Per scope `[DECISION]` flag; recorded in LICENSING.md |
| A4 | New session kinds | `elenchus`, `thoughtExperiment`, `argumentLab` in migration 0004; `dialogue`, `rediscovery` reserved for V1 migrations | Matches MVP cut in scope §4; keeps kind check-constraint churn to one migration per tier |
| A5 | Commitment writes | Dual-path: in-turn envelope `commitmentOps` (professor notices live) + post-session MODEL_LIGHT extraction sweep (catches what the professor missed); in-turn ops win on conflict | In-turn-only misses positions asserted mid-flow; batch-only loses the professor's judgment about what was *actually asserted* vs. floated |
| A6 | Tension computation | Direct `conflicts` edges + 1-hop entailment (`A entails X, X conflicts B`), no deeper closure | Conservative by contract (scope §7): false contradictions are the feature's failure mode; depth-2+ chains compound ontology judgment calls |
| A7 | Tension surfacing threshold | Both sides `asserted` with `affirm_count ≥ 2`; at most one tension in the digest; oldest-unraised first | Scope guardrail (minimum evidence); one-per-session keeps it a scalpel, not a nag |
| A8 | Ontology storage | Authored `content/ontology/claims.json`, seeded to `claims`/`claim_edges` catalog tables; versioned like personas | It's content, not code — human-reviewable, diffable, and the validator cross-checks course `relatedClaims` against it |
| A9 | Ontology starter size | ~60 claims (≥10 per domain) for M2, growing toward ~200 | Scope build order M2 says start ~60; the required-id list in CONTRACTS §12.6 keeps course authoring unblocked |
| A10 | Thought-experiment branching | Authored nodes render client-side with no API call; the professor enters only at interrogation/debrief | Determinism + zero-latency branching + screenshot-shareable cards; the LLM interrogates the *why*, which is where it adds value |
| A11 | Argument-map rendering | Deterministic SwiftUI layered layout from `ArgumentSpec` (no LLM in the render path) | Scope §5 names this a primitive; correctness of the diagram must not depend on model output |
| A12 | iOS rebrand | Directory + target `TheAcademy`, display name "The Academy", bundle id `com.theacademy.app` | Clean fork; XcodeGen makes the rename cheap |
| A13 | Elenchus completion rule | `completeSession` rejected unless `phase == "reflection"`; professor must `declareOutcome` (aporia or robust) by revision 4 | Enforces the aporia-ends-in-reflection guardrail mechanically, not just in the persona doc |
| A14 | Worldview page vs. Profile page | Worldview replaces the reader-profile page as the Academy's identity surface; the reader-profile *pipeline* stays on (it still tunes teaching) but its UI is folded into Worldview | One identity surface; commitments are the product here, attention dimensions are supporting cast |
