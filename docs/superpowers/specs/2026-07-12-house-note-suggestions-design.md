# House Note Suggestions — Design

**Date:** 2026-07-12
**Status:** Approved by owner (design review in-session)

## Problem

House notes exist in three forms: per-item notes (`houses.notes` jsonb, keyed —
`furnaceFilter`, `fireExtinguishers`, …, shown 📍 under checklist items and on
the House Notes screen), house info pairs (`houses.info` jsonb `[label, detail]`
arrays, shown on the House Notes screen), and the freeform general note
(`houses.general_notes`). Only the general note is editable in-app today
(techs suggest, supervisors approve — migration 0006). Per-item notes and info
pairs can only be changed by editing the database by hand.

## Goal

Techs can propose an **edit**, an **addition**, or a **removal** of any
per-item note or info pair. The proposal shows as **pending directly under the
current official value**, everywhere that value appears, until a supervisor
**approves** (change becomes official) or **denies** it (author sees the denial
plus an optional reason). Supervisors edit everything **directly**, no
approval. Supervisors also get a cross-house **pending queue** so nothing sits
unnoticed.

## Approach (chosen: generalize the existing system)

Extend the migration-0006 suggestion system (`house_note_suggestions` table +
atomic approve RPC) to cover all three note kinds, rather than building a
parallel table. One table → one queue, one audit trail, one UI pattern; the
existing general-notes flow inherits deny reasons. Rejected alternatives:
a separate `house_field_suggestions` table (two inconsistent systems), and
direct tech edits with an undo log (no approval gate — contradicts the
requirement and the data-sensitivity posture).

## Database — migration `0008_note_suggestions_all_kinds.sql`

New columns on `public.house_note_suggestions` (all defaulted so existing rows
remain valid):

| Column | Type / constraint | Meaning |
|---|---|---|
| `target` | text, `'general'` (default) \| `'item'` \| `'info'` | which note kind |
| `note_key` | text, default `''` | item-note key (`furnaceFilter`) or info label (`Paint`); empty for `general` |
| `action` | text, `'set'` (default) \| `'delete'` | `set` covers both edit and add; `delete` proposes removal |
| `deny_reason` | text, default `''` | supervisor's optional reason on deny |
| `seen_by_author` | boolean, default `false` | author has dismissed the denial notice |

Constraint: `target in ('general','item','info')`, `action in ('set','delete')`,
and `note_key <> ''` when `target <> 'general'`. A `delete` action requires
`target <> 'general'` (the general note is edited to empty instead) and its
`proposed_text` is ignored (stored as `''`).

**RPCs (both `SECURITY DEFINER`, re-check `current_user_role() = 'supervisor'`
themselves, `search_path = public`, row-locked with `for update`, execute
revoked from `public`/`anon`, granted to `authenticated`):**

- `approve_note_suggestion(suggestion_id uuid)` — **replaced** (same name and
  signature as today). Applies by target, then marks the row
  `approved`/`reviewed_by`/`reviewed_at`:
  - `general` → `update houses set general_notes = proposed_text` (unchanged
    behavior).
  - `item` + `set` → set `notes[note_key]` to `proposed_text` (jsonb update);
    `item` + `delete` → remove the key.
  - `info` + `set` → replace the detail of the **first** pair whose label
    equals `note_key`, or append `[note_key, proposed_text]` if no pair has
    that label (set semantics: add-with-existing-label behaves as edit);
    `info` + `delete` → remove the first pair with that label.
  - Approving a `delete` whose key/label is already gone is a no-op on the
    house but still marks the suggestion approved (same end state, no error).
- `deny_note_suggestion(suggestion_id uuid, reason text default '')` — **new**.
  Marks the row `dismissed`, stamps `reviewed_by`/`reviewed_at`, stores
  `deny_reason`, in one statement.

**RLS changes:**

- Existing policies stand (everyone authenticated reads all suggestions;
  insert only as yourself; delete own pending; supervisors update).
- New policy: the **author** may update their **own reviewed** rows, but a
  trigger (or `with check` comparing old/new via a `before update` trigger
  function) restricts the change to flipping `seen_by_author` — nothing else.
  Simplest correct form: a `before update` trigger that, when the caller is
  not a supervisor, raises unless only `seen_by_author` changed; the policy
  itself allows `author_id = auth.uid() and status <> 'pending'`.

**Denormalized note:** `author_name` stays snapshotted at insert (RLS hides
other techs' profile rows, and it doubles as name-at-time-of-writing history).
Supervisor UI may not know reviewer names for the same reason — display
reviewer only for one's own actions or omit; not a requirement.

No `houses` table changes: supervisors' direct edits use the existing
`houses_write` policy (supervisor-only `for all`).

## Data module (`cloud.js`)

Extend the existing house-notes section; keep the app ↔ Supabase boundary
(the UI never queries Supabase directly):

- `getHouseNotes(houseName)` → also returns pending suggestions for `item` and
  `info` targets, and the caller's unseen denials (`status = 'dismissed'`,
  `author_id = me`, `seen_by_author = false`).
- `suggestChange(houseName, target, noteKey, action, text, authorName)` —
  generalizes `suggestNote` (which remains as a thin wrapper for the
  general-note editor).
- `withdrawSuggestion(id)` — unchanged (delete own pending).
- `approveSuggestion(id)` — unchanged call, new server behavior.
- `denySuggestion(id, reason)` — calls `deny_note_suggestion` (replaces the
  old direct-update `dismissSuggestion`).
- `markDenialSeen(id)` — flips `seen_by_author`.
- `saveHouseField(houseName, target, noteKey, action, text)` — supervisor
  direct write: updates `houses.notes` / `houses.info` (jsonb patch client-side
  on the loaded house object, single `update` of the column), then refreshes
  the local house cache. `saveGeneralNotes` stays for the general note.
- `listPendingSuggestions()` — all pending rows across houses with house
  names, for the queue + badge count (one query, supervisors call it once per
  session for the badge and on opening the queue).

## Tech experience

**Checklist inline:** each 📍 note gets ✎ **Suggest fix** → one-line editor
prefilled with current text; actions: Submit suggestion / Suggest removal /
Cancel. Checklist items whose `NOTE_RULES` key has no note for this house show
a quieter **+ add note**.

**House Notes screen:** every info-pair and item-note row gets the same ✎
control. Two add buttons: **+ Add item note** (picker of this house's unfilled
`NOTE_KEY_LABELS` keys) and **+ Add house info** (label + detail fields).
Door-code rows (from the local codes file) are not editable — not database
data.

**Pending display** (both places, all signed-in users see it; only the author
gets Withdraw):

> 📍 Furnace filter: 16x25x1 — change monthly
> ⏳ **Pending:** 20x25x4 — *suggested by Henry* [Withdraw]

Removal proposals show “⏳ Pending removal — suggested by Henry”. Multiple
pending suggestions for the same key stack; each is reviewed individually.

**Denial notice** (author only, until dismissed):

> ❌ **Denied** — “reason text” [Dismiss]

Dismiss calls `markDenialSeen`; the row stays as audit trail. Approval needs no
notice: the new text becomes the official note.

## Supervisor experience

- Same ✎ / + controls, but labeled **Save** and writing directly via
  `saveHouseField` (mirrors the existing Save-vs-Submit split in the
  general-notes editor). Supervisors can also delete a note/pair outright.
- Inline on any pending suggestion: **[✓ Approve] [✕ Deny]**; Deny opens one
  optional reason field (“Reason — the tech will see this”).
- **Pending changes** screen in the ☰ menu, supervisor-role only, with a count
  badge loaded once per session. Lists all pending suggestions grouped by
  house, newest first, each row showing proposed vs. current official text
  with inline ✓/✕. General-note suggestions appear here too (same table) —
  closing today's gap where they're only visible per-house.
- Techs never see the queue; RLS (not the UI) is what actually blocks a tech
  from approving/denying.

## Edge cases & errors

- **Concurrent review / double-tap:** `for update` row lock + `status =
  'pending'` check → second attempt gets “already reviewed”; UI refreshes.
- **Approve after the note changed:** proposed text still applies
  (last-write-wins); remaining pending suggestions re-render against the new
  official text and still require explicit review.
- **Duplicate info labels:** operations target the first matching pair; adding
  an existing label behaves as an edit. Label rename = removal + addition.
- **Offline / signed out:** all editing/review controls render only when the
  cloud is reachable and a session exists (existing general-notes rule); notes
  still display.
- **Failures are visible:** any Supabase error shows a message next to the
  control that caused it and preserves the typed text for retry (existing
  notes-editor pattern).
- **Escaping:** all user-entered text rendered via the existing
  `escHtml`/`escAttr` helpers.
- **Accessibility:** `aria-label`s naming the specific note on every icon
  button; focus moves into the inline editor on open and back to the trigger
  on cancel; pending/denied conveyed as text, not color alone.

## Out of scope

- Email/notification to supervisors on new suggestions (Phase 3 territory).
- Editing door codes (device-local file, never in the DB by policy).
- Equipment-flag changes (different mechanism: hides/shows checklist items).
- Offline queuing of suggestions (Phase 5 sync).
- `house-data.js` drift: it remains a stale offline fallback, as today.

## Verification (manual, both roles)

1. Tech: suggest an edit, an addition (item note + info pair), and a removal;
   see pending under the official value in checklist **and** House Notes;
   withdraw one.
2. Supervisor: badge count correct; queue shows all pending with current text;
   approve one (official text updates everywhere); deny one with a reason;
   direct-edit and direct-delete a note and an info pair (instant).
3. Tech again: denial + reason visible, Dismiss clears it and it stays gone
   after reload.
4. Regression: general-notes suggest → approve and suggest → deny still work.
5. Supabase: confirm suggestion rows carry correct `target`/`note_key`/
   `action`/`status`/`deny_reason`/`seen_by_author`, and `houses.notes` /
   `houses.info` changed only on approval or supervisor save.
