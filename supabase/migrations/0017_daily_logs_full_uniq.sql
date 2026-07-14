-- ============================================================================
-- MTX Route Checklist — Daily Logs: fix the auto-stamp upsert (slice 3 of 4)
--
-- Bug: stampDailyLog() upserts with onConflict "tech_id,visit_id,log_date",
-- but 0016 backed that with a PARTIAL unique index (where kind='auto').
-- Postgres will not use a partial index as an ON CONFLICT arbiter unless the
-- statement's WHERE predicate is provably satisfied, and PostgREST sends no
-- such predicate — so every auto stamp failed with 42P10 ("no unique or
-- exclusion constraint matching the ON CONFLICT specification"). The visit
-- still saved (the stamp is best-effort), so the failure was silent: nothing
-- ever landed in daily_logs from a live save. Confirmed against the live REST
-- API returning 42P10 for that on_conflict target.
--
-- Fix: replace the partial index with a FULL unique index on the same columns.
--   - auto rows: (tech_id, visit_id, log_date) is exactly the idempotency key
--     we want — repeated Save-progress on one visit/day refreshes one row.
--   - manual rows: visit_id is NULL, and NULLs are DISTINCT in a standard
--     Postgres unique index, so many manual notes per day still coexist, and a
--     manual note never collides with an auto row. No behavior is lost.
-- ============================================================================

drop index if exists public.daily_logs_auto_uniq;

create unique index if not exists daily_logs_tech_visit_date_uniq
  on public.daily_logs (tech_id, visit_id, log_date);
