# Supervisor View of Team Daily Logs — Implementation Plan

> **For agentic workers:** REQUIRED SUB-SKILL: Use superpowers:executing-plans to implement this plan task-by-task. Steps use checkbox (`- [ ]`) syntax for tracking.

**Goal:** Let a supervisor open the Daily Logs screen, pick any tech (or themselves) from a dropdown, and view that person's month calendar read-only.

**Architecture:** Reuse the entire existing Daily Logs screen unchanged; only change *whose* rows feed it. One generalized data function (`listLogsInRange` gains an optional `techId`), one roster helper (`listLogTechs`), a supervisor-only `<select>`, one new state var (`logsViewTechId`), and a read-only guard on the note controls. RLS (migration 0016) already lets supervisors read every tech's rows — no migration.

**Tech Stack:** Vanilla HTML/CSS/JS single-file app; Supabase JS client; no build step; no test framework.

## Global Constraints

- **No automated tests exist.** Verify by running the app in a browser and exercising the flow (CLAUDE.md). Each task's "test" is a manual browser check.
- **RLS is the security backbone — never rely on the UI to hide data.** The supervisor read is allowed by the `daily_logs` select policy; the UI only asks.
- **Only fake/sample data** in the repo/Supabase. Test accounts: `tech1@example.com`, `tech2@example.com`. Supervisor account per HANDOFF.
- **Local preview server** already running at `http://127.0.0.1:8000/` (Python http.server in `route-checklist/`). Hard-refresh (`Ctrl+Shift+R`) after each change — stale SW cache mimics "fix didn't work."
- **No SQL migration** in this slice.

---

### Task 1: Data layer — generalize `listLogsInRange` and add `listLogTechs`

**Files:**
- Modify: `route-checklist/cloud.js` (function `listLogsInRange` ~line 345; add `listLogTechs` near `listTechs` ~line 619; export both on `window.cloud` ~line 659)

**Interfaces:**
- Produces:
  - `listLogsInRange(startDate: string, endDate: string, techId?: string) => Promise<Array<{id, logDate, kind, visitId, houseName, note, doneKeys}>>` — `techId` omitted ⇒ signed-in user's own rows (unchanged for all existing callers).
  - `listLogTechs() => Promise<{ people: Array<{id: string, label: string}>, myId: string } | { error: string }>` — roster = every tech + the signed-in user; `label` is `"You (name)"` for self.

- [ ] **Step 1: Add the optional `techId` param to `listLogsInRange`**

In `route-checklist/cloud.js`, replace the current body opener of `listLogsInRange` (the signature line and the `.eq("tech_id", user.id)` line). Current:

```js
async function listLogsInRange(startDate, endDate) {
  const { data: { user } } = await supabase.auth.getUser();
  if (!user) return [];
  const { data, error } = await supabase
    .from("daily_logs")
    .select("id, log_date, kind, visit_id, note, done_keys, houses(name)")
    .eq("tech_id", user.id)
    .gte("log_date", startDate).lte("log_date", endDate)
    .order("log_date", { ascending: true });
```

Replace with (only the signature and the `.eq` scope change; the mapping below stays as-is):

```js
// techId omitted → the signed-in user's own rows (every existing caller).
// techId passed  → that tech's rows. RLS is the real gate: a non-supervisor
// passing someone else's id gets [] back; a supervisor gets the rows.
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
```

- [ ] **Step 2: Add `listLogTechs` next to `listTechs`**

After the `listTechs` function (ends ~line 624), add:

```js
// The dropdown roster for the supervisor Daily Logs view: every tech, plus the
// signed-in user (so a supervisor can see their own diary too). Only the
// supervisor UI calls this (the dropdown is is-admin-only). Returns
// { people:[{id,label}], myId } or { error }.
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
      label: p.id === user.id ? `You (${p.full_name || "me"})`
                              : (p.full_name || "Unnamed tech"),
    }));
  return { people, myId: user.id };
}
```

- [ ] **Step 3: Export `listLogTechs` on `window.cloud`**

In the `window.cloud = { ... }` object (~line 651), the line already lists `listLogsInRange, addLogEntry, updateLogEntry, deleteLogEntry,`. Add `listLogTechs` to it:

```js
                 listLogsInRange, listLogTechs, addLogEntry, updateLogEntry, deleteLogEntry,
```

(`listLogsInRange` is already exported — its new optional param needs no export change.)

- [ ] **Step 4: Verify in the browser console**

Hard-refresh `http://127.0.0.1:8000/`, sign in as a supervisor, open DevTools console:

```js
await window.cloud.listLogTechs()
```

Expected: `{ people: [ {id, label:"You (...)"}, {id, label:"..."} ... ], myId: "..." }` — includes self (labeled "You (...)") and each tech. Then:

```js
// pick another tech's id from that list, then:
await window.cloud.listLogsInRange("2026-07-01","2026-07-31", "<that-id>")
```

Expected as **supervisor**: an array (possibly empty) of that tech's rows — no error.
Then sign in as a **tech** and repeat the second call with another tech's id.
Expected: `[]` (RLS blocks; no leak).

- [ ] **Step 5: Commit**

```bash
git add route-checklist/cloud.js
git commit -m "feat: listLogsInRange takes optional techId; add listLogTechs roster"
```

---

### Task 2: UI — dropdown, `logsViewTechId` state, read-only guard

**Files:**
- Modify: `route-checklist/index.html` (logs state ~line 2858; `renderLogsScreen` ~line 2865; `renderDayDetail` ~line 2957; the `#logsBody` click handler ~line 2976; add a `change` handler)

**Interfaces:**
- Consumes: `window.cloud.listLogsInRange(start, end, techId)`, `window.cloud.listLogTechs()` from Task 1.

- [ ] **Step 1: Add `logsViewTechId` and `logsMyId` state**

At the logs state block (~line 2858), after `let logsMonthRows = [];`, add:

```js
  let logsViewTechId = null;   // whose calendar is showing; null ⇒ me
  let logsMyId = null;         // signed-in user's id (set once the roster loads)
  let logsTechs = null;        // cached dropdown roster; null until first load
```

- [ ] **Step 2: Load the roster + render the dropdown in `renderLogsScreen`**

Replace the body of `renderLogsScreen` (lines 2865–2877) with the version below. It (a) lazy-loads the roster once for supervisors, (b) defaults `logsViewTechId` to self, (c) passes `logsViewTechId` to the query, (d) computes `readOnly` and threads it into `renderDayDetail`, (e) prepends the dropdown for admins.

```js
  async function renderLogsScreen() {
    const body = document.getElementById("logsBody");
    body.innerHTML = `<p class="screen-sub">Loading…</p>`;

    // Supervisors get a tech picker; load it once. Default the view to self.
    const isAdmin = document.body.classList.contains("is-admin");
    if (isAdmin && logsTechs === null) {
      const r = await window.cloud.listLogTechs();
      if (currentScreenFromHash() !== "logs") return;   // navigated away meanwhile
      if (!r.error) { logsTechs = r.people; logsMyId = r.myId; }
      else { logsTechs = []; }   // roster failed → fall back to own calendar
      if (logsViewTechId === null) logsViewTechId = logsMyId;  // may stay null on failure
    }

    const first = logsMonth;
    const last = new Date(first.getFullYear(), first.getMonth()+1, 0);
    const rows = await window.cloud.listLogsInRange(isoDate(first), isoDate(last), logsViewTechId);
    if (currentScreenFromHash() !== "logs") return;   // navigated away meanwhile
    logsMonthRows = rows;   // stash for renderDayDetail's diff
    const byDay = {};
    rows.forEach(r => { (byDay[r.logDate] = byDay[r.logDate] || []).push(r); });

    // Read-only whenever a supervisor is viewing someone else's calendar.
    const readOnly = isAdmin && logsMyId != null && logsViewTechId !== logsMyId;

    body.innerHTML = renderTechPicker(isAdmin)
      + renderCalHead(first) + renderGrid(first, last, byDay)
      + (logsSelectedDate ? renderDayDetail(logsSelectedDate, byDay[logsSelectedDate] || [], readOnly) : "");
  }

  // Supervisor-only tech picker. Empty string for techs (no picker).
  function renderTechPicker(isAdmin) {
    if (!isAdmin || !logsTechs || !logsTechs.length) return "";
    const opts = logsTechs.map(p =>
      `<option value="${escAttr(p.id)}"${p.id === logsViewTechId ? " selected" : ""}>${escHtml(p.label)}</option>`
    ).join("");
    return `<div class="cal-picker">
      <label for="logsTechSel">Viewing:</label>
      <select id="logsTechSel">${opts}</select>
    </div>`;
  }
```

- [ ] **Step 3: Add the `readOnly` param to `renderDayDetail`**

Change the signature (line 2957) and gate the note-editing UI. Replace the manual-notes map + the add-note block (lines 2957, 2966–2972) so that Edit/Delete/Add only render when not read-only:

```js
  function renderDayDetail(iso, dayRows, readOnly) {
    // The per-day diff needs the WHOLE month's rows (to find the prior auto
    // snapshot for the same visit), not just this day's — so use the month
    // stash set in renderLogsScreen, not dayRows.
    const monthRows = logsMonthRows;
    const autos = dayRows.filter(r => r.kind === "auto");
    const manual = dayRows.filter(r => r.kind === "manual");
    let html = `<div class="cal-detail"><h2 style="font-size:1rem">${escHtml(fmtDate(iso))}</h2>`;
    autos.forEach(auto => { html += renderAutoDetail(auto, monthRows); });
    html += manual.map(m => `<div class="cal-note" data-note-id="${escAttr(m.id)}">
      <p>${escHtml(m.note)}</p>
      ${readOnly ? "" : `<button type="button" class="menu-btn" data-note-edit="${escAttr(m.id)}" aria-label="Edit note">Edit</button>
      <button type="button" class="menu-btn" data-note-del="${escAttr(m.id)}" aria-label="Delete note">Delete</button>`}
    </div>`).join("");
    if (!readOnly) {
      html += `<div class="cal-note"><textarea id="calNoteInput" rows="2" aria-label="New note for ${escAttr(fmtDate(iso))}" placeholder="Add a note for this day…"></textarea>
        <button type="button" class="menu-btn" data-note-add aria-label="Save note">+ Add note</button></div>`;
    }
    return html + `</div>`;
  }
```

- [ ] **Step 4: Handle dropdown changes**

After the existing `#logsBody` click listener (ends ~line 3017 with its closing `});`), add a `change` listener on the same element:

```js
  document.getElementById("logsBody").addEventListener("change", e => {
    if (e.target.id === "logsTechSel") {
      logsViewTechId = e.target.value;
      logsSelectedDate = null;   // don't show one tech's day under another's grid
      renderLogsScreen();
    }
  });
```

- [ ] **Step 5: Add minimal picker styling**

In the calendar CSS block (near `.cal-head`, ~line 561), add:

```css
  .cal-picker { display:flex; align-items:center; gap:8px; margin-bottom:.5rem; }
  .cal-picker select { padding:4px 6px; font-family:inherit; font-size:.85rem; }
```

- [ ] **Step 6: Bump the service-worker cache**

In `route-checklist/sw.js`, change the cache constant:

```js
const CACHE = "route-checklist-v19";
```

- [ ] **Step 7: Manual browser verification**

Hard-refresh `http://127.0.0.1:8000/` (`Ctrl+Shift+R`) after each role switch.

  1. **As `tech1`:** no "Viewing:" dropdown appears. Own calendar renders. Tap a day → Add/Edit/Delete note controls present and working.
  2. **As a supervisor:** "Viewing:" dropdown lists techs + "You (...)"; opens on self; tap a day → controls present (own calendar).
  3. Pick another tech → their month loads; tap an active day → finished-items + notes show, **no Add/Edit/Delete**.
  4. Switch back to "You (...)" → controls return.
  5. Change tech while a day is selected → detail closes (selection cleared), no stale detail under the new grid.

- [ ] **Step 8: Commit**

```bash
git add route-checklist/index.html route-checklist/sw.js
git commit -m "feat: supervisor Daily Logs — tech picker, read-only teammate view"
```

---

### Task 3: Update HANDOFF notes

**Files:**
- Modify: `route-checklist/HANDOFF.md` (top "STATE AS OF" section)

- [ ] **Step 1: Add a supervisor-view note**

Under the current Daily Logs state section at the top of `route-checklist/HANDOFF.md`, add a short paragraph:

```markdown
**Supervisor view (2026-07-14):** On the Daily Logs screen, supervisors
(`body.is-admin`) get a "Viewing:" tech picker (techs + themselves, defaults to
self). Picking a teammate loads that tech's calendar **read-only** (no
Add/Edit/Delete on notes); picking themselves restores full control. Powered by
`listLogsInRange(start, end, techId)` + `listLogTechs()` in cloud.js; the
`daily_logs` RLS select policy already permits supervisor reads (no migration).
SW cache at v19.
```

- [ ] **Step 2: Commit**

```bash
git add route-checklist/HANDOFF.md
git commit -m "docs: HANDOFF note for supervisor Daily Logs view"
```

---

## Notes for the implementer

- **`escAttr` / `escHtml` / `fmtDate` / `currentScreenFromHash` / `isoDate`** already exist in index.html — reuse them, don't redefine.
- The `#logsBody` element is replaced wholesale on each render, but the click/change listeners are attached to `#logsBody` itself (which persists) via delegation — so adding the `change` listener once at setup is correct; don't attach it inside a render function.
- Don't touch `renderGrid`, `renderAutoDetail`, `finishedToday`, `renderCalHead` — they're role-agnostic and reused as-is.
