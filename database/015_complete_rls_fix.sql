-- Complete RLS fix with explicit RLS bypass
-- This version ensures the function truly bypasses RLS

-- ============================================================================
-- Step 1: Drop and recreate the function with explicit RLS bypass
-- ============================================================================

DROP FUNCTION IF EXISTS public.is_conversation_participant(UUID, UUID);

-- Create function that explicitly sets RLS to bypass
-- Using SECURITY DEFINER with SET LOCAL to ensure RLS is bypassed
CREATE OR REPLACE FUNCTION public.is_conversation_participant(
  p_conversation_id UUID,
  p_user_id UUID
) RETURNS BOOLEAN
LANGUAGE plpgsql
SECURITY DEFINER
SET search_path = public
STABLE
AS $$
BEGIN
  -- Explicitly disable RLS for this function's execution
  SET LOCAL row_security = off;
  
  RETURN EXISTS (
    SELECT 1 
    FROM public.conversation_participants
    WHERE conversation_id = p_conversation_id
    AND user_id = p_user_id
  );
END;
$$;

-- Grant execute permission to authenticated users
GRANT EXECUTE ON FUNCTION public.is_conversation_participant(UUID, UUID) TO authenticated;
GRANT EXECUTE ON FUNCTION public.is_conversation_participant(UUID, UUID) TO anon;

-- ============================================================================
-- Step 2: Drop ALL existing policies and recreate them cleanly
-- ============================================================================

-- Drop all conversation_participants policies
DROP POLICY IF EXISTS "participants_select_own_convos" ON public.conversation_participants;
DROP POLICY IF EXISTS "participants_insert_creator_or_self" ON public.conversation_participants;
DROP POLICY IF EXISTS "participants_update_own" ON public.conversation_participants;
DROP POLICY IF EXISTS "participants_delete_own" ON public.conversation_participants;

-- Recreate SELECT policy (simplified - user sees their own rows OR uses function)
CREATE POLICY "participants_select_own_convos" ON public.conversation_participants
  FOR SELECT USING (
    user_id = auth.uid()
    OR
    public.is_conversation_participant(conversation_participants.conversation_id, auth.uid())
  );

-- Recreate INSERT policy (simplified - no recursion risk)
CREATE POLICY "participants_insert_creator_or_self" ON public.conversation_participants
  FOR INSERT WITH CHECK (
    -- User can add themselves
    user_id = auth.uid()
    OR
    -- OR conversation creator can add them (check conversations table directly, no recursion)
    EXISTS (
      SELECT 1 FROM public.conversations c
      WHERE c.id = conversation_participants.conversation_id
      AND c.created_by = auth.uid()
    )
  );

-- Recreate UPDATE policy
CREATE POLICY "participants_update_own" ON public.conversation_participants
  FOR UPDATE USING (user_id = auth.uid());

-- Recreate DELETE policy
CREATE POLICY "participants_delete_own" ON public.conversation_participants
  FOR DELETE USING (user_id = auth.uid());

-- ============================================================================
-- Step 3: Fix conversations policies
-- ============================================================================

-- Drop all conversations policies
DROP POLICY IF EXISTS "conversations_select_participant" ON public.conversations;
DROP POLICY IF EXISTS "conversations_insert_approved" ON public.conversations;
DROP POLICY IF EXISTS "conversations_update_creator" ON public.conversations;

-- Recreate SELECT policy using function
CREATE POLICY "conversations_select_participant" ON public.conversations
  FOR SELECT USING (
    public.is_conversation_participant(id, auth.uid())
  );

-- Recreate INSERT policy (must exist for conversation creation!)
CREATE POLICY "conversations_insert_approved" ON public.conversations
  FOR INSERT WITH CHECK (
    -- User must be approved
    EXISTS (
      SELECT 1 FROM public.profiles 
      WHERE id = auth.uid() 
      AND approved = true
    )
    AND
    -- User can only create conversations where they are the creator
    created_by = auth.uid()
  );

-- Recreate UPDATE policy
CREATE POLICY "conversations_update_creator" ON public.conversations
  FOR UPDATE USING (created_by = auth.uid());

-- ============================================================================
-- Step 4: Fix messages policies to use function
-- ============================================================================

-- Drop all messages policies
DROP POLICY IF EXISTS "messages_select_participant" ON public.messages;
DROP POLICY IF EXISTS "messages_insert_participant" ON public.messages;

-- Recreate SELECT policy using function
CREATE POLICY "messages_select_participant" ON public.messages
  FOR SELECT USING (
    public.is_conversation_participant(conversation_id, auth.uid())
  );

-- Recreate INSERT policy using function
CREATE POLICY "messages_insert_participant" ON public.messages
  FOR INSERT WITH CHECK (
    auth.uid() = from_id
    AND
    public.is_conversation_participant(conversation_id, auth.uid())
  );

-- ============================================================================
-- Verification queries (run these to test)
-- ============================================================================

-- Test 1: Check function exists and is SECURITY DEFINER
-- SELECT proname, prosecdef FROM pg_proc WHERE proname = 'is_conversation_participant';
-- Should show: is_conversation_participant | true

-- Test 2: List all policies
-- SELECT tablename, policyname, cmd FROM pg_policies 
-- WHERE tablename IN ('conversations', 'conversation_participants', 'messages')
-- ORDER BY tablename, policyname;

-- Test 3: Try a simple query (should work without recursion)
-- SELECT * FROM conversation_participants LIMIT 5;


