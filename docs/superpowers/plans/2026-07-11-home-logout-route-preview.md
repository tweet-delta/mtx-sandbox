# Home-Screen Logout + "Preview as Tech" Implementation Plan

> **For agentic workers:** REQUIRED SUB-SKILL: Use superpowers:subagent-driven-development (recommended) or superpowers:executing-plans to implement this plan task-by-task. Steps use checkbox (`- [ ]`) syntax for tracking.

**Goal:** Add a Sign out button to the home screen (sharing one handler with the sidebar's) and a supervisor-only "Preview as tech" toggle on the Routes screen that flips the UI to what a chosen route's tech sees — purely client-side, no DB writes, no impersonation.

**Architecture:** Both features live in the existing two files. `cloud.js` (the data layer) gains one generic sign-out binding and exposes its existing `loadMyRoute` as `window.cloud.refreshMyRoute` so the app can ask it to re-derive route scoping after exiting preview. Everything else is `index.html`: a fixed banner element, a preview state block next to the existing `MY_HOUSE_NAMES` scoping state, and a "Preview as tech" section rendered at the top of the Routes screen. Preview reuses the exact same scoping variable (`MY_HOUSE_NAMES`) that real tech scoping uses, so the picker behaves identically to a real tech's — including the empty-route message and the "Show all houses…" button.

**Tech Stack:** Vanilla HTML/CSS/JS (no deps, no build step), Supabase via `cloud.js`. Deployed by pushing branch `claude/claude-code-tutorial-5l5ew2` — **GitHub Pages serves THIS branch**, not `main`.

## Global Constraints

- Public repo: **no secrets, no real house data** (existing seed data is confirmed fake).
- Vanilla JS only — no new dependencies, no build step.
- Accessibility: `aria-*` where state changes, `:focus-visible` outlines, ≥44px tap targets on new buttons.
- Never lose a tech's in-progress work: preview must not touch the local visit buffer or saved state.
- UI hides, **RLS enforces**: preview is a view flip only; the signed-in supervisor's real permissions never change.
- No automated test framework exists; verification is driving the flow in a real browser (live GitHub Pages site) per CLAUDE.md.
- Service worker cache is `route-checklist-v6` in `sw.js:7`; bump to `v7` with this ship so the owner's phone PWA picks it up.

---

### Task 1: Home-screen Sign out button with one shared handler

**Files:**
- Modify: `route-checklist/index.html` (home screen HTML ~line 635, CSS ~line 500, sidebar button line 681)
- Modify: `route-checklist/cloud.js` (lines 20, 415)

**Interfaces:**
- Consumes: `supabase.auth.signOut()` (existing).
- Produces: the convention `data-sign-out` — ANY element with this attribute becomes a sign-out button. Task 2 does not depend on this task.

- [ ] **Step 1: Add the button to the home screen**

In `route-checklist/index.html`, inside `<div id="homeScreen">`, immediately after the `homeRoutes` button (after line 636), add:

```html
  <button type="button" class="home-signout" data-sign-out>Sign out</button>
```

- [ ] **Step 2: Convert the sidebar button to the shared convention**

Line 681, change:

```html
    <button type="button" id="signOutBtn">Sign out</button>
```

to:

```html
    <button type="button" data-sign-out>Sign out</button>
```

(The `#account button` element selector styles it, so dropping the id changes nothing visually. Nothing else references `signOutBtn` — verified by grep; only `cloud.js:20`/`cloud.js:415`, both replaced in Step 4.)

- [ ] **Step 3: Style the home-screen button**

In the `<style>` block, right after `.home-btn:focus-visible { ... }` (line 500), add:

```css
  .home-signout {
    display: block; margin: 24px auto 0;
    font: inherit; font-size: 0.9rem; font-weight: 600;
    background: none; color: var(--muted);
    border: 1px solid var(--line); border-radius: 8px;
    padding: 10px 18px; min-height: 44px; cursor: pointer;
  }
  .home-signout:hover { border-color: var(--accent); color: var(--accent); }
  .home-signout:focus-visible { outline: 2px solid var(--ink); outline-offset: 2px; }
```

Quiet styling is deliberate: it must not compete with the three big task buttons.

- [ ] **Step 4: One handler for all sign-out buttons in cloud.js**

Delete line 20:

```js
const signOutBtn = document.getElementById("signOutBtn");
```

Replace line 415 (`signOutBtn?.addEventListener("click", () => supabase.auth.signOut());`) with:

```js
// Every sign-out button (houses sidebar + home screen) shares this one handler.
document.querySelectorAll("[data-sign-out]").forEach(btn =>
  btn.addEventListener("click", () => supabase.auth.signOut()));
```

(Safe timing: `cloud.js` is a `<script type="module">` loaded at the end of `<body>`, so all buttons exist when it runs.)

- [ ] **Step 5: Static sanity check**

Open `route-checklist/index.html` from disk in a browser. Expected: auth gate shows (fail-closed), no console errors. Auth can't complete on `file://` — full check is Task 3 on the live site.

- [ ] **Step 6: Commit**

```bash
git add route-checklist/index.html route-checklist/cloud.js
git commit -m "Home screen: Sign out button, shared handler with sidebar"
```

---

### Task 2: "Preview as tech" (by route) on the Routes screen

**Files:**
- Modify: `route-checklist/index.html` (banner HTML after authGate ~line 585, CSS after `.house-route-row` line 566, preview state at the `applyMyHouses` block lines 1079–1086, `renderRoutesScreen` lines 2141–2183, routesBody click delegate lines 2185–2197)
- Modify: `route-checklist/cloud.js` (the `window.cloud = { ... }` export, lines 373–377)
- Modify: `route-checklist/sw.js` line 7 (cache bump)

**Interfaces:**
- Consumes: `window.cloud.listHousesForRoutes()` → `[{id, name, routeId}]`; `window.cloud.role`; existing `MY_HOUSE_NAMES` / `pickerShowAll` / `rebuild()` / `escAttr` / `escHtml`.
- Produces: `window.cloud.refreshMyRoute()` (alias of `loadMyRoute`, re-pushes scoping via `applyMyHouses`); app-side `startPreview(routeName, Set)` / `exitPreview()` / `clearPreviewUI()`; `body.previewing` CSS class.

- [ ] **Step 1: Banner HTML**

In `index.html`, immediately after `</div>` closing `#authGate` (line 585), add:

```html
<div id="previewBanner" role="status" hidden>
  <span id="previewLabel"></span>
  <button type="button" id="previewExit">Exit preview</button>
</div>
```

- [ ] **Step 2: Banner CSS**

After the `.house-route-row { justify-content: space-between; }` rule (line 566), add:

```css
  /* "Preview as tech": fixed strip while a supervisor is previewing a route.
     z-index 18 keeps it under the sidebar (20), its backdrop (19), and the
     auth gate (100), but over the sticky visit header (5). */
  #previewBanner {
    position: fixed; top: 0; left: 0; right: 0; z-index: 18;
    display: flex; align-items: center; justify-content: space-between; gap: 10px;
    min-height: 48px; padding: 6px 12px;
    background: var(--note-bg); color: var(--note);
    border-bottom: 1px solid var(--note);
    font-size: 0.88rem; font-weight: 700;
  }
  #previewBanner[hidden] { display: none; }
  #previewBanner span { overflow: hidden; text-overflow: ellipsis; white-space: nowrap; }
  #previewBanner button {
    flex: none; font: inherit; font-size: 0.85rem; font-weight: 600;
    padding: 8px 14px; min-height: 40px; border-radius: 8px;
    border: 1px solid var(--note); background: var(--card); color: var(--note); cursor: pointer;
  }
  #previewBanner button:focus-visible { outline: 2px solid var(--ink); outline-offset: 2px; }
  body.previewing { padding-top: 48px; }
  body.previewing .visit { top: 48px; } /* sticky visit header clears the banner */
```

- [ ] **Step 3: Preview state + start/exit, and guard `applyMyHouses`**

In the main script, replace the existing block at lines 1079–1086:

```js
  let MY_HOUSE_NAMES = null;
  // The tech tapped "Show all houses…" (float day / covering another route).
  // Reset each time the picker is opened fresh from Home.
  let pickerShowAll = false;
  window.applyMyHouses = function (names) {
    MY_HOUSE_NAMES = names instanceof Set ? names : null;
    rebuild();
  };
```

with:

```js
  let MY_HOUSE_NAMES = null;
  // The tech tapped "Show all houses…" (float day / covering another route).
  // Reset each time the picker is opened fresh from Home.
  let pickerShowAll = false;

  // ---- "Preview as tech" (supervisor-only, purely client-side) ----
  // Flips the UI to what a route's tech sees: admin controls hidden, pickers
  // scoped to that route. No DB writes and no impersonation — the supervisor
  // stays signed in as themselves and RLS still governs real access.
  let previewingRoute = null;   // route NAME while previewing, else null
  const previewBanner = document.getElementById("previewBanner");
  const previewLabel  = document.getElementById("previewLabel");
  function clearPreviewUI() {
    previewingRoute = null;
    previewBanner.hidden = true;
    document.body.classList.remove("previewing");
  }
  function startPreview(routeName, houseNames) {
    previewingRoute = routeName;
    previewLabel.textContent = "Previewing " + routeName;
    previewBanner.hidden = false;
    document.body.classList.add("previewing");
    document.body.classList.remove("is-admin");   // hide supervisor controls
    MY_HOUSE_NAMES = houseNames;                  // scope pickers like the tech's
    pickerShowAll = false;
    location.hash = "#home";                      // land where the tech lands
    rebuild();
  }
  function exitPreview() {
    clearPreviewUI();
    document.body.classList.toggle("is-admin",
      !!window.cloud && window.cloud.role === "supervisor");
    // Re-derive the real scoping from the cloud layer (supervisor → unscoped).
    if (window.cloud && window.cloud.refreshMyRoute) window.cloud.refreshMyRoute();
    else window.applyMyHouses(null);
  }
  document.getElementById("previewExit").addEventListener("click", exitPreview);

  window.applyMyHouses = function (names) {
    // A real push from the cloud layer (sign-in/out, route reload) always
    // wins over a preview — otherwise a stale banner could survive a sign-out.
    if (previewingRoute !== null) clearPreviewUI();
    MY_HOUSE_NAMES = names instanceof Set ? names : null;
    rebuild();
  };
```

- [ ] **Step 4: Preview control at the top of the Routes screen**

In `renderRoutesScreen()`, after `const houseRows = ...` (ends line 2175) and before `body.innerHTML = ...` (line 2176), add:

```js
    const previewSec = `
      <div class="notes-sec"><h2>Preview as tech</h2>
        <p class="screen-sub">See the app the way a route's tech sees it. Look only — you stay signed in as yourself.</p>
        <div class="route-row">
          <select id="previewRouteSel" aria-label="Route to preview">
            ${routes.map(r => `<option value="${escAttr(r.id)}">${escHtml(r.name)}</option>`).join("")}
          </select>
          <button type="button" data-preview-start>Preview</button>
        </div></div>`;
```

Then change the start of the template literal on line 2176 from:

```js
    body.innerHTML = `
      <div class="notes-sec"><h2>Routes &amp; techs</h2>
```

to:

```js
    body.innerHTML = previewSec + `
      <div class="notes-sec"><h2>Routes &amp; techs</h2>
```

- [ ] **Step 5: Start-preview click handling**

In the existing `routesBody` click delegate (line 2185), add a branch at the top, before `const btn = e.target.closest("[data-route-save]");`:

```js
    if (e.target.closest("[data-preview-start]")) {
      const sel = document.getElementById("previewRouteSel");
      const routeName = sel.options[sel.selectedIndex].textContent;
      const houses = window.cloud.listHousesForRoutes()
        .filter(h => h.routeId === sel.value)
        .map(h => h.name.trim().toLowerCase());
      startPreview(routeName, new Set(houses));
      return;
    }
```

(An empty route yields an empty Set — `pickListHTML` already shows the "No houses are assigned to your route yet" message plus the Show-all button for that case; that behavior is wanted in preview too.)

- [ ] **Step 6: Expose `refreshMyRoute` from cloud.js**

In `cloud.js`, in the `window.cloud = { ... }` export (lines 373–377), add `refreshMyRoute: loadMyRoute,` so it reads:

```js
window.cloud = { saveVisit, loadInProgress, lastDone, listInProgress,
                 getHouseNotes, suggestNote, withdrawSuggestion,
                 approveSuggestion, dismissSuggestion, saveGeneralNotes,
                 listRoutes, listTechs, saveRoute, setHouseRoute, listHousesForRoutes,
                 refreshMyRoute: loadMyRoute,
                 role: null };
```

- [ ] **Step 7: Bump the service-worker cache**

`route-checklist/sw.js` line 7: `"route-checklist-v6"` → `"route-checklist-v7"`. Reason: the owner's own phone PWA caches the shell; without a bump they can't verify this ship on the phone. (Techs still don't have the app, so nobody else is affected.)

- [ ] **Step 8: Static sanity check**

Open `route-checklist/index.html` from disk: auth gate shows, no console errors, banner absent. Full flow is Task 3.

- [ ] **Step 9: Commit**

```bash
git add route-checklist/index.html route-checklist/cloud.js route-checklist/sw.js
git commit -m "Routes screen: supervisor Preview-as-tech (by route), client-side only"
```

---

### Task 3: Push, live verification, tech-routes E2E test, handoff

**Files:**
- Modify: `route-checklist/HANDOFF.md` (new state section at top)

**Interfaces:**
- Consumes: everything above; live site `https://tweet-delta.github.io/mtx-sandbox/route-checklist/index.html#home`; owner's supervisor login + `tech1@example.com`.
- Produces: verified features + updated handoff.

- [ ] **Step 1: Push the branch (this deploys — Pages serves this branch)**

```bash
git push origin claude/claude-code-tutorial-5l5ew2
```

- [ ] **Step 2: Live verification with the owner (they drive; auth can't be automated here)**

On the live site, hard-refresh (Ctrl+Shift+R; may take two refreshes for the v7 service worker to take over), then as **supervisor**:
1. Home screen shows a quiet "Sign out" button under the four big buttons; tapping it returns to the login gate; sidebar Sign out still works too.
2. Sign back in → 🗺️ Routes → "Preview as tech" section at the TOP with a route dropdown + Preview button.
3. Preview Route 1 → lands on Home, amber "Previewing Route 1 — Exit preview" banner fixed at top, 🗺️ Routes button GONE, New-visit picker shows only Route 1's houses with "Show all houses…" underneath (or the "No houses assigned" message if the route is empty).
4. Exit preview → banner gone, Routes button back, picker unscoped.
5. Sign out WHILE previewing → gate shows; sign back in → no stale banner.

- [ ] **Step 3: The pending tech-routes E2E test (from the 2026-07-11 tech-routes plan, Task 6)**

As supervisor: assign tech1 to Route 1 and put 140th Lane East, 140th Lane West, 16th Avenue, 92nd Crescent on Route 1 (TEST RUN, not real geography). Then sign in as `tech1@example.com`: New-visit picker shows exactly those 4 houses + "Show all houses…" reveals the rest; Continue and House Notes remain unscoped.

- [ ] **Step 4: Update HANDOFF.md**

Add a new "STATE AS OF" section at the top: what shipped (home logout, preview-as-tech, cache v7), the `data-sign-out` convention, `refreshMyRoute`, preview's purely-client-side nature, and the E2E result (pass/fail per step).

- [ ] **Step 5: Commit and push**

```bash
git add route-checklist/HANDOFF.md
git commit -m "Handoff: home logout + preview-as-tech shipped, E2E results"
git push origin claude/claude-code-tutorial-5l5ew2
```
