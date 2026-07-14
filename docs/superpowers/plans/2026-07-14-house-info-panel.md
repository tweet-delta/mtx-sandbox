# In-checklist House Info Panel Implementation Plan

> **For agentic workers:** REQUIRED SUB-SKILL: Use superpowers:subagent-driven-development (recommended) or superpowers:executing-plans to implement this plan task-by-task. Steps use checkbox (`- [ ]`) syntax for tracking.

**Goal:** Give a tech a one-tap ℹ️ button in the sticky checklist header that opens a modal panel showing the current house's codes + info, and slim the ☰ sidebar down to an account-only menu.

**Architecture:** Front-end only, all in `route-checklist/index.html`. Codes and info both come from data already in memory on the device — `ALL_CODES` (from the gitignored `house-codes.local.js`) and `h.info` (from the houses cache). No database, no migration, no `cloud.js` change, no RLS change. We reuse the existing survey `<dialog>` modal pattern and the existing `.info-item` / `.info-item.code` styles, so the panel body is essentially today's `renderHouseInfo()` markup relocated into a modal.

**Tech Stack:** Vanilla HTML/CSS/JS (no build step, no deps), native `<dialog>`, existing service worker (`sw.js`).

## Global Constraints

- **Single file for app logic:** all changes live in `route-checklist/index.html` except the SW cache bump in `route-checklist/sw.js`. Copied verbatim from spec: "This is a **front-end-only** slice: no migration, no `cloud.js` change, no RLS change."
- **No new dependencies.** Vanilla JS only.
- **Accessibility is required:** `aria-label` on the ℹ️ button, focus-visible ring, modal focus trap, Esc to close, focus returns to the ℹ️ button on close, `prefers-reduced-motion` respected (inherited from the existing modal pattern).
- **Escape all house-derived strings** with the existing `escHtml` / `escAttr` helpers (codes and info are user/owner data).
- **No automated test harness exists** in this repo (per `CLAUDE.md`). "Verify" means driving the app in a real browser and confirming behavior, plus a headless-Chrome parse check (zero console errors) after markup/JS edits. Every task's verification is manual/observational, not `pytest`.
- **Service worker:** bump `CACHE` in `sw.js` from `route-checklist-v19` to `route-checklist-v20` so devices pick up the changed `index.html`. Remind the owner to hard-refresh (Ctrl+Shift+R) and fully close/reopen the PWA.

---

## File structure

- **Modify** `route-checklist/index.html`:
  - Add the ℹ️ button to the visit header `.titlerow` (~line 711).
  - Add a `<dialog id="houseInfoModal">` near the survey modal (~line 728–740).
  - Add a `renderHouseInfoInto(el)` helper; repoint `renderHouseInfo()` at it.
  - Add `openHouseInfo()` / close wiring + ℹ️ visibility toggle in `hydrate()`.
  - Change `☰ Houses` button to `👤` (account); remove sidebar house list, search input, 🔍 toggle, and their handlers/JS.
- **Modify** `route-checklist/sw.js`: cache bump v19 → v20.
- **Modify** `route-checklist/HANDOFF.md`: new state entry.

Task order is deliberate: build the new panel first (Task 1–2) while the old sidebar path still works as a reference/fallback, then remove the old sidebar house UI (Task 3), then housekeeping (Task 4). Each task leaves the app runnable.

---

### Task 1: Add the ℹ️ button and an empty House Info modal

**Files:**
- Modify: `route-checklist/index.html` (header `.titlerow` ~line 711; add `<dialog>` after the survey modal ~line 740; CSS near the existing `.info-item` block ~line 403)

**Interfaces:**
- Consumes: existing `.menu-btn` button styling, existing `<dialog id="surveyModal">` markup pattern (`.modal-card` / `.modal-head` / `.modal-x` / `.modal-body`).
- Produces: DOM ids `houseInfoBtn` (the header button), `houseInfoModal` (the dialog), `houseInfoClose` (its ✕), `houseInfoBody` (the body container). Later tasks fill and open it.

- [ ] **Step 1: Add the ℹ️ button to the visit header**

In `route-checklist/index.html`, the `.titlerow` currently reads:

```html
    <div class="titlerow">
      <button type="button" class="menu-btn" data-nav-home aria-label="Back to home">← Home</button>
      <button id="menuBtn" class="menu-btn" aria-label="Pick house">☰ Houses</button>
      <h1>Maintenance House Visit</h1>
    </div>
```

Add the ℹ️ button after the `#menuBtn` button. Start it hidden (no house selected yet); Task 2 toggles it:

```html
    <div class="titlerow">
      <button type="button" class="menu-btn" data-nav-home aria-label="Back to home">← Home</button>
      <button id="menuBtn" class="menu-btn" aria-label="Pick house">☰ Houses</button>
      <button type="button" id="houseInfoBtn" class="menu-btn" aria-label="House info" hidden>ℹ️ House info</button>
      <h1>Maintenance House Visit</h1>
    </div>
```

- [ ] **Step 2: Add the House Info modal markup**

After the closing `</dialog>` of `#surveyModal` (right after ~line 740, before `<div class="report-bar">`), add:

```html
<dialog id="houseInfoModal" aria-label="House info">
  <div class="modal-card">
    <div class="modal-head">
      <h2 id="houseInfoTitle">House info</h2>
      <button type="button" class="modal-x" id="houseInfoClose" aria-label="Close">✕</button>
    </div>
    <div class="modal-body" id="houseInfoBody"></div>
  </div>
</dialog>
```

- [ ] **Step 3: Add minimal CSS for the modal's info list**

The existing `#houseInfo h3` / `.info-item` rules are scoped to the sidebar's `#houseInfo`. The modal body reuses `.info-item` (already global) but the section heading was `#houseInfo h3`. Add a global heading class near the `.info-item` rules (~line 403) so the modal can show section headings without depending on `#houseInfo`:

```css
  .info-head {
    font-size: 0.68rem; font-weight: 700; text-transform: uppercase;
    letter-spacing: 0.1em; color: var(--muted); margin: 12px 0 8px;
  }
  .info-head:first-child { margin-top: 0; }
```

- [ ] **Step 4: Parse check**

Run (headless Chrome, adjust the binary path if needed):

```bash
cd "c:/Big Dogs Apps/MTX Checklist V1"
"/c/Program Files/Google/Chrome/Application/chrome.exe" --headless --disable-gpu --dump-dom "file:///c:/Big Dogs Apps/MTX Checklist V1/route-checklist/index.html" > /dev/null 2>&1 && echo "loaded"
```

Expected: `loaded` (page parses). The ℹ️ button and modal exist in the DOM but the button is `hidden` and nothing opens it yet — that's correct for this task.

- [ ] **Step 5: Commit**

```bash
git add route-checklist/index.html
git commit -m "feat: add hidden House info button + modal shell to checklist header"
```

---

### Task 2: Fill and open the panel; toggle button visibility with house state

**Files:**
- Modify: `route-checklist/index.html` — `renderHouseInfo()` (~line 1978); `hydrate()` (~line 1464); add `openHouseInfo()` + wiring near the other modal handlers.

**Interfaces:**
- Consumes: `houseInfoBtn`, `houseInfoModal`, `houseInfoClose`, `houseInfoBody`, `houseInfoTitle` (Task 1); existing `currentHouse()`, `ALL_CODES`, `escHtml`, `escAttr`; existing `.info-item` / `.info-item.code` / `.info-head` classes.
- Produces: `renderHouseInfoInto(el)` (fills a given element with the current house's codes + info), `openHouseInfo()` (populates + shows the modal). `renderHouseInfo()` becomes a thin wrapper that fills the sidebar `#houseInfo` (kept working until Task 3 removes it).

- [ ] **Step 1: Extract a reusable renderer**

Replace the existing `renderHouseInfo()` (~lines 1978–1988):

```javascript
  function renderHouseInfo() {
    const box = document.getElementById("houseInfo");
    const h = currentHouse();
    if (!h) { box.innerHTML = ""; return; }
    const rows = [`<h3>${escHtml(h.name)} — house info</h3>`];
    (ALL_CODES[h.name] || []).forEach(([label, val]) =>
      rows.push(`<div class="info-item code"><b>${escHtml(label)}</b>${escHtml(val)}</div>`));
    (h.info || []).forEach(([label, val]) =>
      rows.push(`<div class="info-item"><b>${escHtml(label)}</b>${escHtml(val)}</div>`));
    box.innerHTML = rows.join("");
  }
```

with a shared renderer plus a thin sidebar wrapper (the sidebar `#houseInfo` still exists until Task 3):

```javascript
  // Build the current house's codes + info into `el`. Codes come from
  // ALL_CODES (house-codes.local.js, on-device only); info from h.info.
  // If the local codes file isn't present, ALL_CODES[h.name] is empty and the
  // codes section is simply omitted (no error, no empty header).
  function renderHouseInfoInto(el) {
    const h = currentHouse();
    if (!h) { el.innerHTML = ""; return; }
    const codes = ALL_CODES[h.name] || [];
    const info = h.info || [];
    const rows = [];
    if (codes.length) {
      rows.push(`<div class="info-head">Codes</div>`);
      codes.forEach(([label, val]) =>
        rows.push(`<div class="info-item code"><b>${escHtml(label)}</b>${escHtml(val)}</div>`));
    }
    if (info.length) {
      rows.push(`<div class="info-head">House info</div>`);
      info.forEach(([label, val]) =>
        rows.push(`<div class="info-item"><b>${escHtml(label)}</b>${escHtml(val)}</div>`));
    }
    if (!rows.length) rows.push(`<div class="info-item">No codes or info on file for this house.</div>`);
    el.innerHTML = rows.join("");
  }

  function renderHouseInfo() {
    const box = document.getElementById("houseInfo");
    if (box) renderHouseInfoInto(box);
  }
```

- [ ] **Step 2: Add `openHouseInfo()` and modal open/close wiring**

Add near the other modal handlers (anywhere in the main `<script>`, e.g. just after `renderHouseInfo`):

```javascript
  function openHouseInfo() {
    const h = currentHouse();
    if (!h) return;
    document.getElementById("houseInfoTitle").textContent = h.name + " — house info";
    renderHouseInfoInto(document.getElementById("houseInfoBody"));
    document.getElementById("houseInfoModal").showModal();
  }
  document.getElementById("houseInfoBtn").addEventListener("click", openHouseInfo);
  document.getElementById("houseInfoClose").addEventListener("click", () =>
    document.getElementById("houseInfoModal").close());
```

Native `<dialog>.showModal()` gives Esc-to-close and focus trapping for free, and focus returns to the invoking `houseInfoBtn` on close — matching the survey modal.

- [ ] **Step 3: Toggle the ℹ️ button with house state in `hydrate()`**

`hydrate()` runs on every `rebuild()` (house change, resume, load). It already sets the house field (~line 1467). Right after that line:

```javascript
    document.getElementById("house").value = s.house || "";
```

add:

```javascript
    document.getElementById("houseInfoBtn").hidden = !currentHouse();
```

So the ℹ️ button shows exactly when a real house is selected and hides on "(no house — full checklist)".

- [ ] **Step 4: Drive it in a browser**

Open the app (served or `file://`), sign in / pick a house that has codes locally. Confirm:
- ℹ️ appears in the header only after a house is chosen; hidden for "no house".
- Tapping ℹ️ opens the modal titled "`<House>` — house info", codes section first (from `house-codes.local.js`), then house info.
- Esc closes; ✕ closes; focus returns to the ℹ️ button (Tab shows the ring back on ℹ️).
- Pick a house with no info/codes → modal shows the "No codes or info on file" line, no error.
- Headless parse check as in Task 1 Step 4 → `loaded`, and open DevTools console → no errors.

- [ ] **Step 5: Commit**

```bash
git add route-checklist/index.html
git commit -m "feat: open House info panel from the checklist header ℹ️ button"
```

---

### Task 3: Slim the ☰ sidebar to an account-only menu

**Files:**
- Modify: `route-checklist/index.html` — sidebar markup (~lines 825–844), `renderHouseList` (~1965), `openSidebar` (~1990), `toggleHouseSearch` (~2007), the sidebar event handlers (~2021–2033), header button (~711).

**Interfaces:**
- Consumes: the ℹ️ panel from Task 2 (the only remaining way to see house info on the checklist screen).
- Produces: a sidebar containing only the `#account` block; `openSidebar()` no longer references the removed elements. `renderHouseInfoInto` is still used by the modal (do NOT delete it).

- [ ] **Step 1: Confirm nothing else depends on the house-list pieces**

```bash
cd "c:/Big Dogs Apps/MTX Checklist V1"
grep -nE "renderHouseList|houseSearchToggle|toggleHouseSearch|getElementById\(.houseList.\)|getElementById\(.houseSearch.\)" route-checklist/index.html
```

Expected: matches only inside the sidebar block, `renderHouseList` itself, `openSidebar`, `toggleHouseSearch`, and the sidebar event handlers — all of which this task removes. The up-front checklist house *picker* uses the `#house` field and `applyMyHouses`/`selectHouse` (a different mechanism) and must NOT be touched. If grep shows a dependency outside these, stop and reassess.

- [ ] **Step 2: Change the header button to an account menu**

Replace (~line 711):

```html
      <button id="menuBtn" class="menu-btn" aria-label="Pick house">☰ Houses</button>
```

with:

```html
      <button id="menuBtn" class="menu-btn" aria-label="Account">👤</button>
```

- [ ] **Step 3: Slim the sidebar markup**

Replace the sidebar's header + list + info (~lines 825–833):

```html
<aside id="sidebar" hidden aria-label="House picker">
  <h2>
    <button type="button" class="sidebar-search-toggle" id="houseSearchToggle" aria-label="Search houses" aria-expanded="false">🔍</button>
    <span class="sidebar-title">Houses</span>
    <button type="button" class="modal-x" id="sidebarClose" aria-label="Close">✕</button>
  </h2>
  <input type="search" id="houseSearch" placeholder="Search houses…" aria-label="Search houses" hidden>
  <div id="houseList"></div>
  <div id="houseInfo"></div>
```

with:

```html
<aside id="sidebar" hidden aria-label="Account menu">
  <h2>
    <span class="sidebar-title">Account</span>
    <button type="button" class="modal-x" id="sidebarClose" aria-label="Close">✕</button>
  </h2>
```

(Leave the `#account` block below it untouched.)

- [ ] **Step 4: Remove the now-dead JS**

Delete `renderHouseList()` (~1965–1976) entirely. Delete `toggleHouseSearch()` (~2007–2019) entirely. Delete these event-handler lines (~2023–2033):

```javascript
  document.getElementById("houseSearchToggle").addEventListener("click", toggleHouseSearch);
```

```javascript
  document.getElementById("houseSearch").addEventListener("input", renderHouseList);
  document.getElementById("houseList").addEventListener("click", e => {
    const btn = e.target.closest("[data-house]");
    if (!btn) return;
    selectHouse(btn.dataset.house);
    renderHouseList();
    renderHouseInfo();
    closeSidebar();
  });
```

- [ ] **Step 5: Simplify `openSidebar()`**

Replace (~1990–2001):

```javascript
  function openSidebar() {
    // Always open with search collapsed and cleared, so the list starts at full
    // height and no stale filter from a previous open is silently applied.
    const search = document.getElementById("houseSearch");
    search.value = "";
    search.hidden = true;
    document.getElementById("houseSearchToggle").setAttribute("aria-expanded", "false");
    renderHouseList();
    renderHouseInfo();
    sidebar.hidden = false;
    sideBackdrop.hidden = false;
  }
```

with:

```javascript
  function openSidebar() {
    sidebar.hidden = false;
    sideBackdrop.hidden = false;
  }
```

`renderHouseInfo()` (the thin sidebar wrapper) is now unused. Delete it too — the modal uses `renderHouseInfoInto` directly. Remove the `renderHouseInfo` function (the wrapper added in Task 2 Step 1). Keep `renderHouseInfoInto`.

- [ ] **Step 6: Remove the orphaned sidebar-house CSS (optional cleanup)**

The `#houseSearch`, `#houseList`, `.house-btn`, `#houseInfo`, `.sidebar-search-toggle` selectors are now dead. Removing them is safe but optional. If removing, delete the `#houseSearch {…}` block (~384), `.house-btn` rules (~389–397), and `#houseInfo` / `#houseInfo h3` rules (~398–402). Keep `.info-item` / `.info-item.code` (used by the modal). If unsure, leave them — dead CSS is harmless; do NOT remove `.info-item*` or `.info-head`.

- [ ] **Step 7: Drive it in a browser**

- Tap 👤 in the header → sidebar opens showing only Account (signed-in-as, Set/change password, Sign out) — no house list, no search box.
- Confirm house switching still works via ← Home → 🏠 New house visit, and that switching away from a house with unsaved work still prompts to confirm (via `selectHouse`).
- Confirm the up-front house picker (the `#house` field when no house is chosen) still selects a house.
- ℹ️ panel (Task 2) still opens and shows codes + info.
- Headless parse check → `loaded`; DevTools console → no `renderHouseList is not defined` / no reference errors.

- [ ] **Step 8: Commit**

```bash
git add route-checklist/index.html
git commit -m "feat: slim ☰ sidebar to an account-only 👤 menu; house info now via ℹ️ panel"
```

---

### Task 4: Housekeeping — SW cache bump + HANDOFF

**Files:**
- Modify: `route-checklist/sw.js` (line 7); `route-checklist/HANDOFF.md` (new state entry at top).

**Interfaces:**
- Consumes: nothing.
- Produces: nothing (docs + cache version only).

- [ ] **Step 1: Bump the service worker cache**

In `route-checklist/sw.js` line 7, change:

```javascript
const CACHE = "route-checklist-v19";
```

to:

```javascript
const CACHE = "route-checklist-v20";
```

- [ ] **Step 2: Add a HANDOFF entry**

Add a new dated section at the top of `route-checklist/HANDOFF.md` (below the SLICE 4 note, above the 2026-07-14 Daily Logs section) summarizing: ℹ️ House info button in the sticky checklist header opens a modal panel (codes from `house-codes.local.js` first, then house info); the ☰ sidebar became a 👤 account-only menu (house list/search removed); **codes deliberately stay local-only — not moved to Supabase** (honors the existing compliance posture); front-end-only, no migration/cloud.js change; SW cache v19 → v20. Include the live-verify checklist from the spec and the hard-refresh + close/reopen-PWA reminder. Reference `docs/superpowers/specs/2026-07-14-house-info-panel-design.md` and this plan.

- [ ] **Step 3: Final parse check**

```bash
cd "c:/Big Dogs Apps/MTX Checklist V1"
"/c/Program Files/Google/Chrome/Application/chrome.exe" --headless --disable-gpu --dump-dom "file:///c:/Big Dogs Apps/MTX Checklist V1/route-checklist/index.html" > /dev/null 2>&1 && echo "loaded"
```

Expected: `loaded`.

- [ ] **Step 4: Commit**

```bash
git add route-checklist/sw.js route-checklist/HANDOFF.md
git commit -m "chore: bump SW cache to v20; HANDOFF for in-checklist house info panel"
```

---

## Self-review notes

- **Spec coverage:** ℹ️ button in sticky header (Task 1–2) ✓; modal panel codes-first then info (Task 2) ✓; codes stay local via `ALL_CODES`, section omitted when file absent (Task 2 renderer) ✓; slim sidebar to account menu + 👤 (Task 3) ✓; house-switch via ← Home preserved (Task 3 Step 7 verify) ✓; SW bump + HANDOFF + reminders (Task 4) ✓; no DB/migration/cloud.js/RLS change (front-end-only, honored throughout) ✓.
- **Type consistency:** `renderHouseInfoInto(el)` defined in Task 2, consumed by the modal in Task 2 and kept alive in Task 3; `renderHouseInfo` wrapper is introduced in Task 2 and removed in Task 3 once the sidebar `#houseInfo` is gone (documented in Task 3 Step 5). DOM ids (`houseInfoBtn`, `houseInfoModal`, `houseInfoClose`, `houseInfoBody`, `houseInfoTitle`) are created in Task 1 and used consistently in Task 2.
- **No placeholders:** every code step shows the exact before/after. Verification is browser-driven + headless parse (repo has no unit-test harness — stated in Global Constraints).
