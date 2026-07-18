# Maintenance Tickets Implementation Plan

> **For agentic workers:** REQUIRED SUB-SKILL: Use superpowers:subagent-driven-development (recommended) or superpowers:executing-plans to implement this plan task-by-task. Steps use checkbox (`- [ ]`) syntax for tracking.

**Goal:** Full maintenance-ticket workflow (create → triage → work during visits → complete) with in-app notifications, mirroring the company SharePoint list's shape, per `docs/superpowers/specs/2026-07-18-maintenance-tickets-design.md`.

**Architecture:** One migration adds `tickets` + `ticket_notes` + `notifications` with RLS, two security-definer RPCs (status change, assignment) and triggers (updated_at touch, comment fan-out). `cloud.js` grows a tickets section exposed on `window.cloud`. `index.html` gains four hash-routed screens (#tickets, #ticket/<id>, #newticket, #alerts), a visit-screen panel, home buttons/badges, and picker badges. A CDP-driven Python test mirrors `tests/daily-log-partial-visit.test.py`.

**Tech Stack:** Vanilla JS (no deps), Supabase (Postgres + RLS + RPC), Supabase CLI (`supabase db push`), Python + websocket-client + headless Chrome for the test.

## Global Constraints

- Fake demo data only — no real house/staff names anywhere in repo or DB.
- Statuses exactly: `new`, `in_progress`, `on_hold`, `completed`. Priorities exactly: `urgent`, `time_sensitive`, `normal`, `wish_list`. Levels: `resident`, `rs`. Requester roles: `rs`, `pd`, `rc`, `staff`, `guardian`, `live_in`, `maintenance`.
- RLS is the enforcement; UI hiding is convenience only.
- Stale = open ticket with `updated_at < now() - 30 days`, always computed, never stored.
- Accessibility: chips are `<button aria-pressed>`, badges have text equivalents, focus-visible preserved.
- SW cache bump to `route-checklist-v29` before ship; merge to `main` + push + `curl` the live `sw.js` to prove deploy.

---

### Task 1: Migration `0025_tickets.sql`

**Files:**
- Create: `supabase/migrations/0025_tickets.sql`

**Interfaces produced:** tables `tickets`, `ticket_notes`, `notifications`; RPCs `set_ticket_status(p_ticket_id uuid, p_status text)`, `assign_ticket(p_ticket_id uuid, p_assignee uuid)`; category list constant (28 values, see SQL).

- [ ] **Step 1: Write the migration** — full SQL as drafted (tables + CHECKs + indexes + RLS: tickets select all-authenticated / insert self / update supervisor-only; notes select all / insert self comments only; notifications select+update own; `touch_tickets_updated_at` BEFORE UPDATE trigger; `touch_ticket_on_note` + `notify_on_comment` AFTER INSERT triggers on ticket_notes; both RPCs security definer with `current_user_role()` guard on assign).
- [ ] **Step 2: `supabase db push`** — expect "Applying migration 0025".
- [ ] **Step 3: Verify** — `supabase db query --linked` (or psql via CLI) selecting from the three tables and calling the RPCs with a bogus id (expect the raise). Verify RLS enabled via `select relrowsecurity from pg_class`.
- [ ] **Step 4: Commit** `feat(db): tickets, notes, notifications with RLS + RPCs`.

### Task 2: Seed migration `0026_seed_demo_tickets.sql`

**Files:**
- Create: `supabase/migrations/0026_seed_demo_tickets.sql`

- [ ] **Step 1: Write seed** — DO block, guarded by `if not exists (select 1 from public.tickets)`. Picks the 6 first active houses alphabetically and up to 2 tech profiles + 1 supervisor. Inserts ~20 tickets cycling categories/priorities/statuses; ≥3 with `created_at`/`updated_at` older than 40 days (stale demo); ≥4 category `House Visit List`; a few completed with stamps; mix of assigned/unassigned.
- [ ] **Step 2: `supabase db push`**, then query counts per status/priority to verify ≥20 rows, ≥3 stale.
- [ ] **Step 3: Commit** `feat(db): demo ticket seed (fake data)`.

### Task 3: `cloud.js` tickets API

**Files:**
- Modify: `route-checklist/cloud.js` (new section before `window.cloud`, plus keys on `window.cloud`, plus badge refresh after `loadRole()` in the auth callback)

**Interfaces produced (all on `window.cloud`):**
- `listTickets()` → `{ tickets: [{id,title,description,category,level,status,priority,requestedByRole,houseName,submittedByName,assignedTo,assignedToName,createdAt,updatedAt,completedAt,noteCount}] } | { error, notReady }`
- `getTicket(id)` → same shape + `notes: [{id,kind,body,authorName,createdAt}]`
- `createTicket({houseName,level,title,description,category,priority,requestedByRole})` → `{ id } | { error }`
- `addTicketNote(id, body)` → `{ ok } | { error }`
- `setTicketStatus(id, status)` → RPC → `{ ok } | { error }`
- `assignTicket(id, assigneeId)` (null = unassign) → RPC → `{ ok } | { error }`
- `setTicketPriority(id, priority)` → supervisor direct update → `{ ok } | { error }`
- `listNotifications()` → `{ items: [{id,kind,ticketId,ticketTitle,houseName,actorName,createdAt,readAt}] }`
- `markAllNotificationsRead()` → `{ ok } | { error }`
- `refreshTicketBadges()` — computes `{ mineOpen, allOpen, byHouse: {lowerName: n}, unread }` and calls `window.applyTicketCounts(...)`; invoked after sign-in and after every mutate.

- [ ] Steps: implement, wire `refreshTicketBadges()` into `onAuthStateChange` after `loadMyRoute()`, commit `feat(cloud): tickets + notifications API`.

### Task 4: Screens & routing shell in `index.html`

**Files:** Modify `route-checklist/index.html`
- CSS `body:not([data-screen=…])` block: add `tickets`, `ticket`, `newticket`, `alerts`.
- Home screen: `🎫 Tickets` + `📌 My tickets` buttons (all users) with `pending-count` badges; `🔔 Notifications` button with unread badge.
- Screen divs `#ticketsScreen #ticketDetailScreen #newTicketScreen #alertsScreen` following existing screen-head pattern.
- `currentScreenFromHash()` + `showScreen()` + home button click handlers (`#ticket/<id>` before `#tickets` in matching!).
- `window.applyTicketCounts` painting the three badges + storing `byHouse` for Task 7.
- [ ] Commit `feat(ui): ticket screen shells + home buttons + badges`.

### Task 5: Tickets list + detail + actions

**Files:** Modify `route-checklist/index.html`
- `TICKET_CATEGORIES`, `TICKET_PRIORITIES/STATUSES/ROLES` label maps + pill CSS (`.tk-pill` variants per mockup colors).
- `renderTicketsScreen()`: chips (buttons, `aria-pressed`) New/Unassigned/Urgent/Time sensitive/Wish list/Stale 30d+/All open/Completed with live counts; house `<select>`; `#tickets/mine` variant (My tickets: assigned to me, open, skip chips row except priority sort). Cards: title, house, pills, meta line; click → `#ticket/<id>`.
- `renderTicketDetailScreen()`: pills, meta, description, history (notes newest-last, system rows italic), note composer (localStorage draft `tk-draft-<id>`, cleared on send), status buttons (all users), supervisor-only Assign `<select>` (from `listTechs()` + unassign) and Priority `<select>`.
- [ ] Commit `feat(ui): tickets list, filters, detail, actions`.

### Task 6: New-ticket form

**Files:** Modify `route-checklist/index.html`
- `renderNewTicketScreen()`: house select (from `listHousesForRoutes()`), level, title, description, category, priority, requested-by role; validate title+house; on success go to `#ticket/<id>`; entry buttons on home + tickets screen.
- [ ] Commit `feat(ui): new ticket form`.

### Task 7: Visit panel + picker badges

**Files:** Modify `route-checklist/index.html`
- In `build()` when a house is selected: `<details id="visitTickets">` before the first group; `paintVisitTickets()` fetches via `listTickets()`, filters house + open, House Visit List first, then priority; per-card status buttons + quick-note (reuses `setTicketStatus`/`addTicketNote` then repaint + `refreshTicketBadges`).
- `pickListHTML()`: append `<span class="tk-count">N open</span>` from `byHouse` map when N > 0.
- [ ] Commit `feat(ui): visit ticket panel + picker badges`.

### Task 8: Notifications screen

**Files:** Modify `route-checklist/index.html`
- `renderAlertsScreen()`: unread first (accent left border), "You were assigned…"/"X commented on…", tap-through to `#ticket/<id>`, "Mark all read" button → `markAllNotificationsRead()` + badge refresh.
- [ ] Commit `feat(ui): notification center`.

### Task 9: Automated test `tests/tickets.test.py`

**Files:** Create `tests/tickets.test.py` (copy the CDP harness from `tests/daily-log-partial-visit.test.py`; extend the supabase wrapper so `from('tickets')` selects return canned rows and rpc calls are captured).
Asserts:
1. `createTicket` inserts a `tickets` payload with the chosen fields.
2. `#tickets` renders the canned tickets and chip counts (urgent chip shows 1; stale chip counts the backdated row).
3. Clicking ✔ Completed on the detail screen fires rpc `set_ticket_status` with `completed`.
4. Visit panel lists only the selected house's open tickets.
- [ ] Run: `python tests/tickets.test.py` → RESULT: PASS. Commit `test: ticket flow e2e (mocked supabase)`.

### Task 10: Ship

- [ ] Bump `sw.js` cache to `route-checklist-v29`; add nothing to SHELL (no new files).
- [ ] Manual drive: sign in, create ticket, filter, assign (supervisor), status change, visit panel, bell. Check real rows in Supabase.
- [ ] Update `route-checklist/HANDOFF.md` + `START-HERE.md`.
- [ ] Commit, push `main`, `curl -s https://tweet-delta.github.io/mtx-sandbox/route-checklist/sw.js` until it shows v29, remind hard-refresh.
