-- ----------------------------------------------------------------------------
-- 0014_fix_16th_avenue_fridge_coils.sql
--
-- 16th Avenue's fridgeCoils_res / fridgeCoils_rs notes were wrongly set to
-- the roof-coils note text ("Roof coils in garage by fuse box") — a copy/paste
-- error that predates the fridge-coils split in 0013 and got carried forward
-- by it. Roof coils and refrigerator coils are different equipment. We don't
-- know the real fridge-coils location for this house, so clear both notes to
-- empty; a tech will fill them in the next time they're at the house.
-- Idempotent. Applied with `supabase db push`.
-- ----------------------------------------------------------------------------

update public.houses set notes =
  jsonb_set(jsonb_set(notes, '{fridgeCoils_res}', '""'::jsonb), '{fridgeCoils_rs}', '""'::jsonb)
  where name = '16th Avenue';
