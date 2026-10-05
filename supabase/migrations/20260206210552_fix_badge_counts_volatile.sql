-- 20260206210552_fix_badge_counts_volatile.sql
-- Exported verbatim from supabase_migrations.schema_migrations on 2026-10-05.
-- This migration was applied to production through the Supabase MCP / dashboard before being committed.

-- Fix: Mark get_badge_counts as VOLATILE since it contains UPDATE statements.
-- The function was incorrectly set to STABLE, causing PostgREST to wrap calls
-- in read-only transactions where UPDATE is not permitted.

ALTER FUNCTION public.get_badge_counts(uuid, boolean) VOLATILE;
