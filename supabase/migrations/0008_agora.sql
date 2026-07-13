-- 0008_agora.sql — E-M4 "the Agora" deltas (CONTRACTS §16)
-- The monthly Symposium (catalog + responses + movement RPC) and
-- dinner-party packs.

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
  'newsRead','practice','practiceReview',
  'symposium'
));

-- ---------------------------------------------------------------------------
-- 2. Symposium catalog + responses (§16.1–§16.3)
-- ---------------------------------------------------------------------------

create table public.symposia (
  id text primary key,                      -- e.g. 'sym-001'
  doc jsonb not null,
  version int not null default 1,
  created_at timestamptz not null default now()
);

alter table public.symposia enable row level security;

drop policy if exists symposia_read on public.symposia;
create policy symposia_read on public.symposia
  for select to authenticated using (true);
-- writes: service role only.

create table public.symposium_responses (
  id              uuid primary key default gen_random_uuid(),
  user_id         uuid not null references auth.users(id) on delete cascade,
  symposium_id    text not null references public.symposia(id),
  month           int not null,             -- monthsSinceEpoch(local date)
  before_position text not null check (before_position in ('a','b','undecided')),
  after_position  text check (after_position in ('a','b')),
  completed       boolean not null default false,
  session_id      uuid references public.sessions(id) on delete set null,
  created_at      timestamptz not null default now(),
  unique (user_id, symposium_id, month)
);

create index symposium_responses_sym on public.symposium_responses (symposium_id);

alter table public.symposium_responses enable row level security;

drop policy if exists symposium_responses_owner_select on public.symposium_responses;
create policy symposium_responses_owner_select on public.symposium_responses
  for select to authenticated using (user_id = auth.uid());
-- writes: service role only.

-- Movement aggregate (§16.3 / A33): callable only by users with a COMPLETED
-- response; distributions + moved count only; suppressed below 10 completed.
create or replace function public.symposium_movement(p_symposium_id text)
returns jsonb
language plpgsql
security definer
set search_path = public
as $$
declare
  v_total int;
  v_moved int;
  v_before jsonb;
  v_after jsonb;
begin
  if not exists (
    select 1 from public.symposium_responses
    where symposium_id = p_symposium_id
      and user_id = auth.uid()
      and completed
  ) then
    raise exception 'complete the symposium before viewing the movement';
  end if;

  select count(*) into v_total
  from public.symposium_responses
  where symposium_id = p_symposium_id and completed;

  if v_total < 10 then
    return jsonb_build_object(
      'total', v_total, 'moved', null, 'byBefore', null, 'byAfter', null
    );
  end if;

  select count(*) into v_moved
  from public.symposium_responses
  where symposium_id = p_symposium_id and completed
    and after_position is not null
    and after_position <> before_position;

  select jsonb_object_agg(before_position, n) into v_before
  from (
    select before_position, count(*) as n
    from public.symposium_responses
    where symposium_id = p_symposium_id and completed
    group by before_position
  ) t;

  select jsonb_object_agg(after_position, n) into v_after
  from (
    select after_position, count(*) as n
    from public.symposium_responses
    where symposium_id = p_symposium_id and completed
      and after_position is not null
    group by after_position
  ) t;

  return jsonb_build_object(
    'total', v_total,
    'moved', v_moved,
    'byBefore', coalesce(v_before, '{}'::jsonb),
    'byAfter', coalesce(v_after, '{}'::jsonb)
  );
end;
$$;

revoke all on function public.symposium_movement(text) from public;
grant execute on function public.symposium_movement(text) to authenticated;

-- ---------------------------------------------------------------------------
-- 3. Dinner-party packs (§16.4) — catalog only, untracked by design
-- ---------------------------------------------------------------------------

create table public.packs (
  id text primary key,                      -- e.g. 'pack-001'
  doc jsonb not null,
  version int not null default 1,
  created_at timestamptz not null default now()
);

alter table public.packs enable row level security;

drop policy if exists packs_read on public.packs;
create policy packs_read on public.packs
  for select to authenticated using (true);
-- writes: service role only. NO response/usage tables — §16.6.
