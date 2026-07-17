// supabase/functions/admin-users/index.ts
// ============================================================================
// The app's FIRST server component. It holds the service_role secret key
// (as a Supabase function secret — NEVER in the repo or the browser) and
// performs privileged auth.users operations that the client physically can't.
//
// Every request is GATED: the caller must present a valid JWT AND be a
// supervisor. Only then does the function use the service-role admin client.
// It FAILS CLOSED — any missing/invalid token, non-supervisor, or unknown
// action returns an error and does nothing.
//
// Actions in this file (Slice 2b): "list", "create". Later slices add
// reset_password, change_email, set_active.
// ============================================================================
import { createClient } from "https://esm.sh/@supabase/supabase-js@2";

// Only the deployed app origin may call this from a browser.
const APP_ORIGIN = "https://tweet-delta.github.io";
const cors = {
  "Access-Control-Allow-Origin": APP_ORIGIN,
  "Access-Control-Allow-Headers": "authorization, content-type",
  "Access-Control-Allow-Methods": "POST, OPTIONS",
};
const json = (body: unknown, status = 200) =>
  new Response(JSON.stringify(body), {
    status,
    headers: { ...cors, "Content-Type": "application/json" },
  });

Deno.serve(async (req) => {
  if (req.method === "OPTIONS") return new Response("ok", { headers: cors });
  if (req.method !== "POST") return json({ error: "Method not allowed" }, 405);

  // SUPABASE_URL and SUPABASE_ANON_KEY are auto-injected by the platform.
  // The secret key uses a NON-"SUPABASE_" name because the platform reserves
  // that prefix and rejects `secrets set SUPABASE_...`.
  const SUPABASE_URL = Deno.env.get("SUPABASE_URL")!;
  const ANON = Deno.env.get("SUPABASE_ANON_KEY")!;
  const SECRET = Deno.env.get("ADMIN_SERVICE_KEY")!;
  if (!SUPABASE_URL || !ANON || !SECRET) {
    return json({ error: "Function is not configured." }, 500);
  }

  // 1) Identify the caller from their JWT (a client scoped to that token).
  const authHeader = req.headers.get("Authorization") ?? "";
  const asCaller = createClient(SUPABASE_URL, ANON, {
    global: { headers: { Authorization: authHeader } },
  });
  const { data: { user }, error: uErr } = await asCaller.auth.getUser();
  if (uErr || !user) return json({ error: "Not signed in." }, 401);

  // 2) THE GATE: the caller must be a supervisor.
  const { data: prof } = await asCaller
    .from("profiles").select("role").eq("id", user.id).maybeSingle();
  if (prof?.role !== "supervisor") return json({ error: "Supervisors only." }, 403);

  // 3) Service-role client for the privileged work (bypasses RLS). Only
  //    reached AFTER the gate passes.
  const admin = createClient(SUPABASE_URL, SECRET);

  // Append-only audit write. Never receives a password.
  const audit = (
    action: string,
    target_id: string | null,
    target_email: string | null,
    detail: Record<string, unknown> = {},
  ) =>
    admin.from("admin_audit").insert({
      actor_id: user.id, action, target_id, target_email, detail,
    });

  let body: Record<string, unknown>;
  try {
    body = await req.json();
  } catch {
    return json({ error: "Bad JSON" }, 400);
  }
  const action = body?.action;

  try {
    // -- list: every account with its REAL email (only the server can read it) --
    if (action === "list") {
      const { data: list, error } = await admin.auth.admin.listUsers();
      if (error) return json({ error: error.message }, 500);
      const { data: profs } = await admin
        .from("profiles").select("id, full_name, phone, job_title, role, active");
      const byId = new Map((profs ?? []).map((p) => [p.id as string, p]));
      const people = list.users.map((u) => {
        const p = (byId.get(u.id) ?? {}) as Record<string, unknown>;
        return {
          id: u.id,
          email: u.email ?? "",
          fullName: (p.full_name as string) ?? "",
          phone: (p.phone as string) ?? "",
          jobTitle: (p.job_title as string) ?? "",
          role: (p.role as string) ?? "tech",
          active: (p.active as boolean) ?? true,
          isMe: u.id === user.id,
        };
      }).sort((a, b) => (a.fullName || "").localeCompare(b.fullName || ""));
      return json({ people, myId: user.id });
    }

    // -- create: mint a new account with a supervisor-set temp password --
    if (action === "create") {
      const email = String(body.email ?? "").trim();
      const password = String(body.password ?? "");
      const fullName = String(body.fullName ?? "").trim();
      if (!email || password.length < 8) {
        return json({ error: "Email and an 8+ character password are required." }, 400);
      }
      const { data, error } = await admin.auth.admin.createUser({
        email,
        password,
        email_confirm: true, // supervisor-provisioned; no confirmation email
      });
      if (error) return json({ error: error.message }, 400);
      const newId = data.user!.id;
      // handle_new_user (0001) already created a 'tech' profile row; set name.
      await admin.from("profiles").update({ full_name: fullName }).eq("id", newId);
      await audit("create", newId, email, { fullName });
      return json({ ok: true, id: newId });
    }

    return json({ error: "Unknown action" }, 400);
  } catch (e) {
    return json({ error: String((e as Error)?.message ?? e) }, 500);
  }
});
