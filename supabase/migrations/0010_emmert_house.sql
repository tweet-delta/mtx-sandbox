-- ----------------------------------------------------------------------------
-- 0010_emmert_house.sql — add the Emmert house (sheet received 2026-07-12).
--
-- Generated from route-checklist/house-data.js via headless Chrome
-- (scratchpad gen-0010.html) so quote-escaping is guaranteed. Door/entry
-- codes are NEVER stored here (public repo) — they live only in the
-- gitignored house-codes.local.js.
--
-- Applied with `supabase db push`. Safe to re-run: the insert skips the
-- house if it is already present.
-- ----------------------------------------------------------------------------
insert into public.houses (name, equipment, notes, info) values
('Emmert',
 '{"waterSoftener":true,"sumpPump":true,"generator":true,"garbageDisposal":false}'::jsonb,
 '{"furnaceFilter":"16x25x4 — two furnaces","waterSoftener":"In the utility area","shutoffs":"Main water: mechanical room, behind the water softener. Main gas: at the meter on the north side of the house. Outside water: both in the basement utility-room ceiling — front in front of the water heater; back in front of the water softener. Two PVC valves that need adjusting in spring & winter are in the corner next to the water heaters","medLock":"Stealth lock — 5 locking cabinets in the kitchen (code in local codes file)","dryerVents":"Three on the north side of the house. The one on the right takes 3 full packs of rods; one of the two on the left needs a ladder to reach"}'::jsonb,
 '[["Sump pumps","Three — two in the mechanical room, one in the closet under the stairs"],["MTX cabinet","Closet under the stairs (no cabinet)"],["Grounding rod","In the rock bed to the right of the garage (facing the garage doors), among the bushes — one is growing over the rod, so it''s kind of hidden"],["Generator","This house has two generators"],["Electrical boxes","Two panels at the north end of the mechanical room in the basement"],["Door keypads","Installed & serviced by Electrical Watchmen — contact: Ben 651-310-1268"]]'::jsonb)
on conflict (name) do nothing;
