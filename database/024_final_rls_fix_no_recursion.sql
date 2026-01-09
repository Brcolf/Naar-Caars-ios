-- Final RLS fix - Remove recursion from INSERT policy
-- The issue: INSERT policy was checking for existing participants, causing recursion
-- Solution: Remove that check - conversation creator can always add participants

-- ============================================================================
-- Drop and recreate the INSERT policy WITHOUT the recursive check
-- ============================================================================

DROP POLICY IF EXISTS "participants_insert_creator_or_self" ON public.conversation_participants;

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
-- Verification
-- ============================================================================

-- This policy should now work without recursion because:
-- 1. It doesn't query conversation_participants to check for existing participants
-- 2. It only checks conversations, rides, and favors tables
-- 3. The conversation creator can always add participants (no recursion)

-- Test: Try creating a conversation and adding participants
-- Should work without "infinite recursion" errors


