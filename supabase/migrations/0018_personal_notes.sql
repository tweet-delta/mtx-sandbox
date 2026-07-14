-- ============================================================================
-- MTX Route Checklist — My notes (private personal checklist)
-- A per-tech scratchpad: shopping lists, reminders, "bring tomorrow" items.
-- Fully private — unlike daily_logs, there is NO supervisor read exception.
-- Spec: docs/superpowers/specs/2026-07-14-my-notes-design.md
-- ============================================================================

create table if not exists public.personal_notes (
  id         uuid primary key default gen_random_uuid(),
  tech_id    uuid not null references public.profiles (id) on delete cascade
               default auth.uid(),
  text       text not null,
  done       boolean not null default false,
  position   int not null default 0,
  created_at timestamptz not null default now(),
  updated_at timestamptz not null default now()
);

-- The list screen queries by tech, ordered by insertion position.
create index if not exists personal_notes_tech_position_idx
  on public.personal_notes (tech_id, position);

alter table public.personal_notes enable row level security;

-- Every policy is scoped to tech_id = auth.uid() with NO supervisor
-- exception — this table is a personal scratchpad, not work history.
create policy personal_notes_select on public.personal_notes
  for select using (tech_id = auth.uid());

create policy personal_notes_insert on public.personal_notes
  for insert with check (tech_id = auth.uid());

create policy personal_notes_update on public.personal_notes
  for update using (tech_id = auth.uid()) with check (tech_id = auth.uid());

create policy personal_notes_delete on public.personal_notes
  for delete using (tech_id = auth.uid());
