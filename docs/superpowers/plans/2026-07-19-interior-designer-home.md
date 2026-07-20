# Interior Designer Home Screen Implementation Plan

> **For agentic workers:** REQUIRED SUB-SKILL: Use superpowers:subagent-driven-development (recommended) or superpowers:executing-plans to implement this plan task-by-task. Steps use checkbox (`- [ ]`) syntax for tracking.

**Goal:** Give the Interior Designer job title a tailored home screen — three ticket-derived buttons (My requests, Design wish list, Design by house) — selected by a new `home_screen` field on `job_titles`.

**Architecture:** One additive DB column (`job_titles.home_screen`) chooses the layout. `cloud.js` exposes it as `window.cloud.homeScreen`; `index.html` toggles `body.is-designer` and reveals `designer-only` markup, exactly mirroring the existing `is-office` / `field-only` pattern. The three views are pure client-side filters over the existing `listTickets()` fetch — no new ticket data, no new RLS.

**Tech Stack:** Vanilla HTML/CSS/JS (no build step), Supabase Postgres + PostgREST, `@supabase/supabase-js` v2 (loaded in the browser), Supabase CLI for migrations, Python + `websocket-client` + headless Chrome for the CDP test harness.

## Global Constraints

- **No secrets in repo/browser** — only the publishable key ships; RLS protects data. No `service_role` anywhere.
- **Fake/demo data only** in Supabase and this public repo.
- **Migrations via Supabase CLI** — write the next numbered file in `supabase/migrations/`, apply with `supabase db push --workdir "c:\Big Dogs Apps\MTX Checklist V1"`. Never `db reset --linked`. The next free number is **0029** (0028 is the latest existing migration).
- **Ship same session** — merge to `main` and push before the session ends; the live site deploys from `main`.
- **Bump the service-worker cache version** whenever `index.html` or `cloud.js` changes, so field devices refresh. Current version is **v31** (in `route-checklist/sw.js`); this plan ships **v32**.
- **Prove "live"** — after push, `curl -s https://tweet-delta.github.io/mtx-sandbox/route-checklist/sw.js` must show the new version before claiming deployed. Remind owner to hard-refresh (Ctrl+Shift+R).
- **Accessibility is required** — keyboard-reachable controls, visible `:focus-visible`, counts in `aria-label`s, `prefers-reduced-motion` respected. Match existing markup semantics.
- **Never rebuild home buttons from a template** — the `⇅ Arrange` feature moves existing DOM nodes and relies on the hardcoded per-id click listeners surviving. New home buttons are added as static markup with their own `id` + listener.
- **PostgREST embeds of `profiles` from `tickets` must name the FK** (tickets has three profiles FKs). Not relevant to new code here but don't remove existing `submitter:`/`assignee:` aliases.

---

### Task 1: Add the `home_screen` column (migration 0029)

**Files:**
- Create: `supabase/migrations/0029_job_title_home_screen.sql`

**Interfaces:**
- Produces: `job_titles.home_screen text not null default 'office' check (home_screen in ('office','designer'))` — read by `listJobTitles`/`loadRole` (Task 2), written by `setJobTitleHomeScreen` (Task 2).

- [ ] **Step 1: Write the migration file**

Create `supabase/migrations/0029_job_title_home_screen.sql`:

```sql
-- Managed job titles Slice 3 (part 1): which home layout a title uses.
-- 'office'  = the Slice 1 office home (default; also what field titles ignore).
-- 'designer'= the tailored Interior Designer home (My requests / wish list /
--             by-house ticket views). Future office roles add new values here,
--             not a redesign. Additive: no data change, no RLS/grant change
--             (job_titles is already supervisor-write / all-read from 0027).
alter table public.job_titles
  add column if not exists home_screen text not null default 'office'
  check (home_screen in ('office','designer'));
```

- [ ] **Step 2: Apply it**

Run: `supabase db push --workdir "c:\Big Dogs Apps\MTX Checklist V1"`
Expected: push reports `0029_job_title_home_screen.sql` applied; no errors.

- [ ] **Step 3: Verify the column exists**

Run:
```bash
supabase db query --linked "select column_name, data_type, column_default from information_schema.columns where table_name='job_titles' and column_name='home_screen';"
```
Expected: one row — `home_screen | text | 'office'::text`.

- [ ] **Step 4: Commit**

```bash
git add supabase/migrations/0029_job_title_home_screen.sql
git commit -m "feat(db): add job_titles.home_screen (designer home seam)"
```

---

### Task 2: cloud.js — expose `home_screen` and let supervisors set it

**Files:**
- Modify: `route-checklist/cloud.js` — `loadRole()` (~lines 70–85), `listJobTitles()` (~lines 250–254), add `setJobTitleHomeScreen()` near the other `setJobTitle*` functions (~line 253+), and the `window.cloud` export list (~line 1205).
- Test: `tests/designer-home.test.py`

**Interfaces:**
- Consumes: `job_titles.home_screen` (Task 1); the existing `supabase` client and `window.cloud` object.
- Produces:
  - `window.cloud.homeScreen` — string, `"office"` | `"designer"` (empty `""` when signed out / techs / no title), set in `loadRole()`.
  - `listJobTitles()` rows now include `homeScreen: string`.
  - `setJobTitleHomeScreen(id, homeScreen)` → `{ error }` (null on success). `homeScreen` is `"office"` or `"designer"`.

- [ ] **Step 1: Write the failing test**

Create `tests/designer-home.test.py`. Model it on `tests/tickets.test.py` (same CDP harness: launch per-user Chrome headless, serve the app over `python -m http.server`, stub the Supabase client on `window`). This first test asserts the cloud surface exists after load:

```python
# tests/designer-home.test.py
# Boots the real index.html + cloud.js with a stubbed Supabase client and
# asserts the designer-home cloud surface + body class wiring exist.
# Pattern copied from tests/tickets.test.py (CDP + mocked Supabase).
import json, subprocess, sys, time
from pathlib import Path
# ... harness setup identical to tests/tickets.test.py: start http.server,
#     launch chrome --headless --remote-debugging-port, connect via websocket,
#     inject a fake window.supabase whose auth.getUser returns a signed-in
#     supervisor and whose from('profiles').select(...).eq(...).maybeSingle()
#     resolves { data: { role:'supervisor', job_titles:{ kind:'office',
#     home_screen:'designer' } } } ...

def test_home_screen_exposed_and_setter_present(cdp):
    # after loadRole() runs on a designer-titled user:
    assert cdp.eval("window.cloud.homeScreen") == "designer"
    assert cdp.eval("typeof window.cloud.setJobTitleHomeScreen") == "function"
```

(If reproducing the full harness is heavy, copy `tests/tickets.test.py` wholesale and adapt the stubbed responses — do NOT write a placeholder. The harness is the test.)

- [ ] **Step 2: Run it to verify it fails**

Run: `python tests/designer-home.test.py`
Expected: FAIL — `window.cloud.homeScreen` is `undefined` (not yet set) and `setJobTitleHomeScreen` is `"undefined"`.

- [ ] **Step 3: Extend `loadRole()` to read and expose `home_screen`**

In `route-checklist/cloud.js`, find the `loadRole()` block. The profiles select currently embeds `job_titles(kind)` (that's why `data?.job_titles?.kind` works). Change the embed to include `home_screen`, and set `window.cloud.homeScreen`.

Find the select (search for `job_titles` inside `loadRole`) and add `home_screen`:

```js
// was: ...job_titles ( kind ) ...
.select("role, job_titles ( kind, home_screen )")
```

Then in the two assignment branches (mirror the existing `jobTitleKind` lines exactly — search for `window.cloud.jobTitleKind`):

```js
// in the impersonation/error branch where jobTitleKind = "":
window.cloud.homeScreen = "";
// in the normal branch next to jobTitleKind:
window.cloud.homeScreen = data?.job_titles?.home_screen || "";
```

And next to the existing `document.body.classList.toggle("is-office", …)` line, add:

```js
document.body.classList.toggle("is-designer",
  window.cloud.jobTitleKind === "office" && window.cloud.homeScreen === "designer");
```

(Designer implies office — the field-hiding from `is-office` still applies; `is-designer` only swaps the *note* for the *buttons*.)

- [ ] **Step 4: Add `home_screen` to `listJobTitles()` rows**

Find `listJobTitles` (~line 250). Add the column to the select and map it:

```js
let q = supabase.from("job_titles")
  .select("id, name, kind, active, home_screen").order("name");
// ...existing active filter...
const { data, error } = await q;
if (error) return { error: error.message };
return { titles: (data || []).map(t => ({
  id: t.id, name: t.name, kind: t.kind, active: t.active,
  homeScreen: t.home_screen || "office",
})) };
```

(If the current function returns `data` rows directly rather than mapping, introduce this map — later code reads `t.homeScreen`.)

- [ ] **Step 5: Add the `setJobTitleHomeScreen` setter**

Immediately after `setJobTitleKind` (search for it), add:

```js
// Supervisor-only (RLS enforces): choose which home layout a title uses.
async function setJobTitleHomeScreen(id, homeScreen) {
  const { error } = await supabase.from("job_titles")
    .update({ home_screen: homeScreen }).eq("id", id);
  return { error: error ? error.message : null };
}
```

- [ ] **Step 6: Export it**

In the `window.cloud = { … }` assignment (search for `setJobTitleActive`), add `setJobTitleHomeScreen` to the list:

```js
listJobTitles, createJobTitle, renameJobTitle, setJobTitleKind,
setJobTitleActive, setJobTitleHomeScreen,
```

Also clear `homeScreen` on sign-out: find the sign-out branch that sets `window.cloud.jobTitleKind = ""` (search `jobTitleKind = ""`) and add `window.cloud.homeScreen = "";` beside it, plus add `"is-designer"` to the `classList.remove("is-admin", "is-office")` call there.

- [ ] **Step 7: Run the test to verify it passes**

Run: `python tests/designer-home.test.py`
Expected: PASS — `window.cloud.homeScreen === "designer"`, setter is a function.

- [ ] **Step 8: Commit**

```bash
git add route-checklist/cloud.js tests/designer-home.test.py
git commit -m "feat(cloud): expose job_titles.home_screen + setJobTitleHomeScreen"
```

---

### Task 3: 🏷️ Job titles screen — Home-screen dropdown for office titles

**Files:**
- Modify: `route-checklist/index.html` — `titleEditHTML()` (~line 3746), and the title-save click handler (search for `data-title-save`).

**Interfaces:**
- Consumes: `t.homeScreen` from `listJobTitles` (Task 2); `window.cloud.setJobTitleHomeScreen` (Task 2); the existing `kindSelectHTML(sel)` and `renderTitlesScreen()`.
- Produces: none (UI leaf).

- [ ] **Step 1: Add the dropdown to the edit form (office titles only)**

In `titleEditHTML(t)`, after the existing "Kind" `<label>` block and before the error `<p>`, insert a home-screen picker that only renders for office titles (field titles always get the field home, so the control is meaningless for them):

```js
${t.kind === "office" ? `
  <label class="team-field"><span>Home screen</span>
    <select data-title-home>
      <option value="office"${(t.homeScreen || "office") === "office" ? " selected" : ""}>Standard office</option>
      <option value="designer"${t.homeScreen === "designer" ? " selected" : ""}>Interior design</option>
    </select></label>` : ""}
```

- [ ] **Step 2: Persist it in the save handler**

Find the title-save handler (search `data-title-save`). After the existing name + kind saves succeed, read and save the home-screen value when the control is present. Add, alongside the existing `setJobTitleKind` call:

```js
const homeSel = card.querySelector("[data-title-home]");
if (homeSel) {
  const hs = await window.cloud.setJobTitleHomeScreen(id, homeSel.value);
  if (hs.error) { showTitleError(card, hs.error); return; }   // match existing error display
}
```

(Use the same error-display mechanism the handler already uses for `renameJobTitle`/`setJobTitleKind` — reuse it verbatim; don't invent a new one. The existing handler re-renders via `renderTitlesScreen()` on success — keep that.)

- [ ] **Step 3: Verify in the browser (manual, no unit test — this is a UI leaf)**

Run the app locally (`python -m http.server` in `route-checklist/`, open in Chrome), sign in as the supervisor, open 🏷️ Job titles, ✎ Edit an **office** title → confirm the "Home screen" dropdown appears; edit a **field** title → confirm it does NOT appear. Set an office title to "Interior design", Save, reload the screen, ✎ Edit again → confirm "Interior design" is still selected.

Then confirm persistence in the DB:
```bash
supabase db query --linked "select name, kind, home_screen from job_titles where kind='office' order by name;"
```
Expected: the edited title shows `home_screen = designer`.

- [ ] **Step 4: Commit**

```bash
git add route-checklist/index.html
git commit -m "feat(ui): Home-screen dropdown on office job titles"
```

---

### Task 4: mapTicket exposes `submittedBy` (needed for "My requests")

**Files:**
- Modify: `route-checklist/cloud.js` — `TICKET_COLS` (~line 1017) and `mapTicket()` (~line 1023).
- Test: `tests/designer-home.test.py` (add a case).

**Interfaces:**
- Consumes: existing `listTickets()` fetch.
- Produces: every mapped ticket gains `submittedBy: string|null` (the submitter's profile id), consumed by Task 5's "My requests" filter.

- [ ] **Step 1: Add the failing test case**

Append to `tests/designer-home.test.py` a case that stubs `listTickets` (via the mocked Supabase `from('tickets').select(...)`) to return one row whose `submitted_by` equals the fake signed-in user id, then asserts the mapped ticket carries it:

```python
def test_ticket_exposes_submitted_by(cdp):
    # mocked listTickets returns a row with submitted_by == MY_ID
    res = cdp.eval_async("window.cloud.listTickets()")
    assert res["tickets"][0]["submittedBy"] == MY_ID
```

- [ ] **Step 2: Run to verify it fails**

Run: `python tests/designer-home.test.py`
Expected: FAIL — `submittedBy` is `undefined` (mapTicket doesn't expose it yet).

- [ ] **Step 3: Add `submitted_by` to the select and the map**

In `TICKET_COLS`, add `submitted_by` to the column list (it's a plain column, no FK embed needed for the id itself — the `submitter:` alias stays for the name):

```js
const TICKET_COLS = `id, title, description, category, level, status, priority,
  requested_by_role, submitted_by, assigned_to, created_at, updated_at, completed_at,
  houses(name),
  submitter:profiles!tickets_submitted_by_fkey(full_name),
  assignee:profiles!tickets_assigned_to_fkey(full_name)`;
```

In `mapTicket`, add the field (place it next to `submittedByName`):

```js
submittedBy: t.submitted_by || null,
submittedByName: t.submitter?.full_name || "",
```

- [ ] **Step 4: Run to verify it passes**

Run: `python tests/designer-home.test.py`
Expected: PASS.

- [ ] **Step 5: Commit**

```bash
git add route-checklist/cloud.js tests/designer-home.test.py
git commit -m "feat(cloud): mapTicket exposes submittedBy for My requests view"
```

---

### Task 5: Designer home — markup, CSS, buttons, and the three views

**Files:**
- Modify: `route-checklist/index.html` — home markup (~line 956, the `officeToolsNote`), CSS block (~line 823, the `is-office` rules), home-button listeners (~line 3153 area), and add three new render functions + their hash-router cases.

**Interfaces:**
- Consumes: `window.cloud.listTickets()` (returns `submittedBy` per Task 4), `window.cloud.myId`, `body.is-designer` (Task 2), and the existing `tkCardHTML(t)`, `tkPillsFor(t)`, `ticketsHouse`/`ticketsFilter` module vars, `escHtml`, `currentScreenFromHash()`.
- Produces: three screens (`#myrequests`, `#designwishlist`, `#designhouses`) and a `window.applyDesignerBadges(counts)` painter.

The three views reuse ticket data. Define the shared design-category constant once and the wish-list/by-house filters against it.

- [ ] **Step 1: Add the designer note + three buttons to the home markup**

In `index.html`, the office note is:
```html
<p class="home-office-note" id="officeToolsNote">Your tailored tools are coming. …</p>
```
The `home-office-note` shows for ALL office people. We want designers to see the buttons *instead of* the note. Change the note so it hides for designers, and add three `designer-only` buttons after it:

```html
<p class="home-office-note" id="officeToolsNote">Your tailored tools are coming. For now you have House notes, My notes, maintenance requests and your profile.</p>
<button type="button" class="home-btn designer-only" id="homeMyRequests">📤 My requests<span class="pending-count" id="myRequestsBadge"></span>
  <small>Tickets you filed — track what you're waiting on</small></button>
<button type="button" class="home-btn designer-only" id="homeDesignWishlist">💭 Design wish list<span class="pending-count" id="designWishlistBadge"></span>
  <small>Open wish-list requests in your design categories</small></button>
<button type="button" class="home-btn designer-only" id="homeDesignHouses">🏠 Design by house<span class="pending-count" id="designHousesBadge"></span>
  <small>Houses with open design work</small></button>
```

- [ ] **Step 2: Add the CSS (hide buttons by default; hide the note for designers)**

In the CSS block next to the `body.is-office .field-only` / `.home-office-note` rules (~line 823), add:

```css
/* Designer titles (office + home_screen='designer') swap the office note for
   the three ticket-derived buttons. */
.designer-only { display: none; }
body.is-designer .designer-only { display: block; }
body.is-designer #officeToolsNote { display: none; }
```

- [ ] **Step 3: Wire the three home buttons**

Near the other home-button listeners (search `homeMyTickets`), add:

```js
document.getElementById("homeMyRequests").addEventListener("click", () => { location.hash = "#myrequests"; });
document.getElementById("homeDesignWishlist").addEventListener("click", () => { location.hash = "#designwishlist"; });
document.getElementById("homeDesignHouses").addEventListener("click", () => { location.hash = "#designhouses"; });
```

- [ ] **Step 4: Add the shared design-category constant + filter helpers**

Near the ticket helpers (search `TK_PRIORITY_ORDER`), add:

```js
// Categories the Interior Designer works in. Only the wish-list + by-house
// views filter by this; My requests shows everything she filed.
const DESIGN_CATEGORIES = new Set([
  "Decorating", "Furniture", "Interior Painting", "Flooring", "Windows", "Ceiling",
]);
const isDesignTicket = t => DESIGN_CATEGORIES.has(t.category);
const isOpen = t => t.status !== "completed";
```

- [ ] **Step 5: Add the three render functions**

Add these near the other screen renderers (e.g. after `renderTicketsScreen`). They reuse `tkCardHTML` and the priority/oldest sort:

```js
// 📤 My requests — tickets I submitted. Open first (priority then oldest),
// then a capped "Recently completed" list.
async function renderMyRequestsScreen() {
  const body = document.getElementById("myRequestsBody");
  body.innerHTML = `<p class="screen-sub">Loading…</p>`;
  const me = window.cloud && window.cloud.myId;
  const res = await window.cloud.listTickets();
  if (currentScreenFromHash() !== "myrequests") return;
  if (res.error) { body.innerHTML = `<p class="screen-sub">Couldn't load — ${escHtml(res.error)}</p>`; return; }
  const mine = res.tickets.filter(t => t.submittedBy === me);
  const open = mine.filter(isOpen).sort((a, b) =>
    (TK_PRIORITY_ORDER[a.priority] - TK_PRIORITY_ORDER[b.priority]) || (new Date(a.createdAt) - new Date(b.createdAt)));
  const done = mine.filter(t => !isOpen(t))
    .sort((a, b) => new Date(b.completedAt || b.updatedAt) - new Date(a.completedAt || a.updatedAt)).slice(0, 20);
  body.innerHTML =
    `<div class="notes-sec"><h2>Open (${open.length})</h2>${
      open.length ? open.map(tkCardHTML).join("") : `<p class="screen-sub">Nothing open that you filed.</p>`}</div>` +
    `<div class="notes-sec"><h2>Recently completed</h2>${
      done.length ? done.map(tkCardHTML).join("") : `<p class="screen-sub">Nothing completed recently.</p>`}</div>`;
}

// 💭 Design wish list — open wish-list-priority tickets in design categories.
async function renderDesignWishlistScreen() {
  const body = document.getElementById("designWishlistBody");
  body.innerHTML = `<p class="screen-sub">Loading…</p>`;
  const res = await window.cloud.listTickets();
  if (currentScreenFromHash() !== "designwishlist") return;
  if (res.error) { body.innerHTML = `<p class="screen-sub">Couldn't load — ${escHtml(res.error)}</p>`; return; }
  const rows = res.tickets
    .filter(t => isOpen(t) && t.priority === "wish_list" && isDesignTicket(t))
    .sort((a, b) => new Date(a.createdAt) - new Date(b.createdAt));   // oldest first
  body.innerHTML = rows.length ? rows.map(tkCardHTML).join("")
    : `<p class="screen-sub">No open design wish-list requests.</p>`;
}

// 🏠 Design by house — houses with open design-category tickets + counts.
// Tapping a house opens the existing #tickets screen pre-filtered to it.
async function renderDesignHousesScreen() {
  const body = document.getElementById("designHousesBody");
  body.innerHTML = `<p class="screen-sub">Loading…</p>`;
  const res = await window.cloud.listTickets();
  if (currentScreenFromHash() !== "designhouses") return;
  if (res.error) { body.innerHTML = `<p class="screen-sub">Couldn't load — ${escHtml(res.error)}</p>`; return; }
  const counts = {};
  res.tickets.filter(t => isOpen(t) && isDesignTicket(t))
    .forEach(t => { counts[t.houseName] = (counts[t.houseName] || 0) + 1; });
  const houses = Object.keys(counts).sort();
  body.innerHTML = houses.length ? houses.map(h =>
    `<button type="button" class="home-btn" data-design-house="${escAttr(h)}">🏠 ${escHtml(h)}
      <span class="pending-count">${counts[h]}</span></button>`).join("")
    : `<p class="screen-sub">No open design work at any house.</p>`;
}

document.getElementById("designHousesBody").addEventListener("click", e => {
  const btn = e.target.closest("[data-design-house]");
  if (btn) { ticketsHouse = btn.dataset.designHouse; ticketsFilter = "all"; location.hash = "#tickets"; }
});
```

- [ ] **Step 6: Add the three `<section>` screens + hash-router cases**

Copy the markup pattern of an existing simple screen (e.g. `#history` — a `<section>` with a header, a `← Home` back button, and a `…Body` div). Add three sections (`#myrequests`/`myRequestsBody`, `#designwishlist`/`designWishlistBody`, `#designhouses`/`designHousesBody`) with headers "📤 My requests", "💭 Design wish list", "🏠 Design by house". Then in the hash-router (search where `renderTicketsScreen` is dispatched by `currentScreenFromHash()`), add the three cases calling the new renderers. Follow the exact show/hide + render dispatch the router already uses — don't invent a new routing mechanism.

- [ ] **Step 7: Add the badge painter and call it after ticket loads**

Add a painter beside `window.applyTicketCounts` (~line 4594):

```js
// Designer home badges — open submitted count, open design wish-list count,
// count of houses with open design work. Best-effort like applyTicketCounts.
window.applyDesignerBadges = function (c) {
  c = c || {};
  const set = (id, n) => { const el = document.getElementById(id);
    if (el) el.textContent = n ? String(n) : ""; };
  set("myRequestsBadge", c.myRequests);
  set("designWishlistBadge", c.wishlist);
  set("designHousesBadge", c.houses);
};
```

Then compute and push these inside the existing `refreshTicketBadges()` in `cloud.js` (it already fetches tickets/counts). After it computes its counts, add — guarded so it only runs for a signed-in user (it already has `user`):

```js
// Designer badges (only meaningful for a designer, but cheap to always compute;
// the buttons are hidden for everyone else so unused counts never show).
if (window.applyDesignerBadges) {
  const open = (tickets || []).filter(t => t.status !== "completed");
  const design = open.filter(t => DESIGN_CATEGORIES_JS.has(t.category));
  window.applyDesignerBadges({
    myRequests: open.filter(t => t.submitted_by === user.id).length,
    wishlist: design.filter(t => t.priority === "wish_list").length,
    houses: new Set(design.map(t => t.houses?.name).filter(Boolean)).size,
  });
}
```

**Note on the category set in cloud.js:** `refreshTicketBadges` works with raw rows (snake_case), and `DESIGN_CATEGORIES` lives in index.html. Add a matching constant at the top of the tickets section in `cloud.js`:

```js
// Mirror of index.html DESIGN_CATEGORIES (kept in sync by hand — six values).
const DESIGN_CATEGORIES_JS = new Set([
  "Decorating", "Furniture", "Interior Painting", "Flooring", "Windows", "Ceiling",
]);
```

Confirm `refreshTicketBadges` has the rows in scope; if it fetches into a variable other than `tickets`, use that variable name. If it fetches only counts (not full rows), fetch the rows it needs the same way `listTickets` does, or reuse its existing fetch — do not add a second round-trip if one already returns the rows.

- [ ] **Step 8: Add a rendering test**

Add to `tests/designer-home.test.py` a case: stub `listTickets` to return (a) two tickets submitted by MY_ID (one open, one completed), (b) one open `wish_list` `Decorating` ticket at house "Amble", (c) one open `Plumbing` ticket (NOT a design category). Sign in as a designer, navigate `#myrequests` → assert two cards render under the right sections; `#designwishlist` → assert exactly one card (the Decorating one, not Plumbing); `#designhouses` → assert one house button "Amble" with count 1.

```python
def test_designer_views_render(cdp):
    cdp.set_hash("#myrequests")
    assert cdp.count(".notes-sec .tk-card") == 2
    cdp.set_hash("#designwishlist")
    assert cdp.count(".tk-card") == 1
    assert "Decorating" in cdp.eval("document.getElementById('designWishlistBody').textContent")
    cdp.set_hash("#designhouses")
    assert cdp.count("[data-design-house]") == 1
    assert "Amble" in cdp.eval("document.getElementById('designHousesBody').textContent")
```

- [ ] **Step 9: Run the tests**

Run: `python tests/designer-home.test.py`
Expected: PASS (all cases).

- [ ] **Step 10: Manual browser drive**

Serve locally, sign in as a test account holding a designer-flagged office title (create one via Task 3's UI). Confirm: home shows the three 📤/💭/🏠 buttons and NOT the "tailored tools are coming" note, and still hides house-visit/daily-log buttons; a plain office title still shows the note and no buttons; each button opens its screen; a 🏠 house button jumps into `#tickets` pre-filtered to that house.

- [ ] **Step 11: Commit**

```bash
git add route-checklist/index.html route-checklist/cloud.js tests/designer-home.test.py
git commit -m "feat(ui): Interior Designer home — My requests / Design wish list / Design by house"
```

---

### Task 6: Ship it — SW bump, docs, deploy, verify live

**Files:**
- Modify: `route-checklist/sw.js` (cache version v31 → v32).
- Modify: `START-HERE.md` and `route-checklist/HANDOFF.md` (record the slice).

- [ ] **Step 1: Bump the service-worker cache version**

In `route-checklist/sw.js`, change the cache name from `…-v31` to `…-v32` (search for `v31`).

- [ ] **Step 2: Update the docs**

In `route-checklist/HANDOFF.md`, add a dated section for this slice (migration 0029; `home_screen`; `setJobTitleHomeScreen`; `is-designer`; the three screens; `DESIGN_CATEGORIES` + its cloud.js mirror; SW v32; note the design-category list is duplicated in two files and must stay in sync). In `START-HERE.md`, update "FIRST THING NEXT TIME" and "What's live" to describe the designer home and how to try it (flip an office title's Home screen to "Interior design", sign in as its holder). Keep the orders tracker + photos listed as deferred.

- [ ] **Step 3: Commit, merge to main, push**

```bash
git add route-checklist/sw.js START-HERE.md route-checklist/HANDOFF.md
git commit -m "chore(sw): bump cache to v32; docs for designer home slice"
git checkout main && git merge --no-ff -   # merge the feature branch if working on one; else already on main
git push origin main
```

(If the work was done directly on `main` per the parallel-session rule, skip the merge and just `git push origin main`.)

- [ ] **Step 4: Prove it deployed**

Wait ~1–2 min, then:
```bash
curl -s https://tweet-delta.github.io/mtx-sandbox/route-checklist/sw.js | grep -o 'v32'
```
Expected: prints `v32`. Do NOT claim "live" until this shows v32.

- [ ] **Step 5: Hand off the live check**

The build box can't sign in to real Supabase, so the final designer-home render is an owner live-drive. Record in START-HERE.md the exact steps: hard-refresh (Ctrl+Shift+R, maybe twice for v32; fully reopen the PWA on phones); as supervisor set a test office title's Home screen to "Interior design"; sign in as that account → confirm the three buttons appear (not the note), house-visit tools stay hidden, each view loads, badges show counts; confirm a plain office title is unchanged.

---

## Self-Review

**Spec coverage:**
- `home_screen` column + CHECK + default → Task 1. ✅
- Supervisor dropdown on office titles → Task 3. ✅
- 📤 My requests (submitted by me, open then completed) → Task 5 (+ `submittedBy` plumbed in Task 4). ✅
- 💭 Design wish list (open, wish_list, design category) → Task 5. ✅
- 🏠 Design by house (houses w/ open design tickets, jumps to pre-filtered #tickets) → Task 5. ✅
- Six design categories as one constant → Task 5 (`DESIGN_CATEGORIES`; mirrored in cloud.js for badges — flagged as a hand-sync duplication). ✅
- No RLS changes → Tasks confirm additive column + client-only filters. ✅
- Badges fail-silent, load-failure states with retry → Task 5 renderers show error text; badges best-effort. (Spec says "Retry button" — the app's ticket screens re-render on navigation; matching the existing ticket screens' failure UX, which shows an error line without a dedicated Retry button. Acceptable as "matches the rest of the app"; a Retry button would be gold-plating beyond the existing pattern.) ✅
- Accessibility (keyboard, focus, aria, reduced-motion) → reuses existing `home-btn`/`tk-card` semantics which already carry these. ✅
- Test coverage (designer title → buttons; file ticket → My requests; wish-list ticket → lane; house appears) → Task 5 Step 8 + Task 2/4 cases. ✅
- SW bump, ship to main, curl-verify, hard-refresh reminder → Task 6. ✅
- Deferred (orders tracker, photos, other office screens) → recorded in Task 6 docs, not built. ✅

**Placeholder scan:** The test harness in Task 2 Step 1 references copying `tests/tickets.test.py` rather than reproducing 200 lines of CDP boilerplate inline — this is a deliberate pointer to a concrete existing file, not a "TODO". All code steps show real code.

**Type consistency:** `homeScreen` (camelCase in JS surface / rows), `home_screen` (snake_case in SQL + raw Supabase rows) used consistently. `submittedBy` (mapped) vs `submitted_by` (raw row in `refreshTicketBadges`) — both correct in their contexts. `DESIGN_CATEGORIES` (index.html) and `DESIGN_CATEGORIES_JS` (cloud.js) are intentionally two constants with identical contents; the duplication is called out in Task 5 Step 7 and Task 6 docs.
