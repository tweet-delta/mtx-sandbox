# Maintenance Tickets — Design

**Date:** 2026-07-18 · **Status:** Approved by owner (via visual mockup)
**Mockup:** `2026-07-18-maintenance-tickets-mockup.html` (open in a browser)

## Goal

Bring the company's SharePoint "Current Maintenance Requests" workflow into
the demo app: anyone signed in can file a ticket, techs see and work a
house's open tickets while on a visit, and supervisors triage everything
with filters. The demo mirrors the real list's *shape* exactly so a future
official migration into company M365 is a plain data copy — **no real data
enters Supabase or this repo** (fake demo houses/people only).

## What we learned from the real list (captured 2026-07-18)

Viewed the live classic-SharePoint list with the owner signed in. Shape
copied; real house/staff names deliberately not recorded here.

- **Fields:** Title, House Name, Category, Status, Level, Requested By
  (a role), Assigned To (person or Unassigned), Priority, Submitted By,
  Created, Modified.
- **Status values:** New, Open, In Progress (+ On Hold view, Completed
  implied). Demo uses: `new`, `in_progress`, `on_hold`, `completed`
  (real "Open" maps to `new`).
- **Priority values:** Urgent, Time Sensitive, Normal Priority, Wish List.
- **Level values:** Resident Level, RS Level (matches the app's duplex model).
- **Requested-by roles:** RS, PD, RC, Staff, Guardian, Live In, Maintenance.
- **Categories (~25):** Flooring, Plumbing, Doors, Windows, Electrical,
  Appliance Issues, Landscaping, Pest Control, Carpentry, Gutters, Fences,
  Roofing, Ceiling, Railings, Decorating, Furniture, Interior Painting,
  Exterior Painting, Deck Sealing or Repair, Sidewalk or Driveway,
  Tree Trimming or Removal, Items to Haul Away, Fire Extinguisher,
  Van or Vehicle Issues, Other Bathroom Issues, Other Kitchen Issues,
  Other/Unsure, **House Visit List** (= "do at next routine visit").
- **Views today** map to filter chips, not separate screens: All Open /
  Current Priority / Wish List-On Hold / by House.
- "Unassigned" is an **Assigned To** state, not a priority.

## Owner decisions (from brainstorming Q&A)

| Question | Decision |
|---|---|
| SharePoint sync now? | No — needs IT/Graph approval we don't have. Demo-only data, same shape; sync is the someday-migration. |
| Who submits in-app? | **Everyone signed in** (any job title). "Requested by" is a role dropdown since real requesters often phone it in. |
| Tech powers on tickets | **Work them:** change status (In Progress / On Hold / Completed) + add notes. Only supervisors assign, re-prioritize, or edit others' tickets. |
| Tech home screen | Yes — **📌 My tickets** (open, assigned to me, grouped by house, priority-sorted). |
| Scope | **Approach C**: full slice + completed history + route-preview badges. |
| Urgent-ticket email | **Not needed** — RingCentral already alerts on urgent. Instead: in-app notifications on (a) being assigned a ticket, (b) comments on a ticket you're involved in; plus a computed **Stale ≥30 days** filter. |

## Data model (Supabase migration)

### `tickets`
| column | type | notes |
|---|---|---|
| id | uuid PK | |
| house_id | FK → houses | |
| title | text, required | |
| description | text | |
| category | text, required | one of the fixed category list (CHECK) |
| level | text | `resident` \| `rs` (CHECK) |
| status | text | `new` \| `in_progress` \| `on_hold` \| `completed`, default `new` |
| priority | text | `urgent` \| `time_sensitive` \| `normal` \| `wish_list`, default `normal` |
| requested_by_role | text | `rs` \| `pd` \| `rc` \| `staff` \| `guardian` \| `live_in` \| `maintenance` |
| submitted_by | FK → profiles | stamped at insert |
| assigned_to | FK → profiles, nullable | null = Unassigned |
| created_at / updated_at | timestamptz | `updated_at` maintained by trigger on ticket update **and** on note insert |
| completed_at / completed_by | timestamptz / FK | stamped when status → completed |

Stale = `status not in (completed)` AND `updated_at < now() - interval '30 days'` — computed in queries, never stored.

### `ticket_notes`
id, ticket_id FK, author FK → profiles, body text, kind (`comment` \|
`status_change` \| `assignment`), created_at. System rows (status/assignment
changes) are inserted by the app-facing RPCs so the history trail is complete.

### `notifications`
id, recipient FK → profiles, ticket_id FK, kind (`assigned` \| `comment`),
actor FK → profiles, created_at, read_at nullable. Created by DB triggers:

- assignment change → notify the new assignee (not if self-assigned)
- note insert (kind=comment) → notify ticket's submitter, assignee, and all
  supervisors, **minus the author**

### RLS
| action | tech | supervisor |
|---|---|---|
| read tickets / notes | ✅ all | ✅ all |
| insert ticket | ✅ (submitted_by = self) | ✅ |
| add comment note | ✅ | ✅ |
| change status | ✅ via RPC (writes status_change note) | ✅ |
| assign / change priority / edit fields | ❌ | ✅ |
| notifications | read + mark-read own rows only | same |

Status/assignment changes go through `security definer` RPCs (like the
existing `mark reviewed` RPC) so the note trail + guards can't be bypassed.

## UI (six pieces — see mockup)

1. **Home:** new buttons **📌 My tickets** (open count) and **🎫 Tickets**
   (all-open count) for everyone; **🔔 bell** with unread-notification count.
2. **🎫 Tickets screen:** filter chips with live counts — New · Unassigned ·
   Urgent · Time sensitive · Wish list · Stale 30d+ · All open · Completed —
   plus a house picker. Sort: priority (urgent → wish list), then oldest
   first. Supervisor cards get Assign ▾ and Priority ▾ controls inline.
3. **Ticket detail:** pills (priority/status/level), meta, description, then
   one **History** trail (comments + system entries interleaved), note
   composer, status buttons per role.
4. **Visit integration:** the checklist screen shows a collapsible
   **"🎫 Open tickets at this house (N)"** panel above the checklist for the
   visited house; **House Visit List** category pinned to top; actions:
   In Progress / Completed / add note.
5. **＋ New ticket form:** house, level, title, description, category,
   priority, requested-by role. Submitter + timestamps stamped automatically.
6. **🔔 Notifications screen:** unread-first list ("You were assigned…",
   "X commented…"), tap-through to the ticket, Mark all read.
   **Route badges:** each house in the route preview shows its open-ticket
   count.

## Seed data (fake only)

~20 tickets across the existing demo houses: mixed categories, all four
priorities, some assigned to tech1/tech2, a couple In Progress, a couple
Completed, 2–3 backdated >30 days to demonstrate Stale, at least one
House Visit List item per demo house so the visit panel shows content.

## Quality bar

- Accessibility: chips/buttons keyboard-reachable with visible focus,
  `aria-pressed` on filter chips, bell count in `aria-label`, panels are
  real `<button>`/`<details>` semantics, reduced-motion respected.
- Never lose work: note composer buffers to localStorage until sent.
- Online-first with visible failure + retry (matches the rest of the app).
- Service-worker version bump; ship to `main` same session; verify live via
  `curl` of `sw.js`; remind owner to hard-refresh.
- Verification: drive every flow in the browser + a Playwright test
  (pattern: `tests/daily-log-partial-visit.test.py`) covering
  create → assign → work-in-visit → complete → notification.

## Out of scope (later slices)

- Real SharePoint/Graph sync (needs IT approval; field mapping above keeps
  it a data-copy).
- Email / RingCentral integration (RingCentral already covers urgent).
- Photos on tickets (arrives with Phase 2 storage).
- Requester-role logins (RS/PD accounts submitting directly).
