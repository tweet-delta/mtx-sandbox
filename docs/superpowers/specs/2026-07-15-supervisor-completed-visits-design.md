# Supervisor Completed-Visits Review + Home Screen Cleanup — Design

**Date:** 2026-07-15
**Slice:** Part of Phase 4 (supervisor dashboard). Two pieces shaped together
with the owner: (1) a supervisor-only **Completed visits** review screen with a
"new" badge, and (2) a supervisor home-screen cleanup that demotes the field
buttons a supervisor rarely uses. A follow-on slice (in-app checklist task
editing) was agreed as the *next* cycle — explicitly **not** in this spec.

## Goal

The owner (a supervisor) reviews techs' completed visits and surveys. Today
there is **no UI for that at all** — the only visit-history screen is
"My visit history," which shows a tech only their own visits. This slice gives
the supervisor:

- A home button **"✅ Completed visits (N)"** — N = completed visits not yet
  marked reviewed; no badge when caught up.
- A list screen: **Awaiting review** on top, **Reviewed** below, both grouped
  by tech name, newest first within each group. Each row: tech · house ·
  small date, plus a short hint ("2 flagged · 1 note") of what's inside.
- A detail page per visit: the **survey answers**, then only the checklist
  items that were **flagged bad or carry a note** (the same "worth revisiting"
  filter the techs' own history uses). Clean visit → "No issues flagged."
- A **✓ Mark reviewed** button on the detail page. Reviewing permanently
  stamps *who* and *when* (audit trail), moves the visit to the Reviewed
  section, and decrements the badge.

And a decluttered supervisor home screen:

- Headline buttons: ✅ Completed visits (N) · ⏳ Pending changes (N) ·
  🗓️ Daily logs · 📓 House notes · 🗺️ Routes · 👤 My profile · 📋 My notes.
- A collapsed **"🧰 Field tools"** section at the bottom holding 🏠 New house
  visit · ▶ Continue house visit · 🗓️ My visit history. Nothing is removed —
  the owner confirmed supervisors *rarely* run a visit (covering for a tech),
  so the ability stays, demoted. **Techs' home screen is completely
  unchanged.**

## Decisions made with the owner (2026-07-15)

| Question | Decision |
|---|---|
| What clears the "new" badge? | An explicit **✓ Mark reviewed** per visit (not just opening the tab/detail) — supervisor wants a record of what they've actually reviewed. |
| Detail contents | **Survey + problems** (flagged/noted items only), not a full 100+-item replay. |
| List organization | Owner liked both "unreviewed first" and "grouped by tech" → combined: two sections (Awaiting review / Reviewed), each grouped by tech. |
| New/Continue visit buttons for supervisors | **Tuck away, don't remove** — collapsed Field tools section. |
| Checklist task editing | Wanted, but **deferred to the next slice** (it moves `GROUPS` into the DB — much bigger). |

## Non-goals (YAGNI)

- No photos (Phase 2), no filtering/search, no editing a visit's answers,
  no un-review, no notifying the tech their visit was reviewed.
- No checklist-task editor (next slice).
- No pagination — the Reviewed section shows the **last 3 months** (one
  rotation); Awaiting review is never time-limited (unreviewed work must
  never silently disappear).
- No change to any tech-facing screen.

## What already exists (verified in code 2026-07-15)

- `visits.survey jsonb` (0001) — survey answers **are** saved on Save & Send.
- `visits_select` / `profiles_select` RLS (0001) already let a supervisor read
  every visit and every tech's name. `visit_items_all` likewise.
- `visits_update` (0001) already permits supervisor updates — so marking a
  review needs **no new RLS policy**, only new columns + an honest stamp.
- The badge pattern exists: `loadRole()` → `pendingCount()` →
  `window.applyPendingCount(n)` → `#pendingCountBadge`. We add a parallel one.
- The flagged/noted detail filter exists in the tech `#history` detail
  (polarity lookup via `ITEM_BY_KEY`, computed client-side) — reuse it.

## Architecture

### 1. Migration `0020_visit_reviews.sql`

```sql
-- Review audit stamp on completed visits.
alter table public.visits
  add column if not exists reviewed_at timestamptz,
  add column if not exists reviewed_by uuid references public.profiles (id);

-- Server-side stamp so the audit trail is trustworthy: reviewed_by is ALWAYS
-- the caller (auth.uid()), never client-supplied. Same precedent as
-- approve_note_suggestion (0008).
create or replace function public.mark_visit_reviewed(p_visit_id uuid)
returns void
language plpgsql
security definer set search_path = public
as $$
begin
  if public.current_user_role() is distinct from 'supervisor' then
    raise exception 'Only supervisors can review visits';
  end if;
  update public.visits
     set reviewed_at = now(), reviewed_by = auth.uid()
   where id = p_visit_id
     and status = 'completed'
     and reviewed_at is null;      -- first review wins; re-review is a no-op
  if not found then
    raise exception 'Visit not found, not completed, or already reviewed';
  end if;
end $$;

grant execute on function public.mark_visit_reviewed(uuid) to authenticated;
```

Notes:
- Columns are nullable — every existing completed visit starts **unreviewed**
  (owner accepts clearing the ~4 test visits by hand).
- No new RLS policy: reads are covered by `visits_select`; the write goes
  through the security-definer RPC (role-checked inside).
- Applied with `supabase db push` (CLI workflow, no dashboard pasting).

### 2. Data layer (`route-checklist/cloud.js`)

Four additions, all exported on `window.cloud`, all returning `{ error }`
shapes consistent with existing functions:

- **`listCompletedVisits()`** — supervisor list feed. Selects completed
  visits: `id, visit_date, reviewed_at, reviewed_by, houses(name),
  profiles!visits_tech_id_fkey(full_name)` (exact FK name confirmed at build
  time), **plus** their `visit_items(item_key, answer, note)` in the same
  nested select so the per-row "2 flagged · 1 note" hint is computed
  client-side with the existing polarity logic — one query, no N+1.
  Scope: all unreviewed (any age) + reviewed with `visit_date >=` 3 months
  ago. Returns rows sorted newest-first; grouping by tech happens in the UI.
- **`getAnyVisitDetail(visitId)`** — like the existing `getVisitDetail` but
  **without** the `tech_id = me` self-scope (RLS is the gate: a tech calling
  it for someone else's visit gets nothing back). Also selects `survey`,
  `counts`, house name, tech name, `reviewed_at`/`reviewed_by` (+ reviewer
  name for "Reviewed by ‹name› on ‹date›").
- **`markVisitReviewed(visitId)`** — calls the `mark_visit_reviewed` RPC,
  then refreshes the badge count.
- **`unreviewedVisitCount()`** — `count` of completed visits with
  `reviewed_at is null`. Called from `loadRole()` for supervisors and pushed
  via a new **`window.applyReviewCount(n)`** — the exact `pendingCount` /
  `applyPendingCount` pattern.

The existing tech-facing `getVisitDetail` / `listMyVisits` are untouched.

### 3. UI (`route-checklist/index.html`)

**New `#reviews` screen** (hash router: `#reviews` list, `#reviews/<id>`
detail — same pattern as `#history`). Reached from a new home button:

```html
<button type="button" class="home-btn admin-only" id="homeReviews">✅ Completed visits<span class="pending-count" id="reviewCountBadge"></span></button>
```

- **List:** section "Awaiting review" (all unreviewed, grouped by tech,
  newest first within each tech) then "Reviewed — last 3 months" (same
  grouping). Row: `house · small date · hint`. Tech name is the group
  header, not repeated per row. Empty inbox → "You're all caught up."
- **Detail:** header (tech · house · date) → **Survey** section (each SURVEY
  question with its saved answer; unanswered → muted "—") → **Problems**
  section reusing the flagged-or-noted filter/rendering approach from the
  tech history detail (extracted into a shared helper so the two can't
  drift; unknown `item_key`s still show by raw key) → footer: either the
  **✓ Mark reviewed** button or "Reviewed by ‹name› on ‹date›".
- **Mark reviewed flow:** button disables while in flight → RPC → on success
  navigate back to `#reviews` (list re-fetches; visit now appears under
  Reviewed; badge decremented via `applyReviewCount`). On error, inline
  message, button re-enables.

**Supervisor home cleanup:** the three field buttons (🏠 New house visit,
▶ Continue house visit, 🗓️ My visit history) get wrapped in a
`<details id="fieldTools">` with a `<summary>🧰 Field tools</summary>`,
placed at the bottom of the home button stack:

- **Techs (`body:not(.is-admin)`):** the summary is hidden via CSS and the
  `open` attribute is forced on when role resolves → renders exactly as
  today, three plain buttons, no visible wrapper. Signed-out/pre-role state
  behaves as tech (open) so nothing flashes hidden for techs.
- **Supervisors (`body.is-admin`):** summary visible, starts collapsed
  (`open` removed when role resolves). Expanding reveals the three buttons,
  which behave exactly as before — zero logic changes to visits.

**Button order (supervisor):** ✅ Completed visits · ⏳ Pending changes ·
🗓️ Daily logs · 📓 House notes · 🗺️ Routes · 👤 My profile · 📋 My notes ·
🧰 Field tools (collapsed). Tech order: unchanged from today.

### 4. Service worker

Bump `CACHE` `route-checklist-v23` → `v24` (`index.html` + `cloud.js`
change). Remind the owner: hard-refresh (Ctrl+Shift+R), fully close/reopen
the PWA on phones.

## Data flow (happy path)

1. Supervisor signs in → `loadRole()` → `unreviewedVisitCount()` →
   `applyReviewCount(3)` → home shows "✅ Completed visits (3)".
2. Tap it → `#reviews` → `listCompletedVisits()` → Awaiting review: grouped
   rows with hints.
3. Tap a row → `#reviews/<id>` → `getAnyVisitDetail(id)` → survey + problems.
4. Tap ✓ Mark reviewed → `mark_visit_reviewed` RPC stamps
   `reviewed_at = now(), reviewed_by = auth.uid()` server-side → back to
   list → badge shows (2), visit now under Reviewed.

## Edge cases

| Case | Behavior |
|---|---|
| Tech deep-links `#reviews` | Screen is admin-gated in the router (like `#pending`); even if forced, RLS/RPC return nothing/refuse. UI hides, DB enforces. |
| Two supervisors review the same visit at once | RPC's `reviewed_at is null` guard → second call errors "already reviewed"; UI shows the message and re-fetches. First stamp is never overwritten. |
| Visit with empty survey (older data) | Survey section renders questions with muted "—"; no crash. |
| Unknown `item_key` (checklist changed since visit) | Listed under "Other" by raw key — same convention as tech history. |
| Tech has no `full_name` | Group header falls back to "Unnamed tech" (existing convention). |
| `in_progress` visits | Never listed — this screen is completed-only. |
| Badge fetch fails | Badge simply doesn't render; screen still loads its own data. |
| Pre-0020 client cache (stale SW) | Old clients don't know the screen exists; nothing breaks. New client + unapplied migration is a non-case (we push 0020 before deploying), but `isMissingColumn` guards would degrade reads gracefully regardless. |

## Testing (manual — repo convention, no automated tests yet)

**As the supervisor (live site, after hard refresh):**
1. Home shows "✅ Completed visits (N)" with N = existing completed visits;
   "🧰 Field tools" is collapsed at the bottom; expanding it shows New house
   visit / Continue house visit / My visit history, all working.
2. Open Completed visits → Awaiting review grouped by tech, newest first;
   hints match reality (pick a visit known to have flags).
3. Open a visit → survey answers render; only flagged/noted items listed;
   clean visit shows "No issues flagged."
4. Mark reviewed → returns to list, visit under "Reviewed — last 3 months",
   badge decremented; reload → state persisted; detail now says
   "Reviewed by ‹you› on ‹today›".
5. `supabase db query --linked` spot-check: `reviewed_at`/`reviewed_by`
   populated on that row.

**As tech1/tech2:**
6. Home screen identical to before this slice — three field buttons visible
   as plain buttons, **no** Field tools summary, **no** Completed visits
   button. `#reviews` deep-link doesn't render the screen.
7. Complete a visit as tech1 → supervisor's badge increments and the visit
   appears at the top of tech1's Awaiting-review group.

## Files touched

- `supabase/migrations/0020_visit_reviews.sql` — new.
- `route-checklist/cloud.js` — 4 new functions + badge push in `loadRole()`.
- `route-checklist/index.html` — `#reviews` screen, home button + badge,
  Field tools wrapper + role-driven open/collapse, shared detail-filter
  helper.
- `route-checklist/sw.js` — cache bump to v24.
- `route-checklist/HANDOFF.md` — new state section.

## Follow-on slice (agreed, separate cycle)

**In-app checklist task editing** (add/remove/edit `GROUPS` items from the
app). Big: moves checklist content into the DB, touches how every visit
saves, needs its own brainstorm → spec → plan.
