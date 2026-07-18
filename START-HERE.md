# START HERE — MTX Route Checklist

**This is the one file to open.** New Claude Code session? Just say:
**"Read START-HERE.md and let's continue."**
(Claude: read this, then `route-checklist/HANDOFF.md` for deep detail. Update
this file before every session ends.)

---

## ⏭️ FIRST THING NEXT TIME (as of 2026-07-18)

0. **Try the new 🎫 Tickets feature** (hard-refresh first, Ctrl+Shift+R):
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
   - Tell Claude how it looks — anything to tweak before Phase 2 (photos).
1. **Still pending from before:** the 👥 Team **+ Add new team member**
   milestone test (sign out, sign in as the new person). Do it when convenient.

**Note on SharePoint sync:** the app does NOT talk to the real SharePoint list
yet — that needs company IT/Graph approval. Tickets are fake demo data with the
**same field shape**, so a real hookup later is a data copy, not a rewrite.

## ✅ What's live right now

- **Live app:** https://tweet-delta.github.io/mtx-sandbox/route-checklist/index.html#home
- Supervisor **👥 Team** screen: edit anyone's name / phone / job title /
  role (with confirm + can't-demote-yourself/last-supervisor guards), real
  emails, **Add new team member** (temp-password flow).
- **NEW 2026-07-18 — 🎫 Maintenance tickets:** file requests in-app, filter
  the queue (new/unassigned/urgent/time-sensitive/wish-list/stale/completed),
  assign + re-prioritize (supervisor), work tickets during a house visit,
  history trail per ticket, and 🔔 notifications for assignments/comments.
  Fake demo data, shaped like the real SharePoint list. Not synced to
  SharePoint (needs IT approval).
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

## 🗺️ Roadmap after 2c + 2d

Photos (Phase 2) · rotation + advance-notice email (Phase 3) · checklist
task editing in-app · offline sync (Phase 5) · on-call calendar (Slice 4).
Someday: move data into company M365/SharePoint (compliance home).

---
*Claude: keep this file current — update "FIRST THING NEXT TIME" and
"What's live" at the end of every session. This file outranks HANDOFF.md as
the session entry point; HANDOFF.md stays the deep technical log.*
