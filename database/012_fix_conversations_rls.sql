-- Fix conversations RLS policy to use the helper function
-- This ensures consistency and avoids any potential recursion issues

-- Update the conversations SELECT policy to use the helper function
DROP POLICY IF EXISTS "conversations_select_participant" ON public.conversations;

CREATE POLICY "conversations_select_participant" ON public.conversations
  FOR SELECT USING (
    -- Use the SECURITY DEFINER function to check participation
    -- This avoids any potential RLS recursion issues
    public.is_conversation_participant(id, auth.uid())
  );



