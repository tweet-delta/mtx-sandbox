# START HERE — MTX Route Checklist

**This is the one file to open.** New Claude Code session? Just say:
**"Read START-HERE.md and let's continue."**
(Claude: read this, then `route-checklist/HANDOFF.md` for deep detail. Update
this file before every session ends.)

---

## ⏭️ FIRST THING NEXT TIME (as of 2026-07-18)

0. **Re-check yesterday's partial-visit test:** hard-refresh (Ctrl+Shift+R),
   sign in as tech1, open 📆 Daily Logs → July 17 → it should now list the
   two Mechanical Room items you answered at Amble. (Bug fixed 2026-07-18:
   partial visits that only answered yes/no questions stamped an empty diary
   entry — see HANDOFF.md top section.)
1. **Retry the 👥 Team screen** (plain reload is fine). It errored with
   "Failed to send a request to the Edge Function" — that was a CORS bug in
   the function; it's **fixed and verified server-side**. It should now load
   everyone with real emails.
2. **The milestone test:** Team → **+ Add new team member** → name, email,
   Generate password → Create → then sign out and sign in as that new person
   with the temp password. If that works, the whole server foundation works.
3. Tell Claude the result. Then Claude builds:
   - **2c** — Reset password + Change email buttons on each Team card
   - **2d** — Deactivate / Reactivate a tech (kept, never deleted)

## ✅ What's live right now

- **Live app:** https://tweet-delta.github.io/mtx-sandbox/route-checklist/index.html#home
- Supervisor **👥 Team** screen: edit anyone's name / phone / job title /
  role (with confirm + can't-demote-yourself/last-supervisor guards), real
  emails, **Add new team member** (temp-password flow).
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
