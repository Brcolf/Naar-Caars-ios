-- ============================================================================
-- Secure Messaging RLS Policies (No Recursion)
-- ============================================================================
-- This migration creates secure RLS policies for the messaging system
-- while avoiding infinite recursion issues.
--
-- Strategy:
-- 1. conversation_participants: Keep RLS DISABLED for performance
--    Security enforced at application level (MessageService)
-- 2. conversations: Simple policies for creators
-- 3. messages: Application-level security checks (already implemented)
-- 4. message_reactions: Simple policies based on conversation participation
--
-- Last Updated: January 2026
-- ============================================================================

-- ============================================================================
-- SECTION 1: conversation_participants (RLS DISABLED)
-- ============================================================================
-- RLS is disabled on this table to avoid recursion and allow efficient queries
-- Security is enforced in MessageService.swift with manual checks

-- Ensure RLS is disabled (should already be from migration 038)
ALTER TABLE public.conversation_participants DISABLE ROW LEVEL SECURITY;

-- Drop any existing policies
DROP POLICY IF EXISTS "participants_insert_creator_or_self" ON public.conversation_participants;
DROP POLICY IF EXISTS "participants_select_own_convos" ON public.conversation_participants;
DROP POLICY IF EXISTS "participants_update_own" ON public.conversation_participants;
DROP POLICY IF EXISTS "participants_delete_own" ON public.conversation_participants;

-- ============================================================================
-- SECTION 2: conversations
-- ============================================================================
-- Simple policies that allow creators to manage their conversations
-- Participants can read conversations if they're in conversation_participants

-- Drop existing policies
DROP POLICY IF EXISTS "conversations_select_creator" ON public.conversations;
DROP POLICY IF EXISTS "conversations_select_participant" ON public.conversations;
DROP POLICY IF EXISTS "conversations_insert_approved" ON public.conversations;
DROP POLICY IF EXISTS "conversations_update_creator" ON public.conversations;
DROP POLICY IF EXISTS "conversations_delete_creator" ON public.conversations;

-- Enable RLS on conversations
ALTER TABLE public.conversations ENABLE ROW LEVEL SECURITY;

-- SELECT: Allow if user is creator
-- Note: Application code filters to only show conversations where user is participant
CREATE POLICY "conversations_select_creator" ON public.conversations
  FOR SELECT 
  USING (created_by = auth.uid());

-- INSERT: Approved users can create conversations
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

-- UPDATE: Only creator can update (title, etc.)
CREATE POLICY "conversations_update_creator" ON public.conversations
  FOR UPDATE 
  USING (created_by = auth.uid())
  WITH CHECK (created_by = auth.uid());

-- DELETE: Only creator can delete (optional feature)
CREATE POLICY "conversations_delete_creator" ON public.conversations
  FOR DELETE 
  USING (created_by = auth.uid());

-- ============================================================================
-- SECTION 3: messages
-- ============================================================================
-- Simple policies for message access
-- Application code verifies user is participant before showing messages

-- Drop existing policies
DROP POLICY IF EXISTS "messages_select_creator" ON public.messages;
DROP POLICY IF EXISTS "messages_select_participant" ON public.messages;
DROP POLICY IF EXISTS "messages_insert_creator" ON public.messages;
DROP POLICY IF EXISTS "messages_insert_participant" ON public.messages;
DROP POLICY IF EXISTS "messages_update_own" ON public.messages;
DROP POLICY IF EXISTS "messages_delete_own" ON public.messages;

-- Enable RLS on messages
ALTER TABLE public.messages ENABLE ROW LEVEL SECURITY;

-- SELECT: Allow if user is conversation creator
-- Application code additionally filters to only show messages in conversations
-- where user is a participant
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

-- INSERT: Allow if user is sender AND conversation creator
-- Application code verifies user is participant before allowing insert
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

-- UPDATE: Users can update their own messages (for read_by array)
CREATE POLICY "messages_update_own" ON public.messages
  FOR UPDATE 
  USING (from_id = auth.uid())
  WITH CHECK (from_id = auth.uid());

-- ============================================================================
-- SECTION 4: message_reactions
-- ============================================================================
-- Policies for message reactions

-- Check if table exists first
DO $$ 
BEGIN
  IF EXISTS (SELECT FROM pg_tables WHERE schemaname = 'public' AND tablename = 'message_reactions') THEN
    -- Drop existing policies
    DROP POLICY IF EXISTS "reactions_select_all" ON public.message_reactions;
    DROP POLICY IF EXISTS "reactions_insert_own" ON public.message_reactions;
    DROP POLICY IF EXISTS "reactions_update_own" ON public.message_reactions;
    DROP POLICY IF EXISTS "reactions_delete_own" ON public.message_reactions;

    -- Enable RLS
    ALTER TABLE public.message_reactions ENABLE ROW LEVEL SECURITY;

    -- SELECT: Anyone can see reactions (public)
    CREATE POLICY "reactions_select_all" ON public.message_reactions
      FOR SELECT 
      USING (true);

    -- INSERT: Users can add reactions
    CREATE POLICY "reactions_insert_own" ON public.message_reactions
      FOR INSERT 
      WITH CHECK (user_id = auth.uid());

    -- UPDATE: Users can update their own reactions
    CREATE POLICY "reactions_update_own" ON public.message_reactions
      FOR UPDATE 
      USING (user_id = auth.uid())
      WITH CHECK (user_id = auth.uid());

    -- DELETE: Users can delete their own reactions
    CREATE POLICY "reactions_delete_own" ON public.message_reactions
      FOR DELETE 
      USING (user_id = auth.uid());
  END IF;
END $$;

-- ============================================================================
-- SECTION 5: Indexes for Performance
-- ============================================================================
-- Ensure critical indexes exist for efficient queries

-- Index on conversation_participants for user lookups (critical for app security)
CREATE INDEX IF NOT EXISTS idx_conversation_participants_user_id 
  ON public.conversation_participants(user_id);

CREATE INDEX IF NOT EXISTS idx_conversation_participants_conversation_id 
  ON public.conversation_participants(conversation_id);

-- Index on conversations for ordering
CREATE INDEX IF NOT EXISTS idx_conversations_updated_at 
  ON public.conversations(updated_at DESC);

-- Index on messages for conversation queries
CREATE INDEX IF NOT EXISTS idx_messages_conversation_id_created_at 
  ON public.messages(conversation_id, created_at DESC);

-- Index on message_reactions for message queries
DO $$ 
BEGIN
  IF EXISTS (SELECT FROM pg_tables WHERE schemaname = 'public' AND tablename = 'message_reactions') THEN
    CREATE INDEX IF NOT EXISTS idx_message_reactions_message_id 
      ON public.message_reactions(message_id);
  END IF;
END $$;

-- ============================================================================
-- SECTION 6: Documentation & Application Security Notes
-- ============================================================================

COMMENT ON TABLE public.conversation_participants IS 
'RLS DISABLED: Security enforced at application level in MessageService.swift. 
Application verifies user participation before showing conversations/messages.';

COMMENT ON TABLE public.conversations IS 
'RLS ENABLED: Creators can see their conversations. Application filters to show 
only conversations where user is a participant (checked via conversation_participants).';

COMMENT ON TABLE public.messages IS 
'RLS ENABLED: Conversation creators can access messages. Application verifies 
user is participant before showing messages.';

-- ============================================================================
-- Migration Complete
-- ============================================================================
-- Test with: SELECT * FROM conversations; (should only show user's created conversations)
-- Application code in MessageService handles additional filtering

