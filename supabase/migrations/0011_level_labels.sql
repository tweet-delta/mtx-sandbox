-- ----------------------------------------------------------------------------
-- 0011_level_labels.sql — level-specific note labels (owner-approved rewrite).
--
-- "Up/Upstairs/Down/Downstairs" note labels become "Residents (up):" /
-- "RS (down):" — flipped at the five RS-on-top houses (92nd Crescent, Amble,
-- Fallgold, McAfee, Sherwood Place); Fallgold uses Residents (1st) /
-- RS (2nd) / Basement (shared). Full before→after table reviewed by the
-- owner: docs/superpowers/specs/2026-07-12-level-label-notes-design.md.
--
-- jsonb || merges TOP-LEVEL keys: only the keys listed per house change;
-- every other note on the row is untouched. Safe to re-run (idempotent
-- overwrites). A renamed house simply no-ops its UPDATE.
-- ----------------------------------------------------------------------------

update public.houses set notes = notes || '{"fireExtinguishers": "Residents (up): laundry closet · RS (down): mech room · Garage: by main door · One in the van", "fridgeCoils": "Residents (up): front · RS (down): back", "dryerVents": "Residents (up): NW side · RS (down): NE side under deck"}'::jsonb where name = 'Dogwood';

update public.houses set notes = notes || '{"fireExtinguishers": "Residents (up): kitchen sink, van, garage · RS (down): kitchen sink"}'::jsonb where name = 'Roselawn';

update public.houses set notes = notes || '{"fireExtinguishers": "Residents (up): back hall by the pantry · RS (down): storage room off the kitchen, right around the corner", "fridgeCoils": "Residents (up): front of fridge · RS (down): front of fridge"}'::jsonb where name = '140th Lane East';

update public.houses set notes = notes || '{"fireExtinguishers": "Residents (up): kitchen, on the wall above the garbage cans · RS (down): kitchen, on wall by office", "fridgeCoils": "Residents (up): front of the fridge · RS (down): back of the fridge"}'::jsonb where name = '140th Lane West';

-- RS on top ↓
update public.houses set notes = notes || '{"fireExtinguishers": "Residents (down): kitchen, far right cabinet; one in the van · RS (up): one under the sink, one in laundry room", "dryerVents": "RS (up): back of the house by patio · Residents (down): by front door"}'::jsonb where name = '92nd Crescent';

-- RS on top ↓
update public.houses set notes = notes || '{"dryerVents": "Residents (down): east side of house · RS (up): back of house, middle vent next to porch (not under it); tall ladder needed"}'::jsonb where name = 'Amble';

update public.houses set notes = notes || '{"dryerVents": "Residents (up): above patio door"}'::jsonb where name = 'Barclay';

update public.houses set notes = notes || '{"fireExtinguishers": "(3) Van · Residents (up): west kitchen wall · RS (down): under the sink in the basement apartment"}'::jsonb where name = 'Bicentennial';

update public.houses set notes = notes || '{"fireExtinguishers": "(3) Van · Residents (up): under the sink · RS (down): under the sink"}'::jsonb where name = 'Boutwell';

update public.houses set notes = notes || '{"fireExtinguishers": "(5) Van · Residents (up): hallway, under sink, garage · RS (down): under sink", "dryerVents": "Residents (up): on the deck · RS (down): by the fence for the trash, on the house"}'::jsonb where name = 'Co. Rd. B2';

update public.houses set notes = notes || '{"dryerVents": "Residents (up): through the roof · RS (down): back under the deck (very long run; the RS dryer may auto-shut-off — coordinate with the live-in to keep it running while checking)"}'::jsonb where name = 'Crestridge';

update public.houses set notes = notes || '{"fireExtinguishers": "(2) Residents (up): under the kitchen sink · RS (down): under the kitchen sink", "dryerVents": "RS (down): south side of the house · Residents (up): on the roof"}'::jsonb where name = 'Dale Court';

update public.houses set notes = notes || '{"dryerVents": "Residents (up): east deck · RS (down): behind the house on the west side, under the deck where the brick blocks jut out, on top (not the disconnected one tucked way under the deck)"}'::jsonb where name = 'Dawn';

-- Three levels: Residents 1st, RS 2nd, shared basement ↓
update public.houses set notes = notes || '{"fireExtinguishers": "Residents (1st): on the cabinet in the kitchen · RS (2nd): laundry closet between washer and dryer · Basement (shared): bottom of the stairs · Van", "fridgeCoils": "Residents (1st): front side · RS (2nd): back of refrigerator", "atticAccess": "Attic access — RS (2nd): apartment hallway · Residents (1st): office area (for the garage) and in the hallway", "dryerVents": "RS (2nd): back of the house above the sunroom · Residents (1st): back of the house by the patio"}'::jsonb where name = 'Fallgold';

update public.houses set notes = notes || '{"fireExtinguishers": "Residents (up): kitchen wall · RS (down): attached to wall · in house van"}'::jsonb where name = 'Hillcrest';

update public.houses set notes = notes || '{"fireExtinguishers": "(4) Van · Residents (up): right of fridge · RS (down): just inside utility room and under the kitchen sink"}'::jsonb where name = 'Ilex';

update public.houses set notes = notes || '{"fireExtinguishers": "(4) Residents (up): normal and grease under the sink · RS (down): under the sink · van"}'::jsonb where name = 'Jennifer Court';

update public.houses set notes = notes || '{"fireExtinguishers": "Residents (up): garage · RS (down): mechanical room", "dryerVents": "Residents (up): north end of the house, by the garbage cans · RS (down): east side of the house in the back yard"}'::jsonb where name = 'Lancaster';

update public.houses set notes = notes || '{"fireExtinguishers": "(4) Inside garage by back door · van · Residents (up): kitchen behind the door · RS (down): under the sink"}'::jsonb where name = 'Lydia Ave';

update public.houses set notes = notes || '{"fireExtinguishers": "(4) Van · Residents (up): kitchen, laundry · RS (down): under kitchen sink"}'::jsonb where name = 'Lydia West';

update public.houses set notes = notes || '{"fireExtinguishers": "Residents (up): laundry room by the washing machine · RS (down): one in mechanical room, one under the kitchen sink", "dryerVents": "Residents (up): under deck · RS (down): (see house)"}'::jsonb where name = 'Magnolia';

-- RS on top ↓
update public.houses set notes = notes || '{"dryerVents": "Residents (down): south side · RS (up): back of house"}'::jsonb where name = 'McAfee';

update public.houses set notes = notes || '{"fireExtinguishers": "Residents (up): under kitchen sink, cleaning closet (by front door), laundry · RS (down): office, furnace room · Van"}'::jsonb where name = 'McMenemy';

update public.houses set notes = notes || '{"fireExtinguishers": "(4) Van · Residents (up): under sink, laundry · RS (down): (not filled in on the sheet)"}'::jsonb where name = 'Oakwood';

update public.houses set notes = notes || '{"fireExtinguishers": "Residents (up): closet in dining room · RS (down): in the cabinet under the island", "dryerVents": "Residents (up): on the south wall, under the ramp to the deck · RS (down): north wall"}'::jsonb where name = 'Regent';

update public.houses set notes = notes || '{"fireExtinguishers": "(6) Van · Residents (up): kitchen (hanging on the wall), laundry (on the wall to the left) · RS (down): under kitchen sink, closet in the second living room (just right of laundry room) · 1 in the garage", "dryerVents": "Both on the south side. Residents (up): right of the faucet in the corner · RS (down): left of the faucet"}'::jsonb where name = 'Riverdale';

update public.houses set notes = notes || '{"fireExtinguishers": "Residents (up): kitchen and hallway · In the van · RS (down): under sink and furnace room", "dryerVents": "Residents (up): vented through the roof · RS (down): vent comes out on the front ramp"}'::jsonb where name = 'Robin Ave';

-- RS on top ↓
update public.houses set notes = notes || '{"fireExtinguishers": "Residents (down): left of the sink · RS (up): under the sink · one mounted on the garage wall · one in the house van", "atticAccess": "Attic access — RS (up): laundry room; will need the 6 ft ladder"}'::jsonb where name = 'Sherwood Place';

update public.houses set notes = notes || '{"fireExtinguishers": "Garage, under kitchen sink, van, RS apartment (down), and laundry room"}'::jsonb where name = 'Tiller Lane';

update public.houses set notes = notes || '{"fireExtinguishers": "(3) Residents (up): laundry closet · RS (down): under kitchen sink · One in the van", "fridgeCoils": "Residents (up): front of fridge · RS (down): back of fridge", "dryerVents": "Residents (up): on the back of the house · RS (down): on the front of the house"}'::jsonb where name = 'Toledo';

update public.houses set notes = notes || '{"fireExtinguishers": "Residents (up): above kitchen sink on cabinet · Van: on passenger seat · RS (down): under kitchen sink", "dryerVents": "Residents (up): right outside the garage door · RS (down): right outside the garage door"}'::jsonb where name = 'Valders';

update public.houses set notes = notes || '{"fireExtinguishers": "Residents (up): in the kitchen by the cabinet; also one in the garage · RS (down): under the kitchen sink", "dryerVents": "Residents (up): on the roof · RS (down): on the east end of the house"}'::jsonb where name = 'Oregon Brooklyn Park (OBP)';

update public.houses set notes = notes || '{"dryerVents": "RS (down): comes out at the front of the house under the kitchen window · Residents (up): on the north side of the house, up high"}'::jsonb where name = 'Redwood';

update public.houses set notes = notes || '{"fireExtinguishers": "Residents (up): laundry closet and in kitchen next to fridge · RS (down): under kitchen sink, van, garage", "fridgeCoils": "Residents (up): front/back · RS (down): front/back", "dryerVents": "Residents (up): roof · RS (down): on north side of the house"}'::jsonb where name = 'Oregon Golden Valley (OGV)';

update public.houses set notes = notes || '{"fireExtinguishers": "(3) One in the van · Residents (up): in the cabinet right of the fridge · RS (down): in the cabinet just right of the dishwasher", "dryerVents": "Residents (up): super short run straight out on the west side of the house · RS (down): (not filled in on the sheet)"}'::jsonb where name = 'Riverton';
