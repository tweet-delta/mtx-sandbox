# Home Screen, House Notes & Collapsed Sections Implementation Plan

> **For agentic workers:** REQUIRED SUB-SKILL: Use superpowers:subagent-driven-development (recommended) or superpowers:executing-plans to implement this plan task-by-task. Steps use checkbox (`- [ ]`) syntax for tracking.

**Goal:** After login the app opens on a Home screen (New house visit / Continue house visit / House notes), checklist sections start collapsed everywhere, and a House Notes page lets techs suggest freeform-note updates that the owner's supervisor account approves.

**Architecture:** All screens live inside the existing single `route-checklist/index.html`, switched by a tiny URL-hash router (`#home` / `#visit` / `#continue` / `#notes/<house>`) — the same "one file, layers shown/hidden" pattern the login gate already uses. Supabase gets one new migration (a `general_notes` column on `houses` plus a `house_note_suggestions` table with RLS and an atomic approve function). `cloud.js` grows a small notes/role/list API; `index.html` never talks to Supabase directly.

**Tech Stack:** Vanilla HTML/CSS/JS (no build step, no new dependencies), Supabase (Postgres + RLS + RPC), service worker unchanged in strategy.

**Spec:** `docs/superpowers/specs/2026-07-10-home-screen-house-notes-design.md`

## Global Constraints

- **This repo is PUBLIC.** No secrets, no real door/med-lock codes, no resident-adjacent data in any tracked file. The pre-commit secret guard must stay passing.
- **No new dependencies, no build step.** Vanilla JS only; `cloud.js` stays the only module and the only file that imports Supabase.
- **Never lose a tech's in-progress work.** Navigation must not clear the localStorage buffer; destructive transitions go through the existing `selectHouse()` confirm.
- **Accessibility:** keep/extend `aria-*`, `:focus-visible`, `prefers-reduced-motion`; touch targets ≥ 44px; text inputs on phone use `font-size: 16px` (stops iOS zoom).
- **SQL is applied by the OWNER by hand** in the Supabase dashboard. Hand SQL as a chat code block or a real file — never as terminal output. Verify afterwards with a `select count(*)`.
- **No automated test framework exists.** Verification = headless-Chrome DOM checks where scriptable, plus driving the real app in a browser. Do not claim a flow works without driving it.
- **Do NOT `git push`.** The owner asked to review locally first. Commit per task; never push.
- **Do not touch** the pre-existing uncommitted changes in the working tree (`house-data.js`, `scripts/pre-commit-secret-guard.sh`, `supabase/migrations/0004_more_houses.sql`, `0005_more_houses.sql`). Stage only the files each task names.
- Headless Chrome binary: `"/c/Program Files/Google/Chrome/Application/chrome.exe"` (Git Bash path form). App URL with encoded spaces: `file:///C:/Big%20Dogs%20Apps/MTX%20Checklist%20V1/route-checklist/index.html`.

---

### Task 1: Checklist sections start collapsed

**Files:**
- Modify: `route-checklist/index.html:946` and `route-checklist/index.html:1032`

**Interfaces:**
- Consumes: nothing.
- Produces: no API change. All `<details class="section">` render WITHOUT the `open` attribute; per-section progress counts still render (they are filled by `refresh()`, independent of open state).

- [ ] **Step 1: Remove the hardcoded `open` attributes**

In `build()` (index.html line 946), change:

```js
        html += `<details class="section" data-g="${g}" data-s="${s}" open>
```

to:

```js
        html += `<details class="section" data-g="${g}" data-s="${s}">
```

And for the Alarm Counts section (line 1032), change:

```js
          html += `<details class="section" id="alarmCounts" open>
```

to:

```js
          html += `<details class="section" id="alarmCounts">
```

- [ ] **Step 2: Verify via headless Chrome**

Run (Bash):

```bash
CHROME="/c/Program Files/Google/Chrome/Application/chrome.exe"
"$CHROME" --headless=new --disable-gpu --virtual-time-budget=4000 --dump-dom \
  "file:///C:/Big%20Dogs%20Apps/MTX%20Checklist%20V1/route-checklist/index.html" > /tmp/dom.html
grep -c '<details class="section"' /tmp/dom.html          # expect: 15 (14 checklist sections + alarm counts)
grep -c '<details class="section"[^>]* open' /tmp/dom.html # expect: 0
```

Expected: first grep ≥ 14, second grep exactly `0`. (The set-password `<details class="setpw">` in the sidebar is not a `.section` and is unaffected.)

- [ ] **Step 3: Verify by hand in a real browser**

Open `route-checklist/index.html` in Chrome. Confirm: every section (including Alarm Counts) starts closed; tapping a summary opens it; progress counts (e.g. `0/11`) show on closed sections; checking items inside still updates counts and the top progress bar.

- [ ] **Step 4: Commit**

```bash
cd "/c/Big Dogs Apps/MTX Checklist V1"
git add route-checklist/index.html
git commit -m "Checklist sections start collapsed on all devices

Co-Authored-By: Claude Fable 5 <noreply@anthropic.com>"
```

---

### Task 2: Migration 0006 — general notes, suggestions table, atomic approve

**Files:**
- Create: `supabase/migrations/0006_house_notes.sql`

**Interfaces:**
- Consumes: `public.houses`, `public.profiles`, `public.current_user_role()` (all from `0001_init.sql`).
- Produces (used by Task 3's cloud functions):
  - `houses.general_notes text not null default ''`
  - table `public.house_note_suggestions(id uuid, house_id uuid, author_id uuid, author_name text, proposed_text text, status text 'pending'|'approved'|'dismissed', created_at timestamptz, reviewed_by uuid null, reviewed_at timestamptz null)`
  - RPC `public.approve_note_suggestion(suggestion_id uuid) returns void` — supervisor-only, atomic.
  - RLS: any authenticated user selects all suggestions and inserts own; author deletes own while `pending`; only supervisors update.

- [ ] **Step 1: Write the migration file**

Create `supabase/migrations/0006_house_notes.sql` with exactly:

```sql
-- ============================================================================
-- 0006_house_notes.sql — House Notes: freeform general notes + suggest/approve
--
-- Adds:
--   1. houses.general_notes — the OFFICIAL freeform note per house.
--   2. house_note_suggestions — a tech's proposed replacement text. The
--      original note is untouched until a supervisor approves. Reviewed rows
--      are kept (status approved/dismissed) as an audit trail.
--   3. approve_note_suggestion(uuid) — supervisor-only, atomic: copies the
--      proposed text into houses.general_notes AND marks the suggestion
--      approved in one transaction, so a dropped connection can't half-apply.
--
-- Safe to re-run (create-if-not-exists / drop-policy-if-exists throughout).
-- ============================================================================

-- 1. The official note lives on the house row itself.
alter table public.houses
  add column if not exists general_notes text not null default '';

-- 2. Proposed updates. author_name is denormalized on purpose: RLS lets a
--    tech read only their OWN profiles row, so a join to profiles would show
--    blank names to other techs. Snapshotting the name at insert time is
--    simpler and doubles as history (name at the time of writing).
create table if not exists public.house_note_suggestions (
  id            uuid primary key default gen_random_uuid(),
  house_id      uuid not null references public.houses (id) on delete cascade,
  author_id     uuid not null references public.profiles (id) default auth.uid(),
  author_name   text not null default '',
  proposed_text text not null,
  status        text not null default 'pending'
                check (status in ('pending', 'approved', 'dismissed')),
  created_at    timestamptz not null default now(),
  reviewed_by   uuid references public.profiles (id),
  reviewed_at   timestamptz
);
create index if not exists hns_house_status_idx
  on public.house_note_suggestions (house_id, status);

-- 3. RLS: the database enforces who can do what — the UI only *hides* things.
alter table public.house_note_suggestions enable row level security;

-- Everyone signed in sees all suggestions (so techs don't re-suggest the
-- same fix someone already proposed).
drop policy if exists hns_select on public.house_note_suggestions;
create policy hns_select on public.house_note_suggestions
  for select to authenticated using (true);

-- You can only file suggestions as yourself.
drop policy if exists hns_insert on public.house_note_suggestions;
create policy hns_insert on public.house_note_suggestions
  for insert to authenticated
  with check (author_id = auth.uid());

-- You can withdraw (delete) your own suggestion while it's still pending.
drop policy if exists hns_delete_own_pending on public.house_note_suggestions;
create policy hns_delete_own_pending on public.house_note_suggestions
  for delete to authenticated
  using (author_id = auth.uid() and status = 'pending');

-- Only supervisors change suggestion rows (approve/dismiss set status +
-- reviewed_by/reviewed_at).
drop policy if exists hns_update_supervisor on public.house_note_suggestions;
create policy hns_update_supervisor on public.house_note_suggestions
  for update to authenticated
  using (public.current_user_role() = 'supervisor')
  with check (public.current_user_role() = 'supervisor');

-- Auto-expose is OFF in this project, so grant table access explicitly.
-- (RLS above still decides which ROWS each person can touch.)
grant select, insert, update, delete
  on public.house_note_suggestions to authenticated;

-- 4. Atomic approve. SECURITY DEFINER so it can update houses + the
--    suggestion in one transaction; it re-checks the caller's role itself,
--    so it grants nothing to non-supervisors.
create or replace function public.approve_note_suggestion(suggestion_id uuid)
returns void
language plpgsql
security definer set search_path = public
as $$
declare
  s public.house_note_suggestions%rowtype;
begin
  if public.current_user_role() is distinct from 'supervisor' then
    raise exception 'Only a supervisor can approve suggestions';
  end if;
  select * into s from public.house_note_suggestions
    where id = suggestion_id and status = 'pending'
    for update;
  if not found then
    raise exception 'Suggestion not found or already reviewed';
  end if;
  update public.houses
    set general_notes = s.proposed_text
    where id = s.house_id;
  update public.house_note_suggestions
    set status = 'approved', reviewed_by = auth.uid(), reviewed_at = now()
    where id = suggestion_id;
end;
$$;

revoke execute on function public.approve_note_suggestion(uuid) from public, anon;
grant  execute on function public.approve_note_suggestion(uuid) to authenticated;
```

- [ ] **Step 2: Sanity-check the SQL file**

Run: `grep -c "create policy\|drop policy" supabase/migrations/0006_house_notes.sql`
Expected: `8` (4 drop + 4 create). Also visually confirm the first line of the file is the `-- ===` comment (the owner copies by hand; a stray shell prompt on line 1 has burned us twice).

- [ ] **Step 3: Commit**

```bash
cd "/c/Big Dogs Apps/MTX Checklist V1"
git add supabase/migrations/0006_house_notes.sql
git commit -m "Migration 0006: house general notes + suggest/approve table, RLS, atomic approve fn

Co-Authored-By: Claude Fable 5 <noreply@anthropic.com>"
```

- [ ] **Step 4: CHECKPOINT — hand the owner the SQL (blocks live verification of Tasks 3–5)**

Give the owner, **as chat code blocks** (never terminal output):
1. The full contents of `supabase/migrations/0006_house_notes.sql`, with the reminder to check the first visible line says `-- ===...` before pressing Run.
2. The supervisor promotion one-liner (their account already exists):

```sql
update public.profiles set role = 'supervisor'
where id = (select id from auth.users where email = 'hfwinter16@gmail.com');
```

3. Verification queries — expected results noted:

```sql
select count(*) from public.house_note_suggestions;                      -- expect 0
select count(*) from public.houses where general_notes is not null;     -- expect 29
select role from public.profiles
  where id = (select id from auth.users where email = 'hfwinter16@gmail.com'); -- expect supervisor
```

Code tasks 3–5 may proceed before the owner runs this (the cloud layer degrades gracefully), but the end-to-end verification in Task 6 requires it applied.

---

### Task 3: cloud.js — role, in-progress list, house-notes API

**Files:**
- Modify: `route-checklist/cloud.js` (add functions near the existing visit-history block, lines 56–184; extend `window.cloud` at line 184; extend `onAuthStateChange` at line 226)

**Interfaces:**
- Consumes: migration 0006 objects (Task 2); existing `supabase`, `housesByName`, `isMissingColumn()`.
- Produces (consumed by Tasks 4–5 via `window.cloud`):
  - `window.cloud.role` — `null` until loaded, then `"tech"` or `"supervisor"`. Also sets/clears `document.body.classList "is-admin"`.
  - `listInProgress() → Promise<Array<{visitId, houseName, date, itemCount}> | null>` — the signed-in tech's in-progress visits, newest first; `null` means "cloud unreachable" (distinct from `[]` = none).
  - `getHouseNotes(houseName) → Promise<{generalNotes, suggestions, notReady?} | {error}>` where `suggestions` is `Array<{id, authorName, text, createdAt, mine}>` (pending only, newest first). `notReady: true` means migration 0006 isn't applied yet.
  - `suggestNote(houseName, text, authorName) → Promise<{ok?: true, error?: string}>`
  - `withdrawSuggestion(id) → Promise<{ok?: true, error?: string}>`
  - `approveSuggestion(id) → Promise<{ok?: true, error?: string}>` (calls the RPC)
  - `dismissSuggestion(id) → Promise<{ok?: true, error?: string}>`
  - `saveGeneralNotes(houseName, text) → Promise<{ok?: true, error?: string}>` (supervisor direct edit)

- [ ] **Step 1: Add the role loader**

In `cloud.js`, insert after the `loadHouses()` function (after line 54):

```js
// ---- Who am I? (role gates the admin controls; RLS is the real enforcement) ----
async function loadRole() {
  window.cloud.role = null;
  const { data: { user } } = await supabase.auth.getUser();
  if (!user) return;
  const { data, error } = await supabase
    .from("profiles").select("role").eq("id", user.id).maybeSingle();
  if (error) { console.error("Could not load role:", error.message); return; }
  window.cloud.role = data?.role || "tech";
  document.body.classList.toggle("is-admin", window.cloud.role === "supervisor");
}
```

And in the `onAuthStateChange` handler (line 226–235), load it alongside houses and clear it on sign-out:

```js
supabase.auth.onAuthStateChange((_event, session) => {
  if (session) {
    showGate(false);
    if (whoami) whoami.textContent = session.user.email;
    setTimeout(() => { loadHouses(); loadRole(); }, 0); // DB work OUTSIDE the auth callback
  } else {
    showGate(true);
    if (whoami) whoami.textContent = "";
    if (window.cloud) window.cloud.role = null;
    document.body.classList.remove("is-admin");
  }
});
```

- [ ] **Step 2: Add `listInProgress()`**

Insert after `loadInProgress()` (after line 149):

```js
// Every in-progress visit belonging to the signed-in tech, for the Continue
// screen. Returns null (not []) when the cloud can't be reached, so the UI
// can say so instead of claiming "nothing in progress".
async function listInProgress() {
  const { data: { user } } = await supabase.auth.getUser();
  if (!user) return null;
  const { data, error } = await supabase
    .from("visits")
    .select("id, visit_date, houses(name), visit_items(count)")
    .eq("tech_id", user.id).eq("status", "in_progress")
    .order("started_at", { ascending: false });
  if (error) { console.error("Could not list visits:", error.message); return null; }
  return data.map(v => ({
    visitId: v.id,
    houseName: v.houses?.name || "",
    date: v.visit_date,
    itemCount: v.visit_items?.[0]?.count ?? 0,
  }));
}
```

- [ ] **Step 3: Add the house-notes API**

Insert after `lastDone()` (after line 182):

```js
// ---- House notes: official freeform note + tech suggestions ----
// The official note lives in houses.general_notes; a tech's proposed
// replacement is a house_note_suggestions row. Nothing changes for other
// techs until a supervisor approves (the atomic RPC below).

async function getHouseNotes(houseName) {
  const house = housesByName.get((houseName || "").trim().toLowerCase());
  if (!house) return { error: `"${houseName}" isn't a house in the database.` };
  const { data, error } = await supabase
    .from("houses").select("general_notes").eq("id", house.id).single();
  // Migration 0006 not applied yet → tell the UI, don't fake an empty note.
  if (error) {
    return isMissingColumn(error) ? { notReady: true } : { error: error.message };
  }
  const { data: sugs, error: e2 } = await supabase
    .from("house_note_suggestions")
    .select("id, author_id, author_name, proposed_text, created_at")
    .eq("house_id", house.id).eq("status", "pending")
    .order("created_at", { ascending: false });
  if (e2) return { error: e2.message };
  const { data: { user } } = await supabase.auth.getUser();
  return {
    generalNotes: data.general_notes || "",
    suggestions: (sugs || []).map(s => ({
      id: s.id,
      authorName: s.author_name || "(name not set)",
      text: s.proposed_text,
      createdAt: s.created_at,
      mine: !!user && s.author_id === user.id,
    })),
  };
}

async function suggestNote(houseName, text, authorName) {
  const house = housesByName.get((houseName || "").trim().toLowerCase());
  if (!house) return { error: `"${houseName}" isn't a house in the database.` };
  const { data: { user } } = await supabase.auth.getUser();
  const { error } = await supabase.from("house_note_suggestions").insert({
    house_id: house.id,
    proposed_text: text,
    author_name: (authorName || "").trim() || user?.email || "",
  });
  return error ? { error: error.message } : { ok: true };
}

async function withdrawSuggestion(id) {
  const { error } = await supabase
    .from("house_note_suggestions").delete().eq("id", id);
  return error ? { error: error.message } : { ok: true };
}

async function approveSuggestion(id) {
  const { error } = await supabase.rpc("approve_note_suggestion", { suggestion_id: id });
  return error ? { error: error.message } : { ok: true };
}

async function dismissSuggestion(id) {
  const { data: { user } } = await supabase.auth.getUser();
  const { error } = await supabase.from("house_note_suggestions")
    .update({ status: "dismissed", reviewed_by: user?.id || null,
              reviewed_at: new Date().toISOString() })
    .eq("id", id).eq("status", "pending");
  return error ? { error: error.message } : { ok: true };
}

async function saveGeneralNotes(houseName, text) {
  const house = housesByName.get((houseName || "").trim().toLowerCase());
  if (!house) return { error: `"${houseName}" isn't a house in the database.` };
  const { error } = await supabase
    .from("houses").update({ general_notes: text }).eq("id", house.id);
  return error ? { error: error.message } : { ok: true };
}
```

- [ ] **Step 4: Extend the `window.cloud` export (line 184)**

```js
window.cloud = { saveVisit, loadInProgress, lastDone, listInProgress,
                 getHouseNotes, suggestNote, withdrawSuggestion,
                 approveSuggestion, dismissSuggestion, saveGeneralNotes,
                 role: null };
```

Note: `window.cloud` is created at module top-level before `loadRole()` ever runs, so `loadRole`'s `window.cloud.role = ...` writes are safe.

- [ ] **Step 5: Verify — syntax + console smoke test**

Headless syntax check (module loads without parse errors):

```bash
CHROME="/c/Program Files/Google/Chrome/Application/chrome.exe"
"$CHROME" --headless=new --disable-gpu --virtual-time-budget=6000 \
  --enable-logging=stderr --dump-dom \
  "file:///C:/Big%20Dogs%20Apps/MTX%20Checklist%20V1/route-checklist/index.html" \
  2>/tmp/console.log >/dev/null
grep -i "syntaxerror\|uncaught" /tmp/console.log
```

Expected: no matches. Then in a real browser open the app, sign in, and in DevTools console run `window.cloud.role` (expect `"tech"` or `"supervisor"`) and `await window.cloud.listInProgress()` (expect an array or `null`, no exception). If migration 0006 isn't applied yet, `await window.cloud.getHouseNotes("Dogwood")` must return `{ notReady: true }` — not throw.

- [ ] **Step 6: Commit**

```bash
cd "/c/Big Dogs Apps/MTX Checklist V1"
git add route-checklist/cloud.js
git commit -m "cloud.js: role loading, in-progress visit list, house-notes API

Co-Authored-By: Claude Fable 5 <noreply@anthropic.com>"
```

---

### Task 4: Screens, hash router, Home + Continue

**Files:**
- Modify: `route-checklist/index.html` — new CSS (append inside `<style>`), new HTML (after the `report-bar` div, line 513), new JS (router + screens, near the bottom before `rebuild()` at line 1650), small edits to `.titlerow` (line 478) and the survey-send success handler (line 1493).

**Interfaces:**
- Consumes: `window.cloud.listInProgress()`, `window.cloud.loadInProgress(houseName)` (Task 3); existing `load()`, `blank()`, `save()`, `selectHouse(name)`, `applyCloudVisit(v)`, `rebuild()`, `fmtDate(iso)`, `escHtml`/`escAttr`, `pickerDismissed`.
- Produces (consumed by Task 5):
  - `document.body.dataset.screen` ∈ `"home" | "visit" | "continue" | "notes"`, driven by `location.hash`.
  - `function showScreen()` — reads the hash, sets `data-screen`, calls per-screen render hooks. Task 5 adds its `renderNotesScreen()` call inside it (the hook call is already present in this task as a no-op guard).
  - `function goHome()` — sets `location.hash = "#home"`.
  - CSS classes: `.screen`, `.screen-head`, `.home-btn`, `.list-btn`, `.screen-sub`.

- [ ] **Step 1: Add screen CSS**

Append inside `<style>` (after line 455, before `</style>`):

```css
  /* ---- Screens (Home / Visit / Continue / Notes) ---- */
  /* The checklist is the "visit" screen: its wrapper + bottom bar only show there. */
  body:not([data-screen="visit"]) .wrapper,
  body:not([data-screen="visit"]) .report-bar { display: none; }
  .screen { max-width: 680px; margin: 0 auto; padding: 16px 14px 40px; }
  body:not([data-screen="home"])     #homeScreen,
  body:not([data-screen="continue"]) #continueScreen,
  body:not([data-screen="notes"])    #notesScreen { display: none; }

  .screen-head { display: flex; align-items: center; gap: 10px; margin: 4px 0 16px; }
  .screen-head h1 { font-size: 1.05rem; margin: 0; }

  /* Home menu: three big thumb targets */
  .home-btn {
    display: block; width: 100%; text-align: left;
    font: inherit; font-size: 1.05rem; font-weight: 700;
    background: var(--card); color: var(--ink);
    border: 1px solid var(--line); border-radius: 12px;
    padding: 18px 16px; margin-bottom: 12px; cursor: pointer;
    min-height: 64px;
  }
  .home-btn small { display: block; font-size: 0.82rem; font-weight: 500; color: var(--muted); margin-top: 3px; }
  .home-btn:hover { border-color: var(--accent); }
  .home-btn:focus-visible { outline: 2px solid var(--ink); outline-offset: 2px; }

  /* Continue-visit / notes-house list entries */
  .list-btn {
    display: block; width: 100%; text-align: left;
    font: inherit; font-size: 0.95rem; font-weight: 600;
    background: var(--card); color: var(--ink);
    border: 1px solid var(--line); border-radius: 8px;
    padding: 13px 12px; margin-bottom: 8px; cursor: pointer;
  }
  .list-btn small { display: block; font-weight: 500; color: var(--muted); margin-top: 2px; }
  .list-btn:hover { border-color: var(--accent); }
  .list-btn:focus-visible { outline: 2px solid var(--ink); outline-offset: 2px; }
  .screen-sub { font-size: 0.88rem; color: var(--muted); margin: 0 0 14px; }
```

- [ ] **Step 2: Add the screen HTML**

Insert after the `</div>` closing `.report-bar` (after line 513):

```html
<div id="homeScreen" class="screen" aria-label="Home">
  <div class="screen-head"><h1>Maintenance House Visit</h1></div>
  <button type="button" class="home-btn" id="homeNewVisit">🏠 New house visit
    <small>Pick a house and start the checklist</small></button>
  <button type="button" class="home-btn" id="homeContinue">▶ Continue house visit
    <small>Pick up where you left off</small></button>
  <button type="button" class="home-btn" id="homeNotes">📝 House notes
    <small>Info, item notes &amp; general notes per house</small></button>
</div>

<div id="continueScreen" class="screen" aria-label="Continue a visit">
  <div class="screen-head">
    <button type="button" class="menu-btn" data-nav-home>← Home</button>
    <h1>Continue a visit</h1>
  </div>
  <div id="continueList"></div>
</div>

<div id="notesScreen" class="screen" aria-label="House notes">
  <div class="screen-head">
    <button type="button" class="menu-btn" data-nav-home>← Home</button>
    <h1>House notes</h1>
  </div>
  <div id="notesBody"></div>
</div>
```

Also add a Home button to the checklist header — change line 478–481 from:

```html
    <div class="titlerow">
      <button id="menuBtn" class="menu-btn" aria-label="Pick house">☰ Houses</button>
      <h1>Maintenance House Visit</h1>
    </div>
```

to:

```html
    <div class="titlerow">
      <button type="button" class="menu-btn" data-nav-home aria-label="Back to home">← Home</button>
      <button id="menuBtn" class="menu-btn" aria-label="Pick house">☰ Houses</button>
      <h1>Maintenance House Visit</h1>
    </div>
```

- [ ] **Step 3: Add the router + Home/Continue logic**

Insert in the main `<script>`, immediately BEFORE the final `rebuild();` call (line 1650):

```js
  // ---- Screens & hash router ----
  // The hash is the single source of truth for which screen shows, so the
  // phone's back button moves between screens instead of leaving the app.
  //   #home  #visit  #continue  #notes  #notes/<house name>
  function currentScreenFromHash() {
    const h = location.hash;
    if (h.startsWith("#visit")) return "visit";
    if (h.startsWith("#notes")) return "notes";
    if (h.startsWith("#continue")) return "continue";
    return "home";
  }
  function showScreen() {
    const scr = currentScreenFromHash();
    document.body.dataset.screen = scr;
    if (scr === "continue") renderContinue();
    if (scr === "notes" && typeof renderNotesScreen === "function") renderNotesScreen();
  }
  function goHome() { location.hash = "#home"; }
  window.addEventListener("hashchange", showScreen);
  document.addEventListener("click", e => {
    if (e.target.closest("[data-nav-home]")) goHome();
  });

  // Home buttons. "New" forces the up-front picker even if a house is already
  // on screen; actually SWITCHING houses still goes through selectHouse()'s
  // confirm, so in-progress work is never silently wiped.
  let forceShowPicker = false;
  document.getElementById("homeNewVisit").addEventListener("click", () => {
    forceShowPicker = true;
    pickerDismissed = false;
    location.hash = "#visit";
    rebuild();
  });
  document.getElementById("homeContinue").addEventListener("click", () => {
    location.hash = "#continue";
  });
  document.getElementById("homeNotes").addEventListener("click", () => {
    location.hash = "#notes";
  });

  // ---- Continue screen ----
  async function renderContinue() {
    const box = document.getElementById("continueList");
    const s = load();
    const rows = [];
    // Work sitting on THIS device (may or may not also be saved to the cloud).
    if ((s.house || "").trim() && Object.keys(s.items || {}).length) {
      rows.push(`<button type="button" class="list-btn" data-resume-local="1">
        ${escHtml(s.house)} <small>On this device · ${Object.keys(s.items).length} item${Object.keys(s.items).length === 1 ? "" : "s"} filled in${s.date ? " · " + fmtDate(s.date) : ""}</small></button>`);
    }
    box.innerHTML = rows.join("") + `<p class="screen-sub">Checking the cloud…</p>`;
    let cloudRows = null;
    if (window.cloud) cloudRows = await window.cloud.listInProgress();
    let cloudHtml = "";
    if (cloudRows === null) {
      cloudHtml = `<p class="screen-sub">Couldn't reach the cloud — showing this device only.</p>`;
    } else {
      const localId = s.cloudVisitId || null;
      cloudRows
        .filter(v => v.visitId !== localId)   // already listed as the local row
        .forEach(v => {
          cloudHtml += `<button type="button" class="list-btn" data-resume-cloud="${escAttr(v.houseName)}">
            ${escHtml(v.houseName)} <small>Saved to cloud · ${v.itemCount} item${v.itemCount === 1 ? "" : "s"}${v.date ? " · " + fmtDate(v.date) : ""}</small></button>`;
        });
    }
    if (!rows.length && !cloudHtml.includes("list-btn")) {
      cloudHtml += `<p class="screen-sub">Nothing in progress.</p>
        <button type="button" class="home-btn" id="continueStartNew">🏠 Start a new house visit</button>`;
    }
    box.innerHTML = rows.join("") + cloudHtml;
    const startNew = document.getElementById("continueStartNew");
    if (startNew) startNew.addEventListener("click", () =>
      document.getElementById("homeNewVisit").click());
  }
  document.getElementById("continueList").addEventListener("click", async e => {
    if (e.target.closest("[data-resume-local]")) { location.hash = "#visit"; return; }
    const cloudBtn = e.target.closest("[data-resume-cloud]");
    if (!cloudBtn) return;
    const houseName = cloudBtn.dataset.resumeCloud;
    // selectHouse owns the "don't wipe unsaved work" confirm; it also offers
    // the cloud resume itself (maybeResume) once the house is active.
    if (selectHouse(houseName)) location.hash = "#visit";
  });

  if (!location.hash) history.replaceState(null, "", "#home");
  showScreen();
```

- [ ] **Step 4: Make `build()` honor `forceShowPicker` and clear it on pick**

Change the picker condition in `build()` (line 932) from:

```js
    if (!house && !pickerDismissed) {
```

to:

```js
    if ((!house && !pickerDismissed) || forceShowPicker) {
```

And in `selectHouse()` (line 1566), clear the flag once a choice is made — add as the FIRST line of the function body:

```js
    forceShowPicker = false;
```

(`selectHouse` reverts/returns false on a declined confirm — the flag still clears, which is correct: the tech answered the picker; the old house stays.)

Note: `forceShowPicker` is declared (Step 3) *after* `build`/`selectHouse` are defined but *before* any user can click — `let` hoisting makes earlier calls throw, so the declaration must run before the first `rebuild()`. Step 3's placement (before the final `rebuild()`) guarantees that.

- [ ] **Step 5: Finish-visit returns Home**

In the survey-send success branch (line 1493–1498), after `rebuild()` add one line:

```js
        surveyModal.close();
        save(blank());
        rebuild();
        goHome();
        toast(res.degraded
```

- [ ] **Step 6: Verify via headless Chrome**

```bash
CHROME="/c/Program Files/Google/Chrome/Application/chrome.exe"
"$CHROME" --headless=new --disable-gpu --virtual-time-budget=4000 --dump-dom \
  "file:///C:/Big%20Dogs%20Apps/MTX%20Checklist%20V1/route-checklist/index.html" > /tmp/dom.html
grep -o 'data-screen="[a-z]*"' /tmp/dom.html   # expect: data-screen="home"
grep -c 'id="homeScreen"' /tmp/dom.html         # expect: 1
```

- [ ] **Step 7: Verify by hand**

In a real browser (signed in): app opens on Home → "New house visit" shows the picker → pick a house → checklist (sections closed) → check two items → phone/browser Back → Home → "Continue house visit" lists the house with "On this device · 2 items" → tap it → checklist restored with both items. Also: Save progress on a house, clear localStorage (DevTools → Application → Local Storage → delete `route-checklist-v3`), reload, sign in, Continue → the cloud row appears → tap → resume prompt loads it. Confirm "☰ Houses" and the survey still work on the visit screen.

- [ ] **Step 8: Commit**

```bash
cd "/c/Big Dogs Apps/MTX Checklist V1"
git add route-checklist/index.html
git commit -m "Home screen + hash router; Continue lists in-progress visits

Co-Authored-By: Claude Fable 5 <noreply@anthropic.com>"
```

---

### Task 5: House Notes screen (tech suggest + admin approve)

**Files:**
- Modify: `route-checklist/index.html` — notes CSS (append), `renderNotesScreen()` + helpers + event wiring (insert immediately BEFORE the router block added in Task 4, so `showScreen()`'s `renderNotesScreen` reference resolves).

**Interfaces:**
- Consumes: `window.cloud.getHouseNotes / suggestNote / withdrawSuggestion / approveSuggestion / dismissSuggestion / saveGeneralNotes / role` (Task 3); `#notesBody`, hash routing, `.list-btn` CSS (Task 4); existing `ALL_HOUSES`, `ALL_CODES`, `GROUPS`, `NOTE_RULES`, `currentHouse`-style name matching, `escHtml`, `escAttr`, `loadName()`, `toast()`, `fmtDate()`.
- Produces: `function renderNotesScreen()` (called by Task 4's `showScreen()`); hash form `#notes/<encodeURIComponent(house name)>`.

- [ ] **Step 1: Add notes CSS**

Append inside `<style>`:

```css
  /* ---- House Notes screen ---- */
  .notes-sec { background: var(--card); border: 1px solid var(--line); border-radius: 8px; padding: 12px 14px; margin-bottom: 12px; }
  .notes-sec h2 { font-size: 0.8rem; text-transform: uppercase; letter-spacing: 0.08em; color: var(--muted); margin: 0 0 8px; }
  .notes-item { font-size: 0.88rem; padding: 6px 0; border-top: 1px solid #EEF1F4; }
  .notes-item:first-of-type { border-top: none; }
  .notes-item b { display: block; font-size: 0.74rem; color: var(--muted); text-transform: uppercase; letter-spacing: 0.04em; }
  .gen-notes { font-size: 0.92rem; white-space: pre-wrap; margin: 0; }
  .gen-notes.empty { color: var(--muted); font-style: italic; }
  .sug {
    border: 1px dashed var(--note); background: var(--note-bg);
    border-radius: 8px; padding: 10px 12px; margin-top: 10px;
  }
  .sug-meta { font-size: 0.74rem; font-weight: 700; color: var(--note); text-transform: uppercase; letter-spacing: 0.05em; margin-bottom: 5px; }
  .sug-text { font-size: 0.9rem; white-space: pre-wrap; margin: 0 0 8px; }
  .sug-actions { display: flex; gap: 8px; flex-wrap: wrap; }
  .sug-actions button, .notes-actions button {
    font: inherit; font-size: 0.85rem; font-weight: 600;
    border-radius: 8px; padding: 9px 14px; cursor: pointer;
    border: 1px solid var(--line); background: var(--card); color: var(--ink);
    min-height: 44px;
  }
  .sug-actions button:focus-visible, .notes-actions button:focus-visible { outline: 2px solid var(--ink); outline-offset: 2px; }
  .btn-primary { background: var(--accent) !important; color: var(--accent-ink) !important; border-color: var(--accent) !important; }
  .btn-danger { color: var(--bad) !important; border-color: var(--bad) !important; }
  .notes-actions { margin-top: 10px; display: flex; gap: 8px; flex-wrap: wrap; }
  #notesBody textarea {
    font: inherit; font-size: 16px; width: 100%; min-height: 120px;
    border: 1px solid var(--line); border-radius: 8px; padding: 9px 11px;
    margin-top: 8px; resize: vertical; background: #FFFDF5;
  }
  .notes-msg { font-size: 0.82rem; margin: 6px 0 0; min-height: 1.1em; }
  .notes-msg.error { color: var(--bad); font-weight: 600; }
```

- [ ] **Step 2: Add the notes screen JS**

Insert immediately BEFORE the `// ---- Screens & hash router ----` block from Task 4:

```js
  // ---- House Notes screen ----
  // #notes            → house picker
  // #notes/<name>     → that house's notes (name is encodeURIComponent'd)
  function notesHouseFromHash() {
    const m = location.hash.match(/^#notes\/(.+)$/);
    if (!m) return null;
    const name = decodeURIComponent(m[1]).trim().toLowerCase();
    return ALL_HOUSES.find(h => h.name.toLowerCase() === name) || null;
  }

  // Every 📍 note this house shows on the checklist, with the item it's under.
  function itemNotesHTML(house) {
    const rows = [];
    GROUPS.forEach(group => group.sections.forEach(section => {
      section.items.forEach(item => {
        const label = itemLabel(item);
        const texts = NOTE_RULES.filter(r => r.match.test(label))
          .map(r => r.note && house.notes && house.notes[r.note]).filter(Boolean);
        if (texts.length) rows.push(
          `<div class="notes-item"><b>${escHtml(label)}</b>📍 ${escHtml(texts.join(" · "))}</div>`);
      });
    }));
    return rows.length ? rows.join("")
      : `<p class="screen-sub">No item notes recorded for this house.</p>`;
  }

  function houseInfoNotesHTML(house) {
    const rows = [];
    (ALL_CODES[house.name] || []).forEach(([label, val]) =>
      rows.push(`<div class="notes-item"><b>${escHtml(label)}</b>${escHtml(val)}</div>`));
    (house.info || []).forEach(([label, val]) =>
      rows.push(`<div class="notes-item"><b>${escHtml(label)}</b>${escHtml(val)}</div>`));
    return rows.length ? rows.join("")
      : `<p class="screen-sub">No house info recorded.</p>`;
  }

  let notesEditorOpen = false;   // reset on each house render
  async function renderNotesScreen() {
    const body = document.getElementById("notesBody");
    const house = notesHouseFromHash();
    if (!house) {
      // House picker (same look as the visit picker, notes-specific buttons).
      body.innerHTML = `
        <input type="search" id="notesSearch" placeholder="Type the house name…" aria-label="Search houses">
        <div id="notesPickList">${notesPickListHTML("")}</div>`;
      const search = document.getElementById("notesSearch");
      search.className = ""; search.id = "notesSearch";
      search.style.cssText = "font:inherit;font-size:16px;width:100%;padding:10px 12px;margin-bottom:10px;border:1px solid var(--line);border-radius:8px;background:var(--card);color:var(--ink);";
      return;
    }
    notesEditorOpen = false;
    body.innerHTML = `
      <div class="screen-head" style="margin-top:0"><h1 style="font-size:1rem">${escHtml(house.name)}</h1></div>
      <div class="notes-sec"><h2>House info</h2>${houseInfoNotesHTML(house)}</div>
      <div class="notes-sec"><h2>Checklist item notes</h2>${itemNotesHTML(house)}</div>
      <div class="notes-sec" id="genNotesSec"><h2>General notes</h2>
        <p class="screen-sub">Loading…</p></div>`;
    if (!window.cloud) {
      document.getElementById("genNotesSec").innerHTML =
        `<h2>General notes</h2><p class="screen-sub">Cloud isn't loaded — general notes need a connection.</p>`;
      return;
    }
    const res = await window.cloud.getHouseNotes(house.name);
    // The hash may have changed while we awaited; don't paint a stale house.
    if (notesHouseFromHash()?.name !== house.name) return;
    const sec = document.getElementById("genNotesSec");
    if (!sec) return;
    if (res.error || res.notReady) {
      sec.innerHTML = `<h2>General notes</h2><p class="screen-sub">${res.notReady
        ? "General notes aren't set up in the database yet (migration 0006)."
        : "Couldn't load general notes — " + escHtml(res.error)}</p>`;
      return;
    }
    sec.innerHTML = genNotesHTML(house, res);
  }

  function notesPickListHTML(filter) {
    const f = (filter || "").trim().toLowerCase();
    const matches = ALL_HOUSES.filter(h => !f || h.name.toLowerCase().includes(f));
    if (!matches.length) return `<p class="pick-none">No house matches "${escHtml(filter)}".</p>`;
    return matches.map(h =>
      `<button type="button" class="list-btn" data-notes-house="${escAttr(h.name)}">${escHtml(h.name)}</button>`).join("");
  }

  function genNotesHTML(house, res) {
    const isAdmin = window.cloud && window.cloud.role === "supervisor";
    const noteHtml = res.generalNotes
      ? `<p class="gen-notes">${escHtml(res.generalNotes)}</p>`
      : `<p class="gen-notes empty">No general notes yet.</p>`;
    const sugs = res.suggestions.map(s => `
      <div class="sug" data-sug-id="${escAttr(s.id)}">
        <div class="sug-meta">Awaiting approval — ${escHtml(s.authorName)}${s.createdAt ? " · " + fmtDate(s.createdAt.slice(0, 10)) : ""}</div>
        <p class="sug-text">${escHtml(s.text)}</p>
        <div class="sug-actions">
          ${isAdmin ? `<button type="button" class="btn-primary" data-sug-approve="${escAttr(s.id)}">Approve</button>
                       <button type="button" data-sug-dismiss="${escAttr(s.id)}">Dismiss</button>` : ""}
          ${s.mine ? `<button type="button" class="btn-danger" data-sug-withdraw="${escAttr(s.id)}">Withdraw my suggestion</button>` : ""}
        </div>
      </div>`).join("");
    const editor = notesEditorOpen ? `
      <textarea id="notesEditor" aria-label="${isAdmin ? "Edit general notes" : "Suggest an update to the general notes"}">${escHtml(res.generalNotes)}</textarea>
      <div class="notes-actions">
        <button type="button" class="btn-primary" data-notes-submit="${escAttr(house.name)}">${isAdmin ? "Save notes" : "Submit suggestion"}</button>
        <button type="button" data-notes-cancel>Cancel</button>
      </div>` : `
      <div class="notes-actions">
        <button type="button" data-notes-edit>${isAdmin ? "✎ Edit notes" : "✎ Suggest an update"}</button>
      </div>`;
    return `<h2>General notes</h2>${noteHtml}${sugs}${editor}
      <p class="notes-msg" id="notesMsg" role="status"></p>`;
  }

  document.getElementById("notesBody").addEventListener("input", e => {
    if (e.target.id === "notesSearch") {
      document.getElementById("notesPickList").innerHTML = notesPickListHTML(e.target.value);
    }
  });
  document.getElementById("notesBody").addEventListener("click", async e => {
    const pick = e.target.closest("[data-notes-house]");
    if (pick) { location.hash = "#notes/" + encodeURIComponent(pick.dataset.notesHouse); return; }
    if (e.target.closest("[data-notes-edit]")) { notesEditorOpen = true; refreshGenNotes(); return; }
    if (e.target.closest("[data-notes-cancel]")) { notesEditorOpen = false; refreshGenNotes(); return; }
    const submit = e.target.closest("[data-notes-submit]");
    if (submit) { await submitNotes(submit.dataset.notesSubmit, submit); return; }
    const approve = e.target.closest("[data-sug-approve]");
    if (approve) { await sugAction(() => window.cloud.approveSuggestion(approve.dataset.sugApprove), "Approved — the note is updated.", approve); return; }
    const dismiss = e.target.closest("[data-sug-dismiss]");
    if (dismiss) { await sugAction(() => window.cloud.dismissSuggestion(dismiss.dataset.sugDismiss), "Suggestion dismissed.", dismiss); return; }
    const withdraw = e.target.closest("[data-sug-withdraw]");
    if (withdraw) { await sugAction(() => window.cloud.withdrawSuggestion(withdraw.dataset.sugWithdraw), "Suggestion withdrawn.", withdraw); return; }
  });

  // Re-render ONLY the general-notes section (keeps scroll position). On any
  // failure the editor content is preserved by not re-rendering (see below).
  async function refreshGenNotes() {
    const house = notesHouseFromHash();
    if (!house || !window.cloud) return;
    const res = await window.cloud.getHouseNotes(house.name);
    const sec = document.getElementById("genNotesSec");
    if (!sec || notesHouseFromHash()?.name !== house.name) return;
    if (res.error || res.notReady) {
      const msg = document.getElementById("notesMsg");
      if (msg) { msg.textContent = res.error || "Notes aren't set up in the database yet."; msg.className = "notes-msg error"; }
      return;   // keep whatever's on screen (incl. the tech's typed text)
    }
    sec.innerHTML = genNotesHTML(house, res);
  }

  async function submitNotes(houseName, btn) {
    const ta = document.getElementById("notesEditor");
    const msg = document.getElementById("notesMsg");
    const text = ta.value;   // deliberate: allow clearing a note to empty
    const isAdmin = window.cloud && window.cloud.role === "supervisor";
    if (!isAdmin && !text.trim()) {
      msg.textContent = "Type your suggested note first."; msg.className = "notes-msg error"; return;
    }
    btn.disabled = true;
    msg.textContent = isAdmin ? "Saving…" : "Submitting…"; msg.className = "notes-msg";
    try {
      const res = isAdmin
        ? await window.cloud.saveGeneralNotes(houseName, text)
        : await window.cloud.suggestNote(houseName, text, loadName());
      if (res.error) {   // keep the textarea + its content so nothing is lost
        msg.textContent = "Couldn't save — " + res.error; msg.className = "notes-msg error";
        return;
      }
      notesEditorOpen = false;
      toast(isAdmin ? "✓ Notes saved." : "✓ Suggestion submitted for approval.", "ok");
      await refreshGenNotes();
    } finally { btn.disabled = false; }
  }

  async function sugAction(fn, okText, btn) {
    const msg = document.getElementById("notesMsg");
    btn.disabled = true;
    try {
      const res = await fn();
      if (res.error) { msg.textContent = res.error; msg.className = "notes-msg error"; return; }
      toast("✓ " + okText, "ok");
      await refreshGenNotes();
    } finally { btn.disabled = false; }
  }
```

- [ ] **Step 3: Verify via headless Chrome (screen renders, no JS errors)**

```bash
CHROME="/c/Program Files/Google/Chrome/Application/chrome.exe"
"$CHROME" --headless=new --disable-gpu --virtual-time-budget=5000 \
  --enable-logging=stderr --dump-dom \
  "file:///C:/Big%20Dogs%20Apps/MTX%20Checklist%20V1/route-checklist/index.html#notes" \
  2>/tmp/console.log >/tmp/dom.html
grep -o 'data-screen="[a-z]*"' /tmp/dom.html          # expect: data-screen="notes"
grep -c 'data-notes-house' /tmp/dom.html               # expect: 29 (falls back to house-data.js roster when logged out)
grep -i "syntaxerror\|uncaught" /tmp/console.log       # expect: no matches
```

- [ ] **Step 4: Verify by hand (requires migration 0006 applied — Task 2 checkpoint)**

As a TECH account: Home → House notes → search + pick a house → info and 📍 item-note sections show → "Suggest an update" → edit text → Submit → pending block appears with your name, original note unchanged; "Withdraw my suggestion" appears on yours; reload → still there. As the OWNER (supervisor): same page shows "✎ Edit notes" plus Approve/Dismiss on the pending block → Approve → official note becomes the suggested text, pending block gone → in Supabase, the suggestion row has `status='approved'` and `reviewed_by/reviewed_at` set. RLS spot-check as tech (DevTools console): `await window.cloud.saveGeneralNotes("Dogwood", "hack")` returns an error (or reports 0 rows updated) and the DB value is unchanged.

- [ ] **Step 5: Commit**

```bash
cd "/c/Big Dogs Apps/MTX Checklist V1"
git add route-checklist/index.html
git commit -m "House Notes screen: per-house info + general notes with suggest/approve

Co-Authored-By: Claude Fable 5 <noreply@anthropic.com>"
```

---

### Task 6: Service-worker bump, handoff docs, full end-to-end verification

**Files:**
- Modify: `route-checklist/sw.js:7` (cache name)
- Modify: `route-checklist/HANDOFF.md` (state + features sections)

**Interfaces:**
- Consumes: everything from Tasks 1–5.
- Produces: nothing new — this task proves the slice and records it.

- [ ] **Step 1: Bump the service-worker cache**

In `sw.js` line 7, change:

```js
const CACHE = "route-checklist-v3";
```

to:

```js
const CACHE = "route-checklist-v4";
```

(Strategy is network-first so stale cache mostly self-heals, but the bump forces installed phones to drop the pre-screens shell on next activate.)

- [ ] **Step 2: Update HANDOFF.md**

Add to the "STATE AS OF" area and "Current features" list (adjusting the date):
- Sections start collapsed everywhere.
- Screens + hash router: `#home` (post-login landing: New / Continue / House notes), `#visit`, `#continue`, `#notes/<house>`; back button navigates screens; finishing a survey returns Home.
- Continue screen lists the tech's in-progress visits (cloud `listInProgress()` + local buffer).
- House Notes screen: house info + 📍 item notes (read-only) + `houses.general_notes` with `house_note_suggestions` suggest→approve flow (`0006_house_notes.sql`); approve is an atomic supervisor-only RPC; owner's account promoted to supervisor.
- `window.cloud` additions: `role`, `listInProgress`, `getHouseNotes`, `suggestNote`, `withdrawSuggestion`, `approveSuggestion`, `dismissSuggestion`, `saveGeneralNotes`.
- Remove/adjust the now-built "Start flow" bullet under "Owner requests captured but NOT built yet".

- [ ] **Step 3: Full end-to-end drive (the spec's verification list)**

Precondition: owner has applied 0006 + promotion (Task 2 checkpoint). Run every item; do not claim done on partial passes:

1. Sign in → lands on Home; all three buttons navigate; browser Back returns Home.
2. All checklist sections + Alarm Counts start closed; counts visible.
3. Start a visit, answer items, Save progress, go Home → Continue lists it (local + cloud de-duplicated) → tap → resumes with answers intact.
4. Tech: suggest a note update → pending appears, original unchanged, survives reload, row in Supabase (`select count(*) from house_note_suggestions where status='pending'` — hand the owner this as a chat block if they want to see it).
5. Owner account: Approve → note updated + row `approved`; Dismiss on a second suggestion → note unchanged + row `dismissed`; direct "Edit notes" saves immediately.
6. Tech console: direct `saveGeneralNotes` / `approveSuggestion` attempts fail (RLS/role check).
7. Offline-ish check: with DevTools offline, House Notes still shows house info sections and a plain "couldn't load" message for general notes — no blank screen; suggestion submit failure keeps the typed text.
8. Survey Save & Send on a finished visit → clears → lands on Home.

- [ ] **Step 4: Commit (no push)**

```bash
cd "/c/Big Dogs Apps/MTX Checklist V1"
git add route-checklist/sw.js route-checklist/HANDOFF.md
git commit -m "SW cache bump to v4; handoff notes for screens + house notes

Co-Authored-By: Claude Fable 5 <noreply@anthropic.com>"
```

Then walk the owner through trying it themselves. Push only after the owner approves.
