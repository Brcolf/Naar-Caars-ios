-- Bypass RLS using SECURITY DEFINER function
-- This function will completely bypass RLS when checking participation

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
-- Step 2: Create SECURITY DEFINER function that bypasses RLS
-- This function runs with the privileges of the function creator, bypassing RLS
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
  -- This function runs with SECURITY DEFINER, so it completely bypasses RLS
  -- We can query conversation_participants directly without triggering policies
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
-- Step 3: Create conversation_participants SELECT policy (SIMPLE)
-- ============================================================================

CREATE POLICY "participants_select_own_convos" ON public.conversation_participants
  FOR SELECT 
  USING (user_id = auth.uid());

-- ============================================================================
-- Step 4: Create conversation_participants INSERT policy
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
-- Step 5: Create conversation_participants UPDATE/DELETE policies
-- ============================================================================

CREATE POLICY "participants_update_own" ON public.conversation_participants
  FOR UPDATE 
  USING (user_id = auth.uid());

CREATE POLICY "participants_delete_own" ON public.conversation_participants
  FOR DELETE 
  USING (user_id = auth.uid());

-- ============================================================================
-- Step 6: Create conversations SELECT policy (USES FUNCTION)
-- ============================================================================

CREATE POLICY "conversations_select_participant" ON public.conversations
  FOR SELECT 
  USING (
    created_by = auth.uid()
    OR
    public.is_conversation_participant(id, auth.uid())
  );

-- ============================================================================
-- Step 7: Create conversations INSERT policy
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
-- Step 8: Create conversations UPDATE policy
-- ============================================================================

CREATE POLICY "conversations_update_creator" ON public.conversations
  FOR UPDATE 
  USING (created_by = auth.uid());

-- ============================================================================
-- Step 9: Create messages SELECT policy (USES FUNCTION)
-- ============================================================================

CREATE POLICY "messages_select_participant" ON public.messages
  FOR SELECT 
  USING (
    public.is_conversation_participant(conversation_id, auth.uid())
  );

-- ============================================================================
-- Step 10: Create messages INSERT policy (USES FUNCTION)
-- ============================================================================

CREATE POLICY "messages_insert_participant" ON public.messages
  FOR INSERT 
  WITH CHECK (
    auth.uid() = from_id
    AND public.is_conversation_participant(conversation_id, auth.uid())
  );

-- ============================================================================
-- IMPORTANT: If this STILL causes recursion
-- ============================================================================

-- If the SECURITY DEFINER function still causes recursion, it means PostgreSQL
-- is evaluating the function in a way that still triggers RLS. In that case:
--
-- 1. We may need to use `SET LOCAL row_level_security = off` inside the function
-- 2. Or we may need to restructure the policies completely
-- 3. Or we may need to disable RLS on conversation_participants and handle
--    access control in application code or database triggers


