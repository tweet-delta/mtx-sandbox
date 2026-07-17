# Account Admin — Slice 2 design (Edge Function + job title)

**Date:** 2026-07-17
**Status:** Approved (owner), pending spec review before planning.
**Builds on:** `2026-07-17-supervisor-team-roster-design.md` (Slice 1, shipped).

## Context

Slice 1 shipped the supervisor Team roster (edit name / phone / role of
existing accounts) using only RLS — no server. Slice 2 adds the operations
that Slice 1 *couldn't* do from the browser, because they write to Supabase's
protected `auth.users` table and therefore need the **`service_role` secret
key**, which must never reach the client. The correct home for that key is an
**Edge Function** — the project's first server component.

The owner's chosen operations:

1. **Add new team member** — supervisor types name, email, temp password.
2. **Reset password** — supervisor sets a new temp password for a tech.
3. **Change email** — immediate, no confirmation link.
4. **Deactivate / reactivate** — disable an account when someone leaves;
   history is preserved (NOT delete).
5. **List with real emails** — the roster finally shows every account's real
   email (only the server can read `auth.users`).

Plus one non-server addition the owner asked for:

6. **Job title** — a free-text, informational label per person. This is just
   profile data (like name/phone), so it rides the existing RLS-backed roster
   editing and does NOT need the Edge Function.

All privileged actions are recorded in an **append-only audit log** —
appropriate for an app handling data about vulnerable adults.

## Goals

- A `service_role`-backed Edge Function `admin-users` that gates every request
  on "is the caller a supervisor?" and then performs create / reset-password /
  change-email / deactivate / list-with-emails via the Admin API.
- The secret key lives only as a Supabase function secret — never in the repo
  or browser.
- Every privileged action writes an `admin_audit` row.
- The Team roster's Slice-1 seams (Add member, Email, Password) become live;
  a Deactivate/Reactivate control per card; real emails shown.
- Job title editable in the roster.

## Non-goals (explicit)

- **Permanent account deletion** (owner chose deactivate; the schema's
  `on delete cascade` would destroy visit history — deliberately avoided).
- An audit-log **viewer UI** (the table is written now; reading it is
  `supabase db query` for the foreseeable future — no dashboard).
- Job title controlling **permissions** (it's a label only; the tech/
  supervisor role remains the sole permission axis).
- Email-change **confirmation links**, magic-link invites (owner chose
  immediate/temp-password flows).
- Rate limiting, bulk import, SSO — out of scope.

## Architecture

Client (`cloud.js`) → `supabase.functions.invoke("admin-users", …)` (the
supabase-js client auto-attaches the caller's JWT) → Edge Function verifies
the caller is a supervisor → uses a service-role admin client for the Admin
API call → writes an audit row → returns JSON.

### The security gate (the whole point)

Every request, before any privileged work:

1. Read the caller's JWT from the `Authorization` header (an RLS-scoped client
   built from that token, so `auth.getUser()` returns the caller).
2. Look up `profiles.role` for that user.
3. If not `supervisor` → respond `403` and do nothing.

Only after the gate passes does the function touch the service-role admin
client. The function **fails closed**: any missing/invalid token, any non-
supervisor, any unknown action → error, no side effect. CORS is restricted to
the app origin (`https://tweet-delta.github.io`), with the standard preflight
`OPTIONS` handler.

### Secret handling

- The secret (`SUPABASE_SERVICE_ROLE_KEY`, or a new `sb_secret_…`) is set with
  `supabase secrets set` and read inside the function via
  `Deno.env.get(...)`. It is NEVER committed and NEVER sent to the browser.
- `SUPABASE_URL` and the anon/publishable key are also read from the function
  env (Supabase injects `SUPABASE_URL` and `SUPABASE_ANON_KEY` automatically).

### Migrations

- **`0022_profile_job_title.sql`** — `alter table profiles add column job_title
  text not null default ''`. No RLS/grant change (profiles policies already
  cover the whole row).
- **`0023_admin_audit.sql`** — `public.admin_audit` table:
  `id, actor_id (uuid → profiles), action text, target_id uuid, target_email
  text, detail jsonb, created_at timestamptz default now()`. RLS: **select**
  supervisor-only; **no** client insert/update/delete grant at all — only the
  Edge Function's service-role client writes it (bypasses RLS), so the log
  can't be forged or tampered with from the browser. Append-only by
  construction (no update/delete path exposed).
- **`0024_profile_active.sql`** — `alter table profiles add column active
  boolean not null default true`. Deactivation flips this false AND bans the
  auth user (see below). `listAllProfiles`/route dropdowns filter to active;
  the Team roster shows inactive rows muted with a Reactivate action.

### The Edge Function — `supabase/functions/admin-users/index.ts`

One function, an `action` field in the JSON body selects the operation:

- **`list`** → `admin.auth.admin.listUsers()` joined with profiles → returns
  `[{id, fullName, phone, role, jobTitle, email, active, isMe}]`. This
  replaces the client-side `listAllProfiles` email gap.
- **`create`** → `admin.auth.admin.createUser({ email, password,
  email_confirm: true })`; the existing `handle_new_user` trigger creates the
  `tech` profile; the function then sets `full_name`. Audit: `create`.
- **`reset_password`** → `admin.auth.admin.updateUserById(id, { password })`.
  Audit: `reset_password` (NEVER logs the password itself).
- **`change_email`** → `updateUserById(id, { email, email_confirm: true })`
  and mirror onto any profile email cache if one exists. Audit: `change_email`
  (logs old→new address).
- **`set_active`** → sets `profiles.active` and bans/unbans the auth user
  (`updateUserById(id, { ban_duration: 'none' | '876000h' })` — a ~100-year
  ban = effectively disabled, reversible). Audit: `deactivate`/`reactivate`.

Every branch: gate → act → audit → return `{ ok: true, … }` or
`{ error, status }`. A supervisor may not deactivate or demote **themselves**
via the function (mirrors Slice 1's self-protect; the `guard_last_supervisor`
trigger from 0021 still independently protects role demotions).

### Client — `cloud.js`

A thin helper:

```
async function callAdmin(action, payload) {
  const { data, error } = await supabase.functions.invoke("admin-users",
    { body: { action, ...payload } });
  return error ? { error: error.message } : data;
}
```

Plus: `createTeamMember({fullName,email,password})`,
`resetTechPassword(id,password)`, `changeTechEmail(id,email)`,
`setTechActive(id,active)`, and `listTeam()` (calls the function's `list`,
returns rows WITH real emails + active + jobTitle). `saveProfileAsSupervisor`
gains `jobTitle`. Slice-1's `listAllProfiles` is superseded by `listTeam` for
the roster (kept if still used elsewhere, else removed).

### UI — `index.html` Team screen (activating Slice-1 seams)

- **"+ Add new team member"** (was disabled) → opens an inline create form:
  Full name, Email, Temp password (with a show/generate helper), Create.
  On success the roster re-renders with the new person.
- Each card's **Email** row → real address + "Change email" action (inline
  field + confirm, since email is the login identity).
- Each card's **Password** row → "Reset password" action (inline temp-password
  field; on save, shows the supervisor the value to hand over, then clears).
- **Deactivate / Reactivate** per card (confirm; never on your own card).
  Inactive cards render muted with a Reactivate button and are visually
  separated.
- **Job title** joins the Slice-1 inline edit form (name / phone / job title /
  role).
- Techs still get "Supervisors only." (renderer gate); the Edge Function's
  server-side gate is the real enforcement.

## Data flow (add member, as the representative case)

1. Supervisor fills the create form → `createTeamMember(...)`.
2. `cloud.js` → `functions.invoke("admin-users", { action:"create", … })`
   with the supervisor's JWT auto-attached.
3. Function: gate (is caller supervisor?) → `admin.createUser({email,password,
   email_confirm:true})` → trigger makes the `tech` profile → function sets
   `full_name` → writes `admin_audit` row → returns `{ ok, id }`.
4. `cloud.js` re-fetches `listTeam()` → roster re-renders with the new person.

## Error handling

- No/invalid JWT, non-supervisor → `403`, surfaced as "Supervisors only." /
  the function's message; no side effect.
- Duplicate email on create → Admin API error surfaced inline
  ("A user with this email already exists.").
- Weak password (< 8, the project min) → validated client-side before the call
  AND surfaced if the Admin API still rejects.
- Function unreachable / not yet deployed → the UI shows a clear "Account admin
  isn't available yet" message rather than a raw error (graceful, like the
  Slice-1 degraded paths).
- Self-target guardrails (can't deactivate/demote yourself) enforced in the
  function, not just the UI.

## Testing / verification

No automated harness. Per piece:

1. **Migrations** — `supabase db push`; verify columns/table + RLS via
   `supabase db query --linked`.
2. **Edge Function** — deployed with `supabase functions deploy admin-users`;
   secret set with `supabase secrets set`. Because local `supabase functions
   serve` needs Docker (not running on this box), verification is (a) a
   TypeScript/deno parse/lint check where possible, and (b) the owner's live
   drive against the deployed function.
3. **Live drive (owner)** — after hard-refresh:
   - Add a member (name/email/temp pw) → they appear; sign in AS them with the
     temp password → works; they land as a tech.
   - Roster shows real emails for everyone.
   - Reset a tech's password → sign in with the new one.
   - Change a tech's email → sign in with the new email.
   - Deactivate a tech → they vanish from route dropdowns and can't log in;
     Reactivate → restored.
   - Job title edits save and persist.
   - As a tech: no Team button; direct function calls without a supervisor JWT
     are rejected (the gate).
   - `supabase db query --linked "select * from admin_audit order by created_at
     desc limit 5"` → the actions are logged.

SW cache bumped (`v25` → next). Each sub-slice merges to `main` + pushes the
same session per the owner's standing rule; the owner is told when each live
piece is deployed so they can look.

## Sequencing (each sub-slice independently shippable)

- **2a — Job title.** Migration 0022 + roster field + cloud.js. No server.
  Ships first (fast, visible, zero deploy risk).
- **2b — Edge Function foundation.** Migrations 0023 (audit) + 0024 (active) +
  the function with the supervisor gate, `list`, and `create` + audit logging;
  activate "+ Add member" and real-email display. **The milestone live-drive:
  add a member end-to-end.**
- **2c — reset_password + change_email.** More calls through the proven
  function; activate the Email/Password card actions.
- **2d — deactivate / reactivate.** The destructive op, done last on
  battle-tested infrastructure; muted inactive rows + Reactivate.

## Deployment note (owner gate)

Deploying the Edge Function and setting its secret hit the live Supabase
project and are bigger "live" actions than a migration. As with migration
0021, everything is built and checked first, then the owner explicitly okays
the `functions deploy` / `secrets set` step before it runs. The secret key is
handled only via `supabase secrets set` (typed by the owner or pasted into the
CLI) — it never appears in a file, a commit, or the browser.
