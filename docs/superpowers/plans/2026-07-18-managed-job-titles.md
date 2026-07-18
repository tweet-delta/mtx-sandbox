# Managed Job Titles + Office/Field Home Screens — Implementation Plan

> **For agentic workers:** REQUIRED SUB-SKILL: Use superpowers:subagent-driven-development (recommended) or superpowers:executing-plans to implement this plan task-by-task. Steps use checkbox (`- [ ]`) syntax for tracking.

**Goal:** Turn the free-text `profiles.job_title` into a supervisor-managed list of official job titles (a real `job_titles` table), assign them via a dropdown on the Team screen, and let each title's `field`/`office` kind decide whether a person sees the field tooling (house visits, daily logs) on their home screen.

**Architecture:** One SQL migration adds a `job_titles` table (RLS: all read, supervisors write) and a `profiles.job_title_id` foreign key, and backfills existing text titles. `cloud.js` gains title-CRUD functions and switches profile reads/writes to the joined title. `index.html` gets a supervisor-only `#titles` screen, a dropdown on `#team`, a read-only title on `#profile`, and a `body.is-office` CSS gate that hides field-only home buttons. The Edge Function's `list` action returns the joined title. Mirrors the existing `#team`/`#reviews`/`#tickets` screen patterns exactly.

**Tech Stack:** Vanilla HTML/CSS/JS (no build step), Supabase Postgres + RLS, Supabase CLI migrations, one Deno Edge Function (`admin-users`).

## Global Constraints

- **This git repo is PUBLIC and Supabase holds a demo.** Never commit secrets; only fake/sample data. (CLAUDE.md)
- **RLS is the real enforcement, never the UI.** Every screen's role check is convenience; the database policy is the guarantee. (CLAUDE.md)
- **No bandaids, no data loss.** The proper relational model ships now; the old free-text `profiles.job_title` column is *kept but unused* for one release as a recovery net, dropped later in a separate migration.
- **Migrations run via CLI:** `supabase db push --workdir "c:\Big Dogs Apps\MTX Checklist V1"`. Next free number is **0027**. Migrations must be idempotent (`if not exists`, `on conflict do nothing`).
- **Supervisor-write RLS predicate (copy verbatim from 0025):** `public.current_user_role() = 'supervisor'`. Read predicate for shared lists: `auth.uid() is not null`. Auto-expose is OFF — every table needs an explicit `grant ... to authenticated`.
- **Titles are supervisor-assigned only.** People cannot set their own title (it governs their home screen and later their permissions).
- **Every person, any title, always keeps:** House notes, My notes, My profile, and the maintenance-request screens (My tickets / Tickets / Notifications — already built). `field`-only = New house visit, Continue house visit, My visit history, Daily logs, 🧰 Field tools drawer.
- **`field` and `office` are the only two kinds** (`check (kind in ('field','office'))`).
- **Finished work ships the same session:** merge to `main`, push, bump the SW cache version (currently `route-checklist-v29` in `sw.js`), remind the owner to hard-refresh. (CLAUDE.md)
- **Verify for real:** run the app in Chrome, drive the flow, and confirm rows with `supabase db query --linked`. No automated test harness exists.

---

### Task 1: Migration `0027_job_titles.sql` (table + FK + RLS + backfill)

**Files:**
- Create: `supabase/migrations/0027_job_titles.sql`

**Interfaces:**
- Produces: table `public.job_titles(id uuid, name text, kind text, active bool, created_at timestamptz)`; column `public.profiles.job_title_id uuid references job_titles(id)`; RLS policies `job_titles_select` (all authenticated read) and `job_titles_write` (supervisor insert/update). Consumed by every later task.

- [ ] **Step 1: Write the migration file**

Create `supabase/migrations/0027_job_titles.sql` with exactly this content:

```sql
-- ============================================================================
-- 0027_job_titles.sql — a supervisor-managed list of official job titles.
-- Spec: docs/superpowers/specs/2026-07-18-managed-job-titles-design.md
--
-- Replaces the free-text profiles.job_title (0022) with a real table + FK so
-- titles are consistent, renamable everywhere at once, and carry a `kind`
-- (field/office) that decides a person's home screen. Permissions attach here
-- LATER (Slice 2). The old text column is KEPT but unused for one release as a
-- recovery net; a later migration drops it once the backfill is confirmed good.
--
-- HOW TO RUN: supabase db push --workdir "c:\Big Dogs Apps\MTX Checklist V1"
-- Safe to re-run (if not exists / on conflict do nothing).
-- ============================================================================

create table if not exists public.job_titles (
  id         uuid primary key default gen_random_uuid(),
  name       text not null check (length(trim(name)) > 0),
  kind       text not null default 'field' check (kind in ('field','office')),
  active     boolean not null default true,
  created_at timestamptz not null default now()
);

-- Case-insensitive uniqueness: "Lead Tech" and "lead tech" can't both exist.
create unique index if not exists job_titles_name_lower_idx
  on public.job_titles (lower(name));

alter table public.profiles
  add column if not exists job_title_id uuid references public.job_titles (id);

-- ---------------------------------------------------------------------------
-- Row-Level Security. Everyone signed in reads the list (dropdowns + labels);
-- only supervisors create/edit titles. No delete policy — titles are retired
-- (active=false), never deleted, so the FK can't orphan a profile.
-- ---------------------------------------------------------------------------
alter table public.job_titles enable row level security;

create policy job_titles_select on public.job_titles
  for select using (auth.uid() is not null);

create policy job_titles_insert on public.job_titles
  for insert with check (public.current_user_role() = 'supervisor');

create policy job_titles_update on public.job_titles
  for update using  (public.current_user_role() = 'supervisor')
             with check (public.current_user_role() = 'supervisor');

-- Auto-expose is OFF in this project, so grant table access explicitly.
grant select, insert, update on public.job_titles to authenticated;

-- ---------------------------------------------------------------------------
-- Backfill: one job_titles row per distinct non-empty existing text title
-- (kind='field' — everyone today is a field tech), then point each profile at
-- its matching row. Idempotent: re-running inserts nothing new and re-links
-- the same rows.
-- ---------------------------------------------------------------------------
insert into public.job_titles (name, kind)
select distinct trim(job_title), 'field'
from public.profiles
where job_title is not null and trim(job_title) <> ''
on conflict (lower(name)) do nothing;

update public.profiles p
set job_title_id = jt.id
from public.job_titles jt
where p.job_title is not null
  and trim(p.job_title) <> ''
  and lower(trim(p.job_title)) = lower(jt.name)
  and p.job_title_id is null;
```

- [ ] **Step 2: Apply the migration**

Run: `supabase db push --workdir "c:\Big Dogs Apps\MTX Checklist V1"`
Expected: applies `0027_job_titles.sql` with no error.

- [ ] **Step 3: Verify the schema and backfill**

Run:
```
supabase db query --linked "select column_name from information_schema.columns where table_schema='public' and table_name='job_titles' order by column_name;"
supabase db query --linked "select p.full_name, p.job_title, jt.name, jt.kind from public.profiles p left join public.job_titles jt on jt.id = p.job_title_id order by p.full_name;"
```
Expected: first query lists `active, created_at, id, kind, name`. Second query shows every profile that had a non-empty text title now linked to a `job_titles` row whose `name` matches and `kind` is `field`; the old `job_title` text is still present (untouched).

- [ ] **Step 4: Verify RLS (supervisor-write, all-read)**

Run:
```
supabase db query --linked "select policyname, cmd from pg_policies where tablename='job_titles' order by policyname;"
```
Expected: rows `job_titles_insert (INSERT)`, `job_titles_select (SELECT)`, `job_titles_update (UPDATE)`. No delete policy.

- [ ] **Step 5: Commit**

```bash
git add supabase/migrations/0027_job_titles.sql
git commit -m "feat(db): 0027 job_titles table + profiles.job_title_id + backfill"
```

---

### Task 2: `cloud.js` — title-list CRUD functions

**Files:**
- Modify: `route-checklist/cloud.js` (add functions after `saveProfileAsSupervisor`/`setProfileRole`, near line 201; export them in the `window.cloud = {...}` block at line 1100)

**Interfaces:**
- Consumes: the module-scoped `supabase` client and the existing `isMissingColumn(error)` helper (already in cloud.js).
- Produces, all on `window.cloud`:
  - `listJobTitles({ activeOnly } = {})` → `{ titles: [{ id, name, kind, active }], error }` (titles ordered by name; `activeOnly:true` filters to `active=true`).
  - `createJobTitle({ name, kind })` → `{ error }` (friendly duplicate message).
  - `renameJobTitle(id, name)` → `{ error }`.
  - `setJobTitleKind(id, kind)` → `{ error }`.
  - `setJobTitleActive(id, active)` → `{ error }`.

- [ ] **Step 1: Add the five functions to cloud.js**

Insert this block immediately AFTER the `setProfileRole` function (which ends at `route-checklist/cloud.js:201` with its closing `}`), BEFORE the `// ---- Account admin (the admin-users Edge Function) ----` comment:

```javascript
// ---- Job titles (supervisor-managed list; RLS is the real gate) ----
// The list everyone reads (for dropdowns + labels); only supervisors write.

// All titles, ordered by name. activeOnly:true → only assignable ones (the
// Team dropdown); the management screen passes nothing to see retired ones too.
// Returns { titles:[{id,name,kind,active}], error }.
async function listJobTitles({ activeOnly } = {}) {
  let q = supabase.from("job_titles").select("id, name, kind, active").order("name");
  if (activeOnly) q = q.eq("active", true);
  const { data, error } = await q;
  if (error) return { titles: [], error: error.message };
  return { titles: (data || []).map(t => ({
    id: t.id, name: t.name, kind: t.kind || "field", active: t.active !== false,
  })) };
}

// Create a title (supervisor-only via RLS). Trims name. The unique lower(name)
// index (0027) rejects a duplicate — surfaced as a friendly message.
async function createJobTitle({ name, kind }) {
  const clean = (name || "").trim();
  if (!clean) return { error: "Title name can't be empty." };
  const k = kind === "office" ? "office" : "field";
  const { error } = await supabase.from("job_titles").insert({ name: clean, kind: k });
  if (error) {
    if ((error.code === "23505") || /duplicate|unique/i.test(error.message || "")) {
      return { error: "A title with that name already exists." };
    }
    return { error: error.message };
  }
  return { error: null };
}

async function renameJobTitle(id, name) {
  const clean = (name || "").trim();
  if (!clean) return { error: "Title name can't be empty." };
  const { error } = await supabase.from("job_titles").update({ name: clean }).eq("id", id);
  if (error) {
    if ((error.code === "23505") || /duplicate|unique/i.test(error.message || "")) {
      return { error: "A title with that name already exists." };
    }
    return { error: error.message };
  }
  return { error: null };
}

async function setJobTitleKind(id, kind) {
  const k = kind === "office" ? "office" : "field";
  const { error } = await supabase.from("job_titles").update({ kind: k }).eq("id", id);
  return { error: error ? error.message : null };
}

async function setJobTitleActive(id, active) {
  const { error } = await supabase.from("job_titles").update({ active: !!active }).eq("id", id);
  return { error: error ? error.message : null };
}
```

- [ ] **Step 2: Export the five functions**

In `route-checklist/cloud.js`, find the `window.cloud = { ... }` assignment (starts at line 1100). Add this line right after the existing `listTeam, createTeamMember,` line:

```javascript
                 listJobTitles, createJobTitle, renameJobTitle, setJobTitleKind, setJobTitleActive,
```

- [ ] **Step 3: Parse-check cloud.js**

Run (from `route-checklist/`): `node --check cloud.js`
Expected: no output (exit 0), meaning zero SyntaxError.

- [ ] **Step 4: Commit**

```bash
git add route-checklist/cloud.js
git commit -m "feat(cloud): job-title list CRUD (list/create/rename/setKind/setActive)"
```

---

### Task 3: `cloud.js` — profile reads/writes use the linked title

**Files:**
- Modify: `route-checklist/cloud.js` — `getMyProfile` (105-128), `saveMyProfile` (133-148), `listAllProfiles` (158-177), `saveProfileAsSupervisor` (182-191), `loadRole` (64-80)

**Interfaces:**
- Consumes: `job_titles`/`profiles.job_title_id` from Task 1; `isMissingColumn` helper.
- Produces:
  - `getMyProfile()` now returns `{ ..., jobTitleName, jobTitleKind }` (was `jobTitle`).
  - `saveMyProfile({ fullName, phone })` — no longer accepts/sends a title.
  - `listAllProfiles()` people carry `{ ..., jobTitleId, jobTitleName, jobTitleKind }`.
  - `saveProfileAsSupervisor(id, { fullName, phone, jobTitleId })` — sends `job_title_id`.
  - `loadRole()` sets `window.cloud.jobTitleKind` and toggles `body.is-office`.

- [ ] **Step 1: Rewrite `getMyProfile` to join the title**

Replace the whole `getMyProfile` function (`route-checklist/cloud.js:111-128`) with:

```javascript
async function getMyProfile() {
  const { data: { user } } = await supabase.auth.getUser();
  if (!user) return { error: "Not signed in." };
  let { data, error } = await supabase
    .from("profiles")
    .select("full_name, phone, role, job_title_id, job_titles(name, kind)")
    .eq("id", user.id).maybeSingle();
  if (error && isMissingColumn(error)) {
    ({ data, error } = await supabase
      .from("profiles").select("full_name, role").eq("id", user.id).maybeSingle());
  }
  if (error) return { error: error.message };
  const jt = data?.job_titles || null;
  return {
    fullName: data?.full_name || "",
    phone: data?.phone || "",
    jobTitleName: jt?.name || "",
    jobTitleKind: jt?.kind || "",
    role: data?.role || "tech",
    email: user.email || "",
  };
}
```

- [ ] **Step 2: Rewrite `saveMyProfile` to stop sending a title**

Replace the whole `saveMyProfile` function (`route-checklist/cloud.js:133-148`) with:

```javascript
async function saveMyProfile({ fullName, phone }) {
  const { data: { user } } = await supabase.auth.getUser();
  if (!user) return { error: "Not signed in." };
  let { error } = await supabase
    .from("profiles").update({ full_name: fullName, phone }).eq("id", user.id);
  if (error && isMissingColumn(error)) {
    ({ error } = await supabase
      .from("profiles").update({ full_name: fullName }).eq("id", user.id));
    if (!error) return { error: null, degraded: true };
  }
  return { error: error ? error.message : null };
}
```

- [ ] **Step 3: Rewrite `listAllProfiles` to join the title**

Replace the whole `listAllProfiles` function (`route-checklist/cloud.js:158-177`) with:

```javascript
async function listAllProfiles() {
  const { data: { user } } = await supabase.auth.getUser();
  if (!user) return { error: "Not signed in." };
  let { data, error } = await supabase
    .from("profiles")
    .select("id, full_name, phone, role, job_title_id, job_titles(name, kind)")
    .order("full_name");
  if (error && isMissingColumn(error)) {
    ({ data, error } = await supabase
      .from("profiles").select("id, full_name, role").order("full_name"));
  }
  if (error) return { error: error.message };
  const people = (data || []).map(p => ({
    id: p.id,
    fullName: p.full_name || "",
    phone: p.phone || "",
    jobTitleId: p.job_title_id || null,
    jobTitleName: p.job_titles?.name || "",
    jobTitleKind: p.job_titles?.kind || "",
    role: p.role || "tech",
    isMe: p.id === user.id,
  }));
  return { people, myId: user.id, myEmail: user.email || "" };
}
```

- [ ] **Step 4: Rewrite `saveProfileAsSupervisor` to send `job_title_id`**

Replace the whole `saveProfileAsSupervisor` function (`route-checklist/cloud.js:182-191`) with:

```javascript
async function saveProfileAsSupervisor(id, { fullName, phone, jobTitleId }) {
  const patch = { full_name: fullName, phone, job_title_id: jobTitleId || null };
  let { error } = await supabase.from("profiles").update(patch).eq("id", id);
  if (error && isMissingColumn(error)) {
    ({ error } = await supabase
      .from("profiles").update({ full_name: fullName }).eq("id", id));
    if (!error) return { error: null, degraded: true };
  }
  return { error: error ? error.message : null };
}
```

- [ ] **Step 5: Set `body.is-office` in `loadRole`**

In `loadRole` (`route-checklist/cloud.js:64-80`), the current body reads the role and sets `is-admin`. Replace lines 68-73 (from `const { data, error } = await supabase` through `if (window.applyRole) window.applyRole(window.cloud.role);`) with:

```javascript
  const { data, error } = await supabase
    .from("profiles").select("role, job_titles(kind)").eq("id", user.id).maybeSingle();
  if (error) {
    // Fall back to role-only if job_titles isn't joinable yet (pre-0027).
    const { data: d2, error: e2 } = await supabase
      .from("profiles").select("role").eq("id", user.id).maybeSingle();
    if (e2) { console.error("Could not load role:", e2.message); return; }
    window.cloud.role = d2?.role || "tech";
    window.cloud.jobTitleKind = "";
  } else {
    window.cloud.role = data?.role || "tech";
    window.cloud.jobTitleKind = data?.job_titles?.kind || "";
  }
  document.body.classList.toggle("is-admin", window.cloud.role === "supervisor");
  document.body.classList.toggle("is-office", window.cloud.jobTitleKind === "office");
  if (window.applyRole) window.applyRole(window.cloud.role);
```

(The lines below — the `if (window.cloud.role === "supervisor") { ... }` block — stay unchanged.)

- [ ] **Step 6: Parse-check cloud.js**

Run (from `route-checklist/`): `node --check cloud.js`
Expected: no output (exit 0).

- [ ] **Step 7: Commit**

```bash
git add route-checklist/cloud.js
git commit -m "feat(cloud): profile reads/writes use linked job title; loadRole sets is-office"
```

---

### Task 4: Edge Function `list` returns the linked title

**Files:**
- Modify: `supabase/functions/admin-users/index.ts:87-102` (the `list` action's profile select + mapped object)

**Interfaces:**
- Consumes: `profiles.job_title_id` + `job_titles` from Task 1.
- Produces: each person in the `list` response carries `jobTitleId` and `jobTitleName` (in addition to the existing fields). The old `jobTitle` free-text field is removed from the response.

- [ ] **Step 1: Update the profile select to join the title**

In `supabase/functions/admin-users/index.ts`, in the `if (action === "list")` block, replace this line (line 87-88):

```javascript
      const { data: profs } = await admin
        .from("profiles").select("id, full_name, phone, job_title, role, active");
```

with:

```javascript
      const { data: profs } = await admin
        .from("profiles")
        .select("id, full_name, phone, role, active, job_title_id, job_titles(name)");
```

- [ ] **Step 2: Update the mapped person object**

In the same block, replace the `jobTitle` line (line 97) inside the returned object:

```javascript
          jobTitle: (p.job_title as string) ?? "",
```

with:

```javascript
          jobTitleId: (p.job_title_id as string) ?? null,
          jobTitleName: ((p.job_titles as { name?: string } | null)?.name) ?? "",
```

- [ ] **Step 3: Deploy the function**

Run: `supabase functions deploy admin-users --workdir "c:\Big Dogs Apps\MTX Checklist V1"`
Expected: deploys with no error.

- [ ] **Step 4: Commit**

```bash
git add supabase/functions/admin-users/index.ts
git commit -m "feat(fn): admin-users list returns linked job title (id + name)"
```

---

### Task 5: `#titles` screen — HTML shell + CSS + router wiring

**Files:**
- Modify: `route-checklist/index.html` — add screen container (after `#teamScreen`, ~line 1009); add home button (after `homeTeam`, ~line 899); add router cases (`currentScreenFromHash` ~2846, `showScreen` ~2866); add the display-toggle CSS rule (~line 516); add the home-button click handler (~line 2929).

**Interfaces:**
- Consumes: nothing yet (render function comes in Task 6). Sets up the seams the renderer plugs into: element `#titlesBody`, hash `#titles` → screen `"titles"`, and a `homeTitles` button.
- Produces: a routable, supervisor-gated (via `admin-only` CSS) empty `#titles` screen.

- [ ] **Step 1: Add the screen container**

In `route-checklist/index.html`, immediately after the `#teamScreen` block closes (`</div>` at line 1009), insert:

```html
<div id="titlesScreen" class="screen" aria-label="Job titles">
  <div class="screen-head">
    <button type="button" class="menu-btn" data-nav-home>← Home</button>
    <h1>Job titles</h1>
  </div>
  <div id="titlesBody"><p class="screen-sub">Loading…</p></div>
</div>
```

- [ ] **Step 2: Add the display-toggle CSS**

In the screen-visibility rule list (`route-checklist/index.html:516`), add a line after `body:not([data-screen="team"])     #teamScreen,`:

```css
  body:not([data-screen="titles"])   #titlesScreen,
```

- [ ] **Step 3: Add the home button**

In the home screen, immediately after the `homeTeam` button block (ends at line 899 with `</button>`), insert:

```html
  <button type="button" class="home-btn admin-only" id="homeTitles">🏷️ Job titles
    <small>Create &amp; manage the team's job titles</small></button>
```

- [ ] **Step 4: Add the router cases**

In `currentScreenFromHash` (`route-checklist/index.html:2846`), add this line right after the `if (h.startsWith("#team")) return "team";` line (line 2858):

```javascript
    if (h.startsWith("#titles")) return "titles";
```

In `showScreen` (`route-checklist/index.html:2866`), add this line right after `if (scr === "team") renderTeamScreen();` (line 2877):

```javascript
    if (scr === "titles") renderTitlesScreen();
```

- [ ] **Step 5: Add the home-button click handler**

In the home-button wiring, right after the `homeTeam` click handler (`route-checklist/index.html:2929-2932`), insert:

```javascript
  document.getElementById("homeTitles").addEventListener("click", () => {
    editingTitleId = null;   // always land on Job titles with no card mid-edit
    location.hash = "#titles";
  });
```

- [ ] **Step 6: Declare the `editingTitleId` state variable**

The Team screen declares `editingTeamId`. Find that declaration (search for `let editingTeamId`) and add, right after it:

```javascript
  // Job titles: id of the title whose card is open for editing, or null; and
  // whether the "+ Add title" form is open. Single-open discipline like Team.
  let editingTitleId = null;
  let titleAddOpen = false;
```

- [ ] **Step 7: Add a temporary stub renderer so the page parses**

So Steps 4-5 reference a defined function before Task 6 fills it in, add this stub right BEFORE `renderTeamScreen` (`route-checklist/index.html:3406`):

```javascript
  async function renderTitlesScreen() {
    document.getElementById("titlesBody").innerHTML =
      `<p class="screen-sub">Coming up in the next step.</p>`;
  }
```

(Task 6 replaces this stub with the real renderer.)

- [ ] **Step 8: Parse-check the page in headless Chrome**

Run (from `route-checklist/`), start a static server and load the page, watching for SyntaxError:
```
python -m http.server 8099 &
"%LOCALAPPDATA%\Google\Chrome\Application\chrome.exe" --headless --disable-gpu --dump-dom "http://localhost:8099/index.html" > /dev/null
```
Expected: Chrome exits cleanly; no `SyntaxError` in output. (Kill the server after: `kill %1`.)

- [ ] **Step 9: Commit**

```bash
git add route-checklist/index.html
git commit -m "feat(ui): #titles screen shell, home button, router wiring, is-office state"
```

---

### Task 6: `#titles` screen — the real renderer + interactions

**Files:**
- Modify: `route-checklist/index.html` — replace the Task 5 stub `renderTitlesScreen` (~line 3406) with the real one + card-HTML helpers; add a `#titlesBody` click handler (near the Team handler, ~line 3218).

**Interfaces:**
- Consumes: `window.cloud.listJobTitles`, `.createJobTitle`, `.renameJobTitle`, `.setJobTitleKind`, `.setJobTitleActive` (Task 2); `editingTitleId`, `titleAddOpen` (Task 5); existing helpers `escHtml`, `escAttr`, `toast`, `currentScreenFromHash`, `window.cloud.role`.
- Produces: a working supervisor-only titles manager (add / rename / change kind / retire / reactivate), re-rendered from the server after each change.

- [ ] **Step 1: Replace the stub renderer with the real one + helpers**

Replace the stub `renderTitlesScreen` function from Task 5 Step 7 with this block:

```javascript
  async function renderTitlesScreen() {
    const body = document.getElementById("titlesBody");
    if (!window.cloud || window.cloud.role !== "supervisor") {
      body.innerHTML = `<p class="screen-sub">Supervisors only.</p>`;
      return;
    }
    body.innerHTML = `<p class="screen-sub">Loading…</p>`;
    const res = await window.cloud.listJobTitles();   // all, incl. retired
    if (currentScreenFromHash() !== "titles") return;  // navigated away meanwhile
    if (res.error) {
      body.innerHTML = `<p class="screen-sub">Couldn't load job titles — ${escHtml(res.error)}</p>`;
      return;
    }
    const titles = res.titles || [];
    body.innerHTML =
      `<button type="button" class="home-btn" id="titleAddBtn">+ Add job title</button>` +
      (titleAddOpen ? titleAddFormHTML() : "") +
      (titles.length
        ? titles.map(t => titleCardHTML(t)).join("")
        : `<p class="screen-sub">No titles yet — add your first one above.</p>`);
    if (titleAddOpen) body.querySelector("[data-title-new-name]")?.focus();
  }

  // The "+ Add title" form: name + a field/office picker.
  function titleAddFormHTML() {
    return `<div class="team-card" data-title-add-form>
      <label class="team-field"><span>Title name</span>
        <input type="text" data-title-new-name placeholder="e.g. Interior Designer"></label>
      <label class="team-field"><span>Kind</span>
        ${kindSelectHTML("field")}</label>
      <p class="team-error" data-title-error hidden></p>
      <div class="team-edit-actions">
        <button type="button" class="menu-btn team-save" data-title-create>Add</button>
        <button type="button" class="menu-btn team-cancel" data-title-add-cancel>Cancel</button>
      </div>
    </div>`;
  }

  // A field/office dropdown; `sel` is the currently-selected value.
  function kindSelectHTML(sel) {
    return `<select data-title-kind>
      <option value="field"${sel === "field" ? " selected" : ""}>Field (house visits &amp; daily logs)</option>
      <option value="office"${sel === "office" ? " selected" : ""}>Office / Projects</option>
    </select>`;
  }

  function titleCardHTML(t) {
    if (editingTitleId === t.id) return titleEditHTML(t);
    const kindLabel = t.kind === "office" ? "Office / Projects" : "Field";
    const retired = t.active === false
      ? ` <span class="team-role-badge">retired</span>` : "";
    return `<div class="team-card" data-title-card data-title-id="${escAttr(t.id)}">
      <h3>${escHtml(t.name)}
        <span class="team-role-badge">${escHtml(kindLabel)}</span>${retired}</h3>
      <div class="team-edit-actions">
        <button type="button" class="menu-btn team-edit-btn" data-title-edit="${escAttr(t.id)}">✎ Edit</button>
        <button type="button" class="menu-btn" data-title-active="${escAttr(t.id)}" data-title-to="${t.active === false ? "1" : "0"}">${t.active === false ? "Reactivate" : "Retire"}</button>
      </div>
    </div>`;
  }

  function titleEditHTML(t) {
    return `<div class="team-card" data-title-card data-title-id="${escAttr(t.id)}">
      <label class="team-field"><span>Title name</span>
        <input type="text" data-title-name value="${escAttr(t.name)}"></label>
      <label class="team-field"><span>Kind</span>
        ${kindSelectHTML(t.kind === "office" ? "office" : "field")}</label>
      <p class="team-error" data-title-error hidden></p>
      <div class="team-edit-actions">
        <button type="button" class="menu-btn team-save" data-title-save="${escAttr(t.id)}">Save</button>
        <button type="button" class="menu-btn team-cancel" data-title-cancel>Cancel</button>
      </div>
    </div>`;
  }
```

- [ ] **Step 2: Add the `#titlesBody` click handler**

Immediately after the Team roster click handler closes (`route-checklist/index.html`, the `});` at line 3293 that ends `document.getElementById("teamBody").addEventListener(...)`), insert:

```javascript
  // ---- Job-titles interactions (supervisor-only; RLS enforces) ----
  document.getElementById("titlesBody").addEventListener("click", async (e) => {
    if (e.target.closest("#titleAddBtn")) {
      titleAddOpen = true; editingTitleId = null; renderTitlesScreen(); return;
    }
    if (e.target.closest("[data-title-add-cancel]")) {
      titleAddOpen = false; renderTitlesScreen(); return;
    }
    const editBtn = e.target.closest("[data-title-edit]");
    if (editBtn) { editingTitleId = editBtn.dataset.titleEdit; titleAddOpen = false; renderTitlesScreen(); return; }
    if (e.target.closest("[data-title-cancel]")) {
      editingTitleId = null; renderTitlesScreen(); return;
    }

    // Retire / reactivate.
    const activeBtn = e.target.closest("[data-title-active]");
    if (activeBtn) {
      const r = await window.cloud.setJobTitleActive(
        activeBtn.dataset.titleActive, activeBtn.dataset.titleTo === "1");
      if (r.error) { toast("Couldn't update — " + r.error, "error"); return; }
      renderTitlesScreen(); return;
    }

    // Create a new title.
    if (e.target.closest("[data-title-create]")) {
      const form = e.target.closest("[data-title-add-form]");
      const name = form.querySelector("[data-title-new-name]").value.trim();
      const kind = form.querySelector("[data-title-kind]").value;
      const errEl = form.querySelector("[data-title-error]");
      const showErr = (m) => { errEl.textContent = m; errEl.hidden = false; };
      errEl.hidden = true;
      if (!name) { showErr("Title name can't be empty."); return; }
      const r = await window.cloud.createJobTitle({ name, kind });
      if (r.error) { showErr(r.error); return; }
      titleAddOpen = false; renderTitlesScreen(); return;
    }

    // Save an edit (name + kind).
    const saveBtn = e.target.closest("[data-title-save]");
    if (!saveBtn) return;
    const card = saveBtn.closest("[data-title-card]");
    const id = saveBtn.dataset.titleSave;
    const name = card.querySelector("[data-title-name]").value.trim();
    const kind = card.querySelector("[data-title-kind]").value;
    const errEl = card.querySelector("[data-title-error]");
    const showErr = (m) => { errEl.textContent = m; errEl.hidden = false; };
    errEl.hidden = true;
    if (!name) { showErr("Title name can't be empty."); return; }
    const r1 = await window.cloud.renameJobTitle(id, name);
    if (r1.error) { showErr(r1.error); return; }
    const r2 = await window.cloud.setJobTitleKind(id, kind);
    if (r2.error) { showErr(r2.error); return; }
    editingTitleId = null; renderTitlesScreen();
  });
```

- [ ] **Step 3: Parse-check the page in headless Chrome**

Run (from `route-checklist/`):
```
python -m http.server 8099 &
"%LOCALAPPDATA%\Google\Chrome\Application\chrome.exe" --headless --disable-gpu --dump-dom "http://localhost:8099/index.html" > /dev/null
kill %1
```
Expected: no `SyntaxError`.

- [ ] **Step 4: Commit**

```bash
git add route-checklist/index.html
git commit -m "feat(ui): Job titles screen — add / rename / change kind / retire"
```

---

### Task 7: Team screen — title dropdown replaces the free-text input

**Files:**
- Modify: `route-checklist/index.html` — `teamEditHTML` (3466-3487), `teamCardHTML` read-only row (3457), the save handler's title read (3271) + `saveProfileAsSupervisor` call (3289), and `renderTeamScreen` to fetch active titles (3406-3427).

**Interfaces:**
- Consumes: `window.cloud.listJobTitles({ activeOnly: true })` (Task 2); `listTeam` people now carry `jobTitleId`/`jobTitleName` (Task 4).
- Produces: assigning a title on the Team screen writes `job_title_id`.

- [ ] **Step 1: Fetch active titles in `renderTeamScreen` and pass them to the cards**

In `renderTeamScreen` (`route-checklist/index.html:3406-3427`), after the `const people = res.people || [];` line (3421), add a titles fetch, and pass the list into `teamCardHTML`. Replace lines 3421-3425:

```javascript
    const people = res.people || [];
    body.innerHTML =
      `<button type="button" class="home-btn" id="teamAddBtn">+ Add new team member</button>` +
      (teamAddOpen ? teamAddFormHTML() : "") +
      people.map(p => teamCardHTML(p)).join("");
```

with:

```javascript
    const people = res.people || [];
    const tRes = await window.cloud.listJobTitles({ activeOnly: true });
    if (currentScreenFromHash() !== "team") return;
    const activeTitles = tRes.titles || [];
    body.innerHTML =
      `<button type="button" class="home-btn" id="teamAddBtn">+ Add new team member</button>` +
      (teamAddOpen ? teamAddFormHTML() : "") +
      people.map(p => teamCardHTML(p, activeTitles)).join("");
```

- [ ] **Step 2: Update `teamCardHTML` signature + read-only title row**

Change the `teamCardHTML` signature (`route-checklist/index.html:3449`) from `function teamCardHTML(p) {` to `function teamCardHTML(p, activeTitles) {`, and update its call to `teamEditHTML` on the next line (3450) from `return teamEditHTML(p);` to `return teamEditHTML(p, activeTitles);`. Then change the title read-only row (line 3457) from:

```javascript
      <div class="muted-row">🏷️ ${escHtml(p.jobTitle || "—")}</div>
```

to:

```javascript
      <div class="muted-row">🏷️ ${escHtml(p.jobTitleName || "—")}</div>
```

- [ ] **Step 3: Replace the free-text title input in `teamEditHTML` with a dropdown**

Change the `teamEditHTML` signature (`route-checklist/index.html:3466`) from `function teamEditHTML(p) {` to `function teamEditHTML(p, activeTitles) {`. Then, inside it, replace the job-title label block (lines 3478-3479):

```javascript
      <label class="team-field"><span>Job title</span>
        <input type="text" data-team-title value="${escAttr(p.jobTitle || "")}"></label>
```

with:

```javascript
      <label class="team-field"><span>Job title</span>
        <select data-team-title-id>
          <option value=""${!p.jobTitleId ? " selected" : ""}>— none —</option>
          ${(activeTitles || []).map(t =>
            `<option value="${escAttr(t.id)}"${t.id === p.jobTitleId ? " selected" : ""}>${escHtml(t.name)}</option>`
          ).join("")}
          ${p.jobTitleId && !(activeTitles || []).some(t => t.id === p.jobTitleId)
            ? `<option value="${escAttr(p.jobTitleId)}" selected>${escHtml(p.jobTitleName)} (retired)</option>`
            : ""}
        </select></label>
```

(The trailing option keeps a person's *retired* title visible and selected so saving doesn't silently drop it.)

- [ ] **Step 4: Update the Team save handler to read + send `jobTitleId`**

In the Team save handler, change the title read (`route-checklist/index.html:3271`) from:

```javascript
    const jobTitle = card.querySelector("[data-team-title]").value.trim();
```

to:

```javascript
    const jobTitleId = card.querySelector("[data-team-title-id]").value || null;
```

Then change the save call (line 3289) from:

```javascript
    const s = await window.cloud.saveProfileAsSupervisor(id, { fullName, phone, jobTitle });
```

to:

```javascript
    const s = await window.cloud.saveProfileAsSupervisor(id, { fullName, phone, jobTitleId });
```

- [ ] **Step 5: Parse-check the page in headless Chrome**

Run (from `route-checklist/`):
```
python -m http.server 8099 &
"%LOCALAPPDATA%\Google\Chrome\Application\chrome.exe" --headless --disable-gpu --dump-dom "http://localhost:8099/index.html" > /dev/null
kill %1
```
Expected: no `SyntaxError`.

- [ ] **Step 6: Commit**

```bash
git add route-checklist/index.html
git commit -m "feat(ui): Team screen assigns job title via dropdown (writes job_title_id)"
```

---

### Task 8: My Profile — title becomes read-only

**Files:**
- Modify: `route-checklist/index.html` — `renderProfileScreen` title field (3108-3110), the save handler's title read + call (3783, 3795).

**Interfaces:**
- Consumes: `getMyProfile()` now returns `jobTitleName` (Task 3); `saveMyProfile({ fullName, phone })` no longer takes a title (Task 3).
- Produces: My Profile shows the title read-only; saving sends only name/phone.

- [ ] **Step 1: Make the profile title read-only**

In `renderProfileScreen` (`route-checklist/index.html`), replace the editable job-title field (lines 3108-3110):

```javascript
      <div class="profile-field">
        <label for="profileTitle">Job title</label>
        <input type="text" id="profileTitle" value="${escAttr(res.jobTitle || "")}" placeholder="e.g. Lead Tech">
      </div>
```

with:

```javascript
      <p class="profile-readonly">Job title: <b>${escHtml(res.jobTitleName || "—")}</b> <span class="muted-row">(set by a supervisor)</span></p>
```

- [ ] **Step 2: Update the profile save handler**

In the profile save handler (`route-checklist/index.html:3779-3807`), remove the now-missing title read. Delete this line (3783):

```javascript
    const titleInput = document.getElementById("profileTitle");
```

and change the save call (line 3795) from:

```javascript
    const res = await window.cloud.saveMyProfile({ fullName, phone: phoneInput.value.trim(), jobTitle: titleInput.value.trim() });
```

to:

```javascript
    const res = await window.cloud.saveMyProfile({ fullName, phone: phoneInput.value.trim() });
```

- [ ] **Step 3: Parse-check the page in headless Chrome**

Run (from `route-checklist/`):
```
python -m http.server 8099 &
"%LOCALAPPDATA%\Google\Chrome\Application\chrome.exe" --headless --disable-gpu --dump-dom "http://localhost:8099/index.html" > /dev/null
kill %1
```
Expected: no `SyntaxError`.

- [ ] **Step 4: Commit**

```bash
git add route-checklist/index.html
git commit -m "feat(ui): My Profile shows job title read-only (supervisor-assigned)"
```

---

### Task 9: Home screen — the `field`/`office` gate

**Files:**
- Modify: `route-checklist/index.html` — add `field-only` class to five home buttons/drawer (896-927), add the `body.is-office` CSS rule (~line 701 near the `admin-only` rule), add the office empty-state note element (in the home screen), clear `is-office` on sign-out and in preview (search `is-admin` toggles in `startPreview`/`exitPreview`/sign-out).

**Interfaces:**
- Consumes: `body.is-office` set by `loadRole` (Task 3).
- Produces: office people don't see field tooling; everyone keeps the always-on set; an office home shows a friendly note instead of looking empty.

- [ ] **Step 1: Add the `field-only` class to the field buttons and drawer**

In `route-checklist/index.html`, add the class `field-only` to each of these existing elements (keep every other attribute/class):
- `homeNewVisit` button (line 900): `class="home-btn field-only"`
- `homeContinue` button (line 902): `class="home-btn field-only"`
- `homeHistory` button (line 914): `class="home-btn field-only"`
- `homeLogs` button (line 916): `class="home-btn field-only"`
- `fieldTools` details (line 924): `class="admin-only field-only"`

(Note: `homeNotes`, `homeMyNotes`, `homeProfile`, `homeMyTickets`, `homeTickets`, `homeAlerts` get NO class — they are always-on.)

- [ ] **Step 2: Add the office empty-state note to the home screen**

In the home screen, immediately BEFORE the `homeNewVisit` button (line 900), insert:

```html
  <p class="home-office-note" id="officeToolsNote">Your tailored tools are coming. For now you have House notes, My notes, maintenance requests and your profile.</p>
```

- [ ] **Step 3: Add the CSS gate**

Near the existing supervisor-visibility rule (`route-checklist/index.html:701`, `body:not(.is-admin) .admin-only { display: none; }`), add:

```css
  /* Office titles (kind='office') don't do house visits or daily logs, so
     loadRole() sets body.is-office to hide the field-only buttons. The office
     note is the reverse: shown ONLY for office people. */
  body.is-office .field-only { display: none; }
  .home-office-note { display: none; }
  body.is-office .home-office-note {
    display: block; margin: 0 0 12px; padding: 12px 14px;
    background: var(--card); border: 1px solid var(--line); border-radius: 10px;
    color: var(--muted, #555); font-size: 0.95rem;
  }
```

- [ ] **Step 4: Clear `is-office` on sign-out**

The single sign-out path is the `else` branch of `onAuthStateChange` in `route-checklist/cloud.js:1175`. Change:

```javascript
    document.body.classList.remove("is-admin");
```

to:

```javascript
    document.body.classList.remove("is-admin", "is-office");
```

Also clear the cached kind two lines up: change `window.cloud.role = null; window.cloud.myId = null;` (line 1174) to `window.cloud.role = null; window.cloud.myId = null; window.cloud.jobTitleKind = "";`.

(This edit is in `cloud.js`, so commit it with `git add route-checklist/cloud.js` — see Step 7.)

- [ ] **Step 5: Force field view in supervisor preview**

In `startPreview` (`route-checklist/index.html:1354`), where it does `document.body.classList.remove("is-admin");`, add clearing office too so a previewing supervisor sees the tech's full field home: change it to `document.body.classList.remove("is-admin", "is-office");`. In `exitPreview` (line 1367), after the `is-admin` toggle, re-apply the real office state:

```javascript
    document.body.classList.toggle("is-office",
      !!window.cloud && window.cloud.jobTitleKind === "office");
```

- [ ] **Step 6: Parse-check the page in headless Chrome**

Run (from `route-checklist/`):
```
python -m http.server 8099 &
"%LOCALAPPDATA%\Google\Chrome\Application\chrome.exe" --headless --disable-gpu --dump-dom "http://localhost:8099/index.html" > /dev/null
kill %1
```
Expected: no `SyntaxError`; the DOM includes `id="officeToolsNote"` and `class="home-btn field-only"` on the four field buttons.

- [ ] **Step 7: Commit**

```bash
git add route-checklist/index.html route-checklist/cloud.js
git commit -m "feat(ui): office titles hide field-only home buttons; office empty-state note"
```

(Includes the `cloud.js` sign-out edit from Step 4.)

---

### Task 10: Bump SW cache, live end-to-end verification, ship

**Files:**
- Modify: `route-checklist/sw.js:7` (cache version).

**Interfaces:**
- Consumes: everything above.
- Produces: a deployed, hard-refreshable release.

- [ ] **Step 1: Bump the service-worker cache version**

In `route-checklist/sw.js:7`, change `const CACHE = "route-checklist-v29";` to `const CACHE = "route-checklist-v30";`.

- [ ] **Step 2: Commit and merge to main + push**

```bash
git add route-checklist/sw.js
git commit -m "chore(sw): bump cache to v30 for job-titles release"
git push origin main
```

(If work was done on a branch, merge to `main` first per the owner's standing rule, then push.)

- [ ] **Step 3: Verify the deploy is actually live**

Run: `curl -s "https://tweet-delta.github.io/mtx-sandbox/route-checklist/sw.js" | grep -o "route-checklist-v[0-9]*"`
Expected: `route-checklist-v30`. (Pages can take a minute; re-run until it matches before claiming "live.")

- [ ] **Step 4: Live end-to-end check (signed in, after hard-refresh)**

In Chrome at `https://tweet-delta.github.io/mtx-sandbox/route-checklist/index.html#home`, hard-refresh (Ctrl+Shift+R), then as a **supervisor**:
- 🏷️ Job titles button appears. Create "Interior Designer" (Office) and "Lead Tech" (Field). Rename one; retire one and confirm it shows a "retired" badge and drops out of the Team dropdown, but a person already holding it still shows it "(retired)".
- 👥 Team → ✎ Edit a **test** account → pick the office title from the dropdown → Save. Reload. Confirm it persisted:
  `supabase db query --linked "select p.full_name, jt.name, jt.kind from profiles p join job_titles jt on jt.id=p.job_title_id where jt.kind='office';"`
- Sign in as that office **test account** for real (not preview). Confirm the home screen HIDES New/Continue visit, My visit history, Daily logs, Field tools; SHOWS House notes, My notes, My profile, the maintenance-request buttons, and the "Your tailored tools are coming" note.
- My Profile shows the title read-only (no title input).
- As a **tech**: no 🏷️ Job titles button; deep-linking `#titles` → "Supervisors only."

- [ ] **Step 5: Verify RLS refuses a non-supervisor write**

Run (as the linked/service connection this checks the policy exists and shape; the true test is that a tech's browser insert fails — confirm by reasoning through `job_titles_insert` using `current_user_role()`):
```
supabase db query --linked "select policyname, cmd, qual, with_check from pg_policies where tablename='job_titles';"
```
Expected: `job_titles_insert`/`job_titles_update` carry `current_user_role() = 'supervisor'`; `job_titles_select` uses `auth.uid() is not null`.

- [ ] **Step 6: Update HANDOFF.md and START-HERE.md**

Add a short note to `route-checklist/HANDOFF.md` (current-state section) and `START-HERE.md` (owner's next-steps) describing the shipped Slice 1: managed job titles, dropdown assignment, office/field home-screen gate; and that Slice 2 (permissions) and Slice 3 (tailored office screens) plus dropping the retained `profiles.job_title` text column are the next follow-ups.

- [ ] **Step 7: Commit the docs**

```bash
git add route-checklist/HANDOFF.md START-HERE.md
git commit -m "docs: record managed job titles (Slice 1) shipped; note Slice 2/3 next"
git push origin main
```

- [ ] **Step 8: Remind the owner to hard-refresh**

Tell the owner: hard-refresh (Ctrl+Shift+R); on phones fully close and reopen the PWA, so the new service worker (v30) takes over and the Job titles screen + office home appear.

---

## Notes for the implementer

- **Retired-title edge case is handled on purpose:** the Team dropdown (Task 7 Step 3) keeps a person's assigned-but-retired title as a selected option so a supervisor editing an unrelated field (name/phone) doesn't accidentally clear it.
- **`is-admin` and `is-office` are independent** (Task 3 Step 5, Task 9). A supervisor who also holds an office title sees supervisor buttons AND has field tooling hidden — intended: kind governs field tooling, role governs supervisor tooling.
- **The old `profiles.job_title` text column is deliberately left in place.** Nothing reads or writes it after this slice. A separate future migration `0028_drop_job_title_text.sql` drops it once the owner confirms the migrated data — that is NOT part of this plan.
- **Maintenance-request screens already exist** (My tickets / Tickets / Notifications, migration 0025) and are treated as always-on, not field-only, matching the owner's "everyone gets maintenance requests" requirement.
