-- Test script to verify RLS policies work correctly
-- Run this as the authenticated user (not as service_role)

-- ============================================================================
-- Test 1: Check if function exists and works
-- ============================================================================
SELECT 
    'Function exists' as test,
    proname as function_name,
    prosecdef as is_security_definer
FROM pg_proc
WHERE proname = 'is_conversation_participant';

-- Test the function directly (should work)
SELECT 
    'Function test' as test,
    public.is_conversation_participant(
        (SELECT id FROM conversations LIMIT 1),
        auth.uid()
    ) as result;

-- ============================================================================
-- Test 2: Try to SELECT conversations (should work if user is participant)
-- ============================================================================
SELECT 
    'SELECT conversations' as test,
    COUNT(*) as conversation_count
FROM conversations;

-- ============================================================================
-- Test 3: Try to SELECT conversation_participants (should only show user's own rows)
-- ============================================================================
SELECT 
    'SELECT conversation_participants' as test,
    COUNT(*) as participant_count
FROM conversation_participants;

-- ============================================================================
-- Test 4: Try to INSERT a conversation (should work if user is approved)
-- ============================================================================
-- First check if user is approved
SELECT 
    'User approval check' as test,
    id,
    approved
FROM profiles
WHERE id = auth.uid();

-- Try to insert a test conversation (will fail if not approved)
-- Uncomment to test:
-- INSERT INTO conversations (created_by) VALUES (auth.uid()) RETURNING id;

-- ============================================================================
-- Test 5: Check all policies exist
-- ============================================================================
SELECT 
    'Policy check' as test,
    tablename,
    policyname,
    cmd as operation
FROM pg_policies
WHERE tablename IN ('conversations', 'conversation_participants', 'messages')
ORDER BY tablename, policyname;


