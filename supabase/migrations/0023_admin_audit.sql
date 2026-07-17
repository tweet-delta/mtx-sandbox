-- ============================================================================
-- 0023_admin_audit.sql — append-only log of privileged account-admin actions.
-- Written ONLY by the admin-users Edge Function's service-role client (which
-- bypasses RLS). No client insert/update/delete grant, so the log can't be
-- forged or tampered with from the browser. Supervisors may read it.
-- HOW TO RUN: supabase db push --workdir "c:\Big Dogs Apps\MTX Checklist V1"
-- Safe to re-run ("if not exists" / "drop policy if exists").
-- ============================================================================
create table if not exists public.admin_audit (
  id           uuid primary key default gen_random_uuid(),
  actor_id     uuid references public.profiles (id),
  action       text not null,
  target_id    uuid,
  target_email text,
  detail       jsonb not null default '{}'::jsonb,
  created_at   timestamptz not null default now()
);
create index if not exists admin_audit_created_idx on public.admin_audit (created_at desc);

alter table public.admin_audit enable row level security;

-- Supervisors may READ the log. (There is no client write path at all.)
drop policy if exists admin_audit_select on public.admin_audit;
create policy admin_audit_select on public.admin_audit
  for select to authenticated
  using (public.current_user_role() = 'supervisor');

-- Only SELECT is granted to 'authenticated'. No insert/update/delete grant —
-- the Edge Function writes via the service-role key, which bypasses grants+RLS.
-- Append-only by construction: nothing exposed can update or delete a row.
grant select on public.admin_audit to authenticated;
