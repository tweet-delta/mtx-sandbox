-- ============================================================================
-- 0009_set_house_field.sql — supervisor direct note edits done server-side
--
-- The client used to rewrite the whole houses.notes / houses.info column from
-- its cached copy — a stale cache could silently revert someone else's
-- change. This RPC patches ONE key/pair on the server's current data, same
-- jsonb logic as approve_note_suggestion in 0008.
--
-- Also hardens 0008's author-update guard trigger: id joins the protected
-- column list (an author could previously rewrite their own reviewed row's
-- primary key).
--
-- Safe to re-run (create-or-replace throughout).
-- ============================================================================

create or replace function public.hns_guard_author_update()
returns trigger
language plpgsql
security definer set search_path = public
as $$
begin
  if public.current_user_role() = 'supervisor' then
    return new;   -- supervisors update via the RPCs; don't restrict them
  end if;
  if new.id            is distinct from old.id
     or new.house_id      is distinct from old.house_id
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

create or replace function public.set_house_field(house_id uuid, target text, note_key text, action text, new_text text)
returns void
language plpgsql
security definer set search_path = public
as $$
declare
  cur_info jsonb;
  idx      int;
begin
  if public.current_user_role() is distinct from 'supervisor' then
    raise exception 'Only a supervisor can edit house notes directly';
  end if;

  if target = 'item' then
    if action = 'delete' then
      update public.houses set notes = coalesce(notes, '{}'::jsonb) - note_key
        where id = house_id;
    else
      update public.houses
        set notes = jsonb_set(coalesce(notes, '{}'::jsonb),
                              array[note_key], to_jsonb(new_text), true)
        where id = house_id;
    end if;

  elsif target = 'info' then
    select info into cur_info from public.houses where id = house_id for update;
    cur_info := coalesce(cur_info, '[]'::jsonb);
    select t.i - 1 into idx
      from jsonb_array_elements(cur_info) with ordinality as t(pair, i)
      where t.pair->>0 = note_key
      limit 1;
    if action = 'delete' then
      if idx is not null then
        cur_info := cur_info - idx;
      end if;
    elsif idx is not null then
      cur_info := jsonb_set(cur_info, array[idx::text, '1'], to_jsonb(new_text));
    else
      cur_info := cur_info
        || jsonb_build_array(jsonb_build_array(note_key, new_text));
    end if;
    update public.houses set info = cur_info where id = house_id;

  else
    raise exception 'Unknown target: %', target;
  end if;
end;
$$;

revoke execute on function public.set_house_field(uuid, text, text, text, text) from public, anon;
grant  execute on function public.set_house_field(uuid, text, text, text, text) to authenticated;
