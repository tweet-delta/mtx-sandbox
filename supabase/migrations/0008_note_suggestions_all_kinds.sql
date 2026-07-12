-- ============================================================================
-- 0008_note_suggestions_all_kinds.sql — suggestions for ALL house-note kinds
--
-- Migration 0006 built suggest/approve for the freeform general note only.
-- This generalizes the same table + RPC to the per-item notes (houses.notes
-- jsonb) and the house-info pairs (houses.info jsonb), and adds:
--   * action 'delete' — a tech can propose REMOVING a stale note.
--   * deny_reason — supervisor's optional reason; the author sees it.
--   * seen_by_author — author dismisses the denial notice (row is kept:
--     reviewed rows are the audit trail and are never deleted).
--
-- Safe to re-run (if-not-exists / drop-if-exists / create-or-replace).
-- ============================================================================

-- 1. New columns. Defaults make every pre-0008 row a valid 'general' edit.
alter table public.house_note_suggestions
  add column if not exists target text not null default 'general',
  add column if not exists note_key text not null default '',
  add column if not exists action text not null default 'set',
  add column if not exists deny_reason text not null default '',
  add column if not exists seen_by_author boolean not null default false;

alter table public.house_note_suggestions
  drop constraint if exists hns_target_ck;
alter table public.house_note_suggestions
  add constraint hns_target_ck check (target in ('general', 'item', 'info'));

alter table public.house_note_suggestions
  drop constraint if exists hns_action_ck;
alter table public.house_note_suggestions
  add constraint hns_action_ck check (action in ('set', 'delete'));

-- general notes are edited (possibly to empty), never key-addressed or
-- deleted; item/info suggestions must say WHICH note they mean.
alter table public.house_note_suggestions
  drop constraint if exists hns_target_key_ck;
alter table public.house_note_suggestions
  add constraint hns_target_key_ck check (
    (target = 'general' and note_key = '' and action = 'set')
    or (target in ('item', 'info') and note_key <> '')
  );

-- 2. Authors may update their own REVIEWED rows... (policy) but a trigger
--    below restricts that update to flipping seen_by_author — nothing else.
drop policy if exists hns_update_author_seen on public.house_note_suggestions;
create policy hns_update_author_seen on public.house_note_suggestions
  for update to authenticated
  using (author_id = auth.uid() and status <> 'pending')
  with check (author_id = auth.uid() and status <> 'pending');

create or replace function public.hns_guard_author_update()
returns trigger
language plpgsql
security definer set search_path = public
as $$
begin
  if public.current_user_role() = 'supervisor' then
    return new;   -- supervisors update via the RPCs; don't restrict them
  end if;
  if new.house_id       is distinct from old.house_id
     or new.author_id     is distinct from old.author_id
     or new.author_name   is distinct from old.author_name
     or new.proposed_text is distinct from old.proposed_text
     or new.status        is distinct from old.status
     or new.created_at    is distinct from old.created_at
     or new.reviewed_by   is distinct from old.reviewed_by
     or new.reviewed_at   is distinct from old.reviewed_at
     or new.target        is distinct from old.target
     or new.note_key      is distinct from old.note_key
     or new.action        is distinct from old.action
     or new.deny_reason   is distinct from old.deny_reason then
    raise exception 'Only seen_by_author can be changed';
  end if;
  return new;
end;
$$;

drop trigger if exists hns_guard_author_update on public.house_note_suggestions;
create trigger hns_guard_author_update
  before update on public.house_note_suggestions
  for each row execute function public.hns_guard_author_update();

-- 3. Atomic approve, now target-aware. SECURITY DEFINER + its own role check,
--    so Postgres (not the UI) stops non-supervisors.
create or replace function public.approve_note_suggestion(suggestion_id uuid)
returns void
language plpgsql
security definer set search_path = public
as $$
declare
  s        public.house_note_suggestions%rowtype;
  cur_info jsonb;
  idx      int;
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

  if s.target = 'general' then
    update public.houses set general_notes = s.proposed_text
      where id = s.house_id;

  elsif s.target = 'item' then
    if s.action = 'delete' then
      -- removing an already-removed key is a harmless no-op: same end state.
      update public.houses set notes = coalesce(notes, '{}'::jsonb) - s.note_key
        where id = s.house_id;
    else
      update public.houses
        set notes = jsonb_set(coalesce(notes, '{}'::jsonb),
                              array[s.note_key], to_jsonb(s.proposed_text), true)
        where id = s.house_id;
    end if;

  else  -- 'info': [label, detail] pairs; operations target the FIRST pair
        -- whose label matches (set semantics: add-with-existing-label = edit).
    select info into cur_info from public.houses where id = s.house_id for update;
    cur_info := coalesce(cur_info, '[]'::jsonb);
    select t.i - 1 into idx
      from jsonb_array_elements(cur_info) with ordinality as t(pair, i)
      where t.pair->>0 = s.note_key
      limit 1;
    if s.action = 'delete' then
      if idx is not null then
        cur_info := cur_info - idx;
      end if;
    elsif idx is not null then
      cur_info := jsonb_set(cur_info, array[idx::text, '1'],
                            to_jsonb(s.proposed_text));
    else
      cur_info := cur_info
        || jsonb_build_array(jsonb_build_array(s.note_key, s.proposed_text));
    end if;
    update public.houses set info = cur_info where id = s.house_id;
  end if;

  update public.house_note_suggestions
    set status = 'approved', reviewed_by = auth.uid(), reviewed_at = now()
    where id = suggestion_id;
end;
$$;

revoke execute on function public.approve_note_suggestion(uuid) from public, anon;
grant  execute on function public.approve_note_suggestion(uuid) to authenticated;

-- 4. Deny: reason + review stamp in one statement, same locking discipline.
create or replace function public.deny_note_suggestion(suggestion_id uuid, reason text default '')
returns void
language plpgsql
security definer set search_path = public
as $$
declare
  s public.house_note_suggestions%rowtype;
begin
  if public.current_user_role() is distinct from 'supervisor' then
    raise exception 'Only a supervisor can deny suggestions';
  end if;
  select * into s from public.house_note_suggestions
    where id = suggestion_id and status = 'pending'
    for update;
  if not found then
    raise exception 'Suggestion not found or already reviewed';
  end if;
  update public.house_note_suggestions
    set status = 'dismissed', deny_reason = coalesce(reason, ''),
        reviewed_by = auth.uid(), reviewed_at = now()
    where id = suggestion_id;
end;
$$;

revoke execute on function public.deny_note_suggestion(uuid, text) from public, anon;
grant  execute on function public.deny_note_suggestion(uuid, text) to authenticated;
