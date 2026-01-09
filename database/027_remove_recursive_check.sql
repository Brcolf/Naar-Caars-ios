-- Remove the recursive check from INSERT policy
-- The issue: Checking if user is participant during INSERT causes recursion
-- Solution: Remove that check - only allow creator/request creator to add

-- ============================================================================
-- Step 1: Drop ALL policies that might cause recursion
-- ============================================================================

DROP POLICY IF EXISTS "participants_insert_creator_or_self" ON public.conversation_participants;
DROP POLICY IF EXISTS "participants_select_own_convos" ON public.conversation_participants;

-- ============================================================================
-- Step 2: Create simplified SELECT policy (NO RECURSION)
-- ============================================================================

CREATE POLICY "participants_select_own_convos" ON public.conversation_participants
  FOR SELECT USING (user_id = auth.uid());

-- ============================================================================
-- Step 3: Create simplified INSERT policy WITHOUT the recursive check
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
    -- NOTE: Removed "existing participants can add others" to avoid recursion
    -- For now, only creators can add participants
    -- We can add this back later with a better approach if needed
  );

-- ============================================================================
-- Verification
-- ============================================================================

-- This policy should now work without recursion because:
-- 1. It doesn't query conversation_participants to check for existing participants
-- 2. It only checks conversations, rides, and favors tables
-- 3. The conversation creator can always add participants (no recursion)

-- For the "existing participants can add others" feature, we'll need to:
-- 1. Either use a database trigger
-- 2. Or handle it in application code by checking participation before INSERT
-- 3. Or use a different RLS approach

