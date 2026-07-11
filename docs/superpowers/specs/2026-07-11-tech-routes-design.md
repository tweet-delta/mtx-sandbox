# Tech Routes — Design

Date: 2026-07-11
Status: approved, ready for implementation plan

## Problem

There are 4 maintenance route techs. Each has a fixed set of houses they
rotate through (~3-month rotation, order roughly fixed). Some days a tech is
a "float" — free that day to respond to requests at any house instead of
their own route.

Today every signed-in tech sees all 47 houses on the Home screen pickers
("New house visit" / "Continue house visit") and in House Notes. There's no
concept of "this house belongs to that tech." The owner wants routes set up
so each tech's day-to-day pickers show only their own houses, while still
being able to reach every house's notes and, when needed, start/continue a
visit anywhere.

## Decisions (confirmed with the owner)

- **Fixed assignment, not a schedule.** A house belongs to one tech until a
  supervisor reassigns it. No day-of-week or rotation-date logic.
- **Float days need no new app concept.** "Float" just means the tech uses
  the existing "All houses" escape hatch that day — nothing scheduled.
- **Direct assignment, no route entity.** `houses.assigned_tech_id` — no
  separate `routes` table. Simplest model that satisfies "each house has one
  owning tech."
- **Supervisor-only assignment**, via a small new in-app screen (not just the
  Supabase dashboard) — dropdown per house, sets or clears the tech.
- **Unassigned houses are hidden** from every tech's route pickers until a
  supervisor assigns them. They remain reachable via "All houses."
- **House Notes is unaffected** — it already shows every house and stays
  that way; routes are a Home-screen concept only.
- **"All houses" toggle is full access** — same read/write as a route house
  (start a new visit, continue an in-progress one), not a browse-only view.

## Data model change

One nullable column on the existing `houses` table:

```sql
alter table public.houses
  add column if not exists assigned_tech_id uuid references public.profiles (id);
```

- `null` = unassigned.
- No new table. Reassigning a house is just changing this one value.

## RLS

- `houses` SELECT policy is unchanged — every signed-in user still reads
  every house row (required for House Notes and "All houses").
- `houses` WRITE policy is unchanged — already supervisor-only
  (`houses_write`), which now also covers editing `assigned_tech_id`.
- No new RLS surface. This is the smallest possible change to the security
  model.

## App changes

### 1. Home screen pickers

"New house visit" and "Continue house visit" filter the house list to
`houses.assigned_tech_id === current tech's profile id`, instead of all
houses.

### 2. "All houses" toggle

A separate, explicit control next to the route-scoped pickers. Opens the
same searchable house-picker UI, unfiltered (all 47). Full read/write —
a tech can start a new visit or resume an in-progress one at any house from
here. This is a one-off detour: it doesn't change what the Home screen shows
by default afterward.

### 3. House Notes screen

No change — continues to show every house regardless of route.

### 4. New supervisor screen: Assign Routes

- Reachable from the same `☰ Houses` area as other supervisor tools, gated
  the same way existing admin UI is gated (`body.is-admin` / `cloud.role ===
  'supervisor'`).
- Flat, alphabetical list of all houses. Each row has a select/dropdown of
  the 4 techs plus "Unassigned," defaulting to the house's current
  `assigned_tech_id`.
- Changing the dropdown writes immediately (or via a per-row Save — matches
  whatever pattern `cloud.js` already uses for single-field house edits).
- No search box in this first pass — 47 rows in a flat list is manageable;
  add search later only if it proves unwieldy.

### `cloud.js` additions

- `cloud.listMyHouses()` — houses where `assigned_tech_id` = current user.
- `cloud.listAllHouses()` — existing full list (likely already exists in
  some form — reuse, don't duplicate).
- `cloud.assignHouseTech(houseId, techId | null)` — supervisor-only write
  (RLS enforces this; the UI should also hide the control from non-
  supervisors).
- `cloud.listTechs()` — profiles where role = 'tech' (plus supervisors, if
  supervisors also want to appear as assignable — **open question below**).

## Assignable roles

The Assign Routes dropdown lists only profiles with `role = 'tech'` —
`cloud.listTechs()` filters to `role = 'tech'`, excluding supervisors.
Confirmed with the owner: the ask is specifically about the 4 route techs,
not supervisors.

## Out of scope (explicitly deferred)

- Float-day scheduling (calendar, day-of-week logic, auto-switching a tech
  into "float mode").
- Named/portable routes independent of a specific tech.
- Tech self-service reassignment.
- Search/filter on the new supervisor Assign Routes screen.

## Testing / verification

No automated tests in this repo. Verify by:

1. Running migration `0007_tech_routes.sql`, confirming the column exists.
2. As a supervisor: opening Assign Routes, assigning each of the 4 techs a
   handful of houses, confirming the value persists (reload the page).
3. As a tech (a second account or by temporarily changing role): confirming
   Home screen pickers show only assigned houses, House Notes still shows
   all houses, and the "All houses" toggle reveals and allows starting/
   continuing a visit at an unassigned house.
4. Confirming an unassigned house is invisible on the route-scoped pickers
   but visible via "All houses" and in House Notes.
