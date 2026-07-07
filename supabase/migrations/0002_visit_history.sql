-- 0002_visit_history.sql — visit history is house-level context
--
-- Why: the app now shows "last done at this house" badges on periodic jobs
-- (e.g. yearly water-alarm batteries). That date may come from ANOTHER tech's
-- earlier visit, so read access can't be limited to your own visits.
-- Writes are unchanged: techs still only insert/update their OWN visits.

-- 1. Any signed-in staff member may READ visits and their items.
--    (Logged-out users still see nothing — no grants to 'anon'.)
drop policy if exists visits_select on public.visits;
create policy visits_select on public.visits
  for select to authenticated
  using (true);

-- visit_items previously had only the parent-visit-ownership policy; add a
-- read-for-all-staff policy alongside it (policies are OR'd for SELECT).
drop policy if exists visit_items_select on public.visit_items;
create policy visit_items_select on public.visit_items
  for select to authenticated
  using (true);

-- 2. Allow 'na' answers — e.g. Generator questions at a house that has no
--    generator. The original check only allowed 'yes'/'no'.
alter table public.visit_items
  drop constraint if exists visit_items_answer_check;
alter table public.visit_items
  add constraint visit_items_answer_check
  check (answer in ('yes', 'no', 'na'));
