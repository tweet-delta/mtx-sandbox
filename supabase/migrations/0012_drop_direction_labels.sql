-- ----------------------------------------------------------------------------
-- 0012_drop_direction_labels.sql — Part 1 of the level-split-notes work.
--
-- Drops the (up)/(down)/(1st)/(2nd)/(shared) direction parenthetical from
-- fireExtinguishers, dryerVents, atticAccess notes: "Residents (up): X · RS
-- (down): Y" -> "Resident: X · RS: Y". The label already names the unit, so
-- the direction word is redundant (owner decision, format B). fridgeCoils is
-- handled separately in 0013 (true per-level split). Spec:
-- docs/superpowers/specs/2026-07-12-fridge-coils-split-design.md.
--
-- jsonb_set replaces one key; every other note on the row is untouched.
-- Idempotent: re-running writes the same already-clean text. Applied with
-- `supabase db push`.
-- ----------------------------------------------------------------------------

update public.houses set notes = jsonb_set(notes, '{fireExtinguishers}', '"Resident: laundry closet · RS: mech room · Garage: by main door · One in the van"'::jsonb) where name = 'Dogwood';
update public.houses set notes = jsonb_set(notes, '{dryerVents}', '"Resident: NW side · RS: NE side under deck"'::jsonb) where name = 'Dogwood';
update public.houses set notes = jsonb_set(notes, '{fireExtinguishers}', '"Resident: kitchen sink, van, garage · RS: kitchen sink"'::jsonb) where name = 'Roselawn';
update public.houses set notes = jsonb_set(notes, '{fireExtinguishers}', '"Resident: back hall by the pantry · RS: storage room off the kitchen, right around the corner"'::jsonb) where name = '140th Lane East';
update public.houses set notes = jsonb_set(notes, '{fireExtinguishers}', '"Resident: kitchen, on the wall above the garbage cans · RS: kitchen, on wall by office"'::jsonb) where name = '140th Lane West';
update public.houses set notes = jsonb_set(notes, '{fireExtinguishers}', '"Resident: kitchen, far right cabinet; one in the van · RS: one under the sink, one in laundry room"'::jsonb) where name = '92nd Crescent';
update public.houses set notes = jsonb_set(notes, '{dryerVents}', '"RS: back of the house by patio · Resident: by front door"'::jsonb) where name = '92nd Crescent';
update public.houses set notes = jsonb_set(notes, '{dryerVents}', '"Resident: east side of house · RS: back of house, middle vent next to porch (not under it); tall ladder needed"'::jsonb) where name = 'Amble';
update public.houses set notes = jsonb_set(notes, '{dryerVents}', '"Resident: above patio door"'::jsonb) where name = 'Barclay';
update public.houses set notes = jsonb_set(notes, '{fireExtinguishers}', '"(3) Van · Resident: west kitchen wall · RS: under the sink in the basement apartment"'::jsonb) where name = 'Bicentennial';
update public.houses set notes = jsonb_set(notes, '{fireExtinguishers}', '"(3) Van · Resident: under the sink · RS: under the sink"'::jsonb) where name = 'Boutwell';
update public.houses set notes = jsonb_set(notes, '{fireExtinguishers}', '"(5) Van · Resident: hallway, under sink, garage · RS: under sink"'::jsonb) where name = 'Co. Rd. B2';
update public.houses set notes = jsonb_set(notes, '{dryerVents}', '"Resident: on the deck · RS: by the fence for the trash, on the house"'::jsonb) where name = 'Co. Rd. B2';
update public.houses set notes = jsonb_set(notes, '{dryerVents}', '"Resident: through the roof · RS: back under the deck (very long run; the RS dryer may auto-shut-off — coordinate with the live-in to keep it running while checking)"'::jsonb) where name = 'Crestridge';
update public.houses set notes = jsonb_set(notes, '{fireExtinguishers}', '"(2) Resident: under the kitchen sink · RS: under the kitchen sink"'::jsonb) where name = 'Dale Court';
update public.houses set notes = jsonb_set(notes, '{dryerVents}', '"RS: south side of the house · Resident: on the roof"'::jsonb) where name = 'Dale Court';
update public.houses set notes = jsonb_set(notes, '{dryerVents}', '"Resident: east deck · RS: behind the house on the west side, under the deck where the brick blocks jut out, on top (not the disconnected one tucked way under the deck)"'::jsonb) where name = 'Dawn';
update public.houses set notes = jsonb_set(notes, '{fireExtinguishers}', '"Resident: on the cabinet in the kitchen · RS: laundry closet between washer and dryer · Basement: bottom of the stairs · Van"'::jsonb) where name = 'Fallgold';
update public.houses set notes = jsonb_set(notes, '{atticAccess}', '"Attic access — RS: apartment hallway · Resident: office area (for the garage) and in the hallway"'::jsonb) where name = 'Fallgold';
update public.houses set notes = jsonb_set(notes, '{dryerVents}', '"RS: back of the house above the sunroom · Resident: back of the house by the patio"'::jsonb) where name = 'Fallgold';
update public.houses set notes = jsonb_set(notes, '{fireExtinguishers}', '"Resident: kitchen wall · RS: attached to wall · in house van"'::jsonb) where name = 'Hillcrest';
update public.houses set notes = jsonb_set(notes, '{fireExtinguishers}', '"(4) Van · Resident: right of fridge · RS: just inside utility room and under the kitchen sink"'::jsonb) where name = 'Ilex';
update public.houses set notes = jsonb_set(notes, '{fireExtinguishers}', '"Resident: garage · RS: mechanical room"'::jsonb) where name = 'Lancaster';
update public.houses set notes = jsonb_set(notes, '{dryerVents}', '"Resident: north end of the house, by the garbage cans · RS: east side of the house in the back yard"'::jsonb) where name = 'Lancaster';
update public.houses set notes = jsonb_set(notes, '{fireExtinguishers}', '"(4) Inside garage by back door · van · Resident: kitchen behind the door · RS: under the sink"'::jsonb) where name = 'Lydia Ave';
update public.houses set notes = jsonb_set(notes, '{fireExtinguishers}', '"(4) Van · Resident: kitchen, laundry · RS: under kitchen sink"'::jsonb) where name = 'Lydia West';
update public.houses set notes = jsonb_set(notes, '{fireExtinguishers}', '"Resident: laundry room by the washing machine · RS: one in mechanical room, one under the kitchen sink"'::jsonb) where name = 'Magnolia';
update public.houses set notes = jsonb_set(notes, '{dryerVents}', '"Resident: under deck · RS: (see house)"'::jsonb) where name = 'Magnolia';
update public.houses set notes = jsonb_set(notes, '{dryerVents}', '"Resident: south side · RS: back of house"'::jsonb) where name = 'McAfee';
update public.houses set notes = jsonb_set(notes, '{fireExtinguishers}', '"Resident: under kitchen sink, cleaning closet (by front door), laundry · RS: office, furnace room · Van"'::jsonb) where name = 'McMenemy';
update public.houses set notes = jsonb_set(notes, '{fireExtinguishers}', '"(4) Resident: normal and grease under the sink · RS: under the sink · van"'::jsonb) where name = 'Jennifer Court';
update public.houses set notes = jsonb_set(notes, '{fireExtinguishers}', '"(4) Van · Resident: under sink, laundry · RS: (not filled in on the sheet)"'::jsonb) where name = 'Oakwood';
update public.houses set notes = jsonb_set(notes, '{fireExtinguishers}', '"Resident: closet in dining room · RS: in the cabinet under the island"'::jsonb) where name = 'Regent';
update public.houses set notes = jsonb_set(notes, '{dryerVents}', '"Resident: on the south wall, under the ramp to the deck · RS: north wall"'::jsonb) where name = 'Regent';
update public.houses set notes = jsonb_set(notes, '{fireExtinguishers}', '"(6) Van · Resident: kitchen (hanging on the wall), laundry (on the wall to the left) · RS: under kitchen sink, closet in the second living room (just right of laundry room) · 1 in the garage"'::jsonb) where name = 'Riverdale';
update public.houses set notes = jsonb_set(notes, '{dryerVents}', '"Both on the south side. Resident: right of the faucet in the corner · RS: left of the faucet"'::jsonb) where name = 'Riverdale';
update public.houses set notes = jsonb_set(notes, '{fireExtinguishers}', '"Resident: kitchen and hallway · In the van · RS: under sink and furnace room"'::jsonb) where name = 'Robin Ave';
update public.houses set notes = jsonb_set(notes, '{dryerVents}', '"Resident: vented through the roof · RS: vent comes out on the front ramp"'::jsonb) where name = 'Robin Ave';
update public.houses set notes = jsonb_set(notes, '{fireExtinguishers}', '"Resident: left of the sink · RS: under the sink · one mounted on the garage wall · one in the house van"'::jsonb) where name = 'Sherwood Place';
update public.houses set notes = jsonb_set(notes, '{atticAccess}', '"Attic access — RS: laundry room; will need the 6 ft ladder"'::jsonb) where name = 'Sherwood Place';
update public.houses set notes = jsonb_set(notes, '{fireExtinguishers}', '"Garage, under kitchen sink, van, RS apartment, and laundry room"'::jsonb) where name = 'Tiller Lane';
update public.houses set notes = jsonb_set(notes, '{fireExtinguishers}', '"(3) Resident: laundry closet · RS: under kitchen sink · One in the van"'::jsonb) where name = 'Toledo';
update public.houses set notes = jsonb_set(notes, '{dryerVents}', '"Resident: on the back of the house · RS: on the front of the house"'::jsonb) where name = 'Toledo';
update public.houses set notes = jsonb_set(notes, '{fireExtinguishers}', '"Resident: above kitchen sink on cabinet · Van: on passenger seat · RS: under kitchen sink"'::jsonb) where name = 'Valders';
update public.houses set notes = jsonb_set(notes, '{dryerVents}', '"Resident: right outside the garage door · RS: right outside the garage door"'::jsonb) where name = 'Valders';
update public.houses set notes = jsonb_set(notes, '{fireExtinguishers}', '"Resident: in the kitchen by the cabinet; also one in the garage · RS: under the kitchen sink"'::jsonb) where name = 'Oregon Brooklyn Park (OBP)';
update public.houses set notes = jsonb_set(notes, '{dryerVents}', '"Resident: on the roof · RS: on the east end of the house"'::jsonb) where name = 'Oregon Brooklyn Park (OBP)';
update public.houses set notes = jsonb_set(notes, '{dryerVents}', '"RS: comes out at the front of the house under the kitchen window · Resident: on the north side of the house, up high"'::jsonb) where name = 'Redwood';
update public.houses set notes = jsonb_set(notes, '{fireExtinguishers}', '"Resident: laundry closet and in kitchen next to fridge · RS: under kitchen sink, van, garage"'::jsonb) where name = 'Oregon Golden Valley (OGV)';
update public.houses set notes = jsonb_set(notes, '{dryerVents}', '"Resident: roof · RS: on north side of the house"'::jsonb) where name = 'Oregon Golden Valley (OGV)';
update public.houses set notes = jsonb_set(notes, '{fireExtinguishers}', '"(3) One in the van · Resident: in the cabinet right of the fridge · RS: in the cabinet just right of the dishwasher"'::jsonb) where name = 'Riverton';
update public.houses set notes = jsonb_set(notes, '{dryerVents}', '"Resident: super short run straight out on the west side of the house · RS: (not filled in on the sheet)"'::jsonb) where name = 'Riverton';
