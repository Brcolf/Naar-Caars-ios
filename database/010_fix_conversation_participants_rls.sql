-- Fix infinite recursion in conversation_participants RLS policy
-- 
-- Problem: The existing policy queries conversation_participants to check
-- if a user is a participant, which triggers the same policy again, causing
-- infinite recursion.
--
-- Solution: Use a SECURITY DEFINER function that bypasses RLS to check
-- participation without triggering recursion.

-- Step 1: Create a helper function that bypasses RLS
-- This function runs with elevated privileges and can check participation
-- without triggering the RLS policy recursion
CREATE OR REPLACE FUNCTION public.is_conversation_participant(
  p_conversation_id UUID,
  p_user_id UUID
) RETURNS BOOLEAN
LANGUAGE sql
SECURITY DEFINER
STABLE
AS $$
  SELECT EXISTS (
    SELECT 1 FROM public.conversation_participants
    WHERE conversation_id = p_conversation_id
    AND user_id = p_user_id
  );
$$;

-- Step 2: Drop the problematic policy
DROP POLICY IF EXISTS "participants_select_own_convos" ON public.conversation_participants;

-- Step 3: Create the new SELECT policy using the helper function
-- Users can see:
-- 1. Their own participation rows (user_id = auth.uid())
-- 2. Other participants in conversations where they are a participant
--    (checked via the SECURITY DEFINER function to avoid recursion)
CREATE POLICY "participants_select_own_convos" ON public.conversation_participants
  FOR SELECT USING (
    -- User can see their own participation
    user_id = auth.uid()
    OR
    -- User can see other participants in conversations where they are a participant
    -- Use the security definer function to avoid recursion
    public.is_conversation_participant(conversation_participants.conversation_id, auth.uid())
  );

-- Step 4: Add INSERT policy (if missing)
-- Users can add themselves or be added by conversation creator
DROP POLICY IF EXISTS "participants_insert_creator_or_self" ON public.conversation_participants;

CREATE POLICY "participants_insert_creator_or_self" ON public.conversation_participants
  FOR INSERT WITH CHECK (
    -- User can add themselves as a participant
    user_id = auth.uid()
    OR
    -- Conversation creator can add participants
    EXISTS (
      SELECT 1 FROM public.conversations c
      WHERE c.id = conversation_participants.conversation_id
      AND c.created_by = auth.uid()
    )
  );

-- Step 5: Add UPDATE policy (if missing)
-- Users can update their own participation
DROP POLICY IF EXISTS "participants_update_own" ON public.conversation_participants;

CREATE POLICY "participants_update_own" ON public.conversation_participants
  FOR UPDATE USING (user_id = auth.uid());

-- Step 6: Add DELETE policy (if missing)
-- Users can remove their own participation
DROP POLICY IF EXISTS "participants_delete_own" ON public.conversation_participants;

CREATE POLICY "participants_delete_own" ON public.conversation_participants
  FOR DELETE USING (user_id = auth.uid());

-- Verification: After running this script, test with:
-- SELECT * FROM conversation_participants WHERE conversation_id = '<some-id>';
-- This should no longer cause infinite recursion errors.
