# House Note Suggestions Implementation Plan

> **For agentic workers:** REQUIRED SUB-SKILL: Use superpowers:subagent-driven-development (recommended) or superpowers:executing-plans to implement this plan task-by-task. Steps use checkbox (`- [ ]`) syntax for tracking.

**Goal:** Techs can propose edits/additions/removals to per-item house notes and house-info pairs (pending until a supervisor approves or denies with an optional reason); supervisors edit directly and get a cross-house Pending changes queue.

**Architecture:** Extend the existing migration-0006 suggestion system (`house_note_suggestions` table + atomic approve RPC) to cover all three note kinds (`general` / `item` / `info`) instead of building a parallel table. The UI talks only to `cloud.js` (never Supabase directly). Spec: `docs/superpowers/specs/2026-07-12-house-note-suggestions-design.md`.

**Tech Stack:** Vanilla HTML/CSS/JS (no build step, no deps), Supabase (Postgres + RLS + plpgsql RPCs), Supabase CLI for migrations.

## Global Constraints

- **No automated test runner exists.** Per CLAUDE.md, verification = driving the app in a browser and checking rows in Supabase. Auth requires the served origin, so full end-to-end verification happens on the live GitHub Pages URL (`https://tweet-delta.github.io/mtx-sandbox/route-checklist/index.html#home`) after the final push. **GitHub Pages deploys from branch `claude/claude-code-tutorial-5l5ew2`, not `main`** — do not push until Task 7 (a mid-feature push deploys a half-built UI to the owner's live demo). Per-task checks are parse/render sanity checks.
- Migrations are applied ONLY with `supabase db push` (CLI is installed, logged in, linked). Never hand-paste SQL into the dashboard. Read-only spot-check queries in the dashboard SQL editor are fine.
- This repo is PUBLIC. No secrets, no real house data. The publishable key in `supabase-config.js` is safe by design.
- RLS is the enforcement; the UI only hides. Every new privileged path must be blocked by Postgres for the wrong role, not just hidden.
- All user-entered text rendered via `escHtml`/`escAttr` (defined in `index.html` ~line 1635). Inside `build()` keep the file's existing `.replace(/</g, "&lt;")` idiom.
- Never wipe typed text on a failed save — show the error next to the control and keep the form.
- Accessibility: `aria-label` on every icon button naming the specific note; move focus into an opened editor and back to its trigger on cancel; state conveyed as text, not color alone.
- Reviewed suggestion rows are an audit trail — never delete them (only the author-withdraw path deletes, and only while pending).
- Keep item keys stable; note keys are the existing `NOTE_KEY_LABELS` keys (`fireExtinguishers`, `furnaceFilter`, `fridgeCoils`, `waterSoftener`, `shutoffs`, `knives`, `medLock`, `atticAccess`, `dryerVents`).
- Commit after every task. Commit messages end with `Co-Authored-By: Claude Fable 5 <noreply@anthropic.com>`.

---

### Task 1: Migration 0008 — suggestions for all note kinds

**Files:**
- Create: `supabase/migrations/0008_note_suggestions_all_kinds.sql`

**Interfaces:**
- Consumes: `public.house_note_suggestions`, `public.houses`, `public.current_user_role()` (all from migrations 0001/0006).
- Produces: columns `target` / `note_key` / `action` / `deny_reason` / `seen_by_author` on `house_note_suggestions`; replaced RPC `approve_note_suggestion(suggestion_id uuid)`; new RPC `deny_note_suggestion(suggestion_id uuid, reason text default '')`; RLS policy `hns_update_author_seen`; trigger `hns_guard_author_update`.

- [ ] **Step 1: Write the migration file**

Create `supabase/migrations/0008_note_suggestions_all_kinds.sql` with exactly:

```sql
-- ============================================================================
-- 0008_note_suggestions_all_kinds.sql — suggestions for ALL house-note kinds
--
-- Migration 0006 built suggest/approve for the freeform general note only.
-- This generalizes the same table + RPC to the per-item notes (houses.notes
-- jsonb) and the house-info pairs (houses.info jsonb), and adds:
--   * action 'delete' — a tech can propose REMOVING a stale note.
--   * deny_reason — supervisor's optional reason; the author sees it.
--   * seen_by_author — author dismisses the denial notice (row is kept:
--     reviewed rows are the audit trail and are never deleted).
--
-- Safe to re-run (if-not-exists / drop-if-exists / create-or-replace).
-- ============================================================================

-- 1. New columns. Defaults make every pre-0008 row a valid 'general' edit.
alter table public.house_note_suggestions
  add column if not exists target text not null default 'general',
  add column if not exists note_key text not null default '',
  add column if not exists action text not null default 'set',
  add column if not exists deny_reason text not null default '',
  add column if not exists seen_by_author boolean not null default false;

alter table public.house_note_suggestions
  drop constraint if exists hns_target_ck;
alter table public.house_note_suggestions
  add constraint hns_target_ck check (target in ('general', 'item', 'info'));

alter table public.house_note_suggestions
  drop constraint if exists hns_action_ck;
alter table public.house_note_suggestions
  add constraint hns_action_ck check (action in ('set', 'delete'));

-- general notes are edited (possibly to empty), never key-addressed or
-- deleted; item/info suggestions must say WHICH note they mean.
alter table public.house_note_suggestions
  drop constraint if exists hns_target_key_ck;
alter table public.house_note_suggestions
  add constraint hns_target_key_ck check (
    (target = 'general' and note_key = '' and action = 'set')
    or (target in ('item', 'info') and note_key <> '')
  );

-- 2. Authors may update their own REVIEWED rows... (policy) but a trigger
--    below restricts that update to flipping seen_by_author — nothing else.
drop policy if exists hns_update_author_seen on public.house_note_suggestions;
create policy hns_update_author_seen on public.house_note_suggestions
  for update to authenticated
  using (author_id = auth.uid() and status <> 'pending')
  with check (author_id = auth.uid() and status <> 'pending');

create or replace function public.hns_guard_author_update()
returns trigger
language plpgsql
security definer set search_path = public
as $$
begin
  if public.current_user_role() = 'supervisor' then
    return new;   -- supervisors update via the RPCs; don't restrict them
  end if;
  if new.house_id       is distinct from old.house_id
     or new.author_id     is distinct from old.author_id
     or new.author_name   is distinct from old.author_name
     or new.proposed_text is distinct from old.proposed_text
     or new.status        is distinct from old.status
     or new.created_at    is distinct from old.created_at
     or new.reviewed_by   is distinct from old.reviewed_by
     or new.reviewed_at   is distinct from old.reviewed_at
     or new.target        is distinct from old.target
     or new.note_key      is distinct from old.note_key
     or new.action        is distinct from old.action
     or new.deny_reason   is distinct from old.deny_reason then
    raise exception 'Only seen_by_author can be changed';
  end if;
  return new;
end;
$$;

drop trigger if exists hns_guard_author_update on public.house_note_suggestions;
create trigger hns_guard_author_update
  before update on public.house_note_suggestions
  for each row execute function public.hns_guard_author_update();

-- 3. Atomic approve, now target-aware. SECURITY DEFINER + its own role check,
--    so Postgres (not the UI) stops non-supervisors.
create or replace function public.approve_note_suggestion(suggestion_id uuid)
returns void
language plpgsql
security definer set search_path = public
as $$
declare
  s        public.house_note_suggestions%rowtype;
  cur_info jsonb;
  idx      int;
begin
  if public.current_user_role() is distinct from 'supervisor' then
    raise exception 'Only a supervisor can approve suggestions';
  end if;
  select * into s from public.house_note_suggestions
    where id = suggestion_id and status = 'pending'
    for update;
  if not found then
    raise exception 'Suggestion not found or already reviewed';
  end if;

  if s.target = 'general' then
    update public.houses set general_notes = s.proposed_text
      where id = s.house_id;

  elsif s.target = 'item' then
    if s.action = 'delete' then
      -- removing an already-removed key is a harmless no-op: same end state.
      update public.houses set notes = coalesce(notes, '{}'::jsonb) - s.note_key
        where id = s.house_id;
    else
      update public.houses
        set notes = jsonb_set(coalesce(notes, '{}'::jsonb),
                              array[s.note_key], to_jsonb(s.proposed_text), true)
        where id = s.house_id;
    end if;

  else  -- 'info': [label, detail] pairs; operations target the FIRST pair
        -- whose label matches (set semantics: add-with-existing-label = edit).
    select info into cur_info from public.houses where id = s.house_id for update;
    cur_info := coalesce(cur_info, '[]'::jsonb);
    select t.i - 1 into idx
      from jsonb_array_elements(cur_info) with ordinality as t(pair, i)
      where t.pair->>0 = s.note_key
      limit 1;
    if s.action = 'delete' then
      if idx is not null then
        cur_info := cur_info - idx;
      end if;
    elsif idx is not null then
      cur_info := jsonb_set(cur_info, array[idx::text, '1'],
                            to_jsonb(s.proposed_text));
    else
      cur_info := cur_info
        || jsonb_build_array(jsonb_build_array(s.note_key, s.proposed_text));
    end if;
    update public.houses set info = cur_info where id = s.house_id;
  end if;

  update public.house_note_suggestions
    set status = 'approved', reviewed_by = auth.uid(), reviewed_at = now()
    where id = suggestion_id;
end;
$$;

revoke execute on function public.approve_note_suggestion(uuid) from public, anon;
grant  execute on function public.approve_note_suggestion(uuid) to authenticated;

-- 4. Deny: reason + review stamp in one statement, same locking discipline.
create or replace function public.deny_note_suggestion(suggestion_id uuid, reason text default '')
returns void
language plpgsql
security definer set search_path = public
as $$
declare
  s public.house_note_suggestions%rowtype;
begin
  if public.current_user_role() is distinct from 'supervisor' then
    raise exception 'Only a supervisor can deny suggestions';
  end if;
  select * into s from public.house_note_suggestions
    where id = suggestion_id and status = 'pending'
    for update;
  if not found then
    raise exception 'Suggestion not found or already reviewed';
  end if;
  update public.house_note_suggestions
    set status = 'dismissed', deny_reason = coalesce(reason, ''),
        reviewed_by = auth.uid(), reviewed_at = now()
    where id = suggestion_id;
end;
$$;

revoke execute on function public.deny_note_suggestion(uuid, text) from public, anon;
grant  execute on function public.deny_note_suggestion(uuid, text) to authenticated;
```

- [ ] **Step 2: Push the migration**

Run from the repo root: `supabase db push`
Expected: prompt lists `0008_note_suggestions_all_kinds.sql`, confirm, ends with `Finished supabase db push.` (no errors).

- [ ] **Step 3: Verify it applied**

Run: `supabase migration list`
Expected: `0008` shows in BOTH the Local and Remote columns.

Then in the Supabase dashboard SQL editor (read-only spot check, allowed):
```sql
select target, note_key, action, deny_reason, seen_by_author
from public.house_note_suggestions limit 3;
```
Expected: query succeeds (columns exist); any pre-existing rows show `general` / `''` / `set` / `''` / `false`.

- [ ] **Step 4: Commit**

```bash
git add supabase/migrations/0008_note_suggestions_all_kinds.sql
git commit -m "feat: migration 0008 — note suggestions for item notes + info pairs, deny reason, atomic target-aware approve"
```

---

### Task 2: cloud.js — data-module functions

**Files:**
- Modify: `route-checklist/cloud.js` (house-notes section ~lines 253–324, `loadHouses` ~line 43, `loadRole` ~line 64, exports ~line 372)

**Interfaces:**
- Consumes: Task 1's columns and RPCs; existing `housesByName` Map, `isMissingColumn(error)`, `loadHouses()`, `supabase` client.
- Produces (all on `window.cloud`):
  - `getHouseNotes(houseName)` → `{ error }` | `{ notReady: true }` | `{ generalNotes: string, suggestions: Sug[], denials: Denial[] }` where `Sug = { id, target: 'general'|'item'|'info', noteKey: string, action: 'set'|'delete', text: string, authorName: string, createdAt: string, mine: boolean }` and `Denial = { id, target, noteKey, action, text, denyReason }` (only the caller's own unseen denials).
  - `suggestChange(houseName, { target, noteKey, action, text }, authorName)` → `{ ok: true }` | `{ error }`
  - `suggestNote(houseName, text, authorName)` — kept, now delegates to `suggestChange`.
  - `denySuggestion(id, reason)` → `{ ok: true }` | `{ error }` (replaces `dismissSuggestion`, which is removed).
  - `markDenialSeen(id)` → `{ ok: true }` | `{ error }`
  - `saveHouseField(houseName, { target, noteKey, action, text })` → `{ ok: true }` | `{ error }` (supervisor direct write; refreshes the house cache via `loadHouses()`).
  - `listPendingSuggestions()` → `{ error, notReady? }` | `{ suggestions: [{ id, houseName, target, noteKey, action, text, authorName, createdAt, current }] }` (`current` = today's official text for that note, `''` if none).
  - `pendingCount()` → `{ error }` | `{ count: number }`
  - `approveSuggestion(id)` — same signature; on success now calls `loadHouses()` so 📍 notes repaint fresh.
  - After `loadRole()` resolves a supervisor, cloud calls `window.applyPendingCount(count)` if the app defined it.

- [ ] **Step 1: Add `general_notes` to the houses load**

In `loadHouses()` (~line 43), change both select strings:
- `"id, name, equipment, notes, info, route_id"` → `"id, name, equipment, notes, info, general_notes, route_id"`
- `"id, name, equipment, notes, info"` → `"id, name, equipment, notes, info, general_notes"`

(The pending queue needs the current general note to show "current vs proposed" without a per-row query. Migration 0006 is applied, so the column exists; the pre-0007 fallback path still works because it also gets the column.)

- [ ] **Step 2: Replace the house-notes section**

Replace the entire block from the comment `// ---- House notes: official freeform note + tech suggestions ----` (~line 253) through the end of `saveGeneralNotes` (~line 324) with:

```js
// ---- House notes: official notes + tech suggestions (all kinds) ----
// Official data lives on the houses row: general_notes (text), notes (jsonb,
// item-note keys), info (jsonb [label, detail] pairs). A tech's proposed
// change is a house_note_suggestions row (target = general|item|info).
// Nothing changes for other techs until a supervisor approves (atomic RPC).

const SUG_COLS = "id, author_id, author_name, proposed_text, created_at, target, note_key, action";

function mapSug(s, uid) {
  return {
    id: s.id,
    target: s.target || "general",
    noteKey: s.note_key || "",
    action: s.action || "set",
    text: s.proposed_text,
    authorName: s.author_name || "(name not set)",
    createdAt: s.created_at,
    mine: !!uid && s.author_id === uid,
  };
}

async function getHouseNotes(houseName) {
  const house = housesByName.get((houseName || "").trim().toLowerCase());
  if (!house) return { error: `"${houseName}" isn't a house in the database.` };
  const { data, error } = await supabase
    .from("houses").select("general_notes").eq("id", house.id).single();
  // Migration 0006 not applied yet → tell the UI, don't fake an empty note.
  if (error) {
    return isMissingColumn(error) ? { notReady: true } : { error: error.message };
  }
  const { data: { user } } = await supabase.auth.getUser();
  let { data: sugs, error: e2 } = await supabase
    .from("house_note_suggestions").select(SUG_COLS)
    .eq("house_id", house.id).eq("status", "pending")
    .order("created_at", { ascending: false });
  // Migration 0008 not applied yet → fall back to the 0006 shape (general only).
  if (e2 && isMissingColumn(e2)) {
    ({ data: sugs, error: e2 } = await supabase
      .from("house_note_suggestions")
      .select("id, author_id, author_name, proposed_text, created_at")
      .eq("house_id", house.id).eq("status", "pending")
      .order("created_at", { ascending: false }));
  }
  if (e2) return { error: e2.message };
  // My denied-and-not-yet-dismissed suggestions (the ❌ notices).
  let denials = [];
  if (user) {
    const { data: dens, error: e3 } = await supabase
      .from("house_note_suggestions")
      .select(SUG_COLS + ", deny_reason")
      .eq("house_id", house.id).eq("status", "dismissed")
      .eq("author_id", user.id).eq("seen_by_author", false)
      .order("created_at", { ascending: false });
    if (!e3) denials = dens || [];        // pre-0008 DB → just no denial notices
  }
  return {
    generalNotes: data.general_notes || "",
    suggestions: (sugs || []).map(s => mapSug(s, user?.id)),
    denials: denials.map(d => ({ ...mapSug(d, user?.id), denyReason: d.deny_reason || "" })),
  };
}

async function suggestChange(houseName, { target, noteKey, action, text }, authorName) {
  const house = housesByName.get((houseName || "").trim().toLowerCase());
  if (!house) return { error: `"${houseName}" isn't a house in the database.` };
  const { data: { user } } = await supabase.auth.getUser();
  const { error } = await supabase.from("house_note_suggestions").insert({
    house_id: house.id,
    target: target || "general",
    note_key: noteKey || "",
    action: action || "set",
    proposed_text: action === "delete" ? "" : (text || ""),
    author_name: (authorName || "").trim() || user?.email || "",
  });
  return error ? { error: error.message } : { ok: true };
}

// Kept for the general-notes editor (and any old callers).
async function suggestNote(houseName, text, authorName) {
  return suggestChange(houseName, { target: "general", noteKey: "", action: "set", text }, authorName);
}

async function withdrawSuggestion(id) {
  const { error } = await supabase
    .from("house_note_suggestions").delete().eq("id", id);
  return error ? { error: error.message } : { ok: true };
}

async function approveSuggestion(id) {
  const { error } = await supabase.rpc("approve_note_suggestion", { suggestion_id: id });
  if (error) return { error: error.message };
  await loadHouses();   // the official note changed — refresh 📍 notes everywhere
  return { ok: true };
}

async function denySuggestion(id, reason) {
  const { error } = await supabase.rpc("deny_note_suggestion",
    { suggestion_id: id, reason: reason || "" });
  return error ? { error: error.message } : { ok: true };
}

async function markDenialSeen(id) {
  const { error } = await supabase.from("house_note_suggestions")
    .update({ seen_by_author: true }).eq("id", id);
  return error ? { error: error.message } : { ok: true };
}

async function saveGeneralNotes(houseName, text) {
  const house = housesByName.get((houseName || "").trim().toLowerCase());
  if (!house) return { error: `"${houseName}" isn't a house in the database.` };
  const { error } = await supabase
    .from("houses").update({ general_notes: text }).eq("id", house.id);
  return error ? { error: error.message } : { ok: true };
}

// Supervisor direct write: set/remove one item note or info pair. The patch is
// computed from the cached house row, written as one column update (RLS
// houses_write = supervisor-only enforces the role), then the cache is
// re-fetched so every screen repaints truthful data.
async function saveHouseField(houseName, { target, noteKey, action, text }) {
  const house = housesByName.get((houseName || "").trim().toLowerCase());
  if (!house) return { error: `"${houseName}" isn't a house in the database.` };
  let patch;
  if (target === "item") {
    const notes = { ...(house.notes || {}) };
    if (action === "delete") delete notes[noteKey];
    else notes[noteKey] = text;
    patch = { notes };
  } else if (target === "info") {
    const info = (house.info || []).map(p => [...p]);
    const i = info.findIndex(p => p[0] === noteKey);
    if (action === "delete") { if (i >= 0) info.splice(i, 1); }
    else if (i >= 0) info[i][1] = text;
    else info.push([noteKey, text]);
    patch = { info };
  } else {
    return { error: "Unknown field target: " + target };
  }
  const { error } = await supabase.from("houses").update(patch).eq("id", house.id);
  if (error) return { error: error.message };
  await loadHouses();
  return { ok: true };
}

// Every pending suggestion across all houses (the supervisor queue).
// `current` is the official text today, so the queue can show old vs new.
async function listPendingSuggestions() {
  const { data, error } = await supabase
    .from("house_note_suggestions")
    .select(SUG_COLS + ", house_id")
    .eq("status", "pending")
    .order("created_at", { ascending: false });
  if (error) return { error: error.message, notReady: isMissingColumn(error) };
  const byId = new Map([...housesByName.values()].map(h => [h.id, h]));
  const { data: { user } } = await supabase.auth.getUser();
  return {
    suggestions: (data || []).map(s => {
      const house = byId.get(s.house_id);
      let current = "";
      if (house) {
        if (s.target === "item") current = (house.notes || {})[s.note_key] || "";
        else if (s.target === "info") current = ((house.info || []).find(p => p[0] === s.note_key) || [])[1] || "";
        else current = house.general_notes || "";
      }
      return { ...mapSug(s, user?.id), houseName: house ? house.name : "(unknown house)", current };
    }),
  };
}

async function pendingCount() {
  const { count, error } = await supabase
    .from("house_note_suggestions")
    .select("id", { count: "exact", head: true })
    .eq("status", "pending");
  return error ? { error: error.message } : { count: count || 0 };
}
```

- [ ] **Step 3: Tell the app the pending count when a supervisor signs in**

At the end of `loadRole()` (~line 72, after `document.body.classList.toggle("is-admin", ...)`), add:

```js
  if (window.cloud.role === "supervisor") {
    pendingCount().then(r => {
      if (!r.error && window.applyPendingCount) window.applyPendingCount(r.count);
    });
  }
```

- [ ] **Step 4: Update the exports**

Replace the `window.cloud = { ... }` object (~line 372) so the notes-related exports read (keep every non-notes entry exactly as it is):

```js
window.cloud = { saveVisit, loadInProgress, lastDone, listInProgress,
                 getHouseNotes, suggestNote, suggestChange, withdrawSuggestion,
                 approveSuggestion, denySuggestion, markDenialSeen,
                 saveGeneralNotes, saveHouseField,
                 listPendingSuggestions, pendingCount,
                 listRoutes, listTechs, saveRoute, setHouseRoute, listHousesForRoutes,
                 refreshMyRoute: loadMyRoute,
                 role: null };
```

(`dismissSuggestion` is intentionally gone — `denySuggestion` replaces it. Task 3 updates the one UI call site.)

- [ ] **Step 5: Parse check**

Open `route-checklist/index.html` in a browser (file:// is fine for this) with DevTools console open. Expected: no `SyntaxError` from `cloud.js`. (The login gate will show; that's fine — we only need the script to parse.)

- [ ] **Step 6: Commit**

```bash
git add route-checklist/cloud.js
git commit -m "feat: cloud.js — suggest/approve/deny for item notes + info pairs, pending queue + count"
```

---

### Task 3: Notes screen — pending display, denial notices, review actions

Rework the House Notes screen so every info pair and item note renders as an editable "field row" with its pending suggestions and denial notices under it, and unify the general-notes suggestion blocks onto the same shared helpers (this is where Deny-with-reason replaces the old Dismiss).

**Files:**
- Modify: `route-checklist/index.html` — CSS block (~lines 533–567), `allHouseDetailsHTML`/`renderNotesScreen`/`genNotesHTML`/listeners/`refreshGenNotes`/`sugAction` (~lines 1948–2120)

**Interfaces:**
- Consumes: `window.cloud.getHouseNotes / approveSuggestion / denySuggestion / withdrawSuggestion / markDenialSeen / pendingCount` (Task 2 shapes); existing `NOTE_KEY_LABELS`, `ALL_CODES`, `escHtml`, `escAttr`, `fmtDate`, `toast`, `notesHouseFromHash`.
- Produces (used by Tasks 4–6): `sugBlockHTML(s, opts)` (`opts.current` optional), `denialBlockHTML(d)`, `sugClickActions(e, refresh)` → `Promise<boolean>`, `refreshPendingBadge()`, `refreshNotesData()`, `repaintFields()`, `fieldRowsForHouse(house, res)`, module state `lastNotesRes`, `fieldEditor`; DOM ids `houseFieldsSec`, `genNotesSec`.

- [ ] **Step 1: Add CSS**

After the `.sug-actions button:focus-visible ...` rule (~line 553), insert:

```css
  /* Field rows (editable house notes) + suggestion review controls */
  .field-edit-btn, .hn-edit {
    background: none; border: 1px solid var(--line); border-radius: 6px;
    cursor: pointer; font: inherit; font-size: 0.8rem; padding: 2px 8px;
    margin-left: 6px; color: var(--muted); min-height: 28px;
  }
  .hn-add {
    background: none; border: 1px dashed var(--line); border-radius: 6px;
    cursor: pointer; font: inherit; font-size: 0.78rem; color: var(--muted);
    padding: 2px 8px; min-height: 28px;
  }
  .field-edit-btn:focus-visible, .hn-edit:focus-visible, .hn-add:focus-visible {
    outline: 2px solid var(--ink); outline-offset: 2px;
  }
  .field-form { margin-top: 6px; }
  .field-form textarea, .field-form input, .field-form select {
    width: 100%; box-sizing: border-box; font: inherit; font-size: 16px;
    padding: 8px 10px; border: 1px solid var(--line); border-radius: 8px;
    margin-bottom: 6px; background: var(--card); color: var(--ink);
  }
  .field-form textarea { min-height: 64px; resize: vertical; }
  .field-form label { display: block; font-size: 0.78rem; color: var(--muted); margin-bottom: 2px; }
  .sug-current { font-size: 0.78rem; color: var(--muted); margin: 0 0 8px; }
  .deny-form { display: flex; gap: 6px; flex-wrap: wrap; margin-top: 6px; }
  .deny-form input {
    flex: 1 1 160px; font: inherit; font-size: 16px; padding: 6px 8px;
    border: 1px solid var(--line); border-radius: 6px;
  }
  .denied {
    background: #FDF2F2; border: 1px solid #F5C6C6; border-radius: 8px;
    padding: 8px 10px; margin-top: 6px; font-size: 0.85rem;
  }
  .denied .denied-text { display: block; color: var(--muted); font-size: 0.8rem; margin: 2px 0 4px; }
  .denied button {
    font: inherit; font-size: 0.78rem; border: 1px solid var(--line);
    border-radius: 6px; background: var(--card); cursor: pointer; padding: 2px 8px;
  }
  .denied button:focus-visible { outline: 2px solid var(--ink); outline-offset: 2px; }
  .no-note { color: var(--muted); font-style: italic; }
```

- [ ] **Step 2: Replace `allHouseDetailsHTML` with field-row helpers**

Replace the whole `allHouseDetailsHTML` function (~lines 1964–1977) with:

```js
  // Every editable house fact as a "field row": info pairs + item notes,
  // PLUS rows for pending suggestions/denials whose key has no official
  // value yet (a proposed addition still needs somewhere to show).
  function fieldRowsForHouse(house, res) {
    const rows = new Map();   // "target key" → row
    const put = (target, key, text) => {
      const label = target === "item" ? (NOTE_KEY_LABELS[key] || key) : key;
      rows.set(target + " " + key, { target, key, label, text });
    };
    (house.info || []).forEach(([label, val]) => put("info", label, val));
    Object.entries(house.notes || {}).filter(([, t]) => t)
      .forEach(([k, t]) => put("item", k, t));
    if (res && !res.error && !res.notReady) {
      res.suggestions.concat(res.denials || []).forEach(s => {
        if (s.target !== "general" && !rows.has(s.target + " " + s.noteKey))
          put(s.target, s.noteKey, "");
      });
    }
    return [...rows.values()];
  }

  // One pending suggestion, with role-appropriate actions. Shared by the
  // notes screen, the checklist inline notes, and the pending queue.
  function sugBlockHTML(s, opts) {
    const isAdmin = window.cloud && window.cloud.role === "supervisor";
    const what = s.action === "delete"
      ? `<p class="sug-text no-note">Proposes removing this note</p>`
      : `<p class="sug-text">${escHtml(s.text)}</p>`;
    const current = opts && opts.current !== undefined
      ? `<p class="sug-current">Current: ${opts.current ? escHtml(opts.current) : "(none)"}</p>` : "";
    return `
      <div class="sug" data-sug-id="${escAttr(s.id)}">
        <div class="sug-meta">⏳ Awaiting approval — ${escHtml(s.authorName)}${s.createdAt ? " · " + fmtDate(s.createdAt.slice(0, 10)) : ""}</div>
        ${what}${current}
        <div class="sug-actions">
          ${isAdmin ? `<button type="button" class="btn-primary" data-sug-approve="${escAttr(s.id)}">✓ Approve</button>
                       <button type="button" data-sug-deny="${escAttr(s.id)}">✕ Deny…</button>` : ""}
          ${s.mine ? `<button type="button" class="btn-danger" data-sug-withdraw="${escAttr(s.id)}">Withdraw</button>` : ""}
        </div>
        <div class="deny-form" data-deny-form="${escAttr(s.id)}" hidden>
          <input type="text" data-deny-reason="${escAttr(s.id)}" placeholder="Reason — the tech will see this (optional)" aria-label="Reason for denying this suggestion">
          <button type="button" class="btn-danger" data-deny-confirm="${escAttr(s.id)}">Deny</button>
          <button type="button" data-deny-cancel="${escAttr(s.id)}">Cancel</button>
        </div>
      </div>`;
  }

  // The author's ❌ notice for a denied suggestion (until they dismiss it).
  function denialBlockHTML(d) {
    return `
      <div class="denied" role="status">
        ❌ <b>Denied</b>${d.denyReason ? " — " + escHtml(d.denyReason) : ""}
        <span class="denied-text">Your suggestion: ${d.action === "delete" ? "remove this note" : escHtml(d.text)}</span>
        <button type="button" data-denied-dismiss="${escAttr(d.id)}">Dismiss</button>
      </div>`;
  }

  // One field row: official value + ✎ + its pending/denied blocks.
  // (The ✎ edit control itself is wired in the next task.)
  function fieldRowHTML(row, res) {
    const isAdmin = window.cloud && window.cloud.role === "supervisor";
    const canCloud = !!(window.cloud && res && !res.error && !res.notReady);
    const sugs = canCloud ? res.suggestions.filter(s => s.target === row.target && s.noteKey === row.key) : [];
    const dens = canCloud ? (res.denials || []).filter(d => d.target === row.target && d.noteKey === row.key) : [];
    const editing = fieldEditor && fieldEditor.mode === "edit"
      && fieldEditor.target === row.target && fieldEditor.key === row.key;
    const editBtn = canCloud && !editing
      ? `<button type="button" class="field-edit-btn" data-field-edit
           data-target="${escAttr(row.target)}" data-key="${escAttr(row.key)}"
           aria-label="${isAdmin ? "Edit" : "Suggest a fix to"} the ${escAttr(row.label)} note"><span aria-hidden="true">✎</span></button>`
      : "";
    return `<div class="notes-item"><b>${escHtml(row.label)}</b><span>${row.text ? escHtml(row.text) : `<span class="no-note">(no note yet)</span>`}</span>${editBtn}
      ${editing ? fieldEditorHTML(row.target, row.key, row.label, row.text) : ""}
      ${sugs.map(s => sugBlockHTML(s)).join("")}
      ${dens.map(denialBlockHTML).join("")}
    </div>`;
  }

  // The whole editable-fields section: door codes (read-only, on-device data)
  // then every field row, then the add buttons (wired in the next task).
  function houseFieldsHTML(house, res) {
    const rows = [];
    (ALL_CODES[house.name] || []).forEach(([label, val]) =>
      rows.push(`<div class="notes-item"><b>${escHtml(label)}</b>${escHtml(val)}</div>`));
    fieldRowsForHouse(house, res).forEach(row => rows.push(fieldRowHTML(row, res)));
    const body = rows.length ? rows.join("")
      : `<p class="screen-sub">No notes recorded for this house.</p>`;
    return `<h2>House notes</h2>${body}${addControlsHTML(house, res)}
      <p class="notes-msg" id="fieldsMsg" role="status"></p>`;
  }
```

Also add, immediately after these helpers, a stub that Task 4 fills in (so this task is runnable on its own):

```js
  // Editors land in the next commit; render nothing until then.
  function fieldEditorHTML(target, key, label, currentText) { return ""; }
  function addControlsHTML(house, res) { return ""; }
```

And above `renderNotesScreen`, next to the existing `let notesEditorOpen = false;`, add the module state:

```js
  let lastNotesRes = null;   // last getHouseNotes result for the open house
  let fieldEditor = null;    // { mode: 'edit'|'add-item'|'add-info', target?, key? }
```

- [ ] **Step 3: Rework `renderNotesScreen` + refresh**

Replace `renderNotesScreen` (~lines 1980–2013) and `refreshGenNotes` (~lines 2073–2085) with:

```js
  async function renderNotesScreen() {
    const body = document.getElementById("notesBody");
    const house = notesHouseFromHash();
    if (!house) {
      body.innerHTML = `
        <input type="search" id="notesSearch" placeholder="Type the house name…" aria-label="Search houses">
        <div id="notesPickList">${notesPickListHTML("")}</div>`;
      return;
    }
    notesEditorOpen = false;
    fieldEditor = null;
    lastNotesRes = null;
    body.innerHTML = `
      <div class="screen-head" style="margin-top:0"><h1 style="font-size:1rem">${escHtml(house.name)}</h1></div>
      <div class="notes-sec" id="houseFieldsSec">${houseFieldsHTML(house, null)}</div>
      <div class="notes-sec" id="genNotesSec"><h2>General notes</h2>
        <p class="screen-sub">Loading…</p></div>`;
    if (!window.cloud) {
      document.getElementById("genNotesSec").innerHTML =
        `<h2>General notes</h2><p class="screen-sub">Cloud isn't loaded — general notes need a connection.</p>`;
      return;
    }
    await refreshNotesData();
  }

  // (Re)fetch and repaint BOTH notes sections. On any failure we do NOT
  // re-render, so a tech's typed text is never wiped.
  async function refreshNotesData() {
    const house = notesHouseFromHash();
    if (!house || !window.cloud) return;
    const res = await window.cloud.getHouseNotes(house.name);
    // The hash may have changed while we awaited; don't paint a stale house.
    if (notesHouseFromHash()?.name !== house.name) return;
    const fields = document.getElementById("houseFieldsSec");
    const gen = document.getElementById("genNotesSec");
    if (!fields || !gen) return;
    if (res.error || res.notReady) {
      const msg = document.getElementById("notesMsg") || document.getElementById("fieldsMsg");
      if (msg) {
        msg.textContent = res.notReady
          ? "Note suggestions aren't set up in the database yet (migration 0006/0008)."
          : "Couldn't load notes — " + res.error;
        msg.className = "notes-msg error";
      }
      return;
    }
    lastNotesRes = res;
    // Look the house up FRESH — approve/save refreshes ALL_HOUSES behind us.
    const fresh = notesHouseFromHash();
    fields.innerHTML = houseFieldsHTML(fresh, res);
    gen.innerHTML = genNotesHTML(fresh, res);
  }

  // Repaint only the fields section from cached data (open/close editors).
  function repaintFields() {
    const house = notesHouseFromHash();
    const sec = document.getElementById("houseFieldsSec");
    if (house && sec) sec.innerHTML = houseFieldsHTML(house, lastNotesRes);
  }
```

- [ ] **Step 4: Unify `genNotesHTML` onto the shared blocks**

Replace `genNotesHTML` (~lines 2023–2049) with:

```js
  function genNotesHTML(house, res) {
    const isAdmin = window.cloud && window.cloud.role === "supervisor";
    const noteHtml = res.generalNotes
      ? `<p class="gen-notes">${escHtml(res.generalNotes)}</p>`
      : `<p class="gen-notes empty">No general notes yet.</p>`;
    const sugs = res.suggestions.filter(s => s.target === "general")
      .map(s => sugBlockHTML(s)).join("");
    const dens = (res.denials || []).filter(d => d.target === "general")
      .map(denialBlockHTML).join("");
    const editor = notesEditorOpen ? `
      <textarea id="notesEditor" aria-label="${isAdmin ? "Edit general notes" : "Suggest an update to the general notes"}">${escHtml(res.generalNotes)}</textarea>
      <div class="notes-actions">
        <button type="button" class="btn-primary" data-notes-submit="${escAttr(house.name)}">${isAdmin ? "Save notes" : "Submit suggestion"}</button>
        <button type="button" data-notes-cancel>Cancel</button>
      </div>` : `
      <div class="notes-actions">
        <button type="button" data-notes-edit>${isAdmin ? "✎ Edit notes" : "✎ Suggest an update"}</button>
      </div>`;
    return `<h2>General notes</h2>${noteHtml}${sugs}${dens}${editor}
      <p class="notes-msg" id="notesMsg" role="status"></p>`;
  }
```

- [ ] **Step 5: Shared review-action handler + rewire the notesBody listener**

Replace `sugAction` (~lines 2111–2120) with the version below, and add `sugClickActions` + `refreshPendingBadge` next to it:

```js
  async function sugAction(fn, okText, btn, refresh) {
    const msg = document.getElementById("notesMsg");
    btn.disabled = true;
    try {
      const res = await fn();
      if (res.error) {
        if (msg) { msg.textContent = res.error; msg.className = "notes-msg error"; }
        else toast("Couldn't do that — " + res.error, "error");
        return;
      }
      toast("✓ " + okText, "ok");
      await (refresh || refreshNotesData)();
      refreshPendingBadge();
    } finally { btn.disabled = false; }
  }

  // Approve / deny(+reason) / withdraw / dismiss-denial, wherever suggestion
  // blocks render (notes screen, checklist, pending queue). Returns true if
  // the click was one of ours.
  async function sugClickActions(e, refresh) {
    const openDeny = e.target.closest("[data-sug-deny]");
    if (openDeny) {
      const f = document.querySelector(`[data-deny-form="${CSS.escape(openDeny.dataset.sugDeny)}"]`);
      if (f) { f.hidden = false; f.querySelector("input").focus(); }
      return true;
    }
    const cancelDeny = e.target.closest("[data-deny-cancel]");
    if (cancelDeny) {
      const id = cancelDeny.dataset.denyCancel;
      const f = document.querySelector(`[data-deny-form="${CSS.escape(id)}"]`);
      if (f) f.hidden = true;
      document.querySelector(`[data-sug-deny="${CSS.escape(id)}"]`)?.focus();
      return true;
    }
    const confirmDeny = e.target.closest("[data-deny-confirm]");
    if (confirmDeny) {
      const id = confirmDeny.dataset.denyConfirm;
      const reason = (document.querySelector(`[data-deny-reason="${CSS.escape(id)}"]`)?.value || "").trim();
      await sugAction(() => window.cloud.denySuggestion(id, reason),
        "Denied — the tech will see this.", confirmDeny, refresh);
      return true;
    }
    const approve = e.target.closest("[data-sug-approve]");
    if (approve) {
      await sugAction(() => window.cloud.approveSuggestion(approve.dataset.sugApprove),
        "Approved — the note is updated.", approve, refresh);
      return true;
    }
    const withdraw = e.target.closest("[data-sug-withdraw]");
    if (withdraw) {
      await sugAction(() => window.cloud.withdrawSuggestion(withdraw.dataset.sugWithdraw),
        "Suggestion withdrawn.", withdraw, refresh);
      return true;
    }
    const dismiss = e.target.closest("[data-denied-dismiss]");
    if (dismiss) {
      await sugAction(() => window.cloud.markDenialSeen(dismiss.dataset.deniedDismiss),
        "Cleared.", dismiss, refresh);
      return true;
    }
    return false;
  }

  // Supervisor home-screen badge. Harmless no-op for techs / signed-out.
  async function refreshPendingBadge() {
    if (!window.cloud || window.cloud.role !== "supervisor" || !window.cloud.pendingCount) return;
    const r = await window.cloud.pendingCount();
    if (!r.error && window.applyPendingCount) window.applyPendingCount(r.count);
  }
```

Then in the `notesBody` click listener (~lines 2056–2069): keep the `data-notes-house`, `data-notes-edit` / `data-notes-cancel` / `data-notes-submit` branches, changing their two `refreshGenNotes()` calls to `refreshNotesData()` (one fetch repaints both sections — simpler than keeping a general-only path). Replace the `data-sug-approve` / `data-sug-dismiss` / `data-sug-withdraw` branches with one line at the end:

```js
    if (await sugClickActions(e, refreshNotesData)) return;
```

Also in `submitNotes` (~line 2107): change `await refreshGenNotes();` to `await refreshNotesData();` — and delete the now-unused `refreshGenNotes` if Step 3 hasn't already replaced it.

- [ ] **Step 6: Parse + render sanity check**

Open `route-checklist/index.html` from disk with the console open. Expected: no syntax errors. (Behavioral checks come in Task 7 on the live site.)

- [ ] **Step 7: Commit**

```bash
git add route-checklist/index.html
git commit -m "feat: notes screen — field rows with pending suggestions, denial notices, approve/deny-with-reason"
```

---

### Task 4: Notes screen — editors (suggest / save / add / remove)

**Files:**
- Modify: `route-checklist/index.html` — replace the Task 3 stubs `fieldEditorHTML` / `addControlsHTML`, extend the notesBody click listener.

**Interfaces:**
- Consumes: `window.cloud.saveHouseField / suggestChange` (Task 2), Task 3's `fieldEditor`, `repaintFields()`, `refreshNotesData()`, `refreshPendingBadge()`; existing `loadName()`, `toast`, `NOTE_KEY_LABELS`.
- Produces (Task 5 reuses these exact functions): `fieldEditorHTML(target, key, label, currentText)`, `fieldFormClick(e, houseName, refresh, closeEditor)` → `Promise<boolean>`. Form internals are class-addressed (`.field-form`, `.field-text`, `.field-key`, `.field-label`, `[data-field-msg]`) — never id-addressed, because the checklist and notes screen both live in the DOM at once.

- [ ] **Step 1: Replace the two stubs**

Replace the Task 3 stub bodies of `fieldEditorHTML` and `addControlsHTML` with:

```js
  // Inline editor for ONE field. Also used by the checklist (Task 5), so all
  // inner elements are class-addressed, never id-addressed.
  function fieldEditorHTML(target, key, label, currentText) {
    const isAdmin = window.cloud && window.cloud.role === "supervisor";
    return `<div class="field-form">
      <textarea class="field-text" aria-label="${isAdmin ? "Edit" : "Suggest new text for"} the ${escAttr(label)} note">${escHtml(currentText || "")}</textarea>
      <div class="notes-actions">
        <button type="button" class="btn-primary" data-field-submit data-target="${escAttr(target)}" data-key="${escAttr(key)}">${isAdmin ? "Save" : "Submit suggestion"}</button>
        ${currentText ? `<button type="button" class="btn-danger" data-field-remove data-target="${escAttr(target)}" data-key="${escAttr(key)}">${isAdmin ? "Remove note" : "Suggest removal"}</button>` : ""}
        <button type="button" data-field-cancel>Cancel</button>
      </div>
      <p class="notes-msg" data-field-msg role="status"></p>
    </div>`;
  }

  // "+ Add item note" / "+ Add house info" (notes screen only).
  function addControlsHTML(house, res) {
    if (!window.cloud || !res || res.error || res.notReady) return "";
    const isAdmin = window.cloud.role === "supervisor";
    if (fieldEditor && fieldEditor.mode === "add-item") {
      const free = Object.keys(NOTE_KEY_LABELS).filter(k => !((house.notes || {})[k]));
      return `<div class="field-form">
        <label>Which item is this note for?</label>
        <select class="field-key" aria-label="Which item is this note for?">
          ${free.map(k => `<option value="${escAttr(k)}">${escHtml(NOTE_KEY_LABELS[k])}</option>`).join("")}
        </select>
        <textarea class="field-text" aria-label="Note text"></textarea>
        <div class="notes-actions">
          <button type="button" class="btn-primary" data-field-submit data-target="item">${isAdmin ? "Save" : "Submit suggestion"}</button>
          <button type="button" data-field-cancel>Cancel</button>
        </div>
        <p class="notes-msg" data-field-msg role="status"></p>
      </div>`;
    }
    if (fieldEditor && fieldEditor.mode === "add-info") {
      return `<div class="field-form">
        <label>Label (e.g. "Chest freezer")</label>
        <input type="text" class="field-label" aria-label="Label for the new house info">
        <label>Detail (e.g. "Garage, north wall")</label>
        <textarea class="field-text" aria-label="Detail for the new house info"></textarea>
        <div class="notes-actions">
          <button type="button" class="btn-primary" data-field-submit data-target="info">${isAdmin ? "Save" : "Submit suggestion"}</button>
          <button type="button" data-field-cancel>Cancel</button>
        </div>
        <p class="notes-msg" data-field-msg role="status"></p>
      </div>`;
    }
    const freeCount = Object.keys(NOTE_KEY_LABELS).filter(k => !((house.notes || {})[k])).length;
    return `<div class="notes-actions">
      ${freeCount ? `<button type="button" data-add-item>+ Add item note</button>` : ""}
      <button type="button" data-add-info>+ Add house info</button>
    </div>`;
  }
```

- [ ] **Step 2: Shared submit/cancel handler**

Add next to `sugClickActions`:

```js
  // Submit / remove / cancel inside any .field-form. Supervisor writes
  // directly; tech files a suggestion. Returns true if the click was ours.
  // On failure the form (and its typed text) stays; error shows inline.
  async function fieldFormClick(e, houseName, refresh, closeEditor) {
    const cancel = e.target.closest("[data-field-cancel]");
    if (cancel) { closeEditor(cancel); return true; }
    const submit = e.target.closest("[data-field-submit]");
    const remove = e.target.closest("[data-field-remove]");
    const btn = submit || remove;
    if (!btn) return false;
    const form = btn.closest(".field-form");
    const msg = form.querySelector("[data-field-msg]");
    const isAdmin = window.cloud && window.cloud.role === "supervisor";
    const target = btn.dataset.target;
    const key = btn.dataset.key !== undefined ? btn.dataset.key
      : (form.querySelector(".field-key")?.value
         || form.querySelector(".field-label")?.value || "").trim();
    const text = remove ? "" : (form.querySelector(".field-text")?.value || "");
    if (!key) { msg.textContent = "Give it a label first."; msg.className = "notes-msg error"; return true; }
    if (!remove && !text.trim()) { msg.textContent = "Type the note text first."; msg.className = "notes-msg error"; return true; }
    if (remove && isAdmin && !confirm("Remove this note for everyone?")) return true;
    btn.disabled = true;
    msg.textContent = isAdmin ? "Saving…" : "Submitting…"; msg.className = "notes-msg";
    try {
      const payload = { target, noteKey: key, action: remove ? "delete" : "set", text };
      const res = isAdmin
        ? await window.cloud.saveHouseField(houseName, payload)
        : await window.cloud.suggestChange(houseName, payload, loadName());
      if (res.error) {
        msg.textContent = "Couldn't save — " + res.error; msg.className = "notes-msg error";
        return true;
      }
      toast(isAdmin ? "✓ Saved." : "✓ Suggestion submitted for approval.", "ok");
      closeEditor(null);
      await refresh();
      refreshPendingBadge();
    } finally { btn.disabled = false; }
    return true;
  }
```

- [ ] **Step 3: Wire the notes screen**

In the `notesBody` click listener, before the `sugClickActions` line, add:

```js
    const house = notesHouseFromHash();
    if (house) {
      const fe = e.target.closest("[data-field-edit]");
      if (fe) {
        fieldEditor = { mode: "edit", target: fe.dataset.target, key: fe.dataset.key };
        repaintFields();
        document.querySelector("#houseFieldsSec .field-text")?.focus();
        return;
      }
      if (e.target.closest("[data-add-item]")) {
        fieldEditor = { mode: "add-item" };
        repaintFields();
        document.querySelector("#houseFieldsSec .field-key")?.focus();
        return;
      }
      if (e.target.closest("[data-add-info]")) {
        fieldEditor = { mode: "add-info" };
        repaintFields();
        document.querySelector("#houseFieldsSec .field-label")?.focus();
        return;
      }
      if (await fieldFormClick(e, house.name, refreshNotesData, () => {
        const was = fieldEditor;
        fieldEditor = null;
        repaintFields();
        if (was && was.mode === "edit")
          document.querySelector(`#houseFieldsSec [data-field-edit][data-target="${CSS.escape(was.target)}"][data-key="${CSS.escape(was.key)}"]`)?.focus();
      })) return;
    }
```

(Order matters: these run before `sugClickActions`, and the existing `data-notes-*` branches for the general note stay untouched above them.)

- [ ] **Step 4: Parse check**

Open `route-checklist/index.html` from disk, console open. Expected: no syntax errors.

- [ ] **Step 5: Commit**

```bash
git add route-checklist/index.html
git commit -m "feat: notes screen — suggest/edit/add/remove editors for item notes + info pairs"
```

---

### Task 5: Checklist inline — ✎ on 📍 notes, add-note, pending under the item

**Files:**
- Modify: `route-checklist/index.html` — `build()` house-note block (~lines 1219–1226), `rebuild()` (~line 1775), new `#app` click listener + note-suggestion painter.

**Interfaces:**
- Consumes: `NOTE_RULES`, `NOTE_KEY_LABELS`, `currentHouse()`, `window.cloud.getHouseNotes`, Task 3's `sugBlockHTML` / `denialBlockHTML` / `sugClickActions`, Task 4's `fieldEditorHTML` / `fieldFormClick`.
- Produces: `loadChecklistNotes()` (fetch + repaint slots; safe to call anytime), `paintHouseNoteSugs()` (repaint slots from cache), module state `CHECKLIST_NOTES`.

- [ ] **Step 1: Rework the house-note block in `build()`**

Replace lines ~1219–1226 (from `// House tailoring:` through the `if (texts.length) houseNote = ...` line) with:

```js
          // House tailoring: skip items for missing equipment; render one 📍
          // line per note key, each with its own ✎ and a slot that
          // paintHouseNoteSugs() later fills with pending/denied blocks.
          let houseNote = "";
          if (house) {
            const rules = NOTE_RULES.filter(r => r.match.test(label));
            if (rules.some(r => r.flag && house.equipment && house.equipment[r.flag] === false)) return;
            rules.filter(r => r.note).forEach(r => {
              const key = r.note;
              const text = (house.notes && house.notes[key]) || "";
              const keyLabel = (NOTE_KEY_LABELS[key] || key).replace(/"/g, "&quot;");
              if (text) {
                houseNote += `<div class="house-note" data-hn-key="${key}">📍 ${text.replace(/</g, "&lt;")}
                  ${window.cloud ? `<button type="button" class="hn-edit" data-hn-edit="${key}" aria-label="Edit or suggest a fix to the ${keyLabel} note"><span aria-hidden="true">✎</span></button>` : ""}
                  <span data-hn-slot="${key}"></span></div>`;
              } else if (window.cloud) {
                houseNote += `<div class="house-note hn-empty" data-hn-key="${key}">
                  <button type="button" class="hn-add" data-hn-edit="${key}">+ add note (${keyLabel})</button>
                  <span data-hn-slot="${key}"></span></div>`;
              }
            });
          }
```

(Display change to be aware of: an item matching several note rules used to join its notes on one 📍 line; it now gets one line per key. No current item matches more than one rule.)

- [ ] **Step 2: The slot painter + fetch**

Add after `rebuild()`'s definition (~line 1775):

```js
  // Pending suggestions / denial notices for the checklist's 📍 notes.
  // build() renders empty <span data-hn-slot> slots synchronously; this pair
  // fetches the data and fills them in place (no full rebuild → no lost state).
  let CHECKLIST_NOTES = null;   // getHouseNotes result for the current house
  function paintHouseNoteSugs() {
    document.querySelectorAll("#app [data-hn-slot]").forEach(slot => {
      const key = slot.dataset.hnSlot;
      if (!CHECKLIST_NOTES) { slot.innerHTML = ""; return; }
      const sugs = CHECKLIST_NOTES.suggestions.filter(s => s.target === "item" && s.noteKey === key);
      const dens = (CHECKLIST_NOTES.denials || []).filter(d => d.target === "item" && d.noteKey === key);
      slot.innerHTML = sugs.map(s => sugBlockHTML(s)).join("") + dens.map(denialBlockHTML).join("");
    });
  }
  async function loadChecklistNotes() {
    CHECKLIST_NOTES = null;
    paintHouseNoteSugs();   // clear stale blocks immediately
    const house = currentHouse();
    if (!house || !window.cloud || !window.cloud.getHouseNotes) return;
    const res = await window.cloud.getHouseNotes(house.name);
    if (currentHouse()?.name !== house.name) return;   // house changed mid-await
    if (res.error || res.notReady) return;   // inline blocks are an enhancement;
                                             // the notes screen reports errors
    CHECKLIST_NOTES = res;
    paintHouseNoteSugs();
  }
```

Then change `rebuild()` itself from
`function rebuild() { build(); hydrate(); refreshDueInfo(); }` to:

```js
  function rebuild() { build(); hydrate(); refreshDueInfo(); loadChecklistNotes(); }
```

(`rebuild()` runs on house pick, cloud house load, and preview toggles — each is exactly when the suggestion blocks could have changed. It is NOT called per checkbox tap, so this adds no per-interaction queries.)

- [ ] **Step 3: The `#app` click listener**

Add after the painter functions:

```js
  // Checklist-inline note editing. Separate listener; the selectors don't
  // collide with the main document-level checklist handler.
  document.getElementById("app").addEventListener("click", async e => {
    const edit = e.target.closest("[data-hn-edit]");
    if (edit) {
      const key = edit.dataset.hnEdit;
      const house = currentHouse();
      if (!house || !window.cloud) return;
      const slot = edit.closest("[data-hn-key]").querySelector("[data-hn-slot]");
      slot.innerHTML = fieldEditorHTML("item", key, NOTE_KEY_LABELS[key] || key,
        (house.notes && house.notes[key]) || "");
      slot.querySelector(".field-text")?.focus();
      return;
    }
    const house = currentHouse();
    if (house && await fieldFormClick(e, house.name, loadChecklistNotes, (btn) => {
      const wrap = btn ? btn.closest("[data-hn-key]") : null;
      paintHouseNoteSugs();   // restores the slot's suggestion blocks
      if (wrap) wrap.querySelector("[data-hn-edit]")?.focus();
    })) return;
    if (window.cloud && await sugClickActions(e, loadChecklistNotes)) return;
  });
```

(A supervisor's direct Save also triggers `loadHouses()` → `applyHouses` → `rebuild()`, which repaints the official 📍 text itself.)

- [ ] **Step 4: Parse check**

Open `route-checklist/index.html` from disk, console open. Expected: no syntax errors.

- [ ] **Step 5: Commit**

```bash
git add route-checklist/index.html
git commit -m "feat: checklist inline — suggest/edit house notes at the item, pending shown under the note"
```

---

### Task 6: Pending changes queue + home badge

**Files:**
- Modify: `route-checklist/index.html` — screens HTML (~line 694), screen-hiding CSS (~line 481), home screen (~line 673), hash router (~lines 2126–2140), new render function + listener.

**Interfaces:**
- Consumes: `window.cloud.listPendingSuggestions / pendingCount` (Task 2), Task 3's `sugBlockHTML` / `sugClickActions` / `refreshPendingBadge`, `NOTE_KEY_LABELS`, `escHtml`.
- Produces: `#pending` hash route, `renderPendingScreen()`, `window.applyPendingCount(n)` (cloud.js calls it after a supervisor signs in).

- [ ] **Step 1: Screen HTML + CSS gate + home button**

After the `routesScreen` div (~line 700), add:

```html
<div id="pendingScreen" class="screen" aria-label="Pending changes">
  <div class="screen-head">
    <button type="button" class="menu-btn" data-nav-home>← Home</button>
    <h1>Pending changes</h1>
  </div>
  <div id="pendingBody"></div>
</div>
```

Extend the screen-hiding CSS (~line 481–484) with one more line in the same pattern:

```css
  body:not([data-screen="pending"])  #pendingScreen { display: none; }
```

On the home screen, after the `homeRoutes` button (~line 674), add:

```html
  <button type="button" class="home-btn admin-only" id="homePending">⏳ Pending changes<span class="pending-count" id="pendingCountBadge"></span>
    <small>Review techs' suggested note fixes</small></button>
```

And with the other home-button CSS, add:

```css
  .pending-count { font-weight: 700; }
```

- [ ] **Step 2: Router + navigation**

In `currentScreenFromHash()` (~line 2126), add before the `return "home";`:

```js
    if (h.startsWith("#pending")) return "pending";
```

In `showScreen()` (~line 2134), with the other screen renders, add:

```js
    if (scr === "pending") renderPendingScreen();
```

Next to the `homeRoutes` click handler (~line 2164), add:

```js
  document.getElementById("homePending").addEventListener("click", () => {
    location.hash = "#pending";
  });
```

- [ ] **Step 3: Render + badge + listener**

Add near `renderRoutesScreen` (~line 2218):

```js
  // The supervisor's cross-house review queue. Techs can reach the hash but
  // see no action buttons (sugBlockHTML gates them) — and RLS is what
  // actually refuses a tech's approve/deny.
  function pendingRowLabel(s) {
    if (s.target === "general") return "General notes";
    if (s.target === "item") return NOTE_KEY_LABELS[s.noteKey] || s.noteKey;
    return "House info: " + s.noteKey;
  }

  async function renderPendingScreen() {
    const body = document.getElementById("pendingBody");
    if (!window.cloud || !window.cloud.listPendingSuggestions) {
      body.innerHTML = `<p class="screen-sub">Cloud isn't loaded — pending changes need a connection.</p>`;
      return;
    }
    body.innerHTML = `<p class="screen-sub">Loading…</p>`;
    const res = await window.cloud.listPendingSuggestions();
    if (currentScreenFromHash() !== "pending") return;
    if (res.error) {
      body.innerHTML = `<p class="screen-sub">${res.notReady
        ? "Pending changes aren't set up in the database yet (migration 0008)."
        : "Couldn't load — " + escHtml(res.error)}</p>`;
      return;
    }
    if (window.applyPendingCount) window.applyPendingCount(res.suggestions.length);
    if (!res.suggestions.length) {
      body.innerHTML = `<p class="screen-sub">Nothing pending — all caught up.</p>`;
      return;
    }
    const byHouse = new Map();
    res.suggestions.forEach(s => {
      if (!byHouse.has(s.houseName)) byHouse.set(s.houseName, []);
      byHouse.get(s.houseName).push(s);
    });
    body.innerHTML = [...byHouse.entries()].map(([houseName, sugs]) => `
      <div class="notes-sec"><h2>${escHtml(houseName)}</h2>
        ${sugs.map(s => `<div class="notes-item"><b>${escHtml(pendingRowLabel(s))}</b>
          ${sugBlockHTML(s, { current: s.current })}</div>`).join("")}
      </div>`).join("");
  }

  window.applyPendingCount = function (n) {
    const el = document.getElementById("pendingCountBadge");
    if (el) el.textContent = n > 0 ? ` (${n})` : "";
  };

  document.getElementById("pendingBody").addEventListener("click", async e => {
    if (await sugClickActions(e, renderPendingScreen)) return;
  });
```

- [ ] **Step 4: Parse check**

Open `route-checklist/index.html` from disk, console open. Expected: no syntax errors; `#pendingScreen` exists in the DOM (Elements tab).

- [ ] **Step 5: Commit**

```bash
git add route-checklist/index.html
git commit -m "feat: supervisor Pending changes queue with home-screen count badge"
```

---

### Task 7: Ship — cache bump, handoff notes, push, full verification

**Files:**
- Modify: `route-checklist/sw.js:7` (cache version), `route-checklist/HANDOFF.md`

**Interfaces:**
- Consumes: everything above; the live site `https://tweet-delta.github.io/mtx-sandbox/route-checklist/index.html#home`; one tech account and one supervisor account (owner has both).

- [ ] **Step 1: Bump the service-worker cache**

In `route-checklist/sw.js` line 7: `const CACHE = "route-checklist-v7";` → `"route-checklist-v8"` (index.html and cloud.js both changed; installed phones must fetch the new shell).

- [ ] **Step 2: Update HANDOFF.md**

Add a new dated "STATE AS OF" section at the top of the state sections, summarizing: migration 0008 (columns + replaced approve RPC + deny RPC + author-seen guard trigger), the new `window.cloud` functions (`suggestChange`, `denySuggestion`, `markDenialSeen`, `saveHouseField`, `listPendingSuggestions`, `pendingCount`; `dismissSuggestion` removed), the tech suggest flows (checklist ✎/+ and notes-screen field rows, add-item/add-info), supervisor direct save + inline approve/deny-with-reason + `#pending` queue with badge, and the SW bump to v8. Note the known limitation: `house-data.js` remains a stale offline fallback.

- [ ] **Step 3: Commit and push**

```bash
git add route-checklist/sw.js route-checklist/HANDOFF.md
git commit -m "chore: SW cache v8 + handoff notes for house-note suggestions"
git push
```

(Pushing this branch deploys GitHub Pages — this is the moment the feature goes live on the demo site.)

- [ ] **Step 4: Full end-to-end verification (live site, both roles)**

Wait ~2 minutes for Pages to deploy, then drive every flow. **As a tech:**
1. Open a house's checklist → an existing 📍 note shows ✎; tap it, change the text, Submit suggestion → ⏳ pending block appears under the note with your name and a Withdraw button.
2. On an item whose note is blank for this house → `+ add note (…)` → submit → pending block appears.
3. House Notes screen for the same house → both suggestions show under their rows; info pairs and item notes all show ✎; use "+ Add house info" to propose a new pair; on an existing note choose "Suggest removal" → "Pending removal" block.
4. Withdraw one suggestion → block disappears.
5. General notes → suggest an update (regression check for the 0006 flow).

**As a supervisor (second browser/profile):**
6. Home screen shows "⏳ Pending changes (N)" with the right N.
7. Open the queue → suggestions grouped by house, each showing proposed vs current; Approve one → toast, it leaves the queue, badge decrements; open that house → the official note text now IS the proposal (checklist 📍 and House Notes both).
8. Deny one WITH a reason → it leaves the queue.
9. On the House Notes screen: ✎ an existing note → button says Save → save → text updates instantly, no pending step. "Remove note" on one → confirm dialog → gone. Approve/deny also work inline from the house view.
10. General-notes suggestion from step 5: approve it inline (regression).

**As the tech again:**
11. The denied note shows "❌ Denied — <reason>" in both the checklist and House Notes → Dismiss → gone, and still gone after a reload.

**In Supabase (dashboard SQL editor, read-only):**
12. `select target, note_key, action, status, deny_reason, seen_by_author from house_note_suggestions order by created_at desc limit 10;` — statuses/reasons match what you did; approved/denied rows still exist (audit trail).
13. `select name, notes, info from houses where name = '<the house you used>';` — only approved + supervisor-saved changes are present.

**Negative check:** confirm the tech UI shows no Approve/Deny buttons anywhere (checklist blocks, House Notes, and by navigating directly to `#pending`). The database-side guarantee (a tech calling the RPCs directly gets `Only a supervisor can…`) comes from the role checks written into both RPCs in Task 1 — the supabase client isn't exposed on `window`, so there's no console route to drive it, and the UI check plus the RPC source is the verification.

Every step must actually pass before claiming done. If any fails, fix it (root cause, no bandaids), re-push, re-verify.

- [ ] **Step 5: Record verification**

Note in HANDOFF.md's new section that the checklist above was driven on the live site with both roles on <date>, and commit:

```bash
git add route-checklist/HANDOFF.md
git commit -m "docs: record live verification of house-note suggestions"
git push
```
