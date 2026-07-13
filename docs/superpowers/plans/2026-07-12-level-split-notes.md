# Level-Split Notes Implementation Plan

> **For agentic workers:** REQUIRED SUB-SKILL: Use superpowers:subagent-driven-development (recommended) or superpowers:executing-plans to implement this plan task-by-task. Steps use checkbox (`- [ ]`) syntax for tracking.

**Goal:** (Part 1) Drop `(up)/(down)/(1st)/(2nd)/(shared)` direction labels from `fireExtinguishers`, `dryerVents`, `atticAccess` notes so they read `Resident: X · RS: Y`; (Part 2) split `fridgeCoils` into two independent per-level keys shown one per checklist section.

**Architecture:** Two data migrations plus a small render change. Part 1 (migration 0012) is a mechanical text transform on three note keys. Part 2 (migration 0013) replaces one note key with two and rewires `NOTE_RULES`/`NOTE_KEY_LABELS`. The database is the live source of truth; `house-data.js` (offline fallback) gets identical edits.

**Tech Stack:** Postgres jsonb (Supabase), Supabase CLI, vanilla JS (`route-checklist/index.html`, `house-data.js`), service worker cache versioning.

**Spec:** `docs/superpowers/specs/2026-07-12-fridge-coils-split-design.md`

## Global Constraints

- Migrations applied ONLY with `supabase db push`. CLI full path if not on PATH: `$LOCALAPPDATA/Programs/supabase-cli/supabase.exe`. Never hand-paste SQL into the dashboard.
- The database is the source of truth for CURRENT note values — the seed `.sql` files still hold pre-0011 text. `route-checklist/house-data.js` WAS updated by 0011 and holds current values; use it as the reference for current text and cross-check live with `supabase` if in doubt.
- Part 1 transform is exactly: delete ` (up)`, ` (down)`, ` (1st)`, ` (2nd)`, ` (shared)` (leading space + parenthetical), and change `Residents:` → `Resident:`. Nothing else. Applies ONLY to keys `fireExtinguishers`, `dryerVents`, `atticAccess`.
- Repo is PUBLIC — no secrets or door codes.
- **Path-limit every commit** (`git commit <paths> -m …`): a parallel session shares this repo; a bare `git commit` after `git add` can sweep in unrelated staged files.
- Commit messages end with `Co-Authored-By: Claude Opus 4.8 <noreply@anthropic.com>`.
- Do NOT push until the final task says to (GitHub Pages deploys this branch).
- No automated test runner. Verification = the generated before→after table read against the transform rule + headless-Chrome parse check + `supabase migration list` + owner live drive.

---

### Task 1: Migration 0012 — drop direction labels (Part 1)

**Files:**
- Create: `supabase/migrations/0012_drop_direction_labels.sql`
- Create (scratch, not committed): the generated before→after table for review

**Interfaces:**
- Consumes: `public.houses.notes` jsonb with post-0011 values; keys `fireExtinguishers`, `dryerVents`, `atticAccess`.
- Produces: those keys rewritten to format-B text in the live DB. Task 2 copies the identical strings into `house-data.js`.

- [ ] **Step 1: Generate the before→after table from current values**

The 52 current values live in `route-checklist/house-data.js` (post-0011). Generate the table so you (and the owner) can review every transform. Run in Git Bash:

```bash
cd "/c/Big Dogs Apps/MTX Checklist V1"
awk '
  /name:/ { n=$0; sub(/^[ \t]*name: "/,"",n); sub(/".*/,"",n) }
  /^[ \t]*(fireExtinguishers|dryerVents|atticAccess):/ && /\((up|down|1st|2nd|shared)\)/ {
    line=$0
    key=line; sub(/:.*/,"",key); gsub(/[ \t]/,"",key)
    val=line; sub(/^[^:]*: "/,"",val); sub(/",?[ \t]*$/,"",val)
    nw=val
    gsub(/ \((up|down|1st|2nd|shared)\)/,"",nw)
    gsub(/Residents:/,"Resident:",nw)
    printf "%s | %s\n  BEFORE: %s\n  AFTER:  %s\n", n, key, val, nw
  }
' route-checklist/house-data.js > /tmp/part1-table.txt
wc -l /tmp/part1-table.txt
head -30 /tmp/part1-table.txt
```
Expected: ~52 note blocks. Read `/tmp/part1-table.txt` fully and confirm each AFTER equals BEFORE with only the parenthetical removed and Residents→Resident. If any AFTER looks wrong (e.g. a `(down)` inside real prose got stripped), STOP and report — do not proceed.

Known intentional cases to confirm, not fix:
- Tiller Lane `fireExtinguishers`: `… RS apartment (down), …` → `… RS apartment, …` (correct — "(down)" removed, "RS apartment" is prose that stays).
- Fallgold `fireExtinguishers`: `Basement (shared): …` → `Basement: …`.
- Crestridge `dryerVents`: contains prose "the RS dryer may auto-shut-off" — must be UNCHANGED (no label there).

- [ ] **Step 2: Write the migration from the generated AFTER values**

Create `supabase/migrations/0012_drop_direction_labels.sql`. Header, then one `jsonb_set` per (house, key) using the AFTER text from Step 1. Use this exact shape (fill every row from the table — do NOT abbreviate):

```sql
-- ----------------------------------------------------------------------------
-- 0012_drop_direction_labels.sql — Part 1 of the level-split-notes work.
--
-- Drops the (up)/(down)/(1st)/(2nd)/(shared) direction parenthetical from
-- fireExtinguishers, dryerVents, atticAccess notes: "Residents (up): X · RS
-- (down): Y" -> "Resident: X · RS: Y". The label already names the unit, so
-- the direction word is redundant (owner decision, format B). fridgeCoils is
-- handled separately in 0013 (true per-level split). Spec:
-- docs/superpowers/specs/2026-07-12-fridge-coils-split-design.md.
--
-- jsonb_set replaces one key; every other note on the row is untouched.
-- Idempotent: re-running writes the same already-clean text. Applied with
-- `supabase db push`.
-- ----------------------------------------------------------------------------

update public.houses set notes = jsonb_set(notes, '{fireExtinguishers}', '"Resident: laundry closet · RS: mech room · Garage: by main door · One in the van"'::jsonb) where name = 'Dogwood';
update public.houses set notes = jsonb_set(notes, '{dryerVents}', '"Resident: NW side · RS: NE side under deck"'::jsonb) where name = 'Dogwood';
-- … one line per row in /tmp/part1-table.txt (52 total) …
```

Rules for writing each line:
- Inner jsonb string is double-quoted; the AFTER values contain no `"` or `\`, so no escaping is needed. They DO contain `·`, `—`, `≤`-type chars — paste them verbatim (UTF-8).
- `atticAccess` for Fallgold and Sherwood Place: use their AFTER text (they start with `Attic access — RS: …`).
- Houses appear once per key they have; Dogwood/Fallgold/etc. have multiple keys = multiple lines.

- [ ] **Step 3: Push and verify applied**

```bash
"$LOCALAPPDATA/Programs/supabase-cli/supabase.exe" db push
"$LOCALAPPDATA/Programs/supabase-cli/supabase.exe" migration list
```
Expected: push lists `0012_drop_direction_labels.sql` and finishes cleanly; `migration list` shows `0012` in both Local and Remote.

- [ ] **Step 4: Verify no direction labels remain in the DB for these keys**

```bash
"$LOCALAPPDATA/Programs/supabase-cli/supabase.exe" db push >/dev/null 2>&1
psql_check() { "$LOCALAPPDATA/Programs/supabase-cli/supabase.exe" db execute --stdin <<'SQL'
select count(*) from houses
where notes->>'fireExtinguishers' ~ '\((up|down|1st|2nd|shared)\)'
   or notes->>'dryerVents'        ~ '\((up|down|1st|2nd|shared)\)'
   or notes->>'atticAccess'       ~ '\((up|down|1st|2nd|shared)\)';
SQL
}
psql_check
```
Expected: count = 0. (If `db execute` is unavailable in this CLI version, skip this step — Step 1's table review plus Task 2's grep already cover it.)

- [ ] **Step 5: Commit (path-limited)**

```bash
git add supabase/migrations/0012_drop_direction_labels.sql
git commit supabase/migrations/0012_drop_direction_labels.sql -m "feat: migration 0012 — drop (up)/(down) direction labels from fire ext/dryer/attic notes

Co-Authored-By: Claude Opus 4.8 <noreply@anthropic.com>"
```

---

### Task 2: house-data.js sync + SW bump (Part 1)

**Files:**
- Modify: `route-checklist/house-data.js` (the 52 `fireExtinguishers`/`dryerVents`/`atticAccess` values carrying direction labels)
- Modify: `route-checklist/sw.js` (cache version, current `route-checklist-v12` → `route-checklist-v13`)

**Interfaces:**
- Consumes: Task 1's migration AFTER text (identical strings).
- Produces: offline fallback consistent with the DB.

- [ ] **Step 1: Apply the transform in-place**

The same mechanical rule, applied to the three keys only. Run in Git Bash (operates only on lines whose key is one of the three AND that contain a direction parenthetical):

```bash
cd "/c/Big Dogs Apps/MTX Checklist V1"
perl -i -pe '
  if (/^\s*(fireExtinguishers|dryerVents|atticAccess):/) {
    s/ \((up|down|1st|2nd|shared)\)//g;
    s/Residents:/Resident:/g;
  }
' route-checklist/house-data.js
```

- [ ] **Step 2: Verify count went to zero and nothing else changed**

```bash
grep -cE "^\s*(fireExtinguishers|dryerVents|atticAccess):.*\((up|down|1st|2nd|shared)\)" route-checklist/house-data.js || echo 0
git diff --stat route-checklist/house-data.js
```
Expected: first command prints `0`; diff stat shows only `house-data.js` changed with ~52 line modifications. Then spot-check the diff:
```bash
git diff route-checklist/house-data.js | grep -E '^[-+]' | head -20
```
Confirm every `+` line is its `-` line minus the parenthetical (and Residents→Resident). No other keys touched.

- [ ] **Step 3: Bump the service worker cache**

`route-checklist/sw.js` line 7: change `const CACHE = "route-checklist-v12";` to `"route-checklist-v13";`. (Confirm the current value first with `grep route-checklist-v route-checklist/sw.js`; bump to the next integer whatever it is.)

- [ ] **Step 4: Parse check**

```bash
"$LOCALAPPDATA/Google/Chrome/Application/chrome.exe" --headless=new --disable-gpu --no-first-run --allow-file-access-from-files --enable-logging=stderr --v=0 --virtual-time-budget=5000 --dump-dom "file:///C:/Big%20Dogs%20Apps/MTX%20Checklist%20V1/route-checklist/index.html" > /dev/null 2> /tmp/cc.txt; grep -i CONSOLE /tmp/cc.txt | grep -iv manifest
```
Expected: no output (a `SyntaxError` means a broken string edit — fix before committing).

- [ ] **Step 5: Commit (path-limited)**

```bash
git commit route-checklist/house-data.js route-checklist/sw.js -m "feat: drop direction labels in offline roster (Part 1); SW v13

Co-Authored-By: Claude Opus 4.8 <noreply@anthropic.com>"
```

---

### Task 3: Migration 0013 + render — fridge-coils split (Part 2)

**Files:**
- Create: `supabase/migrations/0013_fridge_coils_split.sql`
- Modify: `route-checklist/index.html` (`NOTE_RULES` ~line 1051, `NOTE_KEY_LABELS` ~line 2068, and the render filter ~line 1275)
- Modify: `route-checklist/house-data.js` (`fridgeCoils` → two keys, per house)
- Modify: `route-checklist/sw.js` (cache → `route-checklist-v14`)

**Interfaces:**
- Consumes: `public.houses.notes.fridgeCoils` (current values). Checklist items `rk-fridge-coils` (Resident Kitchen) and `rsk-fridge-coils` (RS Kitchen), both labeled "Vacuum refrigerator coils (front/back)".
- Produces: keys `fridgeCoils_res`, `fridgeCoils_rs`; the old `fridgeCoils` key removed. Render maps each item to its key.

- [ ] **Step 1: List current fridgeCoils values and derive the split**

```bash
cd "/c/Big Dogs Apps/MTX Checklist V1"
grep -nE "^\s*fridgeCoils:" route-checklist/house-data.js
```
Current values (post-0011) and the derived split — the RS half always goes to `fridgeCoils_rs` regardless of which side "up" is (flipped houses: 92nd Crescent is the only fridgeCoils house among the five, and its value is "See house info" → copy-both, so no flip parsing is actually needed here):

| House | current fridgeCoils | fridgeCoils_res | fridgeCoils_rs |
|---|---|---|---|
| Dogwood | `Residents (up): front · RS (down): back` | `front` | `back` |
| 16th Avenue | `Roof coils in garage by fuse box` | `Roof coils in garage by fuse box` | `Roof coils in garage by fuse box` |
| 140th Lane East | `Residents (up): front of fridge · RS (down): front of fridge` | `front of fridge` | `front of fridge` |
| 140th Lane West | `Residents (up): front of the fridge · RS (down): back of the fridge` | `front of the fridge` | `back of the fridge` |
| 92nd Crescent | `See house info` | `See house info` | `See house info` |
| Fallgold | `Residents (1st): front side · RS (2nd): back of refrigerator` | `front side` | `back of refrigerator` |
| Toledo | `Residents (up): front of fridge · RS (down): back of fridge` | `front of fridge` | `back of fridge` |
| Oregon Golden Valley (OGV) | `Residents (up): front/back · RS (down): front/back` | `front/back` | `front/back` |

Confirm these 8 against the live grep output before writing SQL. If the grep shows a `fridgeCoils` value NOT in this table, STOP and report (a house was added/edited since planning). The split rule: if the value has ` · ` with `Residents`/`RS` markers, take the text after each `: ` up to the ` · ` / end, dropping the leading label; otherwise copy the whole value to both.

- [ ] **Step 2: Write migration 0013**

Create `supabase/migrations/0013_fridge_coils_split.sql`:

```sql
-- ----------------------------------------------------------------------------
-- 0013_fridge_coils_split.sql — Part 2 of level-split-notes.
--
-- fridgeCoils is the only note with a checklist item in BOTH the Resident and
-- RS kitchen sections, so its single value rendered (duplicated) in both.
-- Split it into fridgeCoils_res (Resident kitchen) and fridgeCoils_rs (RS
-- kitchen), each independently editable; remove the old key. Values that don't
-- cleanly split (no markers, identical halves, "See house info") copy whole to
-- both. Spec: docs/superpowers/specs/2026-07-12-fridge-coils-split-design.md.
--
-- Per house: set the two new keys, then delete the old key with `- 'fridgeCoils'`.
-- Idempotent. Applied with `supabase db push`.
-- ----------------------------------------------------------------------------

update public.houses set notes =
  jsonb_set(jsonb_set(notes, '{fridgeCoils_res}', '"front"'::jsonb), '{fridgeCoils_rs}', '"back"'::jsonb)
  - 'fridgeCoils'
  where name = 'Dogwood';

update public.houses set notes =
  jsonb_set(jsonb_set(notes, '{fridgeCoils_res}', '"Roof coils in garage by fuse box"'::jsonb), '{fridgeCoils_rs}', '"Roof coils in garage by fuse box"'::jsonb)
  - 'fridgeCoils'
  where name = '16th Avenue';

update public.houses set notes =
  jsonb_set(jsonb_set(notes, '{fridgeCoils_res}', '"front of fridge"'::jsonb), '{fridgeCoils_rs}', '"front of fridge"'::jsonb)
  - 'fridgeCoils'
  where name = '140th Lane East';

update public.houses set notes =
  jsonb_set(jsonb_set(notes, '{fridgeCoils_res}', '"front of the fridge"'::jsonb), '{fridgeCoils_rs}', '"back of the fridge"'::jsonb)
  - 'fridgeCoils'
  where name = '140th Lane West';

update public.houses set notes =
  jsonb_set(jsonb_set(notes, '{fridgeCoils_res}', '"See house info"'::jsonb), '{fridgeCoils_rs}', '"See house info"'::jsonb)
  - 'fridgeCoils'
  where name = '92nd Crescent';

update public.houses set notes =
  jsonb_set(jsonb_set(notes, '{fridgeCoils_res}', '"front side"'::jsonb), '{fridgeCoils_rs}', '"back of refrigerator"'::jsonb)
  - 'fridgeCoils'
  where name = 'Fallgold';

update public.houses set notes =
  jsonb_set(jsonb_set(notes, '{fridgeCoils_res}', '"front of fridge"'::jsonb), '{fridgeCoils_rs}', '"back of fridge"'::jsonb)
  - 'fridgeCoils'
  where name = 'Toledo';

update public.houses set notes =
  jsonb_set(jsonb_set(notes, '{fridgeCoils_res}', '"front/back"'::jsonb), '{fridgeCoils_rs}', '"front/back"'::jsonb)
  - 'fridgeCoils'
  where name = 'Oregon Golden Valley (OGV)';
```

(If Step 1 revealed a house not in the table, add its line using the same shape and the split rule.)

- [ ] **Step 3: Push and verify**

```bash
"$LOCALAPPDATA/Programs/supabase-cli/supabase.exe" db push
"$LOCALAPPDATA/Programs/supabase-cli/supabase.exe" migration list
```
Expected: `0013` applied, Local+Remote.

- [ ] **Step 4: Update `NOTE_RULES` to key fridge coils by item**

In `route-checklist/index.html`, the `NOTE_RULES` array (~line 1051) currently has:
```javascript
    { match: /refrigerator coils/i,     note: "fridgeCoils" },
```
Replace that single line with two item-scoped rules:
```javascript
    { match: /refrigerator coils/i,     note: "fridgeCoils_res", itemKey: "rk-fridge-coils" },
    { match: /refrigerator coils/i,     note: "fridgeCoils_rs",  itemKey: "rsk-fridge-coils" },
```

- [ ] **Step 5: Make the render filter honor `itemKey`**

In `route-checklist/index.html` (~line 1275), the note rendering currently does:
```javascript
            const rules = NOTE_RULES.filter(r => r.match.test(label));
```
Change it to also match the optional `itemKey` against the current item's key (`id` is `item.key`, in scope from line 1267):
```javascript
            const rules = NOTE_RULES.filter(r => r.match.test(label) && (!r.itemKey || r.itemKey === id));
```
This keeps every existing rule working (they have no `itemKey`) and makes the two fridge-coils rules apply only to their own item.

- [ ] **Step 6: Update `NOTE_KEY_LABELS`**

In `route-checklist/index.html` (~line 2068), find:
```javascript
    fridgeCoils: "Refrigerator coils",
```
Replace with:
```javascript
    fridgeCoils_res: "Refrigerator coils (Resident)",
    fridgeCoils_rs: "Refrigerator coils (RS)",
```

- [ ] **Step 7: Sync house-data.js**

For each of the 8 houses in Step 1's table, in `route-checklist/house-data.js`, replace the single `fridgeCoils: "…",` line with two lines:
```javascript
      fridgeCoils_res: "<res value>",
      fridgeCoils_rs: "<rs value>",
```
using the split values from the table. (Manual edit — 8 houses. Match each house by its `name:` then its `fridgeCoils:` line.)

- [ ] **Step 8: Bump SW cache and parse check**

`route-checklist/sw.js`: bump cache to the next integer (v13 → `route-checklist-v14`). Then:
```bash
"$LOCALAPPDATA/Google/Chrome/Application/chrome.exe" --headless=new --disable-gpu --no-first-run --allow-file-access-from-files --enable-logging=stderr --v=0 --virtual-time-budget=5000 --dump-dom "file:///C:/Big%20Dogs%20Apps/MTX%20Checklist%20V1/route-checklist/index.html" > /dev/null 2> /tmp/cc.txt; grep -i CONSOLE /tmp/cc.txt | grep -iv manifest
```
Expected: no output.

- [ ] **Step 9: Verify no lingering `fridgeCoils` (old key) references**

```bash
grep -n "fridgeCoils\b" route-checklist/index.html route-checklist/house-data.js | grep -vE "fridgeCoils_(res|rs)"
```
Expected: no output (the only matches should be the two new suffixed keys). If the old bare `fridgeCoils` appears anywhere in code, fix it.

- [ ] **Step 10: Commit (path-limited)**

```bash
git commit supabase/migrations/0013_fridge_coils_split.sql route-checklist/index.html route-checklist/house-data.js route-checklist/sw.js -m "feat: split fridge-coils note per level (0013) — independent Resident/RS values; SW v14

Co-Authored-By: Claude Opus 4.8 <noreply@anthropic.com>"
```

---

### Task 4: Ship — HANDOFF note, push, live verification

**Files:**
- Modify: `route-checklist/HANDOFF.md` (append to the newest 2026-07-12 section)

**Interfaces:**
- Consumes: Tasks 1–3 committed; live URL `https://tweet-delta.github.io/mtx-sandbox/route-checklist/index.html#home`.

- [ ] **Step 1: HANDOFF note**

Append to the newest 2026-07-12 section of `route-checklist/HANDOFF.md`, in its existing voice: migration 0012 dropped `(up)/(down)/(1st)/(2nd)/(shared)` labels from fireExtinguishers/dryerVents/atticAccess (52 notes) → `Resident: X · RS: Y`; migration 0013 split `fridgeCoils` into `fridgeCoils_res`/`fridgeCoils_rs`, each rendered under its own kitchen section via new `itemKey` field on `NOTE_RULES`; `NOTE_KEY_LABELS` labels them "(Resident)"/"(RS)"; house-data.js synced; SW v14; the "coils move when a fridge is replaced" verify-reminder is a deferred follow-up (blocked on no System author + once-only migration seeding). Owner live spot-check pending.

- [ ] **Step 2: Commit (path-limited) and push**

```bash
git commit route-checklist/HANDOFF.md -m "docs: handoff notes for level-split notes (0012/0013)

Co-Authored-By: Claude Opus 4.8 <noreply@anthropic.com>"
git push
```

- [ ] **Step 3: Live smoke check**

```bash
until curl -s "https://tweet-delta.github.io/mtx-sandbox/route-checklist/sw.js" | grep -q "route-checklist-v14"; do sleep 15; done; echo LIVE
curl -s "https://tweet-delta.github.io/mtx-sandbox/route-checklist/house-data.js" | grep -cE "fridgeCoils_(res|rs):"
curl -s "https://tweet-delta.github.io/mtx-sandbox/route-checklist/house-data.js" | grep -cE "^\s*(fireExtinguishers|dryerVents|atticAccess):.*\((up|down)\)" || echo 0
```
Expected: `LIVE`; first count ≥ 16 (8 houses × 2 keys); second count `0` (no direction labels remain in the deployed roster).

- [ ] **Step 4: Hand the owner the spot-check list**

Report to the owner (do not claim verified): sign in and open —
1. Any house's fire-extinguisher note reads `Resident: … · RS: …` (no "(up)/(down)").
2. Dogwood checklist: **Resident-Level Kitchen** fridge coils shows only "front"; **RS-Unit Kitchen** fridge coils shows only "back" — no combined line, no up/down.
3. Edit the Resident fridge-coils note (suggest or supervisor save); confirm the RS one is untouched.
4. House Notes screen / pending queue label them "Refrigerator coils (Resident)" and "(RS)".
The DB change is live immediately (notes come from Supabase); the deploy only refreshes the offline fallback.
