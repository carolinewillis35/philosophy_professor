-- 0006_ladder.sql — E-M2 "the Ladder" deltas (CONTRACTS §14)
-- Commitment events ledger, tension resolution, weekly drops + crowd
-- aggregate, and the steelman kind + scores.

-- ---------------------------------------------------------------------------
-- 1. Commitment events ledger (§14.1) — the changelog of your mind
-- ---------------------------------------------------------------------------

create table public.commitment_events (
  id            uuid primary key default gen_random_uuid(),
  user_id       uuid not null references auth.users(id) on delete cascade,
  commitment_id uuid not null references public.commitments(id) on delete cascade,
  event text not null check (event in
    ('explored','leaned','asserted','affirmed','abandoned')),
  prior_strength text,                      -- null on first insert
  evidence      text not null default '',
  session_id    uuid references public.sessions(id) on delete set null,
  created_at    timestamptz not null default now()
);

create index commitment_events_user on public.commitment_events (user_id, created_at desc);

alter table public.commitment_events enable row level security;

drop policy if exists commitment_events_owner_select on public.commitment_events;
create policy commitment_events_owner_select on public.commitment_events
  for select to authenticated using (user_id = auth.uid());
-- writes: service role only (the fold writes; contest deletes cascade).

-- ---------------------------------------------------------------------------
-- 2. Tension resolution (§14.2)
-- ---------------------------------------------------------------------------

alter table public.commitment_tensions
  add column if not exists resolution text not null default '';
alter table public.commitment_tensions
  add column if not exists resolved_at timestamptz;

-- ---------------------------------------------------------------------------
-- 3. Weekly drops (§14.3) — catalog + response ledger + crowd aggregate
-- ---------------------------------------------------------------------------

create table public.drops (
  id text primary key,                      -- e.g. 'drop-001'
  doc jsonb not null,                       -- {id, personaId, teaser, experiment}
  version int not null default 1,
  created_at timestamptz not null default now()
);

alter table public.drops enable row level security;

drop policy if exists drops_read on public.drops;
create policy drops_read on public.drops
  for select to authenticated using (true);
-- writes: service role only.

create table public.drop_responses (
  id           uuid primary key default gen_random_uuid(),
  user_id      uuid not null references auth.users(id) on delete cascade,
  drop_id      text not null references public.drops(id),
  week         int not null,                -- weeksSinceEpoch(local date)
  path         jsonb not null default '[]',
  first_choice text not null default '',
  session_id   uuid references public.sessions(id) on delete set null,
  created_at   timestamptz not null default now(),
  unique (user_id, drop_id, week)
);

create index drop_responses_drop on public.drop_responses (drop_id);

alter table public.drop_responses enable row level security;

drop policy if exists drop_responses_owner_select on public.drop_responses;
create policy drop_responses_owner_select on public.drop_responses
  for select to authenticated using (user_id = auth.uid());
-- writes: service role only (the session function inserts on completion).

-- Crowd aggregate (§14.3 / A22): callable only by users who have answered;
-- first-choice distribution only; suppressed below 10 responses.
create or replace function public.drop_aggregate(p_drop_id text)
returns jsonb
language plpgsql
security definer
set search_path = public
as $$
declare
  v_total int;
  v_by jsonb;
begin
  if not exists (
    select 1 from public.drop_responses
    where drop_id = p_drop_id and user_id = auth.uid()
  ) then
    raise exception 'answer the drop before viewing the crowd';
  end if;

  select count(*) into v_total
  from public.drop_responses where drop_id = p_drop_id;

  if v_total < 10 then
    return jsonb_build_object('total', v_total, 'byFirstChoice', null);
  end if;

  select jsonb_object_agg(first_choice, n) into v_by
  from (
    select first_choice, count(*) as n
    from public.drop_responses
    where drop_id = p_drop_id and first_choice <> ''
    group by first_choice
  ) t;

  return jsonb_build_object('total', v_total, 'byFirstChoice', coalesce(v_by, '{}'::jsonb));
end;
$$;

revoke all on function public.drop_aggregate(text) from public;
grant execute on function public.drop_aggregate(text) to authenticated;

-- ---------------------------------------------------------------------------
-- 4. Steelman (§14.4) — kind + scores
-- ---------------------------------------------------------------------------

alter table public.sessions drop constraint if exists sessions_kind_check;
alter table public.sessions add constraint sessions_kind_check check (kind in (
  'lecture','seminar','closeReading','officeHours','essay','quiz',
  'disputation','craftLab','coReading',
  'elenchus','thoughtExperiment','argumentLab',
  'dailyQuestion','argumentClinic',
  'steelman'
));

create table public.steelman_scores (
  id                 uuid primary key default gen_random_uuid(),
  user_id            uuid not null references auth.users(id) on delete cascade,
  target_ontology_id text references public.claims(id),
  target_claim       text not null,
  level              int not null check (level between 1 and 4),
  justification      text not null default '',
  session_id         uuid references public.sessions(id) on delete set null,
  created_at         timestamptz not null default now()
);

create index steelman_scores_user on public.steelman_scores (user_id, created_at desc);

alter table public.steelman_scores enable row level security;

drop policy if exists steelman_scores_owner_select on public.steelman_scores;
create policy steelman_scores_owner_select on public.steelman_scores
  for select to authenticated using (user_id = auth.uid());
-- writes: service role only (the session function inserts when the op lands).
