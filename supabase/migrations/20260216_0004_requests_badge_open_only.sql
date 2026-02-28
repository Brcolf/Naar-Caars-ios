-- Requests tab badge: count only notifications for requests that still have a card on the
-- dashboard (open/pending). Exclude ride_completed, favor_completed, review_request,
-- review_reminder, review_received — those appear only in the bell and can open ride/favor
-- detail when tapped, but do not drive the Requests tab badge.

create or replace function public.get_badge_counts(
    p_include_details boolean default false,
    p_user_id uuid default null
) returns jsonb as $$
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
    if v_user_id is null then
        raise exception 'User not authenticated';
    end if;

    -- Messages: total unread for user **only in their conversations**
    select coalesce(count(*), 0)::int
    into v_messages_total
    from public.messages m
    join public.conversation_participants cp
        on cp.conversation_id = m.conversation_id
        and cp.user_id = v_user_id
    where m.from_id <> v_user_id
      and not (coalesce(m.read_by, array[]::uuid[]) @> array[v_user_id]::uuid[]);

    -- Cleanup: mark 'message' and 'added_to_conversation' notifications as read
    -- when there are no unread messages in that conversation (user must be participant).
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
            and m.from_id <> v_user_id
            and not (coalesce(m.read_by, array[]::uuid[]) @> array[v_user_id]::uuid[])
      );

    -- Requests tab: only notifications for requests that still have a dashboard card
    -- (open/pending). Exclude completed and review types (bell-only).
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

    -- Community: unread Town Hall notifications
    select coalesce(count(*), 0)::int
    into v_community_total
    from public.notifications
    where user_id = v_user_id
      and read = false
      and type in ('town_hall_post', 'town_hall_comment', 'town_hall_reaction');

    -- Bell: unread grouped bell-feed notifications (non-message) — includes all types
    -- (completed, review_request, etc.) so user still sees them in the bell.
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
        -- Only conversations where user is a participant
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
            where m.from_id <> v_user_id
              and not (coalesce(m.read_by, array[]::uuid[]) @> array[v_user_id]::uuid[])
            group by m.conversation_id
        ) as per_conversation;

        -- Request details: same open-only types as requests_total (dashboard-visible only)
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
$$ language plpgsql volatile security definer set search_path to '';

grant execute on function public.get_badge_counts(boolean, uuid) to authenticated;
