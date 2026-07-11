# Route Checklist App — Handoff Notes

Context for continuing work in a new session. Point a fresh Claude Code
session at this file: "Read route-checklist/HANDOFF.md and let's continue."

## STATE AS OF 2026-07-11 (tech routes) — read this first

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
  checklist), `#continue`, `#notes` / `#notes/<house>`. The phone back button
  moves between screens; finishing a survey returns Home. `← Home` buttons in
  every non-home header.
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
- **☰ Houses sidebar**: searchable house picker + "House info" panel
  (paint location, attic access, door codes if the local codes file is
  present). Picking a house tailors the checklist (see below).
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
