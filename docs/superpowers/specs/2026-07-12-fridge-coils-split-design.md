# Fridge-Coils Per-Level Note Split — Design

**Date:** 2026-07-12
**Status:** Awaiting owner review

## Problem

The Resident-Level Kitchen and RS-Unit Kitchen are separate checklist sections
with separate items (`rk-fridge-coils`, `rsk-fridge-coils`). Both items match
the same `NOTE_RULES` entry (`/refrigerator coils/i` → note key `fridgeCoils`),
so the *single* `fridgeCoils` note value renders identically under both — the
tech sees the whole combined line ("Residents (up): front · RS (down): back")
twice, once in each section, instead of the relevant half in each. The recent
level-label migration (0011) made the combined text readable but did not fix
the duplication; it is a data-model issue, not a wording one.

Fridge coils is the ONLY note with a real checklist item in BOTH the Resident
and RS sections. Other level-split notes (fire extinguishers, dryer vents,
attic access) render in a single Shared / Whole-House spot and have no second
section to split into — confirmed by mapping every `NOTE_RULES` key to its
items. They are explicitly OUT of scope.

## Goal

Split `fridgeCoils` into two independent note values — one per level — each
shown only under its own section's item and edited independently. No "(up)/
(down)" prefix (the section header already states the level).

## Approach (chosen: two note keys)

Replace the single `fridgeCoils` key with `fridgeCoils_res` (Resident) and
`fridgeCoils_rs` (RS) in `houses.notes` (jsonb) and `house-data.js`. Because
the suggestion/edit/approve system already keys everything by note key, two
keys become two independently-editable notes with zero new plumbing.

Rejected: a structured `{res, rs}` object under one key (the whole
suggestion/approve/jsonb-patch layer assumes string values keyed by name — an
object value would need special-casing everywhere); a UI-only split of the
combined string (fragile parsing on every render, and edits could not be
independent).

## Migration `0012_fridge_coils_split.sql`

For each house, transform `notes.fridgeCoils` into the two new keys, then
remove the old key. The transform, per house:

1. **Parseable** — value contains ` · ` AND both a Residents-side and an
   RS-side marker: strip the leading label from each half and assign each half
   to its key, **respecting flipped houses** (the RS-on-top houses from spec
   2026-07-12-level-label: 92nd Crescent, Amble, Fallgold, McAfee, Sherwood
   Place — for those, the "up" half is RS and the "down" half is Residents).
   - Example (normal house): `"Residents (up): front · RS (down): back"` →
     `fridgeCoils_res = "front"`, `fridgeCoils_rs = "back"`.
   - Example (flipped, if any had split coils): `"Residents (down): X · RS
     (up): Y"` → `fridgeCoils_res = "X"`, `fridgeCoils_rs = "Y"`.
2. **Not parseable** — no ` · `, or identical halves, or missing markers:
   copy the full existing text into BOTH keys unchanged. (Owner rule: never
   lose location info; the few oddballs get hand-edited in-app later.)
3. Remove the old `fridgeCoils` key from every house that had one.

The migration is written as an explicit per-house `jsonb_set` / `-` sequence,
NOT a generic string-parsing function — the set of houses with `fridgeCoils`
is small and known, and explicit UPDATEs are reviewable line-by-line (matching
how 0011 was done). The implementation plan will contain the full before→after
table for owner review, same as 0011.

**Source-of-truth caution:** the seed `.sql` files still contain PRE-0011
text ("Upstairs:/Downstairs:") because 0011 rewrote the live DB via UPDATE, not
the seed files. The plan MUST derive each house's *current* `fridgeCoils` value
by applying 0011's rewrite on top of the seed value (or by reading it live from
Supabase), never from the raw seed text. `house-data.js`, by contrast, WAS
updated by 0011's task 2, so it holds current values and is a good cross-check.

House-data.js receives the identical two-key values (offline fallback stays
consistent). SW cache bumps one version.

**Houses that currently have `fridgeCoils`** (distinct current values, to be
confirmed live in the plan): Dogwood, 140th Lane East (identical halves →
copy-both), 140th Lane West, Fallgold (1st/2nd labels), Toledo, Oregon Golden
Valley (OGV, "front/back · front/back"), plus two non-level values that also
match the key and must copy-both: **16th Avenue** ("Roof coils in garage by
fuse box") and **92nd Crescent** ("See house info"). Houses without the key are
untouched.

## Rendering (`route-checklist/index.html`)

- `NOTE_RULES`: the single `{ match: /refrigerator coils/i, note: "fridgeCoils" }`
  rule is replaced by matching on item key instead of a shared regex, so
  `rk-fridge-coils` → `fridgeCoils_res` and `rsk-fridge-coils` → `fridgeCoils_rs`.
  (Implementation detail for the plan: the current `NOTE_RULES` matches on item
  *text*, and both items share the text "Vacuum refrigerator coils (front/back)".
  The plan must key these two off the item `key`, not the text — e.g. a small
  per-key override map, or splitting the rule to test `item.key`.)
- Each item then shows only its own note value. No up/down prefix.
- `NOTE_KEY_LABELS`: replace `fridgeCoils: "Refrigerator coils"` with
  `fridgeCoils_res: "Refrigerator coils (Resident)"` and
  `fridgeCoils_rs: "Refrigerator coils (RS)"` — names them on the House Notes
  screen, the "+ add note" picker, and the pending queue.

## Editing / suggestions

No new code. Two keys are two notes; the existing suggest → approve/deny,
supervisor direct-save, and add/remove flows treat them independently.
Editing the Resident coils note cannot touch the RS one.

## Out of scope

- Fire extinguishers, dryer vents, attic access (no second-section item).
- The "coils move when a fridge is replaced" verify reminder — deferred to its
  own project (seeding per-house queue items hits two real blockers: the
  suggestion table's `author_id` is NOT NULL and must reference a real
  `profiles` row, so there is no "System" author; and a migration seeds only
  once, missing houses added later). Handled properly as a follow-up.
- Any house-data.js drift beyond the fridge-coils keys.

## Verification (manual)

1. On a normal house (e.g. Dogwood), open the checklist: Resident-Level Kitchen
   → fridge coils shows only its half (e.g. "front"); RS-Unit Kitchen → shows
   only its half (e.g. "back"). No "up/down" text on either.
2. Edit the Resident coils note (tech suggest or supervisor save) — the RS note
   is unchanged, and vice versa.
3. House Notes screen and pending queue label the two as "(Resident)" / "(RS)".
4. A house whose coils were identical/unparseable shows the same full text on
   both — nothing lost.
5. Supabase: `select name, notes->'fridgeCoils_res', notes->'fridgeCoils_rs',
   notes->'fridgeCoils' from houses where name in ('Dogwood','Toledo');` —
   two new keys present, old key gone.
