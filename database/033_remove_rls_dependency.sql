-- Remove RLS dependency entirely
-- The issue: Even SECURITY DEFINER functions can cause recursion if called from policies
-- Solution: Make the function use a completely different approach that doesn't trigger RLS

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
-- Step 2: Create function that uses pg_catalog to bypass RLS completely
-- ============================================================================

CREATE OR REPLACE FUNCTION public.is_conversation_participant(
  p_conversation_id UUID,
  p_user_id UUID
) RETURNS BOOLEAN
LANGUAGE plpgsql
SECURITY DEFINER
SET search_path = public, pg_catalog
STABLE
AS $$
DECLARE
  result BOOLEAN;
  old_rls_setting BOOLEAN;
BEGIN
  -- Get current RLS setting
  SELECT current_setting('row_security', true)::boolean INTO old_rls_setting;
  
  -- Disable RLS for this session
  PERFORM set_config('row_security', 'off', true);
  
  -- Query without RLS
  SELECT EXISTS (
    SELECT 1 
    FROM public.conversation_participants
    WHERE conversation_id = p_conversation_id
    AND user_id = p_user_id
  ) INTO result;
  
  -- Restore RLS setting if it was on
  IF old_rls_setting THEN
    PERFORM set_config('row_security', 'on', true);
  END IF;
  
  RETURN result;
EXCEPTION
  WHEN OTHERS THEN
    -- Restore RLS setting on error
    IF old_rls_setting THEN
      PERFORM set_config('row_security', 'on', true);
    END IF;
    RAISE;
END;
$$;

-- Grant execute permission
GRANT EXECUTE ON FUNCTION public.is_conversation_participant(UUID, UUID) TO authenticated;
GRANT EXECUTE ON FUNCTION public.is_conversation_participant(UUID, UUID) TO anon;

-- ============================================================================
-- Step 3: Create conversation_participants SELECT policy (SIMPLE - NO RECURSION)
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


