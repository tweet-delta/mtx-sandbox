# Level-Specific Note Labels — Design + Full Rewrite Table

**Date:** 2026-07-12
**Status:** Awaiting owner review of the table below

## Problem

Per-item house notes say "Up:", "Upstairs:", "Down:", "Downstairs:" — but which
unit that is depends on the house. Up is the Residents' level everywhere
**except** 92nd Crescent, Amble, Fallgold, McAfee, and Sherwood Place, where
the RS lives on top. Fallgold has three levels (shared basement, Residents
1st, RS 2nd). A tech reading "Upstairs: laundry closet" has to remember which
kind of house they're in.

## Decisions (confirmed with the owner)

- Label format: **who + direction** — `Residents (up):` / `RS (down):`
  (flipped for the five RS-on-top houses; Fallgold uses
  `Residents (1st):` / `RS (2nd):` / `Basement (shared):`).
- Phrases that mean **both levels** ("up and down") just state locations and
  stay exactly as they are.
- Descriptive uses stay ("basement mechanical room", "boiler downstairs",
  "utility room downstairs, outside the RS apartment") — they say where a
  thing is, not whose level a note entry belongs to.
- Scope is the **checklist-item notes** (`houses.notes`) only. The House info
  panel (`houses.info`) rows like "Garbage disposal: Upstairs yes /
  downstairs no" are NOT touched — possible follow-up.

## How it ships

- Migration `0010_level_labels.sql`: one `jsonb_set` per affected note key —
  only the notes listed below change; nothing else on any house row is
  touched. Applied with `supabase db push`.
- The same wording changes go into `route-checklist/house-data.js` (offline
  fallback stays consistent).
- **No app code changes.** Checklist 📍 notes and the House Notes screen
  display whatever the text is.
- Pending tech suggestions on these notes stay pending; approving one later
  overwrites the new wording (a human decision beats a bulk rewrite —
  intended).
- Any hand-edit made in the app to one of these keys before this ships would
  be overwritten — owner confirms none exist at ship time.

## Judgment calls the owner must confirm

| House | What the note said | What I assumed |
|---|---|---|
| Jennifer Court | "under live-in sink" | live-in = RS, on the lower level |
| Tiller Lane | "downstairs apartment" | that apartment = the RS unit |
| Dale Court | everything "in the RS apartment" downstairs | RS = basement level |
| Redwood | "Basement apartment" dryer vent | basement apartment = RS unit |
| Bicentennial | "under sink in basement apartment" | basement apartment = RS unit |

## THE TABLE — review every line

Notation: each changed note shows **Now** (current text) and **New**
(proposed). Houses not listed have no single-level labels to fix.
RS-on-top houses are marked ⚠️ — check those extra carefully.

### Dogwood
- **Fire extinguishers** — Now: `Up: laundry closet · Down: mech room · Garage: by main door · One in the van`
  New: `Residents (up): laundry closet · RS (down): mech room · Garage: by main door · One in the van`
- **Refrigerator coils** — Now: `Upstairs: front · Downstairs: back`
  New: `Residents (up): front · RS (down): back`
- **Dryer vents** — Now: `Upstairs: NW side · Downstairs: NE side under deck`
  New: `Residents (up): NW side · RS (down): NE side under deck`

### Roselawn
- **Fire extinguishers** — Now: `Up: kitchen sink, van, garage · Downstairs: kitchen sink`
  New: `Residents (up): kitchen sink, van, garage · RS (down): kitchen sink`

### 140th Lane East
- **Fire extinguishers** — Now: `Upstairs: back hall by the pantry · Downstairs: storage room off the kitchen, right around the corner`
  New: `Residents (up): back hall by the pantry · RS (down): storage room off the kitchen, right around the corner`
- **Refrigerator coils** — Now: `Upstairs: front of fridge · Downstairs: front of fridge`
  New: `Residents (up): front of fridge · RS (down): front of fridge`

### 140th Lane West
- **Fire extinguishers** — Now: `Upstairs: kitchen, on the wall above the garbage cans · Downstairs: kitchen, on wall by office`
  New: `Residents (up): kitchen, on the wall above the garbage cans · RS (down): kitchen, on wall by office`
- **Refrigerator coils** — Now: `Upstairs: front of the fridge · Downstairs: back of the fridge`
  New: `Residents (up): front of the fridge · RS (down): back of the fridge`

### ⚠️ 92nd Crescent (RS on top)
- **Fire extinguishers** — Now: `Downstairs: kitchen, far right cabinet; one in the van · Upstairs: one under the sink, one in laundry room`
  New: `Residents (down): kitchen, far right cabinet; one in the van · RS (up): one under the sink, one in laundry room`
- **Dryer vents** — Now: `Upstairs: back of the house by patio · Downstairs: by front door`
  New: `RS (up): back of the house by patio · Residents (down): by front door`

### ⚠️ Amble (RS on top)
- **Dryer vents** — Now: `Downstairs: east side of house · Upstairs: back of house, middle vent next to porch (not under it); tall ladder needed`
  New: `Residents (down): east side of house · RS (up): back of house, middle vent next to porch (not under it); tall ladder needed`
- (Fire extinguishers "up and down" = both levels — unchanged.)

### Barclay
- **Dryer vents** — Now: `Residents: above patio door`
  New: `Residents (up): above patio door`

### Bicentennial
- **Fire extinguishers** — Now: `(3) Van · west kitchen wall upstairs · under sink in basement apartment`
  New: `(3) Van · Residents (up): west kitchen wall · RS (down): under the sink in the basement apartment`

### Boutwell
- **Fire extinguishers** — Now: `(3) Van · upstairs under the sink · downstairs under the sink`
  New: `(3) Van · Residents (up): under the sink · RS (down): under the sink`

### Co. Rd. B2
- **Fire extinguishers** — Now: `(5) Van · Upstairs: hallway, under sink, garage · Downstairs: under sink`
  New: `(5) Van · Residents (up): hallway, under sink, garage · RS (down): under sink`
- **Dryer vents** — Now: `Upstairs: on the deck · Downstairs: by the fence for the trash, on the house`
  New: `Residents (up): on the deck · RS (down): by the fence for the trash, on the house`

### Crestridge
- **Dryer vents** — Now: `Upstairs: through the roof · Downstairs: back under the deck (very long run; the downstairs dryer may auto-shut-off — coordinate with the live-in to keep it running while checking)`
  New: `Residents (up): through the roof · RS (down): back under the deck (very long run; the RS dryer may auto-shut-off — coordinate with the live-in to keep it running while checking)`

### Dale Court
- **Fire extinguishers** — Now: `Two: one under the resident-level kitchen sink, one under the basement-level kitchen sink`
  New: `(2) Residents (up): under the kitchen sink · RS (down): under the kitchen sink`
- **Dryer vents** — Now: `Basement dryer vent: south side of the house · Upstairs dryer vent: on the roof`
  New: `RS (down): south side of the house · Residents (up): on the roof`

### Dawn
- **Dryer vents** — Now: `Upstairs: east deck · Downstairs: behind the house on the west side, under the deck where the brick blocks jut out, on top (not the disconnected one tucked way under the deck)`
  New: `Residents (up): east deck · RS (down): behind the house on the west side, under the deck where the brick blocks jut out, on top (not the disconnected one tucked way under the deck)`

### ⚠️ Fallgold (Residents 1st, RS 2nd, shared basement)
- **Fire extinguishers** — Now: `Downstairs: on the cabinet in the kitchen · Upstairs: laundry closet between washer and dryer · Basement: bottom of the stairs · Van`
  New: `Residents (1st): on the cabinet in the kitchen · RS (2nd): laundry closet between washer and dryer · Basement (shared): bottom of the stairs · Van`
- **Refrigerator coils** — Now: `Resident: front side · RS: back of refrigerator`
  New: `Residents (1st): front side · RS (2nd): back of refrigerator`
- **Attic access** — Now: `Attic access: upstairs in the RS apartment hallway; Downstairs: office area (for the garage) and in the hallway`
  New: `Attic access — RS (2nd): apartment hallway · Residents (1st): office area (for the garage) and in the hallway`
- **Dryer vents** — Now: `Upstairs: back of the house above the sunroom · Downstairs: back of the house by the patio`
  New: `RS (2nd): back of the house above the sunroom · Residents (1st): back of the house by the patio`

### Hillcrest
- **Fire extinguishers** — Now: `Upstairs: kitchen wall · Downstairs: attached to wall · in house van`
  New: `Residents (up): kitchen wall · RS (down): attached to wall · in house van`

### Ilex
- **Fire extinguishers** — Now: `(4) Van · Upstairs: right of fridge · Downstairs: just inside utility room and under the kitchen sink`
  New: `(4) Van · Residents (up): right of fridge · RS (down): just inside utility room and under the kitchen sink`

### Jennifer Court
- **Fire extinguishers** — Now: `(4) Normal and grease under upstairs sink · under live-in sink · van`
  New: `(4) Residents (up): normal and grease under the sink · RS (down): under the sink · van`

### Lancaster
- **Fire extinguishers** — Now: `Upstairs: garage · Downstairs: mechanical room`
  New: `Residents (up): garage · RS (down): mechanical room`
- **Dryer vents** — Now: `Upstairs: north end of the house, by the garbage cans · Downstairs: east side of the house in the back yard`
  New: `Residents (up): north end of the house, by the garbage cans · RS (down): east side of the house in the back yard`

### Lydia Ave
- **Fire extinguishers** — Now: `(4) Inside garage by back door · van · upstairs kitchen behind the door · under RS sink`
  New: `(4) Inside garage by back door · van · Residents (up): kitchen behind the door · RS (down): under the sink`

### Lydia West
- **Fire extinguishers** — Now: `(4) Van · Upstairs: kitchen, laundry · Downstairs: under kitchen sink`
  New: `(4) Van · Residents (up): kitchen, laundry · RS (down): under kitchen sink`

### Magnolia
- **Fire extinguishers** — Now: `Upstairs: laundry room by the washing machine · Downstairs: one in mechanical room, one under the kitchen sink`
  New: `Residents (up): laundry room by the washing machine · RS (down): one in mechanical room, one under the kitchen sink`
- **Dryer vents** — Now: `Upstairs: under deck · Downstairs: (see house)`
  New: `Residents (up): under deck · RS (down): (see house)`

### ⚠️ McAfee (RS on top)
- **Dryer vents** — Now: `Resident: south side · RS: back of house`
  New: `Residents (down): south side · RS (up): back of house`
- (Fire extinguishers "up and down" = both levels — unchanged.)

### McMenemy
- **Fire extinguishers** — Now: `Upstairs: under kitchen sink, cleaning closet (by front door), laundry · Downstairs: office, furnace room · Van`
  New: `Residents (up): under kitchen sink, cleaning closet (by front door), laundry · RS (down): office, furnace room · Van`

### Oakwood
- **Fire extinguishers** — Now: `(4) Van · Upstairs: under sink, laundry · Downstairs: (not filled in on the sheet)`
  New: `(4) Van · Residents (up): under sink, laundry · RS (down): (not filled in on the sheet)`

### Regent
- **Fire extinguishers** — Now: `Upstairs: closet in dining room · Downstairs: in the cabinet under the island`
  New: `Residents (up): closet in dining room · RS (down): in the cabinet under the island`
- **Dryer vents** — Now: `Upstairs: on the south wall, under the ramp to the deck · Downstairs: north wall`
  New: `Residents (up): on the south wall, under the ramp to the deck · RS (down): north wall`

### Riverdale
- **Fire extinguishers** — Now: `(6) Van · Upstairs: kitchen (hanging on the wall), laundry (on the wall to the left) · Downstairs: under kitchen sink, closet in the second living room (just right of laundry room) · 1 in the garage`
  New: `(6) Van · Residents (up): kitchen (hanging on the wall), laundry (on the wall to the left) · RS (down): under kitchen sink, closet in the second living room (just right of laundry room) · 1 in the garage`
- **Dryer vents** — Now: `Both on the south side. Right of the faucet in the corner = resident dryer vent; left of the faucet = basement apartment`
  New: `Both on the south side. Residents (up): right of the faucet in the corner · RS (down): left of the faucet`

### Robin Ave
- **Fire extinguishers** — Now: `Upstairs: kitchen and hallway · In the van · Downstairs: under sink and furnace room`
  New: `Residents (up): kitchen and hallway · In the van · RS (down): under sink and furnace room`
- **Dryer vents** — Now: `Upstairs: vented through the roof · Downstairs: vent comes out on the front ramp`
  New: `Residents (up): vented through the roof · RS (down): vent comes out on the front ramp`

### ⚠️ Sherwood Place (RS on top)
- **Fire extinguishers** — Now: `One to the left of downstairs sink · one under the upstairs sink · one mounted on the garage wall · one in the house van`
  New: `Residents (down): left of the sink · RS (up): under the sink · one mounted on the garage wall · one in the house van`
- **Attic access** — Now: `Attic access: upstairs laundry room — will need the 6 ft ladder`
  New: `Attic access — RS (up): laundry room; will need the 6 ft ladder`

### Tiller Lane
- **Fire extinguishers** — Now: `Garage, under kitchen sink, van, downstairs apartment, and laundry room`
  New: `Garage, under kitchen sink, van, RS apartment (down), and laundry room`

### Toledo
- **Fire extinguishers** — Now: `(3) Upstairs: laundry closet · Downstairs: under kitchen sink · One in the van`
  New: `(3) Residents (up): laundry closet · RS (down): under kitchen sink · One in the van`
- **Refrigerator coils** — Now: `Upstairs: front of fridge · Downstairs: back of fridge`
  New: `Residents (up): front of fridge · RS (down): back of fridge`
- **Dryer vents** — Now: `Upstairs: on the back of the house · Downstairs: on the front of the house`
  New: `Residents (up): on the back of the house · RS (down): on the front of the house`

### Valders
- **Fire extinguishers** — Now: `Resident level: above kitchen sink on cabinet · Van: on passenger seat · RS level: under kitchen sink`
  New: `Residents (up): above kitchen sink on cabinet · Van: on passenger seat · RS (down): under kitchen sink`
- **Dryer vents** — Now: `Upstairs: right outside the garage door · Downstairs: right outside the garage door`
  New: `Residents (up): right outside the garage door · RS (down): right outside the garage door`

### Oregon Brooklyn Park (OBP)
- **Fire extinguishers** — Now: `Upstairs: in the kitchen by the cabinet; also one in the garage · Downstairs: under the kitchen sink`
  New: `Residents (up): in the kitchen by the cabinet; also one in the garage · RS (down): under the kitchen sink`
- **Dryer vents** — Now: `Upstairs: on the roof · Downstairs: on the east end of the house`
  New: `Residents (up): on the roof · RS (down): on the east end of the house`

### Redwood
- **Dryer vents** — Now: `Basement apartment: comes out at the front of the house under the kitchen window · Upstairs: on the north side of the house, up high`
  New: `RS (down): comes out at the front of the house under the kitchen window · Residents (up): on the north side of the house, up high`

### Oregon Golden Valley (OGV)
- **Fire extinguishers** — Now: `Resident level: laundry closet and in kitchen next to fridge · RS level: under kitchen sink, van, garage`
  New: `Residents (up): laundry closet and in kitchen next to fridge · RS (down): under kitchen sink, van, garage`
- **Refrigerator coils** — Now: `Upstairs: front/back · Downstairs: front/back`
  New: `Residents (up): front/back · RS (down): front/back`
- **Dryer vents** — Now: `Upstairs: roof · Downstairs: on north side of the house`
  New: `Residents (up): roof · RS (down): on north side of the house`

### Riverton
- **Fire extinguishers** — Now: `(3) One in the van · Upstairs: in the cabinet right of the fridge · Downstairs: in the cabinet just right of the dishwasher`
  New: `(3) One in the van · Residents (up): in the cabinet right of the fridge · RS (down): in the cabinet just right of the dishwasher`
- **Dryer vents** — Now: `Upstairs: super short run straight out on the west side of the house · Downstairs: (not filled in on the sheet)`
  New: `Residents (up): super short run straight out on the west side of the house · RS (down): (not filled in on the sheet)`

### Unchanged houses

16th Avenue, Alta Vista, Brooks, Cummings, Fox Run Bay, Fulham, James,
Larch, Robin Court, Skycroft, Sunbury, Trenton Lane — their notes either
name the unit already, describe locations, or cover both levels.

## Verification

1. Owner reviews this table line by line (they know the buildings).
2. After shipping: on the live site, open Dogwood (normal), McAfee and
   Fallgold (flipped/3-level) — checklist 📍 notes and House Notes screen
   show the new labels.
3. Supabase dashboard spot check: `select name, notes from houses where name
   in ('Dogwood','McAfee','Fallgold');`
