-- Fix recursion in conversation_participants INSERT policy
-- The issue: The INSERT policy checks for existing participants, which causes recursion
-- Solution: Remove the "existing participants can add" check and rely on other conditions

-- ============================================================================
-- Step 1: Drop the problematic INSERT policy
-- ============================================================================

DROP POLICY IF EXISTS "participants_insert_creator_or_self" ON public.conversation_participants;

-- ============================================================================
-- Step 2: Create simplified INSERT policy WITHOUT recursion
-- ============================================================================

-- Users can add themselves OR be added by:
-- - Conversation creator
-- - Request creator (if conversation is linked to their request)
-- NOTE: We removed "existing participants can add" to avoid recursion
-- For group chats, users should be added by the conversation creator
CREATE POLICY "participants_insert_creator_or_self" ON public.conversation_participants
  FOR INSERT WITH CHECK (
    -- User can add themselves
    user_id = auth.uid()
    OR
    -- Conversation creator can add participants
    EXISTS (
      SELECT 1 FROM public.conversations c
      WHERE c.id = conversation_participants.conversation_id
      AND c.created_by = auth.uid()
    )
    OR
    -- Request creator can add participants (if conversation is linked to their request)
    EXISTS (
      SELECT 1 FROM public.conversations c
      LEFT JOIN public.rides r ON c.ride_id = r.id
      LEFT JOIN public.favors f ON c.favor_id = f.id
      WHERE c.id = conversation_participants.conversation_id
      AND (r.user_id = auth.uid() OR f.user_id = auth.uid())
    )
  );

-- ============================================================================
-- Alternative: If we need existing participants to add others, we need a function
-- But for now, let's keep it simple - conversation creator can always add
-- ============================================================================

-- ============================================================================
-- Verification
-- ============================================================================

-- Test: Try to insert a participant
-- Should work if user is adding themselves OR is the conversation creator



