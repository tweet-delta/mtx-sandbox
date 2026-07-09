-- ============================================================================
-- MTX Route Checklist — Phase 1 schema (accounts + saving a visit to the cloud)
-- ============================================================================
-- HOW TO RUN: Supabase dashboard → SQL Editor → New query → paste this whole
-- file → Run. It is safe to re-run (uses "if not exists" / "on conflict").
--
-- Everything lives in the `public` schema. Row-Level Security (RLS) is ON for
-- every table, so the DATABASE ITSELF decides who may read or change each row —
-- we never rely on the app screen to hide data.
-- ============================================================================


-- ----------------------------------------------------------------------------
-- 1. profiles — one row per logged-in person, carrying their role.
--    Linked 1:1 to Supabase's built-in auth.users table.
-- ----------------------------------------------------------------------------
create table if not exists public.profiles (
  id         uuid primary key references auth.users (id) on delete cascade,
  full_name  text not null default '',
  role       text not null default 'tech' check (role in ('tech', 'supervisor')),
  created_at timestamptz not null default now()
);

-- When someone signs up, auto-create their profile (as a 'tech' by default).
-- A supervisor promotes people to 'supervisor' afterward.
create or replace function public.handle_new_user()
returns trigger
language plpgsql
security definer set search_path = public
as $$
begin
  insert into public.profiles (id, full_name)
  values (new.id, coalesce(new.raw_user_meta_data ->> 'full_name', ''));
  return new;
end;
$$;

drop trigger if exists on_auth_user_created on auth.users;
create trigger on_auth_user_created
  after insert on auth.users
  for each row execute function public.handle_new_user();

-- Helper: the caller's role, read WITHOUT tripping RLS (security definer).
-- Policies below call this so a supervisor can see everything.
create or replace function public.current_user_role()
returns text
language sql
stable
security definer set search_path = public
as $$
  select role from public.profiles where id = auth.uid();
$$;

-- Stop a signed-in tech from promoting themselves to supervisor. Admin actions
-- from the dashboard (no auth.uid()) are trusted and bypass this guard.
create or replace function public.guard_profile_role()
returns trigger
language plpgsql
security definer set search_path = public
as $$
begin
  if new.role is distinct from old.role
     and auth.uid() is not null
     and public.current_user_role() is distinct from 'supervisor' then
    raise exception 'Only a supervisor can change a role';
  end if;
  return new;
end;
$$;

drop trigger if exists guard_profile_role on public.profiles;
create trigger guard_profile_role
  before update on public.profiles
  for each row execute function public.guard_profile_role();


-- ----------------------------------------------------------------------------
-- 2. houses — the roster (moving out of house-data.js and into the database).
--    equipment/notes/info mirror the shapes already used in house-data.js.
-- ----------------------------------------------------------------------------
create table if not exists public.houses (
  id         uuid primary key default gen_random_uuid(),
  name       text not null unique,
  equipment  jsonb not null default '{}'::jsonb,
  notes      jsonb not null default '{}'::jsonb,
  info       jsonb not null default '[]'::jsonb,
  active     boolean not null default true,
  created_at timestamptz not null default now()
);


-- ----------------------------------------------------------------------------
-- 3. visits — one row per house visit (the "header": who, which house, when).
-- ----------------------------------------------------------------------------
create table if not exists public.visits (
  id           uuid primary key default gen_random_uuid(),
  house_id     uuid not null references public.houses (id),
  tech_id      uuid not null references public.profiles (id) default auth.uid(),
  visit_date   date not null default current_date,
  status       text not null default 'in_progress' check (status in ('in_progress', 'completed')),
  counts       jsonb not null default '{}'::jsonb,   -- alarm counts
  survey       jsonb not null default '{}'::jsonb,   -- end-of-visit survey answers
  started_at   timestamptz not null default now(),
  completed_at timestamptz,
  created_at   timestamptz not null default now()
);
create index if not exists visits_house_idx on public.visits (house_id);
create index if not exists visits_tech_idx  on public.visits (tech_id);


-- ----------------------------------------------------------------------------
-- 4. visit_items — one row per answered checklist item, keyed by the STABLE
--    item key (e.g. 'rk-sharpen-knives'). Photos (Phase 2) will attach here.
-- ----------------------------------------------------------------------------
create table if not exists public.visit_items (
  id        uuid primary key default gen_random_uuid(),
  visit_id  uuid not null references public.visits (id) on delete cascade,
  item_key  text not null,
  done      boolean,                                  -- action items (checkbox)
  answer    text check (answer in ('yes', 'no')),     -- yes/no questions
  note      text,
  unique (visit_id, item_key)
);


-- ----------------------------------------------------------------------------
-- 5. Row-Level Security — turn it on, then define who can touch which rows.
-- ----------------------------------------------------------------------------
alter table public.profiles    enable row level security;
alter table public.houses      enable row level security;
alter table public.visits      enable row level security;
alter table public.visit_items enable row level security;

-- profiles: read your own; supervisors read everyone.
drop policy if exists profiles_select on public.profiles;
create policy profiles_select on public.profiles
  for select to authenticated
  using (id = auth.uid() or public.current_user_role() = 'supervisor');

-- profiles: edit your own row (the role trigger blocks self-promotion).
drop policy if exists profiles_update on public.profiles;
create policy profiles_update on public.profiles
  for update to authenticated
  using (id = auth.uid() or public.current_user_role() = 'supervisor')
  with check (id = auth.uid() or public.current_user_role() = 'supervisor');

-- houses: any signed-in user reads; only supervisors change.
drop policy if exists houses_select on public.houses;
create policy houses_select on public.houses
  for select to authenticated using (true);

drop policy if exists houses_write on public.houses;
create policy houses_write on public.houses
  for all to authenticated
  using (public.current_user_role() = 'supervisor')
  with check (public.current_user_role() = 'supervisor');

-- visits: a tech reads/edits their OWN visits; supervisors see all.
drop policy if exists visits_select on public.visits;
create policy visits_select on public.visits
  for select to authenticated
  using (tech_id = auth.uid() or public.current_user_role() = 'supervisor');

drop policy if exists visits_insert on public.visits;
create policy visits_insert on public.visits
  for insert to authenticated
  with check (tech_id = auth.uid());

drop policy if exists visits_update on public.visits;
create policy visits_update on public.visits
  for update to authenticated
  using (tech_id = auth.uid() or public.current_user_role() = 'supervisor')
  with check (tech_id = auth.uid() or public.current_user_role() = 'supervisor');

drop policy if exists visits_delete on public.visits;
create policy visits_delete on public.visits
  for delete to authenticated
  using (public.current_user_role() = 'supervisor');

-- visit_items: allowed only if you're allowed on the PARENT visit.
drop policy if exists visit_items_all on public.visit_items;
create policy visit_items_all on public.visit_items
  for all to authenticated
  using (exists (
    select 1 from public.visits v
    where v.id = visit_items.visit_id
      and (v.tech_id = auth.uid() or public.current_user_role() = 'supervisor')
  ))
  with check (exists (
    select 1 from public.visits v
    where v.id = visit_items.visit_id
      and (v.tech_id = auth.uid() or public.current_user_role() = 'supervisor')
  ));


-- ----------------------------------------------------------------------------
-- 6. Grants — this project has "auto-expose new tables" OFF, so we explicitly
--    grant table access to the 'authenticated' role. The RLS policies above
--    still decide which ROWS each person can touch. 'anon' (logged-out) gets
--    nothing at all.
-- ----------------------------------------------------------------------------
grant usage on schema public to authenticated;
grant select, update                         on public.profiles    to authenticated;
grant select, insert, update, delete         on public.houses      to authenticated;
grant select, insert, update, delete         on public.visits      to authenticated;
grant select, insert, update, delete         on public.visit_items to authenticated;


-- ----------------------------------------------------------------------------
-- 7. Seed the two known houses (from house-data.js). Safe to re-run.
-- ----------------------------------------------------------------------------
insert into public.houses (name, equipment, notes, info) values
('Dogwood',
 '{"roofCoils": true, "airExchanger": true, "frontLoadWashers": false}'::jsonb,
 '{"fireExtinguishers": "Up: laundry closet · Down: mech room · Garage: by main door · One in the van", "furnaceFilter": "20x25x20", "fridgeCoils": "Upstairs: front · Downstairs: back", "waterSoftener": "In the mechanical room", "shutoffs": "Gas & water: mech room. Outside water: mech room above softener + under RS kitchen sink", "knives": "Block on counter", "medLock": "Stealth lock (code in local codes file)", "atticAccess": "Attic access: hallway by bathroom", "dryerVents": "Upstairs: NW side · Downstairs: NE side under deck"}'::jsonb,
 '[["Paint","Laundry closet"],["Fuse box","Garage by MTX cabinet"],["Attic access","Hallway by bathroom"]]'::jsonb),
('Roselawn',
 '{"generator": true, "waterSoftener": true, "sumpPump": false, "roofCoils": false, "garbageDisposal": false, "frontLoadWashers": false}'::jsonb,
 '{"fireExtinguishers": "Up: kitchen sink, van, garage · Downstairs: kitchen sink", "furnaceFilter": "16x25x1 — change monthly", "shutoffs": "Main water: mech room by washing machine. Main gas: mech room by furnace. Outside: behind back-yard faucet in wall + mech room above softener", "medLock": "Magnet and key", "atticAccess": "Attic access: big closet in dining area"}'::jsonb,
 '[["Paint","Storage room by RS kitchen"],["MTX cabinet","Garage"],["Jacuzzi tub cover","Velcro"],["Humidifier","Mech room"],["Med lock","Magnet and key"],["Attic access","Big closet in dining area"]]'::jsonb)
on conflict (name) do nothing;

-- ============================================================================
-- Done. After you create your login (front-end, next step), promote yourself
-- to supervisor by running, in this same SQL Editor:
--
--   update public.profiles set role = 'supervisor'
--   where id = (select id from auth.users where email = 'you@example.com');
-- ============================================================================
