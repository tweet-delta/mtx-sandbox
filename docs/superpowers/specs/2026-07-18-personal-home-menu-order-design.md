# Personal home-menu ordering — design

**Date:** 2026-07-18
**Status:** Approved (owner), pending spec review before planning.

## Context

The owner asked: while a tech (or anyone) is signed in, let each person
**customize the order of their home-screen buttons** — move Notes higher, My
profile lower, etc. — **without being able to add or remove anything**. Everyone
still sees the same set of buttons their role grants them; they can only
rearrange them.

The home screen (`#homeScreen` in `route-checklist/index.html`) is a flat stack
of `class="home-btn"` buttons, each with a stable hardcoded `id`
(`homeNewVisit`, `homeNotes`, `homeProfile`, …). Some carry `admin-only`, so a
tech never sees them (`body:not(.is-admin) .admin-only { display:none }`). The
stack ends with a supervisor-only `🧰 Field tools` drawer (`#fieldTools`) and a
`Sign out` button.

**Critical implementation constraint (verified in code):** each button is wired
to its behavior by its hardcoded id via
`document.getElementById("homeNewVisit").addEventListener("click", …)` (index.html
~L2894 onward). Therefore reordering must **move the existing DOM nodes** — never
recreate the buttons from a template — or the click listeners are lost. We change
order only; the elements and their listeners are untouched.

This is the smallest complete slice: **home menu buttons only**, per the owner's
standing rule (build the smallest complete slice first, then widen).

## Decisions locked in (from the owner)

| Question | Decision |
| --- | --- |
| Scope | **Home menu buttons only** (not the in-checklist sections, not all screens). |
| Storage | **Cloud, per-user** — the order follows the person to every device. |
| Interaction | **Arrange mode + up/down controls** (no drag-and-drop — touch-reliable, accessible). |
| New buttons added later | Appear at the **bottom** of an already-customized order; nothing they arranged shifts. |
| Pinned items | **Both** `🧰 Field tools` drawer **and** `Sign out` stay pinned at the bottom; only the buttons above them reorder. |

## Goals

1. Any signed-in person can reorder their home-screen buttons.
2. The order is saved **per user, in the cloud**, so it is the same on every
   device they sign in on.
3. A person can **never** add or remove a button via this feature — only
   rearrange. Their role still governs which buttons exist for them.
4. A stale or role-mismatched saved order can never make a button disappear:
   the order is reconciled against the real, visible button set on every load.
5. `Field tools` and `Sign out` are always pinned last.
6. Fully accessible (keyboard-operable arrows, `aria-label`s, `:focus-visible`),
   consistent with the app's existing accessibility posture.

## Non-goals (explicit)

- Reordering **checklist room groups** or any in-visit section (a much bigger,
  consistency-sensitive change — deferred).
- Reordering any screen **other than** the home menu.
- **Hiding** buttons a person doesn't want (this is order-only; the owner's
  constraint is explicitly "can't remove").
- Drag-and-drop.
- A supervisor setting a default order for the whole team (each person's order
  is their own; nobody else's).

## Architecture

Pure front-end + `cloud.js` + one additive migration. The preference is modeled
as **an ordered array of button-id strings** — the smallest possible
representation, and the reason "can't add/remove" holds by construction: an id in
the saved array that isn't a real, visible button is simply ignored, and a real
button missing from the array is appended. There is no way for the array to
manifest a button the role doesn't grant.

### 1. Migration `0022_profiles_home_order.sql`

Add one nullable column to `public.profiles`:

```sql
alter table public.profiles
  add column if not exists home_order text[];
```

`null` (the default) means "use the app's default order." No RLS or grant
changes: the existing `profiles_update` policy (migration 0001) already lets a
person update **their own** profile row — exactly the scope wanted (you order
your menu, nobody else's). No trigger needed; the value is advisory display data,
never a security boundary.

### 2. `cloud.js` — two new functions (on `window.cloud`)

- `getHomeOrder()` → `{ order: string[] | null }`. Reads `home_order` from the
  caller's own `profiles` row (via `auth.getUser()` id). On any error, or if the
  column is missing, returns `{ order: null }` so the caller falls back to the
  default order rather than erroring.
- `saveHomeOrder(ids)` → `{ error? }`. Writes `ids` (a `string[]`) to the
  caller's own row. Uses the same `isMissingColumn` degrade pattern as
  `saveMyProfile` / `saveProfileAsSupervisor`: if the column doesn't exist yet,
  it returns `{ degraded: true }` instead of throwing, so an un-migrated database
  just doesn't persist the order.

Both target the caller's own id only; neither bulk-updates.

### 3. Home screen — Arrange mode (index.html)

**Trigger.** A small text button `⇅ Arrange` in the home `screen-head` next to
the `<h1>`, visible to everyone. Tapping it toggles arrange mode on the home
screen (a `body`/container flag, e.g. `homeScreen.classList.toggle("arranging")`)
and relabels itself `✓ Done`.

**In arrange mode:**

- Each **reorderable** button (every currently-**visible** `home-btn` except the
  pinned ones — i.e. `admin-only` buttons hidden for the person's role never get
  arrows and are never reordered) shows an injected **↑ / ↓** control pair,
  revealed by CSS only while `.arranging` is set. The controls are real `<button>`s with `aria-label`s
  ("Move House notes up" / "…down"), keyboard-operable, `:focus-visible`
  preserved.
- The button's normal click-to-navigate is suppressed while arranging (so tapping
  the row body doesn't launch a screen); only the arrows act.
- `🧰 Field tools` and `Sign out` are **not** given arrows and are visually set
  apart (dimmed / labelled "stays at bottom") so it's clear they're pinned.
- **↑ / ↓** swap the button with its previous/next reorderable sibling via
  `insertBefore` on the existing nodes — instant live preview, listeners intact.
  The first item's ↑ and the last item's ↓ are `disabled`.

**Exiting (`✓ Done`, or navigating away):** read the current DOM order of the
reorderable buttons into an id array, call `saveHomeOrder(ids)`, remove the
`.arranging` flag, restore normal click behavior. Every move is already the live
on-screen state, so "Done" simply persists what is shown — there is no separate
draft to discard, matching the app's "never lose in-progress work" instinct. A
failed save keeps the on-screen order for the session and shows a small inline
"Couldn't save your order" note.

### 4. Reconcile-on-load (the safety net)

Runs on every home render, **after role is known** (`body.is-admin` already set,
so `admin-only` buttons are correctly shown/hidden):

1. Read the ids of the currently **visible, reorderable** `home-btn`s from the
   DOM (this set already excludes role-hidden `admin-only` buttons and the pinned
   Field tools / Sign out).
2. `getHomeOrder()` → saved array (or `null` → skip; leave default order).
3. Build the effective order: **keep** saved ids that are in the visible set (in
   saved sequence), then **append** any visible id not in the saved array (new /
   previously-hidden buttons land at the bottom).
4. Apply it by `insertBefore`-ing the existing nodes into that order, always
   leaving `#fieldTools` and `Sign out` last.

Because step 1 reads the live visible set, a tech and a supervisor can hold the
same saved array and each get a correct, gap-free menu; and a button added in a
future release automatically appears at the bottom of everyone's menu without any
migration of their saved arrays.

## Data flow

1. Sign-in runs `loadRole()` → sets `body.is-admin` → home shows the right button
   set.
2. Home render calls the reconcile step → `getHomeOrder()` → DOM reordered to the
   effective order (or default if none/unavailable).
3. Person taps `⇅ Arrange` → arrange mode; ↑/↓ reorder live.
4. `✓ Done` → `saveHomeOrder(currentIds)` → persisted to their `profiles` row.
5. Next sign-in on any device → step 2 restores their order.

## Error handling

- `home_order` column missing, or `getHomeOrder()` fails → fall back to the
  **default order**; no banner, arranging just isn't persisted this session.
- `saveHomeOrder()` fails → keep the on-screen order for the session, show a small
  inline "Couldn't save your order" note; nothing is silently lost.
- A saved id that no longer exists or the role can't see → ignored by reconcile
  (never shown, never errors).
- A visible button missing from the saved array → appended at the bottom.

## Testing / verification

No automated harness in this repo. Verify by:

1. **Parse check** — headless Chrome, zero SyntaxError; home renders; `cloud.js`
   loads clean over `python -m http.server`.
2. **Live, signed in** (after hard-refresh; SW cache bumped):
   - As a **tech**: `⇅ Arrange` → move `📋 My notes` to the top, `👤 My profile`
     lower → `✓ Done` → reload → order persists. Confirm the row in Supabase
     (`select home_order from profiles where id = …`).
   - After reordering, **tap a moved button** and confirm it still navigates
     correctly (proves DOM nodes moved, listeners survived).
   - As a **supervisor**: admin-only buttons participate in ordering correctly;
     `🧰 Field tools` and `Sign out` stay pinned at the bottom regardless of the
     saved array.
   - **New-button simulation**: with a saved array that omits one real visible id,
     confirm that button appears at the **bottom** on load (not missing, not
     mid-list).
   - **Stale-id tolerance**: put a bogus id in `home_order` via `db query`, reload,
     confirm no error and no phantom button.
   - Keyboard: Tab to an arrow, activate with Enter/Space, order changes; focus
     ring visible.

SW cache version bumped (next `v` after current) since `index.html` + `cloud.js`
change. Merged to `main` and pushed the same session per the owner's standing
rule.

## Widening later (context, not built here)

The same id-array + reconcile model extends cleanly if the owner later wants
in-checklist section ordering or per-team default orders — but each is its own
brainstorm → spec → cycle. This slice is self-contained.
