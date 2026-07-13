# Visit History Implementation Plan

> **For agentic workers:** REQUIRED SUB-SKILL: Use superpowers:subagent-driven-development (recommended) or superpowers:executing-plans to implement this plan task-by-task. Steps use checkbox (`- [ ]`) syntax for tracking.

**Goal:** Let a signed-in tech view their own completed visits and, one tap in, see only the flagged + noted items from each visit.

**Architecture:** Two new read functions in `route-checklist/cloud.js` (`listMyVisits`, `getVisitDetail`) that query the existing `visits`/`visit_items` tables self-scoped to the signed-in user, plus a new `#history` hash-router screen in `route-checklist/index.html` that mirrors the existing `#profile` screen pattern. Flags are computed client-side from the existing `ITEM_BY_KEY`/`GROUPS` polarity — never stored. No migration, no RLS change.

**Tech Stack:** Vanilla HTML/CSS/JS (no build step, no framework), Supabase JS client (already wired via `window.cloud`), single inline `<script>` in `index.html`, separate `cloud.js` data module.

## Global Constraints

- **No new migration, no RLS/grant change.** Migrations 0001 + 0002 already grant `authenticated` staff read access to `visits`/`visit_items`; slice 2 is read-only front-end work. (spec: "Why this is a thin, front-end-only slice")
- **Self-only.** Both cloud functions must filter `tech_id = user.id`. RLS allows reading any staff visit; these filters are defense-in-depth so the "my history" screen can never surface another tech's data. (spec: "Security")
- **Flag rule (verbatim):** an item is flagged when `answer === item.bad`, where `item.bad` comes from `GROUPS`/`ITEM_BY_KEY` in `index.html` (`bad: "yes"` = "anything wrong?", `bad: "no"` = "working properly?"). NEVER denormalize a `flagged` boolean into the DB. (spec: "The flag definition")
- **Detail shows an item when** `answer === item.bad` **OR** the item has a non-empty `note`. (spec: "Components → detail view")
- **Unknown `item_key`** (in DB but not in `ITEM_BY_KEY`, i.e. removed from checklist since the visit): still show it using the raw `item_key` as a fallback label; never silently drop recorded data. (spec: "Edge cases")
- **Escape all DB-sourced strings** with the existing `escHtml`/`escAttr` (defined `index.html:1726-1727`). (spec: "Security")
- **Stale-nav guard** after every async load: `if (currentScreenFromHash() !== "history") return;` (spec: "Data flow")
- **No automated test framework exists** in this repo (CLAUDE.md: "There are no automated tests yet... Verify by actually running the app in a browser"). Each task's "test" is a static wiring check (grep/read the file) plus, for the final task, a live signed-in browser drive. Do NOT scaffold a test runner.
- **Home button** `homeHistory` is NOT `admin-only` — every tech has their own history. (spec: "Components → screen")

---

### Task 1: `listMyVisits()` in cloud.js

Adds the list-query read function. Modeled almost exactly on the existing `listInProgress()` (`cloud.js:252-267`).

**Files:**
- Modify: `route-checklist/cloud.js` (insert new function after `listInProgress`, ~line 267; add name to the `window.cloud` export object at ~line 517-525)

**Interfaces:**
- Consumes: `supabase` (module global), `supabase.auth.getUser()` (established pattern)
- Produces: `window.cloud.listMyVisits()` → `Promise<Array<{ id: string, houseName: string, visitDate: string }>>`. Returns `[]` on no-user or query error (never throws; never `null` — an empty list renders the empty state cleanly).

- [ ] **Step 1: Read the template so the new code matches it exactly**

Read `route-checklist/cloud.js:252-267` (`listInProgress`). Match its structure: `getUser` guard, `.from("visits").select(...)`, `.eq` filters, `.order`, error-logs-and-returns, `.map` to a clean shape.

- [ ] **Step 2: Insert `listMyVisits` after `listInProgress`**

Insert immediately after line 267 (the closing `}` of `listInProgress`):

```js

// Slice 2: the signed-in tech's OWN completed visits, newest first. Read-only.
// Self-scoped (tech_id = me) even though RLS permits reading any staff visit —
// the "my history" screen must never surface another tech's data.
async function listMyVisits() {
  const { data: { user } } = await supabase.auth.getUser();
  if (!user) return [];
  const { data, error } = await supabase
    .from("visits")
    .select("id, visit_date, completed_at, houses(name)")
    .eq("tech_id", user.id).eq("status", "completed")
    .order("visit_date", { ascending: false })
    .order("completed_at", { ascending: false });
  if (error) { console.error("Could not list my visits:", error.message); return []; }
  return data.map(v => ({
    id: v.id,
    houseName: v.houses?.name || "",
    visitDate: v.visit_date,
  }));
}
```

- [ ] **Step 3: Add `listMyVisits` to the `window.cloud` export object**

In the `window.cloud = { ... }` object (`cloud.js:517-525`), add `listMyVisits` to the list. Change the line `getMyProfile, saveMyProfile,` to:

```js
                 getMyProfile, saveMyProfile,
                 listMyVisits,
```

- [ ] **Step 4: Static wiring check**

Run: `grep -n "async function listMyVisits\|listMyVisits," route-checklist/cloud.js`
Expected: two matches — the function declaration and the export line.

- [ ] **Step 5: Commit**

```bash
git add route-checklist/cloud.js
git commit -m "feat: add listMyVisits to cloud.js (own completed visits)"
```

---

### Task 2: `getVisitDetail()` in cloud.js

Adds the detail-query read function. Fetches one self-owned visit plus its raw items; flag computation happens later in the UI (Task 5), not here.

**Files:**
- Modify: `route-checklist/cloud.js` (insert after `listMyVisits` from Task 1; add name to `window.cloud` export)

**Interfaces:**
- Consumes: `supabase`, `supabase.auth.getUser()`
- Produces: `window.cloud.getVisitDetail(visitId)` → `Promise<{ houseName: string, visitDate: string, items: Array<{ item_key: string, answer: string|null, note: string|null }> } | { error: string }>`. Returns `{ error }` on no-user, not-found/not-mine, or query error.

- [ ] **Step 1: Insert `getVisitDetail` after `listMyVisits`**

Insert immediately after the closing `}` of `listMyVisits`:

```js

// Slice 2: one of the signed-in tech's OWN visits + its recorded items.
// Filtered tech_id = me so a hand-typed id can't open another tech's visit.
// Returns raw items; the UI computes which are "flagged" from GROUPS polarity.
async function getVisitDetail(visitId) {
  const { data: { user } } = await supabase.auth.getUser();
  if (!user) return { error: "Not signed in." };
  const { data, error } = await supabase
    .from("visits")
    .select("visit_date, houses(name), visit_items(item_key, answer, note)")
    .eq("id", visitId).eq("tech_id", user.id)
    .maybeSingle();
  if (error) { console.error("Could not load visit:", error.message); return { error: error.message }; }
  if (!data) return { error: "Visit not found." };
  return {
    houseName: data.houses?.name || "",
    visitDate: data.visit_date,
    items: data.visit_items || [],
  };
}
```

- [ ] **Step 2: Add `getVisitDetail` to the export object**

Change the `listMyVisits,` line added in Task 1 to:

```js
                 listMyVisits, getVisitDetail,
```

- [ ] **Step 3: Static wiring check**

Run: `grep -n "async function getVisitDetail\|getVisitDetail," route-checklist/cloud.js`
Expected: two matches (declaration + export).

- [ ] **Step 4: Commit**

```bash
git add route-checklist/cloud.js
git commit -m "feat: add getVisitDetail to cloud.js (one own visit + items)"
```

---

### Task 3: `#history` screen markup + home button + routing + CSS

Wires the new screen into the shell: visibility CSS, home button, the screen `<div>`, and the two hash-router hooks. No render logic yet (Task 4/5) — this task makes the empty screen reachable.

**Files:**
- Modify: `route-checklist/index.html` — CSS visibility list (~line 485), home buttons (~line 729), screen markup (~after line 760), router `currentScreenFromHash` (~line 2538) + `showScreen` (~line 2547), home-button click handler (~line 2579)

**Interfaces:**
- Consumes: existing `screen`/`screen-head`/`menu-btn`/`data-nav-home` classes and the `currentScreenFromHash`/`showScreen` router
- Produces: reachable `#history` screen with an empty `<div id="historyBody">`; a `renderHistoryScreen()` call site (function itself is stubbed in Step 5 here, filled in Task 4)

- [ ] **Step 1: Add `#historyScreen` to the screen-visibility CSS list**

At `index.html:485`, the line is:

```css
  body:not([data-screen="profile"])  #profileScreen,
```

Add a line directly after it:

```css
  body:not([data-screen="history"])  #historyScreen,
```

- [ ] **Step 2: Add the home-screen button**

At `index.html:729`, the profile button is:

```html
  <button type="button" class="home-btn" id="homeProfile">👤 My profile
```

Insert a new button directly after that button's closing (it is a self-contained `<button>…` line ending before the next button at 731 `homeRoutes`). Add:

```html
  <button type="button" class="home-btn" id="homeHistory">🗓️ My visit history
```

Match the exact closing style of the neighbouring `homeProfile` button (copy its trailing markup verbatim, whether it closes with `</button>` on the same or next line).

- [ ] **Step 3: Add the `#historyScreen` markup**

After the `profileScreen` `</div>` (`index.html:760`) and before `routesScreen` (`index.html:762`), insert:

```html

<div id="historyScreen" class="screen" aria-label="My visit history">
  <div class="screen-head">
    <button type="button" class="menu-btn" data-nav-home>← Home</button>
    <h1>My Visit History</h1>
  </div>
  <div id="historyBody"></div>
</div>
```

- [ ] **Step 4: Add the route to `currentScreenFromHash`**

At `index.html:2538`:

```js
    if (h.startsWith("#profile")) return "profile";
```

Insert directly after it:

```js
    if (h.startsWith("#history")) return "history";
```

- [ ] **Step 5: Add the `showScreen` dispatch + a temporary stub render fn**

At `index.html:2547`:

```js
    if (scr === "profile") renderProfileScreen();
```

Insert directly after it:

```js
    if (scr === "history") renderHistoryScreen();
```

Then, so the page has no ReferenceError before Task 4 fills it in, add a stub `renderHistoryScreen` next to `renderProfileScreen` (after its closing `}` at `index.html:2743`):

```js

  async function renderHistoryScreen() {
    document.getElementById("historyBody").innerHTML = `<p class="screen-sub">Loading…</p>`;
  }
```

(Task 4 replaces this stub body.)

- [ ] **Step 6: Add the home-button click handler**

At `index.html:2579-2581` the profile handler is:

```js
  document.getElementById("homeProfile").addEventListener("click", () => {
    location.hash = "#profile";
  });
```

Insert directly after it:

```js
  document.getElementById("homeHistory").addEventListener("click", () => {
    location.hash = "#history";
  });
```

- [ ] **Step 7: Static wiring check**

Run: `grep -n "homeHistory\|historyScreen\|historyBody\|renderHistoryScreen\|#history\|data-screen=\"history\"" route-checklist/index.html`
Expected matches: the CSS rule, the home button, the screen div, the body div, the `currentScreenFromHash` route, the `showScreen` dispatch, the stub fn, and the click handler (≥8 matches).

- [ ] **Step 8: Commit**

```bash
git add route-checklist/index.html
git commit -m "feat: add reachable #history screen shell (button, markup, routing)"
```

---

### Task 4: `renderHistoryScreen()` — the list view

Fills in the list: load the tech's completed visits, render house + date rows newest-first (or an empty state / error). Delegated click navigates into detail via `#history/<id>`.

**Files:**
- Modify: `route-checklist/index.html` — replace the Task 3 stub `renderHistoryScreen`; add a `historyBody` delegated click listener

**Interfaces:**
- Consumes: `window.cloud.listMyVisits()` (Task 1); `escHtml`/`escAttr` (`index.html:1726-1727`); `currentScreenFromHash` (`index.html:2531`); `fmtDate` if present (see Step 2)
- Produces: rendered list; each row is `<button class="list-btn" data-visit-id="...">`; clicking sets `location.hash = "#history/" + id`

- [ ] **Step 1: Check the date-formatting helper name**

Run: `grep -n "function fmtDate\|const fmtDate" route-checklist/index.html`
If `fmtDate` exists, use `fmtDate(v.visitDate)` for display. If it does NOT exist, display the raw `escHtml(v.visitDate)` (ISO `YYYY-MM-DD`) instead. Use whichever the grep confirms — do not invent a helper.

- [ ] **Step 2: Replace the stub `renderHistoryScreen` body**

Replace the entire stub function added in Task 3 Step 5 with (using `fmtDate` only if Step 1 confirmed it; otherwise substitute `escHtml(v.visitDate)`):

```js
  async function renderHistoryScreen() {
    const body = document.getElementById("historyBody");
    body.innerHTML = `<p class="screen-sub">Loading…</p>`;
    const visits = await window.cloud.listMyVisits();
    if (currentScreenFromHash() !== "history") return;   // navigated away meanwhile
    if (!visits.length) {
      body.innerHTML = `<p class="screen-sub">No completed visits yet.</p>`;
      return;
    }
    body.innerHTML = visits.map(v => `
      <button type="button" class="list-btn" data-visit-id="${escAttr(v.id)}">
        <b>${escHtml(v.houseName)}</b><span>${fmtDate(v.visitDate)}</span>
      </button>`).join("");
  }
```

- [ ] **Step 3: Add the delegated click listener for list rows**

Directly after the `renderHistoryScreen` function's closing `}`, add:

```js

  document.getElementById("historyBody").addEventListener("click", e => {
    const row = e.target.closest("[data-visit-id]");
    if (!row) return;
    location.hash = "#history/" + row.dataset.visitId;
  });
```

- [ ] **Step 4: Static wiring check**

Run: `grep -n "data-visit-id\|No completed visits yet\|listMyVisits()" route-checklist/index.html`
Expected: the row template, the empty state, the delegated listener, and the `listMyVisits()` call (≥4 matches).

- [ ] **Step 5: Commit**

```bash
git add route-checklist/index.html
git commit -m "feat: render #history list (own completed visits, newest first)"
```

---

### Task 5: History detail view (flagged + noted items)

When the hash is `#history/<id>`, `renderHistoryScreen` loads that visit's detail and shows only flagged/noted items, computing flags from `ITEM_BY_KEY` polarity.

**Files:**
- Modify: `route-checklist/index.html` — extend `renderHistoryScreen` to branch on a visit id in the hash; add a small helper to render the detail

**Interfaces:**
- Consumes: `window.cloud.getVisitDetail(id)` (Task 2); `ITEM_BY_KEY` (`index.html:1106`, module-scoped — each entry has `q`+`bad` for questions or `text` for action items); `escHtml`; `fmtDate` (or raw date per Task 4 Step 1)
- Produces: detail render inside `#historyBody`

- [ ] **Step 1: Add a hash helper to read the visit id**

At the top of `renderHistoryScreen` (right after `const body = ...`), the function must decide list vs detail. Replace the `renderHistoryScreen` from Task 4 so it branches. New full function:

```js
  async function renderHistoryScreen() {
    const body = document.getElementById("historyBody");
    const m = location.hash.match(/^#history\/(.+)$/);
    if (m) { return renderVisitDetail(body, decodeURIComponent(m[1])); }
    body.innerHTML = `<p class="screen-sub">Loading…</p>`;
    const visits = await window.cloud.listMyVisits();
    if (currentScreenFromHash() !== "history") return;
    if (!visits.length) {
      body.innerHTML = `<p class="screen-sub">No completed visits yet.</p>`;
      return;
    }
    body.innerHTML = visits.map(v => `
      <button type="button" class="list-btn" data-visit-id="${escAttr(v.id)}">
        <b>${escHtml(v.houseName)}</b><span>${fmtDate(v.visitDate)}</span>
      </button>`).join("");
  }
```

(Use `escHtml(v.visitDate)` instead of `fmtDate(...)` if Task 4 Step 1 found no `fmtDate`.)

- [ ] **Step 2: Add the `renderVisitDetail` helper**

Directly after `renderHistoryScreen`'s closing `}`, add:

```js

  // Detail = only the items worth revisiting: flagged (answer === item.bad,
  // where `bad` is the item's polarity from GROUPS) OR carrying a note. An
  // item_key no longer in the checklist still shows, labelled by its raw key,
  // so history never drops what a tech actually recorded.
  async function renderVisitDetail(body, visitId) {
    body.innerHTML = `<p class="screen-sub">Loading…</p>`;
    const res = await window.cloud.getVisitDetail(visitId);
    if (currentScreenFromHash() !== "history") return;
    if (res.error) {
      body.innerHTML = `<p class="screen-sub">Couldn't load this visit — ${escHtml(res.error)}</p>`;
      return;
    }
    const shown = res.items.filter(it => {
      const def = ITEM_BY_KEY[it.item_key];
      const flagged = def && it.answer && it.answer === def.bad;
      return flagged || (it.note && it.note.trim());
    });
    const header = `
      <button type="button" class="menu-btn" data-history-back>← All visits</button>
      <h2 style="font-size:1rem">${escHtml(res.houseName)} — ${fmtDate(res.visitDate)}</h2>`;
    if (!shown.length) {
      body.innerHTML = header + `<p class="screen-sub">No issues flagged on this visit.</p>`;
      return;
    }
    const rows = shown.map(it => {
      const def = ITEM_BY_KEY[it.item_key];
      const label = def ? escHtml(def.q || def.text) : escHtml(it.item_key);
      const ans = it.answer ? `<span class="hist-answer">${escHtml(it.answer)}</span>` : "";
      const note = it.note && it.note.trim() ? `<p class="hist-note">${escHtml(it.note)}</p>` : "";
      return `<div class="hist-item"><b>${label}</b> ${ans}${note}</div>`;
    }).join("");
    body.innerHTML = header + rows;
  }
```

(Use `escHtml(res.visitDate)` instead of `fmtDate(...)` if no `fmtDate`.)

- [ ] **Step 3: Make the "← All visits" back button work**

The detail's back button (`data-history-back`) should return to the list. Extend the existing `historyBody` click listener (from Task 4 Step 3) to handle it. Replace that listener with:

```js
  document.getElementById("historyBody").addEventListener("click", e => {
    if (e.target.closest("[data-history-back]")) { location.hash = "#history"; return; }
    const row = e.target.closest("[data-visit-id]");
    if (!row) return;
    location.hash = "#history/" + row.dataset.visitId;
  });
```

Note: changing the hash from `#history/<id>` to `#history` fires `hashchange` → `showScreen` → `renderHistoryScreen`, which now re-renders the list (no id in hash). This reuses the existing router; no extra wiring.

- [ ] **Step 4: Add minimal CSS for the detail rows**

Find the `.profile-field` CSS block (search `grep -n "\.profile-field" route-checklist/index.html`). Directly after that block's closing `}`, add:

```css
  .hist-item { padding: 8px 0; border-bottom: 1px solid var(--line, #ddd); }
  .hist-item b { display: block; }
  .hist-answer { font-weight: 600; text-transform: capitalize; }
  .hist-note { margin: 4px 0 0; color: var(--muted, #555); white-space: pre-wrap; }
```

If `--line`/`--muted` CSS variables are not defined in this file (verify: `grep -n "\-\-muted\|\-\-line" route-checklist/index.html`), the fallbacks (`#ddd`/`#555`) apply — leave as written.

- [ ] **Step 5: Static wiring check**

Run: `grep -n "renderVisitDetail\|data-history-back\|ITEM_BY_KEY\[it.item_key\]\|No issues flagged\|hist-item" route-checklist/index.html`
Expected: the helper declaration + its call, the back button + its handler, the polarity lookup, the clean-visit state, and the CSS (≥5 matches).

- [ ] **Step 6: Commit**

```bash
git add route-checklist/index.html
git commit -m "feat: history detail shows only flagged + noted items"
```

---

### Task 6: Bump SW cache + live end-to-end verification

Ship-readiness: bump the service-worker cache (convention when `index.html`/`cloud.js` change) and drive the whole flow in a real signed-in browser against the visit already saved by tech one.

**Files:**
- Modify: `route-checklist/sw.js:7` (cache version)

**Interfaces:**
- Consumes: everything from Tasks 1–5
- Produces: deployable, verified slice

- [ ] **Step 1: Bump the SW cache version**

At `route-checklist/sw.js:7`:

```js
const CACHE = "route-checklist-v15";
```

Change to:

```js
const CACHE = "route-checklist-v16";
```

- [ ] **Step 2: Commit the bump**

```bash
git add route-checklist/sw.js
git commit -m "chore: bump SW cache to v16 for visit history screen"
```

- [ ] **Step 3: Live verification (must actually drive it — do not skip)**

Deploy/serve the app, hard-refresh (Ctrl+Shift+R), then, signed in as **tech one** (who has a saved completed visit):

1. Confirm "🗓️ My visit history" appears on the home screen (and is present for a non-supervisor — not gated).
2. Open it → the list shows tech one's completed visit(s): house name + date, newest first.
3. Tap the known visit → detail shows the house + date header and **only** the items that were flagged (`answer === item.bad`) or carried a note; each shows its question text, answer, and note. Cross-check against what was recorded on that visit.
4. If that visit happened to have no flags/notes, confirm the "No issues flagged on this visit." state instead.
5. Tap "← All visits" → returns to the list. Tap "← Home" → returns home.
6. **Isolation:** sign in as a second tech (or a tech with no completed visits) → confirm they do NOT see tech one's visit (empty state or only their own).
7. Reload while on `#history/<id>` → confirm it re-loads the same detail (deep-link works) with no console errors.

- [ ] **Step 4: Record the result**

If all checks pass, note it in the HANDOFF/progress notes. If anything fails, STOP and fix the cause (no bandaids) before considering the slice done.

---

## Self-Review

**1. Spec coverage:**
- Self-only completed visits list → Task 1 (`listMyVisits`, `tech_id` + `status='completed'`) + Task 4 (render). ✓
- Tap-in detail, flagged + noted only → Task 2 (`getVisitDetail`) + Task 5 (`renderVisitDetail`, `answer === def.bad || note`). ✓
- No migration / RLS change → no migration task exists; both cloud fns are reads. ✓
- Flags from `GROUPS` polarity, not stored → Task 5 uses `ITEM_BY_KEY[...].bad`. ✓
- Unknown `item_key` fallback → Task 5 `label = def ? ... : escHtml(it.item_key)` and the filter keeps noted items even when `def` is undefined. ✓
- Empty state / clean-visit state / error state → Task 4 (empty list), Task 5 (no-issues, error). ✓
- Stale-nav guard → present in Task 4 and Task 5 renders. ✓
- Escaping → `escHtml`/`escAttr` used on every DB string. ✓
- Not admin-gated → Task 3 button has no `admin-only` class. ✓
- SW bump + live drive → Task 6. ✓

**2. Placeholder scan:** No TBD/TODO; every code step shows full code; the only conditional ("use `fmtDate` if it exists") resolves to a concrete grep in Task 4 Step 1 and is threaded through Tasks 4–5. ✓

**3. Type consistency:** `listMyVisits` returns `{ id, houseName, visitDate }` — consumed with those exact names in Task 4/5. `getVisitDetail` returns `{ houseName, visitDate, items:[{item_key,answer,note}] }` — consumed with those exact names in Task 5. `renderVisitDetail(body, visitId)` signature matches its call in Task 5 Step 1. `data-visit-id` / `data-history-back` attribute names consistent between render and listener. ✓
