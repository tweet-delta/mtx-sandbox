# Home screen, House Notes, and collapsed sections — Design

Date: 2026-07-10
Status: approved by owner (sections 1–3 approved in conversation)

## Goal

Three owner requests, built as one coherent slice:

1. Checklist sections start **closed** on every device.
2. After login, the first screen is a **Home page** with three options:
   **New house visit**, **Continue house visit**, **House notes**.
3. A **House Notes page** per house, where techs can *suggest* updates to a
   freeform note and the owner's **supervisor (admin) account** approves them.

## Decisions made with the owner

| Question | Decision |
|---|---|
| App structure | Screens inside the single `index.html` (same pattern as the login gate). No new files/pages, no framework. |
| Sections closed | Everywhere (phone and desktop), including Alarm Counts. |
| Continue flow | Lists the signed-in tech's in-progress visits (cloud + local device buffer); tap to resume. Empty state offers "start a new visit". |
| House notes content | Structured house info + 📍 item notes (read-only) **plus** a new freeform "General notes" section. |
| Editing model | Techs suggest updates to General notes; original stays until admin approves. Admin (supervisor role) edits directly and approves/dismisses suggestions. |
| Approval scope | **Freeform General notes only** for now. Structured info/item notes have no in-app editor yet (owner edits via dashboard/Claude). |
| Admin login | Promote the owner's existing account to the existing `supervisor` role — no new role machinery. |

## Screens & navigation

- Three screens inside `index.html`: **Home**, **Checklist** (existing UI),
  **House Notes**. The auth gate is unchanged and sits above all of them.
- After sign-in the user lands on **Home** (not the checklist).
- Home shows three large stacked buttons (thumb-friendly, `min-height` ≥ 48px):
  - **New house visit** → existing search-driven house picker → checklist.
  - **Continue house visit** → list of the tech's in-progress visits
    (house name, visit date, progress) merging cloud `in_progress` visits
    (new `cloud.listInProgress()`) with the local buffer. Tap to resume.
    Empty state: "Nothing in progress" + start-new button.
  - **House notes** → house picker → that house's notes page.
- Screens are driven by the URL hash (`#home`, `#visit`, `#notes/<house>`), so
  the phone/browser **back button navigates between screens** instead of
  exiting the app. A Home button appears in the header on non-Home screens.
- Navigating away from the checklist never touches the local visit buffer —
  the existing "never lose in-progress work" guarantee holds.

## Collapsed sections

- Remove the hardcoded `open` attribute on rendered `<details>` sections
  (checklist sections and Alarm Counts). All start closed on every device,
  every render — including when resuming an in-progress visit.
- Section headers keep their progress counts, so a closed section still shows
  status at a glance. No per-section open-state persistence (YAGNI).

## House Notes page

Layout, top to bottom, for the selected house:

1. **House info** — the label/value lines from the sidebar panel today
   (paint location, attic access, door codes if `house-codes.local.js` is on
   this device). Read-only.
2. **Item notes** — every 📍 note that appears under checklist items, listed
   with its item text. Read-only.
3. **General notes** — freeform text from `houses.general_notes` (new column).
   - **Tech view:** the official note, then any **pending suggestions**
     (author, date, proposed text, "awaiting approval" label — visible to all
     techs to avoid duplicate suggestions), then a **Suggest an update**
     button: opens a textarea pre-filled with the current official note;
     submit creates a `pending` suggestion. The original note is untouched.
     A tech can **withdraw** (delete) their own suggestion while it is still
     pending.
   - **Admin (supervisor) view:** same, plus direct **Edit** of the official
     note (saves immediately) and **Approve** / **Dismiss** on each pending
     suggestion. Approve atomically replaces the official note with the
     suggestion text and marks it `approved`; Dismiss marks it `dismissed`.
     Reviewed suggestions are kept as history (audit trail).

## Data & security (migration `0006_house_notes.sql`)

- `alter table houses add column general_notes text not null default ''`.
- New table `house_note_suggestions`:
  `id uuid pk`, `house_id → houses`, `author_id → profiles default auth.uid()`,
  `proposed_text text`, `status text check in ('pending','approved','dismissed')
  default 'pending'`, `created_at`, `reviewed_by → profiles null`,
  `reviewed_at timestamptz null`.
- RLS (enforced by the database, not the UI):
  - Any signed-in user: **select** all suggestions; **insert** rows where
    `author_id = auth.uid()`; **delete** their own rows while still `pending`.
  - Supervisor only: **update** suggestions (status/review fields) and
    **update** `houses` (already the rule from 0001).
- **Approve is atomic:** a `security definer` function
  `approve_note_suggestion(suggestion_id uuid)` that (a) verifies the caller
  is a supervisor, (b) copies `proposed_text` into `houses.general_notes`,
  (c) marks the suggestion `approved` with reviewer + timestamp — one
  transaction, so a dropped connection can't half-apply it.
- Owner promotion: one SQL line updating their `profiles.role` to
  `'supervisor'`. All SQL handed to the owner as paste-ready chat blocks
  (never terminal output), verified afterwards with a `select count(*)`.

## App-side role handling

- After sign-in, `cloud.js` loads the user's own `profiles.role` and exposes
  it (e.g. `window.cloud.role`). The UI shows admin controls only for
  supervisors; RLS remains the real enforcement.

## Error handling

- Notes page load failure (offline / DB error): plain message, and the
  on-device `house-data.js` info still renders — never a blank page.
  `general_notes` is cloud-only; offline it shows "can't load notes offline".
- Suggestion submit failure: error shown, textarea content preserved.
- `cloud.listInProgress()` failure: Continue list falls back to the local
  buffer with a "couldn't reach the cloud" note.

## Out of scope (explicitly)

- In-app editors for structured house info / 📍 item notes / equipment flags.
- Approval workflow for anything other than General notes.
- Notifications when a suggestion is approved/dismissed.
- Offline creation of suggestions (Phase 5 territory).

## Verification (no automated tests yet)

Drive the real app in a browser, end-to-end:

1. Sign in → lands on Home; all three buttons work; back button returns Home.
2. Checklist sections (incl. Alarm Counts) start closed; progress counts show.
3. Start a visit, save progress, return Home → Continue lists it → resumes.
4. As tech: open House Notes, suggest an update → pending appears, original
   unchanged; reload → still there (row visible in Supabase).
5. As supervisor (owner's promoted account): approve → official note updates,
   suggestion marked approved; dismiss another → note unchanged.
6. Confirm RLS: tech account cannot update `houses` or suggestion status
   (attempt via console fails).
7. Nothing committed/pushed until the owner has seen it working.
