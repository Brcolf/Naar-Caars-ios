-- Alternative simpler fix: Avoid recursion by not checking participation in policies
-- This uses a different approach - policies only check direct ownership, not participation

-- ============================================================================
-- Step 1: Drop ALL policies that depend on the function FIRST
-- We must drop policies before we can drop/recreate the function
-- ============================================================================

-- Drop policies that use the function
DROP POLICY IF EXISTS "participants_select_own_convos" ON public.conversation_participants;
DROP POLICY IF EXISTS "conversations_select_participant" ON public.conversations;
DROP POLICY IF EXISTS "messages_select_participant" ON public.messages;
DROP POLICY IF EXISTS "messages_insert_participant" ON public.messages;

-- ============================================================================
-- Step 2: Now we can drop and recreate the function
-- ============================================================================

DROP FUNCTION IF EXISTS public.is_conversation_participant(UUID, UUID);

-- Create a function that checks participation by querying with RLS disabled
CREATE OR REPLACE FUNCTION public.is_conversation_participant(
  p_conversation_id UUID,
  p_user_id UUID
) RETURNS BOOLEAN
LANGUAGE plpgsql
SECURITY DEFINER
STABLE
AS $$
DECLARE
  result BOOLEAN;
BEGIN
  -- Use a subquery with explicit schema to avoid RLS
  -- SECURITY DEFINER should bypass RLS, but we'll be explicit
  SELECT EXISTS (
    SELECT 1 
    FROM public.conversation_participants
    WHERE conversation_id = p_conversation_id
    AND user_id = p_user_id
  ) INTO result;
  
  RETURN COALESCE(result, false);
END;
$$;

-- Grant permissions
GRANT EXECUTE ON FUNCTION public.is_conversation_participant(UUID, UUID) TO authenticated;
GRANT EXECUTE ON FUNCTION public.is_conversation_participant(UUID, UUID) TO anon;

-- ============================================================================
-- Step 3: Simplify conversation_participants SELECT policy
-- Only show rows where user_id = auth.uid() - this avoids recursion
-- ============================================================================

-- SIMPLIFIED: Only show user's own participation rows
-- This completely avoids recursion because we're not checking other participants
CREATE POLICY "participants_select_own_convos" ON public.conversation_participants
  FOR SELECT USING (user_id = auth.uid());

-- ============================================================================
-- Step 4: Update conversations SELECT policy to use function
-- ============================================================================

CREATE POLICY "conversations_select_participant" ON public.conversations
  FOR SELECT USING (
    -- Use the function to check participation
    -- The function bypasses RLS, so no recursion
    public.is_conversation_participant(id, auth.uid())
  );

-- ============================================================================
-- Step 5: Ensure INSERT policies exist
-- ============================================================================

-- conversations INSERT
DROP POLICY IF EXISTS "conversations_insert_approved" ON public.conversations;

CREATE POLICY "conversations_insert_approved" ON public.conversations
  FOR INSERT WITH CHECK (
    EXISTS (
      SELECT 1 FROM public.profiles 
      WHERE id = auth.uid() 
      AND approved = true
    )
    AND created_by = auth.uid()
  );

-- conversation_participants INSERT
DROP POLICY IF EXISTS "participants_insert_creator_or_self" ON public.conversation_participants;

CREATE POLICY "participants_insert_creator_or_self" ON public.conversation_participants
  FOR INSERT WITH CHECK (
    user_id = auth.uid()
    OR
    EXISTS (
      SELECT 1 FROM public.conversations c
      WHERE c.id = conversation_participants.conversation_id
      AND c.created_by = auth.uid()
    )
  );

-- ============================================================================
-- Step 6: Recreate messages policies (we dropped them in Step 1)
-- ============================================================================

CREATE POLICY "messages_select_participant" ON public.messages
  FOR SELECT USING (
    public.is_conversation_participant(conversation_id, auth.uid())
  );

CREATE POLICY "messages_insert_participant" ON public.messages
  FOR INSERT WITH CHECK (
    auth.uid() = from_id
    AND public.is_conversation_participant(conversation_id, auth.uid())
  );

