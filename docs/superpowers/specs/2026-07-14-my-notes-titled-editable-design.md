# "My notes" — titled, editable note cards — design

**Date:** 2026-07-14
**Status:** Approved (owner, 2026-07-14)
**Branch:** `claude/claude-code-tutorial-5l5ew2`
**Follow-on to:** `docs/superpowers/specs/2026-07-14-my-notes-design.md` (the original checklist-style My notes)

## Problem

The original "My notes" shipped as a flat checklist — single-line items with a
checkbox. The owner wants each note to have an optional title (header) and a
separate body text box, and to be editable after creation — moving the
feature from a checklist toward a small private notes list.

## Owner decisions captured

| Question | Decision |
|---|---|
| Header meaning | Each **note** gets its own title, not just the screen |
| Checkbox/checklist behavior | **Removed entirely** — no checkbox, no "done" state, no "Clear checked" |
| Removing a note | **✕ Delete only** — no archive/status field |
| Title requirement | **Optional** — only the body is required to save |
| Editing | **Supported** — ✎ Edit button per note, inline title+body fields with Save/Cancel |

## Non-goals (unchanged from original spec, still out of scope)

- Multiple named lists/categories.
- Due dates/reminders.
- Manual reordering (still insertion order via `position`).
- Sharing a list with another tech or supervisor.
- Rich text/markdown formatting.
- Note history/undo.

## What changes from the original build

- `personal_notes.done` is **dropped** — no longer meaningful once there's no
  checkbox.
- `personal_notes.text` becomes the note's **body**; a new `title` column is
  added (`not null default ''`, i.e. empty string means "no title").
- `cloud.js`: `toggleMyNote` and `clearCheckedNotes` are **removed**.
  `addMyNote` becomes `addMyNote(title, body)`. New `updateMyNote(id, title,
  body)`. `listMyNotes()` and `deleteMyNote(id)` keep their signatures (just
  operate on the new column shape).
- RLS is **unchanged** — still fully private, `tech_id = auth.uid()` only, no
  supervisor exception. This slice doesn't touch that boundary.

---

## Part A — Database migration `0019_personal_notes_title.sql`

```sql
alter table public.personal_notes
  add column if not exists title text not null default '';

alter table public.personal_notes
  drop column if exists done;
```

No RLS change — the existing four policies from `0018` already cover every
column on the table generically (`using`/`with check` are row-scoped, not
column-scoped), so a new column needs no new policy.

## Part B — `cloud.js`

- `listMyNotes()` — same signature; now selects `id, title, text, position`
  instead of `id, text, done, position`.
- `addMyNote(title, body)` — inserts `{ tech_id, title: (title||"").trim(),
  text: body trimmed, position: next }`. Body is required (rejected client-
  side if empty, same validation style as before); title may be empty string.
- `updateMyNote(id, title, body)` — new function. Updates `title` and `text`
  on one owned row (`tech_id = me` self-scope, same defense-in-depth pattern
  as every other mutator). Body still required; title still optional.
- `deleteMyNote(id)` — unchanged.
- `toggleMyNote`, `clearCheckedNotes` — **removed** from `cloud.js` and from
  the `window.cloud` export list.

## Part C — UI

### Add box

Two fields: a **Title** text input (`placeholder="Title (optional)"`) and a
**body** `<textarea>` (`placeholder="Write your note…"`, required), plus
"+ Add". Submitting calls `addMyNote(title, body)`; both fields clear on
success. The old single-input "Enter to submit" shortcut is removed — a
textarea needs Enter for its own line breaks, so submission is button-only.

### Each note card (display mode)

- Title rendered as a bold header line **only if non-empty** — an untitled
  note shows just its body, no empty header.
- Body text below, with line breaks preserved (the textarea's newlines must
  survive round-trip through the DB and back into the rendered HTML).
- **✎ Edit** and **✕ Delete** buttons.

### Each note card (edit mode)

Tapping ✎ swaps that card's display for the same title input + body textarea
(pre-filled with the note's current title/body) plus **Save** / **Cancel**.
- **Save** calls `updateMyNote(id, title, body)`; on success, re-renders the
  list showing the updated card in display mode.
- **Cancel** reverts to display mode without saving, discarding any typed
  changes.
- Only one note can be in edit mode at a time (opening ✎ on a different card
  while one is already open closes the first without saving — same
  "single open editor" pattern already used by the House Notes suggestion
  editor).

### Removed entirely

Checkbox, strikethrough/`.done` styling, "Clear checked" button, the
`mynotes-item.done` CSS rule, the checkbox `change` event listener.

---

## Verification (live)

1. Sign in → 📋 My notes → add a note with a title and a multi-line body →
   confirm it renders with the title as a header and the body with line
   breaks preserved.
2. Add a note with **no title** (body only) → confirm it renders with no
   empty header line, just the body.
3. Tap ✎ on a note → fields pre-fill with its current title/body → change the
   body → Save → confirm the card updates in place.
4. Tap ✎, change something, then Cancel → confirm nothing was saved (reload
   to double check).
5. Open ✎ on note A, then tap ✎ on note B without saving A → confirm A closes
   without saving and B opens for editing.
6. Delete a note via ✕ → confirm it's gone; reload → still gone.
7. Reload the whole screen → confirm all remaining notes and their
   titles/bodies persisted exactly.
8. Sign in as a second tech → confirm isolation (their own notes only).
9. Deep-link reload on `#mynotes` → no console errors.

Test accounts: `tech1@example.com`, `tech2@example.com`.
