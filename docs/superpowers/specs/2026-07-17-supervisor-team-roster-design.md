# Supervisor Team Roster — Slice 1 design (name / phone / role)

**Date:** 2026-07-17
**Status:** Approved (owner), pending spec review before planning.

## Context

The owner asked for supervisors to have "complete control" over tech
accounts from inside the app: name, email, password, role — and to **add new
team members** straight from the app.

Working through it in brainstorming surfaced a hard boundary that splits the
request cleanly in two:

- **Name, phone, role** live in `public.profiles` and are governed by
  Row-Level Security (RLS). The `profiles_update` policy (migration 0001)
  already permits a supervisor to update **any** profile row, and the
  `guard_profile_role` trigger already lets a supervisor change roles while
  blocking a tech from self-promoting. So these need **no secret key and no
  server** — only a UI.
- **Email, password, and creating a brand-new account** live in Supabase's
  protected `auth.users` table. Changing another user's login — or minting a
  new one — requires the **`service_role` (secret) key**, which per this
  project's rules (CLAUDE.md) must **never** touch the browser or this public
  repo. The only correct home for it is an **Edge Function** (server-side).
  There is no `supabase/functions/` directory yet.

This spec covers **Slice 1 only: the Team roster screen (name / phone /
role)** — the half that needs no new server infrastructure and is therefore
shippable on its own. Email, password, and "Add new team member" are
**Slice 2** (a separate cycle built on the project's first Edge Function) and
are explicitly out of scope here, appearing only as read-only "coming soon"
seams so the screen already looks complete.

This follows the owner's standing rule: **build the smallest complete slice
first, then widen.**

## Goals (Slice 1)

1. A supervisor-only **👥 Team** screen listing every account.
2. A supervisor can edit any person's **full name** and **phone**.
3. A supervisor can change any person's **role** (tech ↔ supervisor), with
   real safety: a confirm dialog, no self-demotion, and a database guarantee
   that the **last remaining supervisor can never be demoted**.
4. Email + password + "Add member" render as clearly-labelled read-only
   placeholders ("Managed in account admin — coming soon"), so the screen is
   visibly whole and Slice 2 only has to activate them.

## Non-goals (Slice 1 — explicit)

- Changing a tech's **email** (Slice 2 / Edge Function).
- Resetting a tech's **password** (Slice 2 / Edge Function).
- **Creating** a new account / "Add new team member" (Slice 2 / Edge
  Function — shares the same `service_role` boundary).
- **Deleting / deactivating** accounts.
- Per-tech visit stats, activity, or last-login on this screen.

## Architecture

Pure front-end + `cloud.js` + one small guard migration. Mirrors the existing
`#profile` / `#reviews` screen pattern exactly (hash-router screen, `admin-only`
home button, `body.is-admin` gating, renderer that also checks role with
"Supervisors only." for techs). RLS is always the real enforcement; the UI
gate is convenience.

### 1. Migration `0021_guard_last_supervisor.sql`

The only new SQL in Slice 1. A `before update` trigger on `public.profiles`
(security definer) that raises an exception when a role change would:

- **demote the caller's own account** (`old.id = auth.uid()` and role goes
  supervisor → non-supervisor), or
- **remove the last supervisor** (the row is currently `supervisor`, the new
  role is not, and it is the only `supervisor` left).

Dashboard/service_role actions (no `auth.uid()`) are exempt, matching the
existing `guard_profile_role` convention, so the owner can always fix roles
from the Supabase dashboard in an emergency. This trigger is **additive** —
it runs alongside `guard_profile_role` (self-promotion block), not instead of
it. The UI confirm + hidden self-role-control are conveniences layered on top;
this trigger is the actual guarantee.

No RLS or grant changes: `profiles_update` (0001) already scopes the rows.

### 2. `cloud.js` — three new functions (exported on `window.cloud`)

- `listAllProfiles()` — every profile the caller may see. Returns
  `{ people: [{ id, fullName, phone, role, email? , isMe }], myId }` or
  `{ error }`. RLS already returns all rows to a supervisor and only the
  caller's own row to a tech (so a tech who reaches the screen sees at most
  themselves — but the renderer blocks them first anyway). Email is **not**
  in `profiles`; per-row email is a Slice-2 concern, so Slice 1 shows the
  caller's own email only (from `auth.getUser()`), and other rows show a
  muted "—" / "managed in account admin". Sorted by name.
- `saveProfileAsSupervisor(id, { fullName, phone })` — updates another
  person's name/phone. **Never sends `role`.** Falls back to name-only if the
  `phone` column is missing (same `isMissingColumn` pattern as
  `saveMyProfile`). Returns `{ error }`.
- `setProfileRole(id, role)` — the separate, higher-stakes role change, kept
  its own function so the call site is unmistakable. Sends only `{ role }`.
  Returns `{ error }` — and surfaces the DB guard's message verbatim if the
  trigger refuses (e.g. "Cannot demote the last supervisor"), so the UI can
  show exactly why it was blocked.

All three are defensive: even though RLS is the gate, the functions target a
specific `id` and never bulk-update.

### 3. `#team` screen (index.html)

- **Home button** `👥 Team`, class `admin-only`, in the supervisor home stack
  (placed with the other supervisor buttons; exact order finalized in the
  plan, deferring to the existing stack's logic like the reviews slice did).
- **Hash-router:** `#team` renders the roster. (No detail sub-route needed —
  editing is inline, card-style, like My Notes.)
- **Renderer gates on role:** `role === "supervisor"` or the screen shows
  `<p class="screen-sub">Supervisors only.</p>` — same as `#reviews`. RLS/the
  guard trigger are the real enforcement.
- **Roster = one card per person:**
  - Header: full name (or "Unnamed" fallback) + a role badge
    (tech / supervisor). "You" is marked on the caller's own card.
  - Read-only rows: **Email** (own card: real email; others: muted
    placeholder) and **Password** (always the muted "Managed in account admin
    — coming soon" placeholder). These are the Slice-2 seams.
  - **✎ Edit** turns the card into inline fields — Full name, Phone, and
    (only on **other** people's cards) a **Role** dropdown — with Save /
    Cancel. Same single-open-editor discipline as My Notes (`editingId`;
    opening another card or leaving the screen closes the first without
    saving).
  - The caller's **own** card has **no role control at all** (can't demote
    yourself — the DB also enforces this, but hiding the control avoids the
    dead-end).
- **Role change = confirm.** Selecting a new role in the dropdown and Saving
  pops a `confirm()` naming the person and the target role
  ("Change Jordan Rivera from tech to supervisor?"). On cancel, the dropdown
  reverts. On confirm, `setProfileRole` runs; if the DB guard refuses, the
  error message is shown inline and the card stays open.
- Every successful mutation re-fetches via `listAllProfiles()` and re-renders
  the whole roster, so the screen always matches the database (same
  re-render-from-server discipline as My Notes / pending queue).
- **"+ Add new team member"** button renders at the top of the screen but is
  **disabled** with a muted note "Coming in account admin (Slice 2)" — the
  visible seam for the next slice, so the screen looks complete now.

## Data flow

1. `loadRole()` (already runs on sign-in) sets `body.is-admin` for supervisors
   → the `👥 Team` button becomes visible.
2. Supervisor taps it → `location.hash = "#team"` → router renders roster from
   `listAllProfiles()`.
3. ✎ Edit → inline fields. Save name/phone → `saveProfileAsSupervisor` →
   re-fetch + re-render. Save a role change → confirm → `setProfileRole` →
   (DB guard may refuse) → re-fetch + re-render.
4. Techs never see the button; a tech deep-linking `#team` gets
   "Supervisors only."

## Error handling

- Not signed in / query fails → screen shows the error string, not a blank
  form (same as other screens).
- `phone` column missing → name-only fallback, `{ degraded: true }` (matches
  `saveMyProfile`).
- DB guard refusal (last supervisor / self-demote) → the trigger's message is
  shown inline on the card; nothing is silently swallowed.
- `confirm()` cancel on a role change → no call made, dropdown reverts.

## Testing / verification

No automated harness in this repo. Verify by:

1. **Parse check** — headless Chrome (the per-user Chrome at
   `%LOCALAPPDATA%\Google\Chrome\Application\chrome.exe`), zero SyntaxError,
   `#team` renders, `cloud.js` loads clean over `python -m http.server`.
2. **Live, signed in** (after hard-refresh; the SW cache is bumped):
   - As supervisor: `👥 Team` appears; roster lists all accounts; edit a
     tech's name + phone → Save → reload → persists; confirm the row in
     Supabase (`select full_name, phone from profiles where id = …`).
   - Change a tech → supervisor (confirm dialog names them) → reload → role
     persisted; that account now sees supervisor screens.
   - Attempt to demote the **last** supervisor → blocked with the guard's
     message (verify by temporarily having exactly one supervisor on a test
     project, or reasoning through the trigger with a `db query`).
   - Own card shows no role control.
   - As a tech: no `👥 Team` button; deep-linking `#team` → "Supervisors
     only."
3. **DB guard unit-check** via `supabase db query --linked`: an update that
   would demote the sole supervisor raises; a normal role swap (2+
   supervisors) succeeds.

SW cache bumped (next `v` after current `v24`) since `index.html` + `cloud.js`
change. Merged to `main` and pushed the same session per the owner's standing
rule.

## The road to Slice 2 (context, not built here)

One **Edge Function** (the project's first, under `supabase/functions/`)
holding the `service_role` key server-side and verifying the caller is a
supervisor will unlock all three remaining powers together:

- **Add new team member** — supervisor supplies name, email, and a **temp
  password** (owner's choice), account created Auto-Confirmed, `profiles` row
  auto-created as `tech` by the existing `handle_new_user` trigger.
- **Reset a tech's password** — style (supervisor-typed temp vs. emailed link)
  deferred; likely temp-password to match "Add member".
- **Change a tech's email**.

The Slice 1 screen's read-only Email/Password rows and disabled "+ Add new
team member" button are the seams these activate. Slice 1 does not depend on
any of it.
