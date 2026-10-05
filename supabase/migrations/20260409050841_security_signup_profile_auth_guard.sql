-- 20260409050841_security_signup_profile_auth_guard.sql
-- Exported verbatim from supabase_migrations.schema_migrations on 2026-10-05.
-- This migration was applied to production through the Supabase MCP / dashboard before being committed.


-- Security fix: Add auth.uid() validation to create_signup_profile.
-- Revoke PUBLIC and anon grants.
--
-- Live state: SECURITY DEFINER, no auth check, granted to PUBLIC/anon/authenticated.
-- ON CONFLICT resets is_admin, approved, application_complete to false.
-- An attacker could overwrite any profile and lock out admins.
--
-- Swift caller: AuthService.swift:274 — called after auth.signUp() which
-- establishes an authenticated session. auth.uid() = p_user_id at call time.
--
-- Audit ref: CRIT-1.

CREATE OR REPLACE FUNCTION public.create_signup_profile(
    p_user_id uuid,
    p_email text,
    p_name text,
    p_invited_by uuid DEFAULT NULL::uuid,
    p_car text DEFAULT NULL::text,
    p_heard_about text DEFAULT NULL::text,
    p_join_reason text DEFAULT NULL::text
)
RETURNS jsonb
LANGUAGE plpgsql
SECURITY DEFINER
SET search_path TO 'public'
AS $$
BEGIN
    -- SECURITY FIX: Verify caller is creating their own profile
    IF auth.uid() IS NULL OR auth.uid() != p_user_id THEN
        RETURN jsonb_build_object(
            'success', false,
            'error', 'Unauthorized: can only create your own profile'
        );
    END IF;

    -- Validate input
    IF p_user_id IS NULL THEN
        RETURN jsonb_build_object(
            'success', false,
            'error', 'User ID is required'
        );
    END IF;

    IF p_email IS NULL OR p_email = '' THEN
        RETURN jsonb_build_object(
            'success', false,
            'error', 'Email is required'
        );
    END IF;

    IF p_name IS NULL OR p_name = '' THEN
        RETURN jsonb_build_object(
            'success', false,
            'error', 'Name is required'
        );
    END IF;

    -- Upsert the profile
    INSERT INTO profiles (
        id,
        email,
        name,
        invited_by,
        car,
        heard_about,
        join_reason,
        is_admin,
        approved,
        application_complete,
        application_submitted_at,
        created_at,
        updated_at
    ) VALUES (
        p_user_id,
        p_email,
        p_name,
        p_invited_by,
        p_car,
        p_heard_about,
        p_join_reason,
        false,
        false,
        false,
        NULL,
        NOW(),
        NOW()
    )
    ON CONFLICT (id) DO UPDATE SET
        email = EXCLUDED.email,
        name = EXCLUDED.name,
        invited_by = COALESCE(EXCLUDED.invited_by, profiles.invited_by),
        car = EXCLUDED.car,
        heard_about = COALESCE(EXCLUDED.heard_about, profiles.heard_about),
        join_reason = COALESCE(EXCLUDED.join_reason, profiles.join_reason),
        is_admin = false,
        approved = false,
        application_complete = false,
        application_submitted_at = NULL,
        updated_at = NOW();

    RETURN jsonb_build_object(
        'success', true,
        'user_id', p_user_id,
        'message', 'Profile created/updated successfully'
    );

EXCEPTION WHEN OTHERS THEN
    RETURN jsonb_build_object(
        'success', false,
        'error', SQLERRM
    );
END;
$$;

-- Tighten grants
REVOKE ALL ON FUNCTION public.create_signup_profile FROM PUBLIC;
REVOKE ALL ON FUNCTION public.create_signup_profile FROM anon;
GRANT EXECUTE ON FUNCTION public.create_signup_profile TO authenticated;
GRANT EXECUTE ON FUNCTION public.create_signup_profile TO service_role;
