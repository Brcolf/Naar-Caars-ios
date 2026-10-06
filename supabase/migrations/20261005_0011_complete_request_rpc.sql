-- 20261005_0011_complete_request_rpc.sql
--
-- "Mark as Complete" from the ride/favor detail screen. The client used to update the row
-- directly behind a poster-only guard, so the claimer (the person the completion reminder is
-- addressed to) could not close out a past request from the app, and the poster had no UI
-- for it at all. This RPC accepts either role, closes the open completion reminders in the
-- same transaction (so no stale "Did you complete?" prompt is surfaced afterwards), and sends
-- the poster the same review request that handle_completion_response() sends when the
-- reminder's "Yes" quick action is used. The status-change trigger still notifies the
-- participants.

create or replace function public.complete_request(p_request_type text, p_request_id uuid)
returns jsonb
language plpgsql
security definer
set search_path to ''
as $function$
declare
    v_caller uuid := auth.uid();
    v_poster uuid;
    v_claimer uuid;
    v_status text;
    v_title text;
    v_ride_id uuid;
    v_favor_id uuid;
    v_notification_id uuid;
begin
    if v_caller is null then
        raise exception 'Not authenticated';
    end if;

    if p_request_type = 'ride' then
        select user_id, claimed_by, status::text, destination
        into v_poster, v_claimer, v_status, v_title
        from public.rides where id = p_request_id for update;
        v_ride_id := p_request_id;
    elsif p_request_type = 'favor' then
        select user_id, claimed_by, status::text, title
        into v_poster, v_claimer, v_status, v_title
        from public.favors where id = p_request_id for update;
        v_favor_id := p_request_id;
    else
        raise exception 'Unknown request type %', p_request_type;
    end if;

    if v_poster is null then
        return jsonb_build_object('success', false, 'error', 'not_found');
    end if;

    if v_caller <> v_poster and (v_claimer is null or v_caller <> v_claimer) then
        raise exception 'Not authorized to complete this request';
    end if;

    if v_status <> 'confirmed' then
        return jsonb_build_object('success', false, 'error', 'not_confirmed', 'status', v_status);
    end if;

    if v_ride_id is not null then
        update public.rides set status = 'completed' where id = v_ride_id;
    else
        update public.favors set status = 'completed' where id = v_favor_id;
    end if;

    update public.completion_reminders
    set completed = true
    where completed = false
      and ((v_ride_id is not null and ride_id = v_ride_id)
        or (v_favor_id is not null and favor_id = v_favor_id));

    -- Same review request the reminder's "Yes" action produces (handle_completion_response).
    if v_claimer is not null then
        v_notification_id := public.create_notification(
            v_poster, 'review_request', 'How was your experience?',
            'Your request has been completed. Leave a review to thank your helper!',
            v_ride_id, v_favor_id, null, null, null, v_claimer
        );
        if v_notification_id is not null and v_caller <> v_poster then
            perform public.queue_push_notification(
                v_poster, 'review_request', 'How was your experience?',
                'Your request has been completed. Leave a review!',
                jsonb_build_object('ride_id', v_ride_id::text, 'favor_id', v_favor_id::text, 'action', 'review'),
                null, v_notification_id
            );
        end if;
    end if;

    return jsonb_build_object('success', true, 'completed_by', case when v_caller = v_poster then 'poster' else 'claimer' end);
end;
$function$;

revoke all on function public.complete_request(text, uuid) from public, anon;
grant execute on function public.complete_request(text, uuid) to authenticated;
