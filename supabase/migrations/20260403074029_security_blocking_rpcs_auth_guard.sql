-- 20260403074029_security_blocking_rpcs_auth_guard.sql
-- Exported verbatim from supabase_migrations.schema_migrations on 2026-10-05.
-- This migration was applied to production through the Supabase MCP / dashboard before being committed.


-- Security fix: Add auth.uid() validation to blocking RPCs + tighten grants.
-- Live state: All three SECURITY DEFINER, no caller validation, granted to PUBLIC/anon/authenticated.
-- Audit ref: CRIT-5.

CREATE OR REPLACE FUNCTION public.block_user(
    p_blocker_id uuid,
    p_blocked_id uuid,
    p_reason text DEFAULT NULL::text
) RETURNS boolean
LANGUAGE plpgsql
SECURITY DEFINER
SET search_path TO ''
AS $$
BEGIN
    IF auth.uid() IS NULL OR auth.uid() != p_blocker_id THEN
        RAISE EXCEPTION 'Blocker ID must match authenticated user';
    END IF;

    IF p_blocker_id = p_blocked_id THEN
        RAISE EXCEPTION 'Cannot block yourself';
    END IF;

    INSERT INTO public.blocked_users (blocker_id, blocked_id, reason)
    VALUES (p_blocker_id, p_blocked_id, p_reason)
    ON CONFLICT (blocker_id, blocked_id) DO NOTHING;

    RETURN TRUE;
END;
$$;

CREATE OR REPLACE FUNCTION public.unblock_user(
    p_blocker_id uuid,
    p_blocked_id uuid
) RETURNS boolean
LANGUAGE plpgsql
SECURITY DEFINER
SET search_path TO ''
AS $$
BEGIN
    IF auth.uid() IS NULL OR auth.uid() != p_blocker_id THEN
        RAISE EXCEPTION 'Blocker ID must match authenticated user';
    END IF;

    DELETE FROM public.blocked_users
    WHERE blocker_id = p_blocker_id AND blocked_id = p_blocked_id;

    RETURN TRUE;
END;
$$;

CREATE OR REPLACE FUNCTION public.get_blocked_users(
    p_user_id uuid
) RETURNS TABLE (
    blocked_id uuid,
    blocked_name text,
    blocked_avatar_url text,
    blocked_at timestamptz,
    reason text
)
LANGUAGE plpgsql
SECURITY DEFINER
SET search_path TO ''
AS $$
BEGIN
    IF auth.uid() IS NULL OR auth.uid() != p_user_id THEN
        RAISE EXCEPTION 'User ID must match authenticated user';
    END IF;

    RETURN QUERY
    SELECT bu.blocked_id, p.name, p.avatar_url, bu.created_at, bu.reason
    FROM public.blocked_users bu
    JOIN public.profiles p ON p.id = bu.blocked_id
    WHERE bu.blocker_id = p_user_id
    ORDER BY bu.created_at DESC;
END;
$$;

-- Tighten grants for all three
REVOKE ALL ON FUNCTION public.block_user FROM PUBLIC;
REVOKE ALL ON FUNCTION public.block_user FROM anon;
GRANT EXECUTE ON FUNCTION public.block_user TO authenticated;
GRANT EXECUTE ON FUNCTION public.block_user TO service_role;

REVOKE ALL ON FUNCTION public.unblock_user FROM PUBLIC;
REVOKE ALL ON FUNCTION public.unblock_user FROM anon;
GRANT EXECUTE ON FUNCTION public.unblock_user TO authenticated;
GRANT EXECUTE ON FUNCTION public.unblock_user TO service_role;

REVOKE ALL ON FUNCTION public.get_blocked_users FROM PUBLIC;
REVOKE ALL ON FUNCTION public.get_blocked_users FROM anon;
GRANT EXECUTE ON FUNCTION public.get_blocked_users TO authenticated;
GRANT EXECUTE ON FUNCTION public.get_blocked_users TO service_role;
