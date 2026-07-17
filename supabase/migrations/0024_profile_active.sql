-- ============================================================================
-- 0024_profile_active.sql — soft on/off for an account. Deactivation flips
-- this false AND bans the auth user (done in the admin-users Edge Function);
-- reactivation flips it back and unbans. Deactivate, never delete — the
-- schema's on-delete-cascade would destroy a tech's visit history.
-- HOW TO RUN: supabase db push --workdir "c:\Big Dogs Apps\MTX Checklist V1"
-- Safe to re-run ("if not exists").
-- ============================================================================
alter table public.profiles
  add column if not exists active boolean not null default true;

-- No RLS change: supervisors already read all profiles; the app filters
-- inactive people out of the assignable dropdowns.
