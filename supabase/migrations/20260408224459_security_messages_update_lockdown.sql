-- 20260408224459_security_messages_update_lockdown.sql
-- Exported verbatim from supabase_migrations.schema_migrations on 2026-10-05.
-- This migration was applied to production through the Supabase MCP / dashboard before being committed.


-- Security fix: DROP participant-wide messages UPDATE policy.
-- All message mutations now go through SECURITY DEFINER RPCs:
--   edit_message: checks from_id = auth.uid()
--   unsend_message: checks from_id = auth.uid() + 15-min window
--   mark_messages_read_batch: SECURITY DEFINER, handles read receipts
--
-- Swift call sites have already been switched to RPCs (steps 9a-9c).
-- Direct REST PATCH on messages table will be blocked after this.
--
-- Audit ref: CRIT-4 — any active participant could UPDATE any column
-- on any message in the conversation.

DROP POLICY IF EXISTS "messages_update_participant" ON public.messages;
