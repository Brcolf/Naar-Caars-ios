-- Migration 111: Auth user cleanup functions
-- Ensures auth.users entries are properly cleaned up when:
-- 1. Signup fails after auth user creation (orphaned auth user)
-- 2. User deletes their account
-- 3. Admin rejects a pending user

-- ============================================================
-- 1. New function: Clean up orphaned auth user on failed signup
-- Called from iOS when profile creation fails after auth.signUp()
-- ============================================================
CREATE OR REPLACE FUNCTION cleanup_orphaned_auth_user(p_user_id UUID)
RETURNS jsonb
LANGUAGE plpgsql
SECURITY DEFINER
SET search_path = public
AS $$
DECLARE
    v_has_profile BOOLEAN;
BEGIN
    -- Safety check: only delete if user has NO profile
    -- This prevents accidental deletion of valid users
    SELECT EXISTS(SELECT 1 FROM profiles WHERE id = p_user_id) INTO v_has_profile;

    IF v_has_profile THEN
        RETURN jsonb_build_object(
            'success', false,
            'error', 'User has a profile - will not delete'
        );
    END IF;

    -- Delete from auth.users (cascades to auth.identities, auth.sessions, etc.)
    DELETE FROM auth.users WHERE id = p_user_id;

    RETURN jsonb_build_object(
        'success', true,
        'message', 'Orphaned auth user deleted'
    );
EXCEPTION WHEN OTHERS THEN
    RETURN jsonb_build_object(
        'success', false,
        'error', SQLERRM
    );
END;
$$;

-- ============================================================
-- 2. Update delete_user_account to also delete auth.users entry
-- ============================================================
CREATE OR REPLACE FUNCTION delete_user_account(p_user_id UUID)
RETURNS VOID
LANGUAGE plpgsql
SECURITY DEFINER
SET search_path = public
AS $$
BEGIN
    -- Delete all user data from public tables
    DELETE FROM push_tokens WHERE user_id = p_user_id;
    DELETE FROM notifications WHERE user_id = p_user_id;
    DELETE FROM reviews WHERE fulfiller_id = p_user_id OR reviewer_id = p_user_id;
    DELETE FROM town_hall_posts WHERE user_id = p_user_id;
    DELETE FROM invite_codes WHERE created_by = p_user_id;
    DELETE FROM messages WHERE from_id = p_user_id;
    DELETE FROM conversation_participants WHERE user_id = p_user_id;
    DELETE FROM conversations WHERE created_by = p_user_id;
    DELETE FROM rides WHERE user_id = p_user_id;
    DELETE FROM favors WHERE user_id = p_user_id;
    DELETE FROM request_qa WHERE user_id = p_user_id;
    DELETE FROM profiles WHERE id = p_user_id;

    -- Delete the auth user so the email can be re-used
    DELETE FROM auth.users WHERE id = p_user_id;
END $$;

-- ============================================================
-- 3. Update admin_reject_pending_user to also delete auth.users
-- ============================================================
CREATE OR REPLACE FUNCTION admin_reject_pending_user(p_user_id UUID)
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
    v_caller_id := auth.uid();

    -- Verify caller is admin
    SELECT is_admin INTO v_caller_is_admin FROM profiles WHERE id = v_caller_id;
    IF NOT v_caller_is_admin THEN
        RETURN jsonb_build_object('success', false, 'error', 'Not authorized - admin access required');
    END IF;

    -- Check target is unapproved
    SELECT approved INTO v_target_approved FROM profiles WHERE id = p_user_id;
    IF v_target_approved = true THEN
        RETURN jsonb_build_object('success', false, 'error', 'Cannot reject an already approved user');
    END IF;

    -- Delete the profile
    DELETE FROM profiles WHERE id = p_user_id AND approved = false;
    GET DIAGNOSTICS v_rows_deleted = ROW_COUNT;

    -- Delete the auth user so the email can be re-used for a new signup
    DELETE FROM auth.users WHERE id = p_user_id;

    RETURN jsonb_build_object(
        'success', true,
        'deleted_user_id', p_user_id,
        'rows_deleted', v_rows_deleted
    );
END $$;
