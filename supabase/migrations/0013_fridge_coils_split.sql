-- ----------------------------------------------------------------------------
-- 0013_fridge_coils_split.sql — Part 2 of level-split-notes.
--
-- fridgeCoils is the only note with a checklist item in BOTH the Resident and
-- RS kitchen sections, so its single value rendered (duplicated) in both.
-- Split it into fridgeCoils_res (Resident kitchen) and fridgeCoils_rs (RS
-- kitchen), each independently editable; remove the old key. Values that don't
-- cleanly split (no markers, identical halves, "See house info") copy whole to
-- both. Spec: docs/superpowers/specs/2026-07-12-fridge-coils-split-design.md.
--
-- Per house: set the two new keys, then delete the old key with `- 'fridgeCoils'`.
-- Idempotent. Applied with `supabase db push`.
-- ----------------------------------------------------------------------------

update public.houses set notes =
  jsonb_set(jsonb_set(notes, '{fridgeCoils_res}', '"front"'::jsonb), '{fridgeCoils_rs}', '"back"'::jsonb)
  - 'fridgeCoils'
  where name = 'Dogwood';

update public.houses set notes =
  jsonb_set(jsonb_set(notes, '{fridgeCoils_res}', '"Roof coils in garage by fuse box"'::jsonb), '{fridgeCoils_rs}', '"Roof coils in garage by fuse box"'::jsonb)
  - 'fridgeCoils'
  where name = '16th Avenue';

update public.houses set notes =
  jsonb_set(jsonb_set(notes, '{fridgeCoils_res}', '"front of fridge"'::jsonb), '{fridgeCoils_rs}', '"front of fridge"'::jsonb)
  - 'fridgeCoils'
  where name = '140th Lane East';

update public.houses set notes =
  jsonb_set(jsonb_set(notes, '{fridgeCoils_res}', '"front of the fridge"'::jsonb), '{fridgeCoils_rs}', '"back of the fridge"'::jsonb)
  - 'fridgeCoils'
  where name = '140th Lane West';

update public.houses set notes =
  jsonb_set(jsonb_set(notes, '{fridgeCoils_res}', '"See house info"'::jsonb), '{fridgeCoils_rs}', '"See house info"'::jsonb)
  - 'fridgeCoils'
  where name = '92nd Crescent';

update public.houses set notes =
  jsonb_set(jsonb_set(notes, '{fridgeCoils_res}', '"front side"'::jsonb), '{fridgeCoils_rs}', '"back of refrigerator"'::jsonb)
  - 'fridgeCoils'
  where name = 'Fallgold';

update public.houses set notes =
  jsonb_set(jsonb_set(notes, '{fridgeCoils_res}', '"front of fridge"'::jsonb), '{fridgeCoils_rs}', '"back of fridge"'::jsonb)
  - 'fridgeCoils'
  where name = 'Toledo';

update public.houses set notes =
  jsonb_set(jsonb_set(notes, '{fridgeCoils_res}', '"front/back"'::jsonb), '{fridgeCoils_rs}', '"front/back"'::jsonb)
  - 'fridgeCoils'
  where name = 'Oregon Golden Valley (OGV)';
