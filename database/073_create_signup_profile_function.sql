-- Migration: 073_create_signup_profile_function.sql
-- Purpose: Create a function for creating/updating profiles during signup
-- This bypasses RLS using SECURITY DEFINER to avoid permission issues

CREATE OR REPLACE FUNCTION create_signup_profile(
    p_user_id UUID,
    p_email TEXT,
    p_name TEXT,
    p_invited_by UUID,
    p_car TEXT DEFAULT NULL
)
RETURNS jsonb
LANGUAGE plpgsql
SECURITY DEFINER
SET search_path = public
AS $$
DECLARE
    v_result jsonb;
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
    -- INSERT if not exists, UPDATE if exists (handles re-signup after rejection)
    INSERT INTO profiles (
        id,
        email,
        name,
        invited_by,
        car,
        is_admin,
        approved,
        created_at,
        updated_at
    ) VALUES (
        p_user_id,
        p_email,
        p_name,
        p_invited_by,
        p_car,
        false,  -- is_admin
        false,  -- approved (requires admin approval)
        NOW(),
        NOW()
    )
    ON CONFLICT (id) DO UPDATE SET
        email = EXCLUDED.email,
        name = EXCLUDED.name,
        invited_by = EXCLUDED.invited_by,
        car = EXCLUDED.car,
        is_admin = false,  -- Reset to false on re-signup
        approved = false,  -- Reset to false on re-signup (requires new approval)
        updated_at = NOW();
    
    -- Return success
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

-- Grant execute permission to authenticated users
GRANT EXECUTE ON FUNCTION create_signup_profile TO authenticated;

-- Also grant to anon for cases where session isn't fully established yet
GRANT EXECUTE ON FUNCTION create_signup_profile TO anon;

-- Add comment
COMMENT ON FUNCTION create_signup_profile IS 
'Creates or updates a profile during signup. Uses SECURITY DEFINER to bypass RLS.
Handles both new signups and re-signups after rejection.';


