-- ============================================================================
-- Fix Profiles RLS for Messaging
-- ============================================================================
-- Problem: Users can only see their own profiles (profiles_select_own policy)
-- This breaks messaging because MessageService needs to fetch other participants'
-- profiles when displaying conversations.
--
-- Solution: Allow all authenticated users to view basic profile information
-- (name, avatar, car details) which is necessary for the community app to function.
-- This is safe because:
-- 1. Profile data is community-visible by design (users see each other in rides, favors, messages)
-- 2. Sensitive fields (email, phone) are already controlled by the application layer
-- 3. Admin-only fields (approved, role) have separate UPDATE policies
--
-- Last Updated: January 2026
-- ============================================================================

-- Drop the existing restrictive select policy
DROP POLICY IF EXISTS "profiles_select_own" ON public.profiles;
DROP POLICY IF EXISTS "profiles_select_admin" ON public.profiles;

-- Create a new policy that allows authenticated users to view all profiles
-- This matches the community app use case where users need to see each other
CREATE POLICY "profiles_select_authenticated" ON public.profiles
  FOR SELECT
  USING (
    auth.role() = 'authenticated'
  );

-- Create admin policy for SELECT (admins can see all, same as authenticated but explicit)
CREATE POLICY "profiles_select_admin" ON public.profiles
  FOR SELECT
  USING (
    public.is_admin_user(auth.uid())
  );

-- ============================================================================
-- Verification Query
-- ============================================================================
-- Test as a regular user (should see all profiles):
-- SELECT id, name, email, avatar_url FROM profiles LIMIT 5;

-- Verify policies are active:
-- SELECT tablename, policyname, cmd, qual, with_check 
-- FROM pg_policies 
-- WHERE tablename = 'profiles';

-- ============================================================================
-- Security Notes
-- ============================================================================
-- 1. Users can VIEW all profiles (necessary for community features)
-- 2. Users can only UPDATE their own profile (existing policy: profiles_update_own)
-- 3. Users can only INSERT their own profile during signup (existing policy: profiles_insert_own)
-- 4. Admins can UPDATE any profile (existing policy: profiles_update_admin)
-- 5. Application layer (ProfileService) handles additional authorization
--    and controls which fields are displayed in different contexts


