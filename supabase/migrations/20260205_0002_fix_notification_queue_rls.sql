-- Fix: Restrict notification_queue SELECT and UPDATE to service role only
-- Previously USING (true) allowed any authenticated user to read all queued notifications

DROP POLICY IF EXISTS "notification_queue_select_service" ON public.notification_queue;
CREATE POLICY "notification_queue_select_service"
    ON public.notification_queue
    FOR SELECT
    USING (auth.role() = 'service_role');

DROP POLICY IF EXISTS "notification_queue_update_service" ON public.notification_queue;
CREATE POLICY "notification_queue_update_service"
    ON public.notification_queue
    FOR UPDATE
    USING (auth.role() = 'service_role')
    WITH CHECK (auth.role() = 'service_role');

-- Keep INSERT policy as-is (triggers insert from authenticated context)
