-- 20261005_0018_completion_response_state_checks.sql
--
-- APPLIED 2026-10-05 (Supabase MCP, two calls) and verified with a rolled-back probe.
--
-- handle_completion_response() trusted the reminder row and completed whatever ride or favor it
-- pointed at, in any state. completion_reminders was client-writable (table-level UPDATE grant
-- plus the completion_reminders_update_own policy), so a claimer could repoint their own
-- reminder at any request in the app and complete it; the same call could be replayed to send
-- the poster repeated review_request pushes.
--
-- 1. The client only SELECTs completion_reminders (CompletionPromptProvider). Client roles lose
--    every write privilege on it. The completion_reminders_update_own policy is left in place
--    (inert without the grant; dropping a policy needs the SQL editor).
-- 2. The function now completes only a request that is still `confirmed` and still claimed by
--    the caller, ignores an already-handled reminder, and reports `already_handled` when the
--    request was completed by another path (for example the poster's Mark as Complete), without
--    creating a second review_request. Both client call sites ignore the response body, so the
--    new action value has no client impact.
--
-- Probe (begin/rollback, as the claimer): updating the reminder -> permission denied; a reminder
-- pointing at an open ride the caller does not claim -> success=false and the ride stays open;
-- snooze -> snoozed; complete -> completed with exactly one review_request; replay ->
-- already_handled.

revoke insert, update, delete, truncate, references, trigger on public.completion_reminders from anon, authenticated;

CREATE OR REPLACE FUNCTION public.handle_completion_response(p_reminder_id uuid, p_completed boolean)
 RETURNS jsonb
 LANGUAGE plpgsql
 SECURITY DEFINER
 SET search_path TO ''
AS $function$
declare
    v_caller uuid := auth.uid();
    v_reminder record;
    v_requestor_id uuid;
    v_notification_id uuid;
    v_already_completed boolean := false;
begin
    select * into v_reminder from public.completion_reminders where id = p_reminder_id;

    if not found then
        return jsonb_build_object('success', false, 'error', 'Reminder not found');
    end if;

    if v_caller is null or v_caller <> v_reminder.claimer_user_id then
        return jsonb_build_object('success', false, 'error', 'Only the claimer can respond to this reminder');
    end if;

    if v_reminder.completed then
        return jsonb_build_object('success', true, 'action', 'already_handled');
    end if;

    if p_completed then
        -- Complete only a request that is still confirmed and still claimed by the caller. The
        -- reminder row is not trusted on its own: it used to be client-writable.
        if v_reminder.ride_id is not null then
            update public.rides set status = 'completed'
            where id = v_reminder.ride_id and status = 'confirmed' and claimed_by = v_caller
            returning user_id into v_requestor_id;
            if v_requestor_id is null then
                select exists (select 1 from public.rides where id = v_reminder.ride_id and status = 'completed')
                into v_already_completed;
            end if;
        else
            update public.favors set status = 'completed'
            where id = v_reminder.favor_id and status = 'confirmed' and claimed_by = v_caller
            returning user_id into v_requestor_id;
            if v_requestor_id is null then
                select exists (select 1 from public.favors where id = v_reminder.favor_id and status = 'completed')
                into v_already_completed;
            end if;
        end if;

        update public.completion_reminders set completed = true where id = p_reminder_id;

        if v_requestor_id is null then
            if v_already_completed then
                -- e.g. the poster already marked it complete: nothing left to do, no second notification
                return jsonb_build_object('success', true, 'action', 'already_handled');
            end if;
            return jsonb_build_object('success', false, 'error', 'Request is not confirmed or you are no longer its claimer');
        end if;

        v_notification_id := public.create_notification(
            v_requestor_id, 'review_request', 'How was your experience?',
            'Your request has been completed. Leave a review to thank your helper!',
            v_reminder.ride_id, v_reminder.favor_id, null, null, null, v_caller
        );

        if v_notification_id is not null then
            perform public.queue_push_notification(
                v_requestor_id, 'review_request', 'How was your experience?',
                'Your request has been completed. Leave a review!',
                jsonb_build_object('ride_id', v_reminder.ride_id::text, 'favor_id', v_reminder.favor_id::text, 'action', 'review'),
                null, v_notification_id
            );
        end if;

        return jsonb_build_object('success', true, 'action', 'completed');
    else
        update public.completion_reminders
        set scheduled_for = now() + interval '1 hour',
            last_reminded_at = now()
        where id = p_reminder_id;

        return jsonb_build_object('success', true, 'action', 'snoozed',
            'next_reminder', now() + interval '1 hour');
    end if;
end;
$function$;
