-- 20260718020610_20260717_0007_apply_participant_mute_columns.sql
-- Exported verbatim from supabase_migrations.schema_migrations on 2026-10-05.
-- This migration was applied to production through the Supabase MCP / dashboard before being committed.

-- The 20260307_0001 migration was only partially applied (added_by exists, mute columns do not),
-- leaving ConversationMuteService writing to non-existent columns — mute is broken on live.
-- Re-apply idempotently to add the missing mute / read-receipt columns.
ALTER TABLE public.conversation_participants
  ADD COLUMN IF NOT EXISTS added_by uuid REFERENCES public.profiles(id);

ALTER TABLE public.conversation_participants
  ADD COLUMN IF NOT EXISTS notifications_muted boolean NOT NULL DEFAULT false;

ALTER TABLE public.conversation_participants
  ADD COLUMN IF NOT EXISTS muted_until timestamptz;

ALTER TABLE public.conversation_participants
  ADD COLUMN IF NOT EXISTS show_read_receipts boolean;
