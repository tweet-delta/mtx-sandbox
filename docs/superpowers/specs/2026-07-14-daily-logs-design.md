# Daily Logs calendar — design spec (slice 3 of 4)

**Date:** 2026-07-14
**Branch context:** follows slice 1 (My Profile) and slice 2 (Visit History)
on `claude/claude-code-tutorial-5l5ew2`. Slice 4 (shared on-call rotation
calendar) remains a separate future cycle.

## Where this sits

This is slice 3 of a 4-part request from the owner:

1. My Profile editor — ✅ built (slice 1)
2. Tech's own past-visit history view — ✅ built (slice 2)
3. **Daily Logs calendar (auto + manual entries)** — this spec
4. Shared on-call rotation calendar — future

Each slice gets its own spec → plan → build cycle, keeping every change small,
reviewable, and shippable on its own (the project's "smallest complete slice
first" rule).

## Goal

Give each tech a **month-grid calendar of their own workdays** — a work diary.
Two kinds of entries land on it:

- **Auto** — every time the tech saves a visit (Save progress *or* the survey's
  Save & Send), that calendar day gets stamped with the house name and a
  snapshot of what was finished. A multi-day visit therefore shows on each day
  the tech actually saved work.
- **Manual** — free-text notes the tech types onto any day (today or a past day
  they forgot to log), editable and deletable later.

A tech sees only their own diary; supervisors can additionally read everyone's.

## Explicitly out of scope this slice

- The on-call rotation calendar (slice 4 — different data, shared, editable by
  supervisors).
- Hours, mileage, or any structured field beyond a free-text note (owner chose
  free-text only).
- Linking a manual note to a specific house (manual notes are plain text; only
  *auto* rows carry a house).
- Editing or deleting **auto** rows — they are the machine's record of what the
  save actually contained. Only manual rows are user-editable.
- Cross-tech or house-level diary views, filtering, search, export.
- Photos (Phase 2).

## Data model

One new table, `public.daily_logs`, one row per entry.

| column      | type          | notes |
|-------------|---------------|-------|
| `id`        | uuid PK       | `gen_random_uuid()` |
| `tech_id`   | uuid          | `references profiles(id)`, `default auth.uid()` — whose diary |
| `log_date`  | date          | the calendar day this entry sits on |
| `kind`      | text          | `check (kind in ('auto','manual'))` |
| `visit_id`  | uuid          | auto rows only: `references visits(id) on delete cascade`; null on manual |
| `house_id`  | uuid          | auto rows only: `references houses(id)`; null on manual — denormalized so the calendar can show the house name without joining through the visit |
| `note`      | text          | manual rows: the tech's free text. Auto rows: `''` |
| `done_keys` | jsonb         | auto rows: array of stable item keys checked as of that day's latest save (a cumulative snapshot). Manual rows: `'[]'` |
| `created_at`| timestamptz   | `default now()` |
| `updated_at`| timestamptz   | `default now()`, bumped on manual edit |

**Uniqueness (auto rows):** a partial unique index enforces **one auto row per
`(tech_id, visit_id, log_date)`**. Saving progress five times on the same day
updates that single row's `done_keys` snapshot to the latest state rather than
creating duplicates (an *upsert*). Manual rows have no uniqueness constraint —
a tech can add several notes to one day.

```sql
create unique index daily_logs_auto_uniq
  on public.daily_logs (tech_id, visit_id, log_date)
  where kind = 'auto';
```

### Why store cumulative `done_keys`, display the daily difference

Each auto row stores the **cumulative** set of checked keys as of that day. The
"what did I finish *today*" view is computed at **display** time by subtracting
the previous auto row's `done_keys` (same visit, most recent earlier
`log_date`) from this day's set. This is deliberate: a day's row never depends
on another row having been written first (no ordering fragility), and a
re-opened/edited visit still yields a correct per-day diff. If there is no
earlier auto row for the visit, every checked key counts as finished "today."

## Row-Level Security

RLS ON. Mirrors the app's established self-or-supervisor pattern.

- **select:** `tech_id = auth.uid()` **OR** caller is a supervisor
  (`current_user_role() = 'supervisor'`).
- **insert:** `tech_id = auth.uid()` (a tech only writes their own diary).
- **update:** `USING (tech_id = auth.uid())` and
  `WITH CHECK (tech_id = auth.uid())` — a tech may update **their own** rows.
  The policy intentionally does **not** restrict `kind`, because the auto-stamp
  upsert (below) resolves its conflict as an UPDATE and must be able to refresh
  the caller's own auto row.
- **delete:** `USING (tech_id = auth.uid())` — a tech may delete their own rows.

**Why `kind` is not in the update/delete policy, and how auto rows stay
immutable in practice.** The auto stamp is an `upsert` on the
`(tech_id, visit_id, log_date)` partial unique index; Postgres resolves the
conflict as an UPDATE of the caller's own auto row, so a policy that forbade
updating `kind='auto'` rows would break the stamp. We therefore scope the RLS
policies to ownership only (`tech_id = auth.uid()`), which is the real security
boundary — **no tech can ever touch another tech's rows, and supervisors are
read-only.** Auto rows being un-editable *from the user's point of view* is then
enforced two ways, both required:

1. The `#logs` UI never renders Edit/Delete controls on auto entries.
2. `updateLogEntry` and `deleteLogEntry` self-scope with `.eq('kind','manual')`
   in the query, so even a crafted call can't alter an auto row.

This is defense-in-depth, not a gap: ownership is enforced by the database;
the manual-only restriction on user edits is enforced by the app layer (where,
per the compliance plan, our logic is meant to live and to port to M365).

The one-time backfill runs as the migration author (RLS bypassed), so it
writes auto rows freely.

### Backfill (one-time, in the migration)

Existing **completed** visits get one auto row each, on the visit's
`visit_date`, `house_id` from the visit, `done_keys` = that visit's
final set of `visit_items` where `done = true`. So the calendar isn't empty on
day one. Pre-existing multi-day visits collapse to a single dot on their
recorded `visit_date` — that per-day history was never captured and cannot be
reconstructed. In-progress visits are **not** backfilled (they'll stamp
naturally on the next save).

## `cloud.js` additions

### Auto stamp inside `saveVisit()`

Right after the existing visit + visit_items save succeeds, `saveVisit()`
upserts today's auto row:

- `tech_id` = current user, `visit_id` = the visit just saved,
  `house_id` = resolved house, `log_date` = **today's local date**
  (`v.date` is the visit date the tech set; the stamp uses the *actual* save
  day so a multi-day visit lands on each real workday — confirm which field
  carries "today"; if the app has no separate "today," use the client's current
  local date, formatted `YYYY-MM-DD`), `kind='auto'`, `note=''`,
  `done_keys` = keys of `v.items` where `it.done === true`.
- Upsert on the `(tech_id, visit_id, log_date)` conflict target so repeated
  saves that day refresh the snapshot.

**Failure isolation:** the stamp is best-effort. If the daily_logs upsert
errors (flaky network, or the table not yet in the schema cache —
`isMissingTable`), `saveVisit()` still returns success for the visit itself and
logs the miss to `console.warn`. The diary is a record, never a gate on the
tech's real work. (Same spirit as the existing `done_on`/`value` degraded-save
fallback.)

### Read + manual-entry functions (exported on `window.cloud`)

- `listLogsInRange(startDate, endDate)` → the caller's own rows (supervisors
  still only call it for themselves in this slice) with
  `log_date` in `[start, end]`, each as
  `{ id, logDate, kind, houseName, note, doneKeys }`, ordered by `log_date`.
  One month view = one call. Returns `[]` on no-user/error.
- `addLogEntry(logDate, note)` → inserts a manual row for the caller
  (`kind='manual'`). Returns `{ id }` or `{ error }`. Rejects empty/whitespace
  note client-side before calling.
- `updateLogEntry(id, note)` → updates a manual row, self-scoped
  `tech_id = me AND kind = 'manual'`. Returns `{ error }`.
- `deleteLogEntry(id)` → deletes a manual row, same self-scope. Returns
  `{ error }`.

All self-scope on `tech_id` (and manual mutators on `kind='manual'`) as
defense-in-depth atop RLS — the pattern slices 1 and 2 established.

## The `#logs` screen

New home-screen button **"🗓️ Daily logs"**, always visible (NOT `admin-only`
— every tech has a diary), same button style as "👤 My profile" and
"🗓️ My visit history". Opens a hash-router screen `#logs`, same pattern as
`#profile` / `#history`.

### Month grid

- Renders the current month by default; `‹` / `›` move to previous/next month.
  A visible month label ("July 2026").
- One `listLogsInRange(firstOfMonth, lastOfMonth)` call per month shown.
- **Day cell contents:** if the day has an auto row, show the **house name**
  (truncated with ellipsis to fit the cell; full name via `title`/aria-label).
  If it has only manual rows, show **"Daily log"**. If both, house name wins in
  the cell (the day still opens to show everything). No activity → plain day
  number. Today's cell gets the app's existing "today" highlight.
- A day with activity is a button (tappable / focusable); empty days are not
  interactive except the "add note" affordance (see below).

### Day detail (opens below the grid on tap)

Selecting a day reveals that day's full log beneath the grid:

- **Auto entries** first: `"<House> — <section>: n/m done (+k today)"` per
  section that had any finished item, followed by the list of the items
  finished **that day** (the computed diff). Section labels and item labels come
  from the existing `GROUPS` / `ITEM_BY_KEY` structures (same lookup slice 2's
  detail view uses). Sections with nothing finished are omitted. `n/m` is
  cumulative done/total for the section; `+k today` is the diff count.
- **Manual notes** next, each with **Edit** and **Delete** controls (own rows
  only — always true here since it's the tech's own diary).
- **"+ Add note"** button — opens a small text field; saves via `addLogEntry`
  for the **selected** day (works on past days for backfill). After add/edit/
  delete, re-render the day (and refresh the month so the dot/label updates).

### Unknown item keys

If a `done_keys` entry isn't in `ITEM_BY_KEY` (checklist changed since the
visit), show it under an "Other" section by its raw key — never crash. Same
robustness rule slice 2 used.

## Accessibility

- The month grid is a labelled table/grid; day buttons have accessible names
  ("July 7, worked at Dogwood" / "July 9, daily log" / "July 3, no activity").
- Month `‹`/`›` are real buttons with aria-labels.
- The add-note field, Edit, and Delete are keyboard-operable with visible
  `:focus-visible` styles; respects `prefers-reduced-motion`. Matches the bar
  the rest of the app holds.

## Service worker

Both `index.html` and `cloud.js` change, so bump the SW cache `v16` → `v17`
(and tell the owner to hard-refresh / fully reopen the PWA after deploy, per
standing practice).

## Verification (end-to-end, owner/live)

1. Sign in as `tech1@example.com`. Open "🗓️ Daily logs" → current month renders;
   backfilled dots appear on past completed-visit dates.
2. Start a visit at a house, hit **Save progress**. Today's cell now shows the
   house name; tap it → the day lists the sections/items finished so far.
3. Finish more items, Save progress **again same day** → the day's list grows,
   and there is still exactly **one** auto entry for that day (no duplicate).
   (If testable across two days, confirm day 2 shows only day-2 items via the
   diff.)
4. Add a manual note to **today** and to a **past** day; edit one; delete one —
   each re-renders correctly and the month dots update.
5. Sign in as `tech2@example.com`: they see only their own diary (isolation);
   tech1's days are absent.
6. Deep-link reload on `#logs` re-renders with no console errors.
7. Confirm a `daily_logs` row exists in Supabase for a save
   (`select log_date, kind, house_id, done_keys from public.daily_logs
   where tech_id = auth.uid();`).

## Migration

New migration file (next number after 0015 — likely `0016_daily_logs.sql`):
create the table, indexes (including the partial unique auto index), enable
RLS, add the four policies, and run the one-time backfill from completed
visits. No changes to `visits` / `visit_items` schema.
