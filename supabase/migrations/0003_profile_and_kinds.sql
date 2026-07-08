-- ============================================================================
-- THE SEMINAR — migration 0003: novelty addendum (CONTRACTS §10 Addendum v2,
-- §11.2 session-type registry, §11.3 reader profile). Idempotent-safe.
-- ============================================================================

-- ----------------------------------------------------------------------------
-- sessions.kind grows to the 9 kinds (§11.2)
-- (variorum / recitation / staging reserved for later migrations)
-- ----------------------------------------------------------------------------

alter table public.sessions drop constraint if exists sessions_kind_check;
alter table public.sessions add constraint sessions_kind_check check (kind in (
  'lecture', 'seminar', 'closeReading', 'officeHours', 'essay', 'quiz',
  'disputation', 'craftLab', 'coReading'
));

-- ----------------------------------------------------------------------------
-- Reader profile tables (§11.3)
-- RLS: owner may SELECT; owner may DELETE ("reset who you are as a reader");
-- writes via service role only.
-- ----------------------------------------------------------------------------

create table if not exists public.reader_profiles (
  user_id           uuid primary key references auth.users(id) on delete cascade,
  dimensions        jsonb not null default '{}'::jsonb,
  narrative_summary text  not null default '',
  updated_at        timestamptz not null default now()
);

create table if not exists public.profile_evidence (
  id         uuid primary key default gen_random_uuid(),
  user_id    uuid not null references auth.users(id) on delete cascade,
  kind       text not null check (kind in
               ('annotation', 'seminar_turn', 'essay_rubric', 'reading_telemetry', 'contest')),
  dimension  text not null,
  signal     text not null,
  weight     real not null,
  ref        jsonb,                       -- {sessionId, turnSeq, highlightId, ...}
  created_at timestamptz not null default now()
);

create index if not exists profile_evidence_user_created
  on public.profile_evidence (user_id, created_at);

create index if not exists profile_evidence_user_dimension
  on public.profile_evidence (user_id, dimension);

alter table public.reader_profiles  enable row level security;
alter table public.profile_evidence enable row level security;

drop policy if exists reader_profiles_owner_read on public.reader_profiles;
create policy reader_profiles_owner_read on public.reader_profiles
  for select to authenticated using (user_id = auth.uid());

drop policy if exists reader_profiles_owner_delete on public.reader_profiles;
create policy reader_profiles_owner_delete on public.reader_profiles
  for delete to authenticated using (user_id = auth.uid());

drop policy if exists profile_evidence_owner_read on public.profile_evidence;
create policy profile_evidence_owner_read on public.profile_evidence
  for select to authenticated using (user_id = auth.uid());

drop policy if exists profile_evidence_owner_delete on public.profile_evidence;
create policy profile_evidence_owner_delete on public.profile_evidence
  for delete to authenticated using (user_id = auth.uid());

-- No insert/update policies: writes happen through the service role only.

-- ----------------------------------------------------------------------------
-- highlights: nullable enrollment_id (marginalia archive, §11.3).
-- ON DELETE SET NULL — archived highlights must survive re-enrollment cycles
-- (past-self lookup compares created_at against the CURRENT enrollment's
-- started_at).
-- ----------------------------------------------------------------------------

alter table public.highlights
  add column if not exists enrollment_id uuid references public.enrollments(id) on delete set null;

create index if not exists highlights_user_book_ch
  on public.highlights (user_id, book_id, ch);
