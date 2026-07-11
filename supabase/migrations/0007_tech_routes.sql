-- ============================================================================
-- 0007_tech_routes.sql — Named routes: each route owns houses and is run by
-- one tech. Turnover = point the route at a new tech (one UPDATE), and every
-- house on it follows.
--
-- HOW TO RUN: Supabase dashboard → SQL Editor → New query → paste this whole
-- file → click into the editor to clear any text selection → Run.
-- Safe to re-run (if-not-exists / on-conflict throughout).
-- ============================================================================

-- 1. One row per route. tech_id null = no tech right now (mid-turnover);
--    that route's houses appear on no one's picker until a tech is assigned.
create table if not exists public.routes (
  id         uuid primary key default gen_random_uuid(),
  name       text not null unique,
  tech_id    uuid references public.profiles (id),
  created_at timestamptz not null default now()
);

-- 2. Which route each house is on. null = unassigned (hidden from every
--    tech's route-scoped pickers; still reachable via "Show all houses").
alter table public.houses
  add column if not exists route_id uuid references public.routes (id);
create index if not exists houses_route_idx on public.houses (route_id);

-- 3. RLS: every signed-in user reads routes (a tech must resolve their own;
--    names aren't sensitive). Only supervisors change them — same pattern as
--    houses_write in 0001.
alter table public.routes enable row level security;

drop policy if exists routes_select on public.routes;
create policy routes_select on public.routes
  for select to authenticated using (true);

drop policy if exists routes_write on public.routes;
create policy routes_write on public.routes
  for all to authenticated
  using (public.current_user_role() = 'supervisor')
  with check (public.current_user_role() = 'supervisor');

-- Auto-expose is OFF in this project, so grant table access explicitly
-- (RLS above still decides which ROWS each person can touch).
grant select, insert, update, delete on public.routes to authenticated;

-- 4. Seed the four routes. Rename them in-app (Routes screen) if desired.
insert into public.routes (name) values
  ('Route 1'), ('Route 2'), ('Route 3'), ('Route 4')
on conflict (name) do nothing;

-- ============================================================================
-- Verify with:   select name, tech_id from public.routes order by name;
-- Expect 4 rows, all tech_id null. Then assign techs/houses in the app's
-- Routes screen (supervisor only) — no more SQL needed for turnovers.
-- ============================================================================
