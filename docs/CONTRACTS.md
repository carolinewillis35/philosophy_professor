# THE SEMINAR — Shared Contracts

This document is the single source of truth for every cross-component interface.
All workstreams (content, pipeline, backend, iOS) build against it. If you need
to change a contract, change it here first.

## 1. Repository layout

```
content/
  personas/<slug>.md          # persona system-prompt documents (see §6)
  personas/personas.json      # persona registry (id, name, title, portrait, blurb)
  courses/<slug>.json         # authored course definitions (see §7)
pipeline/
  ingest.py                   # EPUB/Gutenberg text -> chapters -> passages -> embeddings
  requirements.txt
  output/<bookID>/            # generated: book.json, chapters/*.json, passages.jsonl
supabase/
  migrations/0001_init.sql    # full schema (see §3)
  functions/session/index.ts  # session engine Edge Function (see §4–5)
  functions/_shared/          # anthropic client, retrieval, envelope schema, persona loader
ios/
  project.yml                 # XcodeGen spec
  TheSeminar/                 # SwiftUI app (Catalog, Reader, Session, Essays, Progress)
docs/
  CONTRACTS.md  DECISIONS.md  LICENSING.md
```

## 2. Text identity: passage IDs and spans

- **bookID**: short kebab slug, e.g. `frankenstein-1818`, `crime-and-punishment-garnett`.
- **Chapter index `ch`**: 0-based integer over the normalized reading order
  (front matter excluded; letters/chapters flattened in order).
- **Passage ID**: `"{bookID}:{ch}:{para}"` where `para` is the 0-based index of the
  first paragraph in the chunk. Example: `frankenstein-1818:4:12`.
- Passages are ~400-token chunks with 50-token overlap, **never crossing a chapter
  boundary**. Each stores `char_start`/`char_end` — offsets into the chapter's
  plain-text (the exact `text` field of the chapter JSON, see §8) — so the client
  can highlight exact spans.
- **Span** (used in course units): `{ "bookID": str, "chStart": int, "chEnd": int }`
  inclusive on both ends.

## 3. Database schema (Postgres / Supabase, migration 0001)

Extensions: `vector` (pgvector). All tables in `public`. UUID PKs default
`gen_random_uuid()` unless noted. Timestamps `created_at timestamptz default now()`.

| table | key columns |
|---|---|
| `editions` | `id text PK` (= bookID), `title`, `author`, `translator`, `source` (gutenberg\|standardebooks), `source_url`, `license text` ('public-domain-us'), `license_note`, `chapter_count int` |
| `chapters` | `book_id text FK->editions`, `ch int`, `title text`, `text text`, `word_count int`, PK `(book_id, ch)` |
| `passages` | `id text PK` (passage ID), `book_id text FK`, `ch int`, `para int`, `text text`, `char_start int`, `char_end int`, `token_count int`, `embedding vector(1024)`, `tsv tsvector` (generated, `to_tsvector('english', text)`) |
| `personas` | `id text PK` (slug), `name`, `title`, `blurb`, `doc text` (full markdown persona doc), `version int` |
| `courses` | `id text PK` (slug), `title`, `persona_id FK->personas`, `description`, `difficulty text`, `est_weeks int`, `texts jsonb` (array of bookIDs), `doc jsonb` (full course JSON, §7), `is_free boolean default false` |
| `enrollments` | `id uuid PK`, `user_id uuid` (FK auth.users), `course_id FK`, `pace text check in ('relaxed','standard','intensive')`, `current_unit int default 0`, `relationship_memory text default ''`, `started_at`, unique `(user_id, course_id)` |
| `sessions` | `id uuid PK`, `enrollment_id FK`, `unit int`, `kind text check in ('lecture','seminar','closeReading','officeHours','essay','quiz')`, `state jsonb default '{}'`, `status text check in ('active','completed') default 'active'`, `created_at`, `completed_at` |
| `turns` | `id uuid PK`, `session_id FK`, `seq int`, `role text check in ('user','professor')`, `content text`, `envelope jsonb` (professor turns only), `created_at`, unique `(session_id, seq)` |
| `essays` | `id uuid PK`, `enrollment_id FK`, `assignment_id text`, `revision int default 1`, `body text`, `feedback jsonb` (rubric scores + margin comments, §5.4), `grade text`, `submitted_at` |
| `highlights` | `id uuid PK`, `user_id uuid`, `book_id text`, `ch int`, `char_start int`, `char_end int`, `note text`, `created_at` |
| `reading_progress` | `user_id uuid`, `book_id text`, `ch int`, `char_offset int`, `updated_at`, PK `(user_id, book_id)` |

Indexes: HNSW on `passages.embedding` (`vector_cosine_ops`), GIN on `passages.tsv`.

RLS: enabled on all user-owned tables (`enrollments, sessions, turns, essays,
highlights, reading_progress`) — owner-only via `auth.uid()`. Catalog tables
(`editions, chapters, passages, personas, courses`) are readable by
`authenticated`; writes via `service_role` only.

**Hybrid retrieval RPC** (used by the Edge Function):

```sql
create function search_passages(
  query_text text,
  query_embedding vector(1024),   -- null => BM25-only
  book_ids text[],
  focus_ch_start int default null, -- current unit span bias
  focus_ch_end int default null,
  match_count int default 8
) returns table (id text, book_id text, ch int, para int, text text,
                 char_start int, char_end int, score float)
```

Scoring: reciprocal-rank fusion of vector cosine ranking and `ts_rank` BM25
ranking; rows inside the focus span get score × 1.25. If `query_embedding` is
null, BM25-only.

## 4. Session Edge Function API

`POST {SUPABASE_URL}/functions/v1/session` — auth: Supabase JWT (anon key +
user session). Body:

```json
{
  "action": "start" | "turn",
  "sessionId": "uuid",            // required for "turn"
  "enrollmentId": "uuid",         // required for "start"
  "kind": "lecture|seminar|closeReading|officeHours|essay|quiz",
  "unit": 0,                      // required for "start"
  "userText": "…",                // for "turn" (student's message / answer)
  "userAnnotations": [ {"passageId": "…", "quote": "…", "note": "…"} ],
  "essayBody": "…"                // for kind=essay submissions
}
```

Response: `text/event-stream` (SSE). Events, in order:

```
event: session      data: {"sessionId":"…","kind":"…","unit":0}      (start only)
event: say          data: {"delta":"…"}                              (repeated; streamed prose)
event: envelope     data: {<full envelope, §5>}                      (once, at end of turn)
event: error        data: {"message":"…"}
event: done         data: {}
```

Clients render `say` deltas immediately; on `envelope` they reconcile (replace
streamed text with `envelope.say`, render citations as quote panels, apply
`uiHints`).

### 4.1 Auth (client ↔ Supabase)

- Sign-in: **Sign in with Apple** → Supabase Auth token grant:
  `POST {SUPABASE_URL}/auth/v1/token?grant_type=id_token` with
  `{"provider":"apple","id_token":"<ASAuthorization identityToken>","nonce":"<raw nonce>"}`
  and `apikey: <anon key>` header. Response: `{access_token, refresh_token, expires_in, user:{id,...}}`.
- Refresh: `POST .../auth/v1/token?grant_type=refresh_token` with `{"refresh_token":"…"}`.
- Session calls send `Authorization: Bearer <access_token>` + `apikey: <anon key>`.
- Tokens stored in the iOS Keychain. Mock mode requires no auth.

### 4.2 Account deletion

`POST {SUPABASE_URL}/functions/v1/delete-account` — auth: user JWT. No body.
Deletes all rows owned by the user (enrollments cascade to sessions/turns/essays;
highlights; reading_progress; usage), then deletes the auth user via the admin
API (service role). Response `{ "deleted": true }`. Client then clears local
state and returns to signed-out.

### 4.3 Usage budget

Table `usage_daily`: `user_id uuid`, `day date`, `turns int default 0`,
`input_tokens bigint default 0`, `output_tokens bigint default 0`,
PK `(user_id, day)`. RLS owner-read; writes via service role.

The session function checks the budget before each model call (env-tunable
`DAILY_TURN_LIMIT` default 150, `DAILY_OUTPUT_TOKEN_LIMIT` default 120000):
- Soft threshold (≥80%): responses continue but the engine instruction asks for
  shorter replies (degrade gracefully — never a hard mid-seminar cutoff).
- Hard limit: return SSE `event: error` with
  `{"code":"budget_exceeded","message":"…in-voice, kind message…"}` and HTTP 200
  (stream already open) or HTTP 429 JSON if caught pre-stream. Usage recorded
  from `response.usage` after every call.

## 5. The envelope (model output contract)

Every professor turn is produced with **structured outputs**
(`output_config.format`, `json_schema`, `additionalProperties: false`).
`say` MUST be the first property in the schema (the server streams it
incrementally by scanning the partial JSON).

```json
{
  "say": "string — professor's prose. Plain text with light markdown. Never contains verbatim quotes longer than ~6 words; quotes go in citations.",
  "citations": [
    { "passageId": "frankenstein-1818:4:12", "quote": "exact substring of that passage", "why": "1-line reason shown as caption" }
  ],
  "stateOps": [
    { "op": "advanceSegment" } |
    { "op": "pushQuestion", "question": "…" } | { "op": "popQuestion" } |
    { "op": "setDepth", "depth": 1 } |
    { "op": "requireEvidence", "value": true } |
    { "op": "recordGrade", "assignmentId": "…", "grade": "…", "rubric": [ {"name":"…","score":0,"max":5,"justification":"…"} ], "marginComments": [ {"anchor":"exact sentence from essay","comment":"…"} ], "directives": ["…","…"] } |
    { "op": "writeMemory", "note": "≤ 2 sentences about this student" } |
    { "op": "completeSession" }
  ],
  "uiHints": { "showPassagePicker": false, "checkInQuestion": null, "endOfSession": false }
}
```

**Server-side validation & enforcement** (not trusted to the model):

- Every `citations[].quote` must be a verbatim substring of the retrieved
  passage with that ID (server verifies; drops the citation and appends a
  correction system note on next turn if not).
- `stateOps` are applied server-side to `sessions.state`; unknown ops rejected.
- `writeMemory` notes are appended to a per-session buffer; on
  `completeSession` the buffer is summarized (Haiku) into
  `enrollments.relationship_memory`, capped ~800 tokens.

Session state shapes (in `sessions.state`):
- lecture: `{ "segment": 0, "segments": ["…outline items…"] }`
- seminar: `{ "questionStack": ["…"], "depth": 0, "evidenceRequired": false, "vagueStrikes": 0 }`
- essay: `{ "phase": "assigned|submitted|feedback|revision", "assignmentId": "…" }`
- quiz: `{ "questions": [...], "answered": 0, "correct": 0 }`

## 6. Anthropic API usage (Edge Function)

- SDK: `npm:@anthropic-ai/sdk` (Deno npm specifier). Key from env
  `ANTHROPIC_API_KEY` (Supabase secret). Never in client.
- Models (env-overridable):
  - `MODEL_SEMINAR` default **`claude-sonnet-5`** — lecture, seminar,
    closeReading, officeHours, essay feedback.
  - `MODEL_LIGHT` default **`claude-haiku-4-5`** — quiz generation/grading,
    memory summarization.
- Sonnet 5 rules: **no** `temperature`/`top_p`/`top_k`; **no** assistant
  prefill; thinking omitted (adaptive by default) — for latency-sensitive
  turns pass `thinking: {type: "disabled"}` explicitly; use
  `output_config: { format: { type: "json_schema", schema: ENVELOPE_SCHEMA } }`.
- Always stream (`client.messages.stream`). `max_tokens: 2048` typical turn.
- Prompt assembly order (stable → volatile, for prompt caching):
  1. persona doc (system block, `cache_control: {type:"ephemeral"}`)
  2. course/unit context (system block, cache_control on last block)
  3. messages: summarized older turns → relationship memory + session state +
     retrieved passages (as a `<context>` block in the latest user turn) →
     last N (=12) raw turns → user's new input.
- Per-turn budget ≈ 6k in / 1k out. Degrade gracefully: shorter lectures, never
  hard lockouts.

## 7. Course JSON (`content/courses/<slug>.json`)

```json
{
  "id": "close-reading-bootcamp",
  "title": "Close Reading Bootcamp",
  "personaId": "voss",
  "description": "…",
  "difficulty": "introductory|intermediate|advanced",
  "estWeeks": 3,
  "texts": [ {"bookID": "…", "title": "…", "author": "…", "source": "gutenberg|standardebooks", "sourceUrl": "…", "license": "public-domain-us", "licenseNote": "…"} ],
  "units": [
    {
      "number": 1,
      "title": "…",
      "reading": [ {"bookID": "…", "chStart": 0, "chEnd": 2} ],
      "lectureOutline": ["segment 1 topic", "…"],       // 5–8 segments
      "seminarQuestionBank": ["…", "…"],                // 6–10 questions, ordered by depth
      "closeReadingPassages": ["bookID:ch:para", "…"],  // optional
      "assignments": [
        {
          "id": "crb-u1-response",
          "kind": "response|essay|closeReading|imitation",
          "prompt": "…",
          "lengthWords": 300,
          "rubric": [ {"name": "…", "weight": 0.4, "descriptors": {"A": "…", "B": "…", "C": "…"}} ]
        }
      ],
      "recapNotes": "…"
    }
  ]
}
```

## 8. Pipeline output formats (`pipeline/output/<bookID>/`)

- `book.json`: `{ "bookID", "title", "author", "translator", "source", "sourceUrl", "license", "licenseNote", "chapterCount" }`
- `chapters/<ch>.json`: `{ "bookID", "ch", "title", "text" }` — `text` is plain
  text, paragraphs separated by `\n\n`, normalized (curly quotes kept, no soft
  hyphens, no page numbers). **This exact string is the offset space** for
  `char_start`/`char_end` everywhere.
- `passages.jsonl`: one JSON object per line matching the `passages` table
  columns (embedding as float array, omitted when embeddings are skipped).
- Embeddings: **Voyage AI `voyage-3.5`, 1024 dims, cosine.** Env `VOYAGE_API_KEY`;
  if unset, pipeline writes passages without embeddings and prints a notice
  (retrieval degrades to BM25-only).
- `pipeline/ingest.py` CLI:
  `python3 ingest.py --url <gutenberg-or-SE-epub-url> --book-id <id> --title … --author … [--translator …] [--no-embed] [--seed-sql]`
  `--seed-sql` additionally emits `seed.sql` (editions/chapters/passages inserts, embeddings included) for `psql`/supabase db push.

## 9. iOS client contracts

- Config via `ios/TheSeminar/Config.swift` reading `Secrets.plist`
  (`SUPABASE_URL`, `SUPABASE_ANON_KEY`) — `Secrets.example.plist` checked in.
- Reader renders chapter JSON (§8) fetched from `chapters` table (or bundled
  fixtures in `ios/TheSeminar/Fixtures/` for offline dev). Highlights map to
  `(book_id, ch, char_start, char_end)`.
- Session UI consumes the SSE protocol in §4. Quote panels render `citations`
  with book/chapter caption and a "open in reader" affordance. Sourced quotes
  are visually distinct (quote panel) from professor paraphrase (plain prose) —
  the client MUST NOT render blockquote styling for anything not in `citations`.
- Bundle `content/courses/*.json` + `personas.json` as fixtures so the catalog
  works before the backend is deployed; live mode fetches the same shapes from
  `courses`/`personas` tables.
- Min iOS 17, SwiftUI, no third-party deps (hand-rolled SSE over URLSession).

## 10. Addendum v2 — envelope, session types, reader profile, authored specs

Everything in this section is additive; nothing above changes semantics.

### 11.1 Envelope v2

The envelope gains **optional** fields (schema still `additionalProperties:false`;
`say` remains the FIRST property and the streaming source; the four v1 fields
stay required). Old stored turns decode fine — clients treat new fields as optional.

```json
{
  "say": "…",                       // for multi-voice turns: full dialogue with speaker-label lines
                                     //   ("VOSS: …\n\nARKADY: …") so streaming still reads naturally;
                                     //   client re-renders from speakers[] on envelope arrival.
  "speakers": [                      // OPTIONAL — present only in disputation turns
    { "personaId": "voss", "say": "…", "citations": [ …same citation shape… ] }
  ],
  "citations": [...], "stateOps": [...],
  "profileOps": [                    // OPTIONAL — reader-profile evidence writes
    { "op": "evidence", "kind": "seminar_turn|annotation|essay_rubric|reading_telemetry|contest",
      "dimension": "character|form|image|structure|context|sound",
      "signal": "one-sentence observation with its receipt", "weight": 0.5 }
  ],
  "uiHints": { "showPassagePicker": false, "checkInQuestion": null,
               "endOfSession": false,
               "adjudicationRequired": false }   // NEW optional key
}
```

New `stateOps`:
- `{ "op": "recordPosition", "side": "<personaId>", "statement": "student's stated position" }` (disputation adjudication)
- `{ "op": "advancePhase" }` (generic phase step for the new multi-phase kinds)

Server-side: `profileOps` are validated (known dimensions, weight 0..1) and
persisted to `profile_evidence` by the session function; the model is limited to
**≤2 evidence ops per turn** (extras dropped). Envelope rows persisted in `turns`
carry a `"v": 2` marker added server-side (not part of the model-facing schema).

### 11.2 Session-type registry

`sessions.kind` check constraint grows to:
`('lecture','seminar','closeReading','officeHours','essay','quiz','disputation','craftLab','coReading')`
(variorum/recitation/staging reserved for later migrations). The engine refactors
per-kind logic into a declarative registry: each kind = `{ initialState(courseUnit,
spec?), instructionBlock(state, ctx), onOps(state, ops) }`.

**disputation** state: `{ "phase": "passage_presented|prof_A_reading|prof_B_counter|exchange|student_adjudicates|cross_examination|student_final_position|joint_debrief", "volley": 0, "disputeId": "…", "position": null|{side, statement} }`
Rules enforced in the instruction block: both voices every exchange turn; each
professor responds to the other's actual point (the authored crux); after
adjudication, the *rejected* side cross-examines; debrief names what each reading
sees and misses; never flatter the adjudication.

**craftLab** state: `{ "phase": "damaged_presented|elicitation|reveal|delta_seminar|repair|compare", "labId": "…" }`
The damaged text is client-rendered from the spec asset; the professor NEVER
quotes damaged text via `citations` (citations always point at the original
passages). The reveal is a client beat (uiHint `endOfSession` unaffected).

**coReading** turns are single-exchange micro-sessions: request carries
`{ "waypointId"?: "…", "position": {"ch": n, "para": n}, "trigger": "on_reach|on_dwell|on_pass_quickly|annotation", "userAnnotations": [...] }`;
response is one short interjection (≤80 words) or one `stop_and_ask` question.
Server caps generated interjections at `CO_READING_MAX_PER_CHAPTER` (default 4)
via session state; authored waypoints render client-side with no API call.

### 11.3 Reader Profile (tables + pipeline + injection)

Tables (migration 0003):

| table | columns |
|---|---|
| `reader_profiles` | `user_id uuid PK`, `dimensions jsonb` (shape below), `narrative_summary text default ''`, `updated_at timestamptz` |
| `profile_evidence` | `id uuid PK`, `user_id uuid`, `kind text check in ('annotation','seminar_turn','essay_rubric','reading_telemetry','contest')`, `dimension text`, `signal text`, `weight real`, `ref jsonb` (session/turn/highlight ids), `created_at` |

`highlights` gains nullable `enrollment_id uuid` (marginalia archive: past-self
lookup = highlights on (user, book, ch-range) with `created_at` before the
current enrollment's `started_at`).

`dimensions` jsonb shape:
```json
{ "attention": {"character": {"score":0.5,"confidence":0.2,"trend":0,"evidenceCount":0},
                 "form": …, "image": …, "structure": …, "context": …, "sound": …},
  "habits": {"quotesOpenings":…, "evidenceDensity":…, "hedging":…, "paraphraseVsQuote":…},
  "avoidances": [{"observation":"…", "evidenceCount":3}],
  "strengths": ["…"], "growthEdges": ["…"] }
```

RLS: owner may **select** `reader_profiles` and `profile_evidence`; owner may
**delete** their profile rows ("reset who you are as a reader"); writes via
service role only. Contest flow: client inserts nothing — it sends a normal
officeHours turn tagged in text; the model emits a `profileOps` evidence write
with kind `contest`.

Pipeline: on `completeSession` (same job as relationship-memory folding) the
server 1) applies exponential decay (×0.98 per day since `updated_at`) to
dimension scores, 2) folds the session's accumulated `profile_evidence` into
dimension scores (bounded 0..1, confidence grows with evidence count),
3) regenerates `narrative_summary` with MODEL_LIGHT when cumulative drift > 0.15
(~150 words, professor-register, receipts not psychology).

Injection: prompt assembly adds a **profile digest** (~200 tokens: top-2
strengths, top-2 growth edges, avoidances with receipts, narrative summary)
after relationship memory in the `<context>` block — only when `reader_profiles`
row exists AND any surfaced dimension has evidenceCount ≥ 5. Persona contract
line (server instruction, all kinds): *at most ONE profile-aware move per
session; a nudge, never a lecture about the profile.* The instruction block
tracks `state._profileMoveUsed`.

### 11.4 Authored spec schemas (course JSON additions)

Units MAY carry (all optional arrays):

```json
"disputations": [{
  "id": "crb-u2-d1", "personaA": "voss", "personaB": "calloway",
  "span": {"bookID": "dubliners", "chStart": 3, "chEnd": 3},
  "passageIds": ["dubliners:3:19"],
  "positionA": "one sentence", "positionB": "one sentence",
  "crux": "what evidence each leans on",
  "volleys": [ {"speaker": "voss", "say": "…"}, {"speaker": "calloway", "say": "…"} ]   // 2-3 authored few-shot volleys
}],
"craftLabs": [{
  "id": "fitw-u1-l1", "bookID": "frankenstein-1818",
  "span": {"ch": 7, "paraStart": 0, "paraEnd": 6},
  "transform": "excise|flatten_syntax|strip_imagery|reorder|swap_pov",
  "damagedText": "…full altered text, authored at build time, human-reviewable…",
  "pedagogicalPoint": "…", "elicitationQuestions": ["…","…"]
}],
"waypoints": [{
  "id": "fitw-u1-w1", "bookID": "frankenstein-1818", "ch": 0, "para": 3,
  "trigger": "on_reach|on_dwell|on_pass_quickly",
  "move": "interjection|stop_and_ask|silent_highlight",
  "text": "authored interjection text (interjection/silent_highlight)",
  "prompt": "authored question (stop_and_ask)"
}]
```

Authoring toolchain: `pipeline/validate_content.py` schema-validates every
course JSON (base §7 + these extensions), every persona doc's required sections,
cross-checks passageIds/spans against `pipeline/output/*/passages.jsonl`, and
verifies craft-lab damaged text differs from the original span. CI-runnable;
exits nonzero with a readable report. **All content merges must pass it.**

### 11.5 Client (iOS) additions

- Disputation UI: two professor voices as distinct bubbles (portrait chip +
  per-persona tint + typography accent); streamed text shows the labeled
  dialogue, re-rendered into per-speaker bubbles on envelope arrival; the
  adjudication beat is a designed "take the floor" input state
  (`uiHints.adjudicationRequired`).
- Profile page: attention radar (custom SwiftUI shape), strengths/edges in the
  professors' voices, avoidances with receipts, narrative summary, evidence
  timeline; "everything the professors see" transparency note; contest
  affordance (deep-links to office hours prefilled); delete/reset button
  (deletes profile rows only). Mock mode ships a fixture profile.
- Co-reading: reader emits position events (chapter, paragraph anchor, dwell)
  to a client-side controller; authored waypoints render as margin notes
  anchored to paragraphs (tappable to expand), stop_and_ask pauses into an
  inline one-exchange bubble then releases; "Reading with Prof. ___" presence
  chip; generated-interjection budget respected client-side too (≤1 per 12
  paragraphs); pass-quickly noted once at chapter break.
- Marginalia time-travel: on opening a chapter with archive highlights from a
  prior enrollment, render past-self notes in a distinct "past you" style; the
  professor may reference them (they ride into session context as annotations
  tagged `past: true`).

## 11. Guardrails (enforced in persona docs AND server)

- Professors never write essays for students, never full summaries of assigned
  reading pre-discussion ("Do the reading; then let's talk").
- Verbatim quotation only via `citations` (RAG-verified). Contemporary works
  discussable, never excerpted.
- Grading requires a non-empty student draft (`essayBody`); server rejects
  essay turns without one.
- Intensity dial: enrollment-level `pace` + persona calibration note; pushing
  on ideas, warmth toward the person.

---

# THE ACADEMY addendum (§12) — philosophy deltas

Everything below is additive to §1–11. The Seminar contracts remain the
platform; this section is binding for all Academy workstreams. App display
name: **The Academy**. iOS directory renames `TheSeminar/` → `TheAcademy/`.

## 12.1 New session kinds

`sessions.kind` check constraint grows (migration 0004) to add:
`('elenchus','thoughtExperiment','argumentLab')` — MVP.
Reserved for later migrations: `dialogue`, `rediscovery`. All existing kinds
(incl. `disputation`, `craftLab`, `coReading`) remain available to philosophy
courses unchanged.

Each new kind registers in the engine's declarative kind registry
(`initialState(courseUnit, spec?)`, `instructionBlock(state, ctx)`,
`onOps(state, ops)`).

**elenchus** state:
```json
{ "phase": "thesis|definition|counterexample|revision|reflection",
  "thesis": null, "currentDefinition": null,
  "revisions": 0, "counterexamplesSurvived": 0,
  "outcome": null, "specId": null }
```
- `outcome`: `null` while live; `"aporia"` or `"robust"` set by `declareOutcome`.
- Loop semantics: `counterexample → revision` repeats until the professor emits
  `declareOutcome`; the engine then forces `phase: "reflection"`. A session may
  NOT complete (`completeSession`) from any phase except `reflection`.
- The instruction block enforces: aporia is a *success state*; the reflection
  must name concretely what the dismantling taught (which definitions died and
  why). Cap: after 4 revisions the professor must move to an outcome.
- New stateOps (elenchus only):
  - `{ "op": "recordThesis", "thesis": "student's stated position" }`
  - `{ "op": "reviseDefinition", "definition": "current working definition" }`
  - `{ "op": "declareOutcome", "outcome": "aporia|robust" }`
  - plus generic `advancePhase`.

**thoughtExperiment** state:
```json
{ "specId": "…", "nodeId": "start", "path": [ {"nodeId":"…","choice":"…"} ],
  "pumpsApplied": [], "phase": "run|interrogation|debrief" }
```
- The client renders the authored node text and choice buttons **from the spec
  asset** (deterministic, no API call per branch). A `turn` request carries the
  choice as `userText` plus `{"nodeId": "…", "choice": "…"}` echoed by the
  server into `path` via stateOp `{ "op": "recordChoice", "nodeId": "…",
  "choice": "…" }`.
- After the authored branches exhaust (or the spec's `pumps` are spent), phase
  moves to `interrogation`: the professor interrogates *why* using the spec's
  `interrogation` questions as the authored spine. `debrief` names the
  philosophical payload and cites the canonical source passage(s).
- stateOps: `recordChoice` (above), `{ "op": "applyPump", "pumpId": "…" }`,
  `advancePhase`.

**argumentLab** state:
```json
{ "specId": "…", "phase": "mapPresented|hunt|reveal|collapse|rebuild",
  "attempts": 0, "found": false }
```
- The argument map renders **client-side from the spec** (deterministic
  renderer, §12.5); the hidden premise is omitted from the render in `hunt`.
- stateOps: `{ "op": "recordHuntResult", "found": true, "attempts": 2 }`,
  `advancePhase`.
- The professor NEVER states the hidden premise before `reveal`; in `collapse`
  mode the client greys out the removed premise and the professor asks what
  broke. Citations always point at the original source passages.

## 12.2 Envelope: `commitmentOps` (Commitment Map writes)

The envelope gains an OPTIONAL array (same pattern as `profileOps`; `say`
remains first; v1 fields unchanged):

```json
"commitmentOps": [
  { "op": "assert|lean|explore|affirm|abandon",
    "claim": "one-sentence position in the student's own terms",
    "domain": "ethics|epistemology|metaphysics|mind|political|aesthetics",
    "ontologyId": "ethics.moral-realism",   // optional; only when confidently matched
    "evidence": "short paraphrase of what the student said" }
]
```

Server-side validation: known domains; `ontologyId` (when present) must exist
in `claims`; **≤2 commitmentOps per turn** (extras dropped); ops persisted to
`commitments` by the session function (service role). Strength transitions:
`explore → lean → assert` upward only via explicit ops; `affirm` bumps
`affirm_count` and `last_affirmed`; `abandon` sets strength `abandoned`
(never deletes — the arc is the product).

**The commitment move (persona contract, all kinds):** prompt assembly injects
a *commitment digest* (~150 tokens) after the profile digest: top live
positions + at most ONE open tension chosen by the server (oldest unraised
first). Instruction line: *at most ONE commitment move per session; framed as a
question about a tension to examine, never a verdict of incoherence; abandoning
a position is progress and is said so.* Tracked via `state._commitmentMoveUsed`.
Digest only injected when the user has ≥3 non-abandoned commitments.

## 12.3 Database (migration 0004)

| table | key columns |
|---|---|
| `claims` | `id text PK` (e.g. `ethics.moral-realism`), `claim text`, `domain text check in ('ethics','epistemology','metaphysics','mind','political','aesthetics')`, `summary text`, `version int` — the authored ontology (catalog table) |
| `claim_edges` | `from_id text FK->claims`, `to_id text FK->claims`, `kind text check in ('entails','conflicts','supports')`, PK `(from_id, to_id, kind)` |
| `commitments` | `id uuid PK`, `user_id uuid`, `claim text`, `domain text` (same check), `ontology_id text FK->claims null`, `strength text check in ('asserted','leaned','explored','abandoned')`, `affirm_count int default 1`, `first_asserted timestamptz default now()`, `last_affirmed timestamptz default now()`, `source_refs jsonb default '[]'` (array of `{sessionId, turnSeq}`), unique `(user_id, ontology_id)` where ontology_id not null |
| `commitment_tensions` | `id uuid PK`, `user_id uuid`, `commitment_a uuid FK->commitments`, `commitment_b uuid FK->commitments`, `via jsonb` (the claim_edges path that produced it), `status text check in ('open','raised','reconciled','dissolved') default 'open'`, `created_at`, `raised_in uuid null` (session id) |
| `worldview_snapshots` | `id uuid PK`, `user_id uuid`, `summary text`, `major_positions jsonb`, `open_tensions jsonb`, `created_at` |

RLS: `claims`/`claim_edges` readable by `authenticated`, writes service-role
(seeded from `content/ontology/claims.json` by `seed_content.ts`).
`commitments`/`commitment_tensions`/`worldview_snapshots`: owner **select** and
owner **update of `strength` to 'abandoned'** + owner delete (contest = "I
don't hold that"); all other writes service role.

## 12.4 Commitment pipeline (post-session job)

Extends the `completeSession` job (relationship memory + profile fold):

1. **Extract:** MODEL_LIGHT pass over the session transcript with the domain
   slice of the ontology (id + claim, not summaries) in context → emits the
   same shape as `commitmentOps` for anything the professor's in-turn ops
   missed. In-turn ops take precedence on conflict.
2. **Fold:** upsert into `commitments` (match by `ontology_id`, else fuzzy by
   normalized claim text); apply strength transitions per §12.2.
3. **Recompute tensions:** for every pair of the user's non-abandoned
   commitments with `ontology_id`, flag when (a) a direct `conflicts` edge
   exists, or (b) a 1-hop entailment of one conflicts with the other
   (`A entails X, X conflicts B`). **1 hop maximum — conservative by contract.**
   New tensions insert as `open`; tensions whose side is abandoned become
   `dissolved`.
4. **Surface eligibility:** a tension may be surfaced (enter the digest) only
   when BOTH sides have `strength='asserted'` AND `affirm_count ≥ 2`.
5. **Snapshot:** when commitment drift since the last snapshot is material
   (any strength change or new/changed tension), write a `worldview_snapshot`
   (~120-word MODEL_LIGHT summary, professor-register, receipts not
   psychology).

## 12.5 Authored spec schemas (course JSON additions)

Units MAY carry (all optional; validated by `pipeline/validate_content.py`):

```json
"elenchusSpecs": [{
  "id": "wij-u1-e1",
  "openingQuestion": "What is justice?",
  "span": {"bookID": "republic-jowett", "chStart": 0, "chEnd": 0},
  "passageIds": ["republic-jowett:0:120"],
  "classicMoves": [                       // the authored spine: known definitions & their classical counterexamples
    {"definition": "returning what one owes", "counterexample": "the madman's weapon (Republic I, Cephalus)"},
    {"definition": "helping friends and harming enemies", "counterexample": "misjudged friends; harming makes men worse (Polemarchus)"}
  ],
  "relatedClaims": ["political.justice-advantage-of-stronger"],
  "reflectionPrompt": "…"
}],
"thoughtExperiments": [{
  "id": "el-u2-t1", "title": "The Ring of Gyges",
  "setup": "…150-300 words, authored, second person…",
  "philosophicalPayload": "…what this experiment is FOR…",
  "sourceRefs": ["republic-jowett:1:14"],
  "nodes": [
    {"id": "start", "text": "…", "options": [{"label": "…", "next": "n2"}, {"label": "…", "next": "n3"}]},
    {"id": "n2", "text": "…", "options": [...]},
    {"id": "n3", "text": "…", "terminal": true}
  ],
  "pumps": [                              // intuition pumps: authored variations that stress the chosen principle
    {"id": "p1", "afterNode": "n2", "variation": "…same case, numbers/framing changed…", "testsPrinciple": "…"}
  ],
  "interrogation": ["…ordered questions for the professor…"],
  "relatedClaims": ["ethics.psychological-egoism"]
}],
"argumentLabs": [{
  "id": "haw-u1-a1", "title": "…",
  "source": {"bookID": "republic-jowett", "passageIds": ["republic-jowett:0:88"]},
  "conclusion": {"id": "c", "text": "…"},
  "premises": [
    {"id": "p1", "text": "…", "stated": true, "supports": "c"},
    {"id": "p2", "text": "…", "stated": false, "supports": "c"}   // the hidden premise
  ],
  "mode": "hunt|collapse",                 // hunt: find the unstated premise; collapse: a premise is removed
  "hiddenPremiseId": "p2",                 // hunt mode
  "removedPremiseId": null,                // collapse mode
  "pedagogicalPoint": "…",
  "elicitationQuestions": ["…", "…"],
  "relatedClaims": []
}]
```

`relatedClaims` entries MUST be ids present in `content/ontology/claims.json`
(validator cross-checks). `passageIds`/spans cross-check against
`pipeline/output/*/passages.jsonl` as in §11.4.

## 12.6 Ontology asset (`content/ontology/claims.json`)

```json
{ "version": 1,
  "claims": [
    { "id": "ethics.moral-realism",
      "claim": "There are moral facts that hold independently of what anyone believes or feels.",
      "domain": "ethics",
      "summary": "1-3 sentences: the position, its classical home, why it matters.",
      "entails": ["epistemology.moral-knowledge-possible"],
      "conflictsWith": ["ethics.moral-anti-realism"],
      "supports": [] } ] }
```

- **ID convention:** `<domain>.<kebab-slug>`. Domains fixed to the six above.
- Edges are **conservative**: an `entails` edge means *classically
  uncontroversial* commitment (if contested by a major tradition, use
  `supports` or omit). `conflictsWith` means genuine logical/near-logical
  tension, not mere disagreement of school.
- Every id referenced by an edge must exist. `conflictsWith` is symmetric
  (validator normalizes); `entails`/`supports` are directed.
- Starter set: ≥60 claims, ≥10 per domain, including at minimum these ids
  (course content may reference them): `political.justice-advantage-of-stronger`,
  `political.justice-intrinsically-good`, `ethics.psychological-egoism`,
  `ethics.consequentialism`, `ethics.deontology`, `ethics.moral-realism`,
  `ethics.moral-anti-realism`, `ethics.virtue-ethics`,
  `epistemology.skepticism-external-world`, `epistemology.empiricism`,
  `epistemology.rationalism`, `metaphysics.libertarian-free-will`,
  `metaphysics.hard-determinism`, `metaphysics.compatibilism`,
  `mind.physicalism`, `mind.dualism`, `mind.machine-thought-possible`.

## 12.7 iOS additions

- **Rebrand:** display name "The Academy", target/dir `TheAcademy`,
  bundle id suffix `.academy`. XcodeGen `project.yml` updated; everything else
  (SSE client, reader, quote panels, session chrome) reused as-is.
- **Elenchus UI:** phase indicator (thesis → definition → counterexample →
  revision → reflection) rendered from session state; the aporia outcome gets
  a designed beat (not an error state — "you now know what you don't know").
- **Thought-Experiment Lab:** authored nodes render as cards with choice
  buttons (no streaming); pumps render as a "the dial turns" variation card;
  interrogation/debrief fall back to the normal chat surface.
- **Argument map renderer:** deterministic SwiftUI layout — premise nodes in
  layers, inference edges as connectors, conclusion at the bottom; hidden
  premise renders as a dashed empty slot in hunt mode; removed premise greys
  out in collapse mode. Reused by argumentLab and (V1) dialogue.
- **Worldview page:** replaces the lit Profile page concept for Academy —
  positions grouped by domain (strength-weighted), open tensions drawn as
  glowing connectors between the two positions, a timeline of strength
  changes ("you moved from X to Y"), contest affordance (owner
  abandon/delete per §12.3 RLS + office-hours deep link), export
  (markdown share sheet), full-transparency note. Mock fixture ships.
- Fixtures: `republic-jowett` chapters + `personas.json` + Academy course
  JSONs bundled; lit fixtures removed.

## 12.8 Guardrails (Academy-specific, enforced in persona docs AND server)

- **The app has no philosophy.** On contested questions professors present
  strongest cases from their tradition and return judgment to the student;
  server never injects a "correct" position; the faculty's documented
  disagreements are the anti-sycophancy mechanism.
- **Tension framing:** questions to examine, never verdicts of incoherence.
  The word "inconsistent" aimed at the *student* (vs. at a pair of claims) is
  out of contract.
- **Aporia ends in reflection, always.** `completeSession` from a
  non-reflection elenchus phase is rejected server-side.
- **No invented citations:** unchanged from §11; entailment claims ground in
  the ontology, not model improvisation.

---

# ENGAGEMENT addendum (§13) — E-M1: the Daily Question + the Argument Clinic

Additive to §1–12. Scope source: `docs/SCOPE-ADDENDUM.md` (tiers E1–E3);
this section binds E-M1 only. Later E-tiers get their own sections.

## 13.1 Standalone sessions (migration 0005)

E-M1 sessions are not course-bound. Migration 0005:

- `sessions.enrollment_id` becomes **nullable**; new columns
  `user_id uuid null references auth.users`,
  `persona_id text null references personas`.
- Integrity check `sessions_binding_check`:
  `(enrollment_id is not null) or (user_id is not null and persona_id is not null)`.
- `sessions_kind_check` grows: + `'dailyQuestion', 'argumentClinic'`.
- RLS `sessions_owner` gains the standalone arm: owner =
  enrollment owner **or** `sessions.user_id = auth.uid()`. Same for `turns`
  (which checks via session).
- Standalone sessions: `unit = 0`; no course doc; **relationship memory and
  reader-profile digest are skipped at MVP**; the **commitment digest is still
  injected** (same §12.2 rules — it is the whole point of the daily loop).

## 13.2 `dailyQuestion` — the sixty-second ritual

**Content asset** `content/daily/questions.json` (validated, seeded to catalog
table `daily_questions` by `seed_content.ts`):

```json
{ "version": 1,
  "questions": [{
    "id": "dq-001",
    "question": "Is a perfect copy of you — memories, habits, loves — you?",
    "domain": "mind",
    "personaId": "whitmore",
    "options": [
      {"id": "yes", "label": "Yes — that's all I am", "ontologyId": "mind.psychological-continuity"},
      {"id": "no",  "label": "No — a copy is a twin, not me", "ontologyId": null},
      {"id": "unsure", "label": "I genuinely can't tell", "ontologyId": null}
    ],
    "relatedClaims": ["mind.physicalism"]
  }]
}
```

- 2–4 options; `ontologyId` (nullable) must exist in the ontology; `personaId`
  must exist in `personas.json`; ids unique; bank ≥ 14 questions.
- **Selection is deterministic, no cron:** questions sorted by `id`; today's
  question = `bank[daysSinceEpoch(localDate) % bank.length]`, where
  `localDate` is the client's `YYYY-MM-DD`. Client and server compute the
  same index; this also lets the client schedule the local notification
  offline — and the notification text **is the question** (never "come back").
- **Table `daily_answers`:** `user_id`, `question_id`, `question_date date`,
  `option_id`, `sentence text`, `session_id uuid`, unique
  `(user_id, question_date)`. RLS: owner select; writes service role.
  Streaks are **derived client-side** from `daily_answers` (rolling ratio);
  no server streak state.
- **Flow — one round trip.** The client collects tap + one sentence FIRST,
  then starts the session: `{kind: "dailyQuestion", questionId, optionId,
  localDate, userText: sentence}`. The server: validates the option, creates
  the standalone session (persona from the question), inserts the
  `daily_answers` row, **deterministically writes the commitment** from the
  tapped option (below), and the professor replies ONCE.
- **Deterministic commitment write:** if the tapped option carries an
  `ontologyId`, the server synthesizes a `lean` op (claim text from the
  ontology) and runs it through the §12.2 fold — a one-tap NEVER yields
  `asserted` by itself. The model may additionally emit a normal
  `commitmentOps` upgrade (`assert`) ONLY when the typed sentence itself
  asserts the position.
- **The reply contract (kind instruction):** ≤120 words; ONE move (sharpen
  the position, name its tradition and its best enemy, or complicate it with
  the cost it carries); it may END on a question only as food-for-thought —
  nothing that demands an answer; then `completeSession` +
  `uiHints.endOfSession` in the SAME turn. State
  `{questionId, optionId, replied}`; no retrieval; `citations` empty.

## 13.3 `argumentClinic` — "Bring me an argument"

A standalone session; the user picks the professor (default `whitmore`). The
user brings a live argument — a disagreement, a take, a decision — and the
professor extracts its structure into the SAME map shape the deterministic
renderer already consumes (§12.5 argument spec: `conclusion {id,text}`,
`premises [{id, text, stated, supports}]`), built incrementally via stateOps.

**State:**
```json
{ "phase": "intake|excavation|map|crux|handback",
  "userArgument": { "conclusion": null, "premises": [] },
  "cruxes": [ {"id": "p2", "kind": "fact|value|definition"} ],
  "mapVersion": 0 }
```

**Phases:** `intake` (what's the actual claim at issue? ≤2 clarifying
questions, then `setConclusion`) → `excavation` (premises pulled out one at a
time, in the arguer's own terms, each confirmed with the user; unstated
load-bearers get `stated:false`) → `map` (the whole map on the table; the
professor walks it once) → `crux` (where do the parties REALLY diverge —
`markCrux` classifies each crux as fact / value / definition; discovering the
disagreement was about something else entirely is the payload) → `handback`
(name what would settle it — empirical work, a definition, or a genuinely
evaluative choice — and hand judgment back; then `completeSession`).

**New stateOps (clinic only), added to the envelope schema:**
- `{ "op": "setConclusion", "text": "…" }` — sets `userArgument.conclusion`
  (id `"c"`); bumps `mapVersion`.
- `{ "op": "addPremise", "id": "p1", "text": "…", "stated": true, "supports": "c" }`
  — `supports` must be `"c"` or an existing premise id; cap 8 premises;
  bumps `mapVersion`.
- `{ "op": "revisePremise", "id": "p1", "text": "…" }`
- `{ "op": "markCrux", "id": "p2", "kind": "fact|value|definition" }` — id
  must exist in the map.
- plus generic `advancePhase` (intake→excavation→map→crux→handback).

`canComplete`: `phase == "handback"` only. The client re-renders the map from
state on every `mapVersion` bump (deterministic renderer reused; unstated
premises render dashed; cruxes get a fact/value/definition badge).
Commitment ops: allowed for positions the USER asserts about the issue —
never inferred from the interlocutor's side of the argument. No retrieval at
MVP; `citations` empty; canonical frameworks may be named, never excerpted.

## 13.4 Guardrails (E-M1, enforced in kind instructions AND server)

- **The clinic dissects arguments, never referees relationships and never
  gives life advice.** No verdicts on who is right; "I can map the reasoning;
  the judgment stays yours" is the register. If the material turns
  therapy-adjacent (grief, self-harm, abuse), the professor names the limit
  plainly and points at the human step — mapping stops being the move.
- **The ritual stays small.** dailyQuestion replies never exceed one short
  paragraph and never demand a reply; the session auto-completes in one turn.
- **One-tap is not a conviction.** Deterministic daily writes enter at
  `lean`, ratchet rules unchanged; `assert` requires the student's own words.
- **Aggregates (later tiers) are shown only after answering, as description
  not pressure** — recorded here so E-M2 inherits it.

## 13.5 iOS additions (E-M1)

- **Home surface:** Daily Question card at top (question + option buttons +
  one-line "why" field); answered state shows the professor's reply and a
  "added to your worldview" affordance linking to the Worldview page. Bank
  bundled as fixture; local-date rotation computed on device.
- **Clinic entry:** "Bring me an argument" from Home with professor picker;
  session surface = chat + the live argument map growing above it
  (`ArgumentMapView` reused; re-render on `mapVersion` change).
- Demo launch args: `-demo-daily`, `-demo-clinic`.

## 13.6 Validation

`pipeline/validate_content.py` gains a daily-bank pass: unique ids; 2–4
options each; every non-null `ontologyId` and every `relatedClaims` entry
exists in `claims.json`; `personaId` exists in `personas.json`; bank ≥ 14;
question text nonempty.

---

# ENGAGEMENT addendum (§14) — E-M2: the Ladder

Additive to §1–13. Scope source: `docs/SCOPE-ADDENDUM.md` §2–§3. Three
systems: the Worldview page as the progress object (the changelog of your
mind), weekly thought-experiment drops with crowd comparison, and the
steelman ladder.

## 14.1 Commitment events ledger (migration 0006)

The changelog needs history; folds currently overwrite in place. New table
`commitment_events` (service-role writes only; owner select):

| column | notes |
|---|---|
| `id uuid PK`, `user_id uuid`, `commitment_id uuid FK->commitments on delete cascade` | |
| `event text check in ('explored','leaned','asserted','affirmed','abandoned')` | the strength verb after the fold |
| `prior_strength text null` | null on first insert; set on every strength CHANGE |
| `evidence text default ''` | the op's evidence line — "the argument that moved you" |
| `session_id uuid null`, `created_at timestamptz` | |

`persistCommitmentOps` writes one event per fold: on row insert, `event` =
the initial strength verb with `prior_strength` null; on strength change,
the new verb with the old strength; on affirm-only folds, `'affirmed'`
(UI filters affirm noise; the table keeps it). The §12.4 sweep writes events
through the same path.

**Derived, not stored:** the changelog = events with `prior_strength` set or
`event='abandoned'`, joined to `commitments` for claim text. The proudest
stat — "you've changed your mind N times this year, each under pressure of
argument" — is the count of `abandoned` events in the trailing 365 days.
Owner contest (§12.3 delete) cascades the events away with the row: the
changelog records the examined life, not the bookkeeping.

## 14.2 Tension resolution

New stateOp (all kinds, valid at most once per session):

```json
{ "op": "markTensionReconciled", "resolution": "one sentence: how the student reconciled it" }
```

Server-side: applies ONLY to the tension this session's digest raised (the
server stamps `state._raisedTensionId` when the digest carries one; the op is
dropped otherwise). Sets that tension `status='reconciled'`,
`resolution` (new text column), `resolved_at` (new column). Emitted when the
student has ACTUALLY reconciled the two positions in conversation — restated
one, subordinated one, or drawn a distinction that dissolves the conflict —
never as a reward for mere acknowledgment. Resolving a tension is a
celebrated event on the Worldview page.

## 14.3 Weekly thought-experiment drops

- **Content asset** `content/drops/drops.json`: `{ version, drops: [{ id:
  "drop-001", personaId, teaser, experiment: <ThoughtExperimentSpec, §12.5
  shape> }] }`. Validator: same node-graph well-formedness as course
  thoughtExperiments; `personaId` in registry; `relatedClaims` in ontology;
  ≥ 4 drops. Seeded to catalog table `drops` (id, doc, version; read
  authenticated, writes service role).
- **Selection deterministic, no cron (A16 pattern):** drops sorted by id;
  this week's = `drops[weeksSinceEpoch(localDate) % drops.length]` where
  `weeksSinceEpoch = floor(daysSinceEpoch / 7)`.
- **Session:** the drop RUNS the existing `thoughtExperiment` kind as a
  STANDALONE session (§13.1): start request `{kind: "thoughtExperiment",
  dropId, localDate}`; the server loads the spec from `drops`, persona from
  the drop, stamps `state.dropId`. Client node rendering per §12.7 unchanged.
- **Table `drop_responses`:** `id`, `user_id`, `drop_id FK->drops`,
  `week int` (weeksSinceEpoch), `path jsonb`, `first_choice text`,
  `session_id`, `created_at`, unique `(user_id, drop_id, week)` (re-runs in a
  later cycle are re-encounters, E-M3). Written by the server on the drop
  session's completeSession, from the kind state's `path`. RLS: owner select;
  writes service role.
- **Crowd aggregate:** RPC `drop_aggregate(p_drop_id text)` (SECURITY
  DEFINER): returns `{ total, byFirstChoice: {label: count} }` over ALL
  users' responses. Hard gates: the caller must have a `drop_responses` row
  for that drop (aggregates exist only AFTER you answer — §13.4), and the
  RPC returns `{total, byFirstChoice: null}` when `total < 10` (small-crowd
  suppression). Shown as description, never pressure: "68% plugged in; you
  didn't; here's the divide."

## 14.4 The steelman ladder

New session kind `steelman` (migration 0006 adds it to the kind check),
STANDALONE (§13.1). The user picks one of their own live commitments; the
exercise is to state the best case AGAINST it — so well its holders would
sign it.

Start request extras: `{ kind: "steelman", targetClaim: "...",
targetOntologyId?: "...", personaId? }` (default persona `whitmore`;
`targetOntologyId` must exist in `claims` when present).

**State:**
```json
{ "phase": "brief|attempt|probe|verdict|debrief",
  "targetClaim": "…", "targetOntologyId": null,
  "probeRounds": 0, "level": null }
```

**Phases:** `brief` (frame the target and the bar; the opposing view is not a
caricature of it) → `attempt` (the student states the steelman; the professor
listens whole) → `probe` (≤2 rounds: where the steelman is still a strawman —
missing strongest premise, uncharitable framing, weak version of the
opponent's best move; the student revises) → `verdict` (grade via the new
stateOp, below) → `debrief` (what the strongest opposing case teaches about
the student's own position; commitmentOps allowed — a steelman that converts
is a live `abandon`/`assert` moment; then completeSession). `canComplete`:
`phase == "debrief"` only. `MAX_PROBE_ROUNDS = 2`, then the professor MUST
move to verdict.

**New stateOp (steelman only):**
```json
{ "op": "recordSteelmanScore", "level": 3,
  "justification": "one sentence naming what earned or capped the level" }
```
Levels (the rubric, enforced in the kind instruction): **1 strawman** (the
opponent wouldn't recognize it), **2 sketch** (recognizable but missing its
best premise), **3 competent** (a holder would nod), **4 signable** (a holder
would sign it as their own statement). Graded against the ARGUMENT the
student produced, never the student; level 4 is rare and said so.

**Table `steelman_scores`:** `id`, `user_id`, `target_ontology_id text null
FK->claims`, `target_claim text`, `level int check between 1 and 4`,
`justification text`, `session_id`, `created_at`. Written by the server when
the op lands. RLS: owner select; writes service role. The ladder = max level
per target + attempt counts, computed client-side.

## 14.5 iOS additions (E-M2)

- **Worldview page becomes the progress object:** (a) stats header — "You've
  changed your mind N times this year — each under pressure of argument";
  (b) TERRITORY: the six domains as a grid, examined (has live commitments)
  vs. untouched, untouched ones carrying an authored provocation line ("you
  have no epistemology yet; everything you believe rests on a theory of
  knowledge you haven't met"); (c) THE CHANGELOG: timeline of
  `commitment_events` (affirm noise filtered), abandonments rendered as
  achievements with the evidence line; (d) tensions split OPEN (glowing,
  §12.7) and RESOLVED (celebrated, with resolution + date).
- **Drop card** on the home surface ("This week: The Experience Machine" +
  teaser + share affordance, text-only share sheet); runs the standalone
  thought-experiment session; on completion the CROWD screen (first-choice
  distribution vs. yours), only ever reachable after answering; suppressed
  small crowds show "too few thinkers yet — check back".
- **Steelman entry:** on each live commitment row in Worldview ("Steelman
  the other side") → steelman session; a LADDER screen showing per-claim max
  level (the four named ranks) and attempts.
- Fixtures: drops bank + a mock crowd aggregate + mock commitment events;
  mock clinic pattern (§13.5) extended to a scripted steelman and drop run.
- Demo launch args: `-demo-drop`, `-demo-steelman`, `-demo-changelog`.

## 14.6 Guardrails (E-M2)

- **Aggregates are description, never pressure:** shown only after the
  user's own answer is recorded; phrased as where people landed, never as
  what one should think; never attached to live public/moral questions
  (that's §15/E-M3's problem, recorded here); suppressed below 10 responses.
- **The changelog celebrates abandonment.** Copy frames changed minds as the
  point of the practice; no loss-aversion framing, no "streak" of stability.
- **Steelman grades the argument, not the person.** Level 1 is named
  "strawman", not "failure"; the justification names what would raise the
  level.
- **Reconciliation is earned.** `markTensionReconciled` only for tensions
  actually worked through in-session, bound server-side to the one raised
  tension; abandoning a side still dissolves (never "reconciles") a tension.

## 14.7 Validation

`validate_content.py` gains a drops pass (§14.3). The daily-bank pass (§13.6)
and all §12 passes unchanged.

