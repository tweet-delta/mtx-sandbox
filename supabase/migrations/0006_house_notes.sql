-- ============================================================================
-- 0006_house_notes.sql — House Notes: freeform general notes + suggest/approve
--
-- Adds:
--   1. houses.general_notes — the OFFICIAL freeform note per house.
--   2. house_note_suggestions — a tech's proposed replacement text. The
--      original note is untouched until a supervisor approves. Reviewed rows
--      are kept (status approved/dismissed) as an audit trail.
--   3. approve_note_suggestion(uuid) — supervisor-only, atomic: copies the
--      proposed text into houses.general_notes AND marks the suggestion
--      approved in one transaction, so a dropped connection can't half-apply.
--
-- Safe to re-run (create-if-not-exists / drop-policy-if-exists throughout).
-- ============================================================================

-- 1. The official note lives on the house row itself.
alter table public.houses
  add column if not exists general_notes text not null default '';

-- 2. Proposed updates. author_name is denormalized on purpose: RLS lets a
--    tech read only their OWN profiles row, so a join to profiles would show
--    blank names to other techs. Snapshotting the name at insert time is
--    simpler and doubles as history (name at the time of writing).
create table if not exists public.house_note_suggestions (
  id            uuid primary key default gen_random_uuid(),
  house_id      uuid not null references public.houses (id) on delete cascade,
  author_id     uuid not null references public.profiles (id) default auth.uid(),
  author_name   text not null default '',
  proposed_text text not null,
  status        text not null default 'pending'
                check (status in ('pending', 'approved', 'dismissed')),
  created_at    timestamptz not null default now(),
  reviewed_by   uuid references public.profiles (id),
  reviewed_at   timestamptz
);
create index if not exists hns_house_status_idx
  on public.house_note_suggestions (house_id, status);

-- 3. RLS: the database enforces who can do what — the UI only *hides* things.
alter table public.house_note_suggestions enable row level security;

-- Everyone signed in sees all suggestions (so techs don't re-suggest the
-- same fix someone already proposed).
drop policy if exists hns_select on public.house_note_suggestions;
create policy hns_select on public.house_note_suggestions
  for select to authenticated using (true);

-- You can only file suggestions as yourself.
drop policy if exists hns_insert on public.house_note_suggestions;
create policy hns_insert on public.house_note_suggestions
  for insert to authenticated
  with check (author_id = auth.uid());

-- You can withdraw (delete) your own suggestion while it's still pending.
drop policy if exists hns_delete_own_pending on public.house_note_suggestions;
create policy hns_delete_own_pending on public.house_note_suggestions
  for delete to authenticated
  using (author_id = auth.uid() and status = 'pending');

-- Only supervisors change suggestion rows (approve/dismiss set status +
-- reviewed_by/reviewed_at).
drop policy if exists hns_update_supervisor on public.house_note_suggestions;
create policy hns_update_supervisor on public.house_note_suggestions
  for update to authenticated
  using (public.current_user_role() = 'supervisor')
  with check (public.current_user_role() = 'supervisor');

-- Auto-expose is OFF in this project, so grant table access explicitly.
-- (RLS above still decides which ROWS each person can touch.)
grant select, insert, update, delete
  on public.house_note_suggestions to authenticated;

-- 4. Atomic approve. SECURITY DEFINER so it can update houses + the
--    suggestion in one transaction; it re-checks the caller's role itself,
--    so it grants nothing to non-supervisors.
create or replace function public.approve_note_suggestion(suggestion_id uuid)
returns void
language plpgsql
security definer set search_path = public
as $$
declare
  s public.house_note_suggestions%rowtype;
begin
  if public.current_user_role() is distinct from 'supervisor' then
    raise exception 'Only a supervisor can approve suggestions';
  end if;
  select * into s from public.house_note_suggestions
    where id = suggestion_id and status = 'pending'
    for update;
  if not found then
    raise exception 'Suggestion not found or already reviewed';
  end if;
  update public.houses
    set general_notes = s.proposed_text
    where id = s.house_id;
  update public.house_note_suggestions
    set status = 'approved', reviewed_by = auth.uid(), reviewed_at = now()
    where id = suggestion_id;
end;
$$;

revoke execute on function public.approve_note_suggestion(uuid) from public, anon;
grant  execute on function public.approve_note_suggestion(uuid) to authenticated;
