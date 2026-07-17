-- ============================================================================
-- 0022_profile_job_title.sql — a free-text, informational job title per person
-- (e.g. "Lead Tech"). Just profile data — no permissions effect, no server.
-- HOW TO RUN: supabase db push --workdir "c:\Big Dogs Apps\MTX Checklist V1"
-- Safe to re-run ("if not exists").
-- ============================================================================
alter table public.profiles
  add column if not exists job_title text not null default '';

-- No RLS/grant change: profiles_select / profiles_update (0001) already gate
-- rows by "id = auth.uid() or supervisor", covering the whole row.
