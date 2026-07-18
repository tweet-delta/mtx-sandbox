-- ============================================================================
-- Demo ticket seed — FAKE DATA ONLY (this whole project is a demo; see
-- CLAUDE.md's data boundary). Gives every screen something real to show:
-- all four priorities, all four statuses, assigned + unassigned, a few
-- House Visit List items (they pin to the top of the in-visit panel), and
-- three tickets backdated >40 days so the "Stale 30d+" filter has rows.
--
-- Idempotent: runs only when the tickets table is completely empty, so
-- re-running migrations never duplicates and real demo use is never touched.
-- Houses are picked alphabetically (first 6 active); people by role.
-- ============================================================================

do $$
declare
  h uuid[];                -- first 6 active house ids, alphabetical
  techs uuid[];            -- up to 2 tech profile ids
  sup uuid;                -- one supervisor (falls back to any profile)
  t1 uuid; t2 uuid;        -- convenience: techs[1] / techs[2] (may be null)
  old_t timestamptz := now() - interval '45 days';
begin
  if exists (select 1 from public.tickets) then
    return;
  end if;

  select array_agg(id) into h from (
    select id from public.houses where active order by name limit 6) s;
  select array_agg(id) into techs from (
    select id from public.profiles where role = 'tech' order by full_name limit 2) s;
  select id into sup from public.profiles where role = 'supervisor' limit 1;
  if sup is null then
    select id into sup from public.profiles limit 1;
  end if;
  if h is null or array_length(h, 1) < 1 or sup is null then
    return;   -- nothing sensible to seed against
  end if;
  t1 := techs[1];
  t2 := coalesce(techs[2], techs[1]);

  insert into public.tickets
    (house_id, title, description, category, level, status, priority,
     requested_by_role, submitted_by, assigned_to, created_at, updated_at,
     completed_at, completed_by)
  values
  -- House 1: the busy house — one of each priority
  (h[1], 'Water heater leaking at base',
   'Slow drip from the relief valve, small puddle forming. Shut-off works.',
   'Plumbing', 'resident', 'in_progress', 'urgent', 'rs', sup, t1,
   now() - interval '2 days', now() - interval '1 day', null, null),
  (h[1], 'Replace hallway smoke detector',
   'Chirping with a fresh battery — unit is past its date.',
   'Electrical', 'resident', 'new', 'time_sensitive', 'pd', sup, t2,
   now() - interval '1 day', now() - interval '1 day', null, null),
  (h[1], 'Adjust closet door in room 3',
   'Rubbing the frame; hard for staff to open quietly at night.',
   'House Visit List', 'resident', 'new', 'normal', 'staff', sup, null,
   now() - interval '4 days', now() - interval '4 days', null, null),
  (h[1], 'Paint accent wall in dining room',
   'RS would love a calmer color someday.',
   'Interior Painting', 'resident', 'new', 'wish_list', 'rs', sup, null,
   now() - interval '6 days', now() - interval '6 days', null, null),

  -- House 2 (falls back to house 1 if fewer than 6 houses exist — coalesce below)
  (coalesce(h[2], h[1]), 'Screen door latch broken',
   'Latch does not catch; door blows open in wind.',
   'Doors', 'rs', 'new', 'normal', 'live_in', sup, t1,
   now() - interval '3 days', now() - interval '3 days', null, null),
  (coalesce(h[2], h[1]), 'Dryer squealing on long cycles',
   'Belt noise after ~20 minutes. Still drying fine.',
   'Appliance Issues', 'resident', 'on_hold', 'normal', 'staff', sup, t1,
   now() - interval '12 days', now() - interval '9 days', null, null),
  (coalesce(h[2], h[1]), 'Check gutter over back entry',
   'Overflowing at the corner in heavy rain.',
   'House Visit List', 'resident', 'new', 'normal', 'maintenance', sup, null,
   now() - interval '8 days', now() - interval '8 days', null, null),

  -- House 3
  (coalesce(h[3], h[1]), 'Ants in kitchen near sink',
   'Small trail along the back splash each morning.',
   'Pest Control', 'resident', 'new', 'time_sensitive', 'rc', sup, null,
   now() - interval '2 days', now() - interval '2 days', null, null),
  (coalesce(h[3], h[1]), 'Wobbly handrail on front steps',
   'Top bracket loose — safety issue for residents.',
   'Railings', 'resident', 'in_progress', 'urgent', 'guardian', sup, t2,
   now() - interval '5 days', now() - interval '2 days', null, null),
  (coalesce(h[3], h[1]), 'New bird feeder pole',
   'Residents would enjoy one visible from the sunroom.',
   'Landscaping', 'resident', 'new', 'wish_list', 'staff', sup, null,
   now() - interval '10 days', now() - interval '10 days', null, null),

  -- House 4
  (coalesce(h[4], h[1]), 'Bathroom fan rattling',
   'Main bath exhaust fan is loud; residents startled.',
   'Other Bathroom Issues', 'resident', 'new', 'normal', 'rs', sup, t2,
   now() - interval '7 days', now() - interval '7 days', null, null),
  (coalesce(h[4], h[1]), 'Haul away old box spring',
   'In the garage, replaced last month.',
   'Items to Haul Away', 'rs', 'new', 'normal', 'rs', sup, null,
   now() - interval '9 days', now() - interval '9 days', null, null),
  (coalesce(h[4], h[1]), 'Tighten kitchen cabinet hinges',
   'Two doors sagging by the stove.',
   'House Visit List', 'resident', 'new', 'normal', 'maintenance', sup, null,
   now() - interval '11 days', now() - interval '11 days', null, null),

  -- House 5
  (coalesce(h[5], h[1]), 'Sidewalk crack lifting near ramp',
   'Trip hazard forming at the expansion joint.',
   'Sidewalk or Driveway', 'resident', 'new', 'time_sensitive', 'pd', sup, null,
   now() - interval '3 days', now() - interval '3 days', null, null),
  (coalesce(h[5], h[1]), 'Replace burnt-out flood light',
   'Backyard flood light out; dark by the patio door.',
   'Electrical', 'rs', 'new', 'normal', 'live_in', sup, t1,
   now() - interval '6 days', now() - interval '6 days', null, null),

  -- House 6
  (coalesce(h[6], h[1]), 'Touch up deck stain before fall',
   'South rail is graying; one more season in it.',
   'Deck Sealing or Repair', 'resident', 'new', 'wish_list', 'rs', sup, null,
   now() - interval '14 days', now() - interval '14 days', null, null),
  (coalesce(h[6], h[1]), 'Fridge coils cleaning overdue',
   'Add to the next visit sweep.',
   'House Visit List', 'resident', 'new', 'normal', 'maintenance', sup, null,
   now() - interval '5 days', now() - interval '5 days', null, null),

  -- Stale demos: untouched for 45 days (Stale chip needs ≥3 rows)
  (h[1], 'Garage weather-strip replacement',
   'Bottom seal torn; leaves blow in.',
   'Carpentry', 'resident', 'new', 'normal', 'maintenance', sup, null,
   old_t, old_t, null, null),
  (coalesce(h[2], h[1]), 'Basement window well cover',
   'Cover cracked; replace before winter.',
   'Windows', 'resident', 'new', 'wish_list', 'rs', sup, null,
   old_t, old_t, null, null),
  (coalesce(h[3], h[1]), 'Quote for driveway extension',
   'PD asked for a rough cost to widen parking.',
   'Sidewalk or Driveway', 'resident', 'on_hold', 'normal', 'pd', sup, null,
   old_t, old_t, null, null),

  -- Completed history demos
  (h[1], 'Reset tripped GFCI in garage',
   'Outlet dead by the workbench.',
   'Electrical', 'resident', 'completed', 'normal', 'staff', sup, t1,
   now() - interval '20 days', now() - interval '18 days',
   now() - interval '18 days', t1),
  (coalesce(h[4], h[1]), 'Rehang bedroom blinds',
   'Bracket pulled out of drywall.',
   'Windows', 'resident', 'completed', 'time_sensitive', 'rs', sup, t2,
   now() - interval '25 days', now() - interval '22 days',
   now() - interval '22 days', t2);

  -- A little history so the detail screen's trail isn't empty.
  insert into public.ticket_notes (ticket_id, author, kind, body, created_at)
  select t.id, sup, 'assignment',
         coalesce((select nullif(full_name,'') from public.profiles where id = t.assigned_to), 'a teammate'),
         t.created_at + interval '1 hour'
    from public.tickets t where t.assigned_to is not null;

  insert into public.ticket_notes (ticket_id, author, kind, body, created_at)
  select t.id, coalesce(t.assigned_to, sup), 'comment',
         'Looked at this during the last stop — parts ordered.',
         t.updated_at - interval '1 hour'
    from public.tickets t where t.status = 'in_progress';
end;
$$;
