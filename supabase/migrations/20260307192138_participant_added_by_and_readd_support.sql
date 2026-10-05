-- 20260307192138_participant_added_by_and_readd_support.sql
-- Exported verbatim from supabase_migrations.schema_migrations on 2026-10-05.
-- This migration was applied to production through the Supabase MCP / dashboard before being committed.


-- Add added_by column to track who added each participant
ALTER TABLE public.conversation_participants
  ADD COLUMN IF NOT EXISTS added_by uuid REFERENCES public.profiles(id);

-- Drop the unique constraint on (conversation_id, user_id) to allow
-- multiple records per user (one active + historical soft-deleted ones).
ALTER TABLE public.conversation_participants
  DROP CONSTRAINT IF EXISTS conversation_participants_conversation_id_user_id_key;

-- Replace with a partial unique index: only one ACTIVE record per user per conversation.
-- Soft-deleted records (left_at IS NOT NULL) are excluded.
CREATE UNIQUE INDEX IF NOT EXISTS conversation_participants_active_unique
  ON public.conversation_participants (conversation_id, user_id)
  WHERE left_at IS NULL;
