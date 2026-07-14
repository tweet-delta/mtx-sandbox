# House info panel + codes in the DB — design

**Date:** 2026-07-14
**Status:** Approved (owner, 2026-07-14)
**Branch:** `claude/claude-code-tutorial-5l5ew2`

## Problem

While running a checklist, a tech needs the current house's info — paint
location, attic access, and especially **entry/med-lock/garage/apartment/alarm
codes** — without scrolling to the bottom of a long list or opening the ☰
Houses sidebar (which shows all 48 houses in a picker the tech doesn't need
mid-visit). Today that info lives in `#houseInfo` inside the sidebar, and the
codes only appear on devices where `house-codes.local.js` was manually copied.

## Goal

One tap from anywhere in the checklist opens a panel showing **only the current
house's** info and codes. Codes become available to every signed-in tech on any
device (moved into the database), and supervisors can fix a code in-app when a
lock changes. The ☰ sidebar slims to an account-only menu.

## Owner decisions captured

| Question | Decision |
|---|---|
| Panel content | House info pairs **+ codes** (garage, med lock, apartment/door, alarm — all code rows) |
| Codes source | **Move to a protected Supabase table** (not local-file-only) |
| Compliance stance | **Middle ground:** real codes in Supabase now for day-to-day use; **physically rotating all codes is a required step of the eventual M365 migration.** Documented as accepted interim risk, overriding the earlier "codes never in Supabase" default. |
| How it opens | **ℹ️ House info button in the sticky visit header** → modal panel |
| Sidebar fate | **Slim to an account menu** (signed-in-as, change password, sign out) |
| Code editing | **Supervisor edits in-app** (✎/✕/+ Add in the panel); techs read-only; no suggest/approve flow |

## Non-goals (this slice)

- Deleting `house-codes.local.js` support (kept as backup + signed-out fallback).
- Code change history / audit trail.
- Per-route or per-tech code visibility restrictions.
- Offline caching of codes (Phase 5, offline-first).
- Touching the House Notes (`#notes`) screen's own info/notes editing.

---

## Part A — Database: the `house_codes` table

### Why a separate table (not columns on `houses`)

`loadHouses()` pulls the whole `houses` table into a client-side cache that
feeds many screens (picker, notes, routes, checklist tailoring). If codes lived
on the `houses` row they'd ride into every one of those caches and any
incidental logging. A **separate `house_codes` table**, fetched **only when the
ℹ️ panel opens** (one house at a time), keeps codes out of the general houses
cache — a real reduction of exposure surface, consistent with the "hard line
around sensitive data" posture.

### Schema (migration `0018_house_codes.sql`)

```
public.house_codes
  id         uuid primary key default gen_random_uuid()
  house_id   uuid not null references public.houses(id) on delete cascade
  label      text not null            -- e.g. "Garage code", "Med lock", "Alarm"
  value      text not null            -- the code itself
  position   int  not null default 0  -- display order within a house
  created_at timestamptz not null default now()
  updated_at timestamptz not null default now()

index on (house_id, position)
```

This mirrors the shape of `house-codes.local.js` today: a house maps to an
ordered list of `[label, value]` pairs.

### RLS (row-level security)

- **Enable RLS** on the table (auto-RLS is on for new tables anyway).
- **Select policy `house_codes_select`:** any authenticated user (`auth.role()
  = 'authenticated'`). Same acceptance already documented for `houses` — every
  account is provisioned deliberately by the supervisor, and signed-in staff
  read all houses. Signed-out visitors get nothing.
- **Write policies `house_codes_write` (insert/update/delete):** supervisors
  only, checked the same way existing supervisor-only writes are (a subquery
  against `public.profiles` for `role = 'supervisor'` on `auth.uid()`, matching
  the pattern used by `houses_write` / the routes policies).

### The migration file contains ZERO real codes

`0018_house_codes.sql` **only** creates the table + policies + index. It is what
gets committed to the public repo. No `INSERT` of any real code appears in any
tracked file, ever.

### One-time import of real codes (local only, never committed)

1. A generator (same headless-Chrome pattern used for `gen-0005.html`) loads
   `house-codes.local.js` **and** the houses list (to resolve each house name →
   `house_id`), and prints `INSERT INTO public.house_codes (house_id, label,
   value, position) VALUES (…);` statements.
2. Output is written to a **scratchpad file outside the repo** (the session
   scratchpad dir), reviewed, then applied with
   `supabase db query --linked --file <scratchpad>.sql` — **not** `db push`, so
   it never enters `supabase/migrations/` and never gets committed.
3. The scratchpad file is deleted after a successful import.
4. The pre-commit secret guard remains the backstop; nothing with a code should
   ever be staged.

If a house name in the local file doesn't resolve to a house row, the generator
skips it and reports it — no silent guessing (the "no guessing" rule).

### `house-codes.local.js` is kept, untouched

Still the owner's personal backup and the **signed-out fallback** for the panel.
Nothing is deleted this slice.

---

## Part B — UI: ℹ️ button, modal panel, slim sidebar

### 1. ℹ️ House info button (sticky visit header)

- Added to the `.titlerow` in the visit header (next to ☰), so it's reachable
  from anywhere in the checklist without scrolling — the header is already
  `position: sticky`.
- Hidden until a house is selected (no house → nothing to show). Toggle its
  visibility wherever `selectHouse()` / house state already updates the header.
- `aria-label="House info"`; keyboard-focusable; visible focus ring (existing
  `:focus-visible` styling applies).

### 2. The panel (modal `<dialog>`)

Reuse the existing survey-modal pattern (`<dialog>`, `.modal-card`,
`.modal-head` with ✕, focus trap, Esc to close, `prefers-reduced-motion`
respected). Content, for the **current house only**:

- **Loading state** shown immediately while codes fetch.
- **Codes section first** — rendered from a new `cloud.getHouseCodes(houseId)`
  read against `house_codes`, ordered by `position`. Each row: label + value.
  - If the fetch fails (offline / error): show a plain
    *"Couldn't load codes — check your connection."* message, and if
    `house-codes.local.js` has entries for this house, fall back to those
    (labelled as the on-device copy). Never a silent blank.
  - If signed out (shouldn't happen mid-visit, but for safety): local-file
    fallback only.
- **House info pairs** below — the same `h.info` `[label, value]` content
  `renderHouseInfo()` shows today (paint, attic access, etc.).

### 3. Supervisor editing inside the panel

- `body.is-admin` (set by `loadRole()` for supervisors) gates edit controls.
- Each code row gets **✎ edit** (label + value inline) and **✕ remove**; a
  **"+ Add code"** control adds a new label/value row.
- Saves call new `cloud.js` writes:
  - `saveHouseCode(houseId, { id?, label, value, position })` — upsert.
  - `deleteHouseCode(id)`.
  - Both write to `house_codes`; **RLS enforces supervisor-only server-side**,
    the UI gate is convenience only (defense in depth, never the sole guard).
- Techs never see edit controls; codes are read-only for them.
- No suggest/approve flow for codes (owner decision — only supervisors set
  codes).

### 4. Slim the ☰ sidebar to an account menu

- Remove from the sidebar: the house list (`#houseList`), search input
  (`#houseSearch`), 🔍 toggle (`#houseSearchToggle`), and the `#houseInfo`
  panel. Their JS (`renderHouseList`, `toggleHouseSearch`, house-list click
  handler, search handler) is removed with them.
- **Keep:** the `#account` block — "Signed in as…", Set/change password,
  Sign out.
- The header button changes from `☰ Houses` to **👤** (label
  `aria-label="Account"`) so it reads as account, not house-picking.
- **House switching** already has a safe path: **← Home → 🏠 New house visit**,
  and `selectHouse()` confirms before discarding unsaved work. No new
  house-switch UI is needed on the checklist screen.

### 5. Housekeeping

- Bump SW cache `v19` → `v20` (`index.html`, `cloud.js`, `sw.js` all change).
- Update `HANDOFF.md` with the new state (table, panel, slimmed sidebar,
  import-done note, live-verify checklist).
- Update memory: amend `compliance-sharepoint-only-eventual` to record the
  accepted-interim-risk decision + the rotate-on-migration requirement.
- Remind owner: hard-refresh (Ctrl+Shift+R) after deploy; fully close/reopen
  the PWA on phones.

---

## Interfaces added to `window.cloud`

- `getHouseCodes(houseId)` → `{ codes: [{id, label, value, position}] }` ordered
  by position, or `{ error }` / `{ notReady: true }` (table missing → graceful,
  via `isMissingTable`). Self-contained read; does **not** touch the houses
  cache.
- `saveHouseCode(houseId, { id?, label, value, position })` → `{ error }` (upsert;
  supervisor-only via RLS).
- `deleteHouseCode(id)` → `{ error }`.

## Verification (live, both roles)

Run on the deployed site after push (hard-refresh, may take two for v20 SW):

1. **Import check:** in the Supabase dashboard, `select count(*) from
   public.house_codes;` matches the number of code lines imported; spot-check a
   couple of houses' rows.
2. Sign in as **tech1** → start a visit at a house that has codes → the **ℹ️**
   button appears in the header → tap it → panel shows that house's codes
   (garage/med-lock/apartment/alarm as applicable) then info pairs. No edit
   controls. Esc/✕ closes; focus returns to ℹ️.
3. Switch to a house with **no** codes → panel shows info pairs and a clean
   "no codes on file" (or just the info) — no error.
4. Sign in as **supervisor** → open the panel → ✎ edit a code, save, reload →
   change persisted (dashboard confirms). Add a code; remove a code.
5. Confirm the ☰→👤 menu shows only account actions (no house list); confirm
   ← Home → New house visit still confirms before discarding unsaved work.
6. Offline / error path: throttle or block the request → panel shows the
   "couldn't load codes" message and, if the local file is present, the
   on-device fallback — never a silent blank.
7. Deep-link reload while a visit is open → header + ℹ️ still work, no console
   errors.

Test accounts: `tech1@example.com`, `tech2@example.com` (role=tech); owner is
supervisor.
