-- Verification script for conversation_participants RLS fix
-- Run this to verify the fix was applied correctly

-- 1. Check if the function exists
SELECT 
    proname as function_name,
    pg_get_functiondef(oid) as function_definition
FROM pg_proc
WHERE proname = 'is_conversation_participant';

-- 2. Check if the policies exist
SELECT 
    schemaname,
    tablename,
    policyname,
    permissive,
    roles,
    cmd,
    qual,
    with_check
FROM pg_policies
WHERE tablename = 'conversation_participants'
ORDER BY policyname;

-- 3. Test the function directly (should work without recursion)
SELECT public.is_conversation_participant(
    (SELECT conversation_id FROM conversation_participants LIMIT 1),
    auth.uid()
) as is_participant;

-- 4. Test a simple query (should work without recursion)
SELECT * FROM conversation_participants LIMIT 10;


