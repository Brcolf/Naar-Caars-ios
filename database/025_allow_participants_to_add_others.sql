-- Allow existing participants to add others to conversations
-- Uses SECURITY DEFINER function to avoid recursion

-- ============================================================================
-- Step 1: Create function to check if user is participant (bypasses RLS)
-- ============================================================================

CREATE OR REPLACE FUNCTION public.is_conversation_participant(
  p_conversation_id UUID,
  p_user_id UUID
) RETURNS BOOLEAN
LANGUAGE sql
SECURITY DEFINER
SET search_path = public
STABLE
AS $$
  -- This function bypasses RLS, so it can check participation without recursion
  SELECT EXISTS (
    SELECT 1 
    FROM public.conversation_participants
    WHERE conversation_id = p_conversation_id
    AND user_id = p_user_id
  );
$$;

-- Grant execute permission
GRANT EXECUTE ON FUNCTION public.is_conversation_participant(UUID, UUID) TO authenticated;
GRANT EXECUTE ON FUNCTION public.is_conversation_participant(UUID, UUID) TO anon;

-- ============================================================================
-- Step 2: Update INSERT policy to allow existing participants to add others
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
    OR
    -- Existing participants can add others (uses function to avoid recursion)
    public.is_conversation_participant(conversation_participants.conversation_id, auth.uid())
  );

-- ============================================================================
-- Step 3: Update conversations SELECT policy to use function (optional optimization)
-- ============================================================================

DROP POLICY IF EXISTS "conversations_select_participant" ON public.conversations;

CREATE POLICY "conversations_select_participant" ON public.conversations
  FOR SELECT USING (
    -- User is the creator
    created_by = auth.uid()
    OR
    -- OR user is a participant (uses function to avoid recursion)
    public.is_conversation_participant(id, auth.uid())
  );

-- ============================================================================
-- Step 4: Update messages policies to use function (optional optimization)
-- ============================================================================

DROP POLICY IF EXISTS "messages_select_participant" ON public.messages;
DROP POLICY IF EXISTS "messages_insert_participant" ON public.messages;

CREATE POLICY "messages_select_participant" ON public.messages
  FOR SELECT USING (
    public.is_conversation_participant(conversation_id, auth.uid())
  );

CREATE POLICY "messages_insert_participant" ON public.messages
  FOR INSERT WITH CHECK (
    auth.uid() = from_id
    AND public.is_conversation_participant(conversation_id, auth.uid())
  );

-- ============================================================================
-- Verification
-- ============================================================================

-- The function uses SECURITY DEFINER, so it bypasses RLS when checking participation
-- This allows the INSERT policy to check if user is a participant without recursion



