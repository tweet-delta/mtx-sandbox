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
checks items off area by area, flags problems, records alarm counts, and
copies a text report to paste into the site survey / email to Steve.

## Where it lives

- **Repo:** `tweet-delta/mtx-sandbox`
- **Working branch:** `claude/claude-code-tutorial-5l5ew2`
- **App file (the master copy):** `route-checklist/index.html`
  (single self-contained HTML file — HTML + CSS + JS, no dependencies)
- **Live artifact link:** https://claude.ai/code/artifact/96afb5f0-1ede-4db8-b62e-12d0f5c4ccf1
- There is also a separate earlier practice app at `home-upkeep/index.html`
  (a generic homeowner maintenance tracker — not the work one).

## Current features

- Sticky header: House name + visit date, plus a progress bar.
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
- **Copy visit report** button: builds a plain-text summary — house, date,
  completion count, alarm counts, all flagged ISSUES with reasons, other
  notes, and a NOT COMPLETED list — and copies it to the clipboard.
- **New visit** button clears everything for the next house.
- Progress saves automatically in the browser (localStorage).

## How it's built (for whoever edits next)

- All content is in the `GROUPS` array near the top of the `<script>`.
  - A plain string = action item (checkbox).
  - An object `{ q: "...", bad: "yes" }` or `{ q: "...", bad: "no" }` =
    yes/no question. `bad` marks which answer triggers the red flag +
    reason box.
- Alarm count fields are in the `COUNTS` array.
- State is stored under localStorage key `route-checklist-v2`. If the
  data model changes in a breaking way, bump that version string.

## Known limitations / things a user should know

- **State is per-browser.** A visit filled out on the phone will NOT
  appear on the computer, and vice versa. Each device keeps its own copy.
  (Fixing this would require a real backend / sync — not built yet.)
- The downloaded HTML file and the artifact link are separate copies;
  editing one doesn't update the other. The repo file is the master.
- A few structural guesses were made from the Excel sheet and confirmed
  with the user; "Common Areas" is currently under Shared Spaces.

## Possible next steps (not yet done)

- Optionally handle houses with only one bathroom (hide Bathroom #2).
- A field to record the actual water-temp reading (currently just a Y/N).
- Export/share the report other ways (email link, save as file).
- Multi-device sync (would need a backend).
- Per-house presets (different houses have different equipment).
