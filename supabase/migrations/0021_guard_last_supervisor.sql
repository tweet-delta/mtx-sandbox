-- ============================================================================
-- 0021_guard_last_supervisor.sql — protect against locking everyone out of
-- supervisor access. Runs ALONGSIDE guard_profile_role (0001, which blocks a
-- tech self-promoting); this trigger blocks two DEMOTIONS:
--   1. a supervisor demoting THEIR OWN account (self-lockout), and
--   2. demoting the LAST remaining supervisor.
-- Dashboard / service_role actions (auth.uid() IS NULL) are exempt, so the
-- owner can always repair roles from the Supabase dashboard.
--
-- HOW TO RUN: supabase db push --workdir "c:\Big Dogs Apps\MTX Checklist V1"
-- Safe to re-run (create or replace / drop trigger if exists).
-- ============================================================================

create or replace function public.guard_last_supervisor()
returns trigger
language plpgsql
security definer set search_path = public
as $$
begin
  -- Only care about a role change that moves AWAY from supervisor.
  if old.role = 'supervisor' and new.role is distinct from 'supervisor' then

    -- Dashboard / service_role (no signed-in user) may do anything.
    if auth.uid() is null then
      return new;
    end if;

    -- 1. You cannot demote your own account.
    if old.id = auth.uid() then
      raise exception 'You cannot remove your own supervisor access.';
    end if;

    -- 2. You cannot demote the last supervisor.
    if (select count(*) from public.profiles where role = 'supervisor') <= 1 then
      raise exception 'Cannot demote the last supervisor.';
    end if;
  end if;

  return new;
end;
$$;

drop trigger if exists guard_last_supervisor on public.profiles;
create trigger guard_last_supervisor
  before update on public.profiles
  for each row execute function public.guard_last_supervisor();

-- ============================================================================
-- No RLS or grant changes: profiles_update (0001) already scopes WHICH rows a
-- supervisor may touch. This trigger only refuses specific role transitions.
-- ============================================================================
