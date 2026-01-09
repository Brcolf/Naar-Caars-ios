-- Test script for messaging RLS policies
-- Run this as an authenticated user (not service_role) to verify policies work

-- ============================================================================
-- Test 1: Verify user can see their own conversations
-- ============================================================================
SELECT 
    'Test 1: User conversations' as test_name,
    COUNT(*) as conversation_count
FROM conversations;

-- ============================================================================
-- Test 2: Verify user can see their own participation rows
-- ============================================================================
SELECT 
    'Test 2: User participations' as test_name,
    COUNT(*) as participation_count
FROM conversation_participants;

-- ============================================================================
-- Test 3: Try to create a conversation (should work if user is approved)
-- ============================================================================
-- Uncomment to test:
-- INSERT INTO conversations (created_by) 
-- VALUES (auth.uid()) 
-- RETURNING id, created_by, created_at;

-- ============================================================================
-- Test 4: Try to add yourself as participant (should work)
-- ============================================================================
-- First, get a conversation ID from Test 3, then:
-- INSERT INTO conversation_participants (conversation_id, user_id, is_admin)
-- VALUES ('<conversation-id-from-test-3>', auth.uid(), true)
-- RETURNING id, conversation_id, user_id;

-- ============================================================================
-- Test 5: Verify user can see messages in their conversations
-- ============================================================================
SELECT 
    'Test 5: User messages' as test_name,
    COUNT(*) as message_count
FROM messages;

-- ============================================================================
-- Test 6: Check all policies exist
-- ============================================================================
SELECT 
    'Test 6: Policy check' as test_name,
    tablename,
    policyname,
    cmd as operation
FROM pg_policies
WHERE tablename IN ('conversations', 'conversation_participants', 'messages')
ORDER BY tablename, policyname;

-- ============================================================================
-- Test 7: Verify no recursion errors
-- ============================================================================
-- This should return without "infinite recursion" errors
SELECT 
    'Test 7: No recursion' as test_name,
    c.id as conversation_id,
    COUNT(cp.user_id) as participant_count
FROM conversations c
LEFT JOIN conversation_participants cp ON cp.conversation_id = c.id
GROUP BY c.id
LIMIT 10;


