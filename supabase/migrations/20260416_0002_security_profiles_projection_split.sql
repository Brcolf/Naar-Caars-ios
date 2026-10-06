-- Security fix: Split profiles into self/admin full-row access + a
-- public_profiles view exposing only non-PII columns for cross-user display.
-- Audit ref: CRIT-7.
--
-- Vulnerability: any authenticated user (and anon guests) can read every
-- profile's email, phone_number, is_admin, is_banned, ban_reason, banned_by,
-- heard_about, join_reason, application_submitted_at, application_complete,
-- and all notify_* preferences via SELECT * FROM profiles.
--
-- Live policy state (verified via pg_policies):
--   profiles_select_authenticated  USING (auth.role() = 'authenticated')
--   profiles_select_anon_guest     USING (true)  -- for anon role
--   profiles_select_admin          USING (is_admin_user(auth.uid()))
--   Users can view approved profiles  USING (auth.uid() = id OR is_user_approved(auth.uid()))
-- All four are PERMISSIVE and OR together, so every role with any of them
-- gets full-row access to every profile.
--
-- Fix: expose only (id, name, avatar_url, car, approved, created_at,
-- updated_at) via a postgres-owned security-barrier view. Tighten the base
-- table to self + admin only. Swift cross-user reads switch to the view in
-- a follow-up change set.

-- -----------------------------------------------------------------------
-- Step 1: Create public_profiles view (postgres-owned, security_barrier)
-- -----------------------------------------------------------------------

CREATE OR REPLACE VIEW public.public_profiles
WITH (security_barrier = true, security_invoker = false) AS
SELECT
    id,
    name,
    avatar_url,
    car,
    approved,
    created_at,
    updated_at
FROM public.profiles;

-- View ownership is postgres by default (matches underlying profiles
-- ownership), which is what makes it bypass profiles RLS with
-- security_invoker = false.

COMMENT ON VIEW public.public_profiles IS
    'Non-PII projection of profiles for cross-user display. '
    'Bypasses profiles RLS (security_invoker=false). '
    'Callers needing full-row data (self, admin) must query profiles directly.';

REVOKE ALL ON public.public_profiles FROM PUBLIC;
GRANT SELECT ON public.public_profiles TO authenticated;
GRANT SELECT ON public.public_profiles TO anon;
GRANT SELECT ON public.public_profiles TO service_role;

-- -----------------------------------------------------------------------
-- Step 2: Drop overly broad SELECT policies on profiles
-- -----------------------------------------------------------------------

DROP POLICY IF EXISTS "profiles_select_authenticated" ON public.profiles;
DROP POLICY IF EXISTS "profiles_select_anon_guest"    ON public.profiles;
DROP POLICY IF EXISTS "profiles_select_admin"         ON public.profiles;
DROP POLICY IF EXISTS "Users can view approved profiles" ON public.profiles;

-- -----------------------------------------------------------------------
-- Step 3: Narrow SELECT policies on profiles (self + admin only)
-- -----------------------------------------------------------------------

CREATE POLICY "profiles_select_own"
ON public.profiles FOR SELECT TO authenticated
USING (auth.uid() = id);

CREATE POLICY "profiles_select_admin"
ON public.profiles FOR SELECT TO authenticated
USING (is_admin_user(auth.uid()));

-- INSERT/UPDATE/DELETE policies are unchanged and remain in effect:
--   "Users can insert own profile"  INSERT WITH CHECK (auth.uid() = id)
--   "Users can update own profile"  UPDATE USING/WITH CHECK (auth.uid() = id)
--   profiles_update_own             UPDATE USING/WITH CHECK (auth.uid() = id)
--   profiles_update_admin           UPDATE USING/WITH CHECK (is_admin_user(auth.uid()))
--   profiles_admin_delete           DELETE USING (approved = false AND is_admin)
