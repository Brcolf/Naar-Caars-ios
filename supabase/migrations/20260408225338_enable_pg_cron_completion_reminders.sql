-- 20260408225338_enable_pg_cron_completion_reminders.sql
-- Exported verbatim from supabase_migrations.schema_migrations on 2026-10-05.
-- This migration was applied to production through the Supabase MCP / dashboard before being committed.

-- Enable pg_cron extension
CREATE EXTENSION IF NOT EXISTS pg_cron;

-- Schedule process_completion_reminders to run every 5 minutes
SELECT cron.schedule(
    'process-completion-reminders',
    '*/5 * * * *',
    $$SELECT public.process_completion_reminders()$$
);
