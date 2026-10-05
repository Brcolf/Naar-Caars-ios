-- 20260304163320_tighten_rls_policies.sql
-- Exported verbatim from supabase_migrations.schema_migrations on 2026-10-05.
-- This migration was applied to production through the Supabase MCP / dashboard before being committed.

-- 1. notifications: drop the overly permissive INSERT policy (keep the scoped one)
DROP POLICY IF EXISTS "notifications_insert_authenticated" ON notifications;

-- 2. notification_queue: restrict to service_role only (triggers bypass RLS via SECURITY DEFINER)
DROP POLICY IF EXISTS "notification_queue_insert_authenticated" ON notification_queue;
DROP POLICY IF EXISTS "notification_queue_select_service" ON notification_queue;
DROP POLICY IF EXISTS "notification_queue_update_service" ON notification_queue;

-- Recreate with service_role restriction (effectively no client access)
CREATE POLICY "notification_queue_select_service_role" ON notification_queue
    FOR SELECT TO service_role USING (true);
CREATE POLICY "notification_queue_insert_service_role" ON notification_queue
    FOR INSERT TO service_role WITH CHECK (true);
CREATE POLICY "notification_queue_update_service_role" ON notification_queue
    FOR UPDATE TO service_role USING (true) WITH CHECK (true);

-- 3. completion_reminders: the INSERT with_check(true) is used by triggers (SECURITY DEFINER).
-- Keep as-is since triggers bypass RLS. The SELECT is already scoped to own rows.

-- 4. geocoding_cache: this is a shared cache — any authenticated user should be able
-- to read/write. WITH CHECK (true) is intentional here for a shared cache table.