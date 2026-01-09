-- Complete RLS fix - Remove ALL recursive checks
-- This ensures no policy queries conversation_participants in a way that causes recursion

-- ============================================================================
-- Step 1: Drop ALL existing policies
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

-- ============================================================================
-- Step 2: Drop the function (we'll recreate it if needed, but try without first)
-- ============================================================================

DROP FUNCTION IF EXISTS public.is_conversation_participant(UUID, UUID) CASCADE;

-- ============================================================================
-- Step 3: Create conversation_participants SELECT policy (SIMPLE - NO RECURSION)
-- ============================================================================

CREATE POLICY "participants_select_own_convos" ON public.conversation_participants
  FOR SELECT USING (user_id = auth.uid());

-- ============================================================================
-- Step 4: Create conversation_participants INSERT policy (NO RECURSIVE CHECKS)
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
    -- NOTE: "Existing participants can add others" is handled in application code
    -- to avoid RLS recursion
  );

-- ============================================================================
-- Step 5: Create conversation_participants UPDATE/DELETE policies
-- ============================================================================

CREATE POLICY "participants_update_own" ON public.conversation_participants
  FOR UPDATE USING (user_id = auth.uid());

CREATE POLICY "participants_delete_own" ON public.conversation_participants
  FOR DELETE USING (user_id = auth.uid());

-- ============================================================================
-- Step 6: Create conversations SELECT policy (DIRECT QUERY - NO FUNCTION)
-- ============================================================================

CREATE POLICY "conversations_select_participant" ON public.conversations
  FOR SELECT USING (
    -- User is the creator
    created_by = auth.uid()
    OR
    -- OR user is a participant (direct query, no function to avoid recursion)
    EXISTS (
      SELECT 1 
      FROM public.conversation_participants cp
      WHERE cp.conversation_id = conversations.id
      AND cp.user_id = auth.uid()
    )
  );

-- ============================================================================
-- Step 7: Create conversations INSERT policy
-- ============================================================================

CREATE POLICY "conversations_insert_approved" ON public.conversations
  FOR INSERT WITH CHECK (
    EXISTS (
      SELECT 1 FROM public.profiles 
      WHERE id = auth.uid() 
      AND approved = true
    )
    AND created_by = auth.uid()
  );

-- ============================================================================
-- Step 8: Create conversations UPDATE policy
-- ============================================================================

CREATE POLICY "conversations_update_creator" ON public.conversations
  FOR UPDATE USING (created_by = auth.uid());

-- ============================================================================
-- Step 9: Create messages SELECT policy (DIRECT QUERY - NO FUNCTION)
-- ============================================================================

CREATE POLICY "messages_select_participant" ON public.messages
  FOR SELECT USING (
    -- Direct query, no function to avoid recursion
    EXISTS (
      SELECT 1 
      FROM public.conversation_participants cp
      WHERE cp.conversation_id = messages.conversation_id
      AND cp.user_id = auth.uid()
    )
  );

-- ============================================================================
-- Step 10: Create messages INSERT policy (DIRECT QUERY - NO FUNCTION)
-- ============================================================================

CREATE POLICY "messages_insert_participant" ON public.messages
  FOR INSERT WITH CHECK (
    auth.uid() = from_id
    AND EXISTS (
      SELECT 1 
      FROM public.conversation_participants cp
      WHERE cp.conversation_id = messages.conversation_id
      AND cp.user_id = auth.uid()
    )
  );

-- ============================================================================
-- Verification
-- ============================================================================

-- Key changes:
-- 1. conversation_participants SELECT policy is simple: user_id = auth.uid() (no recursion)
-- 2. conversations SELECT policy uses direct EXISTS query (no function)
-- 3. messages policies use direct EXISTS query (no function)
-- 4. INSERT policy doesn't check for existing participants (handled in app code)
-- 
-- This should eliminate all recursion because:
-- - The SELECT policy on conversation_participants is simple and doesn't query itself
-- - The EXISTS queries in conversations/messages policies query conversation_participants
--   with a simple WHERE clause that matches the SELECT policy, so no recursion


