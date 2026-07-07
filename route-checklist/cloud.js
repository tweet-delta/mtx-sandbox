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
async function loadHouses() {
  const { data, error } = await supabase
    .from("houses")
    .select("name, equipment, notes, info")
    .eq("active", true)
    .order("name");
  if (error) { console.error("Could not load houses:", error.message); return; }
  if (window.applyHouses) window.applyHouses(data);
}

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
