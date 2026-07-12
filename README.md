# The Academy

An AI philosophy department in your pocket: professors from clashing
traditions, Socratic sessions that aim for productive aporia, thought
experiments that pump your intuitions harder, argument maps with the hidden
premise missing — and a **Commitment Map** that tracks the positions you
actually assert and catches you when a new one contradicts an old one.
iOS (SwiftUI) + Supabase (Postgres/pgvector + Edge Functions) + Claude API.

**Fork of The Seminar engine** (`../literature_professor`), repointed at
philosophy. The platform — personas, envelope, RAG with verified quotation,
courses, reader, profile pipeline — is inherited; this repo is the delta.

**Structure is the product; the LLM is the faculty. The app has no philosophy —
the faculty disagree with each other so no house view can leak.**

## Repository map

| Path | What it is |
|---|---|
| `docs/SCOPE.md` | The Academy product scope (MVP → V2) |
| `docs/SCOPE-ADDENDUM.md` | Engagement addendum (E1–E3): daily loop, growth ladder, seminar-to-life bridge |
| `docs/SEMINAR-SCOPE*.md` | Platform reference (the engine this forks) |
| `docs/CONTRACTS.md` | **Binding cross-component interfaces** — §12 is the Academy delta, §13–§14 the engagement deltas (E-M1/E-M2); read them first |
| `docs/DECISIONS.md` | Resolved `[DECISION]` flags (A1–A14) |
| `docs/LICENSING.md` | Public-domain verification per edition (Kaufmann is NOT PD; Jowett is) |
| `content/personas/` | Faculty persona documents + registry (Vlachos, Whitmore, Lindqvist at MVP) |
| `content/ontology/claims.json` | **The claim ontology** — canonical positions + classical entailments/tensions; powers the Commitment Map |
| `content/daily/questions.json` | The Daily Question bank (§13.2) — one-tap positions mapped to ontology claims |
| `content/drops/drops.json` | Weekly thought-experiment drops (§14.3) — five branching labs with crowd compare |
| `content/courses/` | Authored course JSON incl. elenchus specs, thought experiments, argument labs |
| `pipeline/` | Text ingestion (Gutenberg → chapters → passages → embeddings → seed SQL) + content validator |
| `supabase/` | Schema + RLS + retrieval RPC, session-engine Edge Function, commitment pipeline |
| `ios/` | SwiftUI app (Catalog, Reader, Session, Worldview) |

## What's new on top of the engine

- **Session kinds:** `elenchus` (thesis → definition → counterexample →
  revision → aporia/robust → reflection; the state machine tolerates and aims
  for aporia), `thoughtExperiment` (authored branching nodes render
  client-side; the professor interrogates *why* you chose), `argumentLab`
  (deterministic argument map; find the load-bearing unstated premise).
- **The Commitment Map:** envelope `commitmentOps` + a post-session extraction
  sweep write asserted positions to a per-user graph; tensions are computed
  against a curated ontology (direct conflicts + 1-hop entailments,
  conservative by contract); at most one tension surfaced per session, framed
  as a question, never a verdict. The Worldview page shows everything,
  contestable and exportable.

## Quick start

1. **Pipeline** — done for the first text: `pipeline/output/republic-jowett/`
   (Gutenberg #1497, Jowett; 10 books, 510 passages). Re-run with
   `VOYAGE_API_KEY` set to add embeddings (currently BM25-only).
2. **Backend** — `supabase db push` (migrations 0001–0004), seed catalog +
   ontology + book data (`supabase/scripts/seed_content.ts`),
   `supabase secrets set ANTHROPIC_API_KEY=…`, `supabase functions deploy session`.
3. **iOS** — `cd ios && xcodegen generate && open TheAcademy.xcodeproj`.
   Mock mode works out of the box; add `Secrets.plist` for live mode.
4. **Validate content** — `python3 pipeline/validate_content.py` (courses,
   personas, ontology, passage-ID cross-checks). All content merges must pass.

## Build order status

- **M1 — Repoint + Socratic core:** Republic ingested ✅; Vlachos + Whitmore authored ✅; elenchus session kind specified (CONTRACTS §12.1), engine wiring pending
- **M2 — Commitment Map v1:** ontology authored ✅; migration 0004 ✅; commitmentOps + tension pipeline + Worldview page pending
- **M3 — Thought-Experiment Lab + argument reconstruction:** specs authored ✅; session kinds + deterministic renderer pending
- **M4 (V1):** Lindqvist authored ahead of schedule ✅; disputations, the Dialogue, rediscovery, steelman-my-opposite pending
- **M5 (V2):** political & mind wings, great debates — not started
