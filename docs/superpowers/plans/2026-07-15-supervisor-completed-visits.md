# Supervisor Completed-Visits Review + Home Cleanup — Implementation Plan

> **For agentic workers:** REQUIRED SUB-SKILL: Use superpowers:subagent-driven-development (recommended) or superpowers:executing-plans to implement this plan task-by-task. Steps use checkbox (`- [ ]`) syntax for tracking.

**Goal:** Give supervisors a badged "✅ Completed visits" review screen (survey + flagged items, explicit ✓ Mark reviewed with a server-side audit stamp) and tuck the three field buttons into a collapsed "🧰 Field tools" drawer on the supervisor home screen.

**Architecture:** One migration (two audit columns on `visits` + a security-definer `mark_visit_reviewed` RPC), four new `cloud.js` functions following the existing `{ error }` conventions, one new `#reviews` hash-router screen in `index.html`, and a role-driven DOM shuffle for the home screen. RLS from migration 0001 already covers all reads; the only new write path is the RPC.

**Tech Stack:** Vanilla HTML/CSS/JS (no deps, no build step), Supabase (Postgres + RLS + RPC) via the existing `cloud.js` module, Supabase CLI for migrations.

**Spec:** `docs/superpowers/specs/2026-07-15-supervisor-completed-visits-design.md`

## Global Constraints

- Repo is PUBLIC — no secrets, no real codes, nothing resident-adjacent in any file.
- The app talks to Supabase ONLY through `cloud.js` (`window.cloud.*`); `index.html` never imports supabase directly. Checklist polarity (`ITEM_BY_KEY`, `bad`) stays in `index.html` — `cloud.js` returns raw items.
- UI hides, database enforces: every supervisor gate must also hold server-side (RLS or role check inside the RPC).
- Techs' home screen and every tech-facing flow must be byte-for-byte behaviorally unchanged.
- Migrations: new numbered file in `supabase/migrations/`, applied with `supabase db push --workdir "c:\Big Dogs Apps\MTX Checklist V1"`. Never edit an applied migration.
- Service worker cache: bump `route-checklist-v23` → `route-checklist-v24` exactly once, in the final task.
- No automated test harness exists. Per-task verification = headless-Chrome parse check (zero `SyntaxError` in console) + code review; the full two-role live-site drive is the owner's final step (listed in the last task) — do not claim live verification you didn't do.
- Every commit message ends with: `Co-Authored-By: Claude Fable 5 <noreply@anthropic.com>`
- Known deliberate deviation from the spec's button-order sentence: supervisors see admin buttons in DOM order **✅ Completed visits · ⏳ Pending changes · 📝 House notes · 👤 My profile · 🗓️ Daily logs · 📋 My notes · 🗺️ Routes · 🧰 Field tools**. The spec's hard requirements (Reviews first with badge, field buttons collapsed last, tech order untouched) all hold; matching the spec's exact middle ordering would need extra JS reordering for zero user value. Flag this to the owner at review.

---

### Task 1: Migration `0020_visit_reviews.sql`

**Files:**
- Create: `supabase/migrations/0020_visit_reviews.sql`

**Interfaces:**
- Produces: `visits.reviewed_at timestamptz null`, `visits.reviewed_by uuid null references profiles(id)` (FK constraint auto-named `visits_reviewed_by_fkey` — Task 2's PostgREST embeds depend on that exact name, and on the existing `visits_tech_id_fkey`), and RPC `public.mark_visit_reviewed(p_visit_id uuid) returns void`, execute granted to `authenticated`.

- [ ] **Step 1: Write the migration file**

```sql
-- 0020_visit_reviews.sql — supervisor review stamp on completed visits.
--
-- Two nullable audit columns (every existing completed visit starts
-- unreviewed) + a security-definer RPC so the stamp is trustworthy:
-- reviewed_by is ALWAYS auth.uid(), never client-supplied, and an existing
-- stamp is never overwritten (first review wins). Same precedent as
-- approve_note_suggestion (0008). Reads need no new policy — visits_select
-- (0001) already lets supervisors read every visit.

alter table public.visits
  add column if not exists reviewed_at timestamptz,
  add column if not exists reviewed_by uuid references public.profiles (id);

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
     and reviewed_at is null;
  if not found then
    raise exception 'Visit not found, not completed, or already reviewed';
  end if;
end;
$$;

grant execute on function public.mark_visit_reviewed(uuid) to authenticated;
```

- [ ] **Step 2: Push it**

Run: `supabase db push --workdir "c:\Big Dogs Apps\MTX Checklist V1"`
Expected: lists exactly `0020_visit_reviews.sql`, applies cleanly, exit 0. If it wants to apply anything else, STOP and investigate — do not confirm.

- [ ] **Step 3: Verify columns + RPC exist and the FK name matches**

Run:
```
supabase db query --linked "select column_name from information_schema.columns where table_schema='public' and table_name='visits' and column_name in ('reviewed_at','reviewed_by')"
supabase db query --linked "select constraint_name from information_schema.table_constraints where table_name='visits' and constraint_type='FOREIGN KEY'"
supabase db query --linked "select proname from pg_proc where proname='mark_visit_reviewed'"
```
Expected: both columns; constraints include `visits_tech_id_fkey` AND `visits_reviewed_by_fkey`; one `mark_visit_reviewed` row. If the reviewed_by FK has a different name, note the real name — Task 2 must use it verbatim.

- [ ] **Step 4: Commit**

```bash
git add supabase/migrations/0020_visit_reviews.sql
git commit -m "feat(db): visit review stamp (reviewed_at/by) + mark_visit_reviewed RPC

Co-Authored-By: Claude Fable 5 <noreply@anthropic.com>"
```

---

### Task 2: `cloud.js` — review data layer + badge push

**Files:**
- Modify: `route-checklist/cloud.js` (new section after `getVisitDetail`, ~line 341; `loadRole` at lines 64–78; `window.cloud` export block at lines 738–749)

**Interfaces:**
- Consumes: Task 1's columns/RPC; existing `isMissingColumn(error)`, `supabase` client.
- Produces (all on `window.cloud`):
  - `listCompletedVisits()` → `{ visits: [{ id, visitDate, reviewedAt, houseName, techName, items: [{item_key, answer, note}] }] } | { error, notReady }`
  - `getAnyVisitDetail(visitId)` → `{ houseName, techName, visitDate, survey: {}, reviewedAt, reviewerName, items: [...] } | { error }`
  - `markVisitReviewed(visitId)` → `{ ok: true } | { error }` (also refreshes the badge)
  - `unreviewedVisitCount()` → `{ count } | { error }`
- Calls `window.applyReviewCount(n)` (defined in Task 3) when the supervisor's unreviewed count is known.

- [ ] **Step 1: Add the review section to cloud.js** (insert after `getVisitDetail`, before the `listLogsInRange` comment block)

```js
// ---- Supervisor: completed-visit review queue ----

// Every completed visit for the review screen: ALL unreviewed (any age —
// unreviewed work must never silently disappear) plus reviewed ones from the
// last ~3 months (one rotation). Includes raw visit_items so the UI can
// compute the "2 flagged · 1 note" hint with its GROUPS polarity logic —
// cloud.js deliberately knows nothing about checklist polarity.
// NOTE: after 0020, visits has TWO foreign keys to profiles (tech_id,
// reviewed_by), so every profiles embed must name its FK or PostgREST
// rejects the query as ambiguous.
async function listCompletedVisits() {
  const d = new Date(); d.setMonth(d.getMonth() - 3);
  const cutoff = `${d.getFullYear()}-${String(d.getMonth() + 1).padStart(2, "0")}-${String(d.getDate()).padStart(2, "0")}`;
  const { data, error } = await supabase
    .from("visits")
    .select("id, visit_date, reviewed_at, houses(name), tech:profiles!visits_tech_id_fkey(full_name), visit_items(item_key, answer, note)")
    .eq("status", "completed")
    .or(`reviewed_at.is.null,visit_date.gte.${cutoff}`)
    .order("visit_date", { ascending: false })
    .order("completed_at", { ascending: false });
  if (error) return { error: error.message, notReady: isMissingColumn(error) };
  return {
    visits: data.map(v => ({
      id: v.id,
      visitDate: v.visit_date,
      reviewedAt: v.reviewed_at || null,
      houseName: v.houses?.name || "",
      techName: v.tech?.full_name || "",
      items: v.visit_items || [],
    })),
  };
}

// Any staff member's completed visit + items, for the supervisor detail
// page. Deliberately NO tech_id self-scope (that's the point of the screen);
// RLS is the gate — a tech calling this for someone else's visit gets
// "Visit not found." back, not data.
async function getAnyVisitDetail(visitId) {
  const { data, error } = await supabase
    .from("visits")
    .select("visit_date, survey, reviewed_at, houses(name), tech:profiles!visits_tech_id_fkey(full_name), reviewer:profiles!visits_reviewed_by_fkey(full_name), visit_items(item_key, answer, note)")
    .eq("id", visitId).eq("status", "completed")
    .maybeSingle();
  if (error) return { error: error.message };
  if (!data) return { error: "Visit not found." };
  return {
    houseName: data.houses?.name || "",
    techName: data.tech?.full_name || "",
    visitDate: data.visit_date,
    survey: data.survey || {},
    reviewedAt: data.reviewed_at || null,
    reviewerName: data.reviewer?.full_name || "",
    items: data.visit_items || [],
  };
}

// Stamp a completed visit as reviewed. The RPC (0020) runs server-side and
// always records auth.uid() as the reviewer — the client can't forge it —
// and refuses to overwrite an existing stamp (first review wins; a second
// supervisor gets the "already reviewed" error back).
async function markVisitReviewed(visitId) {
  const { error } = await supabase.rpc("mark_visit_reviewed", { p_visit_id: visitId });
  if (error) return { error: error.message };
  refreshReviewBadge();
  return { ok: true };
}

async function unreviewedVisitCount() {
  const { count, error } = await supabase
    .from("visits")
    .select("id", { count: "exact", head: true })
    .eq("status", "completed")
    .is("reviewed_at", null);
  return error ? { error: error.message } : { count: count || 0 };
}

// Push the current unreviewed count to the home-screen badge. Best-effort:
// on any error the badge just doesn't update (pre-0020 DB included).
function refreshReviewBadge() {
  unreviewedVisitCount().then(r => {
    if (!r.error && window.applyReviewCount) window.applyReviewCount(r.count);
  });
}
```

- [ ] **Step 2: Wire the badge + role hook into `loadRole`**

The supervisor branch of `loadRole` currently reads:

```js
  document.body.classList.toggle("is-admin", window.cloud.role === "supervisor");
  if (window.cloud.role === "supervisor") {
    pendingCount().then(r => {
      if (!r.error && window.applyPendingCount) window.applyPendingCount(r.count);
    });
  }
```

Change to:

```js
  document.body.classList.toggle("is-admin", window.cloud.role === "supervisor");
  if (window.applyRole) window.applyRole(window.cloud.role);
  if (window.cloud.role === "supervisor") {
    pendingCount().then(r => {
      if (!r.error && window.applyPendingCount) window.applyPendingCount(r.count);
    });
    refreshReviewBadge();
  }
```

(`window.applyRole` is defined in Task 4; the `if` guard makes this a no-op until then — and a safe no-op forever if the page hasn't defined it.)

- [ ] **Step 3: Call the role hook on sign-out too**

In the `onAuthStateChange` signed-out branch, directly after `document.body.classList.remove("is-admin");`, add:

```js
    if (window.applyRole) window.applyRole(null);
```

- [ ] **Step 4: Export the new functions**

In the `window.cloud = { ... }` block, after the line `listMyVisits, getVisitDetail,`, add:

```js
                 listCompletedVisits, getAnyVisitDetail, markVisitReviewed, unreviewedVisitCount,
```

- [ ] **Step 5: Parse check**

No Node on this machine; check the file loads as a module without syntax errors via headless Chrome. Write a throwaway harness in the scratchpad directory (NOT the repo), e.g. `parse-cloud.html`:

```html
<script>window.SUPABASE_URL="https://example.invalid";window.SUPABASE_PUBLISHABLE_KEY="x";</script>
<div id="authGate"></div><form id="loginForm"></form><input id="loginEmail"><input id="loginPassword">
<button id="magicLinkBtn"></button><div id="authMsg"></div><div id="whoami"></div>
<input id="newPassword"><button id="setPasswordBtn"></button><div id="pwMsg"></div>
<script type="module" src="http://localhost:8931/cloud.js"></script>
```

Serve the app dir and load it (module scripts don't run from `file://`):

Run (Bash tool, from the repo root):
```bash
(cd route-checklist && python -m http.server 8931 &) ; sleep 1
"/c/Program Files/Google/Chrome/Application/chrome.exe" --headless --disable-gpu --enable-logging=stderr --virtual-time-budget=5000 --dump-dom "http://localhost:8931/../SCRATCHPAD_PATH/parse-cloud.html" 2>&1 | grep -i "syntaxerror" ; kill %1
```
(Adjust to serve a directory that can reach both the harness and `cloud.js` — simplest is to copy `parse-cloud.html` into `route-checklist/` temporarily and delete it before committing; it must never be committed.)
Expected: no `SyntaxError` lines. Network/CDN errors are fine (fake URL); only syntax matters here. If Python isn't available either, fall back to a careful manual re-read of the diff — and say so in the commit-time notes rather than claiming a parse check ran.

- [ ] **Step 6: Commit**

```bash
git add route-checklist/cloud.js
git commit -m "feat(cloud): completed-visit review API + unreviewed badge push

Co-Authored-By: Claude Fable 5 <noreply@anthropic.com>"
```

---

### Task 3: `index.html` — the `#reviews` screen

**Files:**
- Modify: `route-checklist/index.html` —
  CSS screen-hiding rule (~line 507–515), history CSS block (~line 580), home-screen markup (~line 785), new screen `<div>` after `#pendingScreen` (~line 868), router (`currentScreenFromHash` ~2610, `showScreen` ~2623), home-button handlers (~2645), history detail refactor (~2954–2986), new render functions + click handler (add after the history block, ~line 2994), `applyPendingCount` area (~3275).

**Interfaces:**
- Consumes: `window.cloud.listCompletedVisits/getAnyVisitDetail/markVisitReviewed` (Task 2 shapes), existing `ITEM_BY_KEY`, `SURVEY`, `escHtml`, `escAttr`, `fmtDate`, `currentScreenFromHash`.
- Produces: `window.applyReviewCount(n)` (Task 2 calls it); shared helpers `problemItems(items)` and `problemRowsHTML(items)` (used by both history and reviews details).

- [ ] **Step 1: CSS — hide the screen unless active + tech-group heading**

In the screen-hiding rule block, add one line so it ends:

```css
  body:not([data-screen="mynotes"])  #mynotesScreen,
  body:not([data-screen="reviews"])  #reviewsScreen,
  body:not([data-screen="notes"])    #notesScreen { display: none; }
```

Next to the `.hist-item` rules (~line 580), add:

```css
  .review-tech { font-size: 0.85rem; margin: 12px 0 4px; color: var(--ink); }
```

- [ ] **Step 2: Home button — first in the stack**

Immediately after `<div class="screen-head"><h1>Maintenance House Visit</h1></div>` and BEFORE `#homeNewVisit`, add:

```html
  <button type="button" class="home-btn admin-only" id="homeReviews">✅ Completed visits<span class="pending-count" id="reviewCountBadge"></span>
    <small>Review techs' visits &amp; surveys</small></button>
```

(Techs never see it — `admin-only`. Tech button order is untouched.)

- [ ] **Step 3: Screen markup** — after the closing `</div>` of `#pendingScreen`:

```html
<div id="reviewsScreen" class="screen" aria-label="Completed visits">
  <div class="screen-head">
    <button type="button" class="menu-btn" data-nav-home>← Home</button>
    <h1>Completed visits</h1>
  </div>
  <div id="reviewsBody"></div>
</div>
```

- [ ] **Step 4: Router entries**

In `currentScreenFromHash()` add (before the `return "home";`):

```js
    if (h.startsWith("#reviews")) return "reviews";
```

In `showScreen()` add:

```js
    if (scr === "reviews") renderReviewsScreen();
```

In the home-button handlers add:

```js
  document.getElementById("homeReviews").addEventListener("click", () => {
    location.hash = "#reviews";
  });
```

- [ ] **Step 5: Extract the shared problems filter from `renderVisitDetail`**

Add just above `renderHistoryScreen` (~line 2937):

```js
  // Shared by My Visit History and the supervisor review detail so the two
  // can never drift: only the items worth revisiting — flagged (answer ===
  // item.bad, polarity from GROUPS) OR carrying a note. An item_key no
  // longer in the checklist still shows, labelled by its raw key.
  function problemItems(items) {
    return (items || []).filter(it => {
      const def = ITEM_BY_KEY[it.item_key];
      const flagged = def && it.answer && it.answer === def.bad;
      return flagged || (it.note && it.note.trim());
    });
  }
  function problemRowsHTML(items) {
    return items.map(it => {
      const def = ITEM_BY_KEY[it.item_key];
      const label = def ? escHtml(def.q || def.text) : escHtml(it.item_key);
      const ans = it.answer ? `<span class="hist-answer">${escHtml(it.answer)}</span>` : "";
      const note = it.note && it.note.trim() ? `<p class="hist-note">${escHtml(it.note)}</p>` : "";
      return `<div class="hist-item"><b>${label}</b> ${ans}${note}</div>`;
    }).join("");
  }
```

Then in `renderVisitDetail`, replace the `const shown = res.items.filter(...)` block (the whole filter through `});`) with:

```js
    const shown = problemItems(res.items);
```

and replace the `const rows = shown.map(it => { ... }).join("");` block with:

```js
    const rows = problemRowsHTML(shown);
```

The surrounding comment above `renderVisitDetail` ("Detail = only the items worth revisiting…") now duplicates the helper's comment — trim it to `// Detail for one of MY OWN visits (tech screen).`

- [ ] **Step 6: The reviews screen renderers + handler** — add after the `historyBody` click handler (~line 2994):

```js
  // ---- Completed-visits review screen (supervisor) ----
  // The router shows it to anyone, so gate in the renderer; RLS/RPC are the
  // real enforcement — a tech forcing #reviews gets an empty/error screen,
  // never data.

  // "2 flagged · 1 note" row hint; polarity logic stays here, not in cloud.js.
  function reviewHint(items) {
    let flagged = 0, noted = 0;
    (items || []).forEach(it => {
      const def = ITEM_BY_KEY[it.item_key];
      if (def && it.answer && it.answer === def.bad) flagged++;
      if (it.note && it.note.trim()) noted++;
    });
    const parts = [];
    if (flagged) parts.push(`${flagged} flagged`);
    if (noted) parts.push(`${noted} note${noted === 1 ? "" : "s"}`);
    return parts.length ? parts.join(" · ") : "no issues";
  }

  // One section (Awaiting review / Reviewed), grouped by tech name.
  function reviewSectionHTML(title, visits, emptyText) {
    if (!visits.length) {
      return `<div class="notes-sec"><h2>${escHtml(title)}</h2>
        <p class="screen-sub">${escHtml(emptyText)}</p></div>`;
    }
    const byTech = new Map();
    visits.forEach(v => {
      const name = v.techName || "Unnamed tech";
      if (!byTech.has(name)) byTech.set(name, []);
      byTech.get(name).push(v);
    });
    return `<div class="notes-sec"><h2>${escHtml(title)}</h2>` +
      [...byTech.entries()].map(([tech, rows]) =>
        `<h3 class="review-tech">${escHtml(tech)}</h3>` +
        rows.map(v => `
          <button type="button" class="list-btn" data-review-id="${escAttr(v.id)}">
            ${escHtml(v.houseName)} <small>${fmtDate(v.visitDate)} · ${escHtml(reviewHint(v.items))}</small>
          </button>`).join("")
      ).join("") + `</div>`;
  }

  async function renderReviewsScreen() {
    const body = document.getElementById("reviewsBody");
    const m = location.hash.match(/^#reviews\/(.+)$/);
    if (m) { return renderReviewDetail(body, decodeURIComponent(m[1])); }
    if (!window.cloud || window.cloud.role !== "supervisor" || !window.cloud.listCompletedVisits) {
      body.innerHTML = `<p class="screen-sub">Supervisors only.</p>`;
      return;
    }
    body.innerHTML = `<p class="screen-sub">Loading…</p>`;
    const res = await window.cloud.listCompletedVisits();
    if (currentScreenFromHash() !== "reviews") return;   // navigated away meanwhile
    if (res.error) {
      body.innerHTML = `<p class="screen-sub">${res.notReady
        ? "Visit reviews aren't set up in the database yet (migration 0020)."
        : "Couldn't load — " + escHtml(res.error)}</p>`;
      return;
    }
    const unreviewed = res.visits.filter(v => !v.reviewedAt);
    const reviewed = res.visits.filter(v => v.reviewedAt);
    if (window.applyReviewCount) window.applyReviewCount(unreviewed.length);
    body.innerHTML =
      reviewSectionHTML("Awaiting review", unreviewed, "You're all caught up.") +
      reviewSectionHTML("Reviewed — last 3 months", reviewed, "Nothing reviewed in the last 3 months.");
  }

  // Detail: survey answers, then only the flagged/noted items (same shared
  // filter as My Visit History), then Mark reviewed or the review stamp.
  async function renderReviewDetail(body, visitId) {
    body.innerHTML = `<p class="screen-sub">Loading…</p>`;
    const res = await window.cloud.getAnyVisitDetail(visitId);
    if (currentScreenFromHash() !== "reviews") return;
    const backBtn = `<button type="button" class="menu-btn" data-review-back>← All visits</button>`;
    if (res.error) {
      body.innerHTML = backBtn + `<p class="screen-sub">Couldn't load this visit — ${escHtml(res.error)}</p>`;
      return;
    }
    const surveyRows = SURVEY.map(sv => {
      const a = res.survey[sv.id];
      return `<div class="hist-item"><b>${escHtml(sv.q)}</b>${
        a ? `<p class="hist-note">${escHtml(a)}</p>`
          : `<p class="hist-note">(no answer)</p>`}</div>`;
    }).join("");
    const probs = problemItems(res.items);
    const probRows = probs.length ? problemRowsHTML(probs)
      : `<p class="screen-sub">No issues flagged on this visit.</p>`;
    const footer = res.reviewedAt
      ? `<p class="screen-sub">✓ Reviewed by ${escHtml(res.reviewerName || "a supervisor")} on ${escHtml(new Date(res.reviewedAt).toLocaleDateString())}</p>`
      : `<button type="button" class="menu-btn" data-mark-reviewed="${escAttr(visitId)}">✓ Mark reviewed</button>
         <p class="screen-sub" id="reviewMsg" aria-live="polite"></p>`;
    body.innerHTML = backBtn + `
      <h2 style="font-size:1rem">${escHtml(res.techName || "Unnamed tech")} — ${escHtml(res.houseName)} — ${fmtDate(res.visitDate)}</h2>
      <div class="notes-sec"><h2>Survey</h2>${surveyRows}</div>
      <div class="notes-sec"><h2>Problems</h2>${probRows}</div>` + footer;
  }

  document.getElementById("reviewsBody").addEventListener("click", async e => {
    if (e.target.closest("[data-review-back]")) { location.hash = "#reviews"; return; }
    const mark = e.target.closest("[data-mark-reviewed]");
    if (mark) {
      mark.disabled = true;
      const res = await window.cloud.markVisitReviewed(mark.dataset.markReviewed);
      if (res.error) {
        mark.disabled = false;
        const msg = document.getElementById("reviewMsg");
        if (msg) msg.textContent = "Couldn't mark reviewed — " + res.error;
        return;
      }
      location.hash = "#reviews";   // hashchange re-renders the list
      return;
    }
    const row = e.target.closest("[data-review-id]");
    if (row) location.hash = "#reviews/" + row.dataset.reviewId;
  });
```

- [ ] **Step 7: The badge setter** — next to `window.applyPendingCount` (~line 3275), add:

```js
  window.applyReviewCount = function (n) {
    const el = document.getElementById("reviewCountBadge");
    if (el) el.textContent = n > 0 ? ` (${n})` : "";
  };
```

- [ ] **Step 8: Parse check**

Run (Bash tool):
```bash
"/c/Program Files/Google/Chrome/Application/chrome.exe" --headless --disable-gpu --enable-logging=stderr --virtual-time-budget=5000 --dump-dom "file:///c:/Big Dogs Apps/MTX Checklist V1/route-checklist/index.html" 2>&1 >/dev/null | grep -i "syntaxerror"
```
Expected: no output (the `cloud.js` module and CDN fetches may error under `file://` — that's normal and not what this checks). Also confirm the dumped DOM contains `id="reviewsScreen"`.

- [ ] **Step 9: Commit**

```bash
git add route-checklist/index.html
git commit -m "feat: supervisor #reviews screen — badged queue, survey + problems detail, mark reviewed

Co-Authored-By: Claude Fable 5 <noreply@anthropic.com>"
```

---

### Task 4: Home cleanup — the 🧰 Field tools drawer

**Files:**
- Modify: `route-checklist/index.html` — home-screen markup (~line 785–803), CSS near `.home-btn` (~line 521–531), a `window.applyRole` definition next to `applyReviewCount` (~line 3280).

**Interfaces:**
- Consumes: `window.applyRole(role)` is already called by `cloud.js` (Task 2, both on role load and sign-out) — this task defines it.
- Produces: `window.applyRole(role)` — `"supervisor"` moves `#homeNewVisit`, `#homeContinue`, `#homeHistory` into a collapsed `<details id="fieldTools">`; any other value (incl. `null`) restores the original tech layout.

- [ ] **Step 1: Markup — the empty drawer**

After the `#homePending` button and before the sign-out button, add:

```html
  <details id="fieldTools" class="admin-only">
    <summary class="home-btn">🧰 Field tools
      <small>New visit, continue &amp; my own history — rarely needed</small></summary>
  </details>
```

Do NOT move the three field buttons in the markup — the static DOM stays the tech layout (spec: techs byte-for-byte unchanged, including pre-login and while role loads). JS moves them for supervisors only.

- [ ] **Step 2: CSS** — after the `.home-btn:focus-visible` rule, add:

```css
  #fieldTools > summary { list-style: none; cursor: pointer; }
  #fieldTools > summary::-webkit-details-marker { display: none; }
  #fieldTools[open] > summary { border-color: var(--accent); }
  #fieldTools > .home-btn { margin-left: 14px; }
```

(`summary` reuses the `.home-btn` look; the indent visually nests the revealed buttons under the drawer.)

- [ ] **Step 3: The role hook** — next to `window.applyReviewCount`, add:

```js
  // Called by cloud.js whenever the signed-in role resolves (null on
  // sign-out). Supervisors rarely run visits themselves (owner decision
  // 2026-07-15), so their three field buttons tuck into the collapsed
  // Field tools drawer; everyone else keeps today's flat layout. Moving
  // nodes preserves their event listeners; restore order matters: New /
  // Continue sit before House notes, My visit history before Daily logs.
  window.applyRole = function (role) {
    const drawer = document.getElementById("fieldTools");
    const newBtn = document.getElementById("homeNewVisit");
    const contBtn = document.getElementById("homeContinue");
    const histBtn = document.getElementById("homeHistory");
    if (!drawer || !newBtn || !contBtn || !histBtn) return;
    if (role === "supervisor") {
      drawer.append(newBtn, contBtn, histBtn);
      drawer.open = false;
    } else {
      const notesBtn = document.getElementById("homeNotes");
      const logsBtn = document.getElementById("homeLogs");
      notesBtn.parentNode.insertBefore(newBtn, notesBtn);
      notesBtn.parentNode.insertBefore(contBtn, notesBtn);
      logsBtn.parentNode.insertBefore(histBtn, logsBtn);
    }
  };
```

- [ ] **Step 4: Parse check** — same headless-Chrome command as Task 3 Step 8. Expected: no `SyntaxError`; dumped DOM contains `id="fieldTools"` with the three buttons still OUTSIDE it (no role resolved under `file://`).

- [ ] **Step 5: Commit**

```bash
git add route-checklist/index.html
git commit -m "feat: collapsed Field tools drawer on the supervisor home screen

Co-Authored-By: Claude Fable 5 <noreply@anthropic.com>"
```

---

### Task 5: Ship — SW bump, HANDOFF, owner verification list

**Files:**
- Modify: `route-checklist/sw.js` (the `CACHE` constant), `route-checklist/HANDOFF.md` (new state section at top, below the Slice-4 banner).

- [ ] **Step 1: Bump the service-worker cache**

In `route-checklist/sw.js`, change `route-checklist-v23` to `route-checklist-v24`.

- [ ] **Step 2: HANDOFF.md** — add a `## STATE AS OF 2026-07-15 (Supervisor Completed-Visits review + Field tools) — read this first` section above the 2026-07-14 sections, covering: migration 0020 (columns + RPC, pushed & verified), the four cloud.js functions + `applyReviewCount`/`applyRole` hooks, the `#reviews` screen and badge, the Field tools drawer (JS-moved buttons, tech layout untouched), the shared `problemItems`/`problemRowsHTML` refactor of the history detail, SW `v23 → v24`, the spec/plan paths, the supervisor button-order deviation, and the **NOT YET verified end-to-end on the live site** checklist below (copy it verbatim).

- [ ] **Step 3: Owner's live verification checklist** (goes in HANDOFF; the builder does not claim these)

1. Hard-refresh (Ctrl+Shift+R, may take two for the v24 SW) and fully close/reopen the PWA on phones.
2. As the supervisor: home shows "✅ Completed visits (N)" first, N = existing completed visits; 🧰 Field tools collapsed at the bottom; expanding it shows the three field buttons and each still works (New visit picker, Continue list, own history).
3. Open Completed visits → Awaiting review grouped by tech, newest first; hints match a visit known to have flags.
4. Open a visit → survey answers render (blank ones say "(no answer)"); only flagged/noted items under Problems; a clean visit says "No issues flagged on this visit."
5. Mark reviewed → back at the list, the visit sits under "Reviewed — last 3 months", badge decremented; reload → persisted; its detail now reads "✓ Reviewed by ‹you› on ‹today›".
6. `supabase db query --linked "select reviewed_at, reviewed_by from visits where status='completed' order by reviewed_at desc nulls last limit 3"` → the stamped row shows.
7. As tech1: home screen identical to before (three field buttons flat, no drawer summary, no Completed visits button); typing `#reviews` in the URL shows "Supervisors only."
8. As tech1, complete a visit → supervisor's badge increments; the visit tops tech1's Awaiting-review group.

- [ ] **Step 4: Final parse check + commit**

Same headless-Chrome check as Task 3 Step 8, then:

```bash
git add route-checklist/sw.js route-checklist/HANDOFF.md
git commit -m "chore: bump SW cache to v24; HANDOFF for supervisor reviews slice

Co-Authored-By: Claude Fable 5 <noreply@anthropic.com>"
```

---

## Self-review notes (done at plan time)

- **Spec coverage:** badge + explicit review (T1–T3), list sections/grouping/hints (T3), survey+problems detail with shared filter (T3 S5–S6), Field tools with techs untouched (T4), SW/HANDOFF (T5). Spec's "counts" mention in `getAnyVisitDetail` was dropped deliberately — the approved detail design shows survey + problems only; selecting counts would be dead data (YAGNI).
- **Type consistency:** `data-review-id`/`dataset.reviewId`, `data-mark-reviewed`/`dataset.markReviewed`, `applyReviewCount`, `applyRole`, `problemItems`/`problemRowsHTML` used identically across tasks; cloud return shapes in Task 2's Produces block match every Task 3 consumer.
- **Known risk:** if Task 1 Step 3 reveals a different FK constraint name, Task 2's two `profiles!visits_reviewed_by_fkey` embeds must be updated to match before committing.
