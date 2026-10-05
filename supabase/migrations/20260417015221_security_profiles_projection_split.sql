-- 20260417015221_security_profiles_projection_split.sql
-- Exported verbatim from supabase_migrations.schema_migrations on 2026-10-05.
-- This migration was applied to production through the Supabase MCP / dashboard before being committed.

-- Security fix: Split profiles into self/admin full-row access + a
-- public_profiles view exposing only non-PII columns for cross-user display.
-- Audit ref: CRIT-7.

-- Step 1: Create public_profiles view (postgres-owned, security_barrier)
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

COMMENT ON VIEW public.public_profiles IS
    'Non-PII projection of profiles for cross-user display. '
    'Bypasses profiles RLS (security_invoker=false). '
    'Callers needing full-row data (self, admin) must query profiles directly.';

REVOKE ALL ON public.public_profiles FROM PUBLIC;
GRANT SELECT ON public.public_profiles TO authenticated;
GRANT SELECT ON public.public_profiles TO anon;
GRANT SELECT ON public.public_profiles TO service_role;

-- Step 2: Drop overly broad SELECT policies on profiles
DROP POLICY IF EXISTS "profiles_select_authenticated" ON public.profiles;
DROP POLICY IF EXISTS "profiles_select_anon_guest"    ON public.profiles;
DROP POLICY IF EXISTS "profiles_select_admin"         ON public.profiles;
DROP POLICY IF EXISTS "Users can view approved profiles" ON public.profiles;

-- Step 3: Narrow SELECT policies on profiles (self + admin only)
CREATE POLICY "profiles_select_own"
ON public.profiles FOR SELECT TO authenticated
USING (auth.uid() = id);

CREATE POLICY "profiles_select_admin"
ON public.profiles FOR SELECT TO authenticated
USING (is_admin_user(auth.uid()));
