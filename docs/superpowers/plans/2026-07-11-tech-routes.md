# Tech Routes Implementation Plan

> **For agentic workers:** REQUIRED SUB-SKILL: Use superpowers:subagent-driven-development (recommended) or superpowers:executing-plans to implement this plan task-by-task. Steps use checkbox (`- [ ]`) syntax for tracking.

**Goal:** Named routes (4 to start) that own houses and are assigned to one tech each, so a tech's Home-screen pickers show only their route's houses, with an explicit "Show all houses" escape hatch and a supervisor-only Routes screen for assignment and one-dropdown turnover.

**Architecture:** New `routes` table + nullable `houses.route_id` (migration `0007`). `cloud.js` loads the signed-in tech's route house-set and hands it to the app via a new `window.applyMyHouses(Set)` (same pattern as `applyHouses`). The up-front visit picker in `index.html` scopes to that set; a new `#routes` hash screen (supervisor-gated in UI, RLS-enforced in DB) manages route names, tech assignment, and house membership.

**Tech Stack:** Vanilla HTML/CSS/JS (no build step), Supabase (Postgres + RLS via `@supabase/supabase-js` ESM import), service worker cache.

**Spec:** `docs/superpowers/specs/2026-07-11-tech-routes-design.md` — read it first.

## Global Constraints

- This repo is PUBLIC — no real codes/secrets in any file or SQL (fake Dogwood/Roselawn samples only).
- The owner runs SQL by hand in the Supabase dashboard: hand SQL as a chat code block or a real file, never terminal output; tell them to verify the first line before Run.
- Never edit an already-applied migration — new migrations only (`0007` is new, so it may be edited until the owner runs it).
- Graceful degradation is required: until migration `0007` is applied, every new query path must detect the missing table/column and fall back to current behavior (all houses shown, Routes screen shows a "not set up yet" message). Follow the existing `isMissingColumn` pattern in `cloud.js`.
- Keep existing accessibility patterns: `aria-label` on new inputs/selects, `:focus-visible` outlines on new buttons.
- UI hides supervisor controls but RLS is the real enforcement — never rely on the UI for security.
- No automated test framework exists. "Test" steps are: (a) a headless-Chrome parse check proving `index.html`'s script still runs, and (b) manual browser flows. Do not claim a task verified without running its listed checks.
- Bump `sw.js` `CACHE` exactly once for the whole feature (Task 6), `route-checklist-v5` → `route-checklist-v6`.
- Commit after every task.

**Headless parse check** (used by several tasks; Chrome path on this machine):

```bash
"/c/Program Files/Google/Chrome/Application/chrome.exe" --headless=new --dump-dom \
  "file:///C:/Big%20Dogs%20Apps/MTX%20Checklist%20V1/route-checklist/index.html" > /tmp/dom.html
grep -c 'data-pick-house' /tmp/dom.html
```

Expected: a number ≥ 1. `data-pick-house` buttons only exist if the inline script executed `build()` without a syntax error, so 0 (or an empty dump) means the script is broken.

---

### Task 1: Migration `0007_tech_routes.sql`

**Files:**
- Create: `supabase/migrations/0007_tech_routes.sql`

**Interfaces:**
- Produces: table `public.routes (id uuid pk, name text unique, tech_id uuid → profiles, created_at)`; column `public.houses.route_id uuid → routes`; 4 seed rows `Route 1`–`Route 4`. All later tasks assume exactly these names/types.

- [ ] **Step 1: Write the migration file**

```sql
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
```

- [ ] **Step 2: Verify the file is self-consistent**

Read it back checking: every `references` target exists (`public.profiles`, `public.routes`), policy names don't collide with earlier migrations (grep `routes_select\|routes_write` across `supabase/migrations/` — expect hits only in 0007), and the header says how to run it.

- [ ] **Step 3: Commit**

```bash
git add supabase/migrations/0007_tech_routes.sql
git commit -m "Migration 0007: routes table + houses.route_id (named tech routes)"
```

- [ ] **Step 4: Hand the SQL to the owner as a chat code block** (never terminal output — they paste by hand), with the verify query and expected result (4 rows, tech_id null). The app work below degrades gracefully until they run it, so don't block on this.

---

### Task 2: `cloud.js` — load the tech's route house-set

**Files:**
- Modify: `route-checklist/cloud.js` (loadHouses ~line 44, isMissingColumn ~line 120, onAuthStateChange ~line 334)

**Interfaces:**
- Consumes: `routes` / `houses.route_id` from Task 1 (tolerates their absence).
- Produces: calls `window.applyMyHouses(setOrNull)` — a `Set` of **lowercase, trimmed** house names on the caller's route(s); `null` = no route info (signed out, migration missing, query failed, or caller is a supervisor) meaning "don't scope anything". Also `isMissingTable(error)` helper used by Task 4. Task 3 defines `window.applyMyHouses`; until then the optional call is a no-op.

- [ ] **Step 1: Add the `isMissingTable` helper** directly below `isMissingColumn`:

```js
// True when a query failed because a table from a not-yet-applied migration
// (e.g. routes, migration 0007) isn't in the PostgREST schema cache.
function isMissingTable(error) {
  return !!error && (error.code === "PGRST205" || error.code === "42P01" ||
    /could not find the table|relation .* does not exist/i.test(error.message || ""));
}
```

- [ ] **Step 2: Make `loadHouses` fetch `route_id`, with a pre-0007 fallback** (replace the existing single query):

```js
async function loadHouses() {
  let { data, error } = await supabase
    .from("houses")
    .select("id, name, equipment, notes, info, route_id")
    .eq("active", true)
    .order("name");
  // Before migration 0007, route_id doesn't exist — load without it.
  if (error && isMissingColumn(error)) {
    ({ data, error } = await supabase
      .from("houses")
      .select("id, name, equipment, notes, info")
      .eq("active", true)
      .order("name"));
  }
  if (error) { console.error("Could not load houses:", error.message); return; }
  housesByName.clear();
  data.forEach(h => housesByName.set(h.name.trim().toLowerCase(), h));
  if (window.applyHouses) window.applyHouses(data);
}
```

- [ ] **Step 3: Add `loadMyRoute`** below `loadRole`:

```js
// Which houses are on the signed-in tech's route(s)? Hands the app a Set of
// lowercase house names via window.applyMyHouses. null = "no route info" —
// the app then shows every house (signed out, migration 0007 not applied,
// query failed, or a supervisor, whose pickers are deliberately unscoped).
// Must run AFTER loadHouses (reads housesByName) and loadRole (reads role).
async function loadMyRoute() {
  const apply = s => { if (window.applyMyHouses) window.applyMyHouses(s); };
  const { data: { user } } = await supabase.auth.getUser();
  if (!user || window.cloud.role === "supervisor") { apply(null); return; }
  const { data, error } = await supabase
    .from("routes").select("id").eq("tech_id", user.id);
  if (error) {
    if (!isMissingTable(error)) console.error("Could not load routes:", error.message);
    apply(null); return;
  }
  const myRouteIds = new Set(data.map(r => r.id));
  const mine = new Set();
  housesByName.forEach((h, key) => {
    if (h.route_id && myRouteIds.has(h.route_id)) mine.add(key);
  });
  apply(mine);   // empty Set is meaningful: "route info exists, none assigned"
}
```

- [ ] **Step 4: Sequence the loads.** In `onAuthStateChange`, the signed-in branch currently runs `setTimeout(() => { loadHouses(); loadRole(); }, 0);`. `loadMyRoute` needs both done first, so replace that line with:

```js
    setTimeout(async () => {   // DB work OUTSIDE the auth callback
      await loadRole();        // loadMyRoute needs role + houses loaded first
      await loadHouses();
      await loadMyRoute();
    }, 0);
```

And in the signed-OUT branch, after `document.body.classList.remove("is-admin");` add:

```js
    if (window.applyMyHouses) window.applyMyHouses(null);
```

- [ ] **Step 5: Run the headless parse check** (Global Constraints) — expect ≥ 1. Also open the app in a browser while signed in (pre-0007 DB): console must show no errors, houses must still load (the fallback query path).

- [ ] **Step 6: Commit**

```bash
git add route-checklist/cloud.js
git commit -m "cloud.js: load the tech's route house-set (applyMyHouses), pre-0007 fallbacks"
```

---

### Task 3: `index.html` — route-scoped visit picker + "Show all houses"

**Files:**
- Modify: `route-checklist/index.html` — CSS after the `.pick-skip` block (~line 242), JS near `let pickerDismissed` (~line 1026), `pickListHTML` (~line 1028), delegated click handler (~line 1446), `homeNewVisit` handler (~line 1972)

**Interfaces:**
- Consumes: `window.applyMyHouses(setOrNull)` calls from Task 2 (lowercase trimmed names, null = unscoped).
- Produces: `window.applyMyHouses` defined; module-level `MY_HOUSE_NAMES` (Set|null) and `pickerShowAll` (bool). The Continue screen and House Notes are deliberately untouched: Continue already lists only the tech's OWN in-progress visits (scoped by `tech_id` in the DB — an off-route visit they started via "Show all" must stay resumable), and House Notes shows every house by spec.

- [ ] **Step 1: Add state + `applyMyHouses`** just above `function pickListHTML(filter) {`:

```js
  // Houses on MY route: a Set of lowercase names, pushed by cloud.js via
  // applyMyHouses. null = no route info (logged out / migration 0007 not run /
  // supervisor) → pickers show every house, exactly as before routes existed.
  let MY_HOUSE_NAMES = null;
  // The tech tapped "Show all houses…" (float day / covering another route).
  // Reset each time the picker is opened fresh from Home.
  let pickerShowAll = false;
  window.applyMyHouses = function (names) {
    MY_HOUSE_NAMES = names instanceof Set ? names : null;
    rebuild();
  };
```

- [ ] **Step 2: Replace `pickListHTML`** with the scoped version:

```js
  function pickListHTML(filter) {
    const f = (filter || "").trim().toLowerCase();
    const scoped = !pickerShowAll && MY_HOUSE_NAMES instanceof Set
      ? ALL_HOUSES.filter(h => MY_HOUSE_NAMES.has(h.name.trim().toLowerCase()))
      : null;
    const pool = scoped || ALL_HOUSES;
    const matches = pool.filter(h => !f || h.name.toLowerCase().includes(f));
    let html;
    if (!matches.length) {
      html = scoped && !scoped.length
        ? `<p class="pick-none">No houses are assigned to your route yet — ask a supervisor, or use "Show all houses".</p>`
        : `<p class="pick-none">No house matches "${filter.replace(/</g, "&lt;")}".</p>`;
    } else {
      html = matches.map(h =>
        `<button type="button" class="pick-btn" data-pick-house="${h.name.replace(/"/g, "&quot;")}">${h.name.replace(/</g, "&lt;")}</button>`).join("");
    }
    if (scoped) html += `<button type="button" class="pick-all" data-pick-all>Show all houses…</button>`;
    return html;
  }
```

- [ ] **Step 3: Handle the "Show all" tap.** In the delegated `document.addEventListener("click", …)` that handles `[data-pick-house]` (~line 1446), add BEFORE the `data-pick-house` lookup:

```js
    if (e.target.closest("[data-pick-all]")) {
      pickerShowAll = true;
      const search = document.getElementById("pickSearch");
      document.getElementById("pickList").innerHTML = pickListHTML(search ? search.value : "");
      return;
    }
```

- [ ] **Step 4: Reset the toggle when the picker opens fresh.** In the `homeNewVisit` click handler, add `pickerShowAll = false;` alongside the existing `forceShowPicker = true; pickerDismissed = false;`.

- [ ] **Step 5: Style the button.** After the `.pick-skip` CSS block add:

```css
  .pick-all {
    font: inherit; font-size: 0.85rem; width: 100%; margin-top: 8px;
    padding: 10px 12px; border: 1px dashed var(--line); border-radius: 8px;
    background: none; color: var(--muted); cursor: pointer;
  }
  .pick-all:hover { border-color: var(--accent); color: var(--accent); }
  .pick-all:focus-visible { outline: 2px solid var(--ink); outline-offset: 2px; }
```

- [ ] **Step 6: Verify.** Headless parse check → ≥ 1. Manually in a browser, logged OUT (file:// is fine): New house visit shows ALL houses and NO "Show all houses…" button (`MY_HOUSE_NAMES` is null → unscoped). In the console run `applyMyHouses(new Set(["dogwood"]))`: picker now lists only Dogwood plus the "Show all houses…" button; tapping it reveals every house; searching still works in both modes; `applyMyHouses(new Set())` shows the "No houses are assigned to your route yet" message.

- [ ] **Step 7: Commit**

```bash
git add route-checklist/index.html
git commit -m "Visit picker scopes to the tech's route, with a Show-all-houses escape hatch"
```

---

### Task 4: `cloud.js` — routes admin API

**Files:**
- Modify: `route-checklist/cloud.js` (below the house-notes functions ~line 287; `window.cloud` export ~line 289)

**Interfaces:**
- Consumes: `isMissingTable` (Task 2), `housesByName` cache (has `id`, `name`, `route_id` after Task 2).
- Produces (Task 5 calls all of these via `window.cloud`):
  - `listRoutes()` → `{ routes: [{id, name, tech_id}] } | { error, notReady }`
  - `listTechs()` → `{ techs: [{id, full_name}] } | { error }` (role='tech' only, per spec; RLS means techs get [] — fine, screen is supervisor-only)
  - `saveRoute(routeId, { name, techId })` → `{ ok } | { error }` (techId null clears)
  - `setHouseRoute(houseId, routeId|null)` → `{ ok } | { error }`, also updates the local cache row
  - `listHousesForRoutes()` → `[{id, name, routeId}]` sorted by name (synchronous, from cache)

- [ ] **Step 1: Add the functions** after `saveGeneralNotes`:

```js
// ---- Routes admin (the supervisor Routes screen) ----
// The UI hides this screen from techs, but RLS (routes_write / houses_write,
// supervisor-only) is what actually enforces it.

async function listRoutes() {
  const { data, error } = await supabase
    .from("routes").select("id, name, tech_id").order("name");
  // notReady → migration 0007 hasn't been run; the screen says so.
  if (error) return { error: error.message, notReady: isMissingTable(error) };
  return { routes: data };
}

// Assignable people = tech-role profiles only (per spec; supervisors excluded).
// full_name can be '' if it was never set — the screen shows a fallback label.
async function listTechs() {
  const { data, error } = await supabase
    .from("profiles").select("id, full_name").eq("role", "tech").order("full_name");
  if (error) return { error: error.message };
  return { techs: data };
}

// One call covers both rename and tech (re)assignment — the turnover action.
async function saveRoute(routeId, { name, techId }) {
  const { error } = await supabase.from("routes")
    .update({ name: (name || "").trim(), tech_id: techId || null }).eq("id", routeId);
  return error ? { error: error.message } : { ok: true };
}

async function setHouseRoute(houseId, routeId) {
  const { error } = await supabase.from("houses")
    .update({ route_id: routeId || null }).eq("id", houseId);
  if (error) return { error: error.message };
  // Keep the local cache truthful so a re-render shows the new value without
  // a full reload.
  housesByName.forEach(h => { if (h.id === houseId) h.route_id = routeId || null; });
  return { ok: true };
}

// The Routes screen needs house IDs; the checklist app only knows names.
// Serve the already-loaded rows rather than re-querying.
function listHousesForRoutes() {
  return [...housesByName.values()]
    .map(h => ({ id: h.id, name: h.name, routeId: h.route_id || null }))
    .sort((a, b) => a.name.localeCompare(b.name));
}
```

- [ ] **Step 2: Export them.** Extend the `window.cloud = { … }` object with `listRoutes, listTechs, saveRoute, setHouseRoute, listHousesForRoutes`.

- [ ] **Step 3: Verify.** The headless check can't exercise cloud.js (it's a network module that needs a signed-in session), so open the app in a browser signed in and confirm in the console: `typeof cloud.listRoutes === "function"`, and — pre-0007 — `await cloud.listRoutes()` returns `{ error, notReady: true }` rather than throwing.

- [ ] **Step 4: Commit**

```bash
git add route-checklist/cloud.js
git commit -m "cloud.js: routes admin API (listRoutes/listTechs/saveRoute/setHouseRoute)"
```

---

### Task 5: `index.html` — supervisor Routes screen

**Files:**
- Modify: `route-checklist/index.html` — CSS screen-visibility block (~line 462), new CSS, home buttons (~line 599), new screen div after `#notesScreen` (~line 617), router (~lines 1949–1961), home-button handlers (~line 1981), new render function + handlers (add after the Continue-screen code, ~line 2028)

**Interfaces:**
- Consumes: everything Task 4 produces; `escHtml`/`escAttr` (const arrows at ~line 1481 — fine, this code runs on user interaction, long after init); `toast(text, kind)` with kinds `"ok"`/`"error"`; `currentScreenFromHash()`; existing classes `.screen`, `.screen-head`, `.screen-sub`, `.menu-btn`, `.home-btn`, `.notes-sec`, `[data-nav-home]`.
- Produces: `#routes` hash screen; `.admin-only` CSS utility (hidden unless `body.is-admin`).

- [ ] **Step 1: CSS.** In the screen-visibility block, add a line so it reads:

```css
  body:not([data-screen="home"])     #homeScreen,
  body:not([data-screen="continue"]) #continueScreen,
  body:not([data-screen="routes"])   #routesScreen,
  body:not([data-screen="notes"])    #notesScreen { display: none; }
```

After that block add:

```css
  /* Supervisor-only controls; loadRole() toggles body.is-admin. The UI hides,
     RLS enforces. */
  body:not(.is-admin) .admin-only { display: none; }
  .route-row, .house-route-row { display: flex; gap: 8px; align-items: center; margin-bottom: 8px; }
  .route-row input, .route-row select, .house-route-row select {
    font: inherit; font-size: 16px; padding: 8px 10px; min-width: 0;
    border: 1px solid var(--line); border-radius: 8px;
    background: var(--ground); color: var(--ink);
  }
  .route-row input { flex: 1; }
  .route-row button { font: inherit; padding: 8px 12px; border: 1px solid var(--line); border-radius: 8px; background: var(--ground); color: var(--ink); cursor: pointer; }
  .route-row button:focus-visible, .house-route-row select:focus-visible { outline: 2px solid var(--ink); outline-offset: 2px; }
  .house-route-row { justify-content: space-between; }
```

- [ ] **Step 2: Home button.** After the `homeNotes` button add:

```html
  <button type="button" class="home-btn admin-only" id="homeRoutes">🗺️ Routes
    <small>Assign techs &amp; houses to routes</small></button>
```

- [ ] **Step 3: Screen div.** After the `#notesScreen` div add:

```html
<div id="routesScreen" class="screen" aria-label="Routes">
  <div class="screen-head">
    <button type="button" class="menu-btn" data-nav-home>← Home</button>
    <h1>Routes</h1>
  </div>
  <div id="routesBody"></div>
</div>
```

- [ ] **Step 4: Router.** In `currentScreenFromHash()` add `if (h.startsWith("#routes")) return "routes";` (alongside the other startsWith checks — no prefix collisions: visit/notes/continue/routes are distinct). In `showScreen()` add `if (scr === "routes") renderRoutesScreen();`. With the other home-button handlers add:

```js
  document.getElementById("homeRoutes").addEventListener("click", () => {
    location.hash = "#routes";
  });
```

- [ ] **Step 5: Render + handlers.** After the Continue-screen block add:

```js
  // ---- Routes screen (supervisor) ----
  // Top: each route's name + which tech runs it (the one-dropdown turnover).
  // Bottom: which route each house is on. UI-gated to supervisors; RLS is the
  // real enforcement, so a tech who forces the hash just gets failed writes.
  async function renderRoutesScreen() {
    const body = document.getElementById("routesBody");
    if (!window.cloud || window.cloud.role !== "supervisor") {
      body.innerHTML = `<p class="screen-sub">This screen is for supervisors.</p>`;
      return;
    }
    body.innerHTML = `<p class="screen-sub">Loading…</p>`;
    const [routesRes, techsRes] = await Promise.all([
      window.cloud.listRoutes(), window.cloud.listTechs(),
    ]);
    if (currentScreenFromHash() !== "routes") return;   // navigated away meanwhile
    if (routesRes.error) {
      body.innerHTML = `<p class="screen-sub">${routesRes.notReady
        ? "Routes aren't set up in the database yet — run migration 0007 in the dashboard."
        : "Couldn't load routes — " + escHtml(routesRes.error)}</p>`;
      return;
    }
    const routes = routesRes.routes;
    const techs = techsRes.techs || [];
    const techName = t => t.full_name || "(name not set — fill full_name in profiles)";
    const routeRows = routes.map(r => `
      <div class="route-row" data-route-id="${escAttr(r.id)}">
        <input type="text" value="${escAttr(r.name)}" aria-label="Route name">
        <select aria-label="Tech assigned to ${escAttr(r.name)}">
          <option value="">— no tech —</option>
          ${techs.map(t => `<option value="${escAttr(t.id)}"${t.id === r.tech_id ? " selected" : ""}>${escHtml(techName(t))}</option>`).join("")}
        </select>
        <button type="button" data-route-save>Save</button>
      </div>`).join("");
    const routeOpts = h => `<option value="">— no route —</option>` +
      routes.map(r => `<option value="${escAttr(r.id)}"${r.id === h.routeId ? " selected" : ""}>${escHtml(r.name)}</option>`).join("");
    const houseRows = window.cloud.listHousesForRoutes().map(h => `
      <div class="house-route-row"><b>${escHtml(h.name)}</b>
        <select data-house-route="${escAttr(h.id)}" aria-label="Route for ${escAttr(h.name)}">${routeOpts(h)}</select>
      </div>`).join("");
    body.innerHTML = `
      <div class="notes-sec"><h2>Routes &amp; techs</h2>
        <p class="screen-sub">Turnover = change a route's tech and Save. Houses follow the route.</p>
        ${routeRows}
        ${techsRes.error ? `<p class="screen-sub">Couldn't load techs — ${escHtml(techsRes.error)}</p>` : ""}</div>
      <div class="notes-sec"><h2>Houses on each route</h2>
        <p class="screen-sub">Changes save immediately.</p>${houseRows}</div>`;
  }

  document.getElementById("routesBody").addEventListener("click", async e => {
    const btn = e.target.closest("[data-route-save]");
    if (!btn) return;
    const row = btn.closest("[data-route-id]");
    const name = row.querySelector("input").value.trim();
    if (!name) { toast("Route name can't be empty.", "error"); return; }
    btn.disabled = true;
    const res = await window.cloud.saveRoute(row.dataset.routeId,
      { name, techId: row.querySelector("select").value || null });
    btn.disabled = false;
    if (res.error) { toast("Couldn't save — " + res.error, "error"); return; }
    toast("✓ Route saved.", "ok");
  });

  document.getElementById("routesBody").addEventListener("change", async e => {
    const sel = e.target.closest("[data-house-route]");
    if (!sel) return;
    sel.disabled = true;
    const res = await window.cloud.setHouseRoute(sel.dataset.houseRoute, sel.value || null);
    sel.disabled = false;
    if (res.error) { toast("Couldn't save — " + res.error, "error"); return; }
    toast("✓ Saved.", "ok");
  });
```

- [ ] **Step 6: Verify.** Headless parse check → ≥ 1, and `grep -c 'routesScreen' /tmp/dom.html` → ≥ 1. In a browser, logged out: no Routes button on Home (no `is-admin`); forcing `#routes` shows "This screen is for supervisors." Signed in as the owner (supervisor), pre-0007: the screen shows the "run migration 0007" message, no console errors.

- [ ] **Step 7: Commit**

```bash
git add route-checklist/index.html
git commit -m "Supervisor Routes screen: route names, tech assignment, house membership"
```

---

### Task 6: Cache bump, docs, end-to-end verification

**Files:**
- Modify: `route-checklist/sw.js:7`, `route-checklist/HANDOFF.md` (new state section at top)

**Interfaces:**
- Consumes: everything above.

- [ ] **Step 1: Bump the service-worker cache** — `sw.js` line 7: `const CACHE = "route-checklist-v5";` → `"route-checklist-v6"`. (PWA note: an already-open PWA keeps the old SW until fully closed and reopened — see HANDOFF's 2026-07-11 debugging note.)

- [ ] **Step 2: Update `HANDOFF.md`** — add a new "STATE AS OF" section at the top summarizing: migration 0007 (owner must run it), applyMyHouses/route-scoped picker + Show-all button, Routes screen, supervisor pickers unscoped, Continue/Notes deliberately untouched, cache v6, and whether it's been pushed.

- [ ] **Step 3: Full end-to-end verification (owner participation — needs migration 0007 run and at least one tech-role account):**

1. Supervisor: Home shows the Routes button; assign a tech to Route 1; put 2–3 houses on Route 1; reload — values persisted.
2. Tech account: New house visit lists ONLY those houses; "Show all houses…" reveals all 47; starting a visit at an off-route house works; that visit appears on their Continue screen.
3. House Notes still lists every house for the tech.
4. Turnover drill: point Route 1 at a different tech; first tech's picker empties (shows the "no houses assigned" message), second tech's fills.
5. Supervisor's own New-visit picker shows all houses (unscoped), no Show-all button.

- [ ] **Step 4: Commit**

```bash
git add route-checklist/sw.js route-checklist/HANDOFF.md
git commit -m "SW cache v6; handoff notes for tech routes"
```

Do NOT push — the owner reviews and pushes (their established habit).
