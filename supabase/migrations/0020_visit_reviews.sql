-- 0020_visit_reviews.sql — supervisor review stamp on completed visits.
--
-- Two nullable audit columns (every existing completed visit starts
-- unreviewed) + a security-definer RPC so the stamp is trustworthy:
-- reviewed_by is ALWAYS auth.uid(), never client-supplied, and an existing
-- stamp is never overwritten (first review wins). Same precedent as
-- approve_note_suggestion (0008). Reads need no new policy — visits_select
-- (0001) already lets supervisors read every visit.

alter table public.visits
  add column if not exists reviewed_at timestamptz,
  add column if not exists reviewed_by uuid references public.profiles (id);

create or replace function public.mark_visit_reviewed(p_visit_id uuid)
returns void
language plpgsql
security definer set search_path = public
as $$
begin
  if public.current_user_role() is distinct from 'supervisor' then
    raise exception 'Only supervisors can review visits';
  end if;
  update public.visits
     set reviewed_at = now(), reviewed_by = auth.uid()
   where id = p_visit_id
     and status = 'completed'
     and reviewed_at is null;
  if not found then
    raise exception 'Visit not found, not completed, or already reviewed';
  end if;
end;
$$;

grant execute on function public.mark_visit_reviewed(uuid) to authenticated;
