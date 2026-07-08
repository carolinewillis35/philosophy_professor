# SCOPE ADDENDUM — Novelty expansion (eight features)

Build-relevant summary, tiers, and sequencing of the novelty addendum. Binding
interfaces are in CONTRACTS.md §11+ (envelope v2, new session types, spec
schemas, profile tables).

## Features and tiers

| § | Feature | Tier | One-liner |
|---|---|---|---|
| 2 | **Reader Profile** | N1 — build first | Longitudinal model of the student's interpretive habits/blind spots, built from annotations, seminar answers, rubric scores. Professors teach *against* it. Transparent, contestable, deletable. |
| 1 | **Disputation seminars** | N1 — flagship | Two professors read the same passage incompatibly, argue in front of the student; student adjudicates and is cross-examined by the professor whose side they rejected. Authored `DisputeSpec` spine + generated flesh. |
| 5 | **Live co-reading** | N1 | Professor reads with you: authored `Waypoints` fire marginal interjections/stops as you scroll; budgeted generated interjections react to live annotations. Marginalia mode only at launch. |
| 3 | **Counterfactual craft labs** | N1 | Damaged text (excised scene, flattened syntax) presented; student articulates what died; side-by-side diff reveal. Damages authored at build time (`CraftLabSpec`), never runtime-invented. |
| 4 | Imitation assignments | N2 | Pastiche with craft grading: per-author rubric + deterministic stylometrics + reveal of the author's actual next paragraph. Delta on essay cycle. |
| 6 | Translation variorum | N2 | Two PD translations aligned paragraph-level; argue word choices. Needs pipeline alignment + side-by-side component (shared with §3). |
| 7 | Recitation & memorization | N3 | SRS memorization + on-device constrained speech recognition fidelity scoring + Poet-in-Residence coaching. |
| 8 | Reception-history staging | N3 | Read as an 1879 audience member; era-gated commentary; primary-source reactions quoted from retrieval (never fabricated). Composes §5 + RAG. |

## Ordering

§2 → §1 → §5 → §3 → §4 → §6 → §7 → §8.

## Delivery drops

1. **"The professor knows you"** — Reader Profile + profile page + marginalia time-travel. ← *current*
2. **"The faculty argue"** — Disputations in two courses. ← *current*
3. **"Read together"** — Co-reading waypoints on one flagship course. ← *current*
4. **"The craft wing"** — Craft labs + imitation (shared diff component, writer segment).
5. **"The scholarship wing"** — Variorum + reception staging.
6. **"By heart"** — Recitation + Poet-in-Residence (target April / National Poetry Month).

## What must not break

- The quote-integrity contract (extends to primary sources; craft-lab altered text is always visually marked and never rendered as the author's).
- One profile-aware professor move per session, maximum. Profile claims need n≥5 evidence per dimension; observations with receipts, never psychology; reading behavior only, never the person.
- Authored-spine-plus-generated-flesh: disputations, labs, waypoints, stagings all improvise around authored specs, never from scratch.
- Both disputation positions respectable; debrief names what each reading sees and misses.
- Co-reading: interruption is a spice — one stop per authored interval; blown-past waypoints get one chapter-break note, never chasing.
