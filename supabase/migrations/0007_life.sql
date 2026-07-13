-- 0007_life.sql — E-M3 "the Life" deltas (CONTRACTS §15)
-- News-read-philosophically (weekly cached brief), the Practice Wing
-- (exercises catalog + entries ledger), and the three new session kinds.

-- ---------------------------------------------------------------------------
-- 1. Session kinds
-- ---------------------------------------------------------------------------

alter table public.sessions drop constraint if exists sessions_kind_check;
alter table public.sessions add constraint sessions_kind_check check (kind in (
  'lecture','seminar','closeReading','officeHours','essay','quiz',
  'disputation','craftLab','coReading',
  'elenchus','thoughtExperiment','argumentLab',
  'dailyQuestion','argumentClinic',
  'steelman',
  'newsRead','practice','practiceReview'
));

-- ---------------------------------------------------------------------------
-- 2. Weekly news briefs (§15.2) — one shared brief per week, cached
-- ---------------------------------------------------------------------------

create table public.news_briefs (
  week int primary key,                     -- weeksSinceEpoch(local date)
  doc jsonb not null,                       -- {headline, summary, question, domain, sourceUrls, lensPairId}
  created_at timestamptz not null default now()
);

alter table public.news_briefs enable row level security;

drop policy if exists news_briefs_read on public.news_briefs;
create policy news_briefs_read on public.news_briefs
  for select to authenticated using (true);
-- writes: service role only (the week's first newsRead start caches it).

-- Authored lens pairs (§15.2) — seeded from content/news/lenses.json; the
-- brief generator picks a pair by domain and embeds it in the brief doc.
create table public.news_lenses (
  id text primary key,                      -- e.g. 'lens-ethics-1'
  doc jsonb not null,                       -- {id, domain, a, b, splitHint}
  version int not null default 1,
  created_at timestamptz not null default now()
);

alter table public.news_lenses enable row level security;

drop policy if exists news_lenses_read on public.news_lenses;
create policy news_lenses_read on public.news_lenses
  for select to authenticated using (true);
-- writes: service role only.

-- ---------------------------------------------------------------------------
-- 3. Practice Wing (§15.3) — exercises catalog + entries ledger
-- ---------------------------------------------------------------------------

create table public.practice_exercises (
  id text primary key,                      -- 'mp-001' / 'examen' / 'nv-001'
  kind text not null check (kind in ('morning','examen','visualization')),
  doc jsonb not null,
  version int not null default 1,
  created_at timestamptz not null default now()
);

alter table public.practice_exercises enable row level security;

drop policy if exists practice_exercises_read on public.practice_exercises;
create policy practice_exercises_read on public.practice_exercises
  for select to authenticated using (true);
-- writes: service role only (seeded from content/practice/exercises.json).

create table public.practice_entries (
  id          uuid primary key default gen_random_uuid(),
  user_id     uuid not null references auth.users(id) on delete cascade,
  mode        text not null check (mode in ('morning','evening','visualization')),
  exercise_id text references public.practice_exercises(id),
  entry       text not null default '',
  reply       text not null default '',
  local_date  date not null,
  session_id  uuid references public.sessions(id) on delete set null,
  created_at  timestamptz not null default now(),
  unique (user_id, mode, local_date)
);

create index practice_entries_user_date on public.practice_entries (user_id, local_date desc);

alter table public.practice_entries enable row level security;

drop policy if exists practice_entries_owner_select on public.practice_entries;
create policy practice_entries_owner_select on public.practice_entries
  for select to authenticated using (user_id = auth.uid());
-- writes: service role only (the session function inserts on completion).
