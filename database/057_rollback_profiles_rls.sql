-- ============================================================================
-- 057_rollback_profiles_rls.sql
-- ============================================================================
-- 
-- EMERGENCY ROLLBACK: Disables RLS on profiles table temporarily
-- ONLY RUN THIS IF 057_fix_profiles_rls_recursion.sql doesn't work!
-- 
-- This will allow all operations on profiles table without RLS restrictions.
-- This is NOT secure - only use as a last resort to restore functionality.
--
-- ============================================================================

-- Option 1: Disable RLS completely (NOT SECURE - use only if fix doesn't work)
-- ALTER TABLE public.profiles DISABLE ROW LEVEL SECURITY;

-- Option 2: Drop all policies (RLS stays enabled but no restrictions)
DROP POLICY IF EXISTS "profiles_select_own" ON public.profiles;
DROP POLICY IF EXISTS "profiles_select_admin" ON public.profiles;
DROP POLICY IF EXISTS "profiles_insert_own" ON public.profiles;
DROP POLICY IF EXISTS "profiles_update_own" ON public.profiles;
DROP POLICY IF EXISTS "profiles_update_admin" ON public.profiles;

-- After dropping policies, RLS is still enabled but no restrictions apply
-- This should restore functionality but removes all security
-- 
-- TO FIX PROPERLY: Run 057_fix_profiles_rls_recursion.sql instead!

