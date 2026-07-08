// cloud.js — the "cloud layer": login + loading data from Supabase.
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
const signOutBtn = document.getElementById("signOutBtn");
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
// We keep the DB ids here (name → row) so saveVisit/lastDone below can turn
// a house NAME (all the app knows) into the house_id the database needs.
const housesByName = new Map();
async function loadHouses() {
  const { data, error } = await supabase
    .from("houses")
    .select("id, name, equipment, notes, info")
    .eq("active", true)
    .order("name");
  if (error) { console.error("Could not load houses:", error.message); return; }
  housesByName.clear();
  data.forEach(h => housesByName.set(h.name.trim().toLowerCase(), h));
  if (window.applyHouses) window.applyHouses(data);
}

// ---- Visit history (the app calls these via window.cloud) ----

// Save a visit: one `visits` row + one `visit_items` row per answered item.
//   status "in_progress" → the Save progress button (resume later/elsewhere).
//   status "completed"   → the survey's Save & Send (the finalize).
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
  if (rows.length) {
    // upsert: re-saving the same visit overwrites each item row, not duplicates it
    const { error } = await supabase.from("visit_items")
      .upsert(rows, { onConflict: "visit_id,item_key" });
    if (error) return { error: error.message, visitId };
  }
  return { visitId };
}

// The signed-in tech's most recent IN-PROGRESS visit at this house, if any, in
// the app's local-state shape — so Save progress can be resumed on any device.
async function loadInProgress(houseName) {
  const house = housesByName.get((houseName || "").trim().toLowerCase());
  if (!house) return null;
  const { data: { user } } = await supabase.auth.getUser();
  if (!user) return null;
  const { data, error } = await supabase
    .from("visits")
    .select("id, visit_date, counts, survey, visit_items(item_key, done, answer, note, done_on, value)")
    .eq("house_id", house.id)
    .eq("tech_id", user.id)
    .eq("status", "in_progress")
    .order("started_at", { ascending: false })
    .limit(1)
    .maybeSingle();
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

// For each date-tracked item key, find the most recent COMPLETED visit at this
// house where it was done, and return the date it was done on (the recorded
// done_on if the tech entered one, else the visit date).
// Returns { itemKey: "YYYY-MM-DD", … }. Any failure returns {} — the app then
// shows no badge rather than a wrong one.
async function lastDone(houseName, itemKeys) {
  const house = housesByName.get((houseName || "").trim().toLowerCase());
  if (!house || !itemKeys?.length) return {};
  const { data, error } = await supabase
    .from("visits")
    .select("visit_date, visit_items(item_key, done, done_on)")
    .eq("house_id", house.id)
    .eq("status", "completed")
    .order("visit_date", { ascending: false })
    .limit(40);
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

window.cloud = { saveVisit, loadInProgress, lastDone };

// Primary sign-in: email + password.
form.addEventListener("submit", async (event) => {
  event.preventDefault();
  const email = emailInput.value.trim();
  const password = pwInput.value;
  if (!email || !password) { setMsg(authMsg, "Enter your email and password.", "error"); return; }
  setMsg(authMsg, "Signing in…");
  const { error } = await supabase.auth.signInWithPassword({ email, password });
  if (error) setMsg(authMsg, error.message, "error");
  // On success, onAuthStateChange (below) hides the gate and loads houses.
});

// Fallback / first-time: email a one-click magic login link (no password).
magicBtn.addEventListener("click", async () => {
  const email = emailInput.value.trim();
  if (!email) { setMsg(authMsg, "Type your email above first, then click this.", "error"); return; }
  setMsg(authMsg, "Sending link…");
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
  setMsg(pwMsg, "Saving…");
  const { error } = await supabase.auth.updateUser({ password });
  if (error) { setMsg(pwMsg, error.message, "error"); return; }
  setMsg(pwMsg, "Saved — sign in with this password next time.", "ok");
  newPwInput.value = "";
});

signOutBtn?.addEventListener("click", () => supabase.auth.signOut());

// Single source of truth for auth. Fires on page load (INITIAL_SESSION), after
// a successful sign-in, and on sign-out.
supabase.auth.onAuthStateChange((_event, session) => {
  if (session) {
    showGate(false);
    if (whoami) whoami.textContent = session.user.email;
    setTimeout(loadHouses, 0); // do DB work OUTSIDE the auth callback
  } else {
    showGate(true);
    if (whoami) whoami.textContent = "";
  }
});
