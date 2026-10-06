-- Security hardening: lock down SECURITY DEFINER function grants and
-- close one missing auth check on cleanup_orphaned_auth_user.
--
-- Audit ref: Supabase database linter (2026-05-02 advisor pull):
--   - anon_security_definer_function_executable
--   - authenticated_security_definer_function_executable
--
-- Survey results (2026-05-02):
-- Reviewed 12 SECURITY DEFINER functions called from iOS or admin flows.
-- 11 of 12 already enforce `auth.uid()` / `is_admin` in their function
-- bodies — the linter findings on those are defense-in-depth noise.
-- ONE function (cleanup_orphaned_auth_user) had no `auth.uid()` check,
-- allowing any caller — including anon — to invoke it with any UUID.
-- Damage was bounded by an in-body guard that refuses deletion when a
-- profile exists for the target, but the parameter was still trusted.
-- Practical risks: (1) UUID-existence enumeration of orphan auth rows,
-- (2) racing in-progress signups by deleting the auth row before the
-- profile insert lands.
--
-- This migration does two independent things:
--
--   STEP A: Add `auth.uid() = p_user_id` check to cleanup_orphaned_auth_user.
--           The existing callers (email signup failure cleanup at
--           AuthService.swift:307; Apple Sign In no-profile cleanup at
--           AuthService+AppleSignIn.swift:194) both run with an active
--           Supabase auth session for the user being cleaned up, so
--           the new check passes for legitimate callers.
--
--   STEP B: Revoke EXECUTE FROM PUBLIC, anon on the 11 verified functions
--           (4 user-self + 7 admin-only). `authenticated` retains EXECUTE
--           — the iOS app calls these while signed in, and the in-body
--           `auth.uid()` / `is_admin` checks remain the real authorization
--           gate. service_role and postgres grants are unchanged.
--
-- Why `authenticated` is preserved on admin_* functions:
-- These RPCs are called by signed-in admins from the iOS app. The
-- in-body `is_admin = true` check rejects non-admins. Removing the
-- `authenticated` grant would require routing admin calls through an
-- edge function or a distinct admin role, which is a larger refactor
-- and out of scope for this fix.
--
-- Rollback:
--   STEP A: re-deploy the prior cleanup_orphaned_auth_user body (without
--           the auth check) by reverting this migration's CREATE OR REPLACE.
--   STEP B: GRANT EXECUTE ON FUNCTION ... TO PUBLIC, anon;
--           (apply per function; signatures listed below.)

-- -----------------------------------------------------------------------
-- STEP A: cleanup_orphaned_auth_user — add auth.uid() check
-- -----------------------------------------------------------------------

CREATE OR REPLACE FUNCTION public.cleanup_orphaned_auth_user(p_user_id uuid)
 RETURNS jsonb
 LANGUAGE plpgsql
 SECURITY DEFINER
 SET search_path TO 'public'
AS $function$
DECLARE
    v_has_profile BOOLEAN;
BEGIN
    -- Caller may only clean up their own orphan auth row.
    -- Both legitimate callers run with an active session for p_user_id.
    IF auth.uid() IS NULL OR auth.uid() <> p_user_id THEN
        RETURN jsonb_build_object(
            'success', false,
            'error', 'Not authorized'
        );
    END IF;

    SELECT EXISTS(SELECT 1 FROM profiles WHERE id = p_user_id) INTO v_has_profile;

    IF v_has_profile THEN
        RETURN jsonb_build_object(
            'success', false,
            'error', 'User has a profile - will not delete'
        );
    END IF;

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
$function$;

-- -----------------------------------------------------------------------
-- STEP B: Revoke EXECUTE from PUBLIC and anon on verified functions.
-- -----------------------------------------------------------------------
-- User-self functions (caller acts on their own account):

REVOKE EXECUTE ON FUNCTION public.delete_user_account(uuid)               FROM PUBLIC, anon;
REVOKE EXECUTE ON FUNCTION public.link_apple_identity(uuid, text, text)   FROM PUBLIC, anon;
REVOKE EXECUTE ON FUNCTION public.unlink_apple_identity(uuid)             FROM PUBLIC, anon;
REVOKE EXECUTE ON FUNCTION public.cleanup_orphaned_auth_user(uuid)        FROM PUBLIC, anon;

-- Admin-only functions (in-body is_admin check; authenticated retained
-- because admins are signed-in users):

REVOKE EXECUTE ON FUNCTION public.admin_dashboard_stats()                                    FROM PUBLIC, anon;
REVOKE EXECUTE ON FUNCTION public.admin_get_reports(uuid, text)                              FROM PUBLIC, anon;
REVOKE EXECUTE ON FUNCTION public.admin_moderate_content(uuid, uuid, text, text)             FROM PUBLIC, anon;
REVOKE EXECUTE ON FUNCTION public.admin_reject_pending_user(uuid)                            FROM PUBLIC, anon;
REVOKE EXECUTE ON FUNCTION public.admin_stats_active_rides()                                 FROM PUBLIC, anon;
REVOKE EXECUTE ON FUNCTION public.admin_stats_fulfilled(text, integer)                       FROM PUBLIC, anon;
REVOKE EXECUTE ON FUNCTION public.admin_stats_savings(text, integer)                         FROM PUBLIC, anon;
