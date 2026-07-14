# In-checklist house info panel (codes stay local) — design

**Date:** 2026-07-14
**Status:** Approved (owner, 2026-07-14)
**Branch:** `claude/claude-code-tutorial-5l5ew2`

## Problem

While running a checklist, a tech needs the current house's info — paint
location, attic access, and especially **entry/med-lock/garage/apartment/alarm
codes** — without scrolling to the bottom of a long list or opening the ☰
Houses sidebar (which shows all 48 houses in a picker the tech doesn't need
mid-visit). Today that info lives in `#houseInfo` inside the sidebar.

## Goal

One tap from anywhere in the checklist opens a panel showing **only the current
house's** codes and info. The ☰ sidebar slims to an account-only menu.

## Owner decisions captured

| Question | Decision |
|---|---|
| Panel content | House info pairs **+ codes** (garage, med lock, apartment/door, alarm — all code rows) |
| Codes source | **Stay local-only** in `house-codes.local.js` (gitignored, on-device). Codes are **not** moved to Supabase — this keeps the strongest compliance posture (real codes never leave the device). |
| How it opens | **ℹ️ House info button in the sticky visit header** → modal panel |
| Sidebar fate | **Slim to an account menu** (signed-in-as, change password, sign out) |

## Non-goals (this slice)

- Moving codes into Supabase / any database. Explicitly rejected by the owner
  — codes remain in `house-codes.local.js` only.
- In-app editing of codes (they're edited by hand in the local file, as today).
- Code change history / audit trail.
- Offline caching beyond what the SW already does (Phase 5, offline-first).
- Touching the House Notes (`#notes`) screen's own info/notes editing.

This is a **front-end-only** slice: no migration, no `cloud.js` change, no RLS
change. Codes and info both come from data already on the device
(`house-codes.local.js` via `ALL_CODES`, and `h.info` from the houses cache).

---

## Part A — the ℹ️ button and panel

### 1. ℹ️ House info button (sticky visit header)

- Added to the `.titlerow` in the visit header (next to ☰), so it's reachable
  from anywhere in the checklist without scrolling — the header is already
  `position: sticky`.
- Hidden until a house is selected (no house → nothing to show). Its visibility
  is toggled wherever house state already updates the header (`selectHouse()` /
  the same place the house field is set).
- `aria-label="House info"`; keyboard-focusable; visible focus ring (existing
  `:focus-visible` styling applies).

### 2. The panel (modal `<dialog>`)

Reuse the existing survey-modal pattern (`<dialog>`, `.modal-card`,
`.modal-head` with ✕, focus trap, Esc to close, `prefers-reduced-motion`
respected). Content, for the **current house only**:

- **Codes section first** — the `[label, value]` rows from `ALL_CODES[h.name]`
  (populated by `house-codes.local.js`), rendered with the existing
  `.info-item.code` styling. If the local codes file isn't present on this
  device, `ALL_CODES[h.name]` is empty → the codes section is simply omitted
  (no error, no empty header). This is the same graceful behavior the sidebar
  panel has today.
- **House info pairs** below — the same `h.info` `[label, value]` content
  `renderHouseInfo()` shows today (paint, attic access, etc.).

The panel's render is effectively the existing `renderHouseInfo()` markup moved
into a modal, keyed to the current house. Because both data sources are already
in memory, opening is synchronous — no loading state needed.

### 3. Wiring

- New `openHouseInfo()` builds the panel body from the current house and shows
  the `<dialog>`; ✕/Esc closes it and returns focus to the ℹ️ button.
- The ℹ️ button's click handler calls `openHouseInfo()`.
- `renderHouseInfo()` is repurposed to fill the modal body (or a small
  `renderHouseInfoInto(el)` helper it delegates to), so there's one source of
  truth for the info/codes markup.

---

## Part B — slim the ☰ sidebar to an account menu

- Remove from the sidebar: the house list (`#houseList`), search input
  (`#houseSearch`), 🔍 toggle (`#houseSearchToggle`), and the `#houseInfo`
  panel. Their now-unused JS (`renderHouseList`, `toggleHouseSearch`, the
  house-list click handler, the search `input` handler, the 🔍 toggle handler)
  is removed with them.
  - **Verify first** that nothing else depends on `renderHouseList` /
    `#houseList` before deleting (grep). The up-front house *picker* on the
    checklist (`#house` field + its own picker UI) is separate and stays.
- **Keep:** the `#account` block — "Signed in as…", Set/change password,
  Sign out. `openSidebar()` no longer calls `renderHouseList()`; it may still
  render nothing but the account block.
- The header button changes from `☰ Houses` to **👤** with
  `aria-label="Account"` so it reads as account, not house-picking.
- **House switching** already has a safe path: **← Home → 🏠 New house visit**,
  and `selectHouse()` confirms before discarding unsaved work. No new
  house-switch UI is needed on the checklist screen.

---

## Part C — housekeeping

- Bump SW cache `v19` → `v20` (`index.html` changes; `sw.js` bumps).
- Update `HANDOFF.md` with the new state (ℹ️ panel, slimmed sidebar,
  codes-stay-local decision, live-verify checklist).
- Remind owner: hard-refresh (Ctrl+Shift+R) after deploy; fully close/reopen
  the PWA on phones.

No `cloud.js` change, no migration, no memory/compliance change (the earlier
"codes never in Supabase" posture is unchanged — this slice honors it).

---

## Verification (live)

Run on the deployed site after push (hard-refresh, may take two for v20 SW):

1. Sign in → start a visit at a house that has codes in `house-codes.local.js`
   → the **ℹ️** button appears in the header → tap it → panel shows that house's
   codes (garage/med-lock/apartment/alarm as applicable) then info pairs.
   Esc/✕ closes; focus returns to ℹ️.
2. Start a visit at a house with **no** info and (on a device without the local
   file) no codes → ℹ️ still opens a clean panel (or the button is present and
   the panel shows only what exists) — no error, no empty headers.
3. On a device **without** `house-codes.local.js` → panel shows info pairs only,
   no codes section, no error.
4. Confirm the ☰→👤 menu shows only account actions (no house list, no search);
   confirm ← Home → New house visit still confirms before discarding unsaved
   work.
5. Deep-link reload while a visit is open → header + ℹ️ still work, no console
   errors. Keyboard: Tab to ℹ️, Enter opens, Esc closes, focus returns.

Test accounts: `tech1@example.com`, `tech2@example.com`.
