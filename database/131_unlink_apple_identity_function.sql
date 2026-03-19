-- Migration 131: Capture unlink_apple_identity function with auth-method guard
-- This function was created ad-hoc in the live DB without a migration.
-- This migration captures it and adds a safety guard: the user must have at least
-- one non-Apple identity (e.g. email/password) before Apple can be unlinked.
-- Without this guard, Apple-only users could strand their account.

CREATE OR REPLACE FUNCTION unlink_apple_identity(p_user_id UUID)
RETURNS jsonb
LANGUAGE plpgsql
SECURITY DEFINER
SET search_path = public
AS $$
DECLARE
    v_caller_id UUID;
    v_non_apple_count INTEGER;
    v_rows_deleted INTEGER;
BEGIN
    -- Verify the caller is unlinking their own account
    v_caller_id := auth.uid();
    IF v_caller_id IS NULL OR v_caller_id != p_user_id THEN
        RETURN jsonb_build_object(
            'success', false,
            'error', 'Not authorized'
        );
    END IF;

    -- Guard: must have at least one non-Apple identity to fall back on
    SELECT COUNT(*) INTO v_non_apple_count
    FROM auth.identities
    WHERE user_id = p_user_id AND provider != 'apple';

    IF v_non_apple_count = 0 THEN
        RETURN jsonb_build_object(
            'success', false,
            'error', 'Cannot unlink Apple ID — it is your only sign-in method. Please add a password first.'
        );
    END IF;

    -- Remove Apple identity
    DELETE FROM auth.identities
    WHERE user_id = p_user_id AND provider = 'apple';
    GET DIAGNOSTICS v_rows_deleted = ROW_COUNT;

    RETURN jsonb_build_object(
        'success', true,
        'removed', v_rows_deleted
    );
EXCEPTION WHEN OTHERS THEN
    RETURN jsonb_build_object(
        'success', false,
        'error', SQLERRM
    );
END;
$$;

GRANT EXECUTE ON FUNCTION unlink_apple_identity TO authenticated;

COMMENT ON FUNCTION unlink_apple_identity IS 'Removes Apple identity from auth.identities for the calling user. Requires at least one other identity (e.g. email/password) to exist — prevents stranding Apple-only accounts.';
