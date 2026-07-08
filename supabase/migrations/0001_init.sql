-- ============================================================================
-- THE SEMINAR — migration 0001: full schema per docs/CONTRACTS.md §3
-- Idempotent-safe where reasonable (extensions / tables / indexes / policies).
-- ============================================================================

create extension if not exists vector;
create extension if not exists pgcrypto; -- gen_random_uuid()

-- ----------------------------------------------------------------------------
-- Catalog tables (readable by authenticated; writes via service_role only)
-- ----------------------------------------------------------------------------

create table if not exists public.editions (
  id            text primary key,                 -- = bookID (CONTRACTS §2)
  title         text not null,
  author        text,
  translator    text,
  source        text check (source in ('gutenberg', 'standardebooks')),
  source_url    text,
  license       text not null default 'public-domain-us',
  license_note  text,
  chapter_count int,
  created_at    timestamptz not null default now()
);

create table if not exists public.chapters (
  book_id    text not null references public.editions(id) on delete cascade,
  ch         int  not null,
  title      text,
  text       text not null,
  word_count int,
  primary key (book_id, ch)
);

create table if not exists public.passages (
  id          text primary key,                   -- "{bookID}:{ch}:{para}"
  book_id     text not null references public.editions(id) on delete cascade,
  ch          int  not null,
  para        int  not null,
  text        text not null,
  char_start  int  not null,
  char_end    int  not null,
  token_count int,
  embedding   vector(1024),                       -- Voyage voyage-3.5, cosine
  tsv         tsvector generated always as (to_tsvector('english', text)) stored
);

create table if not exists public.personas (
  id      text primary key,                       -- slug
  name    text not null,
  title   text,
  blurb   text,
  doc     text not null,                          -- full markdown persona doc
  version int  not null default 1
);

create table if not exists public.courses (
  id          text primary key,                   -- slug
  title       text not null,
  persona_id  text not null references public.personas(id),
  description text,
  difficulty  text,
  est_weeks   int,
  texts       jsonb not null default '[]'::jsonb, -- array of bookIDs
  doc         jsonb not null,                     -- full course JSON (CONTRACTS §7)
  is_free     boolean not null default false
);

-- ----------------------------------------------------------------------------
-- User-owned tables (RLS owner-only via auth.uid())
-- ----------------------------------------------------------------------------

create table if not exists public.enrollments (
  id                  uuid primary key default gen_random_uuid(),
  user_id             uuid not null references auth.users(id) on delete cascade,
  course_id           text not null references public.courses(id),
  pace                text not null default 'standard'
                      check (pace in ('relaxed', 'standard', 'intensive')),
  current_unit        int  not null default 0,
  relationship_memory text not null default '',
  started_at          timestamptz not null default now(),
  unique (user_id, course_id)
);

create table if not exists public.sessions (
  id            uuid primary key default gen_random_uuid(),
  enrollment_id uuid not null references public.enrollments(id) on delete cascade,
  unit          int  not null,
  kind          text not null check (kind in
                  ('lecture', 'seminar', 'closeReading', 'officeHours', 'essay', 'quiz')),
  state         jsonb not null default '{}'::jsonb,
  status        text not null default 'active' check (status in ('active', 'completed')),
  created_at    timestamptz not null default now(),
  completed_at  timestamptz
);

create table if not exists public.turns (
  id         uuid primary key default gen_random_uuid(),
  session_id uuid not null references public.sessions(id) on delete cascade,
  seq        int  not null,
  role       text not null check (role in ('user', 'professor')),
  content    text not null,
  envelope   jsonb,                               -- professor turns only
  created_at timestamptz not null default now(),
  unique (session_id, seq)
);

create table if not exists public.essays (
  id            uuid primary key default gen_random_uuid(),
  enrollment_id uuid not null references public.enrollments(id) on delete cascade,
  assignment_id text not null,
  revision      int  not null default 1,
  body          text not null,
  feedback      jsonb,                            -- rubric scores + margin comments (§5.4)
  grade         text,
  submitted_at  timestamptz not null default now()
);

create table if not exists public.highlights (
  id         uuid primary key default gen_random_uuid(),
  user_id    uuid not null references auth.users(id) on delete cascade,
  book_id    text not null references public.editions(id),
  ch         int  not null,
  char_start int  not null,
  char_end   int  not null,
  note       text,
  created_at timestamptz not null default now()
);

create table if not exists public.reading_progress (
  user_id     uuid not null references auth.users(id) on delete cascade,
  book_id     text not null references public.editions(id),
  ch          int  not null,
  char_offset int  not null default 0,
  updated_at  timestamptz not null default now(),
  primary key (user_id, book_id)
);

-- ----------------------------------------------------------------------------
-- Indexes (CONTRACTS §3: HNSW on embedding, GIN on tsv)
-- ----------------------------------------------------------------------------

create index if not exists passages_embedding_hnsw
  on public.passages using hnsw (embedding vector_cosine_ops);

create index if not exists passages_tsv_gin
  on public.passages using gin (tsv);

create index if not exists passages_book_ch
  on public.passages (book_id, ch);

create index if not exists sessions_enrollment
  on public.sessions (enrollment_id);

create index if not exists essays_enrollment_assignment
  on public.essays (enrollment_id, assignment_id);

-- ----------------------------------------------------------------------------
-- Row Level Security
-- Catalog tables: authenticated read; writes only via service_role (bypasses RLS).
-- User tables: owner-only via auth.uid().
-- ----------------------------------------------------------------------------

alter table public.editions         enable row level security;
alter table public.chapters         enable row level security;
alter table public.passages         enable row level security;
alter table public.personas         enable row level security;
alter table public.courses          enable row level security;
alter table public.enrollments      enable row level security;
alter table public.sessions         enable row level security;
alter table public.turns            enable row level security;
alter table public.essays           enable row level security;
alter table public.highlights       enable row level security;
alter table public.reading_progress enable row level security;

-- Catalog: read-only for authenticated users
drop policy if exists editions_read on public.editions;
create policy editions_read on public.editions
  for select to authenticated using (true);

drop policy if exists chapters_read on public.chapters;
create policy chapters_read on public.chapters
  for select to authenticated using (true);

drop policy if exists passages_read on public.passages;
create policy passages_read on public.passages
  for select to authenticated using (true);

drop policy if exists personas_read on public.personas;
create policy personas_read on public.personas
  for select to authenticated using (true);

drop policy if exists courses_read on public.courses;
create policy courses_read on public.courses
  for select to authenticated using (true);

-- Enrollments: owner-only
drop policy if exists enrollments_owner on public.enrollments;
create policy enrollments_owner on public.enrollments
  for all to authenticated
  using (user_id = auth.uid())
  with check (user_id = auth.uid());

-- Sessions: owner via enrollment
drop policy if exists sessions_owner on public.sessions;
create policy sessions_owner on public.sessions
  for all to authenticated
  using (exists (
    select 1 from public.enrollments e
    where e.id = enrollment_id and e.user_id = auth.uid()
  ))
  with check (exists (
    select 1 from public.enrollments e
    where e.id = enrollment_id and e.user_id = auth.uid()
  ));

-- Turns: owner via session -> enrollment
drop policy if exists turns_owner on public.turns;
create policy turns_owner on public.turns
  for all to authenticated
  using (exists (
    select 1
    from public.sessions s
    join public.enrollments e on e.id = s.enrollment_id
    where s.id = session_id and e.user_id = auth.uid()
  ))
  with check (exists (
    select 1
    from public.sessions s
    join public.enrollments e on e.id = s.enrollment_id
    where s.id = session_id and e.user_id = auth.uid()
  ));

-- Essays: owner via enrollment
drop policy if exists essays_owner on public.essays;
create policy essays_owner on public.essays
  for all to authenticated
  using (exists (
    select 1 from public.enrollments e
    where e.id = enrollment_id and e.user_id = auth.uid()
  ))
  with check (exists (
    select 1 from public.enrollments e
    where e.id = enrollment_id and e.user_id = auth.uid()
  ));

-- Highlights: owner-only
drop policy if exists highlights_owner on public.highlights;
create policy highlights_owner on public.highlights
  for all to authenticated
  using (user_id = auth.uid())
  with check (user_id = auth.uid());

-- Reading progress: owner-only
drop policy if exists reading_progress_owner on public.reading_progress;
create policy reading_progress_owner on public.reading_progress
  for all to authenticated
  using (user_id = auth.uid())
  with check (user_id = auth.uid());

-- ----------------------------------------------------------------------------
-- Hybrid retrieval RPC (CONTRACTS §3)
--
-- Reciprocal-rank fusion (k = 60) of:
--   * vector cosine ranking (pgvector <=> on embedding), and
--   * BM25-style ts_rank ranking on the generated tsvector.
-- Rows inside the focus span get score × 1.25.
-- query_embedding = null  =>  BM25-only fallback.
-- ----------------------------------------------------------------------------

create or replace function public.search_passages(
  query_text      text,
  query_embedding vector(1024),
  book_ids        text[],
  focus_ch_start  int default null,
  focus_ch_end    int default null,
  match_count     int default 8
) returns table (
  id         text,
  book_id    text,
  ch         int,
  para       int,
  text       text,
  char_start int,
  char_end   int,
  score      float
)
language sql
stable
as $$
  with vec as (
    select p.id as pid,
           row_number() over (order by p.embedding <=> query_embedding) as rnk
    from public.passages p
    where query_embedding is not null
      and p.embedding is not null
      and p.book_id = any (book_ids)
    order by p.embedding <=> query_embedding
    limit 50
  ),
  kw as (
    select p.id as pid,
           row_number() over (order by ts_rank(p.tsv, plainto_tsquery('english', query_text)) desc) as rnk
    from public.passages p
    where p.book_id = any (book_ids)
      and p.tsv @@ plainto_tsquery('english', query_text)
    order by ts_rank(p.tsv, plainto_tsquery('english', query_text)) desc
    limit 50
  ),
  fused as (
    select coalesce(vec.pid, kw.pid) as pid,
           coalesce(1.0 / (60 + vec.rnk), 0)  -- RRF, k = 60
         + coalesce(1.0 / (60 + kw.rnk), 0) as rrf
    from vec
    full outer join kw on kw.pid = vec.pid
  )
  select p.id,
         p.book_id,
         p.ch,
         p.para,
         p.text,
         p.char_start,
         p.char_end,
         (f.rrf * case
                    when focus_ch_start is not null
                     and focus_ch_end   is not null
                     and p.ch between focus_ch_start and focus_ch_end
                    then 1.25
                    else 1.0
                  end)::float as score
  from fused f
  join public.passages p on p.id = f.pid
  order by score desc
  limit match_count;
$$;

grant execute on function public.search_passages(text, vector, text[], int, int, int)
  to authenticated, service_role;
