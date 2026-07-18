# Managed Job Titles + Office/Field home screens — Slice 1 design

**Date:** 2026-07-18
**Status:** Approved (owner), pending spec review before planning.

## Context

Today a person's job title is **free text** on `public.profiles.job_title`
(migration 0022): anyone types anything in My Profile or a supervisor types it
on the 👥 Team screen. That was fine as a label but the owner now needs titles
to do real work:

1. **A managed, consistent list.** Supervisors create the company's official
   titles once; everyone else picks from that list — no "Lead Tech" vs
   "lead tech" vs "Lead Technician" drift.
2. **Titles decide the home screen.** New non-field roles are coming — an
   **Interior Designer**, a **Project Director**, and a **Carpenter / special
   projects** (the owner). They don't do house visits or daily logs; they do
   ordering, renovations, and project management. Their home screen must not
   show visit tooling that isn't theirs.

The owner also raised **per-person "pick and choose" permissions** (e.g. grant
someone admin powers à la carte instead of the all-or-nothing supervisor role).
That is real but **undecided** ("it will be different, not sure yet"), so it is
deliberately **out of this slice** — Slice 1 only leaves a clean seam for it.

Per the owner's standing rule (CLAUDE.md): **build the smallest complete slice
first, then widen.** This spec is Slice 1 only.

## What every title shares (owner decision)

Regardless of title/kind, **every** signed-in person keeps:

- 📝 **House notes**
- 📋 **My notes**
- 👤 **My profile**
- 🧰 **Maintenance requests** and **New maintenance request** — *once those
  screens exist* (the owner is building them now; they are not in the app yet).
  Slice 1 does **not** build them; it only guarantees they will be treated as
  "always-on", not field-only, when they land.

## The two kinds (owner decision: "two kinds for now")

Each title is marked one of exactly two **kinds**:

- **`field`** — today's full experience: New/Continue house visit, My visit
  history, Daily logs, 🧰 Field tools, plus everything in "always shared".
- **`office`** — the shared always-on set **only** (House notes, My notes, My
  profile, + Maintenance requests when they exist). No visit/daily-log tooling.
  Each office title gets a *real* tailored screen later (Slice 3); until then an
  office person sees the always-on buttons plus a friendly "Your tailored tools
  are coming" note, never a blank home.

Interior Designer, Project Director, and Carpenter start as **office**.

## Goals (Slice 1)

1. A supervisor-only **🏷️ Job titles** screen: create a title (name +
   field/office), rename it, and retire / reactivate it.
2. Assigning a title to a person becomes a **dropdown of active titles** on the
   👥 Team screen (replacing the current free-text input). **Supervisors only**
   — people cannot set their own title.
3. My Profile shows the person's title as **read-only** (they can't change it),
   since it now governs their home screen (and later their permissions).
4. A person's home screen is gated by their title's **kind**: `office` people
   don't see field-only buttons; everyone keeps the always-on set.
5. Existing free-text titles are **backfilled** into the new table with no data
   loss and no manual re-typing.

## Non-goals (Slice 1 — explicit)

- **Per-person / per-title permissions** ("pick and choose allow"). Undecided;
  Slice 2. The `job_titles` table is where those columns/joins will live.
- The **actual tailored office screens** for Designer / Director / Carpenter.
  Slice 3 — each in its own cycle. Slice 1 routes office people to a generic
  office home so nothing looks broken meanwhile.
- The **Maintenance requests** screens themselves (owner is building separately).
- People **self-selecting** their title.
- **Deleting** a title that is in use (we retire via `active=false` instead).

## Architecture

Pure front-end + `cloud.js` + one migration, mirroring the existing
`#team` / `#reviews` screen pattern (hash-router screen, `admin-only` home
button, role-gated renderer, re-render-from-server after every mutation). RLS is
always the real enforcement; the UI gate is convenience.

### 1. Migration `0023_job_titles.sql`

**New table `public.job_titles`:**

| column | type | notes |
|---|---|---|
| `id` | `uuid` primary key default `gen_random_uuid()` | |
| `name` | `text` not null | `unique` (case-insensitive via a unique index on `lower(name)`) so "Lead Tech" can't be created twice |
| `kind` | `text` not null default `'field'` | `check (kind in ('field','office'))` |
| `active` | `boolean` not null default `true` | retire = set false; never hard-delete a title in use |
| `created_at` | `timestamptz` not null default `now()` | |

**RLS on `job_titles`** (auto-RLS is on, so it starts locked):
- `job_titles_select` — **any authenticated user** may read (dropdowns and
  labels need the list). `using (true)` for role `authenticated`.
- `job_titles_write` — **supervisors only** for insert/update. Reuses the
  established `exists (select 1 from profiles where id = auth.uid() and role =
  'supervisor')` predicate used by other supervisor policies. No delete policy
  (deletion is not exposed; retire instead).

**`profiles` gets `job_title_id`:**
```sql
alter table public.profiles
  add column if not exists job_title_id uuid references public.job_titles(id);
```
Nullable (a person may have no title yet). The FK means a title in use can't be
deleted, and renaming a title reflects everywhere instantly. No new RLS/grant on
`profiles` — the existing `profiles_select` / `profiles_update` (0001) already
gate rows, and this column rides along.

**Backfill (idempotent, in the same migration):**
1. Insert one `job_titles` row (`kind='field'`, everyone today is a tech) for
   each distinct non-empty `trim(job_title)` currently on any profile, skipping
   any that already exist (`on conflict do nothing` against the lower(name)
   index).
2. Set each profile's `job_title_id` to the matching row by
   `lower(trim(job_title)) = lower(name)`.

**Old column kept, not dropped.** `profiles.job_title` (free text) stays in
place for one release as a recovery net if a backfill mis-maps. It is **no
longer read or written by the app** after this slice. A later migration
(`0024_drop_job_title_text.sql`, not part of this slice) drops it once the
owner has confirmed the migrated data looks right. This is the
"no-bandaid **and** no-data-loss" path — the proper model ships now, the text
lingers only as an undo.

### 2. `cloud.js` changes

**New (title list CRUD):**
- `listJobTitles({ activeOnly } = {})` — returns
  `{ titles: [{ id, name, kind, active }], error }`, ordered by name. Any
  authenticated caller (RLS returns the list to all). `activeOnly` filters to
  `active = true` for the assignment dropdown; the management screen passes
  `false` to show retired ones too.
- `createJobTitle({ name, kind })` — insert; supervisor-only via RLS. Trims
  name; returns `{ error }`. Surfaces the unique-index violation as a friendly
  "A title with that name already exists."
- `renameJobTitle(id, name)` — update name; `{ error }`.
- `setJobTitleKind(id, kind)` — update kind; `{ error }`. (Editing a title's
  name and kind are the two things the management card can change.)
- `setJobTitleActive(id, active)` — retire / reactivate; `{ error }`.

**Changed (assignment + reads join the title):**
- `getMyProfile()` — select `job_title_id` and **join** `job_titles(name,kind)`
  (`select("full_name, phone, role, job_title_id, job_titles(name,kind)")`).
  Returns `jobTitleName` and `jobTitleKind` (both possibly empty/null) instead
  of the old free-text `jobTitle`. The `isMissingColumn` fallback path is kept
  for the pre-0023 shape.
- `loadRole()` — after setting `window.cloud.role`, also read the caller's
  `job_titles(kind)` and set `window.cloud.jobTitleKind` and toggle
  **`body.is-office`** (`kind === 'office'`). Field/no-title people are not
  office, so field tooling stays visible for them exactly as today.
- `listAllProfiles()` — join `job_titles(name,kind)`; each person carries
  `jobTitleId`, `jobTitleName`, `jobTitleKind`. Keeps the missing-column
  fallback.
- `saveProfileAsSupervisor(id, { fullName, phone, jobTitleId })` — sends
  `job_title_id` (nullable) **instead of** the free-text `job_title`. Name-only
  fallback preserved.
- `saveMyProfile({ fullName, phone })` — **stops sending any title** (title is
  no longer self-editable). Name/phone only.

All writes remain defensive (single `id`, never bulk).

### 3. `#titles` screen (index.html) — new, supervisor-only

- **Home button** `🏷️ Job titles`, class `admin-only`, in the supervisor stack
  near 👥 Team (exact order finalized in the plan, deferring to the existing
  stack logic like prior slices).
- **Hash-router:** `#titles` renders the manager. Editing is inline/card-style
  like My Notes and the Team roster (single open editor via an `editingTitleId`;
  the list is re-fetched and re-rendered from the server after every mutation).
- **Renderer gates on role:** supervisor, or `<p class="screen-sub">Supervisors
  only.</p>` — same as `#team`/`#reviews`. RLS is the real gate.
- **"+ Add job title"** at the top: name field + a Field/Office toggle + Add.
- **One card per title:** name + a **kind badge** (Field / Office) + an
  **active/retired badge**. ✎ Edit turns it into name field + kind toggle with
  Save / Cancel. A **Retire** / **Reactivate** button toggles `active`.
  Retiring only hides the title from the assignment dropdown; people already
  holding it keep it (and it still renders on their profile) until reassigned.

### 4. 👥 Team screen change

The current free-text **Job title `<input>`** in the inline editor becomes a
`<select>` populated from `listJobTitles({ activeOnly: true })` with a leading
"— none —" option. Saving writes `job_title_id` via `saveProfileAsSupervisor`.
The read-only card row shows the joined title name (or "—"). If the assigned
title happens to be retired, its name still renders (the person still has it);
it just won't appear as a choose-able option for others.

### 5. My Profile screen change

The editable **Job title `<input>`** becomes a **read-only row** ("Job title:
Lead Tech" or "—"), since titles are supervisor-assigned now. Name and phone
stay editable. `saveMyProfile` no longer sends a title.

### 6. Home screen — the `kind` gate (index.html + CSS)

- CSS, mirroring the existing `body:not(.is-admin) .admin-only { display:none }`
  rule: field-only buttons get a class **`field-only`**, and
  `body.is-office .field-only { display: none; }` hides them for office people.
  Field-only buttons = 🏠 New house visit, ▶ Continue house visit, 🗓️ My visit
  history, 🗓️ Daily logs, 🧰 Field tools drawer. The always-on buttons (House
  notes, My notes, My profile) carry no class and always show.
- An **office empty-state note** renders on the home screen only when
  `body.is-office` and no tailored office screen exists yet: a short muted
  "Your tailored tools are coming — for now you have House notes, My notes and
  My profile." So an office home is never a near-empty screen.
- `body.is-office` is set by `loadRole()` (above) and cleared on sign-out and in
  supervisor **preview** mode (a supervisor previewing a tech is acting as a
  field user), matching how `is-admin` is handled in `startPreview`/`exitPreview`.
- **Supervisor + office is possible** (e.g. the Project Director could be a
  supervisor). `is-admin` and `is-office` are independent: such a person sees
  supervisor buttons **and** has field tooling hidden. That's intended — kind
  controls field tooling, role controls supervisor tooling.

## Data flow

1. On sign-in `loadRole()` sets `window.cloud.role`, `body.is-admin`,
   `window.cloud.jobTitleKind`, and `body.is-office`. Home renders the right
   button set immediately.
2. Supervisor → 🏷️ Job titles → creates/renames/retires titles
   (`create/rename/setJobTitleKind/setJobTitleActive` → re-fetch + re-render).
3. Supervisor → 👥 Team → ✎ Edit a person → picks a title from the dropdown →
   Save (`saveProfileAsSupervisor` with `job_title_id`) → re-fetch + re-render.
   That person's next sign-in (or reload) reflects the new home screen.
4. A field or untitled person sees today's full home; an office person sees the
   always-on set + the "coming soon" note.

## Error handling

- Not signed in / query fails → screen shows the error string, not a blank form
  (same as other screens).
- Duplicate title name → the unique-index violation is caught and shown as
  "A title with that name already exists."
- `job_title_id` / `job_titles` missing (pre-0023) → `isMissingColumn`
  fallbacks keep My Profile, Team, and role loading working (degraded: no
  titles), so a half-applied deploy never white-screens.
- Retiring a title in use is safe (people keep it); deleting is not exposed, so
  the FK can never orphan a profile.

## Testing / verification

No automated harness in this repo. Verify by:

1. **Parse check** — headless Chrome (the per-user Chrome at
   `%LOCALAPPDATA%\Google\Chrome\Application\chrome.exe`), zero SyntaxError;
   `#titles` and `#team` render; `cloud.js` loads clean over
   `python -m http.server`.
2. **Migration** — `supabase db push --workdir "c:\Big Dogs Apps\MTX Checklist
   V1"`; then `supabase db query --linked` to confirm: `job_titles` exists with
   the check + unique-lower index; `profiles.job_title_id` exists; the backfill
   created a row per distinct old title and pointed profiles at them; old
   `profiles.job_title` text is untouched.
3. **Live, signed in** (after hard-refresh; SW cache bumped):
   - As supervisor: 🏷️ Job titles appears; create "Interior Designer"
     (office) and "Lead Tech" (field); rename one; retire one and confirm it
     drops out of the Team dropdown but a person already holding it still shows
     it.
   - On 👥 Team: assign the office title to a test account; reload; confirm the
     row persists (`select job_title_id from profiles where id = …`).
   - Sign in as that office test account (or preview is not enough — preview
     forces field; sign in for real): confirm the home screen hides New/Continue
     visit, My visit history, Daily logs, Field tools; shows House notes, My
     notes, My profile + the "coming soon" note.
   - My Profile shows the title read-only; there's no title input to edit.
   - As a tech: no 🏷️ Job titles button; deep-linking `#titles` → "Supervisors
     only."
4. **RLS check** via `supabase db query --linked`: a non-supervisor insert into
   `job_titles` is refused; a select returns the list to any authenticated user.

SW cache bumped (next `v` after current `v28`) since `index.html` + `cloud.js`
change. Merged to `main` and pushed the same session per the owner's standing
rule; then remind the owner to hard-refresh (Ctrl+Shift+R; fully reopen the PWA
on phones).

## The road to Slice 2 and 3 (context, not built here)

- **Slice 2 — permissions ("pick and choose allow").** Undecided by the owner.
  Whatever it becomes (per-person grant flags, or per-title permission sets),
  the `job_titles` table and the supervisor-only 🏷️ screen are where it hangs.
  Slice 1 builds none of it and assumes none of its shape.
- **Slice 3 — tailored office screens.** Interior Designer, Project Director,
  Carpenter each get a real home (ordering, renovations, awaiting-orders,
  project management) in its own cycle. Slice 1's office empty-state note is the
  seam each of those replaces.
- **Cleanup migration `0024_drop_job_title_text.sql`** drops the retained
  free-text `profiles.job_title` once the migrated data is confirmed good — a
  one-line follow-up, not part of this slice.
