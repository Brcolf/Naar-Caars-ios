-- 20261005_0026_link_apple_identity_interim_hardening.sql
--
-- Step 1 is APPLIED. Verified live on 2026-10-06: the deployed body is byte-identical to this
-- file, and a rolled-back probe showed: first link succeeds and stores no email
-- (identity_data has no email key, identities.email is null); linking the same Apple ID again
-- returns success; a second Apple ID on the same account, an Apple ID already on another
-- account, a caller other than p_user_id and a blank subject are all refused.
-- STILL TO DO: the real-device Sign in with Apple test below, and Step 2 (a client that links
-- with linkIdentityWithIdToken, then the REVOKE). Until Step 2 the Apple subject is still
-- caller-supplied, so an account that knows someone's Apple subject can still claim it.
--
-- link_apple_identity(p_user_id, p_apple_sub, p_apple_email) verifies only that the caller is
-- p_user_id. The Apple subject and email are plain caller-supplied text written into
-- auth.identities as a verified identity (the Swift caller decodes the Apple JWT without
-- verifying its signature). Any signed-in account can therefore plant an Apple identity carrying
-- someone else's email on its own account, and there is no limit on how many. GoTrue matches a
-- first-time Apple sign-in against auth.identities.email, so:
--   * a person with no account yet who signs in with Apple using that email is linked INTO THE
--     ATTACKER'S ACCOUNT (shared account; the attacker keeps the password);
--   * a person who already has an email/password account can no longer sign in with or link Apple;
--   * with a known Apple subject, the victim's Sign in with Apple is routed to the attacker.
-- (GoTrue behaviour is taken from its source; it was not exercised.)
--
-- Step 1 below is an interim hardening that keeps the shipped client working: same signature and
-- grants, at most one Apple identity per account, and the email is no longer stored (GoTrue
-- rewrites identity_data from verified claims on the first real Apple sign-in).
-- The real fix is client-side: link with
--   auth.linkIdentityWithIdToken(credentials: OpenIDConnectCredentials(provider: .apple, idToken:, nonce:))
-- so GoTrue verifies signature, audience and nonce, then revoke EXECUTE from authenticated (Step 2).
--
-- Test on a device before and after: link Apple to an email account, sign out, sign in with
-- Apple, unlink, re-link, and delete an Apple-linked account.

-- Step 1 (applied): interim hardening. Signature, parameter names and grants are unchanged,
-- so the shipped iOS client (AuthService.linkAppleAccount) keeps working.
-- Do NOT revoke EXECUTE from authenticated yet: that breaks "Link Apple ID" in the App Store build.
CREATE OR REPLACE FUNCTION public.link_apple_identity(p_user_id uuid, p_apple_sub text, p_apple_email text)
 RETURNS jsonb
 LANGUAGE plpgsql
 SECURITY DEFINER
 SET search_path TO 'public'
AS $function$
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

    -- NEW: reject empty / oversized subject values
    IF p_apple_sub IS NULL OR btrim(p_apple_sub) = '' OR length(p_apple_sub) > 255 THEN
        RETURN jsonb_build_object('success', false, 'error', 'Invalid Apple identity');
    END IF;

    -- UNCHANGED, and deliberately kept BEFORE the new guard so that re-linking the same
    -- Apple ID still returns success = true (the client throws on success = false)
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

    -- NEW: at most one Apple identity per account (stops planting unlimited rows)
    IF EXISTS (
        SELECT 1 FROM auth.identities
        WHERE user_id = p_user_id AND provider = 'apple'
    ) THEN
        RETURN jsonb_build_object(
            'success', false,
            'error', 'An Apple ID is already linked to this account'
        );
    END IF;

    -- NEW: p_apple_email is accepted only for client compatibility and is never stored.
    -- auth.identities.email is generated from identity_data ->> 'email' and GoTrue's account
    -- linking matches on that column without consulting email_verified, so the key must be absent.
    -- GoTrue rewrites identity_data with verified claims on the user's first real Apple sign-in.
    INSERT INTO auth.identities (
        id, user_id, provider_id, provider, identity_data,
        last_sign_in_at, created_at, updated_at
    ) VALUES (
        gen_random_uuid(),
        p_user_id,
        p_apple_sub,
        'apple',
        jsonb_build_object(
            'sub', p_apple_sub,
            'provider_id', p_apple_sub,
            'iss', 'https://appleid.apple.com',
            'email_verified', false,
            'phone_verified', false
        ),
        NOW(), NOW(), NOW()
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
$function$;

-- Step 2 (only after a client build that links with
--   SupabaseService.shared.client.auth.linkIdentityWithIdToken(credentials: OpenIDConnectCredentials(provider: .apple, idToken:, nonce:))
-- has shipped and older builds are retired; GoTrue then verifies signature, audience and nonce):
-- REVOKE EXECUTE ON FUNCTION public.link_apple_identity(uuid, text, text) FROM authenticated;

-- Step 3 (owner review in the SQL editor, read-only): Apple identities whose stored email is not the owning user's email
-- SELECT i.id, i.user_id, i.provider_id, i.created_at
-- FROM auth.identities i JOIN auth.users u ON u.id = i.user_id
-- WHERE i.provider = 'apple' AND i.email IS NOT NULL
--   AND i.email NOT LIKE '%@privaterelay.appleid.com'
--   AND i.email IS DISTINCT FROM lower(u.email);
