-- ============================================================================
-- 057_fix_profiles_rls_recursion.sql
-- ============================================================================
-- 
-- Fixes RLS policies for profiles table by removing recursive queries.
-- Uses SECURITY DEFINER functions to check admin status (bypasses RLS).
--
-- This fixes the issue where:
-- 1. All accounts appear as pending approval (SELECT policies failing)
-- 2. New accounts cannot be created (INSERT/UPDATE policies failing)
--
-- ============================================================================

-- Step 1: Create helper function to check if user is admin (bypasses RLS)
-- ============================================================================

CREATE OR REPLACE FUNCTION public.is_admin_user(user_id UUID)
RETURNS BOOLEAN
LANGUAGE plpgsql
SECURITY DEFINER
SET search_path = public
STABLE
AS $$
BEGIN
  RETURN EXISTS (
    SELECT 1
    FROM public.profiles
    WHERE id = user_id
    AND is_admin = true
  );
END;
$$;

-- Grant execute permission to authenticated users
GRANT EXECUTE ON FUNCTION public.is_admin_user(UUID) TO authenticated;
GRANT EXECUTE ON FUNCTION public.is_admin_user(UUID) TO anon;

-- ============================================================================
-- Step 2: Drop existing policies
-- ============================================================================

DROP POLICY IF EXISTS "profiles_select_own" ON public.profiles;
DROP POLICY IF EXISTS "profiles_select_admin" ON public.profiles;
DROP POLICY IF EXISTS "profiles_insert_own" ON public.profiles;
DROP POLICY IF EXISTS "profiles_update_own" ON public.profiles;
DROP POLICY IF EXISTS "profiles_update_admin" ON public.profiles;

-- ============================================================================
-- Step 3: Create SELECT policies (using function to avoid recursion)
-- ============================================================================

-- Allow users to SELECT their own profile
CREATE POLICY "profiles_select_own" ON public.profiles
  FOR SELECT
  USING (id = auth.uid());

-- Allow admins to SELECT all profiles (using function to avoid recursion)
CREATE POLICY "profiles_select_admin" ON public.profiles
  FOR SELECT
  USING (public.is_admin_user(auth.uid()));

-- ============================================================================
-- Step 4: Create INSERT policy
-- ============================================================================

-- Allow users to INSERT their own profile during signup
-- Also allow service role (for triggers)
CREATE POLICY "profiles_insert_own" ON public.profiles
  FOR INSERT
  WITH CHECK (
    id = auth.uid()
    OR auth.role() = 'service_role'  -- Allow triggers/functions
  );

-- ============================================================================
-- Step 5: Create UPDATE policies
-- ============================================================================

-- Allow users to UPDATE their own profile
-- They can update fields but cannot set approved=true or is_admin=true
-- Note: They CAN set approved=false and is_admin=false (which is the default)
CREATE POLICY "profiles_update_own" ON public.profiles
  FOR UPDATE
  USING (id = auth.uid())
  WITH CHECK (
    id = auth.uid()
    -- Allow setting approved to false or null (default during signup)
    AND (approved = false OR approved IS NULL)
    -- Allow setting is_admin to false or null (default during signup)
    AND (is_admin = false OR is_admin IS NULL)
  );

-- Allow admins to UPDATE any profile (using function to avoid recursion)
-- Admins can update any field, including approved and is_admin
CREATE POLICY "profiles_update_admin" ON public.profiles
  FOR UPDATE
  USING (public.is_admin_user(auth.uid()))
  WITH CHECK (public.is_admin_user(auth.uid()));

-- ============================================================================
-- Step 6: Verify policies were created
-- ============================================================================

SELECT 
    p.policyname,
    p.cmd as operation,
    p.qual as using_clause,
    p.with_check as with_check_clause
FROM pg_policies p
WHERE p.tablename = 'profiles'
  AND p.schemaname = 'public'
ORDER BY p.cmd, p.policyname;

-- ============================================================================
-- Step 7: Verify function was created
-- ============================================================================

SELECT 
    proname as function_name,
    prosecdef as is_security_definer
FROM pg_proc
WHERE proname = 'is_admin_user';

-- Should show: is_admin_user | true
-- ============================================================================

