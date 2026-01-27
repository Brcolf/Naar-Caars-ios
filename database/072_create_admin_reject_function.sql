-- Migration: 072_create_admin_reject_function.sql
-- Purpose: Create a function for admins to reject pending users
-- This bypasses RLS using SECURITY DEFINER since there's no delete policy for admins
-- Also adds an RLS policy for admin delete as a fallback

-- First, add RLS policy for admin delete on profiles (if not exists)
DO $$
BEGIN
    -- Check if policy exists before creating
    IF NOT EXISTS (
        SELECT 1 FROM pg_policies 
        WHERE tablename = 'profiles' 
        AND policyname = 'profiles_admin_delete'
    ) THEN
        -- Create policy allowing admins to delete unapproved profiles
        CREATE POLICY profiles_admin_delete ON public.profiles
            FOR DELETE
            TO authenticated
            USING (
                -- Target must be unapproved
                approved = false
                -- AND caller must be an admin
                AND EXISTS (
                    SELECT 1 FROM public.profiles
                    WHERE id = auth.uid() AND is_admin = true
                )
            );
        RAISE NOTICE 'Created profiles_admin_delete policy';
    ELSE
        RAISE NOTICE 'profiles_admin_delete policy already exists';
    END IF;
END $$;

-- Create the admin reject function (SECURITY DEFINER bypasses RLS)
CREATE OR REPLACE FUNCTION admin_reject_pending_user(
    p_user_id UUID
)
RETURNS jsonb
LANGUAGE plpgsql
SECURITY DEFINER
SET search_path = public
AS $$
DECLARE
    v_caller_id UUID;
    v_caller_is_admin BOOLEAN;
    v_target_approved BOOLEAN;
    v_rows_deleted INTEGER;
BEGIN
    -- Get caller's ID from auth context
    v_caller_id := auth.uid();
    
    IF v_caller_id IS NULL THEN
        RETURN jsonb_build_object(
            'success', false,
            'error', 'Not authenticated'
        );
    END IF;
    
    -- Check if caller is admin
    SELECT is_admin INTO v_caller_is_admin
    FROM profiles
    WHERE id = v_caller_id;
    
    IF NOT v_caller_is_admin OR v_caller_is_admin IS NULL THEN
        RETURN jsonb_build_object(
            'success', false,
            'error', 'Not authorized - admin access required'
        );
    END IF;
    
    -- Check if target user exists and is unapproved
    SELECT approved INTO v_target_approved
    FROM profiles
    WHERE id = p_user_id;
    
    IF v_target_approved IS NULL THEN
        RETURN jsonb_build_object(
            'success', false,
            'error', 'User not found'
        );
    END IF;
    
    IF v_target_approved = true THEN
        RETURN jsonb_build_object(
            'success', false,
            'error', 'Cannot reject an already approved user'
        );
    END IF;
    
    -- Delete the profile
    DELETE FROM profiles WHERE id = p_user_id AND approved = false;
    GET DIAGNOSTICS v_rows_deleted = ROW_COUNT;
    
    IF v_rows_deleted = 0 THEN
        RETURN jsonb_build_object(
            'success', false,
            'error', 'Delete failed - no rows affected'
        );
    END IF;
    
    -- Log the rejection
    RAISE NOTICE 'Admin % rejected pending user %', v_caller_id, p_user_id;
    
    RETURN jsonb_build_object(
        'success', true,
        'deleted_user_id', p_user_id,
        'rows_deleted', v_rows_deleted
    );
END;
$$;

-- Grant execute permission to authenticated users
GRANT EXECUTE ON FUNCTION admin_reject_pending_user TO authenticated;

-- Add comment
COMMENT ON FUNCTION admin_reject_pending_user IS 
'Rejects a pending user by deleting their profile. Only admins can call this. 
Returns JSON with success status and error message if failed.';


