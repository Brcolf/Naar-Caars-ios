-- Final RLS fix with proper ordering
-- The key insight: PostgreSQL evaluates policies in a way that can cause recursion
-- if the EXISTS subquery in conversations policy triggers the participants SELECT policy
-- which then somehow triggers another check.

-- Solution: Ensure the participants SELECT policy is completely independent
-- and that all EXISTS queries use the exact same WHERE clause

-- ============================================================================
-- Step 1: Drop ALL existing policies and functions
-- ============================================================================

DROP POLICY IF EXISTS "participants_insert_creator_or_self" ON public.conversation_participants;
DROP POLICY IF EXISTS "participants_select_own_convos" ON public.conversation_participants;
DROP POLICY IF EXISTS "participants_update_own" ON public.conversation_participants;
DROP POLICY IF EXISTS "participants_delete_own" ON public.conversation_participants;

DROP POLICY IF EXISTS "conversations_select_participant" ON public.conversations;
DROP POLICY IF EXISTS "conversations_insert_approved" ON public.conversations;
DROP POLICY IF EXISTS "conversations_update_creator" ON public.conversations;

DROP POLICY IF EXISTS "messages_select_participant" ON public.messages;
DROP POLICY IF EXISTS "messages_insert_participant" ON public.messages;

DROP FUNCTION IF EXISTS public.is_conversation_participant(UUID, UUID) CASCADE;

-- ============================================================================
-- Step 2: CRITICAL - Create conversation_participants SELECT policy FIRST
-- This MUST be the simplest possible policy with NO dependencies
-- ============================================================================

CREATE POLICY "participants_select_own_convos" ON public.conversation_participants
  FOR SELECT 
  USING (user_id = auth.uid());

-- ============================================================================
-- Step 3: Create conversation_participants INSERT policy
-- IMPORTANT: This queries conversations/rides/favors, NOT conversation_participants
-- ============================================================================

CREATE POLICY "participants_insert_creator_or_self" ON public.conversation_participants
  FOR INSERT 
  WITH CHECK (
    user_id = auth.uid()
    OR
    EXISTS (
      SELECT 1 
      FROM public.conversations 
      WHERE id = conversation_participants.conversation_id
      AND created_by = auth.uid()
    )
    OR
    EXISTS (
      SELECT 1 
      FROM public.conversations c
      LEFT JOIN public.rides r ON c.ride_id = r.id
      LEFT JOIN public.favors f ON c.favor_id = f.id
      WHERE c.id = conversation_participants.conversation_id
      AND (r.user_id = auth.uid() OR f.user_id = auth.uid())
    )
  );

-- ============================================================================
-- Step 4: Create conversation_participants UPDATE/DELETE policies
-- ============================================================================

CREATE POLICY "participants_update_own" ON public.conversation_participants
  FOR UPDATE 
  USING (user_id = auth.uid());

CREATE POLICY "participants_delete_own" ON public.conversation_participants
  FOR DELETE 
  USING (user_id = auth.uid());

-- ============================================================================
-- Step 5: Create conversations SELECT policy
-- CRITICAL: The EXISTS subquery MUST use the EXACT same WHERE clause
-- as the participants SELECT policy: user_id = auth.uid()
-- ============================================================================

CREATE POLICY "conversations_select_participant" ON public.conversations
  FOR SELECT 
  USING (
    created_by = auth.uid()
    OR
    EXISTS (
      SELECT 1 
      FROM public.conversation_participants
      WHERE conversation_id = conversations.id
      AND user_id = auth.uid()
    )
  );

-- ============================================================================
-- Step 6: Create conversations INSERT policy
-- ============================================================================

CREATE POLICY "conversations_insert_approved" ON public.conversations
  FOR INSERT 
  WITH CHECK (
    EXISTS (
      SELECT 1 
      FROM public.profiles 
      WHERE id = auth.uid() 
      AND approved = true
    )
    AND created_by = auth.uid()
  );

-- ============================================================================
-- Step 7: Create conversations UPDATE policy
-- ============================================================================

CREATE POLICY "conversations_update_creator" ON public.conversations
  FOR UPDATE 
  USING (created_by = auth.uid());

-- ============================================================================
-- Step 8: Create messages SELECT policy
-- CRITICAL: The EXISTS subquery MUST use the EXACT same WHERE clause
-- as the participants SELECT policy: user_id = auth.uid()
-- ============================================================================

CREATE POLICY "messages_select_participant" ON public.messages
  FOR SELECT 
  USING (
    EXISTS (
      SELECT 1 
      FROM public.conversation_participants
      WHERE conversation_id = messages.conversation_id
      AND user_id = auth.uid()
    )
  );

-- ============================================================================
-- Step 9: Create messages INSERT policy
-- CRITICAL: The EXISTS subquery MUST use the EXACT same WHERE clause
-- as the participants SELECT policy: user_id = auth.uid()
-- ============================================================================

CREATE POLICY "messages_insert_participant" ON public.messages
  FOR INSERT 
  WITH CHECK (
    auth.uid() = from_id
    AND EXISTS (
      SELECT 1 
      FROM public.conversation_participants
      WHERE conversation_id = messages.conversation_id
      AND user_id = auth.uid()
    )
  );

-- ============================================================================
-- IMPORTANT NOTES
-- ============================================================================

-- If this STILL causes recursion, the issue is likely that PostgreSQL is
-- evaluating the conversations SELECT policy when we INSERT into conversations,
-- and that's triggering the EXISTS check which queries conversation_participants.
--
-- In that case, we may need to:
-- 1. Use SECURITY DEFINER functions that bypass RLS entirely
-- 2. Or restructure the policies to avoid the circular dependency
-- 3. Or use a different approach (e.g., disable RLS on conversation_participants
--    and handle access control in application code or triggers)


