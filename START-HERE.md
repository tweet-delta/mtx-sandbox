# START HERE — MTX Route Checklist

**This is the one file to open.** New Claude Code session? Just say:
**"Read START-HERE.md and let's continue."**
(Claude: read this, then `route-checklist/HANDOFF.md` for deep detail. Update
this file before every session ends.)

---

## ⏭️ FIRST THING NEXT TIME (as of 2026-07-18)

0a. **NEW — 🏷️ Managed job titles are LIVE (sw.js v31).** Hard-refresh first
   (Ctrl+Shift+R). As a **supervisor**:
   - Home has a new **🏷️ Job titles** button → create titles, each marked
     **Field** or **Office / Projects**, rename or retire them.
   - **👥 Team** → ✎ Edit someone → pick their title from the **dropdown**
     (no more free typing).
   - **The payoff:** give a **test account** an *Office* title, then **sign in
     as that account for real** (not preview) — its home screen should HIDE
     house visits / daily logs and show only House notes, My notes, My profile,
     maintenance requests, plus a "your tailored tools are coming" note. This is
     the live check Claude can't do headless — **please try it and report back.**
   - This is Slice 1. Your "pick-and-choose admin permissions" and the *actual*
     custom screens for the Interior Designer / Project Director / Carpenter are
     the next two slices (not built yet — by design).

0b. **Try the 🎫 Tickets feature — it's LIVE.**
   Hard-refresh first (Ctrl+Shift+R), then:
   - Home now has **📌 My tickets**, **🎫 Tickets**, and **🔔 Notifications**
     buttons (with count badges).
   - Open **🎫 Tickets** → filter chips (New / Unassigned / Urgent / Time
     sensitive / Wish list / Stale 30d+ / Completed) + a house picker. As
     supervisor each ticket card opens to Assign + Priority controls.
   - **＋ New ticket** → file one (house, category, priority, requested-by).
   - Start a **house visit** at one of the first ~6 demo houses → the
     checklist now shows a **"🎫 Open tickets at this house"** panel up top
     (House Visit List items pinned first) with In progress / Completed
     buttons.
   - **22 fake demo tickets are seeded** (2 urgent, 3 stale). Tell Claude how
     it looks — anything to tweak?
1. **Two decisions that unlock the next ticket work:**
   - **Real SharePoint sync** (submit-from-app → SharePoint, and pull the real
     list in). This needs **company IT / Microsoft Graph API access** we don't
     have. If you can find out whether IT would grant it, that's the gate.
   - **Photos on tickets** — arrives with **Phase 2 (photos)**, the natural
     next slice.
2. **Still pending from before:** the 👥 Team **+ Add new team member**
   milestone test (sign out, sign in as the new person). Do it when convenient.

**Note on SharePoint sync:** the app does NOT talk to the real SharePoint list
yet. Tickets are fake demo data with the **same field shape** (fields,
statuses, priorities, ~28 categories copied from the real
`acrhomes123.sharepoint.com` list), so a real hookup later is a data copy, not
a rewrite.

## ✅ What's live right now

- **Live app:** https://tweet-delta.github.io/mtx-sandbox/route-checklist/index.html#home
- **NEW 2026-07-18 — 🏷️ Managed job titles (Slice 1):** supervisors create an
  official list of job titles (each **Field** or **Office/Projects**), assign
  them to people via a dropdown on 👥 Team, and each title's kind decides the
  home screen — **Office** people don't see house-visit/daily-log tooling.
  Titles are supervisor-assigned (read-only on My Profile). Migration 0027;
  Edge Function updated; sw.js **v31**. Permissions and the tailored
  Designer/Director/Carpenter screens are deliberately **later slices**.
- **NEW 2026-07-18 — ⇅ Arrange (personal home-menu order):** everyone can
  reorder their own home buttons (⇅ Arrange next to the title → ↑/↓ → ✓ Done).
  Order saves to your account (`profiles.home_order`, migration 0028) so it
  follows you across devices. Field tools + Sign out stay pinned at the bottom;
  new buttons we add later appear at the bottom of your custom order.
  **Owner: after hard-refresh, try it signed in** — move 📋 My notes up, ✓ Done,
  reload, confirm it stuck (this is the live-auth check Claude can't do headless).
- Supervisor **👥 Team** screen: edit anyone's name / phone / job title /
  role (with confirm + can't-demote-yourself/last-supervisor guards), real
  emails, **Add new team member** (temp-password flow).
- **NEW 2026-07-18 — 🎫 Maintenance tickets** (live, verified): file requests
  in-app, filter the queue
  (new/unassigned/urgent/time-sensitive/wish-list/stale/completed), assign +
  re-prioritize (supervisor), work tickets during a house visit, history trail
  per ticket, and 🔔 notifications for assignments/comments. Fake demo data
  (22 seeded), shaped like the real SharePoint list. Not synced to SharePoint
  (needs IT approval). Spec/plan/mockup in `docs/superpowers/`; migrations
  0025–0026; test `tests/tickets.test.py`.
- Everything earlier: visits, reviews queue, house notes + suggestions,
  routes, daily logs, my notes, profile.
- **2026-07-18 fix:** Daily Logs now records answered questions / N-A marks /
  notes / readings, not just checked boxes — partial visits show their work.
  First automated test lives at `tests/daily-log-partial-visit.test.py`.
- **Data is FAKE / demo** (owner-confirmed) — safe to experiment freely.

## 🔗 The links

| What | Where |
|---|---|
| Live app | https://tweet-delta.github.io/mtx-sandbox/route-checklist/index.html#home |
| GitHub repo | https://github.com/tweet-delta/mtx-sandbox |
| GitHub Pages setting | https://github.com/tweet-delta/mtx-sandbox/settings/pages ← **must say branch `main`** |
| Supabase dashboard | https://supabase.com/dashboard/project/eccukivhjgiqwfnosevt |
| Edge Functions | https://supabase.com/dashboard/project/eccukivhjgiqwfnosevt/functions |
| API keys page | https://supabase.com/dashboard/project/eccukivhjgiqwfnosevt/settings/api-keys |

**Test accounts:** `tech1@example.com`, `tech2@example.com` (techs).
Your own login is the supervisor.

## 🚀 How shipping works (fixed 2026-07-17!)

- Merging to **`main`** + pushing = the live site updates (~1–2 min).
- **It broke silently for 2 days** because GitHub Pages was watching an old
  branch. You flipped it to `main` on 2026-07-17. If deploys ever seem dead
  again, check that Pages setting first.
- **Claude's rule:** never say "it's live" without proving it:
  `curl -s https://tweet-delta.github.io/mtx-sandbox/route-checklist/sw.js`
  must show the new version number.

## 😤 "I don't see my change!" checklist (in order)

1. **Hard-refresh:** Ctrl+Shift+R (sometimes twice).
2. **Phone PWA:** fully swipe the app closed, reopen (refresh isn't enough).
3. **Incognito test:** Ctrl+Shift+N, open the live URL. If the change shows
   there, it's your cache → DevTools (F12) → Application → Service Workers →
   Unregister → Storage → Clear site data → reload.
4. **If it's missing even in Incognito** → it never deployed. Tell Claude —
   check the Pages setting + whether `main` really has the change.

## 🔐 Secrets — the rules that never change

- **Never** put the `sb_secret_…` / service_role key in chat, a file, or the
  repo. It lives ONLY in Supabase (Edge Function secrets, set once — done).
- The `sb_publishable_…` key in the code is **safe by design** — RLS protects
  the data.
- Real door codes: ONLY in `route-checklist/house-codes.local.js`
  (gitignored, copied by hand between devices). Never in Supabase or GitHub.
- Terminal tip learned the hard way: wrap pasted values in **single quotes**
  — `command 'PASTED-VALUE'` — and never type the `<` `>` brackets from
  examples.

## 🗺️ Roadmap

Done: 🎫 tickets (2026-07-18). Next: Photos (Phase 2, also adds photos to
tickets) · **real SharePoint ticket sync** (blocked on IT/Graph access) ·
rotation + advance-notice email (Phase 3) · checklist task editing in-app ·
offline sync (Phase 5) · on-call calendar (Slice 4) · Team 2c/2d (reset
password, deactivate). Someday: move data into company M365/SharePoint
(compliance home).

---
*Claude: keep this file current — update "FIRST THING NEXT TIME" and
"What's live" at the end of every session. This file outranks HANDOFF.md as
the session entry point; HANDOFF.md stays the deep technical log.*
