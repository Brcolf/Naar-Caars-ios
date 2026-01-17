-- Diagnostic script to check invite_codes RLS policies
-- Run this to see what policies exist and their exact definitions

-- ============================================================================
-- Check if RLS is enabled
-- ============================================================================

SELECT 
    schemaname,
    tablename,
    rowsecurity as rls_enabled
FROM pg_tables
WHERE tablename = 'invite_codes'
  AND schemaname = 'public';

-- ============================================================================
-- List ALL policies on invite_codes table with full details
-- ============================================================================

SELECT 
    p.policyname,
    p.cmd as operation,
    CASE 
        WHEN p.qual IS NOT NULL THEN pg_get_expr(p.qual, p.polrelid)
        ELSE '(none)'
    END as using_clause,
    CASE 
        WHEN p.with_check IS NOT NULL THEN pg_get_expr(p.with_check, p.polrelid)
        ELSE '(none)'
    END as with_check_clause,
    p.permissive,
    array_to_string(p.roles, ', ') as roles
FROM pg_policy p
JOIN pg_class c ON c.oid = p.polrelid
JOIN pg_namespace n ON n.oid = c.relnamespace
WHERE c.relname = 'invite_codes'
  AND n.nspname = 'public'
ORDER BY p.cmd, p.policyname;

-- ============================================================================
-- Check what fields exist in invite_codes table
-- ============================================================================

SELECT 
    column_name,
    data_type,
    is_nullable,
    column_default
FROM information_schema.columns
WHERE table_schema = 'public'
  AND table_name = 'invite_codes'
ORDER BY ordinal_position;

-- ============================================================================
-- Check for any foreign key constraints that might affect inserts
-- ============================================================================

SELECT
    tc.constraint_name,
    tc.constraint_type,
    kcu.column_name,
    ccu.table_name AS foreign_table_name,
    ccu.column_name AS foreign_column_name
FROM information_schema.table_constraints AS tc
JOIN information_schema.key_column_usage AS kcu
  ON tc.constraint_name = kcu.constraint_name
  AND tc.table_schema = kcu.table_schema
LEFT JOIN information_schema.constraint_column_usage AS ccu
  ON ccu.constraint_name = tc.constraint_name
  AND ccu.table_schema = tc.table_schema
WHERE tc.table_name = 'invite_codes'
  AND tc.table_schema = 'public'
  AND tc.constraint_type IN ('FOREIGN KEY', 'PRIMARY KEY', 'UNIQUE');

-- ============================================================================
-- Test policy logic (this will show what auth.uid() returns in current context)
-- ============================================================================

-- Note: This will show NULL if not authenticated, or the user ID if authenticated
SELECT 
    'Current auth.uid()' as test,
    auth.uid() as value;

