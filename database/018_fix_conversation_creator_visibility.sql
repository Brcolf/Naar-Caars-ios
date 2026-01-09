-- Fix: Allow conversation creators to see their conversations even before participants are added
-- This fixes the chicken-and-egg problem where a user creates a conversation but can't see it
-- because the SELECT policy checks for participation, but no participants exist yet.

-- ============================================================================
-- Update conversations SELECT policy to allow creators to see their conversations
-- ============================================================================

DROP POLICY IF EXISTS "conversations_select_participant" ON public.conversations;

CREATE POLICY "conversations_select_participant" ON public.conversations
  FOR SELECT USING (
    -- User is the creator (can see conversations they created)
    created_by = auth.uid()
    OR
    -- OR user is a participant (checked via function)
    public.is_conversation_participant(id, auth.uid())
  );

-- ============================================================================
-- Verification
-- ============================================================================

-- After this, users should be able to:
-- 1. Create a conversation (INSERT works)
-- 2. See the conversation they just created (SELECT works because created_by = auth.uid())
-- 3. Add participants (INSERT into conversation_participants works)
-- 4. See the conversation via participation check (SELECT works via function)


