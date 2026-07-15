# CLAUDE.md — MTX Route Checklist

Guidance for any Claude Code session working in this repo. Read this first,
then `route-checklist/HANDOFF.md` for the current app's details.

---

## Who I'm working with

The owner (hfwinter16@gmail.com) is **learning to build software** and has
asked to be **taught as we go**. Explain the *why*, not just the *what*.
Introduce one new concept at a time. Prefer a short, correct explanation over a
long one. When you use a term of art (RLS, migration, bundler, edge function),
define it the first time in a given session.

## How we work together (the owner's standing rules)

These are non-negotiable. They were set by the owner and apply to every task:

1. **No bandaids.** Fix the actual cause, not the symptom. If a proper fix is
   bigger, say so and do it anyway (or explain the tradeoff and let them choose).
2. **No shortcuts.** Don't cut corners to look done. "Works on my machine once"
   is not done.
3. **No guessing.** If a fact decides the design (a schema, an email recipient,
   a business rule), **ask** — don't assume. Verify against the code before
   claiming something is true.
4. **Enterprise-level quality.** Security, accessibility, error handling, and
   data integrity are part of the definition of done, not extras.
5. **Ask plenty of questions** to help the owner clarify their ideas before you
   build.
6. **Push back when something is silly** — including pushing back on the owner.
   Over-engineering is also silly; call that out too.

A corollary the owner and I agreed on: **build the smallest complete slice
first, then widen.** Thin-and-working beats broad-and-broken.

---

## What this project is

A field tool for **maintenance techs servicing Minnesota group homes**. Techs
visit duplex-style group homes (a Resident level + an RS — Residential
Supervisor — live-in unit) on a rotation, run a room-by-room checklist, flag
problems, record alarm counts, take photos, and file an end-of-visit survey.

The existing app (`route-checklist/`) is a clean, single-file, no-dependency
HTML checklist that saves to the browser only. It works well but has hit a wall
its own handoff notes name: **state is per-browser** — no sharing across
devices, no photos, no email. We are moving it onto a real backend to unlock
those things **without losing** what makes it good (fast, offline-capable,
accessible, secret-safe).

## Decisions locked in (from the owner)

| Question | Decision |
|---|---|
| Backend | **Supabase** (Postgres database + file storage + auth + edge functions) |
| Accounts | **Techs + Supervisors**, separate roles |
| Field devices | **A mix** — so: online-first now, real offline sync as a later phase |
| Photos | **Both** — attached to flagged items *and* free-standing per-visit |
| Visit schedule | **~3-month rotation**, order **roughly fixed with per-visit flexibility** |
| Reminder trigger | On **completing** a visit, offer to notify the house **two ahead** in the rotation (with send-now / delay / customize options) |
| Reminder recipient | The **upcoming house's RS / on-site contact** (each house stores a contact email) |

## Compliance & the data boundary (important)

This app handles data about **vulnerable adults**, so compliance requires the
real data to **eventually live only in the company's Microsoft 365 / SharePoint
tenant** — no outside vendor as the system of record. That's a "someday," not now.

What this means for how we build **today**:
- **Supabase is a working demo / proof of the app, not the system of record.**
- **Only fake/sample data goes into Supabase or this public repo** — no real
  house names, real photos, med-lock/door codes, or resident-adjacent details.
  (The current Dogwood/Roselawn seed houses and their codes are already **fake
  samples**, confirmed by the owner — safe to keep in the public demo.)
- Keep a **hard line between app logic and the data layer** (the app talks to a
  small data module — `cloud.js` — and never assumes Supabase directly), so a
  later swap to **M365 (likely SPFx + document libraries + Microsoft Graph**; the
  tenant disabled SharePoint Lists) stays contained work, not a rewrite.

## Supabase project

- **Project URL:** `https://eccukivhjgiqwfnosevt.supabase.co`
- **Publishable (public) key:** `sb_publishable_YsnL38EMpfeb0qdVGPmdjA__RA-T1HB` —
  safe to commit and ship in the client; RLS is what protects the data.
- **`service_role` / secret key:** NOT stored here and must never be committed
  or put in the browser. It lives only in the Supabase dashboard.
- **Schema:** version-controlled SQL in `supabase/migrations/`, applied with the
  **Supabase CLI** (`supabase db push`; installed, logged in, and linked as of
  2026-07-12 — see HANDOFF.md). Migrations 0001–0007 predate the CLI and were
  marked applied via `supabase migration repair`. No more hand-pasting SQL into
  the dashboard.
- **Data API:** enabled; "auto-expose new tables" is OFF and "auto-RLS" is ON,
  so every new table starts locked down and we grant access explicitly.

## Tech stack (and why)

- **Front end: vanilla HTML/CSS/JS, kept** for now. The current app proves this
  team can ship clean vanilla code. We add a small build step (Vite) only when
  logins, multiple screens, and env vars justify it — *not preemptively*. We
  will adopt a framework only when complexity actually demands it, and we'll say
  so out loud when it does.
- **Backend: Supabase.** One product gives us a real SQL database (Postgres),
  file storage for photos, authentication, and serverless functions for sending
  email. Generous free tier. Everything you learn here (SQL, row-level security,
  auth) is transferable, real engineering — not a toy.
- **Auth: Supabase email + password login** (primary), with a **magic-link
  email** kept only as a first-time / password-reset fallback. Email
  confirmation is OFF and public sign-ups should be OFF, so accounts are
  **provisioned deliberately** — for now the supervisor creates them in the
  Supabase dashboard ("Add user → Create new user", Auto Confirm on); an in-app
  "Add user" screen for supervisors is a later phase (needs a service_role-backed
  Edge Function — the secret key must never reach the browser). Users can change
  their own password in-app (☰ Houses → Set / change password). Sessions persist
  in the browser, so people sign in once per device, not every visit. Each person
  is a row in `profiles` with a `role`.
- **Email: an Edge Function** calls an email provider when a tech chooses to
  send an advance notice. Provider TBD (Resend is simplest; Microsoft 365 /
  Graph if the org wants mail to come from a company address — decide in Phase 3).
- **Hosting: the static app is served over HTTPS** (GitHub Pages or Cloudflare
  Pages/Netlify). Supabase auth needs a real web origin — the app can no longer
  be opened as a bare `file://` once login exists.

## Security posture (part of "enterprise quality")

- **Row-Level Security (RLS) is the backbone.** The *database itself* enforces
  who can read/write what — techs edit their own in-progress visits, supervisors
  read everything. We never rely on the UI to hide data.
- **This git repo is PUBLIC.** Never commit secrets. Supabase's *anon* key is
  designed to be public and is safe in the client; the *service_role* key must
  **never** touch the client or the repo.
- **Sensitive data.** This is group-home data; **photos can accidentally capture
  residents.** Storage buckets are private with signed URLs. Advise the owner on
  what should and shouldn't be photographed.
- **Door/entry codes stay in the gitignored `house-codes.local.js` — permanently,
  by owner decision (2026-07-14).** Moving them into a protected DB table was
  considered and explicitly rejected: codes never touch Supabase or this repo,
  full stop. Copy the file by hand to devices that should show codes.

## Conventions

- **Single source of truth for checklist content:** the `GROUPS` / `COUNTS` /
  `SURVEY` data structures. Rendering stays separate from data.
- **Stable item keys.** The current item IDs are *positional*
  (`g0s1i2`), so inserting a checklist item silently shifts saved answers — the
  handoff notes flag this. Before wiring the database, give every item a
  **stable string key** so saved answers, photos, and history survive edits.
- **Accessibility is required, not optional** — keep the existing `aria-*`,
  `:focus-visible`, and `prefers-reduced-motion` support and extend it.
- **Never lose a tech's in-progress work.** Even online-first, keep a local
  buffer so a dropped connection or closed tab doesn't wipe a half-filled visit.

## Roadmap (each phase is shippable)

- **Phase 0 — Foundations.** ✅ Done: this file; Supabase project created;
  stable-item-keys refactor (verified: 114 unique keys, app renders correctly).
- **Phase 1 — Accounts + one visit in the cloud.** ✅ Done. Email+password auth,
  `profiles`/`houses`/`visits`/`visit_items` with RLS, houses load from the DB,
  visits (in-progress + completed) save to and resume from the DB. Since then
  the thin slice has widened well past "one visit": house-note suggestions
  (tech propose / supervisor review), tech routes, My Profile, My Visit
  History, Daily Logs (with a supervisor read-only view of any tech's log —
  see HANDOFF.md), an in-checklist House Info panel, and a private My Notes
  scratchpad are all live. See `route-checklist/HANDOFF.md` for the current,
  detailed state — it's updated far more often than this roadmap.
- **Phase 2 — Photos (current, not started).** Private storage bucket; upload
  on flagged items and as general visit photos; thumbnails; signed URLs.
- **Phase 3 — Rotation + advance-notice email (not started).** Store rotation
  order + RS contact per house; on completion, compute the house two ahead and
  offer send / delay / customize; Edge Function sends the email; log every
  notice sent.
- **Phase 4 — Supervisor dashboard (partially underway).** The Daily Logs
  supervisor view (any tech's calendar, read-only) and the house-note
  suggestion review queue are live pieces of this. Still missing: a unified
  view across completed visits, flagged issues, and photos.
- **Phase 5 — Real offline-first sync (not started).** The hardest piece, done
  deliberately last: service worker + a sync queue that merges when back online.
- **Slice 4 — Shared on-call rotation calendar (deferred, not started).** A
  fifth owner-requested slice alongside My Profile/Visit History/Daily Logs;
  not yet brainstormed. See HANDOFF.md's top section.

## Repo layout

- `route-checklist/` — the real app (the one we're growing).
  - `index.html` — app (HTML+CSS+JS, no deps today).
  - `house-data.js` — per-house roster; migrates into the DB in Phase 1.
  - `house-codes.local.js` — door codes, **gitignored, on-device only**.
  - `HANDOFF.md` — detailed current-state notes; keep it updated.
- `home-upkeep/index.html` — an earlier practice app (generic homeowner
  tracker). Not the work app; leave it unless asked.
- `README.md` — sandbox notes.

## Verifying changes

There are no automated tests yet. Verify by actually running the app in a
browser and exercising the changed flow end-to-end (fill a visit, flag an item,
reload to confirm it persisted). "Verify" also means checking the row actually
appears in Supabase (`supabase db query --linked ...`). Don't claim something
works without having driven it.
