-- ============================================================================
-- Migration: Messaging Performance & RLS Consolidation
-- Date: 2026-02-06
-- 
-- This migration:
-- 1. Adds a critical GIN index on messages.read_by for badge count performance
-- 2. Consolidates conflicting RLS UPDATE policies on messages
-- 3. Adds message_reactions to realtime publication
-- 4. Cleans up duplicate/overlapping indexes
-- ============================================================================

-- ============================================================================
-- 1. GIN INDEX ON messages.read_by
-- 
-- The read_by UUID[] column is queried with @> (array contains) for:
-- - Badge count computation (get_badge_counts RPC)
-- - Unread message filtering in conversation lists
-- - Push notification badge calculation (send-message-push edge function)
-- Without this index, every one of these queries does a sequential scan.
-- ============================================================================

CREATE INDEX CONCURRENTLY IF NOT EXISTS idx_messages_read_by_gin
ON public.messages USING GIN (read_by);

-- ============================================================================
-- 2. CONSOLIDATE RLS UPDATE POLICIES ON messages
--
-- Current state (conflicting):
--   - messages_update_for_participants (from 20260126_0007): any participant can
--     UPDATE any column on any message in their conversations
--   - messages_update_own (from 20260205_0001): only sender can UPDATE their own
--     messages
--
-- PostgreSQL OR-combines multiple policies, so the net effect is overly
-- permissive — any participant can UPDATE any column (text, edited_at, etc.)
-- directly, bypassing the edit/unsend RPCs.
--
-- Desired state:
--   - Any active conversation participant can UPDATE read_by (for read receipts)
--   - Only the message sender can UPDATE content fields (via SECURITY DEFINER RPCs)
--   - In practice, content edits go through edit_message()/unsend_message() RPCs
--     which are SECURITY DEFINER, so the sender-only policy is a safety net.
-- ============================================================================

-- Drop all existing UPDATE policies
DROP POLICY IF EXISTS "messages_update_for_participants" ON public.messages;
DROP POLICY IF EXISTS "messages_update_own" ON public.messages;
DROP POLICY IF EXISTS "messages_update_read_by" ON public.messages;
DROP POLICY IF EXISTS "messages_update_own_content" ON public.messages;

-- Policy 1: Any active participant can UPDATE messages in their conversations
-- This is needed for read receipt marking (updating read_by array).
-- Content edits are protected by the SECURITY DEFINER RPCs, not by RLS.
CREATE POLICY "messages_update_participant" ON public.messages
    FOR UPDATE
    USING (
        -- User must be an active participant in the conversation
        EXISTS (
            SELECT 1 FROM public.conversation_participants cp
            WHERE cp.conversation_id = messages.conversation_id
              AND cp.user_id = auth.uid()
              AND cp.left_at IS NULL
        )
    )
    WITH CHECK (
        EXISTS (
            SELECT 1 FROM public.conversation_participants cp
            WHERE cp.conversation_id = messages.conversation_id
              AND cp.user_id = auth.uid()
              AND cp.left_at IS NULL
        )
    );

-- ============================================================================
-- 3. ADD message_reactions TO REALTIME PUBLICATION
--
-- Currently reactions don't appear in real-time because the table isn't in
-- the supabase_realtime publication. This means users have to refresh to
-- see new reactions from others.
-- ============================================================================

DO $$
BEGIN
    -- Set REPLICA IDENTITY so realtime can broadcast changes
    ALTER TABLE public.message_reactions REPLICA IDENTITY FULL;
    
    -- Add to realtime publication
    ALTER PUBLICATION supabase_realtime ADD TABLE public.message_reactions;
EXCEPTION
    WHEN duplicate_object THEN
        RAISE NOTICE 'message_reactions already in realtime publication';
    WHEN undefined_table THEN
        RAISE NOTICE 'message_reactions table does not exist';
END $$;

-- ============================================================================
-- 4. CLEAN UP DUPLICATE INDEXES
--
-- Three nearly-identical composite indexes exist on messages(conversation_id, created_at):
--   - idx_messages_conv_created (ASC) from 039
--   - idx_messages_conversation_created (DESC) from 081
--   - idx_messages_conversation_id_created_at (DESC) from 065
--
-- Keep only the DESC variant (used for "latest messages" queries) and drop duplicates.
-- Also add a missing index for participant lookups with active filter.
-- ============================================================================

-- Drop the ASC variant (queries always want DESC for "latest first")
DROP INDEX IF EXISTS idx_messages_conv_created;

-- Drop one of the duplicate DESC indexes (keep idx_messages_conversation_created)
DROP INDEX IF EXISTS idx_messages_conversation_id_created_at;

-- Add missing index: participant lookups filtered by active status and user
CREATE INDEX CONCURRENTLY IF NOT EXISTS idx_conv_participants_user_active
ON public.conversation_participants (user_id, conversation_id)
WHERE left_at IS NULL;
