-- 20260408224149_security_completion_reminders_tighten.sql
-- Exported verbatim from supabase_migrations.schema_migrations on 2026-10-05.
-- This migration was applied to production through the Supabase MCP / dashboard before being committed.


-- Security fix: Tighten completion_reminders INSERT/UPDATE policies
-- and add auth.uid() guard to handle_completion_response.
--
-- Live state:
--   SELECT: claimer_user_id = auth.uid() (good, unchanged)
--   INSERT: WITH CHECK (true) for authenticated (too broad)
--   UPDATE: USING (true) WITH CHECK (true) for authenticated (too broad)
--   handle_completion_response: NOT SECURITY DEFINER, no auth guard
--
-- Who INSERTs: only SECURITY DEFINER triggers (notify_ride/favor_status_change)
--   owned by postgres → bypass RLS. No Swift code inserts.
-- Who UPDATEs: handle_completion_response (Swift callers as claimer),
--   process_completion_reminders (cron as postgres), triggers (SECURITY DEFINER).
--
-- Audit ref: CRIT-3 (narrowed), HIGH-4 (corrected for live).

-- Tighten INSERT: only service_role (triggers bypass RLS via SECURITY DEFINER)
DROP POLICY IF EXISTS "completion_reminders_insert_service" ON public.completion_reminders;
CREATE POLICY "completion_reminders_insert_service_only"
ON public.completion_reminders FOR INSERT TO service_role
WITH CHECK (true);

-- Tighten UPDATE: own-row for authenticated, full for service_role
DROP POLICY IF EXISTS "completion_reminders_update_service" ON public.completion_reminders;

CREATE POLICY "completion_reminders_update_own"
ON public.completion_reminders FOR UPDATE TO authenticated
USING (claimer_user_id = auth.uid())
WITH CHECK (claimer_user_id = auth.uid());

CREATE POLICY "completion_reminders_update_service_role"
ON public.completion_reminders FOR UPDATE TO service_role
USING (true) WITH CHECK (true);

-- Add auth.uid() guard to handle_completion_response.
-- Keep as NOT SECURITY DEFINER — all internal operations work with caller's RLS:
--   UPDATE rides/favors: RLS allows claimed_by = auth.uid()
--   UPDATE completion_reminders: new policy allows claimer_user_id = auth.uid()
--   create_notification/queue_push_notification: SECURITY DEFINER RPCs
CREATE OR REPLACE FUNCTION public.handle_completion_response(
    p_reminder_id uuid,
    p_completed boolean
)
RETURNS jsonb
LANGUAGE plpgsql
SET search_path TO ''
AS $$
DECLARE
    v_reminder RECORD;
    v_request_title TEXT;
    v_requestor_id UUID;
    v_notification_id UUID;
BEGIN
    SELECT * INTO v_reminder FROM public.completion_reminders WHERE id = p_reminder_id;

    IF NOT FOUND THEN
        RETURN jsonb_build_object('success', false, 'error', 'Reminder not found');
    END IF;

    -- SECURITY FIX: Verify caller is the claimer
    IF auth.uid() IS NULL OR auth.uid() != v_reminder.claimer_user_id THEN
        RETURN jsonb_build_object('success', false, 'error', 'Only the claimer can respond to this reminder');
    END IF;

    IF p_completed THEN
        IF v_reminder.ride_id IS NOT NULL THEN
            UPDATE public.rides SET status = 'completed' WHERE id = v_reminder.ride_id;
            SELECT user_id, destination INTO v_requestor_id, v_request_title
            FROM public.rides WHERE id = v_reminder.ride_id;
        ELSE
            UPDATE public.favors SET status = 'completed' WHERE id = v_reminder.favor_id;
            SELECT user_id, title INTO v_requestor_id, v_request_title
            FROM public.favors WHERE id = v_reminder.favor_id;
        END IF;

        UPDATE public.completion_reminders SET completed = true WHERE id = p_reminder_id;

        v_notification_id := public.create_notification(
            v_requestor_id, 'review_request', 'How was your experience?',
            'Your request has been completed. Leave a review to thank your helper!',
            v_reminder.ride_id, v_reminder.favor_id, NULL, NULL, NULL, v_reminder.claimer_user_id
        );

        IF v_notification_id IS NOT NULL THEN
            PERFORM public.queue_push_notification(
                v_requestor_id, 'review_request', 'How was your experience?',
                'Your request has been completed. Leave a review!',
                jsonb_build_object('ride_id', v_reminder.ride_id::text, 'favor_id', v_reminder.favor_id::text, 'action', 'review'),
                NULL, v_notification_id
            );
        END IF;

        RETURN jsonb_build_object('success', true, 'action', 'completed');
    ELSE
        UPDATE public.completion_reminders
        SET scheduled_for = NOW() + INTERVAL '1 hour',
            reminder_count = reminder_count + 1,
            last_reminded_at = NOW()
        WHERE id = p_reminder_id;

        RETURN jsonb_build_object('success', true, 'action', 'snoozed',
            'next_reminder', NOW() + INTERVAL '1 hour');
    END IF;
END;
$$;
