# "My notes" personal checklist — design

**Date:** 2026-07-14
**Status:** Approved (owner, 2026-07-14)
**Branch:** `claude/claude-code-tutorial-5l5ew2`

## Problem

A tech has no place in the app to jot personal reminders across visits — e.g.
"bring extra furnace filters tomorrow", "pick up salt", "ask supervisor about
X". Today the only note-taking surfaces are house-scoped (House Notes,
per-item notes) or work-history-scoped (Daily Logs manual notes, visible to
supervisors). Nothing is a private, general-purpose personal list.

## Goal

A simple checklist a tech can add items to anytime, check off as done, and
clear when finished — synced to the cloud so it follows them across devices,
and fully private (not even supervisors can see it).

## Owner decisions captured

| Question | Decision |
|---|---|
| Format | **Simple checklist** (add item → checkbox → check off), not free-text notes |
| Storage | **Cloud-synced** (new Supabase table), not device-only |
| Checked items | **Stay visible, crossed out, until manually cleared** — not removed on check |
| Placement | **New home-screen button** → its own `#mynotes` screen, matching My Profile / Daily Logs |
| Supervisor visibility | **Fully private** — RLS blocks read access for everyone except the owning tech, no supervisor exception (unlike Daily Logs) |
| Adding items | Adding a new item never affects existing ones; no cap on list length |

## Non-goals (this slice)

- Multiple named lists / categories (e.g. separate "shopping" vs "reminders").
- Due dates, reminders, or notifications.
- Manual reordering / drag-and-drop (items stay in the order added).
- Sharing a list with another tech or a supervisor.
- Photos or attachments on an item.
- Editing an item's text after creation (delete and re-add instead — items are
  short reminders, not documents).

---

## Part A — Database: `personal_notes` table

### Schema (migration `0018_personal_notes.sql`)

```
public.personal_notes
  id         uuid primary key default gen_random_uuid()
  tech_id    uuid not null references public.profiles(id) on delete cascade
               default auth.uid()
  text       text not null
  done       boolean not null default false
  position   int not null default 0   -- insertion order, so new items always
                                       -- append and existing order is stable
  created_at timestamptz not null default now()
  updated_at timestamptz not null default now()

index on (tech_id, position)
```

Modeled directly on `daily_logs` (migration `0016`) — same ownership-by-default
pattern (`tech_id default auth.uid()`), same per-tech index shape.

### RLS (row-level security)

Every operation is scoped to `tech_id = auth.uid()` — **no supervisor
exception**, unlike `daily_logs_select`. This is a deliberate, explicit owner
decision: personal notes are genuinely private, not work history.

- **Select:** `tech_id = auth.uid()`.
- **Insert:** `with check (tech_id = auth.uid())`.
- **Update:** `using (tech_id = auth.uid()) with check (tech_id = auth.uid())`
  — covers both toggling `done` and (if ever needed) editing `text`.
- **Delete:** `using (tech_id = auth.uid())`.

No real user data risk here even under the compliance posture — items are
whatever a tech types (shopping lists, reminders), not resident-adjacent data
by nature of the feature, but RLS is still the enforcement boundary, never the
UI, per the project's standing rule.

---

## Part B — `cloud.js` additions

Mirrors the Daily Logs manual-note functions (`addLogEntry` /
`updateLogEntry` / `deleteLogEntry` shape):

- `listMyNotes()` → the signed-in tech's own items, ordered by `position` asc,
  or `[]` on no-user/error/missing-table (`isMissingTable` graceful fallback,
  same pattern as every other feature added after a migration).
- `addMyNote(text)` → inserts a new row with `position` = current max + 1 (or
  0 if the list is empty); returns `{ error }`.
- `toggleMyNote(id, done)` → updates just the `done` column on one owned row;
  returns `{ error }`.
- `deleteMyNote(id)` → deletes one owned row; returns `{ error }`.
- `clearCheckedNotes()` → deletes all of the caller's own rows where
  `done = true` in one call; returns `{ error }`.

All self-scoped (`tech_id = me`) as defense-in-depth atop RLS, matching every
other `cloud.js` mutator in this codebase.

---

## Part C — UI: `#mynotes` screen

### 1. Home screen button

New button `📋 My notes`, always visible (not `admin-only`) — added to
`#homeScreen` alongside `👤 My profile` / `🗓️ Daily logs`, same `.home-btn`
styling.

### 2. The screen

New `#mynotesScreen` (hash-router: `#mynotes`, same pattern as `#profile` /
`#history` / `#logs` — a `.screen-head` with `← Home` + title, then a body
container filled by JS).

Layout, top to bottom:
- **Add box:** a text input + "+ Add" button (or Enter-to-submit). Submitting
  calls `addMyNote(text)`, clears the input, re-renders the list. Empty/
  whitespace-only text is rejected inline (no cloud call) — same validation
  style as My Profile's non-empty name check.
- **The list:** each item is a row with a checkbox, the item text, and a small
  ✕ delete button. Checking the box calls `toggleMyNote(id, true/false)` and
  immediately applies a strikethrough + muted style to that row (optimistic
  UI, matching the checklist's own checkbox pattern) — it does **not** remove
  the row or reorder the list.
- **"Clear checked" button:** shown only when at least one item is checked;
  calls `clearCheckedNotes()`, then re-renders. Placed below the list, not
  inline per-item, so it can't be tapped by accident while checking off a
  single item.
- **Empty state:** "No notes yet — add one above." when the list is empty.

### 3. Housekeeping

- Bump SW cache (next version after whatever is live when this ships).
- Update `HANDOFF.md` with the new state + live-verify checklist.
- Remind owner: hard-refresh (Ctrl+Shift+R) after deploy; fully close/reopen
  the PWA on phones.

---

## Verification (live)

1. Sign in as tech1 → tap 📋 My notes → add "bring extra filters" → confirm it
   appears unchecked.
2. Add a second item without touching the first → confirm both persist, in
   order added.
3. Check the first item → confirm it crosses out but stays in the list (not
   removed, not reordered).
4. Reload the page / re-open the screen → confirm both items and the checked
   state persisted (cloud round-trip).
5. Tap "Clear checked" → confirm only the checked item disappears; the
   unchecked one remains.
6. Delete the remaining item via ✕ → confirm the list shows the empty state.
7. Sign in as tech2 → confirm they see their own (empty or different) list —
   never tech1's items (isolation).
8. Sign in as the supervisor account → confirm there is no way to view
   tech1's or tech2's personal notes anywhere in the app (no admin screen
   exposes this table).
9. Deep-link reload on `#mynotes` → re-renders, no console errors.

Test accounts: `tech1@example.com`, `tech2@example.com`.
