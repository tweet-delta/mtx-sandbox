-- ============================================================================
-- MTX Route Checklist — Maintenance tickets.
-- Spec: docs/superpowers/specs/2026-07-18-maintenance-tickets-design.md
--
-- Mirrors the company's SharePoint "Current Maintenance Requests" list shape
-- (statuses, priorities, levels, requester roles, categories) so a someday
-- migration into company M365 is a plain data copy. DEMO DATA ONLY lives here.
--
-- Three tables:
--   tickets       — one row per request.
--   ticket_notes  — the per-ticket history trail: human comments PLUS system
--                   rows ("status_change", "assignment") written by the RPCs,
--                   so every ticket shows who did what, when.
--   notifications — one row per person-to-tell: you were assigned / someone
--                   commented on a ticket you're involved in.
--
-- Write rules (RLS + RPCs, the UI is never the enforcement):
--   * anyone signed in can read all tickets/notes and create tickets/comments
--   * techs change STATUS only, via the set_ticket_status RPC (audited)
--   * only supervisors assign, re-prioritize, or edit fields (direct update)
--   * you can only see / mark-read your own notifications
-- ============================================================================

create table if not exists public.tickets (
  id                uuid primary key default gen_random_uuid(),
  house_id          uuid not null references public.houses (id),
  title             text not null check (length(trim(title)) > 0),
  description       text not null default '',
  category          text not null check (category in (
    'Flooring','Plumbing','Doors','Windows','Electrical','Appliance Issues',
    'Landscaping','Pest Control','Carpentry','Gutters','Fences','Roofing',
    'Ceiling','Railings','Decorating','Furniture','Interior Painting',
    'Exterior Painting','Deck Sealing or Repair','Sidewalk or Driveway',
    'Tree Trimming or Removal','Items to Haul Away','Fire Extinguisher',
    'Van or Vehicle Issues','Other Bathroom Issues','Other Kitchen Issues',
    'Other/Unsure','House Visit List')),
  level             text not null default 'resident'
                      check (level in ('resident','rs')),
  status            text not null default 'new'
                      check (status in ('new','in_progress','on_hold','completed')),
  priority          text not null default 'normal'
                      check (priority in ('urgent','time_sensitive','normal','wish_list')),
  requested_by_role text not null default 'staff'
                      check (requested_by_role in
                        ('rs','pd','rc','staff','guardian','live_in','maintenance')),
  submitted_by      uuid not null references public.profiles (id) default auth.uid(),
  assigned_to       uuid references public.profiles (id),
  created_at        timestamptz not null default now(),
  updated_at        timestamptz not null default now(),
  completed_at      timestamptz,
  completed_by      uuid references public.profiles (id)
);

create index if not exists tickets_house_idx    on public.tickets (house_id);
create index if not exists tickets_assigned_idx on public.tickets (assigned_to);
create index if not exists tickets_status_idx   on public.tickets (status);

create table if not exists public.ticket_notes (
  id         uuid primary key default gen_random_uuid(),
  ticket_id  uuid not null references public.tickets (id) on delete cascade,
  author     uuid not null references public.profiles (id) default auth.uid(),
  kind       text not null default 'comment'
               check (kind in ('comment','status_change','assignment')),
  body       text not null default '',
  created_at timestamptz not null default now()
);

create index if not exists ticket_notes_ticket_idx
  on public.ticket_notes (ticket_id, created_at);

create table if not exists public.notifications (
  id         uuid primary key default gen_random_uuid(),
  recipient  uuid not null references public.profiles (id) on delete cascade,
  ticket_id  uuid not null references public.tickets (id) on delete cascade,
  kind       text not null check (kind in ('assigned','comment')),
  actor      uuid references public.profiles (id),
  created_at timestamptz not null default now(),
  read_at    timestamptz
);

create index if not exists notifications_recipient_idx
  on public.notifications (recipient, read_at, created_at);

-- ---------------------------------------------------------------------------
-- Row-Level Security
-- ---------------------------------------------------------------------------
alter table public.tickets       enable row level security;
alter table public.ticket_notes  enable row level security;
alter table public.notifications enable row level security;

-- Everyone signed in sees every ticket (that's the point of a shared queue).
create policy tickets_select on public.tickets
  for select using (auth.uid() is not null);

-- Anyone signed in can file a ticket, but only as themselves.
create policy tickets_insert on public.tickets
  for insert with check (submitted_by = auth.uid());

-- Direct UPDATE is supervisor-only (assign / priority / edits). Techs change
-- status through the set_ticket_status RPC below, which audits the change.
create policy tickets_update on public.tickets
  for update using  (public.current_user_role() = 'supervisor')
             with check (public.current_user_role() = 'supervisor');

-- No delete policy: tickets are never deleted, only completed.

create policy ticket_notes_select on public.ticket_notes
  for select using (auth.uid() is not null);

-- Humans insert only their own COMMENT rows; system rows (status_change /
-- assignment) come from the security-definer RPCs, which bypass RLS.
create policy ticket_notes_insert on public.ticket_notes
  for insert with check (author = auth.uid() and kind = 'comment');

-- Your notifications are yours alone; "update" = stamping read_at.
create policy notifications_select on public.notifications
  for select using (recipient = auth.uid());
create policy notifications_update on public.notifications
  for update using  (recipient = auth.uid())
             with check (recipient = auth.uid());

-- Auto-expose is OFF in this project, so grant table access explicitly.
grant select, insert, update on public.tickets       to authenticated;
grant select, insert         on public.ticket_notes  to authenticated;
grant select, update         on public.notifications to authenticated;

-- ---------------------------------------------------------------------------
-- updated_at upkeep. "Stale ≥30 days" is computed from updated_at, so it must
-- move on every meaningful touch: any ticket update, and any new note.
-- ---------------------------------------------------------------------------
create or replace function public.touch_ticket_updated_at()
returns trigger language plpgsql as $$
begin
  new.updated_at := now();
  return new;
end;
$$;

create trigger tickets_touch before update on public.tickets
  for each row execute function public.touch_ticket_updated_at();

-- Security definer: a tech adding a comment may not UPDATE tickets directly,
-- but the note still has to freshen the ticket's updated_at.
create or replace function public.touch_ticket_on_note()
returns trigger
language plpgsql security definer set search_path = public
as $$
begin
  update public.tickets set updated_at = now() where id = new.ticket_id;
  return new;
end;
$$;

create trigger ticket_notes_touch after insert on public.ticket_notes
  for each row execute function public.touch_ticket_on_note();

-- ---------------------------------------------------------------------------
-- Comment fan-out: a new human comment notifies the ticket's submitter, its
-- assignee, and every supervisor — minus the comment's author. Security
-- definer because recipients are other people's notification rows.
-- ---------------------------------------------------------------------------
create or replace function public.notify_on_ticket_comment()
returns trigger
language plpgsql security definer set search_path = public
as $$
begin
  if new.kind <> 'comment' then return new; end if;
  insert into public.notifications (recipient, ticket_id, kind, actor)
  select distinct w.who, new.ticket_id, 'comment', new.author
  from (
    select t.submitted_by as who from public.tickets t where t.id = new.ticket_id
    union
    select t.assigned_to from public.tickets t
      where t.id = new.ticket_id and t.assigned_to is not null
    union
    select p.id from public.profiles p where p.role = 'supervisor'
  ) w
  where w.who is not null and w.who <> new.author;
  return new;
end;
$$;

create trigger ticket_notes_notify after insert on public.ticket_notes
  for each row execute function public.notify_on_ticket_comment();

-- ---------------------------------------------------------------------------
-- RPC: any signed-in user changes a ticket's status. Always writes a
-- status_change note (the audit trail), stamps/clears the completed marks.
-- The note body carries the machine token ('in_progress'); the UI renders
-- the friendly label.
-- ---------------------------------------------------------------------------
create or replace function public.set_ticket_status(p_ticket_id uuid, p_status text)
returns void
language plpgsql security definer set search_path = public
as $$
begin
  if auth.uid() is null then
    raise exception 'Not signed in';
  end if;
  if p_status not in ('new','in_progress','on_hold','completed') then
    raise exception 'Unknown status %', p_status;
  end if;
  update public.tickets
     set status       = p_status,
         completed_at = case when p_status = 'completed' then now() end,
         completed_by = case when p_status = 'completed' then auth.uid() end
   where id = p_ticket_id;
  if not found then
    raise exception 'Ticket not found';
  end if;
  insert into public.ticket_notes (ticket_id, author, kind, body)
  values (p_ticket_id, auth.uid(), 'status_change', p_status);
end;
$$;

grant execute on function public.set_ticket_status(uuid, text) to authenticated;

-- ---------------------------------------------------------------------------
-- RPC: supervisor (re)assigns a ticket. Null = back to Unassigned. Writes an
-- assignment note and notifies the new assignee (unless they did it themselves).
-- ---------------------------------------------------------------------------
create or replace function public.assign_ticket(p_ticket_id uuid, p_assignee uuid)
returns void
language plpgsql security definer set search_path = public
as $$
declare
  v_name text;
begin
  if public.current_user_role() is distinct from 'supervisor' then
    raise exception 'Only supervisors can assign tickets';
  end if;
  update public.tickets set assigned_to = p_assignee where id = p_ticket_id;
  if not found then
    raise exception 'Ticket not found';
  end if;
  if p_assignee is null then
    v_name := 'unassigned';
  else
    select coalesce(nullif(full_name, ''), 'a teammate')
      into v_name from public.profiles where id = p_assignee;
    if v_name is null then
      raise exception 'Assignee not found';
    end if;
  end if;
  insert into public.ticket_notes (ticket_id, author, kind, body)
  values (p_ticket_id, auth.uid(), 'assignment', v_name);
  if p_assignee is not null and p_assignee <> auth.uid() then
    insert into public.notifications (recipient, ticket_id, kind, actor)
    values (p_assignee, p_ticket_id, 'assigned', auth.uid());
  end if;
end;
$$;

grant execute on function public.assign_ticket(uuid, uuid) to authenticated;
