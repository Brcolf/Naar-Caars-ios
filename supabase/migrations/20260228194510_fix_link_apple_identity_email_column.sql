-- 20260228194510_fix_link_apple_identity_email_column.sql
-- Exported verbatim from supabase_migrations.schema_migrations on 2026-10-05.
-- This migration was applied to production through the Supabase MCP / dashboard before being committed.


-- Fix: The 'email' column in auth.identities is generated from identity_data.
-- Remove it from the INSERT and let Supabase compute it automatically.
CREATE OR REPLACE FUNCTION link_apple_identity(
    p_user_id UUID,
    p_apple_sub TEXT,
    p_apple_email TEXT
)
RETURNS jsonb
LANGUAGE plpgsql
SECURITY DEFINER
SET search_path = public
AS $$
DECLARE
    v_caller_id UUID;
BEGIN
    v_caller_id := auth.uid();
    IF v_caller_id IS NULL OR v_caller_id != p_user_id THEN
        RETURN jsonb_build_object(
            'success', false,
            'error', 'Not authorized - can only link your own account'
        );
    END IF;

    IF EXISTS (
        SELECT 1 FROM auth.identities
        WHERE provider = 'apple' AND provider_id = p_apple_sub
    ) THEN
        IF EXISTS (
            SELECT 1 FROM auth.identities
            WHERE provider = 'apple' AND provider_id = p_apple_sub AND user_id = p_user_id
        ) THEN
            RETURN jsonb_build_object(
                'success', true,
                'message', 'Apple identity already linked to this account'
            );
        ELSE
            RETURN jsonb_build_object(
                'success', false,
                'error', 'This Apple ID is already linked to a different account'
            );
        END IF;
    END IF;

    INSERT INTO auth.identities (
        id,
        user_id,
        provider_id,
        provider,
        identity_data,
        last_sign_in_at,
        created_at,
        updated_at
    ) VALUES (
        gen_random_uuid(),
        p_user_id,
        p_apple_sub,
        'apple',
        jsonb_build_object(
            'sub', p_apple_sub,
            'email', p_apple_email,
            'email_verified', true,
            'phone_verified', false,
            'provider_id', p_apple_sub,
            'iss', 'https://appleid.apple.com'
        ),
        NOW(),
        NOW(),
        NOW()
    );

    RETURN jsonb_build_object(
        'success', true,
        'message', 'Apple identity linked successfully'
    );

EXCEPTION WHEN OTHERS THEN
    RETURN jsonb_build_object(
        'success', false,
        'error', SQLERRM
    );
END;
$$;
