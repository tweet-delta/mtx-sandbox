# Tech Routes — Design

Date: 2026-07-11 (revised same day: direct assignment → named routes)
Status: approved, ready for implementation plan

## Problem

There are 4 maintenance route techs. Each has a fixed set of houses they
rotate through (~3-month rotation, order roughly fixed). Some days a tech is
a "float" — free that day to respond to requests at any house instead of
their own route.

Today every signed-in tech sees all 47 houses on the Home screen pickers
("New house visit" / "Continue house visit") and in House Notes. There's no
concept of "this house belongs to that route." The owner wants routes set up
so each tech's day-to-day pickers show only their own houses, while still
being able to reach every house's notes and, when needed, start/continue a
visit anywhere.

**Turnover requirement (added after the first draft, and the reason routes
are a first-class entity):** when a tech quits, the supervisor must be able
to hand their entire route to a replacement in one action — not by
re-assigning ~12 houses one at a time, and not by touching the Supabase
dashboard. The owner initially proposed a "route claim code" e-mailed to new
techs; we rejected it (extra machinery, weak e-mailed secret, and it would
require letting techs write assignments, breaking the supervisor-only rule)
in favor of routes that outlive any specific tech.

## Decisions (confirmed with the owner)

- **Named routes, not direct tech assignment.** A `routes` table with one
  row per route (4 to start). Houses belong to a route; each route has at
  most one assigned tech. Turnover = change the route's tech, one dropdown.
- **Fixed membership, not a schedule.** A house belongs to its route until
  a supervisor moves it. No day-of-week or rotation-date logic.
- **Float days need no new app concept.** "Float" just means the tech uses
  the "All houses" escape hatch that day — nothing scheduled.
- **Supervisor-only management**, via a small new in-app screen — both
  "which houses are on which route" and "which tech runs which route."
- **No claim codes.** The supervisor creates the tech's account in the
  Supabase dashboard (profile row exists immediately), points the route at
  them in-app, then sends the invite. The tech logs in and their route is
  already theirs.
- **Unassigned houses are hidden** from every tech's route pickers until a
  supervisor puts them on a route. They remain reachable via "All houses."
- **House Notes is unaffected** — it already shows every house and stays
  that way; routes are a Home-screen concept only.
- **"All houses" toggle is full access** — same read/write as a route house
  (start a new visit, continue an in-progress one), not a browse-only view.
- **Only `role = 'tech'` profiles are assignable** to a route; supervisors
  don't appear in the dropdown.

## Data model change

One new table and one nullable column on `houses`:

```sql
create table if not exists public.routes (
  id         uuid primary key default gen_random_uuid(),
  name       text not null unique,          -- e.g. 'Route 1', renameable
  tech_id    uuid references public.profiles (id),  -- null = no tech right now
  created_at timestamptz not null default now()
);

alter table public.houses
  add column if not exists route_id uuid references public.routes (id);
```

- `houses.route_id` null = house not on any route (hidden from route views).
- `routes.tech_id` null = route currently has no tech (e.g. mid-turnover);
  its houses appear on no one's picker until a tech is assigned.
- Seed 4 routes (`Route 1`–`Route 4`) in the migration; the owner renames
  them in-app if desired.
- Migration file: `0007_tech_routes.sql`.

## RLS

- `routes`: SELECT for all authenticated users (a tech must resolve their
  own route; names are not sensitive). INSERT/UPDATE/DELETE supervisor-only,
  same pattern as `houses_write`. Explicit grants (auto-expose is OFF).
- `houses`: SELECT policy unchanged — every signed-in user still reads every
  house (required for House Notes and "All houses"). WRITE policy unchanged —
  already supervisor-only, which now also covers `route_id`.

## App changes

### 1. Home screen pickers

"New house visit" and "Continue house visit" filter the house list to houses
whose route's `tech_id` = the signed-in user, instead of all houses.

### 2. "All houses" toggle

A separate, explicit control next to the route-scoped pickers. Opens the
same searchable house-picker UI, unfiltered (all 47). Full read/write — a
tech can start a new visit or resume an in-progress one at any house from
here. This is a one-off detour: it doesn't change what the Home screen shows
by default afterward.

### 3. House Notes screen

No change — continues to show every house regardless of route.

### 4. New supervisor screen: Routes

Reachable from the same `☰ Houses` area as other supervisor tools, gated the
same way existing admin UI is gated (`body.is-admin` / `cloud.role ===
'supervisor'`). Two jobs on one screen:

- **Per route:** the route's name (editable) and a dropdown of tech-role
  profiles (plus "No tech") — this is the one-dropdown turnover action.
- **House membership:** a flat, alphabetical list of all houses, each with a
  dropdown of the 4 routes plus "No route." No search box in this first
  pass — 47 rows is manageable; add search later only if it proves unwieldy.

Writes go through `cloud.js`; the UI hides the screen from techs but RLS is
what actually enforces supervisor-only writes.

### `cloud.js` additions

- `cloud.listMyHouses()` — houses on the route(s) whose `tech_id` = current
  user.
- `cloud.listAllHouses()` — existing full-list load (reuse, don't duplicate).
- `cloud.listRoutes()` — all routes with their assigned tech.
- `cloud.listTechs()` — profiles where `role = 'tech'`. Note: the current
  `profiles_select` RLS lets a tech read only their own row, so the
  dropdown's data is naturally supervisor-only too — verify this rather than
  loosening the policy.
- `cloud.saveRoute(routeId, { name, techId })` — supervisor-only write.
- `cloud.setHouseRoute(houseId, routeId | null)` — supervisor-only write.

## Turnover walkthrough (the scenario that shaped this design)

Bob quits; Maria replaces him on Route 2:

1. Supervisor creates Maria's account in the Supabase dashboard (her
   `profiles` row is created automatically by the existing trigger).
2. Supervisor opens the in-app Routes screen, changes Route 2's tech from
   Bob to Maria. One dropdown.
3. Supervisor sends Maria the invite e-mail (just credentials — no code).
4. Maria logs in; her Home screen already shows Route 2's houses.
5. (Cleanup, outside this feature: disable Bob's account in the dashboard.)

## Out of scope (explicitly deferred)

- Route claim codes (rejected — see Problem section).
- Float-day scheduling (calendar, day-of-week logic, auto-switching a tech
  into "float mode").
- Multiple techs sharing one route, or one tech running multiple routes
  (the schema happens to allow the latter; the UI doesn't prevent it, but
  nothing is designed around it).
- Tech self-service reassignment.
- Search/filter on the Routes screen's house list.
- Deactivating/offboarding accounts in-app.

## Testing / verification

No automated tests in this repo. Verify by:

1. Running migration `0007_tech_routes.sql`; confirming the `routes` table
   has 4 seeded rows and `houses.route_id` exists.
2. As a supervisor: opening Routes, naming routes, assigning a tech to each,
   putting a handful of houses on each route, confirming it persists
   (reload).
3. As a tech (a second account or by temporarily changing role): confirming
   Home screen pickers show only their route's houses, House Notes still
   shows all houses, and the "All houses" toggle reveals and allows
   starting/continuing a visit at an off-route house.
4. Turnover drill: move a route's tech to a different profile, confirm the
   old tech's pickers empty out and the new tech's fill in.
5. Confirming a house with no route is invisible on route-scoped pickers but
   visible via "All houses" and in House Notes.
