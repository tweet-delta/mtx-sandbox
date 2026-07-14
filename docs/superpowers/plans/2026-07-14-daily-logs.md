# Daily Logs Calendar Implementation Plan

> **For agentic workers:** REQUIRED SUB-SKILL: Use superpowers:subagent-driven-development (recommended) or superpowers:executing-plans to implement this plan task-by-task. Steps use checkbox (`- [ ]`) syntax for tracking.

**Goal:** Give each tech a month-grid "Daily logs" calendar — a work diary that auto-stamps the days they save a visit (with a per-day snapshot of what got finished) and lets them add/edit/delete free-text notes on any day.

**Architecture:** One new Postgres table `daily_logs` (RLS: own rows + supervisor-read). `saveVisit()` in `cloud.js` gains a best-effort auto-stamp side effect; four new `cloud.js` functions handle reading a month and manual-note CRUD. A new hash-router screen `#logs` in `index.html` renders the month grid and per-day detail, following the exact pattern slice 2 (`#history`) established.

**Tech Stack:** Vanilla HTML/CSS/JS (no build step), Supabase (Postgres + RLS), `supabase db push` via CLI for migrations. Same stack as slices 1–2.

## Global Constraints

- **No new dependencies.** Vanilla JS only; no framework, no npm packages. (CLAUDE.md tech-stack rule.)
- **Only fake/sample data** ever goes in the repo or Supabase. (Compliance rule.)
- **RLS is the security backbone** — never rely on the UI to hide data. Every `cloud.js` read/write also self-scopes `tech_id = auth.uid()` as defense-in-depth. (Security posture.)
- **Home button `#logs` is NOT `admin-only`** — every signed-in tech has a diary. Button label exactly **"🗓️ Daily logs"**, class `home-btn`, matching "👤 My profile" / "🗓️ My visit history".
- **Never lose a tech's work:** the auto-stamp is best-effort — if it fails, `saveVisit()` still returns success for the visit itself. The diary is a record, never a gate.
- **Accessibility is required:** keep `aria-*`, `:focus-visible`, `prefers-reduced-motion`. Day buttons and month arrows have accessible names.
- **Escape all user/DB text** rendered into HTML with the existing `escHtml` / `escAttr` helpers (index.html:1743). Dates render via the existing `fmtDate` (index.html:1137) — passed **bare**, not escaped.
- **After shipping, bump SW cache** and tell the owner to hard-refresh (Ctrl+Shift+R) and fully reopen the PWA.
- **Stable item keys** are the join between a snapshot and the checklist — `done_keys` stores `ITEM_BY_KEY` keys (e.g. `rk-fridge-coils`), looked up at display time; unknown keys never crash (show under "Other" by raw key).

## Key codebase facts (verified in the current tree)

- `saveVisit(v, status)` lives at `cloud.js:154`. It receives `v.items` = `[{ key, done, answer, note, doneOn, value }]`, resolves the house via `housesByName.get(v.houseName.toLowerCase())`, and returns `{ visitId, degraded }` or `{ error }`. **`v.date` is a user-editable date input** (index.html:1550) — it defaults to today but the tech can change it, so it is NOT reliably "the day I saved." The auto stamp therefore uses the **client's current local date at save time** (`new Date().toISOString().slice(0,10)` — the same idiom the app already uses at index.html:1199), NOT `v.date`.
- `isMissingTable(error)` (cloud.js:206) already detects a not-yet-migrated table — reuse it so the app works before the migration is pushed.
- `window.cloud = { … }` export object is at `cloud.js:557`.
- The `#history` screen is the template: CSS visibility rule (`body:not([data-screen="history"]) #historyScreen`), a `home-btn`, a `.screen` div with `screen-head`/`menu-btn`/`data-nav-home`/`<h1>` and an inner body div, a `currentScreenFromHash()` branch, a `showScreen()` dispatch line, a home-button click handler, an async `render…Screen()` fn, and a delegated click handler on the body div. Slice 2's live at index.html:2766 (`renderHistoryScreen`) and 2817 (delegated handler).
- `GROUPS` (index.html:834) → `[{ label, cls, sections:[{ title, items:[{ key, text?, q?, bad?, … }] }] }]`. `ITEM_BY_KEY` (index.html:1121) maps `key` → the item object. An item's display label is `def.q || def.text`.
- Latest migration is `0015_profile_phone.sql`; this plan adds **`0016_daily_logs.sql`**.
- Current SW cache is `route-checklist-v16` (sw.js:7); this plan bumps to **v17**.

## File Structure

- **Create** `supabase/migrations/0016_daily_logs.sql` — the table, indexes, RLS policies, and one-time backfill. Self-contained; owns the entire data layer for this feature.
- **Modify** `route-checklist/cloud.js` — add the auto-stamp into `saveVisit()`, add `listLogsInRange` / `addLogEntry` / `updateLogEntry` / `deleteLogEntry`, export them.
- **Modify** `route-checklist/index.html` — CSS visibility rule, home button, `#logsScreen` markup, router + dispatch wiring, and the calendar render logic (`renderLogsScreen`, month-grid + day-detail helpers, delegated click handler). This file already holds all screens; follow that convention rather than splitting.
- **Modify** `route-checklist/sw.js` — bump `CACHE` to `v17`.
- **Modify** `route-checklist/HANDOFF.md` — new state section (final task).

---

## Task 1: Migration — `daily_logs` table, RLS, backfill

**Files:**
- Create: `supabase/migrations/0016_daily_logs.sql`

**Interfaces:**
- Produces: table `public.daily_logs (id, tech_id, log_date, kind, visit_id, house_id, note, done_keys, created_at, updated_at)`; partial unique index `daily_logs_auto_uniq (tech_id, visit_id, log_date) where kind='auto'`; RLS policies (select own-or-supervisor, insert own, update own, delete own).

- [ ] **Step 1: Write the migration file**

Create `supabase/migrations/0016_daily_logs.sql`:

```sql
-- ============================================================================
-- MTX Route Checklist — Daily Logs (slice 3 of 4)
-- A per-tech work diary. Auto rows are stamped by saveVisit() each day a tech
-- saves a visit; manual rows are free-text notes the tech adds to any day.
-- Spec: docs/superpowers/specs/2026-07-14-daily-logs-design.md
-- ============================================================================

create table if not exists public.daily_logs (
  id         uuid primary key default gen_random_uuid(),
  tech_id    uuid not null references public.profiles (id) on delete cascade
                default auth.uid(),
  log_date   date not null,
  kind       text not null check (kind in ('auto', 'manual')),
  visit_id   uuid references public.visits (id) on delete cascade,   -- auto only
  house_id   uuid references public.houses (id),                     -- auto only
  note       text not null default '',                               -- manual only
  done_keys  jsonb not null default '[]'::jsonb,                     -- auto only
  created_at timestamptz not null default now(),
  updated_at timestamptz not null default now()
);

-- One auto row per tech + visit + day: repeated Save-progress on the same day
-- refreshes that day's snapshot instead of duplicating it.
create unique index if not exists daily_logs_auto_uniq
  on public.daily_logs (tech_id, visit_id, log_date)
  where kind = 'auto';

-- The month view queries by tech + date range.
create index if not exists daily_logs_tech_date_idx
  on public.daily_logs (tech_id, log_date);

alter table public.daily_logs enable row level security;

-- Read: your own diary, or anything if you're a supervisor.
create policy daily_logs_select on public.daily_logs
  for select using (
    tech_id = auth.uid() or public.current_user_role() = 'supervisor'
  );

-- Insert: only rows you own.
create policy daily_logs_insert on public.daily_logs
  for insert with check (tech_id = auth.uid());

-- Update: only your own rows. Intentionally NOT restricted by `kind` — the
-- auto-stamp upsert resolves its conflict as an UPDATE of your own auto row and
-- must be allowed. User-facing immutability of auto rows is enforced in the app
-- (the UI shows no edit/delete on auto entries, and updateLogEntry/
-- deleteLogEntry self-scope kind='manual'). Ownership is the real boundary here.
create policy daily_logs_update on public.daily_logs
  for update using (tech_id = auth.uid()) with check (tech_id = auth.uid());

-- Delete: only your own rows.
create policy daily_logs_delete on public.daily_logs
  for delete using (tech_id = auth.uid());

-- ----------------------------------------------------------------------------
-- One-time backfill: one auto row per COMPLETED visit, on its visit_date, with
-- the final set of done item_keys. Runs as migration author (RLS bypassed).
-- ON CONFLICT DO NOTHING so re-running the migration is safe.
-- ----------------------------------------------------------------------------
insert into public.daily_logs (tech_id, log_date, kind, visit_id, house_id, done_keys)
select
  v.tech_id,
  v.visit_date,
  'auto',
  v.id,
  v.house_id,
  coalesce(
    (select jsonb_agg(vi.item_key)
       from public.visit_items vi
      where vi.visit_id = v.id and vi.done is true),
    '[]'::jsonb
  )
from public.visits v
where v.status = 'completed'
on conflict (tech_id, visit_id, log_date) where kind = 'auto' do nothing;
```

- [ ] **Step 2: Push the migration**

Run: `supabase db push`
Expected: applies `0016_daily_logs.sql`; no error. (If offline/unlinked, note it for the owner — the app degrades gracefully via `isMissingTable` until it's pushed.)

- [ ] **Step 3: Verify the table and backfill**

Run: `supabase db query --linked "select count(*) as backfilled from public.daily_logs where kind='auto';"`
Expected: a count ≥ the number of completed visits currently in the DB (0 is acceptable if there are none — the table exists, which is the point).

Run: `supabase db query --linked "select kind, count(*) from public.daily_logs group by kind;"`
Expected: runs cleanly; only `auto` rows so far (no manual yet).

- [ ] **Step 4: Commit**

```bash
git add supabase/migrations/0016_daily_logs.sql
git commit -m "feat: daily_logs table with RLS + completed-visit backfill (slice 3)"
```

---

## Task 2: `cloud.js` — auto-stamp inside `saveVisit()`

**Files:**
- Modify: `route-checklist/cloud.js` (inside `saveVisit`, before its final `return`, ~cloud.js:194)

**Interfaces:**
- Consumes: `daily_logs` table (Task 1); existing `saveVisit` locals `visitId`, `house` (the resolved house row), `v.items`; helper `isMissingTable` (cloud.js:206).
- Produces: an auto `daily_logs` row upserted on each successful visit save. No change to `saveVisit`'s return contract.

- [ ] **Step 1: Add the stamp helper above `saveVisit`**

Insert directly above `async function saveVisit` (cloud.js:154):

```js
// Stamp today's auto daily-log row for a saved visit. Best-effort: a failure
// here NEVER blocks the visit save (the diary is a record, not a gate). Uses
// the client's CURRENT local date — v.date is a user-editable field and may not
// be the actual save day, so a multi-day visit lands on each real workday.
async function stampDailyLog(visitId, houseId, items) {
  try {
    const { data: { user } } = await supabase.auth.getUser();
    if (!user) return;
    const doneKeys = (items || []).filter(it => it.done === true).map(it => it.key);
    const today = new Date().toISOString().slice(0, 10);
    const { error } = await supabase.from("daily_logs").upsert({
      tech_id: user.id, log_date: today, kind: "auto",
      visit_id: visitId, house_id: houseId, note: "", done_keys: doneKeys,
    }, { onConflict: "tech_id,visit_id,log_date" });
    if (error && !isMissingTable(error)) {
      console.warn("Daily-log stamp failed (visit still saved):", error.message);
    }
  } catch (e) {
    console.warn("Daily-log stamp threw (visit still saved):", e.message);
  }
}
```

- [ ] **Step 2: Call it from `saveVisit` before the final return**

In `saveVisit`, the success path currently ends (cloud.js:194):

```js
  return { visitId, degraded };
}
```

Change to:

```js
  await stampDailyLog(visitId, house.id, v.items);
  return { visitId, degraded };
}
```

(`house` is already in scope from cloud.js:155; the early `if (rows.length)` error path at cloud.js:192 returns before this, so a failed item-save is not stamped — correct.)

- [ ] **Step 3: Manual verification note (no unit test framework in repo)**

There is no test runner here (CLAUDE.md: "no automated tests yet"). Verify by reading the two edits back: confirm `stampDailyLog` is defined once, called once, `onConflict` string is `"tech_id,visit_id,log_date"`, and `doneKeys` maps `it.key` (not `it.item_key` — the app's local item shape uses `key`).

Run: `grep -n "stampDailyLog\|onConflict: \"tech_id,visit_id,log_date\"" route-checklist/cloud.js`
Expected: 3 lines — the definition, the call, and the onConflict inside the definition.

- [ ] **Step 4: Commit**

```bash
git add route-checklist/cloud.js
git commit -m "feat: stamp auto daily-log row on each visit save (best-effort)"
```

---

## Task 3: `cloud.js` — read + manual-entry functions

**Files:**
- Modify: `route-checklist/cloud.js` (add functions near the other slice reads, ~cloud.js:307; extend the export at cloud.js:557)

**Interfaces:**
- Consumes: `daily_logs` table (Task 1); `housesByName` cache is NOT needed (house name comes via the `houses(name)` join).
- Produces (exported on `window.cloud`):
  - `listLogsInRange(startDate, endDate)` → `Promise<{ id, logDate, kind, houseName, note, doneKeys }[]>` (own rows, `log_date` in `[start,end]` inclusive, ordered by `log_date`; `[]` on no-user/error).
  - `addLogEntry(logDate, note)` → `Promise<{ id } | { error }>` (inserts a manual row).
  - `updateLogEntry(id, note)` → `Promise<{ error }>` (self-scoped `tech_id=me AND kind='manual'`).
  - `deleteLogEntry(id)` → `Promise<{ error }>` (same self-scope).

- [ ] **Step 1: Add the four functions**

Insert after `getVisitDetail` (ends cloud.js:307):

```js
// Slice 3: the signed-in tech's own daily-log rows within a date range (one
// month per call). Self-scoped tech_id=me atop RLS. houseName comes from the
// joined house on auto rows (null on manual). Returns [] on no-user/error.
async function listLogsInRange(startDate, endDate) {
  const { data: { user } } = await supabase.auth.getUser();
  if (!user) return [];
  const { data, error } = await supabase
    .from("daily_logs")
    .select("id, log_date, kind, note, done_keys, houses(name)")
    .eq("tech_id", user.id)
    .gte("log_date", startDate).lte("log_date", endDate)
    .order("log_date", { ascending: true });
  if (error) { console.error("Could not list daily logs:", error.message); return []; }
  return data.map(r => ({
    id: r.id,
    logDate: r.log_date,
    kind: r.kind,
    houseName: r.houses?.name || "",
    note: r.note || "",
    doneKeys: Array.isArray(r.done_keys) ? r.done_keys : [],
  }));
}

// Add a manual free-text note to any day (today or a past day). Manual only.
async function addLogEntry(logDate, note) {
  const { data: { user } } = await supabase.auth.getUser();
  if (!user) return { error: "Not signed in." };
  const text = (note || "").trim();
  if (!text) return { error: "Note can't be empty." };
  const { data, error } = await supabase.from("daily_logs")
    .insert({ tech_id: user.id, log_date: logDate, kind: "manual", note: text })
    .select("id").single();
  if (error) { console.error("Could not add daily log:", error.message); return { error: error.message }; }
  return { id: data.id };
}

// Edit one of the caller's own MANUAL notes. kind='manual' guard blocks any
// attempt to alter an auto row even though RLS would permit an owned-row update.
async function updateLogEntry(id, note) {
  const { data: { user } } = await supabase.auth.getUser();
  if (!user) return { error: "Not signed in." };
  const text = (note || "").trim();
  if (!text) return { error: "Note can't be empty." };
  const { error } = await supabase.from("daily_logs")
    .update({ note: text, updated_at: new Date().toISOString() })
    .eq("id", id).eq("tech_id", user.id).eq("kind", "manual");
  if (error) { console.error("Could not update daily log:", error.message); return { error: error.message }; }
  return { error: null };
}

// Delete one of the caller's own MANUAL notes. Same manual-only self-scope.
async function deleteLogEntry(id) {
  const { data: { user } } = await supabase.auth.getUser();
  if (!user) return { error: "Not signed in." };
  const { error } = await supabase.from("daily_logs")
    .delete().eq("id", id).eq("tech_id", user.id).eq("kind", "manual");
  if (error) { console.error("Could not delete daily log:", error.message); return { error: error.message }; }
  return { error: null };
}
```

- [ ] **Step 2: Export them**

At cloud.js:564, the export currently includes:

```js
                 listMyVisits, getVisitDetail,
```

Add the new functions right after that line:

```js
                 listMyVisits, getVisitDetail,
                 listLogsInRange, addLogEntry, updateLogEntry, deleteLogEntry,
```

- [ ] **Step 3: Verify wiring**

Run: `grep -n "listLogsInRange\|addLogEntry\|updateLogEntry\|deleteLogEntry" route-checklist/cloud.js`
Expected: 8 matches — each of the 4 defined once and exported once.

- [ ] **Step 4: Commit**

```bash
git add route-checklist/cloud.js
git commit -m "feat: cloud.js daily-log read + manual-note CRUD (slice 3)"
```

---

## Task 4: `index.html` — reachable `#logs` screen shell

**Files:**
- Modify: `route-checklist/index.html` (CSS rule ~485; home button ~732; screen markup ~765; router ~2550; dispatch ~2565; home-button handler ~2595; stub render fn ~2766)

**Interfaces:**
- Consumes: existing `#history` wiring as the copy-template; `currentScreenFromHash()`, `showScreen()`.
- Produces: a reachable, empty `#logs` screen with a `renderLogsScreen()` stub that shows "Loading…". No data yet (Task 5).

This task mirrors slice 2's Task 3 exactly. Each edit is additive.

- [ ] **Step 1: CSS visibility rule**

Find `body:not([data-screen="history"])  #historyScreen,` (index.html ~486) and insert after it:

```css
  body:not([data-screen="logs"])     #logsScreen,
```

- [ ] **Step 2: Home button**

Find the `homeHistory` button (index.html ~732):

```html
  <button type="button" class="home-btn" id="homeHistory">🗓️ My visit history
    <small>Your completed visits</small></button>
```

Insert directly after it:

```html
  <button type="button" class="home-btn" id="homeLogs">🗓️ Daily logs
    <small>Your workday calendar</small></button>
```

- [ ] **Step 3: Screen markup**

Find the `#historyScreen` div (index.html ~765) and its closing `</div>`. Insert a new screen directly after it, before the next screen:

```html
<div id="logsScreen" class="screen" aria-label="Daily logs">
  <div class="screen-head">
    <button type="button" class="menu-btn" data-nav-home aria-label="Back to home">← Home</button>
    <h1>Daily Logs</h1>
  </div>
  <div id="logsBody"></div>
</div>
```

- [ ] **Step 4: Hash router**

Find in `currentScreenFromHash()` (index.html ~2550):

```js
    if (h.startsWith("#history")) return "history";
```

Insert after it:

```js
    if (h.startsWith("#logs")) return "logs";
```

- [ ] **Step 5: `showScreen()` dispatch**

Find (index.html ~2565):

```js
    if (scr === "history") renderHistoryScreen();
```

Insert after it:

```js
    if (scr === "logs") renderLogsScreen();
```

- [ ] **Step 6: Home-button click handler**

Find the `homeHistory` handler (index.html ~2595, added in slice 2):

```js
  document.getElementById("homeHistory").addEventListener("click", () => {
    location.hash = "#history";
  });
```

Insert after it:

```js
  document.getElementById("homeLogs").addEventListener("click", () => {
    location.hash = "#logs";
  });
```

- [ ] **Step 7: Stub render function**

Insert after `renderHistoryScreen`/`renderVisitDetail` block (after index.html ~2815, before the `historyBody` click handler at ~2817):

```js
  async function renderLogsScreen() {
    document.getElementById("logsBody").innerHTML = `<p class="screen-sub">Loading…</p>`;
  }
```

- [ ] **Step 8: Verify static wiring**

Run: `grep -n "homeLogs\|logsScreen\|logsBody\|renderLogsScreen\|#logs\|data-screen=\"logs\"" route-checklist/index.html`
Expected: ≥8 matches (CSS rule, home button, screen div, body div, router branch, dispatch, handler, stub fn).

- [ ] **Step 9: Commit**

```bash
git add route-checklist/index.html
git commit -m "feat: add reachable #logs screen shell (button, markup, routing)"
```

---

## Task 5: `index.html` — month grid + day detail render

**Files:**
- Modify: `route-checklist/index.html` (replace the `renderLogsScreen` stub from Task 4; add helper fns + a delegated click handler on `#logsBody`; add CSS for the grid)

**Interfaces:**
- Consumes: `window.cloud.listLogsInRange`, `addLogEntry`, `updateLogEntry`, `deleteLogEntry` (Task 3); `GROUPS`, `ITEM_BY_KEY` (index.html:834/1121); `fmtDate`, `escHtml`, `escAttr`.
- Produces: a working calendar. State held in two module-scoped vars (declared with the render fn): `logsMonth` (a `Date` at the 1st of the shown month) and `logsSelectedDate` (`"YYYY-MM-DD"` or null).

Behavior contract:
- Default month = current month. `‹`/`›` change month and re-query.
- Day cell: house name if any auto row that day (truncated, full name in `title`); else "Daily log" if only manual rows; else plain number. Today highlighted.
- Tap a day with activity → detail opens below: per-section `"<House> — <section>: n/m done (+k today)"` + the list of items finished THAT day (cumulative snapshot minus the previous auto row's snapshot for the same visit), then manual notes (each with Edit/Delete), then "+ Add note".
- "+ Add note" works on any selected day (past included). After any add/edit/delete, re-query the month and re-render.
- Unknown `done_keys` entries (not in `ITEM_BY_KEY`) list under an "Other" section by raw key.

- [ ] **Step 1: Add grid CSS**

Near the other screen styles (after the `.hist-item` rules from slice 2; find them with `grep -n "hist-item" route-checklist/index.html` and insert after that block):

```css
  .cal-head { display:flex; align-items:center; justify-content:space-between; margin:.25rem 0 .5rem; }
  .cal-head h2 { font-size:1rem; margin:0; }
  .cal-nav { background:none; border:1px solid var(--line,#ccc); border-radius:.4rem; font-size:1.1rem; line-height:1; padding:.25rem .6rem; cursor:pointer; }
  .cal-grid { display:grid; grid-template-columns:repeat(7,1fr); gap:2px; }
  .cal-dow { text-align:center; font-size:.7rem; opacity:.7; padding:.2rem 0; }
  .cal-day { min-height:3.2rem; border:1px solid var(--line,#e2e2e2); border-radius:.35rem; padding:.2rem; font-size:.75rem; background:none; text-align:left; overflow:hidden; }
  .cal-day.empty { border:none; }
  .cal-day.has-activity { cursor:pointer; }
  .cal-day.today { outline:2px solid var(--accent,#2a6); outline-offset:-2px; }
  .cal-day.selected { background:var(--accent-soft,#e6f4ec); }
  .cal-daynum { font-weight:600; display:block; }
  .cal-daylabel { display:block; white-space:nowrap; overflow:hidden; text-overflow:ellipsis; opacity:.85; }
  .cal-detail { margin-top:1rem; }
  .cal-detail h3 { font-size:.95rem; margin:.6rem 0 .2rem; }
  .cal-note { display:flex; gap:.5rem; align-items:start; margin:.3rem 0; }
  .cal-note p { margin:0; flex:1; }
  @media (prefers-reduced-motion: reduce) { .cal-day { transition:none; } }
```

(If `--accent`/`--line` vars don't exist, the fallbacks after the comma apply — verify with `grep -n "\-\-accent" route-checklist/index.html` and match an existing var name if the codebase uses a different one.)

- [ ] **Step 2: Replace the `renderLogsScreen` stub with the real render + helpers**

Replace the stub from Task 4 with:

```js
  let logsMonth = startOfMonth(new Date());
  let logsSelectedDate = null;
  let logsMonthRows = [];   // the last month's rows — needed by the per-day diff

  function startOfMonth(d) { return new Date(d.getFullYear(), d.getMonth(), 1); }
  function isoDate(d) { return `${d.getFullYear()}-${String(d.getMonth()+1).padStart(2,"0")}-${String(d.getDate()).padStart(2,"0")}`; }

  async function renderLogsScreen() {
    const body = document.getElementById("logsBody");
    body.innerHTML = `<p class="screen-sub">Loading…</p>`;
    const first = logsMonth;
    const last = new Date(first.getFullYear(), first.getMonth()+1, 0);
    const rows = await window.cloud.listLogsInRange(isoDate(first), isoDate(last));
    if (currentScreenFromHash() !== "logs") return;   // navigated away meanwhile
    logsMonthRows = rows;   // stash for renderDayDetail's diff
    // Group rows by day.
    const byDay = {};
    rows.forEach(r => { (byDay[r.logDate] = byDay[r.logDate] || []).push(r); });
    body.innerHTML = renderCalHead(first) + renderGrid(first, last, byDay)
      + (logsSelectedDate ? renderDayDetail(logsSelectedDate, byDay[logsSelectedDate] || []) : "");
  }

  function renderCalHead(first) {
    const label = first.toLocaleDateString(undefined, { month:"long", year:"numeric" });
    return `<div class="cal-head">
      <button type="button" class="cal-nav" data-cal-prev aria-label="Previous month">‹</button>
      <h2>${escHtml(label)}</h2>
      <button type="button" class="cal-nav" data-cal-next aria-label="Next month">›</button>
    </div>`;
  }

  function renderGrid(first, last, byDay) {
    const dow = ["Su","Mo","Tu","We","Th","Fr","Sa"];
    const cells = dow.map(d => `<div class="cal-dow">${d}</div>`);
    for (let i = 0; i < first.getDay(); i++) cells.push(`<div class="cal-day empty"></div>`);
    const todayIso = isoDate(new Date());
    for (let day = 1; day <= last.getDate(); day++) {
      const iso = isoDate(new Date(first.getFullYear(), first.getMonth(), day));
      const dayRows = byDay[iso] || [];
      const auto = dayRows.find(r => r.kind === "auto");
      const hasManual = dayRows.some(r => r.kind === "manual");
      const active = dayRows.length > 0;
      let label = "", aria = `${iso}, no activity`;
      if (auto) { label = auto.houseName || "Visit"; aria = `${iso}, worked at ${label}`; }
      else if (hasManual) { label = "Daily log"; aria = `${iso}, daily log`; }
      const cls = ["cal-day", active ? "has-activity" : "",
        iso === todayIso ? "today" : "", iso === logsSelectedDate ? "selected" : ""].join(" ").trim();
      const tag = active ? "button" : "div";
      const attrs = active ? `type="button" data-cal-day="${escAttr(iso)}" aria-label="${escAttr(aria)}" title="${escAttr(label)}"` : "";
      cells.push(`<${tag} class="${cls}" ${attrs}>
        <span class="cal-daynum">${day}</span>
        <span class="cal-daylabel">${escHtml(label)}</span></${tag}>`);
    }
    return `<div class="cal-grid" role="grid">${cells.join("")}</div>`;
  }
```

- [ ] **Step 3: Add the day-detail + diff helpers (same script block)**

```js
  // Items finished on THIS day = this day's auto snapshot minus the previous
  // auto row's snapshot for the SAME visit (most recent earlier day). No prior
  // row → everything checked counts as finished today.
  function finishedToday(auto, monthRows) {
    if (!auto) return [];
    const prior = monthRows
      .filter(r => r.kind === "auto" && r.houseName === auto.houseName && r.logDate < auto.logDate)
      .sort((a, b) => a.logDate < b.logDate ? 1 : -1)[0];
    const prev = new Set(prior ? prior.doneKeys : []);
    return auto.doneKeys.filter(k => !prev.has(k));
  }

  // Section-by-section summary for an auto entry: "n/m done (+k today)" + the
  // today-list. Uses GROUPS/ITEM_BY_KEY; unknown keys go under "Other".
  function renderAutoDetail(auto, monthRows) {
    const today = new Set(finishedToday(auto, monthRows));
    const doneSet = new Set(auto.doneKeys);
    let html = "";
    GROUPS.forEach(g => g.sections.forEach(sec => {
      const keys = sec.items.map(it => it.key);
      const doneInSec = keys.filter(k => doneSet.has(k));
      const todayInSec = keys.filter(k => today.has(k));
      if (!doneInSec.length && !todayInSec.length) return;
      const plus = todayInSec.length ? ` (+${todayInSec.length} today)` : "";
      html += `<h3>${escHtml(sec.title)} — ${doneInSec.length}/${keys.length} done${plus}</h3>`;
      const list = todayInSec.length ? todayInSec : doneInSec;
      html += list.map(k => {
        const def = ITEM_BY_KEY[k];
        return `<div class="hist-item">✓ ${escHtml(def ? (def.q || def.text) : k)}</div>`;
      }).join("");
    }));
    // Unknown keys (checklist changed since the visit).
    const unknown = auto.doneKeys.filter(k => !ITEM_BY_KEY[k]);
    if (unknown.length) {
      html += `<h3>Other</h3>` + unknown.map(k => `<div class="hist-item">✓ ${escHtml(k)}</div>`).join("");
    }
    return `<h2 style="font-size:1rem">${escHtml(auto.houseName || "Visit")}</h2>` + html;
  }

  function renderDayDetail(iso, dayRows) {
    // The per-day diff needs the WHOLE month's rows (to find the prior auto
    // snapshot for the same visit), not just this day's — so use the month
    // stash set in renderLogsScreen, not dayRows.
    const monthRows = logsMonthRows;
    const auto = dayRows.find(r => r.kind === "auto");
    const manual = dayRows.filter(r => r.kind === "manual");
    let html = `<div class="cal-detail"><h2 style="font-size:1rem">${escHtml(fmtDate(iso))}</h2>`;
    if (auto) html += renderAutoDetail(auto, monthRows);
    html += manual.map(m => `<div class="cal-note" data-note-id="${escAttr(m.id)}">
      <p>${escHtml(m.note)}</p>
      <button type="button" class="menu-btn" data-note-edit="${escAttr(m.id)}" aria-label="Edit note">Edit</button>
      <button type="button" class="menu-btn" data-note-del="${escAttr(m.id)}" aria-label="Delete note">Delete</button>
    </div>`).join("");
    html += `<div class="cal-note"><textarea id="calNoteInput" rows="2" aria-label="New note for ${escAttr(fmtDate(iso))}" placeholder="Add a note for this day…"></textarea>
      <button type="button" class="menu-btn" data-note-add aria-label="Save note">+ Add note</button></div>`;
    return html + `</div>`;
  }
```

(`logsMonthRows` is declared and populated in Step 2 — no extra wiring here.)

- [ ] **Step 4: Add the delegated click/handler for `#logsBody`**

Add after the render helpers (mirrors the `historyBody` handler at index.html:2817):

```js
  document.getElementById("logsBody").addEventListener("click", async e => {
    if (e.target.closest("[data-cal-prev]")) {
      logsMonth = new Date(logsMonth.getFullYear(), logsMonth.getMonth()-1, 1);
      logsSelectedDate = null; return renderLogsScreen();
    }
    if (e.target.closest("[data-cal-next]")) {
      logsMonth = new Date(logsMonth.getFullYear(), logsMonth.getMonth()+1, 1);
      logsSelectedDate = null; return renderLogsScreen();
    }
    const dayBtn = e.target.closest("[data-cal-day]");
    if (dayBtn) { logsSelectedDate = dayBtn.dataset.calDay; return renderLogsScreen(); }

    const addBtn = e.target.closest("[data-note-add]");
    if (addBtn) {
      const val = document.getElementById("calNoteInput").value;
      if (!val.trim()) return;
      const res = await window.cloud.addLogEntry(logsSelectedDate, val);
      if (res.error) { alert(res.error); return; }
      return renderLogsScreen();
    }
    const delBtn = e.target.closest("[data-note-del]");
    if (delBtn) {
      if (!confirm("Delete this note?")) return;
      const res = await window.cloud.deleteLogEntry(delBtn.dataset.noteDel);
      if (res.error) { alert(res.error); return; }
      return renderLogsScreen();
    }
    const editBtn = e.target.closest("[data-note-edit]");
    if (editBtn) {
      const row = editBtn.closest("[data-note-id]");
      const current = row.querySelector("p").textContent;
      const next = prompt("Edit note:", current);
      if (next == null || !next.trim()) return;
      const res = await window.cloud.updateLogEntry(editBtn.dataset.noteEdit, next);
      if (res.error) { alert(res.error); return; }
      return renderLogsScreen();
    }
  });
```

- [ ] **Step 5: Verify wiring**

Run: `grep -n "renderLogsScreen\|renderGrid\|renderDayDetail\|finishedToday\|data-cal-day\|data-note-add" route-checklist/index.html`
Expected: each helper defined; `data-cal-day` and `data-note-add` appear in both a render fn and the handler.

- [ ] **Step 6: Structural sanity re-read**

Read the whole new block back. Confirm: `logsMonth`, `logsSelectedDate`, `logsMonthRows` declared once; every `<button>`/`<div>`/`<textarea>` opened is closed; no leftover stub `renderLogsScreen`.

- [ ] **Step 7: Commit**

```bash
git add route-checklist/index.html
git commit -m "feat: daily-logs month grid + day detail with per-day diff (slice 3)"
```

---

## Task 6: SW bump + live end-to-end verification

**Files:**
- Modify: `route-checklist/sw.js:7`
- Modify: `route-checklist/HANDOFF.md`

- [ ] **Step 1: Bump the cache version**

In `route-checklist/sw.js:7`, change:

```js
const CACHE = "route-checklist-v16";
```
to:
```js
const CACHE = "route-checklist-v17";
```

- [ ] **Step 2: Commit the bump**

```bash
git add route-checklist/sw.js
git commit -m "chore: bump SW cache to v17 for daily logs screen"
```

- [ ] **Step 3: Live verification (owner-driven; document results)**

After deploy + hard-refresh (Ctrl+Shift+R), run the spec's verification list:
1. Sign in `tech1@example.com` → open "🗓️ Daily logs" → current month renders; backfilled dots on past completed-visit dates.
2. Start a visit, **Save progress** → today's cell shows the house name; tap it → sections/items finished so far are listed.
3. Save progress **again same day** → list grows, still exactly one auto entry (no duplicate). If across two days, day 2 shows only day-2 items.
4. Add a manual note to today and to a past day; edit one; delete one → each re-renders; month updates.
5. Sign in `tech2@example.com` → sees only their own diary (isolation).
6. Deep-link reload on `#logs` → re-renders, no console errors.
7. `supabase db query --linked "select log_date, kind, house_id, done_keys from public.daily_logs order by log_date desc limit 5;"` → rows present.

- [ ] **Step 4: Update HANDOFF.md**

Add a new "STATE AS OF 2026-07-14 (Daily Logs — slice 3 of 4)" section at the top of `route-checklist/HANDOFF.md` summarizing: the `daily_logs` table + migration 0016, RLS (own + supervisor-read; ownership-only update policy with app-layer manual-only guard), the `cloud.js` auto-stamp (uses client local date, best-effort) + 4 new functions, the `#logs` month-grid screen (house name / "Daily log" cells, per-day diff detail, manual-note CRUD, backfill of completed visits), SW `v16→v17`, out-of-scope items, and the not-yet-live-verified caveat with the test steps above.

- [ ] **Step 5: Commit**

```bash
git add route-checklist/HANDOFF.md
git commit -m "docs: HANDOFF entry for Daily Logs screen (slice 3 of 4)"
```

---

## Self-Review

**Spec coverage:**
- `daily_logs` table + all columns + partial unique index + `tech_date` index → Task 1 ✅
- RLS (select own-or-supervisor, insert/update/delete own; ownership-only update policy with the app-layer manual-only guard reasoning) → Task 1 ✅
- Backfill of completed visits → Task 1 ✅
- Auto-stamp in `saveVisit`, best-effort, client-local-date (NOT `v.date`), upsert on conflict → Task 2 ✅
- `listLogsInRange` / `addLogEntry` / `updateLogEntry` / `deleteLogEntry` self-scoped → Task 3 ✅
- `#logs` screen, home button (not admin-only, exact label), router pattern → Task 4 ✅
- Month grid; house-name / "Daily log" / plain cells; today highlight; `‹`/`›` → Task 5 ✅
- Day detail: per-section `n/m done (+k today)` + today-list via cumulative-minus-prior diff → Task 5 (`finishedToday`, `renderAutoDetail`) ✅
- Manual notes list + Edit/Delete + "+ Add note" on any day (backfill) → Task 5 ✅
- Unknown item_key → "Other" by raw key → Task 5 ✅
- Accessibility (aria-labels on days/arrows, focus, reduced-motion) → Task 5 CSS + markup ✅
- SW v16→v17 → Task 6 ✅
- Verification list → Task 6 ✅

**Placeholder scan:** No TBD/TODO; every code step shows full code. The one "verify against existing var name" note (accent CSS var) is a concrete grep instruction, not a placeholder.

**Type consistency:** `listLogsInRange` returns `{ id, logDate, kind, houseName, note, doneKeys }` — consumed with those exact names in `renderGrid`/`finishedToday`/`renderAutoDetail`/`renderDayDetail`. `doneKeys` is an array throughout. `it.key` (not `item_key`) used for the local visit-item shape in Task 2 (matches index.html:1826 `key`), while DB rows use `item_key` in Task 1's backfill (correct — that's the DB column). Auto-stamp `onConflict` target matches the unique index columns exactly.
