-- Comprehensive diagnostic script for RLS issues
-- Run this to see what's actually in your database

-- 1. Check if the function exists and its definition
SELECT 
    proname as function_name,
    prosecdef as security_definer,
    proconfig as config,
    pg_get_functiondef(oid) as function_definition
FROM pg_proc
WHERE proname = 'is_conversation_participant';

-- 2. List ALL policies on conversation-related tables
SELECT 
    schemaname,
    tablename,
    policyname,
    permissive,
    roles,
    cmd as operation,
    qual as using_expression,
    with_check as with_check_expression
FROM pg_policies
WHERE tablename IN ('conversations', 'conversation_participants', 'messages')
ORDER BY tablename, policyname;

-- 3. Check if RLS is enabled on these tables
SELECT 
    schemaname,
    tablename,
    rowsecurity as rls_enabled
FROM pg_tables
WHERE tablename IN ('conversations', 'conversation_participants', 'messages')
AND schemaname = 'public';

-- 4. Test the function directly (should work without recursion)
SELECT 
    'Function test' as test_name,
    public.is_conversation_participant(
        (SELECT conversation_id FROM conversation_participants LIMIT 1),
        auth.uid()
    ) as result;

-- 5. Check for any policies that might query conversation_participants recursively
SELECT 
    tablename,
    policyname,
    qual as policy_expression
FROM pg_policies
WHERE qual::text LIKE '%conversation_participants%'
   OR with_check::text LIKE '%conversation_participants%'
ORDER BY tablename, policyname;



