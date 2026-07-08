# Change Notes — Route Checklist

Requested changes only. Owner will hand off from here.

> **Status — implemented 2026-07-08** (needs migration `0003_dated_items_and_temps.sql`
> run in the Supabase dashboard; see below). Water-temp decided as **number only**.
> Date-tracked set = med-lock batteries, water-alarm batteries, both fire
> extinguishers (kitchen + common), smoke/CO2 detector dates, furnace filter.
> One open item still parked: see "Water temps" note kept for reference.

**Global rule:** every checkbox item keeps a free-text **note** field.
_(Already true — every item, checkbox or Yes/No, has a ✎ Note.)_

## Date-tracked items (medlock battery, water-alarm batteries, fire-extinguisher date, etc.)
- Add an **Update** button → opens a **date picker**; tech enters the actual date done (not auto-today).

## Water temps
- On **checkbox click**, reveal an **input field** to enter the temp reading.
- Open Q: does temp also record a date, or number only?

## Make these simple checkboxes (each keeps a note)
- Change lightbulbs
- Patching and painting
- Toilet + sink plungers
- Attic
- Cabinets & drawers
- Felt protectors on table and chairs
- Faucet + showerhead working
- Every item in the **Bedroom** group (each its own checkbox)

## Saving (visits span multiple days)
- **Save progress**: mid-visit save, anytime; persists across days/devices to resume.
- **Complete end-of-visit survey** = finalize/"big save" (eventually goes to supervisors).
