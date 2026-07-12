# The Seminar — Supabase backend

Postgres schema (pgvector + hybrid retrieval RPC) and the `session` Edge
Function (Deno) that implements the session engine from
[`docs/CONTRACTS.md`](../docs/CONTRACTS.md) §3–§6.

```
supabase/
  migrations/0001_init.sql               # full schema, RLS, HNSW/GIN indexes, search_passages RPC
  migrations/0002_usage_and_deletion.sql # usage_daily + record_usage RPC (§4.3), FK cascade hygiene (§4.2)
  migrations/0003_profile_and_kinds.sql  # 9 session kinds, reader_profiles + profile_evidence,
                                         # highlights.enrollment_id (§10 Addendum v2)
  migrations/0004_academy.sql            # Academy kinds + Commitment Map tables (§12)
  migrations/0005_engagement.sql         # standalone sessions + daily_questions/daily_answers (§13)
  migrations/0006_ladder.sql             # commitment_events, tension resolution, drops + crowd
                                         # aggregate RPC, steelman kind + scores (§14)
  functions/
    _shared/                   # anthropic client, envelope schema (v2), say streamer,
                               # retrieval, prompt assembly, per-kind registry (engine.ts),
                               # usage budget (budget.ts), reader profile (profile.ts)
    session/index.ts           # the session engine Edge Function (SSE)
    session/deno.json
    delete-account/index.ts    # account deletion Edge Function (§4.2)
  scripts/seed_content.ts      # seed personas/courses/ontology/daily bank from content/ (service role)
```

## Prerequisites

- [Supabase CLI](https://supabase.com/docs/guides/cli) (`brew install supabase/tap/supabase`)
- [Deno](https://deno.com) 2.x (`brew install deno`) — for local checks and the seed script
- A Supabase project (note the project ref, anon key, and service-role key)

## 1. Link the project & push the schema

```sh
# from the repo root (this repo already contains supabase/ — init is only
# needed if you want the CLI's local config.toml scaffolding)
supabase init          # safe to skip if you deploy straight to a linked project
supabase link --project-ref <PROJECT_REF>

# apply migrations/ (0001_init … 0006_ladder)
supabase db push
```

All migrations are idempotent-safe (`create ... if not exists`, `drop policy
if exists` + recreate, `create or replace function`, guarded FK/constraint
re-creation), so re-running is fine. If you deployed before `0002`/`0003`
existed, a plain `supabase db push` picks them up — `0003` is required for the
disputation / craftLab / coReading kinds and the reader profile.

## 2. Set secrets

```sh
supabase secrets set \
  ANTHROPIC_API_KEY=sk-ant-... \
  VOYAGE_API_KEY=pa-...        # optional — omit for BM25-only retrieval

# optional model overrides (defaults: claude-sonnet-5 / claude-haiku-4-5)
supabase secrets set MODEL_SEMINAR=claude-sonnet-5 MODEL_LIGHT=claude-haiku-4-5

# optional usage-budget knobs (CONTRACTS §4.3; defaults shown)
supabase secrets set DAILY_TURN_LIMIT=150 DAILY_OUTPUT_TOKEN_LIMIT=120000

# optional co-reading knob (CONTRACTS §11.2): generated interjections per
# chapter — over the cap the function returns a silent no-op envelope with no
# model call and no budget burn (default shown)
supabase secrets set CO_READING_MAX_PER_CHAPTER=4
```

`SUPABASE_URL`, `SUPABASE_ANON_KEY`, and `SUPABASE_SERVICE_ROLE_KEY` are
injected into Edge Functions automatically — do not set them yourself.

## 3. Deploy the Edge Function

```sh
supabase functions deploy session
supabase functions deploy delete-account
```

The function verifies the caller's Supabase JWT itself (`auth.getUser()`), so
the default gateway JWT verification can stay enabled. To iterate locally:

```sh
supabase functions serve session --env-file supabase/.env.local
```

with a `supabase/.env.local` containing `ANTHROPIC_API_KEY=...` (and
optionally `VOYAGE_API_KEY=...`).

## 4. Seed data

### 4a. Book text (editions / chapters / passages)

The ingestion pipeline emits a `seed.sql` per book (CONTRACTS §8):

```sh
cd pipeline
python3 ingest.py --url <gutenberg-epub-url> --book-id frankenstein-1818 \
  --title "Frankenstein" --author "Mary Shelley" --seed-sql

# then load it (connection string from the Supabase dashboard):
psql "$SUPABASE_DB_URL" --set ON_ERROR_STOP=1 -f output/frankenstein-1818/seed.sql
```

### 4b. Personas & courses (from `content/`)

```sh
# from the repo root
SUPABASE_URL=https://<PROJECT_REF>.supabase.co \
SUPABASE_SERVICE_ROLE_KEY=<SERVICE_ROLE_KEY> \
deno run --allow-env --allow-read --allow-net supabase/scripts/seed_content.ts
```

The script upserts every persona in `content/personas/personas.json` (doc text
from `content/personas/<id>.md`) and every course JSON in `content/courses/`.

### 4c. An enrollment to test with

Create a user (Dashboard → Authentication, or `supabase auth` in your app),
then insert an enrollment as that user or via SQL editor:

```sql
insert into enrollments (user_id, course_id, pace)
values ('<AUTH_USER_UUID>', 'frankenstein-in-two-weeks', 'standard')
returning id;
```

## 5. Exercise the API (curl + SSE)

Get a user JWT (e.g. sign in with password grant):

```sh
export SUPABASE_URL=https://<PROJECT_REF>.supabase.co
export ANON_KEY=<ANON_KEY>

export JWT=$(curl -s "$SUPABASE_URL/auth/v1/token?grant_type=password" \
  -H "apikey: $ANON_KEY" -H "Content-Type: application/json" \
  -d '{"email":"student@example.com","password":"..."}' | jq -r .access_token)
```

Start a session (streams SSE — note `-N` to disable curl buffering):

```sh
curl -N "$SUPABASE_URL/functions/v1/session" \
  -H "Authorization: Bearer $JWT" \
  -H "apikey: $ANON_KEY" \
  -H "Content-Type: application/json" \
  -d '{"action":"start","enrollmentId":"<ENROLLMENT_UUID>","kind":"seminar","unit":0}'
```

You should see, in order:

```
event: session
data: {"sessionId":"<uuid>","kind":"seminar","unit":0}

event: say
data: {"delta":"Welcome. Let's start with"}
...
event: envelope
data: {"say":"...","citations":[...],"stateOps":[...],"uiHints":{...}}

event: done
data: {}
```

Take a turn (use the `sessionId` from the `session` event):

```sh
curl -N "$SUPABASE_URL/functions/v1/session" \
  -H "Authorization: Bearer $JWT" \
  -H "apikey: $ANON_KEY" \
  -H "Content-Type: application/json" \
  -d '{
    "action": "turn",
    "sessionId": "<SESSION_UUID>",
    "userText": "I think the creature is the real narrator of the novel.",
    "userAnnotations": [
      {"passageId": "frankenstein-1818:4:12", "quote": "It was on a dreary night", "note": "tone shift here"}
    ]
  }'
```

Essay sessions require the draft in `essayBody`:

```sh
curl -N "$SUPABASE_URL/functions/v1/session" \
  -H "Authorization: Bearer $JWT" -H "apikey: $ANON_KEY" \
  -H "Content-Type: application/json" \
  -d '{"action":"turn","sessionId":"<SESSION_UUID>","userText":"Here is my draft.","essayBody":"<the full essay text>"}'
```

### New kinds (CONTRACTS §11.2)

`kind` accepts `disputation`, `craftLab`, and `coReading` in addition to the
original six (migration 0003 required). Start a disputation — `specId` picks
one of the unit's authored `disputations[]` (omit for the first):

```sh
curl -N "$SUPABASE_URL/functions/v1/session" \
  -H "Authorization: Bearer $JWT" -H "apikey: $ANON_KEY" \
  -H "Content-Type: application/json" \
  -d '{"action":"start","enrollmentId":"<ENROLLMENT_UUID>","kind":"disputation","unit":1,"specId":"crb-u2-d1"}'
```

Disputation envelopes carry the labeled multi-voice dialogue in `say`
("VOSS: …\n\nCALLOWAY: …") mirrored per-persona in `speakers[]`; the
adjudication beat arrives as `uiHints.adjudicationRequired: true`. Take the
adjudication turn like any other turn:

```sh
curl -N "$SUPABASE_URL/functions/v1/session" \
  -H "Authorization: Bearer $JWT" -H "apikey: $ANON_KEY" \
  -H "Content-Type: application/json" \
  -d '{"action":"turn","sessionId":"<SESSION_UUID>","userText":"I side with Voss: the paralysis is in the syntax itself, not the plot."}'
```

`coReading` turns are trigger-driven micro-exchanges and may omit `userText`:

```sh
curl -N "$SUPABASE_URL/functions/v1/session" \
  -H "Authorization: Bearer $JWT" -H "apikey: $ANON_KEY" \
  -H "Content-Type: application/json" \
  -d '{"action":"turn","sessionId":"<SESSION_UUID>","position":{"ch":2,"para":14},"trigger":"on_dwell","userAnnotations":[{"passageId":"frankenstein-1818:2:12","quote":"the moon gazed on my midnight labours"}]}'
```

Over `CO_READING_MAX_PER_CHAPTER` generated interjections in one chapter, the
function answers with a silent no-op envelope (empty `say`) — no model call,
no budget burn.

Delete the signed-in user's account and all their data (CONTRACTS §4.2):

```sh
curl -X POST "$SUPABASE_URL/functions/v1/delete-account" \
  -H "Authorization: Bearer $JWT" -H "apikey: $ANON_KEY"
# -> {"deleted":true}
```

### Usage budget (CONTRACTS §4.3)

Every `session` request (start counts as a turn too) does a single
upsert-read of today's `usage_daily` row before any model call:

- **Hard limit** (`DAILY_TURN_LIMIT` turns, default 150, or
  `DAILY_OUTPUT_TOKEN_LIMIT` output tokens, default 120000): the request is
  refused — HTTP `429` JSON `{"code":"budget_exceeded","message":"…"}`
  pre-stream, or SSE `event: error` with the same payload if the stream is
  already open. The message is warm, short, and shown verbatim in the app.
- **Soft threshold** (≥80% of either limit): the engine instruction block asks
  the professor for tighter, shorter replies — graceful degradation, never a
  mid-seminar cutoff.
- After the request, one `record_usage` upsert adds `turns + 1` and the summed
  `usage.input_tokens` / `output_tokens` from every model call made
  (professor turn, quiz generation/grading, turn & memory summaries).

## Local verification

```sh
deno check supabase/functions/session/index.ts \
           supabase/functions/delete-account/index.ts \
           supabase/functions/_shared/*.ts
deno test  supabase/functions/_shared/sayStream_test.ts
```

## Notes / conventions

- **No `config.toml` is checked in.** `supabase init` generates one locally if
  you want `supabase functions serve` / local dev; deployment only needs
  `supabase link` + the commands above. The `session` function relies on
  gateway JWT verification (the default) *plus* its own `auth.getUser()` check
  and enrollment-ownership authorization.
- **Retrieval fallback:** without `VOYAGE_API_KEY` the function passes a null
  embedding to `search_passages`, which degrades to BM25-only (DECISIONS #4).
- **Models:** `MODEL_SEMINAR` (default `claude-sonnet-5`) for professor turns —
  streamed, structured-output envelope, `thinking: {type:"disabled"}`, no
  sampling params, no prefill. `MODEL_LIGHT` (default `claude-haiku-4-5`) for
  quiz generation/grading, turn summarization, and relationship-memory
  summarization.
- **State bookkeeping:** fields in `sessions.state` prefixed with `_`
  (`_summary`, `_summaryUpto`, `_memoryBuffer`, `_corrections`,
  `_latestRevision`) are server-internal and never shown to the model as
  session state (the prompt filters them; corrections are delivered through a
  dedicated `<serverCorrections>` block once, then cleared).
