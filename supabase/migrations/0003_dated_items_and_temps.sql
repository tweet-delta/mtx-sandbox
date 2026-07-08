-- 0003_dated_items_and_temps.sql
--
-- Two new per-item fields on visit_items:
--   done_on  — the ACTUAL date a date-tracked job was done (med-lock batteries,
--              water-alarm batteries, fire extinguishers, detector dates,
--              furnace filter). May differ from the visit date, so the tech
--              records it explicitly. Drives the due-date badges.
--   value    — a free-form reading captured on an item, e.g. the highest water
--              temperature (°F). Text so it can hold "108", "108.5", etc.
--
-- Safe to re-run (add column if not exists).

alter table public.visit_items
  add column if not exists done_on date;

alter table public.visit_items
  add column if not exists value text;
