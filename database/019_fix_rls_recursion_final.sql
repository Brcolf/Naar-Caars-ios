-- Final fix for RLS recursion: Use a function that explicitly bypasses RLS
-- The issue is that SECURITY DEFINER functions still respect RLS unless explicitly disabled

-- ============================================================================
-- Step 1: Drop all policies that use the function
-- ============================================================================

DROP POLICY IF EXISTS "conversations_select_participant" ON public.conversations;
DROP POLICY IF EXISTS "messages_select_participant" ON public.messages;
DROP POLICY IF EXISTS "messages_insert_participant" ON public.messages;

-- ============================================================================
-- Step 2: Drop and recreate the function with explicit RLS bypass
-- ============================================================================

DROP FUNCTION IF EXISTS public.is_conversation_participant(UUID, UUID);

-- Create function with SECURITY DEFINER
-- We'll disable RLS at the function level using ALTER FUNCTION
CREATE OR REPLACE FUNCTION public.is_conversation_participant(
  p_conversation_id UUID,
  p_user_id UUID
) RETURNS BOOLEAN
LANGUAGE sql
SECURITY DEFINER
SET search_path = public
STABLE
AS $$
  SELECT EXISTS (
    SELECT 1 
    FROM public.conversation_participants
    WHERE conversation_id = p_conversation_id
    AND user_id = p_user_id
  );
$$;

-- Grant permissions
GRANT EXECUTE ON FUNCTION public.is_conversation_participant(UUID, UUID) TO authenticated;
GRANT EXECUTE ON FUNCTION public.is_conversation_participant(UUID, UUID) TO anon;

-- CRITICAL: Disable RLS for this function
-- This tells PostgreSQL to bypass RLS when this function queries tables
ALTER FUNCTION public.is_conversation_participant(UUID, UUID) SET (row_security = off);

-- ============================================================================
-- Step 3: Recreate conversations SELECT policy
-- ============================================================================

CREATE POLICY "conversations_select_participant" ON public.conversations
  FOR SELECT USING (
    -- User is the creator (can see conversations they created)
    created_by = auth.uid()
    OR
    -- OR user is a participant (checked via function that bypasses RLS)
    public.is_conversation_participant(id, auth.uid())
  );

-- ============================================================================
-- Step 4: Recreate messages policies
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

-- ============================================================================
-- Verification
-- ============================================================================

-- Test the function directly (should work without recursion)
-- SELECT public.is_conversation_participant(
--     (SELECT id FROM conversations LIMIT 1),
--     auth.uid()
-- );

