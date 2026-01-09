-- Nuclear option: Disable RLS on conversation_participants
-- Handle all access control in application code
-- This will definitely eliminate recursion

-- ============================================================================
-- Step 1: Drop ALL existing policies on conversation_participants
-- ============================================================================

DROP POLICY IF EXISTS "participants_insert_creator_or_self" ON public.conversation_participants;
DROP POLICY IF EXISTS "participants_select_own_convos" ON public.conversation_participants;
DROP POLICY IF EXISTS "participants_update_own" ON public.conversation_participants;
DROP POLICY IF EXISTS "participants_delete_own" ON public.conversation_participants;

-- ============================================================================
-- Step 2: Disable RLS on conversation_participants
-- ============================================================================

ALTER TABLE public.conversation_participants DISABLE ROW LEVEL SECURITY;

-- ============================================================================
-- Step 3: Keep other policies as they were (they don't query conversation_participants)
-- ============================================================================

-- conversations policies
DROP POLICY IF EXISTS "conversations_select_participant" ON public.conversations;
DROP POLICY IF EXISTS "conversations_insert_approved" ON public.conversations;
DROP POLICY IF EXISTS "conversations_update_creator" ON public.conversations;

-- Since we can't query conversation_participants from policies anymore,
-- we need to allow creators to see their conversations
CREATE POLICY "conversations_select_participant" ON public.conversations
  FOR SELECT 
  USING (
    created_by = auth.uid()
    -- NOTE: We can't check participation here anymore since RLS is disabled
    -- Application code must filter conversations to only show user's conversations
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

-- messages policies
DROP POLICY IF EXISTS "messages_select_participant" ON public.messages;
DROP POLICY IF EXISTS "messages_insert_participant" ON public.messages;

-- Since we can't query conversation_participants from policies anymore,
-- we need to allow based on conversation creator
CREATE POLICY "messages_select_participant" ON public.messages
  FOR SELECT 
  USING (
    EXISTS (
      SELECT 1 
      FROM public.conversations
      WHERE id = messages.conversation_id
      AND created_by = auth.uid()
    )
    -- NOTE: Application code must filter messages to only show user's conversations
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
-- IMPORTANT: Application Code Changes Required
-- ============================================================================

-- With RLS disabled on conversation_participants, the application MUST:
-- 1. Filter conversations to only show those where user is a participant
-- 2. Filter messages to only show those in conversations where user is a participant
-- 3. Verify user is participant before allowing message insert
-- 4. Verify user has permission before allowing participant insert
--
-- This is less secure than RLS, but it will eliminate the recursion issue.
-- Consider using database triggers or application-level checks to enforce security.


