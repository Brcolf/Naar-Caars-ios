-- 20260312032603_drop_duplicate_report_notification_trigger.sql
-- Exported verbatim from supabase_migrations.schema_migrations on 2026-10-05.
-- This migration was applied to production through the Supabase MCP / dashboard before being committed.

-- Remove duplicate report notification trigger.
-- The existing handle_new_report trigger already notifies admins.
DROP TRIGGER IF EXISTS on_report_submitted_notify ON public.reports;
DROP FUNCTION IF EXISTS public.notify_report_submitted();