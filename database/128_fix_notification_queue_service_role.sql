-- Fix: Restrict notification_queue access to service_role only
-- The live DB has proper restrictions, but source SQL in 082 has permissive policies.

DROP POLICY IF EXISTS notification_queue_insert_authenticated ON notification_queue;
DROP POLICY IF EXISTS notification_queue_select_service ON notification_queue;
DROP POLICY IF EXISTS notification_queue_update_service ON notification_queue;

-- Only service_role (via SECURITY DEFINER functions) should access this table
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
