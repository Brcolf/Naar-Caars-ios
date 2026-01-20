-- Migration: 074_create_mark_invite_used_function.sql
-- Purpose: Create a function for marking invite codes as used during signup
-- This bypasses RLS using SECURITY DEFINER since auth.uid() may not be set after signup

CREATE OR REPLACE FUNCTION mark_invite_code_used(
    p_invite_code_id TEXT,
    p_user_id TEXT,
    p_is_bulk TEXT DEFAULT 'false',
    p_bulk_code_id TEXT DEFAULT NULL
)
RETURNS jsonb
LANGUAGE plpgsql
SECURITY DEFINER
SET search_path = public
AS $$
DECLARE
    v_invite_code_id UUID;
    v_user_id UUID;
    v_is_bulk BOOLEAN;
    v_bulk_code_id UUID;
    v_code_exists BOOLEAN;
    v_code_used BOOLEAN;
    v_tracking_code TEXT;
    v_new_record_id UUID;
BEGIN
    -- Parse parameters (accepting TEXT for flexibility from client)
    BEGIN
        v_invite_code_id := p_invite_code_id::UUID;
    EXCEPTION WHEN OTHERS THEN
        RETURN jsonb_build_object('success', false, 'error', 'Invalid invite code ID format');
    END;
    
    BEGIN
        v_user_id := p_user_id::UUID;
    EXCEPTION WHEN OTHERS THEN
        RETURN jsonb_build_object('success', false, 'error', 'Invalid user ID format');
    END;
    
    v_is_bulk := LOWER(p_is_bulk) = 'true';
    
    IF p_bulk_code_id IS NOT NULL AND p_bulk_code_id != '' THEN
        BEGIN
            v_bulk_code_id := p_bulk_code_id::UUID;
        EXCEPTION WHEN OTHERS THEN
            RETURN jsonb_build_object('success', false, 'error', 'Invalid bulk code ID format');
        END;
    END IF;
    
    -- Validate input
    IF v_invite_code_id IS NULL THEN
        RETURN jsonb_build_object(
            'success', false,
            'error', 'Invite code ID is required'
        );
    END IF;
    
    IF v_user_id IS NULL THEN
        RETURN jsonb_build_object(
            'success', false,
            'error', 'User ID is required'
        );
    END IF;
    
    -- Check if invite code exists
    SELECT EXISTS (
        SELECT 1 FROM invite_codes WHERE id = v_invite_code_id
    ) INTO v_code_exists;
    
    IF NOT v_code_exists THEN
        RETURN jsonb_build_object(
            'success', false,
            'error', 'Invite code not found'
        );
    END IF;
    
    IF v_is_bulk THEN
        -- For bulk codes: Create a tracking record
        -- Generate tracking code
        v_tracking_code := (
            SELECT code || '-' || UPPER(SUBSTRING(gen_random_uuid()::text, 1, 8))
            FROM invite_codes 
            WHERE id = v_invite_code_id
        );
        v_new_record_id := gen_random_uuid();
        
        INSERT INTO invite_codes (
            id,
            code,
            created_by,
            used_by,
            used_at,
            created_at,
            is_bulk,
            bulk_code_id
        )
        SELECT 
            v_new_record_id,
            v_tracking_code,
            created_by,  -- Same creator as bulk code
            v_user_id,
            NOW(),
            NOW(),
            false,  -- Tracking record is not bulk
            v_invite_code_id  -- Reference to the bulk code
        FROM invite_codes
        WHERE id = v_invite_code_id;
        
        RETURN jsonb_build_object(
            'success', true,
            'message', 'Bulk code tracking record created',
            'tracking_id', v_new_record_id
        );
    ELSE
        -- For regular codes: Check if already used
        SELECT used_by IS NOT NULL INTO v_code_used
        FROM invite_codes 
        WHERE id = v_invite_code_id;
        
        IF v_code_used THEN
            -- Already used - this can happen on re-signup after rejection
            -- Just return success, the code was already marked
            RETURN jsonb_build_object(
                'success', true,
                'message', 'Invite code was already used'
            );
        END IF;
        
        -- Mark as used
        UPDATE invite_codes
        SET 
            used_by = v_user_id,
            used_at = NOW()
        WHERE id = v_invite_code_id
        AND used_by IS NULL;
        
        RETURN jsonb_build_object(
            'success', true,
            'message', 'Invite code marked as used'
        );
    END IF;
    
EXCEPTION WHEN OTHERS THEN
    RETURN jsonb_build_object(
        'success', false,
        'error', SQLERRM
    );
END;
$$;

-- Grant execute permission to authenticated users
GRANT EXECUTE ON FUNCTION mark_invite_code_used TO authenticated;

-- Also grant to anon for cases where session isn't fully established yet
GRANT EXECUTE ON FUNCTION mark_invite_code_used TO anon;

-- Add comment
COMMENT ON FUNCTION mark_invite_code_used IS 
'Marks an invite code as used during signup. Uses SECURITY DEFINER to bypass RLS.
Handles both regular codes (marks as used) and bulk codes (creates tracking record).';

