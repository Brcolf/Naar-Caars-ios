-- Complete fix for all conversation-related RLS policies
-- This addresses INSERT policies and ensures all policies use the helper function

-- ============================================================================
-- 1. Fix conversations INSERT policy (MISSING - this is causing the error!)
-- ============================================================================

-- Drop any existing INSERT policy
DROP POLICY IF EXISTS "conversations_insert_approved" ON public.conversations;

-- Create INSERT policy: Approved users can create conversations
-- Note: We don't check conversation_participants here because the conversation
-- doesn't exist yet - participants are added after creation
CREATE POLICY "conversations_insert_approved" ON public.conversations
  FOR INSERT WITH CHECK (
    -- User must be approved
    EXISTS (
      SELECT 1 FROM public.profiles 
      WHERE id = auth.uid() 
      AND approved = true
    )
    AND
    -- User can only create conversations where they are the creator
    created_by = auth.uid()
  );

-- ============================================================================
-- 2. Fix conversations UPDATE policy (if needed)
-- ============================================================================

-- Drop any existing UPDATE policy
DROP POLICY IF EXISTS "conversations_update_creator" ON public.conversations;

-- Create UPDATE policy: Only creator can update conversations
CREATE POLICY "conversations_update_creator" ON public.conversations
  FOR UPDATE USING (created_by = auth.uid());

-- ============================================================================
-- 3. Fix messages policies to use helper function (prevents recursion)
-- ============================================================================

-- Drop existing messages policies
DROP POLICY IF EXISTS "messages_select_participant" ON public.messages;
DROP POLICY IF EXISTS "messages_insert_participant" ON public.messages;

-- Recreate messages SELECT policy using helper function
CREATE POLICY "messages_select_participant" ON public.messages
  FOR SELECT USING (
    -- Use the SECURITY DEFINER function to check participation
    public.is_conversation_participant(conversation_id, auth.uid())
  );

-- Recreate messages INSERT policy using helper function
CREATE POLICY "messages_insert_participant" ON public.messages
  FOR INSERT WITH CHECK (
    -- User must be the sender
    auth.uid() = from_id
    AND
    -- User must be a participant (checked via helper function)
    public.is_conversation_participant(conversation_id, auth.uid())
  );

-- ============================================================================
-- 4. Ensure conversation_participants INSERT policy is correct
-- ============================================================================

-- The INSERT policy should already exist from 010_fix_conversation_participants_rls.sql
-- But let's make sure it's using the helper function for the conversation check
DROP POLICY IF EXISTS "participants_insert_creator_or_self" ON public.conversation_participants;

CREATE POLICY "participants_insert_creator_or_self" ON public.conversation_participants
  FOR INSERT WITH CHECK (
    -- User can add themselves as a participant
    user_id = auth.uid()
    OR
    -- Conversation creator can add participants
    -- Check conversation creator directly (no recursion risk)
    EXISTS (
      SELECT 1 FROM public.conversations c
      WHERE c.id = conversation_participants.conversation_id
      AND c.created_by = auth.uid()
    )
  );

-- ============================================================================
-- Verification
-- ============================================================================

-- After running this, verify with:
-- SELECT policyname, cmd FROM pg_policies WHERE tablename IN ('conversations', 'messages', 'conversation_participants');


