# Supervisor Team Roster — Slice 1 Implementation Plan

> **For agentic workers:** REQUIRED SUB-SKILL: Use superpowers:subagent-driven-development (recommended) or superpowers:executing-plans to implement this plan task-by-task. Steps use checkbox (`- [ ]`) syntax for tracking.

**Goal:** A supervisor-only 👥 Team screen that lets a supervisor edit any
existing account's name, phone, and role — with a database guarantee that the
last supervisor can never be demoted.

**Architecture:** Pure front-end + `cloud.js` + one small guard migration.
Mirrors the existing `#reviews` / `#profile` screen pattern (hash-router,
`admin-only` home button, `body.is-admin` gate, renderer that re-checks role).
RLS (`profiles_update`, migration 0001) is the real enforcement for name/phone/
role; a new trigger (0021) enforces the last-supervisor / self-demote rule.
Email, password, and "Add member" are inert Slice-2 seams.

**Tech Stack:** Vanilla HTML/CSS/JS (no build step), `@supabase/supabase-js`
via `cloud.js`, Supabase Postgres + RLS, Supabase CLI for migrations.

## Global Constraints

- **This repo is PUBLIC. Never commit secrets.** The publishable key is fine in
  the client; the `service_role` key must never appear. (Slice 1 uses neither
  beyond what's already present.)
- **No new npm dependencies, no build step.** Vanilla JS only.
- **Migrations run via the Supabase CLI:** `supabase db push --workdir
  "c:\Big Dogs Apps\MTX Checklist V1"`. Never hand-paste SQL. Never run
  destructive remote commands.
- **RLS is the real enforcement.** UI gates (`admin-only`, renderer role check)
  are convenience only. Every `cloud.js` function targets a specific `id`.
- **Never send `role` from a name/phone save.** Role changes go through their
  own function.
- **Accessibility is required:** keep `aria-*`, `:focus-visible`,
  `prefers-reduced-motion`; new controls get labels/`aria-label`.
- **Verification is parse-check (headless Chrome) + manual live drive** — this
  repo has NO automated test harness. "Done" is not "committed"; it's driven.
- **Ship the same session:** once the owner verifies on the branch, merge to
  `main` + push (live deploys from `main`), then remind them to hard-refresh
  (Ctrl+Shift+R; fully reopen the PWA on phones).
- **Current SW cache: `route-checklist-v24` → bump to `v25`** (index.html +
  cloud.js change).
- Work happens on branch `feature/supervisor-team-roster` (already created off
  `main`). Do NOT touch `main` until the owner approves the merge.

**Headless-Chrome parse check** (used as the "test" step throughout — the
per-user install; the Program Files path does not exist on this box, and
headless Edge silently prints nothing so is NOT trusted):

```bash
"$LOCALAPPDATA/Google/Chrome/Application/chrome.exe" --headless --disable-gpu \
  --dump-dom --virtual-time-budget=4000 \
  "http://localhost:8000/route-checklist/index.html#team" 2>/dev/null | head -c 400
```

Serve first from the repo root: `python -m http.server 8000`. A clean run
prints DOM (no `SyntaxError` in stderr) and the app shell renders. This does
NOT exercise a logged-in session — that is the owner's live pass.

---

### Task 1: Migration 0021 — guard the last supervisor / self-demote

**Files:**
- Create: `supabase/migrations/0021_guard_last_supervisor.sql`

**Interfaces:**
- Consumes: existing `public.profiles(id, role)`, `public.current_user_role()`,
  and the `auth.uid()` convention from 0001.
- Produces: a `before update` trigger `guard_last_supervisor` on
  `public.profiles`. No new columns, no signature other tasks import.

- [ ] **Step 1: Write the migration**

```sql
-- ============================================================================
-- 0021_guard_last_supervisor.sql — protect against locking everyone out of
-- supervisor access. Runs ALONGSIDE guard_profile_role (0001, which blocks a
-- tech self-promoting); this trigger blocks two DEMOTIONS:
--   1. a supervisor demoting THEIR OWN account (self-lockout), and
--   2. demoting the LAST remaining supervisor.
-- Dashboard / service_role actions (auth.uid() IS NULL) are exempt, so the
-- owner can always repair roles from the Supabase dashboard.
--
-- HOW TO RUN: supabase db push --workdir "c:\Big Dogs Apps\MTX Checklist V1"
-- Safe to re-run (create or replace / drop trigger if exists).
-- ============================================================================

create or replace function public.guard_last_supervisor()
returns trigger
language plpgsql
security definer set search_path = public
as $$
begin
  -- Only care about a role change that moves AWAY from supervisor.
  if old.role = 'supervisor' and new.role is distinct from 'supervisor' then

    -- Dashboard / service_role (no signed-in user) may do anything.
    if auth.uid() is null then
      return new;
    end if;

    -- 1. You cannot demote your own account.
    if old.id = auth.uid() then
      raise exception 'You cannot remove your own supervisor access.';
    end if;

    -- 2. You cannot demote the last supervisor.
    if (select count(*) from public.profiles where role = 'supervisor') <= 1 then
      raise exception 'Cannot demote the last supervisor.';
    end if;
  end if;

  return new;
end;
$$;

drop trigger if exists guard_last_supervisor on public.profiles;
create trigger guard_last_supervisor
  before update on public.profiles
  for each row execute function public.guard_last_supervisor();

-- ============================================================================
-- No RLS or grant changes: profiles_update (0001) already scopes WHICH rows a
-- supervisor may touch. This trigger only refuses specific role transitions.
-- ============================================================================
```

- [ ] **Step 2: Push the migration**

Run: `supabase db push --workdir "c:\Big Dogs Apps\MTX Checklist V1"`
Expected: `0021_guard_last_supervisor.sql` applies with no error; the push
summary shows local = remote through 0021.

- [ ] **Step 3: Verify the trigger exists and enforces**

Run:
```bash
supabase db query --linked "select tgname from pg_trigger where tgname = 'guard_last_supervisor';"
```
Expected: one row, `guard_last_supervisor`.

Reason through enforcement (do NOT run a destructive update on real data):
with exactly one supervisor, an `update profiles set role='tech'` on that row
would hit `count(*) <= 1` → raises. With 2+ supervisors, demoting a *different*
one succeeds; demoting *yourself* raises regardless of count. If a scratch
check is wanted, run it inside a transaction that is rolled back:
```bash
supabase db query --linked "begin; update public.profiles set role='tech' where role='supervisor'; rollback;"
```
Expected (if only one supervisor and run as service_role, which bypasses the
guard): note that `db query` runs as service_role so `auth.uid()` is null and
the guard is exempt — the guard's live behavior is verified in the owner's
signed-in pass (Task 5), not here. This step only confirms the trigger is
installed.

- [ ] **Step 4: Commit**

```bash
git add supabase/migrations/0021_guard_last_supervisor.sql
git commit -m "feat(db): 0021 guard — block demoting last/own supervisor"
```

---

### Task 2: `cloud.js` — roster read + supervisor edits

**Files:**
- Modify: `route-checklist/cloud.js` (add three functions near the My Profile
  block ~line 105–147; export on `window.cloud` ~line 824–836)

**Interfaces:**
- Consumes: module-level `supabase` client; existing `isMissingColumn(error)`
  helper (already used by `saveMyProfile`).
- Produces (exported on `window.cloud`):
  - `listAllProfiles() → Promise<{ people: {id, fullName, phone, role, isMe}[], myId, myEmail } | { error }>`
  - `saveProfileAsSupervisor(id, { fullName, phone }) → Promise<{ error: string|null, degraded?: true }>`
  - `setProfileRole(id, role) → Promise<{ error: string|null }>`

- [ ] **Step 1: Add the three functions**

Insert after `saveMyProfile` (before the `// ---- Visit history` comment,
~line 148):

```javascript
// ---- Team roster (supervisor-only; RLS is the real gate) ----

// Every profile the caller may see. For a supervisor, RLS returns all rows;
// for a tech it returns only their own (the #team renderer blocks techs first
// anyway). profiles has no email column, so only the caller's OWN email is
// known here (auth.getUser()); other rows' email is a Slice-2 concern.
// Returns { people:[{id,fullName,phone,role,isMe}], myId, myEmail } or { error }.
async function listAllProfiles() {
  const { data: { user } } = await supabase.auth.getUser();
  if (!user) return { error: "Not signed in." };
  let { data, error } = await supabase
    .from("profiles").select("id, full_name, phone, role").order("full_name");
  if (error && isMissingColumn(error)) {
    ({ data, error } = await supabase
      .from("profiles").select("id, full_name, role").order("full_name"));
  }
  if (error) return { error: error.message };
  const people = (data || []).map(p => ({
    id: p.id,
    fullName: p.full_name || "",
    phone: p.phone || "",
    role: p.role || "tech",
    isMe: p.id === user.id,
  }));
  return { people, myId: user.id, myEmail: user.email || "" };
}

// Supervisor edits ANOTHER person's name/phone. Never sends role (that goes
// through setProfileRole). RLS refuses this for a non-supervisor. Name-only
// fallback if the phone column is missing (matches saveMyProfile).
async function saveProfileAsSupervisor(id, { fullName, phone }) {
  let { error } = await supabase
    .from("profiles").update({ full_name: fullName, phone }).eq("id", id);
  if (error && isMissingColumn(error)) {
    ({ error } = await supabase
      .from("profiles").update({ full_name: fullName }).eq("id", id));
    if (!error) return { error: null, degraded: true };
  }
  return { error: error ? error.message : null };
}

// The higher-stakes role change, kept its own function so call sites are
// unmistakable. Sends only { role }. The DB guards (guard_profile_role +
// guard_last_supervisor) may refuse — their message is returned verbatim so
// the UI can show exactly why.
async function setProfileRole(id, role) {
  const { error } = await supabase
    .from("profiles").update({ role }).eq("id", id);
  return { error: error ? error.message : null };
}
```

- [ ] **Step 2: Export the three on `window.cloud`**

In the `window.cloud = { … }` object (~line 824), add to the profile line:

```javascript
                 getMyProfile, saveMyProfile,
                 listAllProfiles, saveProfileAsSupervisor, setProfileRole,
```

- [ ] **Step 3: Parse check**

Serve (`python -m http.server 8000` from repo root) and run the headless-Chrome
command from Global Constraints against `#home`.
Expected: DOM prints, no `SyntaxError` in stderr, `cloud.js` module loads.
Also confirm in a browser console (optional, if a session is handy):
`typeof window.cloud.listAllProfiles === "function"` → `true`.

- [ ] **Step 4: Commit**

```bash
git add route-checklist/cloud.js
git commit -m "feat(cloud): listAllProfiles + supervisor name/phone/role edits"
```

---

### Task 3: `#team` screen — markup, home button, router, styles

**Files:**
- Modify: `route-checklist/index.html` (home-button stack ~line 791–811; add a
  `#teamScreen` section alongside `#reviewsScreen`; hash-router `screenFromHash`
  ~line 2641 and the render dispatch; screen-visibility CSS ~line 515; a small
  block of `.team-*` CSS)

**Interfaces:**
- Consumes: `window.cloud.listAllProfiles/saveProfileAsSupervisor/setProfileRole`
  (Task 2); existing helpers `escHtml`, `escAttr`, `fmtDate` (unused here but
  present); the `admin-only` / `body.is-admin` / `data-screen` conventions.
- Produces: a `#team` screen and a `renderTeamScreen()` function (Task 4 fills
  in the roster body; this task establishes the shell + navigation + gate).

- [ ] **Step 1: Add the home-screen button**

After the `homeReviews` button (~line 791), add another `admin-only` button:

```html
  <button type="button" class="home-btn admin-only" id="homeTeam">👥 Team</button>
```

- [ ] **Step 2: Add the screen section**

Alongside the other screen `<section>`s (find `#reviewsScreen` and mirror its
header + body shell):

```html
  <section id="teamScreen" class="screen" aria-labelledby="teamTitle">
    <header class="screen-head">
      <button type="button" class="link-btn" data-home-nav>← Home</button>
      <h1 id="teamTitle">Team</h1>
    </header>
    <div id="teamBody"><p class="screen-sub">Loading…</p></div>
  </section>
```

- [ ] **Step 3: Wire the router**

In `screenFromHash` (~line 2641, where `#reviews` is handled), add:

```javascript
    if (h.startsWith("#team")) return "team";
```

Add the `homeTeam` click handler near the other home buttons (mirroring
`homeReviews` → `location.hash = "#reviews"`):

```javascript
    document.getElementById("homeTeam")
      ?.addEventListener("click", () => { location.hash = "#team"; });
```

In the render dispatch (where `renderReviewsScreen()` is called for the
`"reviews"` case), add a `"team"` case calling `renderTeamScreen()`.

- [ ] **Step 4: Screen-visibility CSS**

In the visibility rule block (~line 515), add `#teamScreen` to the hidden-list
pattern exactly like `#reviewsScreen`:

```css
  body:not([data-screen="team"]) #teamScreen,
```

- [ ] **Step 5: Team screen CSS**

Add near the reviews styles:

```css
  .team-card { border: 1px solid var(--line); border-radius: 10px;
    padding: 12px; margin: 10px 0; }
  .team-card h3 { margin: 0 0 4px; display: flex; align-items: center; gap: 8px; }
  .team-role-badge { font-size: .72rem; font-weight: 600; padding: 2px 8px;
    border-radius: 999px; background: var(--chip); }
  .team-card .muted-row { color: var(--muted); font-size: .85rem; }
  .team-field { display: block; margin: 8px 0; }
  .team-field label { display: block; font-size: .8rem; color: var(--muted); }
  .team-field input, .team-field select { width: 100%; min-height: 40px; }
  .team-me-tag { font-size: .72rem; color: var(--muted); font-weight: 400; }
  .team-error { color: var(--bad); font-size: .85rem; margin-top: 6px; }
```

(Use whatever the existing CSS variables are — reuse `--line`, `--muted`,
`--bad`, `--chip` if present; match the reviews/notes cards. Confirm names by
grep before writing.)

- [ ] **Step 6: Stub `renderTeamScreen` with the role gate**

Add near `renderReviewsScreen` (~line 3069):

```javascript
  async function renderTeamScreen() {
    const body = document.getElementById("teamBody");
    if (!window.cloud || window.cloud.role !== "supervisor" || !window.cloud.listAllProfiles) {
      body.innerHTML = `<p class="screen-sub">Supervisors only.</p>`;
      return;
    }
    body.innerHTML = `<p class="screen-sub">Loading…</p>`;
    // Task 4 fills in the roster render here.
  }
```

- [ ] **Step 7: Parse check**

Serve and run the headless-Chrome command against `#team`.
Expected: DOM prints with the `#teamScreen` section present, no `SyntaxError`.
Because no session is signed in, `renderTeamScreen` shows "Supervisors only."
— that is correct at this step.

- [ ] **Step 8: Commit**

```bash
git add route-checklist/index.html
git commit -m "feat: #team screen shell — home button, router, role gate, styles"
```

---

### Task 4: Team roster body — render, inline edit, role confirm

**Files:**
- Modify: `route-checklist/index.html` (`renderTeamScreen` body from Task 3; add
  helpers `teamCardHTML`, `teamEditHTML`; add a delegated click/change handler
  for the `#teamBody`; add `editingTeamId` state var)

**Interfaces:**
- Consumes: `listAllProfiles`, `saveProfileAsSupervisor`, `setProfileRole`
  (Task 2); the `#team` shell + gate (Task 3); `escHtml`, `escAttr`.
- Produces: the working roster. No exports.

- [ ] **Step 1: Add roster state + render**

Add a module-scope `let editingTeamId = null;` near the other `editing*` state.
Replace the Task-3 stub body of `renderTeamScreen` with:

```javascript
    const res = await window.cloud.listAllProfiles();
    if (currentScreenFromHash() !== "team") return;   // navigated away
    if (res.error) { body.innerHTML =
      `<p class="screen-sub">${escHtml(res.error)}</p>`; return; }
    const { people, myEmail } = res;
    body.innerHTML =
      `<button type="button" class="home-btn" id="teamAddBtn" disabled
         aria-disabled="true">+ Add new team member</button>
       <p class="screen-sub">Adding members, email, and password changes are
         coming in account admin.</p>` +
      people.map(p => teamCardHTML(p, myEmail)).join("");
```

- [ ] **Step 2: Add the card + edit renderers**

```javascript
  // A person's card. Own card: shows real email, no role control. Others:
  // muted email/password seams + editable role.
  function teamCardHTML(p, myEmail) {
    const name = p.fullName || "Unnamed";
    const meTag = p.isMe ? ` <span class="team-me-tag">(you)</span>` : "";
    if (editingTeamId === p.id) return teamEditHTML(p);
    return `<div class="team-card" data-team-id="${escAttr(p.id)}">
      <h3>${escHtml(name)}${meTag}
        <span class="team-role-badge">${escHtml(p.role)}</span></h3>
      <div class="muted-row">📞 ${escHtml(p.phone || "—")}</div>
      <div class="muted-row">✉️ ${p.isMe ? escHtml(myEmail)
        : "Managed in account admin (coming soon)"}</div>
      <div class="muted-row">🔒 Password — managed in account admin (coming soon)</div>
      <button type="button" class="link-btn" data-team-edit="${escAttr(p.id)}">✎ Edit</button>
    </div>`;
  }

  // Inline editor. Role <select> only on OTHER people's cards (you can't
  // demote yourself; the DB also enforces it).
  function teamEditHTML(p) {
    const roleField = p.isMe ? "" : `
      <label class="team-field">Role
        <select data-team-role>
          <option value="tech"${p.role === "tech" ? " selected" : ""}>tech</option>
          <option value="supervisor"${p.role === "supervisor" ? " selected" : ""}>supervisor</option>
        </select></label>`;
    return `<div class="team-card" data-team-id="${escAttr(p.id)}">
      <label class="team-field">Full name
        <input type="text" data-team-name value="${escAttr(p.fullName)}"></label>
      <label class="team-field">Phone
        <input type="text" data-team-phone value="${escAttr(p.phone)}"></label>
      ${roleField}
      <div class="team-error" data-team-error hidden></div>
      <button type="button" class="home-btn" data-team-save="${escAttr(p.id)}">Save</button>
      <button type="button" class="link-btn" data-team-cancel>Cancel</button>
    </div>`;
  }
```

- [ ] **Step 3: Add the delegated handler**

Near the other screen handlers (e.g. the reviews `body` click handler ~line
3125), add a click handler bound to `#teamBody`:

```javascript
  document.getElementById("teamBody")?.addEventListener("click", async (e) => {
    const edit = e.target.closest("[data-team-edit]");
    if (edit) { editingTeamId = edit.dataset.teamEdit; renderTeamScreen(); return; }
    if (e.target.closest("[data-team-cancel]")) {
      editingTeamId = null; renderTeamScreen(); return;
    }
    const save = e.target.closest("[data-team-save]");
    if (save) {
      const card = save.closest(".team-card");
      const id = save.dataset.teamSave;
      const fullName = card.querySelector("[data-team-name]").value.trim();
      const phone = card.querySelector("[data-team-phone]").value.trim();
      const errEl = card.querySelector("[data-team-error]");
      const showErr = (msg) => { errEl.textContent = msg; errEl.hidden = false; };
      if (!fullName) { showErr("Name can't be empty."); return; }

      // Role change (only present on other people's cards) — confirm first.
      const roleSel = card.querySelector("[data-team-role]");
      const people = (await window.cloud.listAllProfiles()).people || [];
      const before = people.find(p => p.id === id);
      if (roleSel && before && roleSel.value !== before.role) {
        const ok = confirm(
          `Change ${fullName || "this person"} from ${before.role} to ${roleSel.value}?`);
        if (!ok) return;
        const r = await window.cloud.setProfileRole(id, roleSel.value);
        if (r.error) { showErr(r.error); return; }   // DB guard message shows here
      }

      const s = await window.cloud.saveProfileAsSupervisor(id, { fullName, phone });
      if (s.error) { showErr(s.error); return; }
      editingTeamId = null;
      renderTeamScreen();
    }
  });
```

(If the existing screens use one central delegated listener rather than
per-screen listeners, follow THAT pattern instead — grep how the reviews
handler is attached and match it. The logic above is unchanged either way.)

- [ ] **Step 4: Parse check**

Serve and run headless Chrome against `#team`. Expected: no `SyntaxError`; the
"Supervisors only." gate still shows (no session). Confirm the new helper
functions are defined (no `ReferenceError` in stderr).

- [ ] **Step 5: Commit**

```bash
git add route-checklist/index.html
git commit -m "feat: Team roster body — inline name/phone/role edit + confirm"
```

---

### Task 5: SW cache bump + live verification handoff

**Files:**
- Modify: `route-checklist/sw.js:7` (`v24` → `v25`)

**Interfaces:**
- Consumes: everything above. Produces: a shippable branch.

- [ ] **Step 1: Bump the SW cache**

Change `route-checklist/sw.js` line 7:

```javascript
const CACHE = "route-checklist-v25";
```

- [ ] **Step 2: Final parse check**

Serve and run headless Chrome against `#home`, `#team`. Expected: no
`SyntaxError`, both shells render, `cloud.js` loads.

- [ ] **Step 3: Commit**

```bash
git add route-checklist/sw.js
git commit -m "chore: bump SW cache to v25 for Team roster slice"
```

- [ ] **Step 4: Owner live-drive on the branch (NOT yet merged)**

The owner runs this signed-in pass against the branch build (the agent cannot
sign in to real Supabase). Do NOT merge to `main` until every item passes:

1. Sign in as the supervisor → home shows **👥 Team** (admin-only). Techs
   don't see it.
2. Open Team → every account lists as a card: name, role badge, phone, own
   email shown, others' email/password read-only "coming soon". "+ Add new
   team member" is visible but disabled.
3. ✎ Edit a tech → change name + phone → Save → card updates; reload →
   persists. Confirm in Supabase:
   `supabase db query --linked "select full_name, phone from profiles where full_name = '…';"`
4. ✎ Edit that tech → set Role = supervisor → confirm dialog names them →
   Save → reload → role persisted; sign in as that account → supervisor
   screens now visible. Then demote them back (works — 2+ supervisors).
5. With that account demoted back so only YOU are supervisor: ✎ Edit yourself
   → confirm there is **no role control** on your own card.
6. Create a second temporary supervisor, then try to demote yourself via
   another supervisor account is not possible from your own card (no control);
   verify the DB guard by having a second supervisor attempt to demote the
   *last* one → blocked with "Cannot demote the last supervisor."
7. As a tech: no 👥 Team button; deep-link `#team` in the URL → "Supervisors
   only." No console errors.
8. Deep-link reload on `#team` as supervisor → roster re-renders, no errors.

- [ ] **Step 5: Merge + deploy (only after owner approves)**

```bash
git switch main
git merge --no-ff feature/supervisor-team-roster
git push origin main
```

Then remind the owner: hard-refresh (Ctrl+Shift+R, maybe twice for the v25 SW;
fully close/reopen the PWA on phones). Update `HANDOFF.md` with the shipped
state. The old branch can be deleted once confirmed live.

---

## Self-Review

**Spec coverage:**
- Team screen (supervisor-only, 👥) → Task 3. ✓
- Edit name/phone → Task 2 (`saveProfileAsSupervisor`) + Task 4 (UI). ✓
- Change role with confirm + no self-demote UI → Task 4. ✓
- Last-supervisor / self-demote DB guarantee → Task 1 (migration 0021). ✓
- Email/password read-only seams + disabled "Add member" → Task 4. ✓
- Techs blocked ("Supervisors only.") → Task 3 gate. ✓
- Re-render-from-server discipline → Task 4 (every mutation → `renderTeamScreen`). ✓
- SW bump + ship-same-session → Task 5. ✓

**Placeholder scan:** No TBD/TODO in shipped code. The Task-3 stub comment
"Task 4 fills in the roster render here" is replaced wholesale in Task 4 Step 1
(not left in the final code). ✓

**Type consistency:** `listAllProfiles` returns `{ people, myId, myEmail }`
used consistently in Task 4. `saveProfileAsSupervisor(id, {fullName, phone})`
and `setProfileRole(id, role)` signatures match their call sites. Card data
attributes (`data-team-id/edit/save/cancel/role/name/phone/error`) are
consistent between `teamCardHTML`, `teamEditHTML`, and the handler. ✓

**Note for the implementer:** several steps say "match the existing pattern"
(central vs. per-screen listeners, exact CSS var names, the render-dispatch
switch). Before writing, grep how `#reviews` does each and mirror it — the repo
has one established way and this screen must not invent a second.
