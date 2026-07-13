# My Profile editor — design spec

Date: 2026-07-13
Status: approved, not yet built

## Context

This is slice 1 of a 4-part request from the owner:
1. **My Profile editor** (this spec)
2. Tech's own past-visit history view
3. Daily Logs calendar (auto + manual entries)
4. Shared on-call rotation calendar

Each slice gets its own spec → plan → build cycle. This keeps each change
small, reviewable, and shippable on its own, per the project's "smallest
complete slice first" rule.

## Problem

The `profiles` table (from `0001_init.sql`) only stores `full_name` and
`role`. There's no phone number, and no in-app way for a tech to correct
their own name — a supervisor would have to fix it directly in the Supabase
dashboard. The owner wants every user (tech or supervisor) to be able to view
and edit their own contact info from the home screen.

## Decisions

- **Fields:** `full_name` (already exists) and a new `phone` column. Login
  email stays read-only in this UI (changing sign-in email is a separate,
  bigger feature — not in scope).
- **Scope:** self-editing only. A tech can view/edit only their own row. A
  supervisor *can* already update anyone's row per existing RLS
  (`profiles_update` in `0001_init.sql`), but this slice's UI does not expose
  a "pick another tech to edit" flow — that's deferred to a future
  roster/admin screen. No RLS changes are needed to support that later, since
  the policy already allows it.
- **Entry point:** a home-screen button, always visible (not gated by
  `admin-only`), not a first-login forced modal. Simpler, consistent with the
  existing button-grid pattern (`homeNotes`, `homeRoutes`, etc.), and avoids
  building "is this their first login" detection.
- **Role display:** read-only badge ("Tech" / "Supervisor"). Role changes stay
  a dashboard-only, deliberate action (existing `guard_profile_role` trigger
  already blocks self-promotion).

## Data model

New migration `0015_profile_phone.sql`:

```sql
alter table public.profiles
  add column if not exists phone text not null default '';
```

No RLS or grant changes — the existing policies already cover the new column:
- `profiles_select`: read own row, or any row if supervisor.
- `profiles_update`: update own row, or any row if supervisor (with
  `guard_profile_role` still blocking a non-supervisor from changing `role`).

## UI

New screen `#profile`, following the existing hash-router screen pattern
(`#notes`, `#routes`, `#pending`):

- Home screen gains a new button `👤 My profile` (no `admin-only` class),
  placed after the existing buttons, before "Sign out".
- Screen layout (mirrors `screen-head` + back-to-home pattern used by
  `notesScreen`/`routesScreen`):
  - Header: "← Home" button, "My Profile" title.
  - Read-only line: signed-in email (from `auth.getUser()`).
  - Read-only line: role badge.
  - Editable field: Full name (text input).
  - Editable field: Phone (`type="tel"` input).
  - "Save" button + inline status message (same visual pattern as the
    existing "Set / change password" status line in the sidebar).

## cloud.js additions

- `getMyProfile()` — reads the caller's own `id, full_name, phone, role` from
  `profiles`, plus `email` from `supabase.auth.getUser()`. Returns a plain
  object; on error, returns `{ error }` following the module's existing
  error-shape convention (see `loadInProgress`/`lastDone`).
- `saveMyProfile({ full_name, phone })` — updates the caller's own row
  (`.eq("id", user.id)`), never sends `role`. Returns `{ error }` on failure,
  `{ error: null }` on success.
- Add both to the `window.cloud` export object alongside the existing
  functions.

## Error handling

- If the `phone` column doesn't exist yet (migration not applied), follow the
  established `isMissingColumn()` graceful-degradation pattern already used
  elsewhere in `cloud.js`: load/save `full_name` only, and show a small note
  ("Phone sync once the DB update is applied.") — consistent with how
  `0003_dated_items_and_temps.sql` was handled.
- Save validates `full_name` is non-empty before submitting (mirrors existing
  client-side validation elsewhere, e.g. the survey's name/date/house check).
  Phone has no format validation — free text, since formats vary (owner can
  ask for masking later if needed).

## Testing / verification

No automated tests in this project. Verify by:
1. Running the migration (`supabase db push`), confirming `phone` column
   exists.
2. Signing in as a tech, opening "My profile", editing name + phone, saving,
   reloading the page, confirming the values persisted (both in the UI and via
   a `select` in the Supabase dashboard).
3. Signing in as a second tech, confirming they see only their own info (not
   the first tech's).
4. Signing in as a supervisor, confirming they can also edit their own profile
   via the same screen (not another tech's — that's out of scope).

## Out of scope (explicitly deferred)

- Supervisor editing another tech's profile via UI (RLS already supports it;
  no UI yet).
- Changing sign-in email.
- Phone number format validation/masking.
- Any "first login" detection or forced-completion flow.
