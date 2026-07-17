// cloud.js â€” the "cloud layer": login + loading data from Supabase.
//
// Runs as a MODULE so it can import the official Supabase client from a CDN.
// It talks to the checklist app (index.html) through the login-gate elements
// and by calling window.applyHouses(...) with the roster it loads.

import { createClient } from "https://esm.sh/@supabase/supabase-js@2";

const supabase = createClient(window.SUPABASE_URL, window.SUPABASE_PUBLISHABLE_KEY);
window.supabase = supabase; // later phases (saving visits, photos) reuse this

// --- Login-gate + account elements (defined in index.html) ---
const gate       = document.getElementById("authGate");
const form       = document.getElementById("loginForm");
const emailInput = document.getElementById("loginEmail");
const pwInput    = document.getElementById("loginPassword");
const magicBtn   = document.getElementById("magicLinkBtn");
const authMsg    = document.getElementById("authMsg");
const whoami     = document.getElementById("whoami");
const newPwInput = document.getElementById("newPassword");
const setPwBtn   = document.getElementById("setPasswordBtn");
const pwMsg      = document.getElementById("pwMsg");

// Small helper so the two status lines (login + set-password) share one path.
function setMsg(el, text, kind) {
  const base = el === authMsg ? "auth-msg" : "pw-msg";
  el.textContent = text;
  el.className = base + (kind ? " " + kind : "");
}

// Show (locked) or hide the sign-in screen. Default in the HTML is SHOWN, so if
// anything here fails the app stays locked rather than exposed ("fail closed").
function showGate(locked) {
  gate.hidden = !locked;
  document.body.classList.toggle("locked", locked);
}

// Pull the roster from the database and hand it to the checklist app. On any
// error we keep the local fallback houses, so the app still works.
// We keep the DB ids here (name â†’ row) so saveVisit/lastDone below can turn
// a house NAME (all the app knows) into the house_id the database needs.
const housesByName = new Map();
async function loadHouses() {
  let { data, error } = await supabase
    .from("houses")
    .select("id, name, equipment, notes, info, general_notes, route_id")
    .eq("active", true)
    .order("name");
  // Before migration 0007, route_id doesn't exist â€” load without it.
  if (error && isMissingColumn(error)) {
    ({ data, error } = await supabase
      .from("houses")
      .select("id, name, equipment, notes, info, general_notes")
      .eq("active", true)
      .order("name"));
  }
  if (error) { console.error("Could not load houses:", error.message); return; }
  housesByName.clear();
  data.forEach(h => housesByName.set(h.name.trim().toLowerCase(), h));
  if (window.applyHouses) window.applyHouses(data);
}

// ---- Who am I? (role gates the admin controls; RLS is the real enforcement) ----
async function loadRole() {
  window.cloud.role = null;
  const { data: { user } } = await supabase.auth.getUser();
  if (!user) return;
  const { data, error } = await supabase
    .from("profiles").select("role").eq("id", user.id).maybeSingle();
  if (error) { console.error("Could not load role:", error.message); return; }
  window.cloud.role = data?.role || "tech";
  document.body.classList.toggle("is-admin", window.cloud.role === "supervisor");
  if (window.applyRole) window.applyRole(window.cloud.role);
  if (window.cloud.role === "supervisor") {
    pendingCount().then(r => {
      if (!r.error && window.applyPendingCount) window.applyPendingCount(r.count);
    });
    refreshReviewBadge();
  }
}

// Which houses are on the signed-in tech's route(s)? Hands the app a Set of
// lowercase house names via window.applyMyHouses. null = "no route info" â€”
// the app then shows every house (signed out, migration 0007 not applied,
// query failed, or a supervisor, whose pickers are deliberately unscoped).
// Must run AFTER loadHouses (reads housesByName) and loadRole (reads role).
async function loadMyRoute() {
  const apply = s => { if (window.applyMyHouses) window.applyMyHouses(s); };
  const { data: { user } } = await supabase.auth.getUser();
  if (!user || window.cloud.role === "supervisor") { apply(null); return; }
  const { data, error } = await supabase
    .from("routes").select("id").eq("tech_id", user.id);
  if (error) {
    if (!isMissingTable(error)) console.error("Could not load routes:", error.message);
    apply(null); return;
  }
  const myRouteIds = new Set(data.map(r => r.id));
  const mine = new Set();
  housesByName.forEach((h, key) => {
    if (h.route_id && myRouteIds.has(h.route_id)) mine.add(key);
  });
  apply(mine);   // empty Set is meaningful: "route info exists, none assigned"
}

// ---- My Profile (self-service name/phone editor) ----

// The signed-in user's own name/phone/role + their login email. Email comes
// from auth.getUser() (profiles has no email column). Returns { error } if
// not signed in or the query fails — the UI shows that message rather than
// a blank form.
async function getMyProfile() {
  const { data: { user } } = await supabase.auth.getUser();
  if (!user) return { error: "Not signed in." };
  let { data, error } = await supabase
    .from("profiles").select("full_name, phone, role").eq("id", user.id).maybeSingle();
  if (error && isMissingColumn(error)) {
    ({ data, error } = await supabase
      .from("profiles").select("full_name, role").eq("id", user.id).maybeSingle());
  }
  if (error) return { error: error.message };
  return {
    fullName: data?.full_name || "",
    phone: data?.phone || "",
    role: data?.role || "tech",
    email: user.email || "",
  };
}

// Save the signed-in user's OWN name/phone. Never sends role — role changes
// stay a deliberate dashboard action (guard_profile_role trigger blocks a
// non-supervisor from changing it anyway).
async function saveMyProfile({ fullName, phone }) {
  const { data: { user } } = await supabase.auth.getUser();
  if (!user) return { error: "Not signed in." };
  let { error } = await supabase
    .from("profiles")
    .update({ full_name: fullName, phone })
    .eq("id", user.id);
  if (error && isMissingColumn(error)) {
    ({ error } = await supabase
      .from("profiles")
      .update({ full_name: fullName })
      .eq("id", user.id));
    if (!error) return { error: null, degraded: true };
  }
  return { error: error ? error.message : null };
}

// ---- Team roster (supervisor-only; RLS is the real gate) ----

// Every profile the caller may see. For a supervisor, RLS returns all rows;
// for a tech it returns only their own (the #team renderer blocks techs first
// anyway). profiles has no email column, so only the caller's OWN email is
// known here (auth.getUser()); other rows' email is a Slice-2 concern.
// Returns { people:[{id,fullName,phone,role,isMe}], myId, myEmail } or { error }.
async function listAllProfiles() {
  const { data: { user } } = await supabase.auth.getUser();
  if (!user) return { error: "Not signed in." };
  let { data, error } = await supabase
    .from("profiles").select("id, full_name, phone, role").order("full_name");
  if (error && isMissingColumn(error)) {
    ({ data, error } = await supabase
      .from("profiles").select("id, full_name, role").order("full_name"));
  }
  if (error) return { error: error.message };
  const people = (data || []).map(p => ({
    id: p.id,
    fullName: p.full_name || "",
    phone: p.phone || "",
    role: p.role || "tech",
    isMe: p.id === user.id,
  }));
  return { people, myId: user.id, myEmail: user.email || "" };
}

// Supervisor edits ANOTHER person's name/phone. Never sends role (that goes
// through setProfileRole). RLS refuses this for a non-supervisor. Name-only
// fallback if the phone column is missing (matches saveMyProfile).
async function saveProfileAsSupervisor(id, { fullName, phone }) {
  let { error } = await supabase
    .from("profiles").update({ full_name: fullName, phone }).eq("id", id);
  if (error && isMissingColumn(error)) {
    ({ error } = await supabase
      .from("profiles").update({ full_name: fullName }).eq("id", id));
    if (!error) return { error: null, degraded: true };
  }
  return { error: error ? error.message : null };
}

// The higher-stakes role change, kept its own function so call sites are
// unmistakable. Sends only { role }. The DB guards (guard_profile_role +
// guard_last_supervisor) may refuse — their message is returned verbatim so
// the UI can show exactly why.
async function setProfileRole(id, role) {
  const { error } = await supabase
    .from("profiles").update({ role }).eq("id", id);
  return { error: error ? error.message : null };
}

// ---- Visit history (the app calls these via window.cloud) ----

// The client's CURRENT LOCAL date as YYYY-MM-DD. NOT toISOString(), which is
// UTC — an evening save in a US timezone (this app's techs are in Minnesota,
// UTC−5/−6) would otherwise stamp tomorrow's date. Must match the calendar
// grid's day math in index.html (getFullYear/getMonth/getDate), or the auto
// entry lands on a different day than the cell that shows it.
function localToday() {
  const d = new Date();
  return `${d.getFullYear()}-${String(d.getMonth()+1).padStart(2,"0")}-${String(d.getDate()).padStart(2,"0")}`;
}

// Stamp today's auto daily-log row for a saved visit. Best-effort: a failure
// here NEVER blocks the visit save (the diary is a record, not a gate). Uses
// the client's CURRENT local date — v.date is a user-editable field and may not
// be the actual save day, so a multi-day visit lands on each real workday.
async function stampDailyLog(visitId, houseId, items) {
  try {
    const { data: { user } } = await supabase.auth.getUser();
    if (!user) return;
    const doneKeys = (items || []).filter(it => it.done === true).map(it => it.key);
    const today = localToday();
    const { error } = await supabase.from("daily_logs").upsert({
      tech_id: user.id, log_date: today, kind: "auto",
      visit_id: visitId, house_id: houseId, note: "", done_keys: doneKeys,
    }, { onConflict: "tech_id,visit_id,log_date" });
    if (error && !isMissingTable(error)) {
      console.warn("Daily-log stamp failed (visit still saved):", error.message);
    }
  } catch (e) {
    console.warn("Daily-log stamp threw (visit still saved):", e.message);
  }
}

// Save a visit: one `visits` row + one `visit_items` row per answered item.
//   status "in_progress" â†’ the Save progress button (resume later/elsewhere).
//   status "completed"   â†’ the survey's Save & Send (the finalize).
// Passing the same `existingId` back in (the app keeps it in local state as
// cloudVisitId) makes a re-save UPDATE that visit instead of duplicating it.
async function saveVisit(v, status = "completed") {
  const house = housesByName.get((v.houseName || "").trim().toLowerCase());
  if (!house) return { error: `"${v.houseName}" isn't a house in the database.` };
  const header = {
    house_id: house.id,
    visit_date: v.date,
    status,
    counts: v.counts || {},
    survey: v.survey || {},
    completed_at: status === "completed" ? new Date().toISOString() : null,
  };
  let visitId = v.existingId || null;
  if (visitId) {
    const { error } = await supabase.from("visits").update(header).eq("id", visitId);
    if (error) return { error: error.message };
  } else {
    const { data, error } = await supabase.from("visits").insert(header).select("id").single();
    if (error) return { error: error.message };
    visitId = data.id;
  }
  const rows = (v.items || []).map(it => ({
    visit_id: visitId, item_key: it.key, done: it.done, answer: it.answer, note: it.note,
    done_on: it.doneOn || null, value: it.value || null,
  }));
  let degraded = false;
  if (rows.length) {
    // upsert: re-saving the same visit overwrites each item row, not duplicates it
    let { error } = await supabase.from("visit_items")
      .upsert(rows, { onConflict: "visit_id,item_key" });
    // If migration 0003 (done_on / value columns) hasn't been applied yet, retry
    // WITHOUT those fields so the visit still saves. The dates/temps stay in the
    // on-device buffer and will sync on a later save once the columns exist.
    if (error && isMissingColumn(error)) {
      const slim = rows.map(({ done_on, value, ...keep }) => keep);
      ({ error } = await supabase.from("visit_items")
        .upsert(slim, { onConflict: "visit_id,item_key" }));
      degraded = !error;
    }
    if (error) return { error: error.message, visitId };
  }
  await stampDailyLog(visitId, house.id, v.items);
  return { visitId, degraded };
}

// True when a query failed because a column from a not-yet-applied migration
// (done_on / value) is missing from the PostgREST schema cache.
function isMissingColumn(error) {
  return !!error && (error.code === "PGRST204" ||
    /could not find the '.*' column|schema cache/i.test(error.message || ""));
}

// True when a query failed because a table from a not-yet-applied migration
// (e.g. routes, migration 0007) isn't in the PostgREST schema cache.
function isMissingTable(error) {
  return !!error && (error.code === "PGRST205" || error.code === "42P01" ||
    /could not find the table|relation .* does not exist/i.test(error.message || ""));
}

// The signed-in tech's most recent IN-PROGRESS visit at this house, if any, in
// the app's local-state shape â€” so Save progress can be resumed on any device.
async function loadInProgress(houseName) {
  const house = housesByName.get((houseName || "").trim().toLowerCase());
  if (!house) return null;
  const { data: { user } } = await supabase.auth.getUser();
  if (!user) return null;
  const full = "id, visit_date, counts, survey, visit_items(item_key, done, answer, note, done_on, value)";
  const slim = "id, visit_date, counts, survey, visit_items(item_key, done, answer, note)";
  let { data, error } = await supabase
    .from("visits").select(full)
    .eq("house_id", house.id).eq("tech_id", user.id).eq("status", "in_progress")
    .order("started_at", { ascending: false }).limit(1).maybeSingle();
  // Fall back if migration 0003's columns aren't there yet.
  if (error && isMissingColumn(error)) {
    ({ data, error } = await supabase
      .from("visits").select(slim)
      .eq("house_id", house.id).eq("tech_id", user.id).eq("status", "in_progress")
      .order("started_at", { ascending: false }).limit(1).maybeSingle());
  }
  if (error || !data) return null;
  const items = {};
  for (const it of data.visit_items || []) {
    const o = {};
    if (it.answer === "na") o.na = true;
    else {
      if (typeof it.done === "boolean") o.done = it.done;
      if (it.answer) o.answer = it.answer;
    }
    if (it.done_on) o.doneOn = it.done_on;
    if (it.value) o.temp = it.value;
    if (it.note) o.note = it.note;
    items[it.item_key] = o;
  }
  return { visitId: data.id, house: houseName, date: data.visit_date,
           counts: data.counts || {}, survey: data.survey || {}, items };
}

// Every in-progress visit belonging to the signed-in tech, for the Continue
// screen. Returns null (not []) when the cloud can't be reached, so the UI
// can say so instead of claiming "nothing in progress".
async function listInProgress() {
  const { data: { user } } = await supabase.auth.getUser();
  if (!user) return null;
  const { data, error } = await supabase
    .from("visits")
    .select("id, visit_date, houses(name), visit_items(count)")
    .eq("tech_id", user.id).eq("status", "in_progress")
    .order("started_at", { ascending: false });
  if (error) { console.error("Could not list visits:", error.message); return null; }
  return data.map(v => ({
    visitId: v.id,
    houseName: v.houses?.name || "",
    date: v.visit_date,
    itemCount: v.visit_items?.[0]?.count ?? 0,
  }));
}

// Slice 2: the signed-in tech's OWN completed visits, newest first. Read-only.
// Self-scoped (tech_id = me) even though RLS permits reading any staff visit —
// the "my history" screen must never surface another tech's data.
async function listMyVisits() {
  const { data: { user } } = await supabase.auth.getUser();
  if (!user) return [];
  const { data, error } = await supabase
    .from("visits")
    .select("id, visit_date, completed_at, houses(name)")
    .eq("tech_id", user.id).eq("status", "completed")
    .order("visit_date", { ascending: false })
    .order("completed_at", { ascending: false });
  if (error) { console.error("Could not list my visits:", error.message); return []; }
  return data.map(v => ({
    id: v.id,
    houseName: v.houses?.name || "",
    visitDate: v.visit_date,
  }));
}

// Slice 2: one of the signed-in tech's OWN visits + its recorded items.
// Filtered tech_id = me so a hand-typed id can't open another tech's visit.
// Returns raw items; the UI computes which are "flagged" from GROUPS polarity.
async function getVisitDetail(visitId) {
  const { data: { user } } = await supabase.auth.getUser();
  if (!user) return { error: "Not signed in." };
  const { data, error } = await supabase
    .from("visits")
    .select("visit_date, houses(name), visit_items(item_key, answer, note)")
    .eq("id", visitId).eq("tech_id", user.id)
    .maybeSingle();
  if (error) { console.error("Could not load visit:", error.message); return { error: error.message }; }
  if (!data) return { error: "Visit not found." };
  return {
    houseName: data.houses?.name || "",
    visitDate: data.visit_date,
    items: data.visit_items || [],
  };
}

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

// Slice 3: the signed-in tech's own daily-log rows within a date range (one
// month per call). Self-scoped tech_id=me atop RLS. houseName comes from the
// joined house on auto rows (null on manual). Returns [] on no-user/error.
// techId omitted → the signed-in user's own rows (every existing caller).
// techId passed  → that tech's rows. RLS is the real gate: a non-supervisor
// passing someone else's id gets [] back (their select policy matches only
// their own rows); a supervisor gets the rows.
async function listLogsInRange(startDate, endDate, techId) {
  const { data: { user } } = await supabase.auth.getUser();
  if (!user) return [];
  const scopeId = techId || user.id;
  const { data, error } = await supabase
    .from("daily_logs")
    .select("id, log_date, kind, visit_id, note, done_keys, houses(name)")
    .eq("tech_id", scopeId)
    .gte("log_date", startDate).lte("log_date", endDate)
    .order("log_date", { ascending: true });
  if (error) { console.error("Could not list daily logs:", error.message); return []; }
  return data.map(r => ({
    id: r.id,
    logDate: r.log_date,
    kind: r.kind,
    visitId: r.visit_id || null,
    houseName: r.houses?.name || "",
    note: r.note || "",
    doneKeys: Array.isArray(r.done_keys) ? r.done_keys : [],
  }));
}

// Add a manual free-text note to any day (today or a past day). Manual only.
async function addLogEntry(logDate, note) {
  const { data: { user } } = await supabase.auth.getUser();
  if (!user) return { error: "Not signed in." };
  const text = (note || "").trim();
  if (!text) return { error: "Note can't be empty." };
  const { data, error } = await supabase.from("daily_logs")
    .insert({ tech_id: user.id, log_date: logDate, kind: "manual", note: text })
    .select("id").single();
  if (error) { console.error("Could not add daily log:", error.message); return { error: error.message }; }
  return { id: data.id };
}

// Edit one of the caller's own MANUAL notes. kind='manual' guard blocks any
// attempt to alter an auto row even though RLS would permit an owned-row update.
async function updateLogEntry(id, note) {
  const { data: { user } } = await supabase.auth.getUser();
  if (!user) return { error: "Not signed in." };
  const text = (note || "").trim();
  if (!text) return { error: "Note can't be empty." };
  const { error } = await supabase.from("daily_logs")
    .update({ note: text, updated_at: new Date().toISOString() })
    .eq("id", id).eq("tech_id", user.id).eq("kind", "manual");
  if (error) { console.error("Could not update daily log:", error.message); return { error: error.message }; }
  return { error: null };
}

// Delete one of the caller's own MANUAL notes. Same manual-only self-scope.
async function deleteLogEntry(id) {
  const { data: { user } } = await supabase.auth.getUser();
  if (!user) return { error: "Not signed in." };
  const { error } = await supabase.from("daily_logs")
    .delete().eq("id", id).eq("tech_id", user.id).eq("kind", "manual");
  if (error) { console.error("Could not delete daily log:", error.message); return { error: error.message }; }
  return { error: null };
}

// ---- My notes (private personal note cards) ----
// Fully tech-scoped, no supervisor read path — see 0018_personal_notes.sql.
// Each note has an optional title and a required body (`text`).

async function listMyNotes() {
  const { data: { user } } = await supabase.auth.getUser();
  if (!user) return [];
  const { data, error } = await supabase
    .from("personal_notes")
    .select("id, title, text, position")
    .eq("tech_id", user.id)
    .order("position", { ascending: true });
  if (error) {
    if (!isMissingTable(error)) console.error("Could not load my notes:", error.message);
    return [];
  }
  return data || [];
}

async function addMyNote(title, body) {
  const { data: { user } } = await supabase.auth.getUser();
  if (!user) return { error: "Not signed in." };
  const trimmedBody = (body || "").trim();
  if (!trimmedBody) return { error: "Note text can't be empty." };
  const { data: maxRow } = await supabase
    .from("personal_notes")
    .select("position")
    .eq("tech_id", user.id)
    .order("position", { ascending: false })
    .limit(1)
    .maybeSingle();
  const nextPosition = maxRow ? maxRow.position + 1 : 0;
  const { error } = await supabase
    .from("personal_notes")
    .insert({ tech_id: user.id, title: (title || "").trim(), text: trimmedBody, position: nextPosition });
  return { error: error ? error.message : null };
}

async function updateMyNote(id, title, body) {
  const { data: { user } } = await supabase.auth.getUser();
  if (!user) return { error: "Not signed in." };
  const trimmedBody = (body || "").trim();
  if (!trimmedBody) return { error: "Note text can't be empty." };
  const { error } = await supabase
    .from("personal_notes")
    .update({ title: (title || "").trim(), text: trimmedBody })
    .eq("id", id)
    .eq("tech_id", user.id);
  return { error: error ? error.message : null };
}

async function deleteMyNote(id) {
  const { data: { user } } = await supabase.auth.getUser();
  if (!user) return { error: "Not signed in." };
  const { error } = await supabase
    .from("personal_notes")
    .delete()
    .eq("id", id)
    .eq("tech_id", user.id);
  return { error: error ? error.message : null };
}

// For each date-tracked item key, find the most recent COMPLETED visit at this
// house where it was done, and return the date it was done on (the recorded
// done_on if the tech entered one, else the visit date).
// Returns { itemKey: "YYYY-MM-DD", â€¦ }. Any failure returns {} â€” the app then
// shows no badge rather than a wrong one.
async function lastDone(houseName, itemKeys) {
  const house = housesByName.get((houseName || "").trim().toLowerCase());
  if (!house || !itemKeys?.length) return {};
  let { data, error } = await supabase
    .from("visits")
    .select("visit_date, visit_items(item_key, done, done_on)")
    .eq("house_id", house.id).eq("status", "completed")
    .order("visit_date", { ascending: false }).limit(40);
  // Before migration 0003, done_on doesn't exist â€” fall back to the visit date.
  if (error && isMissingColumn(error)) {
    ({ data, error } = await supabase
      .from("visits")
      .select("visit_date, visit_items(item_key, done)")
      .eq("house_id", house.id).eq("status", "completed")
      .order("visit_date", { ascending: false }).limit(40));
  }
  if (error) { console.error("Could not load visit history:", error.message); return {}; }
  const out = {};
  for (const visit of data) {
    for (const it of visit.visit_items || []) {
      if (it.done && itemKeys.includes(it.item_key) && !(it.item_key in out)) {
        out[it.item_key] = it.done_on || visit.visit_date;   // newest first, first hit wins
      }
    }
  }
  return out;
}

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
  // Migration 0006 not applied yet â†’ tell the UI, don't fake an empty note.
  if (error) {
    return isMissingColumn(error) ? { notReady: true } : { error: error.message };
  }
  const { data: { user } } = await supabase.auth.getUser();
  let { data: sugs, error: e2 } = await supabase
    .from("house_note_suggestions").select(SUG_COLS)
    .eq("house_id", house.id).eq("status", "pending")
    .order("created_at", { ascending: false });
  // Migration 0008 not applied yet â†’ fall back to the 0006 shape (general only).
  if (e2 && isMissingColumn(e2)) {
    ({ data: sugs, error: e2 } = await supabase
      .from("house_note_suggestions")
      .select("id, author_id, author_name, proposed_text, created_at")
      .eq("house_id", house.id).eq("status", "pending")
      .order("created_at", { ascending: false }));
  }
  if (e2) return { error: e2.message };
  // My denied-and-not-yet-dismissed suggestions (the âŒ notices).
  let denials = [];
  if (user) {
    const { data: dens, error: e3 } = await supabase
      .from("house_note_suggestions")
      .select(SUG_COLS + ", deny_reason")
      .eq("house_id", house.id).eq("status", "dismissed")
      .eq("author_id", user.id).eq("seen_by_author", false)
      .order("created_at", { ascending: false });
    if (!e3) denials = dens || [];        // pre-0008 DB â†’ just no denial notices
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
  await loadHouses();   // the official note changed â€” refresh ðŸ“ notes everywhere
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

// Supervisor direct write: set/remove one item note or info pair. The patch
// is computed server-side by the set_house_field RPC (migration 0009) from
// the DATABASE's current row, not our cached copy — a stale client cache can
// no longer silently revert someone else's concurrent change. RLS still
// backstops this (the RPC itself checks current_user_role() = 'supervisor'),
// then the cache is re-fetched so every screen repaints truthful data.
async function saveHouseField(houseName, { target, noteKey, action, text }) {
  const house = housesByName.get((houseName || "").trim().toLowerCase());
  if (!house) return { error: `"${houseName}" isn't a house in the database.` };
  const { error } = await supabase.rpc("set_house_field", {
    house_id: house.id,
    target,
    note_key: noteKey || "",
    action: action || "set",
    new_text: action === "delete" ? "" : (text || ""),
  });
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

// ---- Routes admin (the supervisor Routes screen) ----
// The UI hides this screen from techs, but RLS (routes_write / houses_write,
// supervisor-only) is what actually enforces it.

async function listRoutes() {
  const { data, error } = await supabase
    .from("routes").select("id, name, tech_id").order("name");
  // notReady → migration 0007 hasn't been run; the screen says so.
  if (error) return { error: error.message, notReady: isMissingTable(error) };
  return { routes: data };
}

// Assignable people = tech-role profiles only (per spec; supervisors excluded).
// full_name can be '' if it was never set — the screen shows a fallback label.
async function listTechs() {
  const { data, error } = await supabase
    .from("profiles").select("id, full_name").eq("role", "tech").order("full_name");
  if (error) return { error: error.message };
  return { techs: data };
}

// The dropdown roster for the supervisor Daily Logs view: every tech, plus the
// signed-in user (so a supervisor can see their own diary too). Only the
// supervisor UI calls this (the dropdown is is-admin-only). Returns
// { people:[{id,label}], myId } or { error }.
async function listLogTechs() {
  const { data: { user } } = await supabase.auth.getUser();
  if (!user) return { error: "Not signed in." };
  const { data, error } = await supabase
    .from("profiles").select("id, full_name, role").order("full_name");
  if (error) return { error: error.message };
  const people = data
    .filter(p => p.role === "tech" || p.id === user.id)
    .map(p => ({
      id: p.id,
      label: p.id === user.id ? `You (${p.full_name || "me"})`
                              : (p.full_name || "Unnamed tech"),
    }));
  return { people, myId: user.id };
}

// One call covers both rename and tech (re)assignment — the turnover action.
async function saveRoute(routeId, { name, techId }) {
  const { error } = await supabase.from("routes")
    .update({ name: (name || "").trim(), tech_id: techId || null }).eq("id", routeId);
  return error ? { error: error.message } : { ok: true };
}

async function setHouseRoute(houseId, routeId) {
  const { error } = await supabase.from("houses")
    .update({ route_id: routeId || null }).eq("id", houseId);
  if (error) return { error: error.message };
  // Keep the local cache truthful so a re-render shows the new value without
  // a full reload.
  housesByName.forEach(h => { if (h.id === houseId) h.route_id = routeId || null; });
  return { ok: true };
}

// The Routes screen needs house IDs; the checklist app only knows names.
// Serve the already-loaded rows rather than re-querying.
function listHousesForRoutes() {
  return [...housesByName.values()]
    .map(h => ({ id: h.id, name: h.name, routeId: h.route_id || null }))
    .sort((a, b) => a.name.localeCompare(b.name));
}

window.cloud = { saveVisit, loadInProgress, lastDone, listInProgress,
                 getHouseNotes, suggestNote, suggestChange, withdrawSuggestion,
                 approveSuggestion, denySuggestion, markDenialSeen,
                 saveGeneralNotes, saveHouseField,
                 listPendingSuggestions, pendingCount,
                 listRoutes, listTechs, saveRoute, setHouseRoute, listHousesForRoutes,
                 getMyProfile, saveMyProfile,
                 listAllProfiles, saveProfileAsSupervisor, setProfileRole,
                 listMyVisits, getVisitDetail,
                 listCompletedVisits, getAnyVisitDetail, markVisitReviewed, unreviewedVisitCount,
                 listLogsInRange, listLogTechs, addLogEntry, updateLogEntry, deleteLogEntry,
                 listMyNotes, addMyNote, updateMyNote, deleteMyNote,
                 refreshMyRoute: loadMyRoute,
                 role: null };

// Primary sign-in: email + password.
form.addEventListener("submit", async (event) => {
  event.preventDefault();
  const email = emailInput.value.trim();
  const password = pwInput.value;
  if (!email || !password) { setMsg(authMsg, "Enter your email and password.", "error"); return; }
  setMsg(authMsg, "Signing inâ€¦");
  const { error } = await supabase.auth.signInWithPassword({ email, password });
  if (error) setMsg(authMsg, error.message, "error");
  // On success, onAuthStateChange (below) hides the gate and loads houses.
});

// Fallback / first-time: email a one-click magic login link (no password).
magicBtn.addEventListener("click", async () => {
  const email = emailInput.value.trim();
  if (!email) { setMsg(authMsg, "Type your email above first, then click this.", "error"); return; }
  setMsg(authMsg, "Sending linkâ€¦");
  const { error } = await supabase.auth.signInWithOtp({
    email,
    options: { emailRedirectTo: window.location.origin + window.location.pathname },
  });
  if (error) setMsg(authMsg, error.message, "error");
  else setMsg(authMsg, "Check your email for a login link, then return to this tab.", "ok");
});

// Set or change your password (works while you're signed in).
setPwBtn?.addEventListener("click", async () => {
  const password = newPwInput.value;
  if (!password || password.length < 6) { setMsg(pwMsg, "Use at least 6 characters.", "error"); return; }
  setMsg(pwMsg, "Savingâ€¦");
  const { error } = await supabase.auth.updateUser({ password });
  if (error) { setMsg(pwMsg, error.message, "error"); return; }
  setMsg(pwMsg, "Saved â€” sign in with this password next time.", "ok");
  newPwInput.value = "";
});

// Every sign-out button (houses sidebar + home screen) shares this one handler.
document.querySelectorAll("[data-sign-out]").forEach(btn =>
  btn.addEventListener("click", () => supabase.auth.signOut()));

// Single source of truth for auth. Fires on page load (INITIAL_SESSION), after
// a successful sign-in, and on sign-out.
supabase.auth.onAuthStateChange((_event, session) => {
  if (session) {
    showGate(false);
    if (whoami) whoami.textContent = session.user.email;
    setTimeout(async () => {   // DB work OUTSIDE the auth callback
      await loadRole();        // loadMyRoute needs role + houses loaded first
      await loadHouses();
      await loadMyRoute();
    }, 0);
  } else {
    showGate(true);
    if (whoami) whoami.textContent = "";
    if (window.cloud) window.cloud.role = null;
    document.body.classList.remove("is-admin");
    if (window.applyRole) window.applyRole(null);
    if (window.applyMyHouses) window.applyMyHouses(null);
    // Clear any per-user Daily Logs view state so the next sign-in (possibly a
    // different user, no page reload) doesn't inherit the prior user's picked
    // tech / roster / identity.
    if (window.resetLogsView) window.resetLogsView();
  }
});

