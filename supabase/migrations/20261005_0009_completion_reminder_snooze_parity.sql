-- 20261005_0009_completion_reminder_snooze_parity.sql
--
-- Follow-up to 20261005_0006. That cap gated re-sends on reminder_count, but a "Not yet"
-- answer (handle_completion_response with p_completed = false) also incremented
-- reminder_count, so a snooze after the second send could never fire again and a snooze
-- after the first fired 4 h later instead of the promised 1 h.
--
-- Now:
--   * process_completion_reminders() fires whenever scheduled_for <= now() (and the request is
--     still confirmed for this claimer), counts only its own sends in reminder_count, caps at 3
--     sends, and schedules the next send itself: +30 min after the first, +4 h after the second.
--   * handle_completion_response(false) only moves scheduled_for to now() + 1 h; it no longer
--     touches reminder_count, so a user can snooze any number of times and still receive the
--     remaining sends.

create or replace function public.process_completion_reminders()
returns integer
language plpgsql
set search_path to ''
as $function$
declare
    v_reminder record;
    v_request_title text;
    v_count integer := 0;
    v_notification_id uuid;
    v_sends integer;
begin
    for v_reminder in
        select * from public.completion_reminders
        where scheduled_for <= now()
          and completed = false
          and reminder_count < 3
    loop
        -- Skip (and close) reminders whose request is no longer confirmed for this claimer.
        if v_reminder.ride_id is not null then
            if not exists (
                select 1 from public.rides
                where id = v_reminder.ride_id
                  and status = 'confirmed'
                  and claimed_by = v_reminder.claimer_user_id
            ) then
                update public.completion_reminders set completed = true where id = v_reminder.id;
                continue;
            end if;
            select destination into v_request_title from public.rides where id = v_reminder.ride_id;
            v_request_title := 'ride to ' || coalesce(v_request_title, 'destination');
        else
            if not exists (
                select 1 from public.favors
                where id = v_reminder.favor_id
                  and status = 'confirmed'
                  and claimed_by = v_reminder.claimer_user_id
            ) then
                update public.completion_reminders set completed = true where id = v_reminder.id;
                continue;
            end if;
            select title into v_request_title from public.favors where id = v_reminder.favor_id;
            v_request_title := coalesce(v_request_title, 'your favor');
        end if;

        v_notification_id := public.create_notification(
            v_reminder.claimer_user_id, 'completion_reminder', 'Is This Complete?',
            'Did you complete the ' || v_request_title || '?',
            v_reminder.ride_id, v_reminder.favor_id, null, null, null, null
        );

        if v_notification_id is not null then
            perform public.queue_push_notification(
                v_reminder.claimer_user_id, 'completion_reminder', 'Is This Complete?',
                'Did you complete the ' || v_request_title || '?',
                jsonb_build_object(
                    'reminder_id', v_reminder.id::text,
                    'ride_id', v_reminder.ride_id::text,
                    'favor_id', v_reminder.favor_id::text,
                    'actionable', true
                ), null, v_notification_id
            );
        end if;

        v_sends := v_reminder.reminder_count + 1;
        update public.completion_reminders
        set last_reminded_at = now(),
            reminder_count = v_sends,
            -- Next send: 30 min after the first, 4 h after the second; nothing after the third.
            scheduled_for = case v_sends
                when 1 then now() + interval '30 minutes'
                when 2 then now() + interval '4 hours'
                else scheduled_for
            end
        where id = v_reminder.id;

        v_count := v_count + 1;
    end loop;

    return v_count;
end;
$function$;

create or replace function public.handle_completion_response(p_reminder_id uuid, p_completed boolean)
returns jsonb
language plpgsql
security definer
set search_path to ''
as $function$
declare
    v_reminder record;
    v_request_title text;
    v_requestor_id uuid;
    v_notification_id uuid;
begin
    select * into v_reminder from public.completion_reminders where id = p_reminder_id;

    if not found then
        return jsonb_build_object('success', false, 'error', 'Reminder not found');
    end if;

    if auth.uid() is null or auth.uid() != v_reminder.claimer_user_id then
        return jsonb_build_object('success', false, 'error', 'Only the claimer can respond to this reminder');
    end if;

    if p_completed then
        if v_reminder.ride_id is not null then
            update public.rides set status = 'completed' where id = v_reminder.ride_id;
            select user_id, destination into v_requestor_id, v_request_title
            from public.rides where id = v_reminder.ride_id;
        else
            update public.favors set status = 'completed' where id = v_reminder.favor_id;
            select user_id, title into v_requestor_id, v_request_title
            from public.favors where id = v_reminder.favor_id;
        end if;

        update public.completion_reminders set completed = true where id = p_reminder_id;

        v_notification_id := public.create_notification(
            v_requestor_id, 'review_request', 'How was your experience?',
            'Your request has been completed. Leave a review to thank your helper!',
            v_reminder.ride_id, v_reminder.favor_id, null, null, null, v_reminder.claimer_user_id
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
        -- Snooze: ask again in an hour. Does not count against the send cap.
        update public.completion_reminders
        set scheduled_for = now() + interval '1 hour',
            last_reminded_at = now()
        where id = p_reminder_id;

        return jsonb_build_object('success', true, 'action', 'snoozed',
            'next_reminder', now() + interval '1 hour');
    end if;
end;
$function$;
