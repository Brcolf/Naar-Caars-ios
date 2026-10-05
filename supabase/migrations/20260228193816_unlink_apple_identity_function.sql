-- 20260228193816_unlink_apple_identity_function.sql
-- Exported verbatim from supabase_migrations.schema_migrations on 2026-10-05.
-- This migration was applied to production through the Supabase MCP / dashboard before being committed.


CREATE OR REPLACE FUNCTION unlink_apple_identity(p_user_id UUID)
RETURNS jsonb
LANGUAGE plpgsql
SECURITY DEFINER
SET search_path = public
AS $$
DECLARE
    v_caller_id UUID;
    v_rows_deleted INTEGER;
BEGIN
    v_caller_id := auth.uid();
    IF v_caller_id IS NULL OR v_caller_id != p_user_id THEN
        RETURN jsonb_build_object(
            'success', false,
            'error', 'Not authorized'
        );
    END IF;

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
