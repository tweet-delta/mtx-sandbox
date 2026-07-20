# Interior Designer Home Screen — Design (Job Titles Slice 3, part 1)

**Date:** 2026-07-19 · **Status:** Approved by owner (conversation Q&A)
**Depends on:** Managed job titles Slice 1 (migration 0027, live) and the
🎫 Tickets feature (migrations 0025–0026, live).

## Goal

Give the **Interior Designer** office title (Gwyn's role at the company) a
real tailored home screen instead of the Slice 1 "your tailored tools are
coming" note. The screen is built entirely from **existing ticket data** —
no new ticket fields — plus one new column on `job_titles` that says which
home layout a title uses.

## Owner decisions (from brainstorming Q&A)

| Question | Decision |
| --- | --- |
| What does the designer's day look like? | **A mix** of executing tickets assigned to her and filing requests for others (trades) to do — so the home leads with both lanes. |
| Slice scope | **Ticket views only.** The orders / awaiting-delivery tracker (ordered → delivered → installed) is real but is its **own later slice** with its own design. Photos on anything wait for Phase 2. |
| Shared office home vs designer-specific? | **Designer-specific screen.** Other office titles keep the current Slice 1 office home. |
| How does a title get the designer screen? | **A `home_screen` field on `job_titles`** (not name-matching — renames must never break the screen; not Slice 2 permissions — over-engineering today). |

## Data model

Migration **0029**:

```sql
alter table job_titles
  add column home_screen text not null default 'office'
  check (home_screen in ('office','designer'));
```

- `'office'` = the existing Slice 1 office home (default; field titles ignore
  the column entirely — kind='field' always gets the field home).
- `'designer'` = the new Interior Designer layout.
- A future Project Director / Carpenter screen is a new allowed value, not a
  redesign. **No RLS changes anywhere in this slice**: `job_titles` is already
  supervisor-write / all-read, and tickets are already readable by every
  signed-in user.

## UI

### 1. 🏷️ Job titles screen (supervisor)

Office-kind titles get a **Home screen** dropdown in their edit form:
"Standard office" / "Interior design". Field titles don't show the dropdown.
Saving updates `job_titles.home_screen`.

### 2. Designer home

When the signed-in user's title has `kind='office'` and
`home_screen='designer'`, home keeps everything the office home shows today
(📌 My tickets, 🎫 Tickets, ＋ New ticket, 🔔, House notes, My notes,
My profile, ⇅ Arrange, Sign out) and **replaces the "tailored tools are
coming" note with three new buttons**, each with a live count badge,
following the existing home-button pattern (and joining ⇅ Arrange ordering
like any other button):

- **📤 My requests** — tickets **submitted by me**. Open ones first
  (status + priority pills, assigned-to shown, priority-sorted then oldest
  first), a "Recently completed" section below (completed, newest first,
  capped ~20). Tap a card → the existing ticket detail screen. Badge = my
  open submitted count. *This view is the "is the thing I asked for done
  yet?" half of her job — `submitted_by` is already stamped on every
  ticket, so it's a query, not a schema change.*
- **💭 Design wish list** — open tickets with priority `wish_list` in a
  **design category** (below), across all houses, oldest first. Badge =
  count. Tap → ticket detail.
- **🏠 Design by house** — houses having ≥1 open ticket in a design
  category, each with its count; tap a house → the existing 🎫 Tickets
  screen pre-filtered to that house. Home-button badge = number of such
  houses (the per-house counts live inside the view).

What she does **not** see is unchanged from Slice 1: no house visits, daily
logs, routes, or field tools.

### 3. Design categories

A single constant in code (easy to tweak later):

```text
Decorating · Furniture · Interior Painting · Flooring · Windows · Ceiling
```

Only 💭 Design wish list and 🏠 Design by house filter by it; 📤 My requests
shows everything she filed regardless of category.

## Error handling

Same online-first pattern as the rest of the app: each view shows a visible
load-failure state with a Retry button; count badges fail silent (no badge)
rather than blocking home render.

## Testing & verification

- Playwright test (pattern: `tests/tickets.test.py`): give a test title
  `home_screen='designer'`, sign in as its holder → the three buttons render
  with correct counts; file a ticket as that user → appears in 📤 My
  requests; a seeded wish-list Decorating ticket appears in 💭; its house
  appears in 🏠 with the right count; non-designer office title still gets
  the Slice 1 note.
- Manual: drive the flows in the browser; confirm `home_screen` persists via
  `supabase db query --linked`.
- Accessibility: buttons/cards keyboard-reachable with visible focus, badge
  counts in `aria-label`s, reduced-motion respected.
- Ship: service-worker version bump, merge to `main` same session,
  `curl` the live `sw.js` to prove the deploy, remind owner to hard-refresh.
- Real-life rollout note: Gwyn isn't an app user yet. When ready, add her
  via 👥 Team → Add new team member and assign the Interior Designer title
  (whose `home_screen` the owner flips to "Interior design").

## Out of scope (later slices)

- **Orders / awaiting-delivery tracker** (ordered → delivered → installed)
  — its own design conversation, likely the next designer slice.
- **Photos** on tickets/rooms — arrives with Phase 2 storage.
- Project Director / Carpenter screens — reuse the `home_screen` seam.
- Slice 2 pick-and-choose permissions — untouched, still undecided.
