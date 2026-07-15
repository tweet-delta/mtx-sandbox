-- ============================================================================
-- MTX Route Checklist — My notes: add title, drop the checkbox/done concept
-- Follow-on to 0018_personal_notes.sql. Notes become titled cards (title
-- optional, body required) instead of a checklist — no more "done" state.
-- Spec: docs/superpowers/specs/2026-07-14-my-notes-titled-editable-design.md
-- ============================================================================

alter table public.personal_notes
  add column if not exists title text not null default '';

alter table public.personal_notes
  drop column if exists done;
