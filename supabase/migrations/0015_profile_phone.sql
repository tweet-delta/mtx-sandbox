-- ============================================================================
-- 0015_profile_phone.sql — add a phone number to profiles so techs/supervisors
-- can maintain their own contact info in-app (My Profile screen).
--
-- HOW TO RUN: supabase db push --workdir "c:\Big Dogs Apps\MTX Checklist V1"
-- Safe to re-run ("if not exists").
-- ============================================================================

alter table public.profiles
  add column if not exists phone text not null default '';

-- ============================================================================
-- No RLS or grant changes needed: profiles_select / profiles_update (from
-- 0001_init.sql) already gate rows by "id = auth.uid() or supervisor", and
-- that check applies to the whole row, phone included.
-- ============================================================================
