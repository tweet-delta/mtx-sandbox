# Account Admin — Slice 2 Implementation Plan

> **For agentic workers:** REQUIRED SUB-SKILL: Use superpowers:subagent-driven-development (recommended) or superpowers:executing-plans to implement this plan task-by-task. Steps use checkbox (`- [ ]`) syntax for tracking.

**Goal:** A `service_role`-backed Edge Function (`admin-users`) that lets a
verified supervisor create accounts, reset passwords, change emails, and
deactivate/reactivate techs — with an append-only audit log — plus a
non-server job-title field on profiles.

**Architecture:** Client (`cloud.js`) invokes the Edge Function with the
supervisor's JWT; the function verifies the caller is a supervisor, then uses
a service-role admin client for Admin-API calls, writes an `admin_audit` row,
and returns JSON. The secret key lives only as a Supabase function secret.
Job title is plain profile data edited through the existing RLS roster path.

**Tech Stack:** Deno + TypeScript Edge Function, `@supabase/supabase-js` v2,
Supabase Admin API, Postgres + RLS, Supabase CLI (migrations + functions
deploy + secrets). Vanilla JS front-end (no build step).

## Global Constraints

- **The `service_role`/secret key NEVER appears in the repo or the browser.**
  It is set with `supabase secrets set` and read via `Deno.env.get` inside the
  function only. No secret in any committed file, ever.
- **This repo is PUBLIC.** Publishable/anon key is fine in the client; nothing
  else.
- **Migrations via CLI:** `supabase db push --workdir "c:\Big Dogs Apps\MTX
  Checklist V1"`. Never hand-paste. Never run destructive remote commands.
- **The Edge Function fails closed:** no valid supervisor JWT → 403, no side
  effect. CORS restricted to `https://tweet-delta.github.io`.
- **Deploy/secret steps hit the live project** — get the owner's explicit okay
  before `functions deploy` and `secrets set` (as with migration 0021).
- **Deactivate, never delete** (schema cascades would destroy visit history).
- **Never log a password** in the audit table.
- **Min password length 8** (project setting) — validate client-side too.
- **No automated test harness** — verify by parse-check (headless Chrome for
  the client; `deno check`/lint for the function where available) + owner live
  drive against the deployed function.
- **Ship each sub-slice the same session** it's finished: merge to `main` +
  push (live deploys from `main`), bump SW cache, tell the owner it's live +
  hard-refresh (Ctrl+Shift+R; reopen PWA on phones).
- **Current SW cache: `route-checklist-v25`** — bump per sub-slice that
  changes client files.
- Work on branch `feature/account-admin` (already created off `main`). Don't
  touch `main` until the owner approves each merge.

**Headless-Chrome parse check** (client changes): serve `python -m http.server
8000` from repo root, then load the changed screen via an iframe harness in
Chrome at `%LOCALAPPDATA%\Google\Chrome\Application\chrome.exe`
(`--headless=new --dump-dom`), asserting no `SyntaxError` and the expected DOM.
(Same technique proven in the Slice-1 build.)

---

## SUB-SLICE 2a — Job title (no server)

### Task 2a.1: Migration 0022 — job_title column

**Files:**
- Create: `supabase/migrations/0022_profile_job_title.sql`

- [ ] **Step 1: Write the migration**

```sql
-- ============================================================================
-- 0022_profile_job_title.sql — a free-text, informational job title per person
-- (e.g. "Lead Tech"). Just profile data — no permissions effect, no server.
-- HOW TO RUN: supabase db push --workdir "c:\Big Dogs Apps\MTX Checklist V1"
-- ============================================================================
alter table public.profiles
  add column if not exists job_title text not null default '';
-- No RLS/grant change: profiles_select/profiles_update (0001) cover the row.
```

- [ ] **Step 2: Push + verify**

Run: `supabase db push --workdir "c:\Big Dogs Apps\MTX Checklist V1"`
Then: `supabase db query --linked "select column_name from information_schema.columns where table_name='profiles' and column_name='job_title';"`
Expected: one row, `job_title`.

- [ ] **Step 3: Commit**

```bash
git add supabase/migrations/0022_profile_job_title.sql
git commit -m "feat(db): 0022 add job_title to profiles"
```

### Task 2a.2: cloud.js — job_title in profile reads/writes

**Files:**
- Modify: `route-checklist/cloud.js` — `getMyProfile`, `saveMyProfile`,
  `listAllProfiles`, `saveProfileAsSupervisor`

**Interfaces:**
- Produces: `listAllProfiles` people rows gain `jobTitle`;
  `saveProfileAsSupervisor(id, { fullName, phone, jobTitle })` and
  `saveMyProfile({ fullName, phone, jobTitle })` accept it;
  `getMyProfile()` returns `jobTitle`.

- [ ] **Step 1: Add `job_title` to the selects and updates**

In `listAllProfiles`, change the primary select to
`"id, full_name, phone, job_title, role"` and add `jobTitle: p.job_title || ""`
to the mapped row (leave the missing-column fallback select as name/role only).

In `saveProfileAsSupervisor(id, { fullName, phone, jobTitle })`, change the
update to `{ full_name: fullName, phone, job_title: jobTitle }` (fallback stays
name-only).

In `getMyProfile`, add `job_title` to the select and `jobTitle: data?.job_title
|| ""` to the return.

In `saveMyProfile({ fullName, phone, jobTitle })`, add `job_title: jobTitle` to
the update.

- [ ] **Step 2: Parse check** — serve + iframe-load `index.html`, assert
`typeof window.cloud.listAllProfiles === "function"` and no `SyntaxError`.

- [ ] **Step 3: Commit**

```bash
git add route-checklist/cloud.js
git commit -m "feat(cloud): job_title in profile read/write paths"
```

### Task 2a.3: index.html — job title in roster + My Profile

**Files:**
- Modify: `route-checklist/index.html` — `teamCardHTML`, `teamEditHTML`, the
  team save handler, the My Profile screen render/save, `sw.js`

- [ ] **Step 1: Show job title on the card**

In `teamCardHTML`, add under the phone row:
```javascript
      <div class="muted-row">🏷️ ${escHtml(p.jobTitle || "—")}</div>
```

- [ ] **Step 2: Add the field to the editor**

In `teamEditHTML`, after the Phone field:
```javascript
      <label class="team-field"><span>Job title</span>
        <input type="text" data-team-title value="${escAttr(p.jobTitle || "")}"></label>
```

- [ ] **Step 3: Read + save it in the team handler**

In the `#teamBody` save branch, read
`const jobTitle = card.querySelector("[data-team-title]").value.trim();`
and pass it: `saveProfileAsSupervisor(id, { fullName, phone, jobTitle })`.

- [ ] **Step 4: Add job title to My Profile screen** (mirror the phone field —
find `renderProfileScreen` and its save; add a Job title input, include
`jobTitle` in the `getMyProfile` prefill and the `saveMyProfile` payload).

- [ ] **Step 5: Bump SW cache** — `route-checklist/sw.js`: `v25` → `v26`.

- [ ] **Step 6: Parse check** — iframe-load `#team` with a stubbed supervisor
`listAllProfiles` returning a `jobTitle`; assert the card shows it and the
editor input exists. No `SyntaxError`.

- [ ] **Step 7: Commit**

```bash
git add route-checklist/index.html route-checklist/sw.js
git commit -m "feat: job title in Team roster + My Profile; SW v26"
```

### Task 2a.4: Ship 2a

- [ ] **Step 1:** Owner note: 2a is client + a benign column — merge to `main`,
push, tell the owner it's live + hard-refresh. (No deploy/secret step; low
risk.) Verify live: edit a job title, reload, persists.

```bash
git switch main && git merge --ff-only feature/account-admin && git push origin main
git switch feature/account-admin
```

---

## SUB-SLICE 2b — Edge Function foundation + list + create + audit

### Task 2b.1: Migration 0023 — admin_audit

**Files:**
- Create: `supabase/migrations/0023_admin_audit.sql`

- [ ] **Step 1: Write the migration**

```sql
-- ============================================================================
-- 0023_admin_audit.sql — append-only log of privileged account-admin actions.
-- Written ONLY by the admin-users Edge Function's service-role client (which
-- bypasses RLS). No client insert/update/delete grant, so it can't be forged
-- or tampered with from the browser. Supervisors may read it.
-- HOW TO RUN: supabase db push --workdir "c:\Big Dogs Apps\MTX Checklist V1"
-- ============================================================================
create table if not exists public.admin_audit (
  id           uuid primary key default gen_random_uuid(),
  actor_id     uuid references public.profiles (id),
  action       text not null,
  target_id    uuid,
  target_email text,
  detail       jsonb not null default '{}'::jsonb,
  created_at   timestamptz not null default now()
);
create index if not exists admin_audit_created_idx on public.admin_audit (created_at desc);

alter table public.admin_audit enable row level security;

drop policy if exists admin_audit_select on public.admin_audit;
create policy admin_audit_select on public.admin_audit
  for select to authenticated
  using (public.current_user_role() = 'supervisor');

-- Only SELECT is granted to authenticated. No insert/update/delete grant —
-- the Edge Function writes via the service-role key, which bypasses grants+RLS.
grant select on public.admin_audit to authenticated;
```

- [ ] **Step 2: Push + verify** — `supabase db push`; then
`supabase db query --linked "select tablename from pg_tables where tablename='admin_audit';"` → one row.

- [ ] **Step 3: Commit**

```bash
git add supabase/migrations/0023_admin_audit.sql
git commit -m "feat(db): 0023 admin_audit append-only log (supervisor-read)"
```

### Task 2b.2: Migration 0024 — profiles.active

**Files:**
- Create: `supabase/migrations/0024_profile_active.sql`

- [ ] **Step 1: Write the migration**

```sql
-- ============================================================================
-- 0024_profile_active.sql — soft on/off for an account. Deactivation flips
-- this false AND bans the auth user (done in the Edge Function). Kept simple:
-- no RLS change (supervisors already read all profiles; the app filters).
-- HOW TO RUN: supabase db push --workdir "c:\Big Dogs Apps\MTX Checklist V1"
-- ============================================================================
alter table public.profiles
  add column if not exists active boolean not null default true;
```

- [ ] **Step 2: Push + verify** column exists.

- [ ] **Step 3: Commit**

```bash
git add supabase/migrations/0024_profile_active.sql
git commit -m "feat(db): 0024 add profiles.active (soft deactivate)"
```

### Task 2b.3: The Edge Function — gate + list + create + audit

**Files:**
- Create: `supabase/functions/admin-users/index.ts`
- Create: `supabase/functions/admin-users/deno.json` (optional import map)

**Interfaces:**
- Produces: an HTTP function accepting `POST {action, ...}` with the caller's
  JWT in `Authorization`. Actions this task: `list`, `create`. Returns JSON.

- [ ] **Step 1: Write the function**

```typescript
// supabase/functions/admin-users/index.ts
// First server component. Verifies the caller is a supervisor, then performs
// privileged auth.users operations with the service-role key. Fails closed.
import { createClient } from "https://esm.sh/@supabase/supabase-js@2";

const APP_ORIGIN = "https://tweet-delta.github.io";
const cors = {
  "Access-Control-Allow-Origin": APP_ORIGIN,
  "Access-Control-Allow-Headers": "authorization, content-type",
  "Access-Control-Allow-Methods": "POST, OPTIONS",
};
const json = (body: unknown, status = 200) =>
  new Response(JSON.stringify(body), {
    status, headers: { ...cors, "Content-Type": "application/json" },
  });

Deno.serve(async (req) => {
  if (req.method === "OPTIONS") return new Response("ok", { headers: cors });
  if (req.method !== "POST") return json({ error: "Method not allowed" }, 405);

  const SUPABASE_URL = Deno.env.get("SUPABASE_URL")!;
  const ANON = Deno.env.get("SUPABASE_ANON_KEY")!;
  const SECRET = Deno.env.get("SUPABASE_SERVICE_ROLE_KEY")!;

  // 1) Identify the caller from their JWT (RLS-scoped client).
  const authHeader = req.headers.get("Authorization") ?? "";
  const asCaller = createClient(SUPABASE_URL, ANON, {
    global: { headers: { Authorization: authHeader } },
  });
  const { data: { user }, error: uErr } = await asCaller.auth.getUser();
  if (uErr || !user) return json({ error: "Not signed in." }, 401);

  // 2) Gate: caller must be a supervisor.
  const { data: prof } = await asCaller
    .from("profiles").select("role").eq("id", user.id).maybeSingle();
  if (prof?.role !== "supervisor") return json({ error: "Supervisors only." }, 403);

  // 3) Service-role client for the privileged work (bypasses RLS).
  const admin = createClient(SUPABASE_URL, SECRET);

  const audit = (action: string, target_id: string | null,
                 target_email: string | null, detail: Record<string, unknown> = {}) =>
    admin.from("admin_audit").insert({
      actor_id: user.id, action, target_id, target_email, detail,
    });

  let body: any;
  try { body = await req.json(); } catch { return json({ error: "Bad JSON" }, 400); }
  const action = body?.action;

  try {
    if (action === "list") {
      const { data: list, error } = await admin.auth.admin.listUsers();
      if (error) return json({ error: error.message }, 500);
      const { data: profs } = await admin
        .from("profiles").select("id, full_name, phone, job_title, role, active");
      const byId = new Map((profs ?? []).map((p: any) => [p.id, p]));
      const people = list.users.map((u) => {
        const p: any = byId.get(u.id) ?? {};
        return {
          id: u.id, email: u.email ?? "",
          fullName: p.full_name ?? "", phone: p.phone ?? "",
          jobTitle: p.job_title ?? "", role: p.role ?? "tech",
          active: p.active ?? true, isMe: u.id === user.id,
        };
      }).sort((a, b) => (a.fullName || "").localeCompare(b.fullName || ""));
      return json({ people, myId: user.id });
    }

    if (action === "create") {
      const email = String(body.email ?? "").trim();
      const password = String(body.password ?? "");
      const fullName = String(body.fullName ?? "").trim();
      if (!email || password.length < 8)
        return json({ error: "Email and an 8+ char password are required." }, 400);
      const { data, error } = await admin.auth.admin.createUser({
        email, password, email_confirm: true,
      });
      if (error) return json({ error: error.message }, 400);
      const newId = data.user!.id;
      // handle_new_user trigger already made a tech profile; set the name.
      await admin.from("profiles").update({ full_name: fullName }).eq("id", newId);
      await audit("create", newId, email, { fullName });
      return json({ ok: true, id: newId });
    }

    return json({ error: "Unknown action" }, 400);
  } catch (e) {
    return json({ error: String((e as Error).message ?? e) }, 500);
  }
});
```

- [ ] **Step 2: Local parse/type check (best effort)**

If Deno is available: `deno check supabase/functions/admin-users/index.ts`.
If not (likely on this box), rely on careful review + the deploy step's build
output. Do NOT block on Docker-based `supabase functions serve`.

- [ ] **Step 3: Commit (function code only; NO secret)**

```bash
git add supabase/functions/admin-users/index.ts
git commit -m "feat(fn): admin-users Edge Function — gate + list + create + audit"
```

### Task 2b.4: Deploy the function + set the secret (OWNER-GATED)

**Files:** none (CLI actions against the live project)

- [ ] **Step 1: STOP — get owner okay.** Deploying + secrets hit the live
project. Confirm before running.

- [ ] **Step 2: Set the service-role secret** (value from the Supabase
dashboard → Project Settings → API → service_role key; typed/pasted by the
owner, never committed):

```bash
supabase secrets set SUPABASE_SERVICE_ROLE_KEY=<paste> --workdir "c:\Big Dogs Apps\MTX Checklist V1"
```

- [ ] **Step 3: Deploy**

```bash
supabase functions deploy admin-users --workdir "c:\Big Dogs Apps\MTX Checklist V1"
```
Expected: deploy succeeds; function URL printed.

- [ ] **Step 4: Smoke test the gate** — with the owner signed in as a
supervisor in the app console:
`await window.supabase.functions.invoke("admin-users", { body:{action:"list"} })`
→ returns `{ people:[…] }` with real emails. Signed in as a tech → `403`
"Supervisors only.".

### Task 2b.5: cloud.js — callAdmin + listTeam + createTeamMember

**Files:**
- Modify: `route-checklist/cloud.js`

**Interfaces:**
- Produces on `window.cloud`: `listTeam()` (function `list`, rows WITH email/
  active/jobTitle), `createTeamMember({fullName,email,password})`.

- [ ] **Step 1: Add the helper + functions**

```javascript
// ---- Account admin (Edge Function; secret key lives server-side only) ----
async function callAdmin(action, payload = {}) {
  const { data, error } = await supabase.functions
    .invoke("admin-users", { body: { action, ...payload } });
  if (error) {
    // Function not deployed yet / network → a friendly, catchable message.
    return { error: error.message || "Account admin isn't available yet." };
  }
  return data;
}
async function listTeam() { return callAdmin("list"); }
async function createTeamMember({ fullName, email, password }) {
  return callAdmin("create", { fullName, email, password });
}
```
Export `listTeam, createTeamMember` on `window.cloud`.

- [ ] **Step 2: Parse check** (iframe-load, functions defined, no SyntaxError).

- [ ] **Step 3: Commit**

```bash
git add route-checklist/cloud.js
git commit -m "feat(cloud): callAdmin wrapper + listTeam + createTeamMember"
```

### Task 2b.6: index.html — real emails + Add member form

**Files:**
- Modify: `route-checklist/index.html` (`renderTeamScreen` to use `listTeam`;
  activate the `+ Add new team member` button + inline create form), `sw.js`

- [ ] **Step 1: Switch the roster to `listTeam`**

In `renderTeamScreen`, replace `window.cloud.listAllProfiles()` with
`window.cloud.listTeam()`. The row shape already matches (adds `email`,
`active`). Show `p.email` on EVERY card now (drop the "coming soon" email
placeholder). If `listTeam` returns `{ error }`, show it (covers "not deployed
yet" gracefully).

- [ ] **Step 2: Activate + wire the Add form**

Remove `disabled`/`aria-disabled` from `teamAddBtn`. Add an inline create form
(toggled by the button): Full name, Email, Temp password (min 8, with a
"generate" helper that fills a random 12-char string), Create / Cancel. On
Create → `createTeamMember(...)`; on `{error}` show inline; on success clear
the form and `renderTeamScreen()`.

- [ ] **Step 3: Bump SW** `v26` → `v27`.

- [ ] **Step 4: Parse check** — stub `window.cloud.listTeam` returning two
people WITH emails + one `active:false`; assert emails render and the Add form
opens. No SyntaxError.

- [ ] **Step 5: Commit**

```bash
git add route-checklist/index.html route-checklist/sw.js
git commit -m "feat: Team roster real emails + Add-member form; SW v27"
```

### Task 2b.7: Ship 2b + milestone live-drive

- [ ] Merge to `main`, push, tell the owner it's LIVE. Owner live-drive:
add a member (name/email/temp pw) → appears; sign in AS them with the temp
password → works, lands as tech; roster shows real emails; tech gets 403 from
the function; `select * from admin_audit order by created_at desc limit 5`
shows the `create` row.

---

## SUB-SLICE 2c — reset password + change email

### Task 2c.1: Function — add reset_password + change_email

**Files:**
- Modify: `supabase/functions/admin-users/index.ts`

- [ ] **Step 1: Add two action branches** (before the `Unknown action` return):

```typescript
    if (action === "reset_password") {
      const id = String(body.id ?? "");
      const password = String(body.password ?? "");
      if (!id || password.length < 8)
        return json({ error: "A target and an 8+ char password are required." }, 400);
      const { error } = await admin.auth.admin.updateUserById(id, { password });
      if (error) return json({ error: error.message }, 400);
      await audit("reset_password", id, null, {});   // never log the password
      return json({ ok: true });
    }

    if (action === "change_email") {
      const id = String(body.id ?? "");
      const email = String(body.email ?? "").trim();
      if (!id || !email) return json({ error: "A target and email are required." }, 400);
      const { data: before } = await admin.auth.admin.getUserById(id);
      const { error } = await admin.auth.admin
        .updateUserById(id, { email, email_confirm: true });
      if (error) return json({ error: error.message }, 400);
      await audit("change_email", id, email, { from: before?.user?.email ?? null });
      return json({ ok: true });
    }
```

- [ ] **Step 2: Redeploy (owner-gated)** — `supabase functions deploy admin-users`.
- [ ] **Step 3: Commit**

```bash
git add supabase/functions/admin-users/index.ts
git commit -m "feat(fn): admin-users reset_password + change_email"
```

### Task 2c.2: cloud.js + index.html — wire the card actions

**Files:**
- Modify: `route-checklist/cloud.js`, `route-checklist/index.html`, `sw.js`

- [ ] **Step 1:** cloud.js: `resetTechPassword(id, password)` →
`callAdmin("reset_password", {id, password})`; `changeTechEmail(id, email)` →
`callAdmin("change_email", {id, email})`. Export both.

- [ ] **Step 2:** index.html: the Email row gets a "Change email" action
(inline field + confirm); the Password row gets "Reset password" (inline temp
field; on success show the value to hand over, then clear on next render).
Both re-render the roster on success; errors show inline. Never on your own
card's password/email if you'd rather use My Profile — allowed but confirm.

- [ ] **Step 3:** Bump SW `v27` → `v28`. Parse check (stub the two cloud fns).

- [ ] **Step 4: Commit**

```bash
git add route-checklist/cloud.js route-checklist/index.html route-checklist/sw.js
git commit -m "feat: reset password + change email card actions; SW v28"
```

### Task 2c.3: Ship 2c

- [ ] Merge, push, tell owner LIVE. Live-drive: reset a tech's password → sign
in with the new one; change a tech's email → sign in with the new email; both
appear in `admin_audit`.

---

## SUB-SLICE 2d — deactivate / reactivate

### Task 2d.1: Function — add set_active

**Files:**
- Modify: `supabase/functions/admin-users/index.ts`

- [ ] **Step 1: Add the branch** (with self-protection):

```typescript
    if (action === "set_active") {
      const id = String(body.id ?? "");
      const active = !!body.active;
      if (!id) return json({ error: "A target is required." }, 400);
      if (id === user.id) return json({ error: "You can't deactivate yourself." }, 400);
      // Ban ~100 years to disable login; 'none' to restore. Reversible.
      const ban_duration = active ? "none" : "876000h";
      const { error: bErr } = await admin.auth.admin.updateUserById(id, { ban_duration });
      if (bErr) return json({ error: bErr.message }, 400);
      const { error: pErr } = await admin.from("profiles").update({ active }).eq("id", id);
      if (pErr) return json({ error: pErr.message }, 500);
      await audit(active ? "reactivate" : "deactivate", id, null, {});
      return json({ ok: true });
    }
```

- [ ] **Step 2: Redeploy (owner-gated).**
- [ ] **Step 3: Commit**

```bash
git add supabase/functions/admin-users/index.ts
git commit -m "feat(fn): admin-users set_active (deactivate/reactivate, self-protected)"
```

### Task 2d.2: cloud.js + index.html — deactivate UI + filter dropdowns

**Files:**
- Modify: `route-checklist/cloud.js`, `route-checklist/index.html`, `sw.js`

- [ ] **Step 1:** cloud.js: `setTechActive(id, active)` →
`callAdmin("set_active", {id, active})`. Export it. Also filter inactive people
out of the assignable dropdowns: `listTechs()` and `listLogTechs()` gain
`.eq("active", true)` (fallback if the column's missing).

- [ ] **Step 2:** index.html: each card (not your own) gets a
Deactivate/Reactivate button with `confirm()`. Inactive cards render muted,
grouped after active ones, with a Reactivate button. Re-render on success.

- [ ] **Step 3:** Bump SW `v28` → `v29`. Parse check (stub `setTechActive` +
an inactive person in the roster).

- [ ] **Step 4: Commit**

```bash
git add route-checklist/cloud.js route-checklist/index.html route-checklist/sw.js
git commit -m "feat: deactivate/reactivate UI + hide inactive from dropdowns; SW v29"
```

### Task 2d.3: Ship 2d + HANDOFF + close Slice 2

- [ ] Merge, push, tell owner LIVE. Live-drive: deactivate a tech → gone from
route/log dropdowns, can't log in; reactivate → restored; both in
`admin_audit`. Update `HANDOFF.md` with the full Slice-2 state and the
function's operational notes (secret name, redeploy command, `on delete
cascade` warning still relevant). Delete the branch once confirmed.

---

## Self-Review

**Spec coverage:** Add member → 2b.3/2b.6. Reset password → 2c. Change email →
2c. Deactivate/reactivate → 2d. List with real emails → 2b.3/2b.6. Job title →
2a. Audit log → 0023 + `audit()` in every function branch. Supervisor gate →
2b.3. Secret handling → 2b.4 (never committed). ✓

**Placeholder scan:** No TBD/TODO in shipped code. Every function branch and
migration is complete. ✓

**Type consistency:** `callAdmin(action, payload)` used by all client wrappers;
function returns `{people,myId}` / `{ok,...}` / `{error,...}` consistently; the
roster row shape (`id,email,fullName,phone,jobTitle,role,active,isMe`) matches
between the function's `list`, `listTeam`, and `renderTeamScreen`. ✓

**Note for the implementer:** `renderTeamScreen`, `teamCardHTML`,
`teamEditHTML`, and the `#teamBody` handler already exist from Slice 1 — extend
them, don't recreate. Grep how the Slice-1 card renders before editing. The
`admin.auth.admin.*` method names and `ban_duration` are Admin-API specifics —
confirm against current Supabase docs (context7 `/supabase/supabase`) at build
time, as the API evolves.
