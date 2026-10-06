-- 20261005_0006_completion_reminders_cap_and_badge_filters.sql
--
-- Applied through the Supabase MCP on 2026-10-05. The reminder gating below was superseded the
-- same day by 20261005_0009 (a "Not yet" snooze no longer counts against the cap and the
-- processor schedules its own next send); the badge-count change stands.
--
-- 1. process_completion_reminders(): cap and back off.
--    Observed 2026-10-05: one unanswered reminder produced 44 pushes in a day (every 30 min,
--    no limit). Now: at most 3 reminders per request (30 min, then 4 h, then 24 h after the
--    previous one), and nothing for requests that were completed or cancelled meanwhile.
--
-- 2. get_badge_counts(): messages badge ignores blocked users and muted conversations
--    (the Messages tab badge kept showing "1" for a conversation the list hid).

alter table public.completion_reminders
  add column if not exists reminder_count integer not null default 0;

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
    v_next_interval interval;
begin
    for v_reminder in
        select * from public.completion_reminders
        where scheduled_for <= now()
          and completed = false
          and reminder_count < 3
          -- 30 min after the first fire, 4 h after the second, 24 h after the third
          and (
            last_reminded_at is null
            or (reminder_count = 1 and last_reminded_at < now() - interval '30 minutes')
            or (reminder_count = 2 and last_reminded_at < now() - interval '4 hours')
          )
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

        update public.completion_reminders
        set last_reminded_at = now(),
            reminder_count = reminder_count + 1
        where id = v_reminder.id;

        v_count := v_count + 1;
    end loop;

    return v_count;
end;
$function$;

-- 2. Messages badge: exclude unread messages from users the viewer has blocked. The
--    conversations list hides those conversations (client-side filter), but the tab badge and
--    app-icon badge kept counting them. Muted conversations are deliberately still counted
--    (mute suppresses pushes, not unread state) — change the two `and not exists` blocks below
--    if the product decision is to exclude them too.
create or replace function public.get_badge_counts(p_include_details boolean default false, p_user_id uuid default null::uuid)
returns jsonb
language plpgsql
security definer
set search_path to ''
as $function$
declare
    v_user_id uuid;
    v_messages_total integer;
    v_requests_total integer;
    v_community_total integer;
    v_bell_total integer;
    v_request_details jsonb := '[]'::jsonb;
    v_conversation_details jsonb := '[]'::jsonb;
begin
    v_user_id := coalesce(auth.uid(), p_user_id);

    if auth.uid() is not null and p_user_id is not null and auth.uid() != p_user_id then
        raise exception 'Cannot query badge counts for other users';
    end if;

    if v_user_id is null then
        raise exception 'User not authenticated';
    end if;

    -- Messages: total unread for user only in active conversations, excluding blocked senders
    select coalesce(count(*), 0)::int
    into v_messages_total
    from public.messages m
    join public.conversation_participants cp
        on cp.conversation_id = m.conversation_id
        and cp.user_id = v_user_id
    where cp.left_at is null
      and m.from_id <> v_user_id
      and not (coalesce(m.read_by, array[]::uuid[]) @> array[v_user_id]::uuid[])
      and not exists (
          select 1 from public.blocked_users b
          where b.blocker_id = v_user_id and b.blocked_id = m.from_id
      );

    update public.notifications n
    set read = true
    where n.user_id = v_user_id
      and n.read = false
      and n.type in ('message', 'added_to_conversation')
      and n.conversation_id is not null
      and not exists (
          select 1 from public.messages m
          join public.conversation_participants cp
              on cp.conversation_id = m.conversation_id
              and cp.user_id = v_user_id
          where m.conversation_id = n.conversation_id
            and cp.left_at is null
            and m.from_id <> v_user_id
            and not (coalesce(m.read_by, array[]::uuid[]) @> array[v_user_id]::uuid[])
      );

    with unread_requests as (
        select distinct
            case
                when ride_id is not null then 'ride:' || ride_id::text
                when favor_id is not null then 'favor:' || favor_id::text
                else null
            end as request_key
        from public.notifications
        where user_id = v_user_id
          and read = false
          and type in (
              'new_ride', 'ride_update', 'ride_claimed', 'ride_unclaimed',
              'new_favor', 'favor_update', 'favor_claimed', 'favor_unclaimed',
              'completion_reminder', 'qa_activity', 'qa_question', 'qa_answer'
          )
    )
    select coalesce(count(*), 0)::int
    into v_requests_total
    from unread_requests
    where request_key is not null;

    select coalesce(count(*), 0)::int
    into v_community_total
    from public.notifications
    where user_id = v_user_id
      and read = false
      and type in ('town_hall_post', 'town_hall_comment', 'town_hall_reaction');

    with bell_fresh as (
        select *
        from public.notifications
        where user_id = v_user_id
          and type not in ('message', 'added_to_conversation')
          and (read = false or created_at > now() - interval '24 hours')
    ),
    latest_announcement as (
        select id
        from bell_fresh
        where type in ('announcement', 'admin_announcement', 'broadcast')
        order by created_at desc
        limit 1
    ),
    bell_pruned as (
        select * from bell_fresh
        where type not in ('announcement', 'admin_announcement', 'broadcast')
        union all
        select bf.* from bell_fresh bf
        where bf.id in (select id from latest_announcement)
    ),
    bell_groups as (
        select
            case
                when type in ('announcement', 'admin_announcement', 'broadcast')
                    then 'announcement:' || id::text
                when type in ('town_hall_post', 'town_hall_comment', 'town_hall_reaction')
                    and town_hall_post_id is not null
                    then 'townHall:' || town_hall_post_id::text
                when type = 'pending_approval'
                    then 'admin:pendingApproval'
                when type in (
                    'new_ride', 'ride_update', 'ride_claimed', 'ride_unclaimed', 'ride_completed',
                    'new_favor', 'favor_update', 'favor_claimed', 'favor_unclaimed', 'favor_completed',
                    'completion_reminder', 'qa_activity', 'qa_question', 'qa_answer',
                    'review_request', 'review_reminder', 'review_received'
                ) and ride_id is not null
                    then 'ride:' || ride_id::text
                when type in (
                    'new_ride', 'ride_update', 'ride_claimed', 'ride_unclaimed', 'ride_completed',
                    'new_favor', 'favor_update', 'favor_claimed', 'favor_unclaimed', 'favor_completed',
                    'completion_reminder', 'qa_activity', 'qa_question', 'qa_answer',
                    'review_request', 'review_reminder', 'review_received'
                ) and favor_id is not null
                    then 'favor:' || favor_id::text
                else 'notification:' || id::text
            end as group_key,
            bool_or(read = false) as has_unread
        from bell_pruned
        group by group_key
    )
    select coalesce(count(*), 0)::int
    into v_bell_total
    from bell_groups
    where has_unread = true;

    if p_include_details then
        select coalesce(jsonb_agg(jsonb_build_object(
            'conversation_id', conversation_id,
            'unread_count', unread_count
        )), '[]'::jsonb)
        into v_conversation_details
        from (
            select m.conversation_id, count(*)::int as unread_count
            from public.messages m
            join public.conversation_participants cp
                on cp.conversation_id = m.conversation_id
                and cp.user_id = v_user_id
            where cp.left_at is null
              and m.from_id <> v_user_id
              and not (coalesce(m.read_by, array[]::uuid[]) @> array[v_user_id]::uuid[])
              and not exists (
                  select 1 from public.blocked_users b
                  where b.blocker_id = v_user_id and b.blocked_id = m.from_id
              )
            group by m.conversation_id
        ) as per_conversation;

        select coalesce(jsonb_agg(jsonb_build_object(
            'request_type', request_type,
            'request_id', request_id,
            'unread_count', unread_count
        )), '[]'::jsonb)
        into v_request_details
        from (
            select
                case when ride_id is not null then 'ride' else 'favor' end as request_type,
                coalesce(ride_id, favor_id) as request_id,
                count(*)::int as unread_count
            from public.notifications
            where user_id = v_user_id
              and read = false
              and type in (
                  'new_ride', 'ride_update', 'ride_claimed', 'ride_unclaimed',
                  'new_favor', 'favor_update', 'favor_claimed', 'favor_unclaimed',
                  'completion_reminder', 'qa_activity', 'qa_question', 'qa_answer'
              )
              and (ride_id is not null or favor_id is not null)
            group by request_type, request_id
        ) as per_request;
    end if;

    return jsonb_build_object(
        'user_id', v_user_id,
        'messages_total', coalesce(v_messages_total, 0),
        'requests_total', coalesce(v_requests_total, 0),
        'community_total', coalesce(v_community_total, 0),
        'bell_total', coalesce(v_bell_total, 0),
        'request_details', coalesce(v_request_details, '[]'::jsonb),
        'conversation_details', coalesce(v_conversation_details, '[]'::jsonb)
    );
end;
$function$;
