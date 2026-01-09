-- Ultimate RLS fix - Ensure NO recursion at all
-- The key: Make sure conversation_participants SELECT policy is evaluated FIRST
-- and doesn't trigger any other policy checks

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
-- Step 2: Create conversation_participants SELECT policy (MUST BE FIRST)
-- This is the simplest possible policy - just check user_id
-- ============================================================================

CREATE POLICY "participants_select_own_convos" ON public.conversation_participants
  FOR SELECT 
  USING (user_id = auth.uid());

-- ============================================================================
-- Step 3: Create conversation_participants INSERT policy
-- Only checks conversations/rides/favors - never queries conversation_participants
-- ============================================================================

CREATE POLICY "participants_insert_creator_or_self" ON public.conversation_participants
  FOR INSERT 
  WITH CHECK (
    -- User can add themselves (no query needed)
    user_id = auth.uid()
    OR
    -- Conversation creator can add (queries conversations only)
    EXISTS (
      SELECT 1 
      FROM public.conversations 
      WHERE id = conversation_participants.conversation_id
      AND created_by = auth.uid()
    )
    OR
    -- Request creator can add (queries conversations + rides/favors only)
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
-- Step 4: Create conversation_participants UPDATE/DELETE policies
-- ============================================================================

CREATE POLICY "participants_update_own" ON public.conversation_participants
  FOR UPDATE 
  USING (user_id = auth.uid());

CREATE POLICY "participants_delete_own" ON public.conversation_participants
  FOR DELETE 
  USING (user_id = auth.uid());

-- ============================================================================
-- Step 5: Create conversations SELECT policy
-- Uses EXISTS with simple WHERE that matches participants SELECT policy
-- ============================================================================

CREATE POLICY "conversations_select_participant" ON public.conversations
  FOR SELECT 
  USING (
    -- Creator can always see
    created_by = auth.uid()
    OR
    -- Participant can see (query matches participants SELECT policy exactly)
    EXISTS (
      SELECT 1 
      FROM public.conversation_participants
      WHERE conversation_id = conversations.id
      AND user_id = auth.uid()  -- This matches the SELECT policy exactly
    )
  );

-- ============================================================================
-- Step 6: Create conversations INSERT policy
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
-- Step 7: Create conversations UPDATE policy
-- ============================================================================

CREATE POLICY "conversations_update_creator" ON public.conversations
  FOR UPDATE 
  USING (created_by = auth.uid());

-- ============================================================================
-- Step 8: Create messages SELECT policy
-- Uses EXISTS with simple WHERE that matches participants SELECT policy
-- ============================================================================

CREATE POLICY "messages_select_participant" ON public.messages
  FOR SELECT 
  USING (
    EXISTS (
      SELECT 1 
      FROM public.conversation_participants
      WHERE conversation_id = messages.conversation_id
      AND user_id = auth.uid()  -- This matches the SELECT policy exactly
    )
  );

-- ============================================================================
-- Step 9: Create messages INSERT policy
-- Uses EXISTS with simple WHERE that matches participants SELECT policy
-- ============================================================================

CREATE POLICY "messages_insert_participant" ON public.messages
  FOR INSERT 
  WITH CHECK (
    auth.uid() = from_id
    AND EXISTS (
      SELECT 1 
      FROM public.conversation_participants
      WHERE conversation_id = messages.conversation_id
      AND user_id = auth.uid()  -- This matches the SELECT policy exactly
    )
  );

-- ============================================================================
-- Verification Notes
-- ============================================================================

-- Why this should work:
-- 1. conversation_participants SELECT policy is: user_id = auth.uid() (no recursion)
-- 2. All EXISTS queries use: WHERE user_id = auth.uid() (matches SELECT policy)
-- 3. INSERT policy never queries conversation_participants (no recursion)
-- 4. The WHERE clause in EXISTS queries exactly matches the SELECT policy
--
-- PostgreSQL should be able to evaluate:
-- - conversation_participants SELECT: simple equality check
-- - conversations SELECT EXISTS: queries conversation_participants with WHERE user_id = auth.uid()
--   which matches the SELECT policy, so it can use the policy directly
--
-- If this still causes recursion, the issue might be in how PostgreSQL evaluates
-- the policies. In that case, we may need to use SECURITY DEFINER functions or
-- disable RLS temporarily during certain operations.


