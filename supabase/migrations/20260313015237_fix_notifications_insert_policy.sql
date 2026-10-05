-- 20260313015237_fix_notifications_insert_policy.sql
-- Exported verbatim from supabase_migrations.schema_migrations on 2026-10-05.
-- This migration was applied to production through the Supabase MCP / dashboard before being committed.

DROP POLICY IF EXISTS notifications_insert_authenticated ON notifications;
DROP POLICY IF EXISTS notifications_insert_service_only ON notifications;

CREATE POLICY notifications_insert_service_only ON notifications
    FOR INSERT TO authenticated
    WITH CHECK (auth.uid() = user_id);