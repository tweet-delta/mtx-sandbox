# Route Checklist App — Handoff Notes

Context for continuing work in a new session. Point a fresh Claude Code
session at this file: "Read route-checklist/HANDOFF.md and let's continue."

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
  - Houses so far: **Dogwood**, **Roselawn** (from the user's xlsx notes;
    source files were key/value sheets, one per house).
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
- **New visit** button clears everything for the next house.
- Progress saves automatically in the browser (localStorage).

## How it's built (for whoever edits next)

- All checklist content is in the `GROUPS` array near the top of the
  `<script>`; `COUNTS` = alarm count fields; `SURVEY` = survey questions.
- Per-house logic: `NOTE_RULES` maps item text (regex) → `notes` key
  and/or `equipment` flag; `SECTION_FLAGS` maps section title →
  equipment flag. House shape is documented at the top of
  `house-data.js`.
- Survey suggestions come from `surveySuggestions()`.
- State is stored under localStorage key `route-checklist-v2`
  (`route-checklist-name` for the tech's name). If the data model
  changes in a breaking way, bump the version string.
- Item IDs are positional (`g{group}s{section}i{item}`), so
  adding/removing checklist items shifts saved answers for in-progress
  visits.

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

## Possible next steps (not yet done)

- Wire **Save & Send** to SharePoint (Power Automate flow or REST).
- Add more houses to `house-data.js` (user will drop more xlsx files;
  30+ houses expected eventually).
- Per-house bathroom count (hide Bathroom #2) via an equipment flag.
- A field to record the actual water-temp reading (currently just a Y/N).
- Multi-device sync (would need a backend).
