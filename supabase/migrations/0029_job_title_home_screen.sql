-- Managed job titles Slice 3 (part 1): which home layout a title uses.
-- 'office'  = the Slice 1 office home (default; also what field titles ignore).
-- 'designer'= the tailored Interior Designer home (My requests / wish list /
--             by-house ticket views). Future office roles add new values here,
--             not a redesign. Additive: no data change, no RLS/grant change
--             (job_titles is already supervisor-write / all-read from 0027).
alter table public.job_titles
  add column if not exists home_screen text not null default 'office'
  check (home_screen in ('office','designer'));
