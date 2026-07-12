-- 0005_engagement.sql — E-M1 engagement deltas (CONTRACTS §13)
-- Standalone sessions (dailyQuestion, argumentClinic) + the daily-question
-- catalog and answer ledger.

-- ---------------------------------------------------------------------------
-- 1. Standalone sessions (§13.1): not every session hangs off an enrollment.
-- ---------------------------------------------------------------------------

alter table public.sessions alter column enrollment_id drop not null;
alter table public.sessions add column if not exists user_id uuid references auth.users(id) on delete cascade;
alter table public.sessions add column if not exists persona_id text references public.personas(id);

alter table public.sessions drop constraint if exists sessions_binding_check;
alter table public.sessions add constraint sessions_binding_check check (
  enrollment_id is not null
  or (user_id is not null and persona_id is not null)
);

alter table public.sessions drop constraint if exists sessions_kind_check;
alter table public.sessions add constraint sessions_kind_check check (kind in (
  'lecture','seminar','closeReading','officeHours','essay','quiz',
  'disputation','craftLab','coReading',
  'elenchus','thoughtExperiment','argumentLab',
  'dailyQuestion','argumentClinic'
));

create index if not exists sessions_user on public.sessions (user_id)
  where user_id is not null;

-- RLS: owner = enrollment owner OR standalone owner.
drop policy if exists sessions_owner on public.sessions;
create policy sessions_owner on public.sessions
  for all to authenticated
  using (
    user_id = auth.uid()
    or exists (
      select 1 from public.enrollments e
      where e.id = enrollment_id and e.user_id = auth.uid()
    )
  )
  with check (
    user_id = auth.uid()
    or exists (
      select 1 from public.enrollments e
      where e.id = enrollment_id and e.user_id = auth.uid()
    )
  );

-- Turns: owner via session -> (enrollment | standalone user).
drop policy if exists turns_owner on public.turns;
create policy turns_owner on public.turns
  for all to authenticated
  using (exists (
    select 1
    from public.sessions s
    left join public.enrollments e on e.id = s.enrollment_id
    where s.id = session_id
      and (s.user_id = auth.uid() or e.user_id = auth.uid())
  ))
  with check (exists (
    select 1
    from public.sessions s
    left join public.enrollments e on e.id = s.enrollment_id
    where s.id = session_id
      and (s.user_id = auth.uid() or e.user_id = auth.uid())
  ));

-- ---------------------------------------------------------------------------
-- 2. Daily-question catalog (§13.2) — seeded from content/daily/questions.json
-- ---------------------------------------------------------------------------

create table public.daily_questions (
  id text primary key,                     -- e.g. 'dq-001'
  doc jsonb not null,                      -- the full authored question object
  version int not null default 1,
  created_at timestamptz not null default now()
);

alter table public.daily_questions enable row level security;

drop policy if exists daily_questions_read on public.daily_questions;
create policy daily_questions_read on public.daily_questions
  for select to authenticated using (true);
-- writes: service role only (no policy).

-- ---------------------------------------------------------------------------
-- 3. Daily-answer ledger (§13.2) — one answer per user per local date;
--    streaks are derived client-side from this table.
-- ---------------------------------------------------------------------------

create table public.daily_answers (
  id            uuid primary key default gen_random_uuid(),
  user_id       uuid not null references auth.users(id) on delete cascade,
  question_id   text not null references public.daily_questions(id),
  question_date date not null,             -- the client's local YYYY-MM-DD
  option_id     text not null,
  sentence      text not null default '',
  session_id    uuid references public.sessions(id) on delete set null,
  created_at    timestamptz not null default now(),
  unique (user_id, question_date)
);

create index daily_answers_user_date on public.daily_answers (user_id, question_date desc);

alter table public.daily_answers enable row level security;

drop policy if exists daily_answers_owner_select on public.daily_answers;
create policy daily_answers_owner_select on public.daily_answers
  for select to authenticated using (user_id = auth.uid());
-- writes: service role only (the session function inserts).
