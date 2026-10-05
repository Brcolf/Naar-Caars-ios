-- 20260313015250_fix_notification_queue_service_role_v2.sql
-- Exported verbatim from supabase_migrations.schema_migrations on 2026-10-05.
-- This migration was applied to production through the Supabase MCP / dashboard before being committed.

DROP POLICY IF EXISTS notification_queue_insert_authenticated ON notification_queue;
DROP POLICY IF EXISTS notification_queue_select_service ON notification_queue;
DROP POLICY IF EXISTS notification_queue_update_service ON notification_queue;
DROP POLICY IF EXISTS notification_queue_insert_service_role ON notification_queue;
DROP POLICY IF EXISTS notification_queue_select_service_role ON notification_queue;
DROP POLICY IF EXISTS notification_queue_update_service_role ON notification_queue;

CREATE POLICY notification_queue_insert_service_role ON notification_queue
    FOR INSERT TO service_role
    WITH CHECK (true);

CREATE POLICY notification_queue_select_service_role ON notification_queue
    FOR SELECT TO service_role
    USING (true);

CREATE POLICY notification_queue_update_service_role ON notification_queue
    FOR UPDATE TO service_role
    USING (true)
    WITH CHECK (true);