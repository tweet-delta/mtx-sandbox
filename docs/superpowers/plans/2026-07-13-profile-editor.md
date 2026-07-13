# My Profile Editor Implementation Plan

> **For agentic workers:** REQUIRED SUB-SKILL: Use superpowers:subagent-driven-development (recommended) or superpowers:executing-plans to implement this plan task-by-task. Steps use checkbox (`- [ ]`) syntax for tracking.

**Goal:** Let any signed-in user (tech or supervisor) view and edit their own
full name and phone number from a new "My Profile" screen reachable from the
home screen.

**Architecture:** One additive Postgres migration adds a `phone` column to
the existing `profiles` table (no RLS changes — existing policies already
cover self/supervisor read+write). Two new functions in `cloud.js`
(`getMyProfile`, `saveMyProfile`) wrap the Supabase calls. A new `#profile`
screen in `index.html` follows the existing hash-router screen pattern
(same shape as `#routes`/`#notes`).

**Tech Stack:** Vanilla HTML/CSS/JS (`route-checklist/index.html`), a
Supabase JS client module (`route-checklist/cloud.js`), Postgres migrations
applied via the Supabase CLI (`supabase db push`).

## Global Constraints

- No automated test suite exists in this project (per `CLAUDE.md`) —
  verification is manual: run the app in a browser and drive the real flow.
- Never commit secrets; the `service_role` key must never appear in client
  code (not touched by this plan).
- RLS is the enforcement boundary — the UI must not be relied on alone to
  restrict access.
- Keep the existing self-editing scope: this plan does NOT add a "supervisor
  edits another tech" UI, even though RLS already allows it server-side.
- Spec: `docs/superpowers/specs/2026-07-13-profile-editor-design.md` — this
  plan implements it in full.

---

### Task 1: Migration — add `phone` column to `profiles`

**Files:**
- Create: `supabase/migrations/0015_profile_phone.sql`

**Interfaces:**
- Produces: `public.profiles.phone` (text, not null, default `''`) — consumed
  by Task 2's `getMyProfile`/`saveMyProfile`.

- [ ] **Step 1: Write the migration file**

```sql
-- ============================================================================
-- 0015_profile_phone.sql — add a phone number to profiles so techs/supervisors
-- can maintain their own contact info in-app (My Profile screen).
--
-- HOW TO RUN: supabase db push --workdir "c:\Big Dogs Apps\MTX Checklist V1"
-- Safe to re-run ("if not exists").
-- ============================================================================

alter table public.profiles
  add column if not exists phone text not null default '';

-- ============================================================================
-- No RLS or grant changes needed: profiles_select / profiles_update (from
-- 0001_init.sql) already gate rows by "id = auth.uid() or supervisor", and
-- that check applies to the whole row, phone included.
-- ============================================================================
```

- [ ] **Step 2: Apply the migration**

Run: `supabase db push --workdir "c:\Big Dogs Apps\MTX Checklist V1"`
Expected: CLI reports the new migration applied, no errors.

- [ ] **Step 3: Verify the column exists**

In the Supabase dashboard SQL Editor, run:
```sql
select column_name, data_type, column_default
from information_schema.columns
where table_name = 'profiles' and column_name = 'phone';
```
Expected: one row — `phone | text | ''::text`.

- [ ] **Step 4: Commit**

```bash
git add supabase/migrations/0015_profile_phone.sql
git commit -m "feat: add phone column to profiles (migration 0015)"
```

---

### Task 2: cloud.js — `getMyProfile` and `saveMyProfile`

**Files:**
- Modify: `route-checklist/cloud.js` (add two functions near the other
  per-user helpers, e.g. after `loadMyRoute` around line 100-101; add both
  names to the `window.cloud = { ... }` export object at line 473-480)

**Interfaces:**
- Consumes: `supabase` (module-level client, `cloud.js:9`), `isMissingColumn`
  (`cloud.js:155`).
- Produces:
  - `getMyProfile()` → `Promise<{ fullName: string, phone: string, role: string, email: string } | { error: string }>`
  - `saveMyProfile({ fullName, phone })` → `Promise<{ error: string | null }>`
  - Both added to `window.cloud` for Task 3's UI to call as
    `window.cloud.getMyProfile()` / `window.cloud.saveMyProfile(...)`.

- [ ] **Step 1: Add `getMyProfile` to cloud.js**

Insert after `loadMyRoute` (after line 101, before the `// ---- Visit
history` comment on line 103):

```javascript
// ---- My Profile (self-service name/phone editor) ----

// The signed-in user's own name/phone/role + their login email. Email comes
// from auth.getUser() (profiles has no email column). Returns { error } if
// not signed in or the query fails — the UI shows that message rather than
// a blank form.
async function getMyProfile() {
  const { data: { user } } = await supabase.auth.getUser();
  if (!user) return { error: "Not signed in." };
  let { data, error } = await supabase
    .from("profiles").select("full_name, phone, role").eq("id", user.id).maybeSingle();
  if (error && isMissingColumn(error)) {
    ({ data, error } = await supabase
      .from("profiles").select("full_name, role").eq("id", user.id).maybeSingle());
  }
  if (error) return { error: error.message };
  return {
    fullName: data?.full_name || "",
    phone: data?.phone || "",
    role: data?.role || "tech",
    email: user.email || "",
  };
}

// Save the signed-in user's OWN name/phone. Never sends role — role changes
// stay a deliberate dashboard action (guard_profile_role trigger blocks a
// non-supervisor from changing it anyway).
async function saveMyProfile({ fullName, phone }) {
  const { data: { user } } = await supabase.auth.getUser();
  if (!user) return { error: "Not signed in." };
  let { error } = await supabase
    .from("profiles")
    .update({ full_name: fullName, phone })
    .eq("id", user.id);
  if (error && isMissingColumn(error)) {
    ({ error } = await supabase
      .from("profiles")
      .update({ full_name: fullName })
      .eq("id", user.id));
    if (!error) return { error: null, degraded: true };
  }
  return { error: error ? error.message : null };
}
```

- [ ] **Step 2: Export both functions**

In the `window.cloud = { ... }` object (currently `cloud.js:473-480`), add
`getMyProfile, saveMyProfile,` — e.g.:

```javascript
window.cloud = { saveVisit, loadInProgress, lastDone, listInProgress,
                 getHouseNotes, suggestNote, suggestChange, withdrawSuggestion,
                 approveSuggestion, denySuggestion, markDenialSeen,
                 saveGeneralNotes, saveHouseField,
                 listPendingSuggestions, pendingCount,
                 listRoutes, listTechs, saveRoute, setHouseRoute, listHousesForRoutes,
                 getMyProfile, saveMyProfile,
                 refreshMyRoute: loadMyRoute,
                 role: null };
```

- [ ] **Step 3: Manual verification (no automated tests in this project)**

Open the app in a browser signed in as any tech, open the browser console,
and run:
```javascript
await window.cloud.getMyProfile()
```
Expected: an object like `{ fullName: "...", phone: "", role: "tech", email: "..." }`
with no `error` key. Then run:
```javascript
await window.cloud.saveMyProfile({ fullName: "Test Name", phone: "555-0100" })
```
Expected: `{ error: null }`. Re-run `getMyProfile()` and confirm the new
values come back.

- [ ] **Step 4: Commit**

```bash
git add route-checklist/cloud.js
git commit -m "feat: add getMyProfile/saveMyProfile to cloud.js"
```

---

### Task 3: UI — "My Profile" screen

**Files:**
- Modify: `route-checklist/index.html`
  - CSS: extend the screen-visibility rule (currently lines 481-485) and add
    a small form style block near the other screen-specific styles (after
    the `#notesSearch` block, around line 528-534).
  - HTML: add a home-screen button (after `homeNotes`, before `homeRoutes`,
    around line 712-717) and a new `<div id="profileScreen">` screen block
    (alongside `notesScreen`/`routesScreen`, around line 729-743).
  - JS: extend `currentScreenFromHash()` (line 2506-2514) and `showScreen()`
    (line 2515-2522), add a `homeProfile` click handler (near line 2543-2551),
    and add a `renderProfileScreen()` function + its event listener (same
    pattern as `renderRoutesScreen()` at line 2602 and its listener at 2655).

**Interfaces:**
- Consumes: `window.cloud.getMyProfile()`, `window.cloud.saveMyProfile({fullName, phone})`
  (from Task 2), `escHtml`/`escAttr` (`index.html:1701-1702`), `toast(text, kind)`
  (`index.html:1992`), `currentScreenFromHash()`/`showScreen()` router.
- Produces: `#profile` hash route; no new interfaces consumed by later tasks
  (this is the last task in this plan).

- [ ] **Step 1: Add the CSS screen-visibility rule**

In `index.html`, change lines 481-485 from:

```css
  body:not([data-screen="home"])     #homeScreen,
  body:not([data-screen="continue"]) #continueScreen,
  body:not([data-screen="routes"])   #routesScreen,
  body:not([data-screen="pending"])  #pendingScreen,
  body:not([data-screen="notes"])    #notesScreen { display: none; }
```

to:

```css
  body:not([data-screen="home"])     #homeScreen,
  body:not([data-screen="continue"]) #continueScreen,
  body:not([data-screen="routes"])   #routesScreen,
  body:not([data-screen="pending"])  #pendingScreen,
  body:not([data-screen="profile"])  #profileScreen,
  body:not([data-screen="notes"])    #notesScreen { display: none; }
```

- [ ] **Step 2: Add profile form CSS**

After the `#notesSearch` block (ends at line 534), insert:

```css
  /* ---- My Profile screen ---- */
  .profile-field { margin-bottom: 14px; }
  .profile-field label { display: block; font-size: 0.85rem; font-weight: 600; color: var(--muted); margin-bottom: 4px; }
  .profile-field input {
    font: inherit; font-size: 16px; /* 16px stops iOS zoom-on-focus */
    width: 100%; padding: 10px 12px;
    border: 1px solid var(--line); border-radius: 8px;
    background: var(--card); color: var(--ink);
  }
  .profile-readonly { font-size: 0.95rem; color: var(--muted); margin: 0 0 14px; }
  #profileMsg { font-size: 0.88rem; margin-top: 8px; }
  #profileMsg.ok { color: var(--ok, green); }
  #profileMsg.error { color: var(--bad, crimson); }
```

- [ ] **Step 3: Add the home-screen button**

In the `homeScreen` div, change (lines 712-717) from:

```html
  <button type="button" class="home-btn" id="homeNotes">📝 House notes
    <small>Info, item notes &amp; general notes per house</small></button>
  <button type="button" class="home-btn admin-only" id="homeRoutes">🗺️ Routes
```

to:

```html
  <button type="button" class="home-btn" id="homeNotes">📝 House notes
    <small>Info, item notes &amp; general notes per house</small></button>
  <button type="button" class="home-btn" id="homeProfile">👤 My profile
    <small>Your name &amp; phone number</small></button>
  <button type="button" class="home-btn admin-only" id="homeRoutes">🗺️ Routes
```

- [ ] **Step 4: Add the profile screen markup**

After the `notesScreen` div closes (line 735, `</div>`) and before
`routesScreen` (line 737), insert:

```html
<div id="profileScreen" class="screen" aria-label="My profile">
  <div class="screen-head">
    <button type="button" class="menu-btn" data-nav-home>← Home</button>
    <h1>My Profile</h1>
  </div>
  <div id="profileBody"></div>
</div>
```

- [ ] **Step 5: Wire the hash router**

In `currentScreenFromHash()` (line 2506-2514), change:

```javascript
    if (h.startsWith("#pending")) return "pending";
    return "home";
```

to:

```javascript
    if (h.startsWith("#pending")) return "pending";
    if (h.startsWith("#profile")) return "profile";
    return "home";
```

In `showScreen()` (line 2515-2522), change:

```javascript
    if (scr === "pending") renderPendingScreen();
```

to:

```javascript
    if (scr === "pending") renderPendingScreen();
    if (scr === "profile") renderProfileScreen();
```

- [ ] **Step 6: Wire the home button click handler**

After the `homePending` listener (lines 2549-2551), add:

```javascript
  document.getElementById("homeProfile").addEventListener("click", () => {
    location.hash = "#profile";
  });
```

- [ ] **Step 7: Write `renderProfileScreen()` and its event listener**

After `renderRoutesScreen()` and its two `addEventListener` blocks (i.e.
after line 2688, before the "supervisor's cross-house review queue" comment
at line 2690), insert:

```javascript
  // ---- My Profile screen ----
  async function renderProfileScreen() {
    const body = document.getElementById("profileBody");
    body.innerHTML = `<p class="screen-sub">Loading…</p>`;
    const res = await window.cloud.getMyProfile();
    if (currentScreenFromHash() !== "profile") return;   // navigated away meanwhile
    if (res.error) {
      body.innerHTML = `<p class="screen-sub">Couldn't load your profile — ${escHtml(res.error)}</p>`;
      return;
    }
    const roleLabel = res.role === "supervisor" ? "Supervisor" : "Tech";
    body.innerHTML = `
      <p class="profile-readonly">Signed in as <b>${escHtml(res.email)}</b> · ${escHtml(roleLabel)}</p>
      <div class="profile-field">
        <label for="profileName">Full name</label>
        <input type="text" id="profileName" value="${escAttr(res.fullName)}">
      </div>
      <div class="profile-field">
        <label for="profilePhone">Phone</label>
        <input type="tel" id="profilePhone" value="${escAttr(res.phone)}" placeholder="e.g. 555-123-4567">
      </div>
      <button type="button" id="profileSaveBtn">Save</button>
      <div id="profileMsg"></div>`;
  }

  document.getElementById("profileBody").addEventListener("click", async e => {
    if (!e.target.closest("#profileSaveBtn")) return;
    const nameInput = document.getElementById("profileName");
    const phoneInput = document.getElementById("profilePhone");
    const msg = document.getElementById("profileMsg");
    const fullName = nameInput.value.trim();
    if (!fullName) {
      msg.textContent = "Name can't be empty.";
      msg.className = "error";
      return;
    }
    const btn = document.getElementById("profileSaveBtn");
    btn.disabled = true;
    msg.textContent = "Saving…";
    msg.className = "";
    const res = await window.cloud.saveMyProfile({ fullName, phone: phoneInput.value.trim() });
    btn.disabled = false;
    if (res.error) {
      msg.textContent = "Couldn't save — " + res.error;
      msg.className = "error";
      return;
    }
    msg.textContent = res.degraded
      ? "Name saved. (Phone sync once the DB update is applied.)"
      : "✓ Saved.";
    msg.className = "ok";
    toast("✓ Profile saved.", "ok");
  });
```

- [ ] **Step 8: Manual verification in the browser**

1. Open the app, sign in as a tech.
2. Confirm a "👤 My profile" button appears on the home screen (not gated to
   supervisors).
3. Click it → confirm the screen shows the signed-in email, role ("Tech"),
   and the current full name in the Full name field.
4. Change the full name and enter a phone number, click Save.
   Expected: "✓ Saved." message + a toast, button re-enables.
5. Click "← Home", then reopen "My profile" (or reload the page and reopen).
   Expected: the new name and phone are still there (confirms the DB write
   persisted, not just local state).
6. In the Supabase dashboard, run
   `select full_name, phone from public.profiles where id = auth.uid();`
   (or filter by the known test email) to confirm the row matches.
7. Sign in as a second tech account; open "My profile"; confirm it shows
   that account's own (different) name/phone, not the first tech's.
8. Try saving with an empty Full name field.
   Expected: inline "Name can't be empty." error, no request sent, existing
   value unchanged on reload.

- [ ] **Step 9: Commit**

```bash
git add route-checklist/index.html
git commit -m "feat: add My Profile screen (view/edit own name and phone)"
```

---

### Task 4: Bump service worker cache version

**Files:**
- Modify: `route-checklist/sw.js`

**Interfaces:**
- Consumes: none.
- Produces: none (deployment hygiene only).

- [ ] **Step 1: Find and bump the cache version**

Read `route-checklist/sw.js`, find the `CACHE` constant (pattern established
across prior sessions — see HANDOFF.md, currently `route-checklist-v14`),
and bump it to the next integer (`route-checklist-v15`), since `index.html`
and `cloud.js` both changed in this plan and devices with the PWA installed
need to pick up the new files.

- [ ] **Step 2: Commit**

```bash
git add route-checklist/sw.js
git commit -m "chore: bump SW cache to v15 for My Profile screen"
```

- [ ] **Step 3: Tell the owner to hard-refresh**

After deploy, remind the owner: hard-refresh (Ctrl+Shift+R) on any browser
tab, and fully close + reopen the PWA on phones, since the old service
worker keeps serving cached files until then (per prior HANDOFF.md notes).

---

## Plan self-review notes

- **Spec coverage:** fields (full name + phone) → Task 1/2/3; self-edit-only
  scope, no cross-tech UI → Task 3 has no tech picker; entry point (home
  button, always visible) → Task 3 Step 3 (no `admin-only` class); read-only
  email + role badge → Task 3 Step 7; graceful degradation if migration not
  applied → Task 2 `isMissingColumn` handling + Task 3's `degraded` message;
  non-empty full_name validation → Task 3 Step 7 click handler.
- **Out of scope confirmed not built:** supervisor-edits-others UI, sign-in
  email change, phone format validation — none of the tasks above add these.
- **Type/name consistency check:** `getMyProfile()` returns `fullName`/`phone`/
  `role`/`email` (camelCase, matching the app's existing JS convention, e.g.
  `houseName`/`itemCount` in `listInProgress`); `saveMyProfile({fullName, phone})`
  takes the same shape. `renderProfileScreen()` reads exactly those same key
  names. `window.cloud` export list includes both new names.
