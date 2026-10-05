-- 20260319173500_update_create_signup_profile_v2.sql
-- Exported verbatim from supabase_migrations.schema_migrations on 2026-10-05.
-- This migration was applied to production through the Supabase MCP / dashboard before being committed.


-- Drop old function signature (with required p_invited_by)
DROP FUNCTION IF EXISTS create_signup_profile(UUID, TEXT, TEXT, UUID, TEXT);

-- Recreate with optional invited_by and new application fields
CREATE OR REPLACE FUNCTION create_signup_profile(
    p_user_id UUID,
    p_email TEXT,
    p_name TEXT,
    p_invited_by UUID DEFAULT NULL,
    p_car TEXT DEFAULT NULL,
    p_heard_about TEXT DEFAULT NULL,
    p_join_reason TEXT DEFAULT NULL
)
RETURNS jsonb
LANGUAGE plpgsql
SECURITY DEFINER
SET search_path = public
AS $$
BEGIN
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

GRANT EXECUTE ON FUNCTION create_signup_profile TO authenticated;
GRANT EXECUTE ON FUNCTION create_signup_profile TO anon;
