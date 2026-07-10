# Route Checklist App — Handoff Notes

Context for continuing work in a new session. Point a fresh Claude Code
session at this file: "Read route-checklist/HANDOFF.md and let's continue."

## STATE AS OF 2026-07-09 — read this first

**Database is complete: all 29 houses are in Supabase** (owner ran the
18-house INSERT and confirmed). The permanent SQL record is
`supabase/migrations/0004_more_houses.sql` (27 inserts; Dogwood/Roselawn
are seeded by 0001). The temp paste-helper `NEW-18-houses.sql` has been
deleted.

**Known pitfall that burned us twice:** the owner copies SQL by hand into
the Supabase dashboard. Twice they copied from VS Code's read-only
"Bash tool output" tab (which embeds the shell command that produced the
SQL) → `syntax error at or near "cd"`. Always hand them SQL as a **chat
code block** or point them at a **real file**, and tell them to verify the
first line before Run. Also: every SQL-editor tab runs against the same
database — tabs are scratchpads; only the box's content matters.

### Git state

- Branch `claude/claude-code-tutorial-5l5ew2`. As of 2026-07-10 all house
  work is committed AND pushed (owner approved): commit `aaf7929`
  (9 houses, med-lock scrub, secret guard, battery checkboxes) plus a
  follow-up commit adding the remaining 18 houses (29 total in
  `house-data.js`), `0004_more_houses.sql` at 27 inserts, and this handoff
  update. Working tree clean. Parse check before committing: headless
  Chrome, `HOUSES.length` = 29, no duplicate names.

### Security state (owner confirmed 2026-07-09)

- **Dogwood and Roselawn are FAKE samples. All other 27 houses are REAL.**
  Real door/apt/house/shed/med-lock/alarm/wifi codes live ONLY in the
  gitignored `house-codes.local.js` — never in tracked files or the DB.
- A fake med-lock combo (a brand name + 4 digits, from the Dogwood/Roselawn
  samples) was scrubbed from tracked files; it remains in git history
  knowingly (fake, so no rotation needed). The literal string is not
  repeated here — it trips the pre-commit guard.
- **Pre-commit secret guard:** `scripts/pre-commit-secret-guard.sh`,
  installed via `bash scripts/install-hooks.sh` — run that once per clone.
  Tested: blocks every code shape in use (incl. dash codes like 5-3-1),
  passes clean files.
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
  - Houses so far: **29** — Dogwood + Roselawn (fake samples) plus 27 real
    houses (140th Lane East/West, 16th Avenue, 92nd Crescent, Amble,
    Barclay, Bicentennial, Boutwell, Brooks, Co. Rd. B2, Crestridge,
    Cummings, Dale Court, Dawn, Fallgold, Fox Run Bay, Fulham, Hillcrest,
    Ilex, James, Lancaster, Larch, Lydia Ave, Lydia West, Magnolia,
    McAfee, McMenemy), transcribed from the owner's SharePoint house-notes
    screenshots. The logged-in app loads houses from Supabase
    (`cloud.js` → `applyHouses()`); `house-data.js` is the logged-out
    fallback — keep both in sync when adding houses.
- Sections grouped by area: Whole House, Resident Level (Kitchen,
  Bathroom #1, Bathroom #2, Bedrooms), RS Unit (Kitchen, Bathroom),
  Shared Spaces (Mechanical Room, Common Areas, Outside, Generator,
  Maintenance Cabinet Stock), Visit Wrap-Up. Each section is
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

- **Start flow:** a page before the checklist — who you are → what you want
  (checklist / requests / house notes) → checklist. "Requests" and "house
  notes" are undefined features; ask the owner before designing.
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
