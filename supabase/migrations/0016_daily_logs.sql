-- ============================================================================
-- MTX Route Checklist — Daily Logs (slice 3 of 4)
-- A per-tech work diary. Auto rows are stamped by saveVisit() each day a tech
-- saves a visit; manual rows are free-text notes the tech adds to any day.
-- Spec: docs/superpowers/specs/2026-07-14-daily-logs-design.md
-- ============================================================================

create table if not exists public.daily_logs (
  id         uuid primary key default gen_random_uuid(),
  tech_id    uuid not null references public.profiles (id) on delete cascade
                default auth.uid(),
  log_date   date not null,
  kind       text not null check (kind in ('auto', 'manual')),
  visit_id   uuid references public.visits (id) on delete cascade,   -- auto only
  house_id   uuid references public.houses (id),                     -- auto only
  note       text not null default '',                               -- manual only
  done_keys  jsonb not null default '[]'::jsonb,                     -- auto only
  created_at timestamptz not null default now(),
  updated_at timestamptz not null default now()
);

-- One auto row per tech + visit + day: repeated Save-progress on the same day
-- refreshes that day's snapshot instead of duplicating it.
create unique index if not exists daily_logs_auto_uniq
  on public.daily_logs (tech_id, visit_id, log_date)
  where kind = 'auto';

-- The month view queries by tech + date range.
create index if not exists daily_logs_tech_date_idx
  on public.daily_logs (tech_id, log_date);

alter table public.daily_logs enable row level security;

-- Read: your own diary, or anything if you're a supervisor.
create policy daily_logs_select on public.daily_logs
  for select using (
    tech_id = auth.uid() or public.current_user_role() = 'supervisor'
  );

-- Insert: only rows you own.
create policy daily_logs_insert on public.daily_logs
  for insert with check (tech_id = auth.uid());

-- Update: only your own rows. Intentionally NOT restricted by `kind` — the
-- auto-stamp upsert resolves its conflict as an UPDATE of your own auto row and
-- must be allowed. User-facing immutability of auto rows is enforced in the app
-- (the UI shows no edit/delete on auto entries, and updateLogEntry/
-- deleteLogEntry self-scope kind='manual'). Ownership is the real boundary here.
create policy daily_logs_update on public.daily_logs
  for update using (tech_id = auth.uid()) with check (tech_id = auth.uid());

-- Delete: only your own rows.
create policy daily_logs_delete on public.daily_logs
  for delete using (tech_id = auth.uid());

-- ----------------------------------------------------------------------------
-- One-time backfill: one auto row per COMPLETED visit, on its visit_date, with
-- the final set of done item_keys. Runs as migration author (RLS bypassed).
-- ON CONFLICT DO NOTHING so re-running the migration is safe.
-- ----------------------------------------------------------------------------
insert into public.daily_logs (tech_id, log_date, kind, visit_id, house_id, done_keys)
select
  v.tech_id,
  v.visit_date,
  'auto',
  v.id,
  v.house_id,
  coalesce(
    (select jsonb_agg(vi.item_key)
       from public.visit_items vi
      where vi.visit_id = v.id and vi.done is true),
    '[]'::jsonb
  )
from public.visits v
where v.status = 'completed'
on conflict (tech_id, visit_id, log_date) where kind = 'auto' do nothing;
