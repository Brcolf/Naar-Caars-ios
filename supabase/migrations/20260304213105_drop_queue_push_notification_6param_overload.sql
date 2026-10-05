-- 20260304213105_drop_queue_push_notification_6param_overload.sql
-- Exported verbatim from supabase_migrations.schema_migrations on 2026-10-05.
-- This migration was applied to production through the Supabase MCP / dashboard before being committed.


-- Drop the old 6-parameter overload of queue_push_notification.
-- The 7-parameter version (with p_notification_id UUID DEFAULT NULL)
-- handles all use cases. Having both causes PostgREST PGRST203 errors
-- because it cannot disambiguate between the two when called with
-- default parameter values.
DROP FUNCTION IF EXISTS public.queue_push_notification(UUID, TEXT, TEXT, TEXT, JSONB, TEXT);
