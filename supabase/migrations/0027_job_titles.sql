-- ============================================================================
-- 0027_job_titles.sql — a supervisor-managed list of official job titles.
-- Spec: docs/superpowers/specs/2026-07-18-managed-job-titles-design.md
--
-- Replaces the free-text profiles.job_title (0022) with a real table + FK so
-- titles are consistent, renamable everywhere at once, and carry a `kind`
-- (field/office) that decides a person's home screen. Permissions attach here
-- LATER (Slice 2). The old text column is KEPT but unused for one release as a
-- recovery net; a later migration drops it once the backfill is confirmed good.
--
-- HOW TO RUN: supabase db push --workdir "c:\Big Dogs Apps\MTX Checklist V1"
-- Safe to re-run (if not exists / on conflict do nothing).
-- ============================================================================

create table if not exists public.job_titles (
  id         uuid primary key default gen_random_uuid(),
  name       text not null check (length(trim(name)) > 0),
  kind       text not null default 'field' check (kind in ('field','office')),
  active     boolean not null default true,
  created_at timestamptz not null default now()
);

-- Case-insensitive uniqueness: "Lead Tech" and "lead tech" can't both exist.
create unique index if not exists job_titles_name_lower_idx
  on public.job_titles (lower(name));

alter table public.profiles
  add column if not exists job_title_id uuid references public.job_titles (id);

-- ---------------------------------------------------------------------------
-- Row-Level Security. Everyone signed in reads the list (dropdowns + labels);
-- only supervisors create/edit titles. No delete policy — titles are retired
-- (active=false), never deleted, so the FK can't orphan a profile.
-- ---------------------------------------------------------------------------
alter table public.job_titles enable row level security;

create policy job_titles_select on public.job_titles
  for select using (auth.uid() is not null);

create policy job_titles_insert on public.job_titles
  for insert with check (public.current_user_role() = 'supervisor');

create policy job_titles_update on public.job_titles
  for update using  (public.current_user_role() = 'supervisor')
             with check (public.current_user_role() = 'supervisor');

-- Auto-expose is OFF in this project, so grant table access explicitly.
grant select, insert, update on public.job_titles to authenticated;

-- ---------------------------------------------------------------------------
-- Backfill: one job_titles row per distinct non-empty existing text title
-- (kind='field' — everyone today is a field tech), then point each profile at
-- its matching row. Idempotent: re-running inserts nothing new and re-links
-- the same rows.
-- ---------------------------------------------------------------------------
insert into public.job_titles (name, kind)
select distinct trim(job_title), 'field'
from public.profiles
where job_title is not null and trim(job_title) <> ''
on conflict (lower(name)) do nothing;

update public.profiles p
set job_title_id = jt.id
from public.job_titles jt
where p.job_title is not null
  and trim(p.job_title) <> ''
  and lower(trim(p.job_title)) = lower(jt.name)
  and p.job_title_id is null;
