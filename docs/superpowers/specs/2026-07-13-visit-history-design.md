# Visit History — design spec (slice 2 of 4)

**Date:** 2026-07-13
**Branch context:** follows slice 1 (My Profile). Slices 3–4 (Daily Logs
calendar, on-call rotation calendar) remain separate future cycles.

## Goal

Let a signed-in tech view **their own completed visits** and, one tap in, see
**only the items that need attention** from that visit (flagged answers and any
item with a note). This is the reason a tech opens history: "what did I find
wrong last time at this house."

## Why this is a thin, front-end-only slice

The data and read access already exist:

- `public.visits` (migration 0001) stores `house_id`, `tech_id` (defaults to the
  signed-in user), `visit_date`, `status` (`in_progress`/`completed`),
  `completed_at`, plus `counts`/`survey` JSON we are **not** surfacing this slice.
- `public.visit_items` (migration 0001) stores per-item `answer` (`yes`/`no`/`na`)
  and `note`, keyed by stable `item_key`.
- Migration 0002 already grants **any signed-in staff member read access** to
  `visits` and `visit_items` via `visits_select` / `visit_items_select`
  (`using (true)` for `authenticated`).

Therefore: **no new migration, no RLS change.** Slice 2 = two new read functions
in `cloud.js` + one new `#history` screen in `index.html`.

## The flag definition (critical — do not store it)

An item is **flagged** when `answer === item.bad`, where `bad` is the item's
*polarity* declared in the `GROUPS` data structure in `index.html`:

- `bad: "yes"` → "anything wrong?" question (Yes = problem)
- `bad: "no"`  → "working properly?" question (No = problem)

This matches the live app's own logic (`paintYN`: `isBad = answer && answer === bad`).
`GROUPS` is the single source of truth for polarity (CLAUDE.md convention), so the
history view **computes flags client-side from `GROUPS`** — it must NOT denormalize
a `flagged` boolean into the DB (that would duplicate polarity and make old rows
lie if wording/polarity ever changes — the same class of bug the positional-key
refactor already eliminated).

## Approach chosen

**Pure front-end + one-read-per-view.** Rejected alternatives: a DB view/RPC that
pre-joins a flag count (splits the single source of truth into SQL), and a stored
`flagged` boolean on `visit_items` (denormalization that can go stale).

## Components

### 1. `cloud.js` → `listMyVisits()`

- Get signed-in user. Query `visits` where `tech_id = me` and
  `status = 'completed'`, joined to `houses(name)`.
- Order by `visit_date` desc, then `completed_at` desc (tiebreaker for two visits
  the same day).
- Returns `[{ id, houseName, visitDate }]`, or `{ error }`. Mirrors the shape and
  error handling of the existing `listInProgress()`.

### 2. `cloud.js` → `getVisitDetail(visitId)`

- Fetch the one visit (with `houses(name)`) **filtered `tech_id = me`** (defense in
  depth — RLS allows reading any staff visit; this ensures the "my history" screen
  can't wander into another tech's visit via a hand-typed id) plus its `visit_items`
  (`item_key`, `answer`, `note`).
- Returns `{ houseName, visitDate, items: [{ item_key, answer, note }] }`, or
  `{ error }`.

### 3. `index.html` → `#history` screen

- Home-screen button **"🗓️ My visit history"**, always visible (NOT `admin-only`).
- **List view** (`#history`): rows of house name + date, newest first. Tap → detail.
- **Detail view** (`#history/<visitId>`): house + date header, then only the
  flagged + noted items. For each item in the DB, look up `item_key` in `GROUPS`;
  show it when `answer === item.bad` **or** it has a `note`. Render the item's
  question text, the recorded answer, and the note (all via `escHtml`/`escAttr`).
- Same hash-router / `screen-head` / "← Home" pattern as `#profile`, `#notes`,
  `#routes`.

## Data flow

Home → "🗓️ My visit history" → `#history` renders list via `listMyVisits()` →
tap row → `#history/<visitId>` → detail via `getVisitDetail(id)`, cross-referenced
against `GROUPS`. A stale-nav guard
(`if (currentScreenFromHash() !== "history") return;`) runs after each async load,
exactly as the profile screen does, so a late-resolving query never paints stale
content.

## Edge cases

- **No completed visits** → empty state ("No completed visits yet.").
- **A visit with zero flags/notes** → detail shows "No issues flagged on this
  visit." (a clean visit is a normal outcome, not an error).
- **`item_key` in the DB no longer in `GROUPS`** (item removed since the visit) →
  still show it, using the raw `item_key` as a fallback label, and treat any
  answer/note as worth displaying — history must never silently drop what a tech
  actually recorded.
- **Offline / query error** → inline error message (+ `toast()`); never blank the
  screen.

## Security

- Self-only via the `tech_id = me` filter in both functions.
- All DB-sourced strings rendered through the existing `escHtml` / `escAttr`.
- No new secrets, no service_role, no new grants.

## Out of scope (YAGNI — each a clean future slice)

- Flagged-count badge on list rows (list is house + date only).
- Full checklist replay, alarm `counts`, or `survey` in detail.
- Other techs' history or a house-level history view.
- Photos in history (Phase 2).
- Editing a past visit (history is strictly read-only).
- Filtering / searching the list.

## Verification (must drive it — no claiming done without running)

- Sign in as a tech with completed visits → button appears; list shows house +
  date, newest first.
- Tap a visit with a known flagged item → detail shows exactly that item, its
  answer, its note; a clean visit shows the "no issues" state.
- Tech with no completed visits → empty state.
- Confirm self-isolation: a second tech sees only their own visits.
- Bump the SW cache version (convention when `index.html`/`cloud.js` change);
  hard-refresh (Ctrl+Shift+R) after deploy.
