-- 20260408213932_security_bulk_grant_revocations.sql
-- Exported verbatim from supabase_migrations.schema_migrations on 2026-10-05.
-- This migration was applied to production through the Supabase MCP / dashboard before being committed.


-- Security fix: Revoke PUBLIC and anon EXECUTE from dangerous functions.
-- All functions retain authenticated + service_role grants.
-- create_signup_profile is intentionally excluded (deferred to signup-hardening batch).
--
-- Live callers that use authenticated sessions:
--   queue_push_notification: ClaimService.swift (authenticated user claims ride/favor)
--   is_user_blocked: MessageService.swift (authenticated user checks block status)
--   handle_completion_response: PushNotificationService.swift, PromptSideEffects.swift
--   create_notification: DB triggers only (run as definer)
--   send_push_notification_direct: no Swift callers
--   mark_invite_code_used: unused RPC (InviteService uses direct table ops)

-- create_notification
REVOKE ALL ON FUNCTION public.create_notification FROM PUBLIC;
REVOKE ALL ON FUNCTION public.create_notification FROM anon;
GRANT EXECUTE ON FUNCTION public.create_notification TO authenticated;
GRANT EXECUTE ON FUNCTION public.create_notification TO service_role;

-- queue_push_notification (two overloads — use DO block)
DO $$
DECLARE
    r RECORD;
BEGIN
    FOR r IN
        SELECT oid FROM pg_proc
        WHERE proname = 'queue_push_notification'
        AND pronamespace = 'public'::regnamespace
    LOOP
        EXECUTE format('REVOKE ALL ON FUNCTION %s FROM PUBLIC', r.oid::regprocedure);
        EXECUTE format('REVOKE ALL ON FUNCTION %s FROM anon', r.oid::regprocedure);
        EXECUTE format('GRANT EXECUTE ON FUNCTION %s TO authenticated', r.oid::regprocedure);
        EXECUTE format('GRANT EXECUTE ON FUNCTION %s TO service_role', r.oid::regprocedure);
    END LOOP;
END;
$$;

-- send_push_notification_direct
REVOKE ALL ON FUNCTION public.send_push_notification_direct FROM PUBLIC;
REVOKE ALL ON FUNCTION public.send_push_notification_direct FROM anon;
GRANT EXECUTE ON FUNCTION public.send_push_notification_direct TO authenticated;
GRANT EXECUTE ON FUNCTION public.send_push_notification_direct TO service_role;

-- handle_completion_response
REVOKE ALL ON FUNCTION public.handle_completion_response FROM PUBLIC;
REVOKE ALL ON FUNCTION public.handle_completion_response FROM anon;
GRANT EXECUTE ON FUNCTION public.handle_completion_response TO authenticated;
GRANT EXECUTE ON FUNCTION public.handle_completion_response TO service_role;

-- mark_invite_code_used (unused RPC — revoke all except service_role)
REVOKE ALL ON FUNCTION public.mark_invite_code_used FROM PUBLIC;
REVOKE ALL ON FUNCTION public.mark_invite_code_used FROM anon;
REVOKE ALL ON FUNCTION public.mark_invite_code_used FROM authenticated;
GRANT EXECUTE ON FUNCTION public.mark_invite_code_used TO service_role;

-- is_user_blocked
REVOKE ALL ON FUNCTION public.is_user_blocked FROM PUBLIC;
REVOKE ALL ON FUNCTION public.is_user_blocked FROM anon;
GRANT EXECUTE ON FUNCTION public.is_user_blocked TO authenticated;
GRANT EXECUTE ON FUNCTION public.is_user_blocked TO service_role;

-- is_admin_user (used in profiles RLS policies — keep authenticated)
REVOKE ALL ON FUNCTION public.is_admin_user FROM PUBLIC;
REVOKE ALL ON FUNCTION public.is_admin_user FROM anon;
GRANT EXECUTE ON FUNCTION public.is_admin_user TO authenticated;
GRANT EXECUTE ON FUNCTION public.is_admin_user TO service_role;
