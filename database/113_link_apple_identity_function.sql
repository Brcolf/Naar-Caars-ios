-- Migration 113: Function to link Apple identity to existing user
-- The Supabase Swift SDK doesn't support linkIdentityWithIdToken,
-- so we insert directly into auth.identities via SECURITY DEFINER.
-- This enables Apple Sign-In login for email/password users who link their Apple ID.

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
    -- Verify the caller is the user being linked (security check)
    v_caller_id := auth.uid();
    IF v_caller_id IS NULL OR v_caller_id != p_user_id THEN
        RETURN jsonb_build_object(
            'success', false,
            'error', 'Not authorized - can only link your own account'
        );
    END IF;

    -- Check if this Apple identity is already linked to ANY user
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

    -- Note: 'email' column is omitted because it is a generated column
    -- in auth.identities (derived from identity_data->>'email')
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

GRANT EXECUTE ON FUNCTION link_apple_identity TO authenticated;
