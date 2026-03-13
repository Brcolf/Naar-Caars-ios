-- Fix: Tighten notifications INSERT policy from WITH CHECK (true) to auth.uid() scoped
-- The live DB has this fix, but source SQL in 081 still has WITH CHECK (true).

DROP POLICY IF EXISTS notifications_insert_authenticated ON notifications;
DROP POLICY IF EXISTS notifications_insert_service_only ON notifications;

CREATE POLICY notifications_insert_service_only ON notifications
    FOR INSERT TO authenticated
    WITH CHECK (auth.uid() = user_id);
