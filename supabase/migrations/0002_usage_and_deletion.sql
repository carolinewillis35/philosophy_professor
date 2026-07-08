-- ============================================================================
-- THE SEMINAR — migration 0002: usage budget (§4.3) + clean account deletion
-- (§4.2). Idempotent-safe.
-- ============================================================================

-- ----------------------------------------------------------------------------
-- usage_daily (CONTRACTS §4.3)
-- PK (user_id, day). RLS: owner can select; writes via service role only.
-- ----------------------------------------------------------------------------

create table if not exists public.usage_daily (
  user_id       uuid   not null references auth.users(id) on delete cascade,
  day           date   not null default current_date,
  turns         int    not null default 0,
  input_tokens  bigint not null default 0,
  output_tokens bigint not null default 0,
  primary key (user_id, day)
);

alter table public.usage_daily enable row level security;

drop policy if exists usage_daily_owner_read on public.usage_daily;
create policy usage_daily_owner_read on public.usage_daily
  for select to authenticated using (user_id = auth.uid());
-- No insert/update/delete policies: writes happen through the service role
-- (which bypasses RLS) only.

-- ----------------------------------------------------------------------------
-- record_usage RPC — single upsert-with-increments that RETURNS the updated
-- row, so the session function's budget check costs exactly one round trip
-- (call with zero deltas for a pure upsert-read).
-- Service-role only.
-- ----------------------------------------------------------------------------

create or replace function public.record_usage(
  p_user_id       uuid,
  p_turns         int    default 0,
  p_input_tokens  bigint default 0,
  p_output_tokens bigint default 0
) returns public.usage_daily
language sql
volatile
as $$
  insert into public.usage_daily as u (user_id, day, turns, input_tokens, output_tokens)
  values (p_user_id, current_date, p_turns, p_input_tokens, p_output_tokens)
  on conflict (user_id, day) do update
    set turns         = u.turns         + excluded.turns,
        input_tokens  = u.input_tokens  + excluded.input_tokens,
        output_tokens = u.output_tokens + excluded.output_tokens
  returning *;
$$;

revoke execute on function public.record_usage(uuid, int, bigint, bigint)
  from public, anon, authenticated;
grant execute on function public.record_usage(uuid, int, bigint, bigint)
  to service_role;

-- ----------------------------------------------------------------------------
-- Deletion hygiene: assert ON DELETE CASCADE on every FK in the user-data
-- chain, so deleting an enrollment removes its sessions/turns/essays, and
-- deleting the auth user removes everything user-owned.
--
-- 0001 as shipped in this repo already declares these cascades; this block is
-- defensive for databases provisioned from an earlier draft of 0001. Each FK
-- is dropped and re-created with cascade only when its current delete action
-- is not already CASCADE (confdeltype <> 'c').
-- ----------------------------------------------------------------------------

do $$
declare
  fk record;
begin
  for fk in
    select *
    from (values
      ('public.enrollments',      'enrollments_user_id_fkey',           'user_id',       'auth.users(id)'),
      ('public.sessions',         'sessions_enrollment_id_fkey',        'enrollment_id', 'public.enrollments(id)'),
      ('public.turns',            'turns_session_id_fkey',              'session_id',    'public.sessions(id)'),
      ('public.essays',           'essays_enrollment_id_fkey',          'enrollment_id', 'public.enrollments(id)'),
      ('public.highlights',       'highlights_user_id_fkey',            'user_id',       'auth.users(id)'),
      ('public.reading_progress', 'reading_progress_user_id_fkey',      'user_id',       'auth.users(id)'),
      ('public.usage_daily',      'usage_daily_user_id_fkey',           'user_id',       'auth.users(id)')
    ) as t(tbl, conname, col, ref)
  loop
    if exists (
      select 1
      from pg_constraint c
      where c.conname = fk.conname
        and c.conrelid = fk.tbl::regclass
        and c.contype = 'f'
        and c.confdeltype <> 'c'
    ) then
      execute format('alter table %s drop constraint %I', fk.tbl, fk.conname);
      execute format(
        'alter table %s add constraint %I foreign key (%I) references %s on delete cascade',
        fk.tbl, fk.conname, fk.col, fk.ref
      );
    end if;
  end loop;
end $$;
