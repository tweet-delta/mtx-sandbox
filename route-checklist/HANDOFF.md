# Route Checklist App — Handoff Notes

Context for continuing work in a new session. Point a fresh Claude Code
session at this file: "Read route-checklist/HANDOFF.md and let's continue."

## SLICE 4 — Shared on-call rotation calendar — DEFERRED (not started)

**Intentionally paused by the owner on 2026-07-14.** Slice 4 of the 4-slice
request is a **shared on-call rotation calendar**. It has **not** been
brainstormed, spec'd, or planned — the name above is the entire definition so
far. Nothing is built. When the owner is ready, start it as a fresh
brainstorm → spec → plan → build cycle (its own spec/plan under
`docs/superpowers/`). Slices 1–3 (My Profile, My Visit History, Daily Logs +
supervisor view) are complete and live on `main`.

---

## STATE AS OF 2026-07-14 (In-checklist House info panel) — read this first

**Built inline (executing-plans), all 4 tasks committed on
`claude/claude-code-tutorial-5l5ew2`.** Front-end-only slice — no migration,
no `cloud.js` change, no RLS change. Spec:
`docs/superpowers/specs/2026-07-14-house-info-panel-design.md`; plan:
`docs/superpowers/plans/2026-07-14-house-info-panel.md`.

- **New ℹ️ House info button** in the sticky visit header, next to ☰. Hidden
  until a house is selected (toggled in `hydrate()`, which runs on every
  `rebuild()`). Tapping it opens a modal `<dialog id="houseInfoModal">` (same
  focus-trap/Esc/✕ pattern as the survey modal) showing the **current house
  only**: codes section first (from `ALL_CODES`, sourced from the gitignored
  `house-codes.local.js` — on-device only), then house info pairs (paint,
  attic access, etc., from `h.info`). If a section has no data it's omitted
  entirely (no empty headers); if neither exists, a plain "No codes or info on
  file for this house" line shows. New shared renderer
  `renderHouseInfoInto(el)` builds this markup; `openHouseInfo()` wires the
  button to it.
- **Codes deliberately stay local-only.** The original design explored moving
  codes into a protected Supabase table so every device would see them, but
  the **owner explicitly chose to keep the existing "codes never in Supabase"
  posture** — real codes for real houses stay in `house-codes.local.js` only,
  copied by hand to devices that should show them. This slice does NOT change
  that; it only makes whatever's already in the local file reachable with one
  tap instead of scrolling into the old sidebar.
- **☰ Houses sidebar slimmed to an account-only menu.** The house list, the
  🔍 search toggle, and the buried house-info panel are all removed from the
  sidebar (and their JS — `renderHouseList`, `toggleHouseSearch`, the
  house-list click handler, the search input handler — deleted). What remains:
  "Signed in as…", Set/change password, Sign out. The header button changed
  from `☰ Houses` to **👤** (`aria-label="Account"`). House switching is
  unaffected — it already worked via **← Home → 🏠 New house visit**, which
  still confirms before discarding unsaved work (`selectHouse()` unchanged).
- Orphaned sidebar-only CSS (`#houseSearch`, `.house-btn`, `#houseInfo`,
  `.sidebar-search-toggle`) was removed; `.info-item` / `.info-item.code` are
  kept (now used only by the modal) and a new `.info-head` class labels the
  "Codes" / "House info" sub-sections inside it.
- SW cache bumped `v19` → `v20`.
- **NOT YET verified end-to-end on the live site** — no signed-in browser
  session or local `house-codes.local.js` content was available in this
  session (sandboxed agent, no automated test harness in this repo). Owner/next
  session, after hard-refresh (Ctrl+Shift+R, may take two for the v20 SW to
  take over) and fully closing/reopening the PWA on phones:
  1. Start a visit at a house with codes in your local file → confirm ℹ️
     appears in the header only once a house is picked → tap it → codes show
     first, then info; Esc/✕ closes and focus returns to ℹ️.
  2. Pick "(no house — full checklist)" → confirm ℹ️ disappears.
  3. Pick a house with no codes/info → confirm the "No codes or info on file"
     line, no error.
  4. On a device without `house-codes.local.js` → confirm the codes section is
     simply absent (info pairs still show if present).
  5. Tap 👤 → confirm only account actions show (no house list/search).
  6. Confirm ← Home → 🏠 New house visit still prompts before discarding an
     in-progress checklist.
  7. Deep-link/reload mid-visit → header + ℹ️ still work, no console errors.

---

## STATE AS OF 2026-07-14 (Daily Logs calendar — slice 3 of 4) — read this first

**Built inline (executing-plans, 6 tasks, per-task committed) on
`claude/claude-code-tutorial-5l5ew2`.** Slice 3 of 4 (slice 4 — shared on-call
rotation calendar — is a separate future cycle, NOT built).
Spec: `docs/superpowers/specs/2026-07-14-daily-logs-design.md`; plan:
`docs/superpowers/plans/2026-07-14-daily-logs.md`.

**Two follow-on fixes + a supervisor view landed the same day (2026-07-14):**
- **Migration `0017_daily_logs_full_uniq.sql`** (pushed): replaced 0016's
  *partial* unique index with a **full** `(tech_id, visit_id, log_date)` unique
  index. The partial index couldn't serve as an upsert `onConflict` arbiter
  (Postgres returned `42P10`), so every live auto-stamp was silently failing —
  no diary rows landed from real saves. Full index fixes it; manual rows
  (`visit_id` NULL, NULLs distinct in a unique index) still coexist freely.
- **Clickable empty days:** the calendar grid now renders *every* real day as a
  `<button data-cal-day>` (only pre-1st filler cells stay inert), so a tech can
  open any past day and backfill a note. Previously only days-with-activity
  were clickable.
- **Supervisor view:** on the Daily Logs screen, supervisors (`body.is-admin`)
  get a "Viewing:" tech picker (techs + themselves, defaults to self). Picking a
  teammate loads that tech's calendar **read-only** (no Add/Edit/Delete on
  notes); picking themselves restores full control; the selected day clears on
  every tech switch. Powered by `listLogsInRange(start, end, techId)` +
  `listLogTechs()` in cloud.js; the `daily_logs` RLS select policy already
  permits supervisor reads (**no migration**). SW cache at **v19**.
  Spec/plan: `docs/superpowers/{specs,plans}/2026-07-14-supervisor-daily-logs*`.

- **Migration `0016_daily_logs.sql`** (pushed & verified live: 4 auto rows
  backfilled from 4 completed visits). New `public.daily_logs` table — a
  per-tech work diary. Columns: `tech_id`, `log_date`, `kind` (`auto`|`manual`),
  `visit_id`+`house_id` (auto only), `note` (manual only), `done_keys` (jsonb,
  auto only — cumulative snapshot of checked item keys as of that day),
  timestamps. Partial unique index `(tech_id, visit_id, log_date) where
  kind='auto'` = one auto row per tech+visit+day. RLS: **select** own-or-
  supervisor; **insert/update/delete** own rows. The update policy is
  ownership-only (NOT `kind`-restricted) so the auto-stamp upsert can refresh
  its own auto row; user-facing immutability of auto rows is enforced in the
  **app** (UI shows no edit/delete on auto entries + `updateLogEntry`/
  `deleteLogEntry` self-scope `kind='manual'`). One-time backfill: one auto row
  per completed visit on its `visit_date` with final done keys.
- **`cloud.js`:** `saveVisit()` now calls `stampDailyLog()` after a successful
  save — best-effort (a failed stamp NEVER blocks the visit save; logs to
  `console.warn`), upserts today's auto row using the **client's current local
  date** via `localToday()` (NOT `toISOString()`/UTC — techs are in Minnesota
  so an evening save must not roll to tomorrow; and NOT `v.date`, a
  user-editable field) so a multi-day visit lands on each real workday it was
  saved. Plus 4 exported functions:
  `listLogsInRange(start,end)` (own rows in a date range, one month/call),
  `addLogEntry(date,note)`, `updateLogEntry(id,note)`, `deleteLogEntry(id)` —
  all self-scoped `tech_id=me` (mutators also `kind='manual'`) atop RLS.
- **New `#logs` screen** (hash-router, same pattern as `#history`). Home button
  **"🗓️ Daily logs"**, always visible (NOT `admin-only`). Month grid, `‹`/`›`
  to change month, today highlighted. Day cell shows the **house name** if an
  auto row exists, else **"Daily log"** for manual-only days, else a plain
  number. Tap a day → detail below: per-section `"<section> — n/m done
  (+k today)"` + the list of items finished THAT day (cumulative snapshot minus
  the prior day's snapshot for the same visit, computed client-side), then
  manual notes (each Edit/Delete), then "+ Add note" (works on past days).
  Unknown `done_keys` (checklist changed since the visit) list under "Other" by
  raw key. The per-day diff and the grid key on **`visit_id`** (returned by
  `listLogsInRange`), not house name, so two visits to the same house in a month
  don't conflate; a day with progress saved on **two different visits** shows
  both (cell lists both house names, detail shows both sections).
- **Explicitly out of scope this slice:** the on-call rotation calendar
  (slice 4), hours/mileage/structured fields, linking a manual note to a house,
  editing/deleting auto rows, cross-tech or house-level views, search/export,
  photos (Phase 2).
- SW cache bumped `v16` → `v17`.
- **NOT YET verified end-to-end on the live site.** Owner/next session:
  hard-refresh (Ctrl+Shift+R), sign in as `tech1@example.com` → confirm
  "🗓️ Daily logs" appears; open it → current month renders with backfilled dots
  on past completed-visit dates. Start a visit, **Save progress** → today's cell
  shows the house name; tap it → sections/items finished so far are listed. Save
  progress **again same day** → list grows, still exactly ONE auto entry (no
  duplicate). Add a manual note to today and a past day; edit one; delete one →
  each re-renders and the month updates. Sign in as `tech2@example.com` → sees
  only their own diary (isolation). Deep-link reload on `#logs` → re-renders, no
  console errors. Test accounts: `tech1@example.com`, `tech2@example.com`.

## STATE AS OF 2026-07-13 (My Visit History — slice 2 of 4)

**Built via subagent-driven-development (6 tasks, each task-reviewed + final
whole-branch reviewed on Opus: Ready to merge, 0 Critical/0 Important), all
committed on `claude/claude-code-tutorial-5l5ew2` (slice commits
`7160d6c..60c57db`).** Slice 2 of 4 (slices 3–4 — Daily Logs calendar,
on-call rotation calendar — are separate future cycles, NOT built).
Spec: `docs/superpowers/specs/2026-07-13-visit-history-design.md`; plan:
`docs/superpowers/plans/2026-07-13-visit-history.md`.

- **No migration, no RLS change.** Migrations 0001 + 0002 already grant any
  signed-in staff read access to `visits`/`visit_items`; this slice is
  read-only front-end + two `cloud.js` reads.
- **`cloud.js` additions:** `listMyVisits()` (the signed-in tech's OWN
  completed visits — `{ id, houseName, visitDate }[]`, newest first; returns
  `[]` on no-user/error) and `getVisitDetail(visitId)` (one OWN visit +
  its items — filters `id` AND `tech_id`, `.maybeSingle()`; returns
  `{ houseName, visitDate, items:[{item_key,answer,note}] }` or `{ error }`).
  Both self-scoped (`tech_id = me`) as defense-in-depth atop RLS. Exported
  on `window.cloud`.
- **New `#history` screen** (hash-router: `#history` list, `#history/<id>`
  detail — same pattern as `#profile`). Home button **"🗓️ My visit history"**,
  always visible (NOT `admin-only`). List = house + date (via `fmtDate`),
  newest first, tap → detail. Detail shows ONLY items worth revisiting:
  **flagged** (recorded `answer === item.bad` polarity, looked up in
  `ITEM_BY_KEY`/`GROUPS` — computed client-side, never stored) **OR** carrying
  a note. Clean visit → "No issues flagged on this visit." Unknown `item_key`
  (checklist changed since the visit) still shows, labelled by raw key.
- **Explicitly out of scope this slice:** other techs'/house-level history,
  full checklist replay / alarm counts / survey, photos (Phase 2), editing a
  past visit (read-only), filtering/search.
- SW cache bumped `v15` → `v16` (`index.html` + `cloud.js` changed).
- **NOT YET verified end-to-end on the live site.** Owner/next session:
  hard-refresh (Ctrl+Shift+R), sign in as tech1 (has a completed visit),
  confirm "🗓️ My visit history" appears, open it → list shows the visit,
  tap it → detail shows only flagged/noted items; sign in as tech2 and
  confirm they see only their own (isolation); deep-link reload on
  `#history/<id>` re-renders with no console errors. Test accounts:
  `tech1@example.com`, `tech2@example.com` (both role=tech).

## STATE AS OF 2026-07-13 (My Profile screen — slice 1 of 4)

**Built via subagent-driven-development (4 tasks, each task-reviewed +
final whole-branch reviewed on Opus), all committed on
`claude/claude-code-tutorial-5l5ew2`.** This is slice 1 of a larger
owner request (own visit history, a Daily Logs calendar, and a shared
on-call rotation calendar are separate future slices — NOT built yet).
Spec: `docs/superpowers/specs/2026-07-13-profile-editor-design.md`; plan:
`docs/superpowers/plans/2026-07-13-profile-editor.md`.

- **Migration `0015_profile_phone.sql`** (pushed & verified live via
  `supabase db query --linked`): adds `phone text not null default ''` to
  `public.profiles`. No RLS/grant changes — the existing `profiles_select`/
  `profiles_update` policies (self or supervisor) already cover the new
  column.
- **`cloud.js` additions:** `getMyProfile()` (returns
  `{ fullName, phone, role, email }` for the signed-in user, or
  `{ error }`) and `saveMyProfile({ fullName, phone })` (updates only the
  caller's own row, never sends `role`; returns `{ error }`, with
  `{ error: null, degraded: true }` if the `phone` column isn't there yet).
  Both exported on `window.cloud`.
- **New `#profile` screen** (hash-router screen, same pattern as
  `#notes`/`#routes`/`#pending`): a home-screen button **"👤 My profile"**,
  always visible (not `admin-only`) — every user edits their own name and
  phone. Shows signed-in email + role read-only; role is never editable
  from this UI (dashboard-only, still enforced server-side by
  `guard_profile_role`). Full name is validated non-empty before save;
  phone has no format validation (free text, by design).
- **Explicitly out of scope this slice:** a supervisor editing another
  tech's profile via UI (RLS already allows it; no UI yet — a future
  roster screen), changing sign-in email, phone format/masking.
- SW cache bumped `v14` → `v15` (`index.html` + `cloud.js` both changed).
- **NOT YET verified end-to-end on the live site** — no signed-in browser
  session was available during the build (sandboxed agents). Next
  session/owner: sign in as a tech, confirm "👤 My profile" appears,
  edit name + phone, save, reload, confirm persistence; sign in as a
  second tech and confirm isolation (only their own row); confirm the
  empty-name inline validation blocks a save; spot-check the row in the
  Supabase dashboard (`select full_name, phone from public.profiles
  where id = auth.uid();`). Hard-refresh (Ctrl+Shift+R) after deploy, and
  fully close/reopen the PWA on phones — the old service worker keeps
  serving cached files until then.

## STATE AS OF 2026-07-12 (Emmert house added — 48 houses)

Emmert added via the established house-adding pipeline (see that section):
entry appended to `house-data.js` (**48 total**, parse check passed — 48
unique names, renders in the picker); all five codes (house security, garage,
med lock Stealth, closet code, front-closet programming code) went to
`house-codes.local.js` ONLY — verified absent from tracked files (guard +
grep). Vendor contact (Electrical Watchmen, Ben's number) is in the tracked
info panel by owner decision — business contact, not resident data. Migration
`0010_emmert_house.sql` generated headless from the parsed entry and applied
with `supabase db push` (migration list: local = remote through 0010; row
readable only when signed in, so the owner's live spot-check is the last
mile). SW cache bumped v10 → v11 so devices refresh the roster.

**Level-specific note labels (migration 0011, pushed & applied).** The
per-item house notes that used single-level "Up/Upstairs/Down/Downstairs"
labels were rewritten to `Residents (up):` / `RS (down):` form — flipped at
the five RS-on-top houses (92nd Crescent, Amble, McAfee, Sherwood Place; and
Fallgold, which uses the three-level `Residents (1st)` / `RS (2nd)` /
`Basement (shared)`). Migration `0011_level_labels.sql` merges the new strings
into `houses.notes` (jsonb `||`, one idempotent UPDATE per house, only the
listed keys change) and was applied with `supabase db push`; because notes
come from Supabase, the DB change is live immediately regardless of the deploy.
`house-data.js` was synced with the identical strings (the offline fallback),
and SW cache bumped v11 → v12 so devices refresh the roster. The House info
panel (`houses.info`) was intentionally **not** touched — those "Up/Down"
uses live in a different field and are a possible follow-up. Full,
owner-approved before→after table:
`docs/superpowers/specs/2026-07-12-level-label-notes-design.md`. **Owner's
live spot-check is pending** — sign in and open 140th Lane West (fridge coils),
McAfee (dryer vents flipped), and Fallgold (three-level labels) to confirm.

**Level-split notes (migrations 0012 + 0013, pushed & applied).** Two related
cleanups to the level labeling introduced in 0011. **Migration
`0012_drop_direction_labels.sql`** dropped the `(up)/(down)/(1st)/(2nd)/(shared)`
direction suffixes from the `fireExtinguishers`, `dryerVents`, and `atticAccess`
notes (52 notes across the roster), collapsing them to plain
`Resident: X · RS: Y` — the direction was redundant once the Resident/RS role
was named. **Migration `0013_fridge_coils_split.sql`** split the single
`fridgeCoils` note into two independent keys, `fridgeCoils_res` and
`fridgeCoils_rs`, so each level's coils note carries its own value and can be
edited without touching the other. Rendering: `NOTE_RULES` gained an optional
`itemKey` field so a rule can bind to one specific checklist item — the two
fridge-coils rules match `refrigerator coils` but scope to `rk-fridge-coils`
(Resident-Level Kitchen) and `rsk-fridge-coils` (RS-Unit Kitchen) respectively,
so each 📍 line appears only under its own kitchen section (no combined line).
`NOTE_KEY_LABELS` labels the two keys "Refrigerator coils (Resident)" and
"Refrigerator coils (RS)" so the House Notes screen and pending queue read
clearly. `house-data.js` (the offline fallback) was synced with the identical
strings and split keys; both migrations use jsonb `||` set-semantics UPDATEs
per house, so — as with 0011 — the DB change is live immediately and the deploy
only refreshes the offline fallback. SW cache bumped `v12` → `v14` (Part 1
shipped `v13`, the fridge split shipped `v14`). **Deferred follow-up:** the
"coils physically move when a fridge is replaced, so re-verify which unit each
value describes" reminder was intentionally left out — it needs a System author
and once-only migration seeding we don't have yet. **Owner's live spot-check is
pending** (see the level-split spot-check list handed over this session).

## STATE AS OF 2026-07-12 (House-note suggestions: tech propose / supervisor review) — read this first

**Feature built across migration 0008 + cloud.js + UI, pushed as part of this
commit (SW bumped `route-checklist-v7` → `v8`).** Techs can now propose
changes to house notes and info instead of editing them directly; supervisors
review and approve/deny. GitHub Pages deploys from this branch, so this push
takes the feature live at
`https://tweet-delta.github.io/mtx-sandbox/route-checklist/index.html#home`.

**Database (migration `0008_note_suggestions_all_kinds.sql`, PUSHED AND LIVE
in Supabase):**
- `house_note_suggestions` gained `target`, `note_key`, `action`,
  `deny_reason`, `seen_by_author` columns.
- `approve_note_suggestion(uuid)` was replaced — now target-aware: `general`
  writes `general_notes`, `item` writes the key into `houses.notes` jsonb,
  `info` writes the first label-matching pair in `houses.info`. Uses set
  semantics; a delete action on a key that's already gone is a no-op that
  still marks the suggestion approved (so the audit trail is consistent even
  if the data moved under it).
- New `deny_note_suggestion(uuid, reason default '')` RPC.
- New RLS policy `hns_update_author_seen` + trigger `hns_guard_author_update`:
  an author may update ONLY the `seen_by_author` column on their own already-
  reviewed rows (so "Dismiss" on a denial notice works without opening write
  access to anything else).

**`window.cloud` changes:**
- Added `suggestChange`, `denySuggestion`, `markDenialSeen`, `saveHouseField`,
  `listPendingSuggestions`, `pendingCount`.
- Removed `dismissSuggestion` (supervisor deny). It's replaced by
  `denySuggestion` (RPC, with reason). Withdrawing a suggestion is still the
  unchanged `withdrawSuggestion` delete; `markDenialSeen` is a different thing
  — the author clearing their own ❌ denial notice.
- `suggestNote` now delegates to `suggestChange` (kept as a thin wrapper so
  existing call sites didn't need churn).
- `approveSuggestion` and `saveHouseField` both refresh the houses cache via
  `loadHouses()` on success, so the UI reflects the new official value
  immediately without a manual reload.
- `loadHouses` now also selects `general_notes`.
- `loadRole` pushes the pending-suggestion count to
  `window.applyPendingCount` for supervisors (drives the home-screen badge).

**UI:**
- House Notes screen renders every info pair and item note as an editable
  "field row" — official value, any pending suggestion, any denial notice.
  ✎ suggest/edit; "+ Add item note" opens a picker of unfilled
  `NOTE_KEY_LABELS` keys; "+ Add house info" adds a new label/value pair.
  Supervisors save/remove directly (enforced server-side by the `houses_write`
  RLS policy); techs submit suggestions (enforced by RLS + the RPCs' internal
  role checks). General-notes suggestions now live in the same field-row UI
  and gained deny-with-reason (previously approve-only).
- Checklist screen: each item with a note key gets an inline 📍 line with
  ✎ (edit) or "+ add note", plus pending/denied blocks painted into
  `[data-hn-slot]` spans by `loadChecklistNotes()`, called from `rebuild()`.
- New supervisor-only `#pending` screen, reachable from a home-screen button
  `⏳ Pending changes (N)` carrying the live badge count. Suggestions grouped
  by house, each showing proposed-vs-current, with inline ✓ (approve) /
  ✕ (deny-with-reason) actions.
- Audit trail: reviewed suggestion rows are never deleted, only marked
  approved/denied. Authors can withdraw their own still-pending rows.

**Known limitation (unchanged, not addressed this round):** `house-data.js`
remains a stale offline fallback — it does not reflect notes/info changes
made through this feature. Still fine per HANDOFF precedent; flagged again
for whenever offline-first (Phase 5) is tackled.

**Verification status:** parse checks (headless Chrome, zero console errors)
passed after every task in this feature's build; per-task code review passed.
**The full two-role live-site verification (tech + supervisor driving every
flow end-to-end on the deployed URL, per this feature's plan) is PENDING** —
not done in this session, no owner accounts available here. The owner should
run that pass on the live site after this push finishes deploying (~2 min),
then note the result here.

**Follow-up (same day, final-review fixes):** migration
`0009_set_house_field.sql` adds a `set_house_field` RPC — supervisor direct
edits (info pairs and item notes) now patch the house row server-side from
the database's current data instead of the client's cached copy, closing a
stale-cache-overwrite risk. It also hardens 0008's `hns_guard_author_update`
trigger so `id` joins the list of columns an author can't rewrite on their
own reviewed row. SW cache bumped `v8` → `v9` (`index.html` + `cloud.js`
changed again). Two known Minor gaps deferred, not addressed this round: no
focus restore after a successful editor submit, and a redundant second notes
fetch after a supervisor checklist save.

## STATE AS OF 2026-07-12 (Supabase CLI adopted) — read this first

**The hand-paste-SQL-into-the-dashboard era is over.** The Supabase CLI
(v2.109.1, binary at `%LOCALAPPDATA%\Programs\supabase-cli\supabase.exe`, on
the user PATH — plain `supabase` works in terminals started after 2026-07-12)
is installed, logged in (browser flow; token in Windows credential storage),
and linked to project `eccukivhjgiqwfnosevt`. `supabase init` added
`supabase/config.toml` + `supabase/.gitignore`.

- Migrations 0001–0007 were applied by hand historically, so the remote
  history table was empty; fixed with
  `supabase migration repair --status applied 0001 ... 0007`.
- `supabase db push --dry-run` confirms **remote database is up to date**.
- **New workflow:** write the next numbered file in `supabase/migrations/`,
  then `supabase db push --workdir "c:\Big Dogs Apps\MTX Checklist V1"`.
  No DB password is stored; the CLI authenticates via the owner's access
  token (it creates a temporary login role).
- Never run destructive remote commands (`db reset --linked`, etc.) without
  explicit owner sign-off.

## STATE AS OF 2026-07-11 (Houses menu: collapsible search)

**Small mobile UX fix, committed & pushed (`d021c9f`).** The ☰ Houses
sidebar's search box was always visible, eating a fixed strip of height at
the top and making the 47-house list cramped to scroll on a phone (owner's
complaint). Fixed:

- Search `<input id="houseSearch">` now starts **hidden** — the list gets
  full height by default.
- New **🔍 toggle button** (`#houseSearchToggle`) reveals the box and focuses
  it; tapping again hides it AND clears the filter (`toggleHouseSearch()`), so
  the full list always comes back. `openSidebar()` also resets to
  hidden+cleared on every open, so no stale filter survives a close/reopen.
- Header is now a 3-item flex row: **🔍 far left · "Houses" centered · ✕ far
  right**, both buttons 44×44px min tap targets so they can't be hit by
  accident (owner explicitly asked for the spread). 🔍 carries
  `aria-expanded` for screen readers.
- **The filter logic itself is unchanged** — only *when* the box shows and
  *where* the buttons sit. `renderHouseList()` untouched.
- **No SW cache bump** — deliberate. Owner confirmed **no techs have the app
  yet**, so there's no stale cached copy in the field to force past. Bump the
  cache (currently `route-checklist-v6`) on the *next* change that ships once
  techs are actually using it.

Verified interactively via a standalone Artifact preview (the real markup +
CSS + toggle JS, minus the login gate) — owner tapped it on their phone and
approved. Not driven through the full logged-in app (couldn't headless-drive
past Supabase auth on this box; no Node/Playwright locally, owner works
through GitHub Pages). Behavior is pure DOM toggle, low risk.

## STATE AS OF 2026-07-11 (tech routes)

**Tech routes feature built, pushed, and migration 0007 is RUN in Supabase.**
The `routes` table exists with 4 seeded rows (Route 1–4), all `tech_id` null.
Branch `claude/claude-code-tutorial-5l5ew2` is pushed to origin — and note that
**GitHub Pages deploys from THIS branch, not `main`** (confirmed in repo
Settings → Pages). So pushing the branch updates the live site; no merge to
`main` is needed. Live URL:
`https://tweet-delta.github.io/mtx-sandbox/route-checklist/index.html#home`.

**What the feature does:**
- Supervisor **Routes screen** (☰ Houses → 🗺️ Routes, home button gated by
  `body.is-admin`, which `loadRole()` sets when `role === 'supervisor'`):
  rename routes, assign a tech to each route (dropdown of `role='tech'`
  profiles), and put houses on routes (per-house route dropdown).
- Tech's **new-visit picker is route-scoped** — shows only their route's
  houses, with a **Show all houses…** button to bypass the filter for
  off-route / float-day visits (full read/write, not browse-only).
- Supervisors' picker is **unscoped** (no route → they see all houses, no
  button). **Continue screen & House Notes are unchanged** — both still list
  all in-progress visits / all houses (owner specifically wanted this).
- SW cache bumped to `route-checklist-v6`.

**Interfaces added (actual names — earlier draft of this file was wrong):**
- `cloud.js` admin API on `window.cloud`: `listRoutes()`, `listTechs()`,
  `saveRoute(routeId, {name, techId})`, `setHouseRoute(houseId, routeId|null)`,
  `listHousesForRoutes()`.
- Route scoping is **pushed** from cloud.js: after loadRole → loadHouses →
  `loadMyRoute()`, it calls `window.applyMyHouses(Set|null)`. `null` = show all
  (signed out, supervisor, migration missing, or query failed); empty Set =
  route exists but no houses. `isMissingTable()`/`isMissingColumn()` give
  graceful pre-0007 fallback.
- Migration `0007_tech_routes.sql`: `routes` table (id, name unique, tech_id →
  profiles, created_at) + `houses.route_id` column + RLS (all authenticated
  read routes; supervisor-only write) + 4 seed routes. **No `visit_routes`
  audit table** (an earlier draft of this file wrongly listed one).

**Turnover = one dropdown:** point a route at a new tech in the Routes screen;
all that route's houses follow. New hire: create their account in the Supabase
dashboard (Auto Confirm ON — their `profiles` row auto-creates as `tech` via
the `handle_new_user` trigger in 0001), then assign the route in-app.

**NOT YET verified end-to-end.** Owner (a supervisor) has migration run + a
tech account (`tech1@example.com`, email confirmed via SQL). Next session:
sign in as supervisor on the live site, hard-refresh (Ctrl+Shift+R, may take
two refreshes for the v6 service worker to take over), confirm 🗺️ Routes
button appears, assign tech1 to a route + a few houses, then sign in as tech1
and confirm the picker scopes to those houses and Show-all reveals the rest.
Full checklist in `docs/superpowers/plans/2026-07-11-tech-routes.md` Task 6.

## STATE AS OF 2026-07-11 (existing) — technical detail

**Outside → House Van split (committed & pushed, `f8a656e`).** The owner
confirmed the app renders correctly on both laptop web and the phone PWA, then
asked for a small content reorg:

- `mech-furnace-filter` text simplified from `"Change furnace filter (4" ≈ 90
  days, 1" ≈ 30 days)"` to just `"Change furnace filter"`. The per-house
  `furnaceFilter` note (e.g. Dogwood's "20x25x20") is untouched and still
  renders — only the generic parenthetical was removed.
- New **"House Van"** section added to Shared Spaces, right after Outside and
  before Generator, with 5 items: `van-drive-vehicle` ("Drive house vehicle —
  notify RS of maintenance issues", moved from Outside), `van-qstraint-tracks`
  ("Clean Q-Straint tracks", split out of an old combined item),
  `van-fire-extinguisher` ("Check fire extinguisher", **new**, `dateTracked:
  true`), `van-qstraint-rust` ("Check Q-Straints for rust or damage", new),
  `van-straps` ("Check lap belts, shoulder straps, chest straps", new).
- `out-drive-vehicle` and `out-qstraint-tracks` removed from Outside; every
  other Outside item is unchanged and stayed in place (owner was explicit
  about this — don't touch the rest of Outside).
- `NOTE_RULES`' fire-extinguisher rule narrowed from `/fire extinguisher/i` to
  `/fire extinguisher up to date/i` so the shared per-house `fireExtinguishers`
  note (kitchen/garage/van location text) keeps showing under the Kitchen and
  Common Area items but does **not** duplicate under the new House Van item.
- SW cache bumped to `route-checklist-v5`.

**Deliberately deferred:** splitting each house's single `fireExtinguishers`
note string into three location-specific pieces (Kitchen / Common Area /
House Van) so each item shows only its own relevant location. The owner asked
for this, but with ~30 houses of ambiguous free text (e.g. `"(4) locations"`,
`"(3) Van · west kitchen wall upstairs · under sink in basement apartment"`),
splitting it accurately means guessing which fragment belongs to which item —
that violates the "no guessing" rule, so it was explicitly punted rather than
attempted. **Next session: if picked back up, go house-by-house with the
owner** rather than auto-splitting; don't just start reformatting
`house-data.js` notes.

**Debugging note for next time something "doesn't show up" on the phone
PWA:** the owner reported not seeing a change after a push. Cause was the
service worker — bumping `CACHE` in `sw.js` isn't enough by itself; the old
SW keeps controlling an already-open PWA instance until it's fully closed
(swiped away, not just backgrounded/refreshed) and reopened. Worth checking
early: (1) is this a `file://`/local view or the hosted/PWA view — a local
`file://` open would never reflect a `git push` at all; (2) if hosted, has it
actually been pushed yet (it hadn't been, that one time); (3) full close +
reopen of the PWA, not just a refresh.

## STATE AS OF 2026-07-10 — read this first

**Database is complete: all 47 houses are in Supabase** (owner ran the
18-house batch and confirmed a `select count(*)` of 47). Two permanent SQL
records now: `0004_more_houses.sql` (27 inserts; Dogwood/Roselawn seeded by
0001) and `0005_more_houses.sql` (the 18 new houses added 2026-07-10, plus
two idempotent UPDATEs fixing rows already in the DB — Cummings shed scrub
and Ilex garage-key line). Both are re-runnable (`on conflict (name) do
nothing`).

**Supabase SQL Editor gotcha (cost us a round trip):** Run executes ONLY the
highlighted text if any is selected. A count came back 29 because only part
ran — fix was click into the box to clear the selection, then Run the whole
script.

**Known pitfall that burned us twice:** the owner copies SQL by hand into
the Supabase dashboard. Twice they copied from VS Code's read-only
"Bash tool output" tab (which embeds the shell command that produced the
SQL) → `syntax error at or near "cd"`. Always hand them SQL as a **chat
code block** or point them at a **real file**, and tell them to verify the
first line before Run. Also: every SQL-editor tab runs against the same
database — tabs are scratchpads; only the box's content matters.

### New app features (2026-07-10): home screen, house notes, collapsed sections

Spec: `docs/superpowers/specs/2026-07-10-home-screen-house-notes-design.md`;
plan: `docs/superpowers/plans/2026-07-10-home-screen-house-notes.md`.

- **Sections start collapsed** everywhere (the `open` attr was removed from
  rendered `<details>`, incl. Alarm Counts).
- **Screens + hash router** inside index.html: `#home` (post-login landing:
  New house visit / Continue house visit / House notes), `#visit` (the
  checklist), `#continue`, `#notes` / `#notes/<house>`, `#routes`,
  `#pending`, `#profile` (added 2026-07-13, see that state section). The
  phone back button moves between screens; finishing a survey returns Home.
  `← Home` buttons in every non-home header.
- **Continue screen** merges the local buffer with the tech's cloud
  `in_progress` visits (`cloud.listInProgress()`), de-duplicated via
  `cloudVisitId`; resuming a cloud visit routes through `selectHouse()` +
  `maybeResume()` so nothing is silently wiped.
- **House Notes screen**: read-only house info + 📍 item notes, plus
  `houses.general_notes` with a suggest→approve flow (`house_note_suggestions`
  table). Techs suggest / withdraw their own pending; supervisors edit
  directly, approve (atomic `approve_note_suggestion()` RPC) or dismiss.
  Reviewed rows are kept as audit history. All in migration
  **`0006_house_notes.sql`** — **owner must run it in the dashboard** and
  promote their account to supervisor (one-line update, see 0001's footer);
  until then the notes UI shows a "not set up yet" message (graceful).
- `window.cloud` additions: `role` (null | 'tech' | 'supervisor'; also toggles
  `body.is-admin`), `listInProgress`, `getHouseNotes`, `suggestNote`,
  `withdrawSuggestion`, `approveSuggestion`, `dismissSuggestion`,
  `saveGeneralNotes`.
- SW cache bumped to `route-checklist-v4`. **Not pushed** — owner reviews first.

### Git state

- Branch `claude/claude-code-tutorial-5l5ew2`. Earlier commits (pushed):
  `aaf7929` (9 houses, med-lock scrub, secret guard, battery checkboxes) and
  `75ad4f2` (remaining 18 → 29 total, `0004` at 27 inserts). The 2026-07-10
  batch commit adds 18 more houses (**47 total** in `house-data.js`),
  `0005_more_houses.sql`, the Cummings shed scrub in `0004`, and the guard
  hardening below. Parse check before committing: headless Chrome,
  `HOUSES.length` = 47, no duplicate names.

### Security state (owner confirmed 2026-07-09)

- **Dogwood and Roselawn are FAKE samples. All other 45 houses are REAL.**
  Real door/apt/house/shed/med-lock/alarm/wifi codes and hidden-key
  locations live ONLY in the gitignored `house-codes.local.js` — never in
  tracked files or the DB.
- A fake med-lock combo (a brand name + 4 digits, from the Dogwood/Roselawn
  samples) was scrubbed from tracked files; it remains in git history
  knowingly (fake, so no rotation needed). The literal string is not
  repeated here — it trips the pre-commit guard.
- **⚠ REAL exposure found 2026-07-10 — needs physical rotation.** The
  Cummings **shed combination** was a real code that had been committed and
  pushed in tracked files (`house-data.js` + `0004`). It is now scrubbed from
  tracked files and the DB (via `0005` UPDATE), but **it is still in git
  history** and this repo is public. **Owner TODO: change the physical shed
  combination**, then put the new one in `house-codes.local.js` only. Until
  the physical lock is changed, treat that combo as compromised.
- **Pre-commit secret guard:** `scripts/pre-commit-secret-guard.sh`,
  installed via `bash scripts/install-hooks.sh` — run that once per clone.
  **Hardened 2026-07-10** after the Cummings combo slipped through: a shared
  `CODE` fragment now catches space/comma/plus/dash-separated sequences
  (`01 03 17`, `1, 3, 5`, `2+4 then 3`), and new label patterns (shed, house
  code, basement, office, downstairs, keyless entry, med cabinet/closet,
  alarm code) anchor to the label's own quoted value so innocent lines like
  `["Shed","Yes (no lock needed)"]` don't false-alarm. Self-test: 12/12 bad
  blocked, 0 innocent flagged.
- **Supabase auth:** public sign-ups OFF (verified), min password length 8,
  magic-link fallback on. RLS: any signed-in user reads all houses —
  acceptable because accounts are provisioned manually by the supervisor.

### House-adding pipeline (established; more houses are coming)

The owner pastes SharePoint screenshots of per-house key/value rows.
For each house: (1) entry in `house-data.js` (offline fallback roster);
(2) all codes → `house-codes.local.js` only; (3) INSERT appended to
`0004_more_houses.sql` — safest generated from the parsed `house-data.js`
via headless Chrome so quote-escaping is guaranteed (see this session's
history); (4) verify `house-data.js` parses (headless Chrome,
`HOUSES.length`), stage + run the guard, confirm no codes in tracked
files; (5) hand the owner a paste-ready SQL chat block.

When a screenshot is too tall/large to come through chat (chat downsizes
images past ~2000px, so long house sheets that arrive as two screenshots can
fail), have the owner drop the PNGs in a folder and read them off disk with
the Read tool instead — that bypasses the chat size limit. On this machine
the owner's screenshots land in
`C:\Users\hfwin\OneDrive\Pictures\Screenshots\`.

New migrations: because 0004 was already applied, the 2026-07-10 batch went
in a NEW file `0005_more_houses.sql` rather than editing 0004 (never edit an
applied migration's inserts). Fixes to rows already in the DB are idempotent
UPDATEs in the new file. Generated the same way — headless Chrome runs
`scratchpad/gen-0005.html`, which loads `house-data.js` and prints escaped
SQL.

Conventions: disposal "up yes / down no" → `garbageDisposal: true` + info
note; `roofCoils` = the roof ice-melt cables item (switch location → info);
med-lock brand in the note, combo → codes file; sparse sheets → leave
unstated equipment flags default (shown); smokes/CO replacement dates →
an info "Smokes/CO status" line.

### New app behavior this session

The two battery items (`wh-med-lock-batteries`, `wh-water-alarm-batteries`)
have `withCheckbox: true`: they render a checkbox **and** the Update-date
button. Checking stamps today's date (editable); unchecking clears it;
"done" still means "has a `doneOn` date", so badges/progress/cloud save
are unchanged. The other 4 `dateTracked` items are deliberately unchanged.

## What this app is

A field checklist app for **group-home maintenance visits** (Minnesota
group homes). The buildings are duplex-style: a **Resident level** and an
**RS (Residential Supervisor) unit**, each with their own kitchen and
bathroom(s); the mechanical room, garage, outside, and generator are
**shared**. Built from a real Excel route checklist the user's team uses.

A maintenance tech opens it on a phone or computer during a house visit,
picks the house, checks items off area by area, flags problems, records
alarm counts, and fills out the end-of-visit survey in a popup window.

## Where it lives

- **Repo:** `tweet-delta/mtx-sandbox`
- **Working branch:** `claude/claude-code-tutorial-5l5ew2`
- **App files (the master copy):**
  - `route-checklist/index.html` — the app (HTML + CSS + JS, no deps)
  - `route-checklist/house-data.js` — per-house roster (loaded via
    `<script src>` so it works from `file://`)
  - `route-checklist/house-codes.local.js` — door/entry codes.
    **Gitignored, on-device only, never commit.** Optional; app works
    without it. Copy manually to devices that should show codes.
- There is also a separate earlier practice app at `home-upkeep/index.html`
  (a generic homeowner maintenance tracker — not the work one).

## Current features

- Sticky header: **Your name** (persists across visits), House, visit
  date, plus a progress bar.
- **☰ Houses sidebar**: house picker + "House info" panel (paint location,
  attic access, door codes if the local codes file is present). Search is
  **collapsed behind a 🔍 toggle** in the header (see the 2026-07-11 state
  section) — the list shows full-height by default. Picking a house tailors
  the checklist (see below).
- **Per-house tailoring** (data in `house-data.js`):
  - 📍 inline notes under matching items (fire extinguisher locations,
    furnace filter size, shutoff locations, med lock type, etc.).
  - Equipment flags set to `false` hide items (sump pump, roof coils,
    garbage disposal, HE washers…) or whole sections (Generator).
  - Houses so far: **47** — Dogwood + Roselawn (fake samples) plus 45 real
    houses transcribed from the owner's SharePoint house-notes screenshots.
    First 27 (through 2026-07-09): 140th Lane East/West, 16th Avenue, 92nd
    Crescent, Amble, Barclay, Bicentennial, Boutwell, Brooks, Co. Rd. B2,
    Crestridge, Cummings, Dale Court, Dawn, Fallgold, Fox Run Bay, Fulham,
    Hillcrest, Ilex, James, Lancaster, Larch, Lydia Ave, Lydia West,
    Magnolia, McAfee, McMenemy. Added 2026-07-10: Alta Vista, Jennifer
    Court, Oakwood, Regent, Riverdale, Robin Ave, Robin Court, Sherwood
    Place, Skycroft, Sunbury, Tiller Lane, Toledo, Trenton Lane, Valders,
    Oregon Brooklyn Park (OBP), Redwood, Oregon Golden Valley (OGV),
    Riverton. The logged-in app loads houses from Supabase
    (`cloud.js` → `applyHouses()`); `house-data.js` is the logged-out
    fallback — keep both in sync when adding houses.
- Sections grouped by area: Whole House, Resident Level (Kitchen,
  Bathroom #1, Bathroom #2, Bedrooms), RS Unit (Kitchen, Bathroom),
  Shared Spaces (Mechanical Room, Common Areas, Outside, **House Van**,
  Generator, Maintenance Cabinet Stock), Visit Wrap-Up. Each section is
  collapsible and shows its own progress count.
- Two kinds of checklist entries:
  - **Action items** = simple checkboxes (e.g. "Sharpen knives").
  - **Yes/No questions** = Yes/No buttons. Each question has a "bad"
    answer; picking it flags the item red and reveals a required
    "reason why / what needs follow-up" box.
    - "Anything wrong?" questions → **Yes** is bad.
    - "Working properly?" questions → **No** is bad.
- Any item also has an optional freeform **Note** button.
- **Alarm Counts** block (Resident water/CO2, RS water/CO2) placed after
  Common Areas, matching the paper form.
- **Visit survey** button opens a modal `<dialog>` mirroring the real
  "Maintenance House Visit Survey" MS form (name/date/house + 7
  questions). Answers start blank; questions with a related checklist
  answer get an editable suggestion (snow/ice ← sidewalk-hazard item,
  live-in condition ← flagged RS items, other concerns ← all flagged
  issues). **Save & Send** validates name/date/house and saves;
  **actual sending to SharePoint is a TODO** (marked in code) — the
  survey currently lives in a SharePoint/MS Forms list the user's team
  submits after each visit.
- **No "New visit" button** (removed by owner request). Clearing for the next
  house happens two ways instead: (1) a successful survey **Save & Send** clears
  the screen, and (2) picking a **different house** starts it fresh. Switching
  away from a house that has unsaved entries **confirms first** (with a nudge to
  Save progress) so a tech's in-progress work is never silently wiped —
  `selectHouse()` owns this. The tech's name persists across all of it.
- Progress saves automatically in the browser (localStorage).
- **Cloud visit history (Supabase):** survey **Save & Send** now writes the
  completed visit to `visits` + `visit_items` (idempotent — a second send
  updates the same row via `cloudVisitId` kept in local state). Requires
  `supabase/migrations/0002_visit_history.sql` to be applied.
- **Periodic jobs + due badges:** items with `everyMonths` (currently only
  `wh-water-alarm-batteries`) show a badge with when they were last done at
  this house and when they're next due, read from cloud history. Not-due items
  are dimmed and drop out of the progress totals (doing them early still counts
  and re-stamps the date).
- **Generator N/A:** one button marks the whole Generator section N/A
  (stored per-item as `na: true`, saved to the DB as answer `'na'`).
- **Up-front house picker:** when no house is chosen, a search-driven picker
  (type-to-filter) appears above the checklist; sections render open by default.
- **Phone layout:** under 600px the Yes/No buttons become two big full-width
  thumb targets on their own row and the Note button collapses to its ✎ icon.
- **Date-tracked jobs (`dateTracked: true`):** med-lock batteries, water-alarm
  batteries, both fire extinguishers, detector dates, furnace filter. No
  checkbox — an **Update date** button opens a date picker so the tech records
  the ACTUAL date done (defaults to today, editable). The recorded date drives
  the badge and is stored in `visit_items.done_on`. Add `everyMonths` too (as
  water-alarm has) and the badge also shows due/not-due.
- **Water-temp items (`tempInput: true`):** `rb1-water-temp` / `rb2-water-temp`
  are now checkboxes that reveal a number field for the highest reading, stored
  in `visit_items.value` (number only — no separate date, per owner).
- **Many former Yes/No items are now plain checkboxes** (owner request), keeping
  their stable keys: fixture bulbs, wall/patching, plungers, attic, both
  cabinets & drawers, both felt protectors, all three faucet & showerhead, and
  all five Bedroom items. Their stored shape changed from `answer` to `done`.
- **Save progress** button: writes an `in_progress` visit to the cloud so it can
  be resumed on another day/device. Picking a house checks for an in-progress
  cloud visit and offers to resume it (confirm dialog, won't silently clobber).
  Save & Send remains the finalize (`completed`).
- **Migration `0003_dated_items_and_temps.sql`** (adds `done_on`, `value`
  columns) should be run in the dashboard. **Until it is, the cloud layer
  degrades gracefully:** `cloud.js` detects the missing columns
  (`isMissingColumn`) and retries saves/reads without `done_on`/`value`, so
  visits still save. Dates/temps stay in the on-device buffer and sync on a
  later save once the columns exist; the app shows a "(Dates/temps sync once
  the DB update is applied.)" toast in that state.

## How it's built (for whoever edits next)

- All checklist content is in the `GROUPS` array near the top of the
  `<script>`; `COUNTS` = alarm count fields; `SURVEY` = survey questions.
- Per-house logic: `NOTE_RULES` maps item text (regex) → `notes` key
  and/or `equipment` flag; `SECTION_FLAGS` maps section title →
  equipment flag. House shape is documented at the top of
  `house-data.js`.
- Survey suggestions come from `surveySuggestions()`.
- State is stored under localStorage key `route-checklist-v3`
  (`route-checklist-name` for the tech's name). If the data model
  changes in a breaking way, bump the version string.
- Every checklist item has a **stable `key`** (e.g. `rk-sharpen-knives`),
  defined inline in the `GROUPS` data. Saved answers/notes are stored
  under that key, so inserting or reordering items no longer scrambles
  existing answers. Keys must stay unique and must not be reused for a
  different item. (Before v3 the ids were positional `g#s#i#`, which
  shifted every answer below any inserted item — that's now fixed.)

## Known limitations / things a user should know

- **State is per-browser.** A visit filled out on the phone will NOT
  appear on the computer, and vice versa. (Needs a backend to fix.)
- **Survey "Send" doesn't send yet** — needs a SharePoint/Power Automate
  endpoint from the user. Their survey list:
  `acrhomes123.sharepoint.com/departments/maintenance` (House Notes list
  also lives there — couldn't be read directly; Chrome extension wasn't
  connected).
- Door codes must never be pushed — the repo is public. Keep them in
  `house-codes.local.js` only.
- The user's raw house notes live locally in
  `Desktop/mtx expl/*.xlsx` (Dogwood, roselawn) — outside the repo.
- A stray empty git repo sits at `route-checklist/MTX Route/` locally
  (user-created, untracked; left alone).

## Owner requests captured but NOT built yet (as of 2026-07-07)

- ~~**Start flow**~~ → BUILT 2026-07-10 (Home screen + House Notes; see the
  state section above). "Requests" remains an undefined future feature — ask
  the owner before designing it.
- **Walk-order restructure:** the owner says the current order (All Areas
  first, then rooms) makes a tech "run around a lot"; wants the checklist to
  follow the order techs actually walk a house. Waiting on the owner to
  provide that order.
- **More periodic jobs:** owner will list which jobs are due every N months
  (besides yearly water-alarm batteries); add `everyMonths` to each.

## Possible next steps (not yet done)

- Wire **Save & Send** to SharePoint (Power Automate flow or REST).
- Add more houses to `house-data.js` (user will drop more xlsx files;
  30+ houses expected eventually).
- Per-house bathroom count (hide Bathroom #2) via an equipment flag.
- A field to record the actual water-temp reading (currently just a Y/N).
- Multi-device sync (would need a backend).
