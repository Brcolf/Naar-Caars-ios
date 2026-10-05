-- 20260408213903_security_messages_select_bounds.sql
-- Exported verbatim from supabase_migrations.schema_migrations on 2026-10-05.
-- This migration was applied to production through the Supabase MCP / dashboard before being committed.


-- Security fix: Add joined_at and left_at bounds to messages SELECT policy.
-- Preserves the existing hidden_at visibility rule verbatim.
--
-- Live state before this migration:
--   EXISTS(conversation_participants WHERE user_id = auth.uid())
--   AND ((hidden_at IS NULL) OR (from_id = auth.uid()))
--
-- Problem: no time bounds — former participants can read all messages forever.
-- Fix: add created_at >= cp.joined_at AND (cp.left_at IS NULL OR created_at <= cp.left_at)
-- Audit ref: HIGH-1 (corrected for live).

DROP POLICY IF EXISTS "Users can view messages in their conversations" ON public.messages;

CREATE POLICY "Users can view messages in their conversations" ON public.messages
  FOR SELECT TO authenticated
  USING (
    (
      EXISTS (
        SELECT 1 FROM public.conversation_participants cp
        WHERE cp.conversation_id = messages.conversation_id
          AND cp.user_id = auth.uid()
          AND messages.created_at >= cp.joined_at
          AND (cp.left_at IS NULL OR messages.created_at <= cp.left_at)
      )
    )
    AND
    (
      (hidden_at IS NULL) OR (from_id = auth.uid())
    )
  );
