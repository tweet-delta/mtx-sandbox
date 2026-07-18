# Personal Home-Menu Ordering Implementation Plan

> **For agentic workers:** REQUIRED SUB-SKILL: Use superpowers:subagent-driven-development (recommended) or superpowers:executing-plans to implement this plan task-by-task. Steps use checkbox (`- [ ]`) syntax for tracking.

**Goal:** Let any signed-in person reorder their home-screen buttons, saved per-user in the cloud, without ever adding or removing a button.

**Architecture:** A person's preference is an ordered array of button `id` strings stored in a new `profiles.home_order` column. On every home render we reconcile that array against the live, visible button set (drop unknown ids, append new ones at the bottom) and apply it by **moving the existing DOM nodes** — never recreating them, so each button's click listener survives. An "Arrange" mode on the home screen exposes ↑/↓ controls; `🧰 Field tools` and `Sign out` are always pinned last.

**Tech Stack:** Vanilla HTML/CSS/JS (no build step, no framework), `cloud.js` data module over Supabase JS client, Postgres + RLS, Supabase CLI migrations.

## Global Constraints

- **No automated test harness in this repo.** "Test" steps mean: (a) parse-check in headless Chrome for zero SyntaxError, and (b) drive the flow live in a browser and confirm the Supabase row. Copied verbatim from CLAUDE.md: "Verify by actually running the app in a browser and exercising the changed flow end-to-end."
- **Never recreate the home buttons.** Each button is wired by hardcoded `id` via `getElementById(...).addEventListener(...)` (index.html ~L2907+). Reordering MUST move existing DOM nodes (`insertBefore`), not rebuild from a template.
- **Public repo — never commit secrets.** Supabase publishable key only; `service_role` never touches client or repo.
- **`Field tools` (`#fieldTools`) and `Sign out` (`.home-signout`) are pinned last** and are never given arrows / never reordered.
- **Only visible buttons participate.** `admin-only` buttons hidden for the person's role (`body:not(.is-admin) .admin-only { display:none }`) get no arrows and are excluded from the saved order.
- **Degrade, don't crash.** If the `home_order` column is missing or a read fails, fall back to the default DOM order with no error banner (mirror the `isMissingColumn` pattern in `cloud.js`).
- **Migrations** live in `supabase/migrations/`, applied with `supabase db push`. Next number is **0028**.
- **Finish rule:** bump the SW cache version, merge to `main`, push same session, then tell owner to hard-refresh (Ctrl+Shift+R).
- **Current SW cache version is `v29`** (verified in `route-checklist/sw.js`) — Task 5 bumps it to `v30`.
- **CSS variables that exist:** `--ground` (page bg), `--card`/`--wrap` (surfaces), `--line`, `--ink`, `--muted`, `--accent`. **There is no `--bg`.** Use `--ground` for the arrow-button background.

---

### Task 1: Add the `home_order` column (migration)

**Files:**
- Create: `supabase/migrations/0028_profile_home_order.sql`

**Interfaces:**
- Consumes: nothing.
- Produces: a nullable `public.profiles.home_order text[]` column. No new RLS/grants — existing `profiles_update` (0001) already scopes a person to their own row.

- [ ] **Step 1: Write the migration**

Create `supabase/migrations/0028_profile_home_order.sql`:

```sql
-- Personal home-menu ordering: each person stores their preferred order of
-- home-screen button ids as an array of strings. NULL = use the app default.
-- Advisory display data only, never a security boundary. No RLS change needed:
-- profiles_update (0001) already lets a person update only their own row.
alter table public.profiles
  add column if not exists home_order text[];
```

- [ ] **Step 2: Apply it**

Run: `supabase db push`
Expected: applies `0028_profile_home_order.sql` with no error.

- [ ] **Step 3: Verify the column exists**

Run:
```bash
supabase db query --linked "select column_name, data_type from information_schema.columns where table_schema='public' and table_name='profiles' and column_name='home_order';"
```
Expected: one row — `home_order | ARRAY`.

- [ ] **Step 4: Commit**

```bash
git add supabase/migrations/0028_profile_home_order.sql
git commit -m "feat(db): profiles.home_order for personal menu ordering"
```

---

### Task 2: `cloud.js` — `getHomeOrder()` / `saveHomeOrder()`

**Files:**
- Modify: `route-checklist/cloud.js` (add two functions near `saveMyProfile`, ~L149-160; export them in the `Object.assign(window.cloud, {…})` block ~L1176)

**Interfaces:**
- Consumes: `supabase.auth.getUser()`, `isMissingColumn(error)` (already defined ~L393).
- Produces (exported on `window.cloud`):
  - `getHomeOrder()` → `Promise<{ order: string[] | null }>`. Returns the caller's `home_order` array, or `null` on any error / missing column (caller then uses default order).
  - `saveHomeOrder(ids)` → `Promise<{ error: string | null, degraded?: true }>`. Writes `ids` (a `string[]`) to the caller's own row. `degraded: true` if the column is missing.

- [ ] **Step 1: Add the two functions**

In `route-checklist/cloud.js`, immediately after `saveMyProfile` (ends ~L160), add:

```javascript
// ---- Personal home-menu ordering (per-user; own row only) ----

// The caller's saved home-button order, as an array of button ids, or null
// (use the default order). Never throws: any error or a missing column yields
// null so the home screen just falls back to its default layout.
async function getHomeOrder() {
  const { data: { user } } = await supabase.auth.getUser();
  if (!user) return { order: null };
  const { data, error } = await supabase
    .from("profiles").select("home_order").eq("id", user.id).single();
  if (error || !data) return { order: null };
  return { order: Array.isArray(data.home_order) ? data.home_order : null };
}

// Persist the caller's home-button order (array of button ids) to their own
// row. Degrades to a no-op flag if the column isn't there yet.
async function saveHomeOrder(ids) {
  const { data: { user } } = await supabase.auth.getUser();
  if (!user) return { error: "Not signed in." };
  const { error } = await supabase
    .from("profiles").update({ home_order: ids }).eq("id", user.id);
  if (error && isMissingColumn(error)) return { error: null, degraded: true };
  return { error: error ? error.message : null };
}
```

- [ ] **Step 2: Export them on `window.cloud`**

Find the export block (~L1176, `getMyProfile, saveMyProfile,`). Add the two names to the list:

```javascript
                 getMyProfile, saveMyProfile,
                 getHomeOrder, saveHomeOrder,
```

- [ ] **Step 3: Parse-check `cloud.js`**

Run (per-user Chrome; adjust path if needed):
```bash
"$LOCALAPPDATA/Google/Chrome/Application/chrome.exe" --headless --disable-gpu --dump-dom "http://localhost:8000/route-checklist/index.html" > /dev/null
```
(Serve first with `python -m http.server 8000` in the repo root, in another shell.)
Expected: exits cleanly; no `Uncaught SyntaxError` in the console. If a console-capture flag isn't handy, instead run a Node syntax check on just the file:
```bash
node --check route-checklist/cloud.js
```
Expected: no output (valid syntax).

- [ ] **Step 4: Live smoke — the functions round-trip**

Serve the app, sign in as a test tech, open DevTools console, run:
```javascript
await window.cloud.saveHomeOrder(["homeNotes","homeNewVisit"]);
await window.cloud.getHomeOrder();
```
Expected: save returns `{error:null}`; get returns `{order:["homeNotes","homeNewVisit"]}`. Then confirm in Supabase:
```bash
supabase db query --linked "select home_order from profiles where full_name is not null order by full_name limit 5;"
```
Expected: the test tech's row shows `{homeNotes,homeNewVisit}`.

- [ ] **Step 5: Commit**

```bash
git add route-checklist/cloud.js
git commit -m "feat(cloud): getHomeOrder/saveHomeOrder (own profile row)"
```

---

### Task 3: Reconcile-on-load — apply the saved order to the DOM

**Files:**
- Modify: `route-checklist/index.html` — add an `applyHomeOrder()` helper and call it from `showScreen()` when `scr === "home"` (`showScreen` at ~L2878; add a `home` branch alongside the others ~L2887).

**Interfaces:**
- Consumes: `window.cloud.getHomeOrder()` (Task 2).
- Produces (in-page functions, not exported):
  - `reorderableHomeButtons()` → `HTMLElement[]` — the visible `home-btn`s excluding pinned ones, in current DOM order.
  - `applyHomeOrder()` → `Promise<void>` — fetches the saved order and rearranges the DOM to match (default order if none/unavailable). Idempotent; safe to call on every home render.

- [ ] **Step 1: Add the helpers**

In `route-checklist/index.html`, inside the app script near `showScreen` (before it is fine), add:

```javascript
  // --- Personal home-menu ordering ---------------------------------------
  // The pinned tail that never reorders and always stays last.
  const HOME_PINNED_IDS = ["fieldTools"]; // Sign out has no id; handled below.

  // Visible, reorderable home buttons in current DOM order. Excludes the
  // pinned Field tools drawer, the Sign out button, and any admin-only button
  // hidden for this role (offsetParent === null when display:none).
  function reorderableHomeButtons() {
    const home = document.getElementById("homeScreen");
    return Array.from(home.querySelectorAll(".home-btn")).filter(b =>
      b.id &&
      !HOME_PINNED_IDS.includes(b.id) &&
      b.offsetParent !== null            // visible for this role
    );
  }

  // Fetch the saved order and rearrange the existing button nodes to match.
  // Reconcile rules: keep saved ids that are still visible (in saved order),
  // then append any visible id not in the saved list (new buttons -> bottom).
  // Pinned Field tools + Sign out are moved back to the end afterward.
  async function applyHomeOrder() {
    const home = document.getElementById("homeScreen");
    const buttons = reorderableHomeButtons();
    if (!buttons.length) return;
    const byId = new Map(buttons.map(b => [b.id, b]));
    let saved = null;
    try { ({ order: saved } = await window.cloud.getHomeOrder()); } catch { saved = null; }

    let effective;
    if (Array.isArray(saved) && saved.length) {
      const kept = saved.filter(id => byId.has(id));
      const keptSet = new Set(kept);
      const appended = buttons.map(b => b.id).filter(id => !keptSet.has(id));
      effective = kept.concat(appended);
    } else {
      effective = buttons.map(b => b.id); // no preference -> leave default order
    }

    // Reorder in place. Insert each button, in effective order, before the
    // pinned Field tools drawer (which, with Sign out, stays at the tail).
    const fieldTools = document.getElementById("fieldTools");
    const signOut = home.querySelector(".home-signout");
    for (const id of effective) {
      const btn = byId.get(id);
      if (btn) home.insertBefore(btn, fieldTools || signOut || null);
    }
    // Guarantee the pinned tail order: Field tools, then Sign out, last.
    if (fieldTools) home.appendChild(fieldTools);
    if (signOut) home.appendChild(signOut);
  }
```

- [ ] **Step 2: Call it on home render**

In `showScreen()` (~L2887, among the `if (scr === …)` lines), add:

```javascript
    if (scr === "home") applyHomeOrder();
```

- [ ] **Step 3: Parse-check**

Run: `node --check route-checklist/index.html` will fail (HTML, not JS). Instead parse-check live:
Serve with `python -m http.server 8000`, then:
```bash
"$LOCALAPPDATA/Google/Chrome/Application/chrome.exe" --headless --disable-gpu --virtual-time-budget=4000 --dump-dom "http://localhost:8000/route-checklist/index.html" | grep -c "homeScreen"
```
Expected: `1` (page rendered, no fatal script error killing the DOM). Also open the page in a real browser and confirm the console has **no** `Uncaught SyntaxError`.

- [ ] **Step 4: Live — saved order is applied on load**

Sign in as the test tech (who from Task 2 has `home_order = {homeNotes,homeNewVisit}`). Load home.
Expected: `📝 House notes` appears **above** `🏠 New house visit`; every other button follows in default order **below** them; `🧰 Field tools` (if visible) and `Sign out` are last. Tap `📝 House notes` → it still navigates to `#notes` (proves the node moved but its listener survived).

- [ ] **Step 5: Live — stale + new-button tolerance**

In console: `await window.cloud.saveHomeOrder(["bogusId","homeMyNotes"]); location.reload();`
Expected: no error; `📋 My notes` floats to the top; `bogusId` produces no phantom button; every real button not named is present, appended below (proves reconcile drops unknown ids and appends the rest).

- [ ] **Step 6: Commit**

```bash
git add route-checklist/index.html
git commit -m "feat(home): apply saved menu order on render (reconcile, move nodes)"
```

---

### Task 4: Arrange mode — the ⇅ Arrange / ✓ Done UI

**Files:**
- Modify: `route-checklist/index.html` — add the `⇅ Arrange` button to the home `screen-head` (~L895), add arrange-mode CSS (near `.home-btn` styles ~L527), and add the arrange-mode script (toggle, inject ↑/↓, swap, suppress-navigation, save on exit) alongside `applyHomeOrder` from Task 3.

**Interfaces:**
- Consumes: `reorderableHomeButtons()`, `applyHomeOrder()` (Task 3); `window.cloud.saveHomeOrder(ids)` (Task 2).
- Produces: `enterArrangeMode()` / `exitArrangeMode(save)` (in-page); a `homeScreen.classList` flag `arranging`; injected `.home-move` arrow buttons created/removed per session.

- [ ] **Step 1: Add the Arrange toggle button to the header**

In `index.html`, change the home head (~L895) from:

```html
  <div class="screen-head"><h1>Maintenance House Visit</h1></div>
```
to:
```html
  <div class="screen-head"><h1>Maintenance House Visit</h1>
    <button type="button" class="home-arrange-toggle" id="homeArrangeToggle"
      aria-pressed="false">⇅ Arrange</button></div>
```

- [ ] **Step 2: Add the CSS**

Near the `.home-btn` rules (~L527) add:

```css
  .home-arrange-toggle {
    margin-left: auto; font-size: 0.9rem; padding: 6px 12px;
    background: var(--card); color: var(--ink);
    border: 1px solid var(--line); border-radius: 8px; cursor: pointer;
  }
  .home-arrange-toggle:focus-visible { outline: 2px solid var(--ink); outline-offset: 2px; }
  #homeScreen .screen-head { display: flex; align-items: center; gap: 10px; }

  /* Arrange mode: reveal move controls, quiet the pinned tail. */
  .home-move { display: none; }
  #homeScreen.arranging .home-btn { position: relative; padding-right: 92px; }
  #homeScreen.arranging .home-move { display: inline-flex; }
  .home-move {
    position: absolute; top: 50%; transform: translateY(-50%);
    width: 34px; height: 34px; align-items: center; justify-content: center;
    font-size: 1.1rem; line-height: 1; border: 1px solid var(--line);
    border-radius: 8px; background: var(--ground); color: var(--ink); cursor: pointer;
  }
  .home-move.up   { right: 50px; }
  .home-move.down { right: 10px; }
  .home-move:disabled { opacity: 0.35; cursor: default; }
  .home-move:focus-visible { outline: 2px solid var(--ink); outline-offset: 2px; }
  /* Pinned tail is visibly not part of the arrangement. */
  #homeScreen.arranging #fieldTools,
  #homeScreen.arranging .home-signout { opacity: 0.5; pointer-events: none; }
```

- [ ] **Step 3: Add the arrange-mode script**

Alongside `applyHomeOrder` (Task 3), add:

```javascript
  let homeArranging = false;

  function makeMoveBtn(dir, label) {
    const b = document.createElement("button");
    b.type = "button";
    b.className = "home-move " + dir;
    b.textContent = dir === "up" ? "↑" : "↓";
    b.setAttribute("aria-label", label);
    return b;
  }

  function refreshMoveDisabled() {
    const btns = reorderableHomeButtons();
    btns.forEach((b, i) => {
      const up = b.querySelector(".home-move.up");
      const down = b.querySelector(".home-move.down");
      if (up) up.disabled = (i === 0);
      if (down) down.disabled = (i === btns.length - 1);
    });
  }

  function enterArrangeMode() {
    if (homeArranging) return;
    homeArranging = true;
    const home = document.getElementById("homeScreen");
    home.classList.add("arranging");
    const toggle = document.getElementById("homeArrangeToggle");
    toggle.textContent = "✓ Done";
    toggle.setAttribute("aria-pressed", "true");
    // Inject arrows into each reorderable button. Suppress its navigation
    // while arranging via a capture-phase guard added below.
    reorderableHomeButtons().forEach(b => {
      const label = (b.textContent || "").trim().split("\n")[0];
      const up = makeMoveBtn("up", "Move " + label + " up");
      const down = makeMoveBtn("down", "Move " + label + " down");
      up.addEventListener("click", ev => { ev.stopPropagation(); swapHome(b, -1); });
      down.addEventListener("click", ev => { ev.stopPropagation(); swapHome(b, 1); });
      b.appendChild(up);
      b.appendChild(down);
    });
    refreshMoveDisabled();
  }

  // Move button `b` one slot up (-1) or down (+1) among reorderable siblings.
  function swapHome(b, dir) {
    const btns = reorderableHomeButtons();
    const i = btns.indexOf(b);
    const j = i + dir;
    if (j < 0 || j >= btns.length) return;
    const home = document.getElementById("homeScreen");
    if (dir === -1) home.insertBefore(b, btns[j]);
    else home.insertBefore(btns[j], b);
    refreshMoveDisabled();
  }

  async function exitArrangeMode() {
    if (!homeArranging) return;
    homeArranging = false;
    const home = document.getElementById("homeScreen");
    home.classList.remove("arranging");
    const toggle = document.getElementById("homeArrangeToggle");
    toggle.textContent = "⇅ Arrange";
    toggle.setAttribute("aria-pressed", "false");
    // Read current order BEFORE removing arrows (removal doesn't change order,
    // but read first to be safe), then strip the injected arrows.
    const ids = reorderableHomeButtons().map(b => b.id);
    home.querySelectorAll(".home-move").forEach(el => el.remove());
    const res = await window.cloud.saveHomeOrder(ids);
    if (res && res.error) {
      // Keep the on-screen order; tell the user it didn't persist.
      let note = document.getElementById("homeArrangeNote");
      if (!note) {
        note = document.createElement("p");
        note.id = "homeArrangeNote";
        note.className = "screen-sub";
        note.textContent = "Couldn't save your order — it'll reset next time.";
        home.querySelector(".screen-head").after(note);
      }
    }
  }

  // Toggle button
  document.getElementById("homeArrangeToggle").addEventListener("click", () => {
    if (homeArranging) exitArrangeMode(); else enterArrangeMode();
  });

  // Suppress button navigation while arranging (capture phase, so it beats the
  // per-button click handlers). Arrow clicks call stopPropagation already, but
  // a tap on the button body must not navigate.
  document.getElementById("homeScreen").addEventListener("click", ev => {
    if (homeArranging && ev.target.closest(".home-btn") && !ev.target.closest(".home-move")) {
      ev.stopPropagation();
      ev.preventDefault();
    }
  }, true);
```

- [ ] **Step 4: Leave-arrange-on-navigate safety**

In `showScreen()`, ensure leaving home closes arrange mode without losing the order. At the top of `showScreen()` (after `const scr = ...`), add:

```javascript
    if (scr !== "home" && homeArranging) exitArrangeMode();
```

- [ ] **Step 5: Parse-check**

Serve, then in a real browser open the app and confirm the console shows **no** `Uncaught SyntaxError`, and:
```bash
"$LOCALAPPDATA/Google/Chrome/Application/chrome.exe" --headless --disable-gpu --virtual-time-budget=4000 --dump-dom "http://localhost:8000/route-checklist/index.html" | grep -c "homeArrangeToggle"
```
Expected: `1`.

- [ ] **Step 6: Live — full arrange flow**

Sign in as the test tech. On home:
- Tap `⇅ Arrange` → button becomes `✓ Done`; every reorderable button shows ↑/↓; `Field tools`/`Sign out` are dimmed and have no arrows; the first button's ↑ and the last's ↓ are disabled.
- Tap ↓ on `🏠 New house visit` a couple of times → it moves down live.
- Tab to an arrow with the keyboard, press Enter → it moves; focus ring visible.
- Tap the **body** of a button (not an arrow) → it does **not** navigate.
- Tap `✓ Done` → arrows disappear, order stays, and Supabase shows the new array:
```bash
supabase db query --linked "select home_order from profiles where home_order is not null limit 5;"
```
- Reload → the arranged order is restored (Task 3 applies it).
- Enter arrange, reorder, then tap a real nav (e.g. via hash change) mid-arrange → confirm arrange closes and the order was saved (Step 4 path).

- [ ] **Step 7: Commit**

```bash
git add route-checklist/index.html
git commit -m "feat(home): arrange mode with up/down controls, pinned tail, save on done"
```

---

### Task 5: Ship it — SW cache bump, deploy, verify live

**Files:**
- Modify: `route-checklist/sw.js` (cache version bump).
- Modify: `route-checklist/HANDOFF.md` and `START-HERE.md` (note the feature).

**Interfaces:** none (release task).

- [ ] **Step 1: Bump the service-worker cache version**

Open `route-checklist/sw.js`, find the current cache version constant (currently `v29`), and increment it by one (`v29` → `v30`). This forces clients to pick up the new `index.html` + `cloud.js`.

Run to confirm the change:
```bash
git diff route-checklist/sw.js
```
Expected: exactly the version string changed.

- [ ] **Step 2: Update the docs**

Add a short entry to `route-checklist/HANDOFF.md` (current-state section) and `START-HERE.md` describing: personal home-menu ordering — per-user `profiles.home_order`, `getHomeOrder`/`saveHomeOrder` in `cloud.js`, `⇅ Arrange` mode on home, reconcile-on-load (drops unknown ids, appends new buttons at bottom), Field tools + Sign out pinned.

- [ ] **Step 3: Commit**

```bash
git add route-checklist/sw.js route-checklist/HANDOFF.md START-HERE.md
git commit -m "chore: bump SW cache; document personal home-menu ordering"
```

- [ ] **Step 4: Merge to main and push**

Confirm you're on `main` (per owner rule, finished slices ship from `main`):
```bash
git branch --show-current
```
If on a feature branch, merge it into `main` first. Then:
```bash
git push
```

- [ ] **Step 5: Verify the deploy is actually live**

Per the deploy-from-main memory, don't trust that Pages built — confirm the new SW is served:
```bash
curl -s "https://<pages-domain>/route-checklist/sw.js" | grep -o "v[0-9]*"
```
Expected: the new version number (`v30`). If it still shows the old one (`v29`), the deploy hasn't finished — wait and re-check.

- [ ] **Step 6: Tell the owner to hard-refresh**

Remind the owner: hard-refresh (Ctrl+Shift+R) on desktop; fully close and reopen the PWA on phones, so the new service worker takes over. Then have them try `⇅ Arrange` on their own account.

---

## Self-Review

**Spec coverage** (each spec section → task):

- Migration `0028` / `home_order text[]`, no RLS change → **Task 1** ✅
- `getHomeOrder()` / `saveHomeOrder()` with `isMissingColumn` degrade, own row only → **Task 2** ✅
- Arrange mode: ⇅ Arrange trigger, ↑/↓ injected, click-nav suppressed, Field tools + Sign out pinned/dimmed, ✓ Done saves, disabled end arrows, a11y labels/focus → **Task 4** ✅
- Reconcile-on-load: read visible reorderable set, keep saved ∩ visible, append new at bottom, move nodes, pinned tail last → **Task 3** ✅
- New-button-to-bottom + stale-id tolerance → verified in **Task 3 Step 5** ✅
- Error handling: column missing → default order (Task 3 `try/catch`, Task 2 null); save fails → keep order + inline note (Task 4 `exitArrangeMode`) → ✅
- Move nodes not recreate (listeners survive) → verified in **Task 3 Step 4** (tap a moved button) ✅
- SW cache bump, merge to main, push, hard-refresh reminder → **Task 5** ✅
- Verification method (parse-check + live + Supabase row) → every task's test steps ✅

**Placeholder scan:** No TBD/TODO. The one literal placeholder is `<pages-domain>` in Task 5 Step 5 — intentional, resolved from the live URL at execution time (the deploy-from-main memory requires curling the real domain). Cache version `v24→v25` is illustrative; Step 1 says "current version + 1" and shows how to confirm the actual diff.

**Type consistency:** `getHomeOrder()` returns `{ order }`; every consumer destructures `{ order: saved }` (Task 3) — matches. `saveHomeOrder(ids)` takes `string[]`, returns `{ error, degraded? }`; callers check `res.error` (Task 4) — matches. `reorderableHomeButtons()` returns `HTMLElement[]`, used by `swapHome`, `refreshMoveDisabled`, `applyHomeOrder`, `exitArrangeMode` — consistent. `HOME_PINNED_IDS`/`#fieldTools`/`.home-signout` naming consistent across Tasks 3 and 4.

**Ambiguity check:** "Reorderable button" is defined once in `reorderableHomeButtons()` (visible, has id, not pinned) and every other function derives from it, so there's a single source of truth.
