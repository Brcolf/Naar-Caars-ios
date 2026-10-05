-- 20260304163335_fix_mutable_search_path_functions.sql
-- Exported verbatim from supabase_migrations.schema_migrations on 2026-10-05.
-- This migration was applied to production through the Supabase MCP / dashboard before being committed.

ALTER FUNCTION public.find_dm_conversation SET search_path = public;
ALTER FUNCTION public.record_xp_on_completion SET search_path = public;
ALTER FUNCTION public.get_user_savings SET search_path = public;
ALTER FUNCTION public.get_user_xp_events SET search_path = public;
ALTER FUNCTION public.mark_messages_read_batch SET search_path = public;
ALTER FUNCTION public.get_user_total_savings SET search_path = public;
ALTER FUNCTION public.record_xp_on_request_created SET search_path = public;
ALTER FUNCTION public.record_xp_on_review SET search_path = public;
ALTER FUNCTION public.get_user_total_xp SET search_path = public;