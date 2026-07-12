# Level-Specific Note Labels Implementation Plan

> **For agentic workers:** REQUIRED SUB-SKILL: Use superpowers:subagent-driven-development (recommended) or superpowers:executing-plans to implement this plan task-by-task. Steps use checkbox (`- [ ]`) syntax for tracking.

**Goal:** Rewrite every single-level "Up/Upstairs/Down/Downstairs" label in the per-item house notes to "Residents (up):" / "RS (down):" form (flipped for the five RS-on-top houses; three-level labels at Fallgold), in the live database and the offline fallback.

**Architecture:** Pure data change — migration `0011_level_labels.sql` merges new text into `houses.notes` (jsonb `||`, one UPDATE per house, only listed keys change), and `route-checklist/house-data.js` gets the identical strings. No app code changes. Spec with the owner-approved before→after table: `docs/superpowers/specs/2026-07-12-level-label-notes-design.md`.

**Tech Stack:** Postgres jsonb (Supabase), Supabase CLI, vanilla JS data file.

## Global Constraints

- The spec's table is owner-approved text — apply it **verbatim**. Do not rephrase, fix typos, or improve wording beyond the spec.
- Migrations applied ONLY with `supabase db push` (CLI full path if not on PATH: `$LOCALAPPDATA/Programs/supabase-cli/supabase.exe`). Never hand-paste SQL into the dashboard.
- Repo is PUBLIC — no secrets, no door codes.
- **Path-limit every commit** (`git commit <paths> -m …`): a parallel session works in this repo and may stage files; a bare `git commit` after `git add` can sweep them in (this happened once already).
- Commit messages end with `Co-Authored-By: Claude Fable 5 <noreply@anthropic.com>`.
- Do NOT push until the final task says to (GitHub Pages deploys this branch).
- No test runner exists; verification = headless-Chrome parse check + `supabase migration list` + the owner's live drive (spec's Verification section).

---

### Task 1: Migration 0011 — level labels in `houses.notes`

**Files:**
- Create: `supabase/migrations/0011_level_labels.sql`

**Interfaces:**
- Consumes: `public.houses` (name-unique rows; `notes` jsonb) — migrations 0001–0010 applied.
- Produces: the new note strings in the live DB. Task 2 copies these exact strings into `house-data.js`.

- [ ] **Step 1: Write the migration file**

Create `supabase/migrations/0011_level_labels.sql` with exactly:

```sql
-- ----------------------------------------------------------------------------
-- 0011_level_labels.sql — level-specific note labels (owner-approved rewrite).
--
-- "Up/Upstairs/Down/Downstairs" note labels become "Residents (up):" /
-- "RS (down):" — flipped at the five RS-on-top houses (92nd Crescent, Amble,
-- Fallgold, McAfee, Sherwood Place); Fallgold uses Residents (1st) /
-- RS (2nd) / Basement (shared). Full before→after table reviewed by the
-- owner: docs/superpowers/specs/2026-07-12-level-label-notes-design.md.
--
-- jsonb || merges TOP-LEVEL keys: only the keys listed per house change;
-- every other note on the row is untouched. Safe to re-run (idempotent
-- overwrites). A renamed house simply no-ops its UPDATE.
-- ----------------------------------------------------------------------------

update public.houses set notes = notes || '{"fireExtinguishers": "Residents (up): laundry closet · RS (down): mech room · Garage: by main door · One in the van", "fridgeCoils": "Residents (up): front · RS (down): back", "dryerVents": "Residents (up): NW side · RS (down): NE side under deck"}'::jsonb where name = 'Dogwood';

update public.houses set notes = notes || '{"fireExtinguishers": "Residents (up): kitchen sink, van, garage · RS (down): kitchen sink"}'::jsonb where name = 'Roselawn';

update public.houses set notes = notes || '{"fireExtinguishers": "Residents (up): back hall by the pantry · RS (down): storage room off the kitchen, right around the corner", "fridgeCoils": "Residents (up): front of fridge · RS (down): front of fridge"}'::jsonb where name = '140th Lane East';

update public.houses set notes = notes || '{"fireExtinguishers": "Residents (up): kitchen, on the wall above the garbage cans · RS (down): kitchen, on wall by office", "fridgeCoils": "Residents (up): front of the fridge · RS (down): back of the fridge"}'::jsonb where name = '140th Lane West';

-- RS on top ↓
update public.houses set notes = notes || '{"fireExtinguishers": "Residents (down): kitchen, far right cabinet; one in the van · RS (up): one under the sink, one in laundry room", "dryerVents": "RS (up): back of the house by patio · Residents (down): by front door"}'::jsonb where name = '92nd Crescent';

-- RS on top ↓
update public.houses set notes = notes || '{"dryerVents": "Residents (down): east side of house · RS (up): back of house, middle vent next to porch (not under it); tall ladder needed"}'::jsonb where name = 'Amble';

update public.houses set notes = notes || '{"dryerVents": "Residents (up): above patio door"}'::jsonb where name = 'Barclay';

update public.houses set notes = notes || '{"fireExtinguishers": "(3) Van · Residents (up): west kitchen wall · RS (down): under the sink in the basement apartment"}'::jsonb where name = 'Bicentennial';

update public.houses set notes = notes || '{"fireExtinguishers": "(3) Van · Residents (up): under the sink · RS (down): under the sink"}'::jsonb where name = 'Boutwell';

update public.houses set notes = notes || '{"fireExtinguishers": "(5) Van · Residents (up): hallway, under sink, garage · RS (down): under sink", "dryerVents": "Residents (up): on the deck · RS (down): by the fence for the trash, on the house"}'::jsonb where name = 'Co. Rd. B2';

update public.houses set notes = notes || '{"dryerVents": "Residents (up): through the roof · RS (down): back under the deck (very long run; the RS dryer may auto-shut-off — coordinate with the live-in to keep it running while checking)"}'::jsonb where name = 'Crestridge';

update public.houses set notes = notes || '{"fireExtinguishers": "(2) Residents (up): under the kitchen sink · RS (down): under the kitchen sink", "dryerVents": "RS (down): south side of the house · Residents (up): on the roof"}'::jsonb where name = 'Dale Court';

update public.houses set notes = notes || '{"dryerVents": "Residents (up): east deck · RS (down): behind the house on the west side, under the deck where the brick blocks jut out, on top (not the disconnected one tucked way under the deck)"}'::jsonb where name = 'Dawn';

-- Three levels: Residents 1st, RS 2nd, shared basement ↓
update public.houses set notes = notes || '{"fireExtinguishers": "Residents (1st): on the cabinet in the kitchen · RS (2nd): laundry closet between washer and dryer · Basement (shared): bottom of the stairs · Van", "fridgeCoils": "Residents (1st): front side · RS (2nd): back of refrigerator", "atticAccess": "Attic access — RS (2nd): apartment hallway · Residents (1st): office area (for the garage) and in the hallway", "dryerVents": "RS (2nd): back of the house above the sunroom · Residents (1st): back of the house by the patio"}'::jsonb where name = 'Fallgold';

update public.houses set notes = notes || '{"fireExtinguishers": "Residents (up): kitchen wall · RS (down): attached to wall · in house van"}'::jsonb where name = 'Hillcrest';

update public.houses set notes = notes || '{"fireExtinguishers": "(4) Van · Residents (up): right of fridge · RS (down): just inside utility room and under the kitchen sink"}'::jsonb where name = 'Ilex';

update public.houses set notes = notes || '{"fireExtinguishers": "(4) Residents (up): normal and grease under the sink · RS (down): under the sink · van"}'::jsonb where name = 'Jennifer Court';

update public.houses set notes = notes || '{"fireExtinguishers": "Residents (up): garage · RS (down): mechanical room", "dryerVents": "Residents (up): north end of the house, by the garbage cans · RS (down): east side of the house in the back yard"}'::jsonb where name = 'Lancaster';

update public.houses set notes = notes || '{"fireExtinguishers": "(4) Inside garage by back door · van · Residents (up): kitchen behind the door · RS (down): under the sink"}'::jsonb where name = 'Lydia Ave';

update public.houses set notes = notes || '{"fireExtinguishers": "(4) Van · Residents (up): kitchen, laundry · RS (down): under kitchen sink"}'::jsonb where name = 'Lydia West';

update public.houses set notes = notes || '{"fireExtinguishers": "Residents (up): laundry room by the washing machine · RS (down): one in mechanical room, one under the kitchen sink", "dryerVents": "Residents (up): under deck · RS (down): (see house)"}'::jsonb where name = 'Magnolia';

-- RS on top ↓
update public.houses set notes = notes || '{"dryerVents": "Residents (down): south side · RS (up): back of house"}'::jsonb where name = 'McAfee';

update public.houses set notes = notes || '{"fireExtinguishers": "Residents (up): under kitchen sink, cleaning closet (by front door), laundry · RS (down): office, furnace room · Van"}'::jsonb where name = 'McMenemy';

update public.houses set notes = notes || '{"fireExtinguishers": "(4) Van · Residents (up): under sink, laundry · RS (down): (not filled in on the sheet)"}'::jsonb where name = 'Oakwood';

update public.houses set notes = notes || '{"fireExtinguishers": "Residents (up): closet in dining room · RS (down): in the cabinet under the island", "dryerVents": "Residents (up): on the south wall, under the ramp to the deck · RS (down): north wall"}'::jsonb where name = 'Regent';

update public.houses set notes = notes || '{"fireExtinguishers": "(6) Van · Residents (up): kitchen (hanging on the wall), laundry (on the wall to the left) · RS (down): under kitchen sink, closet in the second living room (just right of laundry room) · 1 in the garage", "dryerVents": "Both on the south side. Residents (up): right of the faucet in the corner · RS (down): left of the faucet"}'::jsonb where name = 'Riverdale';

update public.houses set notes = notes || '{"fireExtinguishers": "Residents (up): kitchen and hallway · In the van · RS (down): under sink and furnace room", "dryerVents": "Residents (up): vented through the roof · RS (down): vent comes out on the front ramp"}'::jsonb where name = 'Robin Ave';

-- RS on top ↓
update public.houses set notes = notes || '{"fireExtinguishers": "Residents (down): left of the sink · RS (up): under the sink · one mounted on the garage wall · one in the house van", "atticAccess": "Attic access — RS (up): laundry room; will need the 6 ft ladder"}'::jsonb where name = 'Sherwood Place';

update public.houses set notes = notes || '{"fireExtinguishers": "Garage, under kitchen sink, van, RS apartment (down), and laundry room"}'::jsonb where name = 'Tiller Lane';

update public.houses set notes = notes || '{"fireExtinguishers": "(3) Residents (up): laundry closet · RS (down): under kitchen sink · One in the van", "fridgeCoils": "Residents (up): front of fridge · RS (down): back of fridge", "dryerVents": "Residents (up): on the back of the house · RS (down): on the front of the house"}'::jsonb where name = 'Toledo';

update public.houses set notes = notes || '{"fireExtinguishers": "Residents (up): above kitchen sink on cabinet · Van: on passenger seat · RS (down): under kitchen sink", "dryerVents": "Residents (up): right outside the garage door · RS (down): right outside the garage door"}'::jsonb where name = 'Valders';

update public.houses set notes = notes || '{"fireExtinguishers": "Residents (up): in the kitchen by the cabinet; also one in the garage · RS (down): under the kitchen sink", "dryerVents": "Residents (up): on the roof · RS (down): on the east end of the house"}'::jsonb where name = 'Oregon Brooklyn Park (OBP)';

update public.houses set notes = notes || '{"dryerVents": "RS (down): comes out at the front of the house under the kitchen window · Residents (up): on the north side of the house, up high"}'::jsonb where name = 'Redwood';

update public.houses set notes = notes || '{"fireExtinguishers": "Residents (up): laundry closet and in kitchen next to fridge · RS (down): under kitchen sink, van, garage", "fridgeCoils": "Residents (up): front/back · RS (down): front/back", "dryerVents": "Residents (up): roof · RS (down): on north side of the house"}'::jsonb where name = 'Oregon Golden Valley (OGV)';

update public.houses set notes = notes || '{"fireExtinguishers": "(3) One in the van · Residents (up): in the cabinet right of the fridge · RS (down): in the cabinet just right of the dishwasher", "dryerVents": "Residents (up): super short run straight out on the west side of the house · RS (down): (not filled in on the sheet)"}'::jsonb where name = 'Riverton';
```

- [ ] **Step 2: Cross-check the SQL against the spec table**

Open `docs/superpowers/specs/2026-07-12-level-label-notes-design.md` and verify, house by house, that every "New:" line in the spec appears verbatim in the migration (35 house UPDATEs; Dogwood, Fallgold, Toledo, OGV carry 3–4 keys each). Verify the five RS-on-top houses (92nd Crescent, Amble, Fallgold, McAfee, Sherwood Place) use `RS (up)` / `Residents (down)` (Fallgold: 1st/2nd/shared). Any mismatch = fix the migration to match the spec, never the reverse.

- [ ] **Step 3: Push and verify**

Run: `supabase db push` (or via full path). Expected: lists `0011_level_labels.sql`, finishes with `Finished supabase db push.`
Run: `supabase migration list`. Expected: `0011` present in both Local and Remote.

- [ ] **Step 4: Commit (path-limited)**

```bash
git commit supabase/migrations/0011_level_labels.sql -m "feat: migration 0011 — level-specific note labels (Residents/RS + direction)

Co-Authored-By: Claude Fable 5 <noreply@anthropic.com>"
```

(Untracked files can't be committed by path alone — run `git add supabase/migrations/0011_level_labels.sql` first, then the path-limited commit.)

---

### Task 2: `house-data.js` sync + service-worker bump

**Files:**
- Modify: `route-checklist/house-data.js` (the `notes` values of the 35 houses listed in Task 1)
- Modify: `route-checklist/sw.js:7` (cache `route-checklist-v11` → `route-checklist-v12`)

**Interfaces:**
- Consumes: Task 1's migration — it holds every new string verbatim. The spec's table holds every old ("Now") string verbatim.
- Produces: an offline fallback consistent with the DB.

- [ ] **Step 1: Apply the same 35 houses' note rewrites**

For each house UPDATE in Task 1's SQL, find that house's entry in `route-checklist/house-data.js` (entries look like `name: "Dogwood",` followed by a `notes: { … }` object) and replace each listed key's value with the new string from the migration, exactly. The current value in the file should match the spec table's "Now" text — if a value does NOT match (file drifted), stop and report it instead of guessing; do not force a replacement.

Notes:
- JS strings in this file use double quotes; the new strings contain no double quotes or backslashes, so no escaping is needed.
- Keys that a house's `house-data.js` entry doesn't have (rare drift) are also a stop-and-report case.

- [ ] **Step 2: Verify no single-level labels remain in the changed values**

Run: `grep -nE '"(fireExtinguishers|fridgeCoils|dryerVents|atticAccess)": "[^"]*(Upstairs:|Downstairs:|Up:|Down:)' route-checklist/house-data.js`
Expected: no output. (Both-level phrases like "up and down" and descriptive uses don't match this pattern and correctly remain.)

- [ ] **Step 3: Bump the service-worker cache**

`route-checklist/sw.js` line 7: `const CACHE = "route-checklist-v11";` → `"route-checklist-v12"` (house-data.js is in the cached shell).

- [ ] **Step 4: Parse check**

Run in Git Bash:
```bash
"$LOCALAPPDATA/Google/Chrome/Application/chrome.exe" --headless=new --disable-gpu --no-first-run --allow-file-access-from-files --enable-logging=stderr --v=0 --virtual-time-budget=5000 --dump-dom "file:///C:/Big%20Dogs%20Apps/MTX%20Checklist%20V1/route-checklist/index.html" > /dev/null 2> /tmp/cc.txt; grep -i CONSOLE /tmp/cc.txt | grep -iv manifest
```
Expected: no output (a `SyntaxError` from house-data.js means a broken string — fix before committing).

- [ ] **Step 5: Commit (path-limited)**

```bash
git commit route-checklist/house-data.js route-checklist/sw.js -m "feat: level-specific note labels in the offline house roster; SW v12

Co-Authored-By: Claude Fable 5 <noreply@anthropic.com>"
```

---

### Task 3: Ship — HANDOFF note, push, owner verification handoff

**Files:**
- Modify: `route-checklist/HANDOFF.md` (append to the newest "STATE AS OF 2026-07-12" section)

**Interfaces:**
- Consumes: Tasks 1–2 committed; live URL `https://tweet-delta.github.io/mtx-sandbox/route-checklist/index.html#home`.

- [ ] **Step 1: HANDOFF note**

Append to the newest 2026-07-12 section in `route-checklist/HANDOFF.md`, in its existing voice, roughly: migration 0011 rewrote single-level note labels to `Residents (up):` / `RS (down):` (flipped at 92nd Crescent, Amble, McAfee, Sherwood Place; Fallgold = Residents (1st)/RS (2nd)/Basement (shared)); `house-data.js` synced; SW v12; the House info panel (`houses.info`) intentionally NOT touched (possible follow-up); owner-approved table in `docs/superpowers/specs/2026-07-12-level-label-notes-design.md`; owner's live spot-check pending.

- [ ] **Step 2: Commit (path-limited) and push**

```bash
git commit route-checklist/HANDOFF.md -m "docs: handoff notes for level-specific note labels (0011)

Co-Authored-By: Claude Fable 5 <noreply@anthropic.com>"
git push
```

(The push also carries the parallel session's already-committed Emmert commit and the spec/plan docs — expected; the Emmert DB change is already applied.)

- [ ] **Step 3: Live smoke check**

Wait for Pages (the SW version is the deploy marker):
```bash
until curl -s "https://tweet-delta.github.io/mtx-sandbox/route-checklist/sw.js" | grep -q "route-checklist-v12"; do sleep 15; done; echo LIVE
```
Then confirm the deployed roster carries the new labels:
```bash
curl -s "https://tweet-delta.github.io/mtx-sandbox/route-checklist/house-data.js" | grep -c "Residents (up):"
```
Expected: a number ≥ 25 (most houses), and `grep -c "RS (up):"` ≥ 4 (the flipped houses).

- [ ] **Step 4: Hand the owner the spot-check list**

Report to the owner (do not claim verified): sign in and open — 140th Lane West (the screenshot house: fridge coils now `Residents (up): front of the fridge · RS (down): back of the fridge`), McAfee (dryer vents flipped: `RS (up): back of house`), Fallgold (three-level labels), and the House Notes screen for any one house. The database change is live immediately (notes come from Supabase, not the deploy); the deploy only updates the offline fallback.
