-- ============================================================================
-- Row-Level Security (RLS) Policy Fixes for Naar's Cars
-- ============================================================================
-- This file contains the necessary database policies to fix the issues with:
-- 1. Claiming rides/favors (which creates conversations)
-- 2. Creating group messages
-- 3. General conversation creation
--
-- Run these commands in your Supabase SQL Editor
-- ============================================================================

-- ----------------------------------------------------------------------------
-- 1. CONVERSATIONS TABLE POLICIES
-- ----------------------------------------------------------------------------

-- Drop existing problematic policies (if any)
DROP POLICY IF EXISTS "Users can view conversations they are part of" ON conversations;
DROP POLICY IF EXISTS "Users can create conversations" ON conversations;
DROP POLICY IF EXISTS "Users can update their own conversations" ON conversations;

-- Allow users to view conversations they are participants in
CREATE POLICY "Users can view conversations they are part of"
ON conversations
FOR SELECT
TO authenticated
USING (
    EXISTS (
        SELECT 1 FROM conversation_participants
        WHERE conversation_participants.conversation_id = conversations.id
        AND conversation_participants.user_id = auth.uid()
    )
);

-- Allow authenticated users to create conversations
CREATE POLICY "Users can create conversations"
ON conversations
FOR INSERT
TO authenticated
WITH CHECK (
    auth.uid() = created_by
);

-- Allow users to update conversations they created
CREATE POLICY "Users can update their conversations"
ON conversations
FOR UPDATE
TO authenticated
USING (created_by = auth.uid())
WITH CHECK (created_by = auth.uid());

-- ----------------------------------------------------------------------------
-- 2. CONVERSATION_PARTICIPANTS TABLE POLICIES
-- ----------------------------------------------------------------------------

-- Drop existing problematic policies (if any)
DROP POLICY IF EXISTS "Users can view participants in their conversations" ON conversation_participants;
DROP POLICY IF EXISTS "Users can add participants when creating conversation" ON conversation_participants;
DROP POLICY IF EXISTS "Conversation creator can manage participants" ON conversation_participants;

-- Allow users to view participants in conversations they're part of
CREATE POLICY "Users can view participants in their conversations"
ON conversation_participants
FOR SELECT
TO authenticated
USING (
    EXISTS (
        SELECT 1 FROM conversation_participants AS cp2
        WHERE cp2.conversation_id = conversation_participants.conversation_id
        AND cp2.user_id = auth.uid()
    )
);

-- Allow adding participants when creating a conversation
CREATE POLICY "Users can add participants when creating conversation"
ON conversation_participants
FOR INSERT
TO authenticated
WITH CHECK (
    -- Allow if the user is the conversation creator
    EXISTS (
        SELECT 1 FROM conversations
        WHERE conversations.id = conversation_participants.conversation_id
        AND conversations.created_by = auth.uid()
    )
);

-- Allow conversation creators to manage participants
CREATE POLICY "Conversation creator can manage participants"
ON conversation_participants
FOR DELETE
TO authenticated
USING (
    EXISTS (
        SELECT 1 FROM conversations
        WHERE conversations.id = conversation_participants.conversation_id
        AND conversations.created_by = auth.uid()
    )
);

-- ----------------------------------------------------------------------------
-- 3. RIDES TABLE POLICIES (for claiming)
-- ----------------------------------------------------------------------------

-- Drop existing problematic policies (if any)
DROP POLICY IF EXISTS "Users can view rides" ON rides;
DROP POLICY IF EXISTS "Users can create rides" ON rides;
DROP POLICY IF EXISTS "Users can update their own rides" ON rides;
DROP POLICY IF EXISTS "Users can claim rides" ON rides;

-- Allow all authenticated users to view rides
CREATE POLICY "Users can view rides"
ON rides
FOR SELECT
TO authenticated
USING (true);

-- Allow authenticated users to create rides
CREATE POLICY "Users can create rides"
ON rides
FOR INSERT
TO authenticated
WITH CHECK (
    user_id = auth.uid()
);

-- Allow users to update their own rides
CREATE POLICY "Users can update their own rides"
ON rides
FOR UPDATE
TO authenticated
USING (user_id = auth.uid())
WITH CHECK (user_id = auth.uid());

-- Allow users to claim rides (update claimed_by and status)
CREATE POLICY "Users can claim rides"
ON rides
FOR UPDATE
TO authenticated
USING (true)  -- Anyone can attempt to claim
WITH CHECK (
    -- Can update if they're the owner OR if they're claiming it
    user_id = auth.uid() OR claimed_by = auth.uid()
);

-- ----------------------------------------------------------------------------
-- 4. FAVORS TABLE POLICIES (for claiming)
-- ----------------------------------------------------------------------------

-- Drop existing problematic policies (if any)
DROP POLICY IF EXISTS "Users can view favors" ON favors;
DROP POLICY IF EXISTS "Users can create favors" ON favors;
DROP POLICY IF EXISTS "Users can update their own favors" ON favors;
DROP POLICY IF EXISTS "Users can claim favors" ON favors;

-- Allow all authenticated users to view favors
CREATE POLICY "Users can view favors"
ON favors
FOR SELECT
TO authenticated
USING (true);

-- Allow authenticated users to create favors
CREATE POLICY "Users can create favors"
ON favors
FOR INSERT
TO authenticated
WITH CHECK (
    user_id = auth.uid()
);

-- Allow users to update their own favors
CREATE POLICY "Users can update their own favors"
ON favors
FOR UPDATE
TO authenticated
USING (user_id = auth.uid())
WITH CHECK (user_id = auth.uid());

-- Allow users to claim favors (update claimed_by and status)
CREATE POLICY "Users can claim favors"
ON favors
FOR UPDATE
TO authenticated
USING (true)  -- Anyone can attempt to claim
WITH CHECK (
    -- Can update if they're the owner OR if they're claiming it
    user_id = auth.uid() OR claimed_by = auth.uid()
);

-- ----------------------------------------------------------------------------
-- 5. MESSAGES TABLE POLICIES
-- ----------------------------------------------------------------------------

-- Drop existing problematic policies (if any)
DROP POLICY IF EXISTS "Users can view messages in their conversations" ON messages;
DROP POLICY IF EXISTS "Users can send messages in their conversations" ON messages;

-- Allow users to view messages in conversations they're part of
CREATE POLICY "Users can view messages in their conversations"
ON messages
FOR SELECT
TO authenticated
USING (
    EXISTS (
        SELECT 1 FROM conversation_participants
        WHERE conversation_participants.conversation_id = messages.conversation_id
        AND conversation_participants.user_id = auth.uid()
    )
);

-- Allow users to send messages in conversations they're part of
CREATE POLICY "Users can send messages in their conversations"
ON messages
FOR INSERT
TO authenticated
WITH CHECK (
    from_id = auth.uid()
    AND EXISTS (
        SELECT 1 FROM conversation_participants
        WHERE conversation_participants.conversation_id = messages.conversation_id
        AND conversation_participants.user_id = auth.uid()
    )
);

-- ----------------------------------------------------------------------------
-- 6. VERIFY RLS IS ENABLED
-- ----------------------------------------------------------------------------

-- Ensure RLS is enabled on all tables
ALTER TABLE conversations ENABLE ROW LEVEL SECURITY;
ALTER TABLE conversation_participants ENABLE ROW LEVEL SECURITY;
ALTER TABLE messages ENABLE ROW LEVEL SECURITY;
ALTER TABLE rides ENABLE ROW LEVEL SECURITY;
ALTER TABLE favors ENABLE ROW LEVEL SECURITY;

-- ----------------------------------------------------------------------------
-- 7. GRANT NECESSARY PERMISSIONS
-- ----------------------------------------------------------------------------

-- Grant basic permissions to authenticated users
GRANT SELECT, INSERT, UPDATE ON conversations TO authenticated;
GRANT SELECT, INSERT, DELETE ON conversation_participants TO authenticated;
GRANT SELECT, INSERT ON messages TO authenticated;
GRANT SELECT, INSERT, UPDATE ON rides TO authenticated;
GRANT SELECT, INSERT, UPDATE ON favors TO authenticated;

-- ----------------------------------------------------------------------------
-- VERIFICATION QUERIES
-- ----------------------------------------------------------------------------

-- Run these to verify the policies are active:

-- Check conversations policies
SELECT schemaname, tablename, policyname, permissive, roles, cmd, qual 
FROM pg_policies 
WHERE tablename = 'conversations';

-- Check conversation_participants policies
SELECT schemaname, tablename, policyname, permissive, roles, cmd, qual 
FROM pg_policies 
WHERE tablename = 'conversation_participants';

-- Check rides policies
SELECT schemaname, tablename, policyname, permissive, roles, cmd, qual 
FROM pg_policies 
WHERE tablename = 'rides';

-- Check favors policies
SELECT schemaname, tablename, policyname, permissive, roles, cmd, qual 
FROM pg_policies 
WHERE tablename = 'favors';

-- Check messages policies
SELECT schemaname, tablename, policyname, permissive, roles, cmd, qual 
FROM pg_policies 
WHERE tablename = 'messages';
