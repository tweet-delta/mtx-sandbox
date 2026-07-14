# Supervisor View of Team Daily Logs — Design

**Date:** 2026-07-14
**Slice:** Extension of slice 3 (Daily Logs). Adds a supervisor's ability to
review any tech's daily-log calendar.

## Goal

Let a supervisor open the Daily Logs screen, pick any tech (or themselves) from
a dropdown, and view that person's month calendar — the same grid, day detail,
and finished-items breakdown techs already see — **read-only** for anyone but
themselves.

## Why this is the "optimistic" path

The heavy lifting is already done:

- **Database is ready.** The `daily_logs` RLS `select` policy (migration 0016)
  already permits `tech_id = auth.uid() OR current_user_role() = 'supervisor'`.
  A supervisor can already read every tech's rows. **No migration needed.**
- **The screen is already built and tested.** The month grid, prev/next nav,
  the finished-that-day diff, house labels, and the day-detail all work. We
  reuse them unchanged and only change *whose* rows feed them.

So this slice is **one generalized data function + one dropdown + one read-only
guard.** Least new code, least new risk.

## Non-goals (YAGNI)

- No "whole-team merged" calendar or cross-tech feed — supervisor views **one
  tech at a time**.
- No supervisor editing of a tech's diary. Review is read-only.
- No new table, column, or migration.
- No date-range or house filters beyond the existing month navigation.

## Architecture

Three focused changes, each with a clear boundary:

### 1. Data layer (`route-checklist/cloud.js`)

**a. Generalize `listLogsInRange` with an optional `techId`.**

```js
// techId omitted → the signed-in user's own rows (every existing caller).
// techId passed  → that tech's rows. RLS is the real gate: a non-supervisor
// passing someone else's id simply gets [] back (their select policy only
// matches their own rows); a supervisor gets the rows.
async function listLogsInRange(startDate, endDate, techId) {
  const { data: { user } } = await supabase.auth.getUser();
  if (!user) return [];
  const scopeId = techId || user.id;
  const { data, error } = await supabase
    .from("daily_logs")
    .select("id, log_date, kind, visit_id, note, done_keys, houses(name)")
    .eq("tech_id", scopeId)
    .gte("log_date", startDate).lte("log_date", endDate)
    .order("log_date", { ascending: true });
  // ...unchanged mapping...
}
```

The security boundary stays in the database. The UI only *asks*; RLS *decides*.
This matches the project rule: never rely on the UI to hide data.

**b. Add a roster helper: techs + the current supervisor.**

The existing `listTechs()` returns tech-role profiles only (supervisors
excluded, by design for route assignment). The Daily Logs dropdown needs techs
**plus the supervisor themselves** (default view = own calendar). New helper:

```js
// The dropdown roster for the supervisor Daily Logs view: every tech, plus
// the signed-in supervisor (so they can see their own diary too). Returns
// { people: [{ id, label }], error? }. Only meaningful for supervisors; a
// tech never calls it (the dropdown is is-admin-only).
async function listLogTechs() {
  const { data: { user } } = await supabase.auth.getUser();
  if (!user) return { error: "Not signed in." };
  const { data, error } = await supabase
    .from("profiles").select("id, full_name, role").order("full_name");
  if (error) return { error: error.message };
  const people = data
    .filter(p => p.role === "tech" || p.id === user.id)
    .map(p => ({
      id: p.id,
      label: p.id === user.id
        ? `You (${p.full_name || "me"})`
        : (p.full_name || "Unnamed tech"),
    }));
  return { people, myId: user.id };
}
```

Both are exported on `window.cloud`.

### 2. UI (`route-checklist/index.html`)

**State:** one new variable alongside the existing logs state:

```js
let logsViewTechId = null;   // whose calendar is showing; null = me
```

**Dropdown:** rendered at the top of `renderLogsScreen`, **only** when
`document.body.classList.contains("is-admin")`. Populated from `listLogTechs()`.
Defaults `logsViewTechId` to the supervisor's own id (`myId`) on first open, so
the screen opens on their own calendar — familiar, identical to the tech
experience. Techs never see the dropdown; nothing about their screen changes.

**Feeding the grid:** `renderLogsScreen` passes `logsViewTechId` to
`listLogsInRange(first, last, logsViewTechId)`. When `logsViewTechId` is null
(a tech, or a supervisor before the roster loads), it means "me" — unchanged.

**Read-only guard:** the day-detail's Add / Edit / Delete note controls render
only when the viewed calendar is the signed-in user's own — i.e.
`logsViewTechId === myId` (or is-admin is false, the tech case). When a
supervisor views a teammate, those controls are omitted entirely; the
finished-items breakdown and existing notes still show, just without buttons.

**Dropdown change handler:** on change, set `logsViewTechId` to the picked id,
**clear `logsSelectedDate`** (so we never show one tech's day-detail under
another's grid), and re-render.

### 3. Service worker (`route-checklist/sw.js`)

Bump `CACHE` to `route-checklist-v19` so browsers pick up the new HTML/JS.

## Data flow (supervisor picks a teammate)

1. Screen opens → roster loads → `logsViewTechId = myId` → own calendar renders
   (identical to today, controls present).
2. Supervisor picks "Alex" → `logsViewTechId = alexId`, `logsSelectedDate`
   cleared → `renderLogsScreen()` → `listLogsInRange(first, last, alexId)` →
   RLS allows (supervisor) → grid shows Alex's month.
3. Supervisor taps a day → Alex's finished-items + notes render, **no buttons**.
4. Supervisor picks "You" again → own calendar, controls return.

## Edge cases

| Case | Behavior |
|---|---|
| Tech passes another id (shouldn't happen; no dropdown) | RLS returns `[]` → empty calendar. No leak. |
| Supervisor viewing self | Controls present; behaves exactly like a tech. |
| Roster load fails / no techs | Fall back to the supervisor's own calendar; never a broken screen. |
| Switching techs with a day selected | `logsSelectedDate` cleared on every dropdown change. |
| Non-supervisor (`is-admin` false) | No dropdown rendered; `logsViewTechId` stays null = "me". |

## Testing (manual — repo convention, no automated tests yet)

**As a tech:**
- No dropdown appears.
- Own calendar renders; Save-progress stamps a day.
- Add / edit / delete note all still work.

**As a supervisor:**
- Dropdown lists techs + self; opens on self, controls present.
- Pick a teammate → their calendar loads; day detail is **read-only** (no
  Add/Edit/Delete).
- Switch back to self → controls return.

**Security check:**
- Confirm in Supabase that no supervisor write lands on another tech's row (RLS
  holds — the UI never offers the write, and RLS would reject it regardless).

## Files touched

- `route-checklist/cloud.js` — generalize `listLogsInRange`; add `listLogTechs`;
  export both.
- `route-checklist/index.html` — dropdown, `logsViewTechId` state, read-only
  guard, change handler.
- `route-checklist/sw.js` — cache bump to v19.
- `route-checklist/HANDOFF.md` — note the supervisor view.

No SQL migration.
