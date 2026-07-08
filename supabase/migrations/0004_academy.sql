-- 0004_academy.sql — The Academy deltas (CONTRACTS §12)
-- New session kinds (elenchus, thoughtExperiment, argumentLab) and the
-- Commitment Map tables (claims ontology, commitments, tensions, snapshots).

-- ---------------------------------------------------------------------------
-- 1. Session kinds
-- ---------------------------------------------------------------------------

alter table public.sessions drop constraint if exists sessions_kind_check;
alter table public.sessions add constraint sessions_kind_check check (kind in (
  'lecture','seminar','closeReading','officeHours','essay','quiz',
  'disputation','craftLab','coReading',
  'elenchus','thoughtExperiment','argumentLab'
));

-- ---------------------------------------------------------------------------
-- 2. Claim ontology (catalog tables; seeded from content/ontology/claims.json)
-- ---------------------------------------------------------------------------

create table public.claims (
  id text primary key,                     -- e.g. 'ethics.moral-realism'
  claim text not null,
  domain text not null check (domain in
    ('ethics','epistemology','metaphysics','mind','political','aesthetics')),
  summary text not null default '',
  version int not null default 1,
  created_at timestamptz not null default now()
);

create table public.claim_edges (
  from_id text not null references public.claims(id) on delete cascade,
  to_id text not null references public.claims(id) on delete cascade,
  kind text not null check (kind in ('entails','conflicts','supports')),
  primary key (from_id, to_id, kind)
);

create index claim_edges_to_idx on public.claim_edges (to_id, kind);

-- ---------------------------------------------------------------------------
-- 3. Commitments (per-user position graph)
-- ---------------------------------------------------------------------------

create table public.commitments (
  id uuid primary key default gen_random_uuid(),
  user_id uuid not null references auth.users(id) on delete cascade,
  claim text not null,                     -- in the student's own terms
  domain text not null check (domain in
    ('ethics','epistemology','metaphysics','mind','political','aesthetics')),
  ontology_id text references public.claims(id),
  strength text not null default 'explored' check (strength in
    ('asserted','leaned','explored','abandoned')),
  affirm_count int not null default 1,
  first_asserted timestamptz not null default now(),
  last_affirmed timestamptz not null default now(),
  source_refs jsonb not null default '[]'  -- [{sessionId, turnSeq}]
);

-- one live commitment per canonical claim per user
create unique index commitments_user_ontology_uidx
  on public.commitments (user_id, ontology_id) where ontology_id is not null;
create index commitments_user_idx on public.commitments (user_id, strength);

create table public.commitment_tensions (
  id uuid primary key default gen_random_uuid(),
  user_id uuid not null references auth.users(id) on delete cascade,
  commitment_a uuid not null references public.commitments(id) on delete cascade,
  commitment_b uuid not null references public.commitments(id) on delete cascade,
  via jsonb not null default '[]',         -- the claim_edges path that produced it
  status text not null default 'open' check (status in
    ('open','raised','reconciled','dissolved')),
  raised_in uuid references public.sessions(id),
  created_at timestamptz not null default now(),
  unique (commitment_a, commitment_b)
);

create index commitment_tensions_user_idx
  on public.commitment_tensions (user_id, status);

create table public.worldview_snapshots (
  id uuid primary key default gen_random_uuid(),
  user_id uuid not null references auth.users(id) on delete cascade,
  summary text not null,
  major_positions jsonb not null default '[]',
  open_tensions jsonb not null default '[]',
  created_at timestamptz not null default now()
);

create index worldview_snapshots_user_idx
  on public.worldview_snapshots (user_id, created_at desc);

-- ---------------------------------------------------------------------------
-- 4. RLS
-- ---------------------------------------------------------------------------

-- Catalog: readable by authenticated, writes via service_role only.
alter table public.claims enable row level security;
alter table public.claim_edges enable row level security;
create policy claims_read on public.claims
  for select to authenticated using (true);
create policy claim_edges_read on public.claim_edges
  for select to authenticated using (true);

-- User-owned: owner select; owner may abandon (update strength -> 'abandoned')
-- or delete ("I don't hold that" contest); all other writes via service_role.
alter table public.commitments enable row level security;
create policy commitments_select on public.commitments
  for select to authenticated using (auth.uid() = user_id);
create policy commitments_abandon on public.commitments
  for update to authenticated
  using (auth.uid() = user_id)
  with check (auth.uid() = user_id and strength = 'abandoned');
create policy commitments_delete on public.commitments
  for delete to authenticated using (auth.uid() = user_id);

alter table public.commitment_tensions enable row level security;
create policy commitment_tensions_select on public.commitment_tensions
  for select to authenticated using (auth.uid() = user_id);
create policy commitment_tensions_delete on public.commitment_tensions
  for delete to authenticated using (auth.uid() = user_id);

alter table public.worldview_snapshots enable row level security;
create policy worldview_snapshots_select on public.worldview_snapshots
  for select to authenticated using (auth.uid() = user_id);
create policy worldview_snapshots_delete on public.worldview_snapshots
  for delete to authenticated using (auth.uid() = user_id);
