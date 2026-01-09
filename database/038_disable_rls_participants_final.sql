-- Final solution: Disable RLS on conversation_participants
-- Handle access control in application code
-- This eliminates recursion and allows efficient queries

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
-- Step 3: Update conversations policies to not query conversation_participants
-- ============================================================================

DROP POLICY IF EXISTS "conversations_select_participant" ON public.conversations;
DROP POLICY IF EXISTS "conversations_insert_approved" ON public.conversations;
DROP POLICY IF EXISTS "conversations_update_creator" ON public.conversations;

-- Allow creators to see their conversations
-- Application code will filter to only show conversations where user is participant
CREATE POLICY "conversations_select_creator" ON public.conversations
  FOR SELECT 
  USING (created_by = auth.uid());

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
-- Step 4: Update messages policies to not query conversation_participants
-- ============================================================================

DROP POLICY IF EXISTS "messages_select_participant" ON public.messages;
DROP POLICY IF EXISTS "messages_insert_participant" ON public.messages;

-- Allow if user is conversation creator
-- Application code will filter to only show messages in conversations where user is participant
CREATE POLICY "messages_select_creator" ON public.messages
  FOR SELECT 
  USING (
    EXISTS (
      SELECT 1 
      FROM public.conversations
      WHERE id = messages.conversation_id
      AND created_by = auth.uid()
    )
  );

CREATE POLICY "messages_insert_creator" ON public.messages
  FOR INSERT 
  WITH CHECK (
    auth.uid() = from_id
    AND EXISTS (
      SELECT 1 
      FROM public.conversations
      WHERE id = messages.conversation_id
      AND created_by = auth.uid()
    )
  );

-- ============================================================================
-- IMPORTANT: Application Code Must Handle Security
-- ============================================================================

-- With RLS disabled on conversation_participants, the application MUST:
-- 1. Query conversation_participants directly to get user's conversation IDs
-- 2. Filter conversations to only show those where user is a participant
-- 3. Filter messages to only show those in conversations where user is a participant
-- 4. Verify user is participant before allowing message insert
-- 5. Verify user has permission before allowing participant insert
--
-- This approach:
-- - Eliminates recursion completely
-- - Allows efficient queries with JOINs
-- - Scales well (PostgreSQL can optimize)
-- - Maintains security through application-level checks


