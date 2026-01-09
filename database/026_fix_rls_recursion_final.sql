-- Final fix for RLS recursion in conversation_participants
-- This completely removes the recursive check and uses a simpler approach

-- ============================================================================
-- Step 1: Drop ALL existing policies that might cause recursion
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

-- ============================================================================
-- Step 2: Drop the function (we'll recreate it properly)
-- ============================================================================

DROP FUNCTION IF EXISTS public.is_conversation_participant(UUID, UUID) CASCADE;

-- ============================================================================
-- Step 3: Create SECURITY DEFINER function that bypasses RLS completely
-- ============================================================================

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
  -- This function runs with SECURITY DEFINER, so it bypasses RLS
  -- We explicitly query the table without RLS checks
  RETURN EXISTS (
    SELECT 1 
    FROM public.conversation_participants
    WHERE conversation_id = p_conversation_id
    AND user_id = p_user_id
  );
END;
$$;

-- Grant execute permission
GRANT EXECUTE ON FUNCTION public.is_conversation_participant(UUID, UUID) TO authenticated;
GRANT EXECUTE ON FUNCTION public.is_conversation_participant(UUID, UUID) TO anon;

-- ============================================================================
-- Step 4: Create conversation_participants SELECT policy (NO RECURSION)
-- ============================================================================

CREATE POLICY "participants_select_own_convos" ON public.conversation_participants
  FOR SELECT USING (user_id = auth.uid());

-- ============================================================================
-- Step 5: Create conversation_participants INSERT policy (uses function to avoid recursion)
-- ============================================================================

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
    OR
    -- Existing participants can add others (uses function to avoid recursion)
    public.is_conversation_participant(conversation_participants.conversation_id, auth.uid())
  );

-- ============================================================================
-- Step 6: Create conversation_participants UPDATE/DELETE policies
-- ============================================================================

CREATE POLICY "participants_update_own" ON public.conversation_participants
  FOR UPDATE USING (user_id = auth.uid());

CREATE POLICY "participants_delete_own" ON public.conversation_participants
  FOR DELETE USING (user_id = auth.uid());

-- ============================================================================
-- Step 7: Create conversations SELECT policy (uses function to avoid recursion)
-- ============================================================================

CREATE POLICY "conversations_select_participant" ON public.conversations
  FOR SELECT USING (
    -- User is the creator
    created_by = auth.uid()
    OR
    -- OR user is a participant (uses function to avoid recursion)
    public.is_conversation_participant(id, auth.uid())
  );

-- ============================================================================
-- Step 8: Create conversations INSERT policy
-- ============================================================================

CREATE POLICY "conversations_insert_approved" ON public.conversations
  FOR INSERT WITH CHECK (
    EXISTS (
      SELECT 1 FROM public.profiles 
      WHERE id = auth.uid() 
      AND approved = true
    )
    AND created_by = auth.uid()
  );

-- ============================================================================
-- Step 9: Create conversations UPDATE policy
-- ============================================================================

CREATE POLICY "conversations_update_creator" ON public.conversations
  FOR UPDATE USING (created_by = auth.uid());

-- ============================================================================
-- Step 10: Create messages SELECT policy (uses function to avoid recursion)
-- ============================================================================

CREATE POLICY "messages_select_participant" ON public.messages
  FOR SELECT USING (
    public.is_conversation_participant(conversation_id, auth.uid())
  );

-- ============================================================================
-- Step 11: Create messages INSERT policy (uses function to avoid recursion)
-- ============================================================================

CREATE POLICY "messages_insert_participant" ON public.messages
  FOR INSERT WITH CHECK (
    auth.uid() = from_id
    AND public.is_conversation_participant(conversation_id, auth.uid())
  );

-- ============================================================================
-- Verification
-- ============================================================================

-- The key difference: The function uses SECURITY DEFINER and plpgsql
-- This ensures it completely bypasses RLS when checking participation
-- All policies that need to check participation use this function
-- The conversation_participants SELECT policy is simple (user_id = auth.uid()) to avoid recursion


