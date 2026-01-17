-- Use a materialized approach: Create a function that queries without RLS
-- by using a different schema or approach

-- Actually, let's try the simplest possible fix one more time
-- but ensure the SELECT policy is truly independent

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
-- Step 2: Re-enable RLS on conversation_participants (in case it was disabled)
-- ============================================================================

ALTER TABLE public.conversation_participants ENABLE ROW LEVEL SECURITY;

-- ============================================================================
-- Step 3: Create the SIMPLEST possible SELECT policy
-- This should be evaluated first and not cause recursion
-- ============================================================================

CREATE POLICY "participants_select_own_convos" ON public.conversation_participants
  FOR SELECT 
  USING (user_id = auth.uid());

-- ============================================================================
-- Step 4: Create INSERT policy (no queries to conversation_participants)
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
-- Step 5: Create UPDATE/DELETE policies
-- ============================================================================

CREATE POLICY "participants_update_own" ON public.conversation_participants
  FOR UPDATE 
  USING (user_id = auth.uid());

CREATE POLICY "participants_delete_own" ON public.conversation_participants
  FOR DELETE 
  USING (user_id = auth.uid());

-- ============================================================================
-- Step 6: For conversations, ONLY allow creators to see (for now)
-- We'll handle participant filtering in application code
-- ============================================================================

CREATE POLICY "conversations_select_participant" ON public.conversations
  FOR SELECT 
  USING (
    created_by = auth.uid()
    -- NOTE: We're not checking participation here to avoid recursion
    -- Application code will filter to only show conversations where user is participant
  );

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

CREATE POLICY "conversations_update_creator" ON public.conversations
  FOR UPDATE 
  USING (created_by = auth.uid());

-- ============================================================================
-- Step 7: For messages, ONLY allow if user is conversation creator (for now)
-- We'll handle participant filtering in application code
-- ============================================================================

CREATE POLICY "messages_select_participant" ON public.messages
  FOR SELECT 
  USING (
    EXISTS (
      SELECT 1 
      FROM public.conversations
      WHERE id = messages.conversation_id
      AND created_by = auth.uid()
    )
    -- NOTE: Application code must filter to only show messages in conversations
    -- where user is a participant
  );

CREATE POLICY "messages_insert_participant" ON public.messages
  FOR INSERT 
  WITH CHECK (
    auth.uid() = from_id
    AND EXISTS (
      SELECT 1 
      FROM public.conversations
      WHERE id = messages.conversation_id
      AND created_by = auth.uid()
    )
    -- NOTE: Application code must verify user is participant before allowing insert
  );

-- ============================================================================
-- IMPORTANT: This is a temporary workaround
-- ============================================================================

-- This setup will eliminate recursion, but it's less secure because:
-- 1. Users can only see conversations they created (not ones they're participants in)
-- 2. Application code must filter conversations/messages to only show user's conversations
--
-- To make this work properly, MessageService needs to:
-- 1. Query conversation_participants directly to get user's conversation IDs
-- 2. Then query conversations WHERE id IN (user's conversation IDs)
-- 3. Filter messages similarly
--
-- This avoids the recursion because we're not querying conversation_participants
-- from within a policy - we're querying it directly in application code.



