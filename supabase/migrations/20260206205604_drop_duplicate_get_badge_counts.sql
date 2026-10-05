-- 20260206205604_drop_duplicate_get_badge_counts.sql
-- Exported verbatim from supabase_migrations.schema_migrations on 2026-10-05.
-- This migration was applied to production through the Supabase MCP / dashboard before being committed.

-- Drop the OLD duplicate get_badge_counts function that uses unqualified table references.
-- The newer version (p_user_id uuid, p_include_details boolean) is the correct one
-- with properly qualified public.* table references.
-- This resolves PostgREST PGRST203 ambiguity error.

DROP FUNCTION IF EXISTS public.get_badge_counts(boolean, uuid);

-- Verify only one function remains
DO $$
DECLARE
    func_count integer;
BEGIN
    SELECT count(*) INTO func_count
    FROM pg_proc
    WHERE proname = 'get_badge_counts'
      AND pronamespace = (SELECT oid FROM pg_namespace WHERE nspname = 'public');
    
    IF func_count != 1 THEN
        RAISE EXCEPTION 'Expected exactly 1 get_badge_counts function, found %', func_count;
    END IF;
END $$;

-- Ensure the remaining function has correct security and grants
ALTER FUNCTION public.get_badge_counts(uuid, boolean) SET search_path = '';
ALTER FUNCTION public.get_badge_counts(uuid, boolean) SECURITY DEFINER;
GRANT EXECUTE ON FUNCTION public.get_badge_counts(uuid, boolean) TO authenticated;