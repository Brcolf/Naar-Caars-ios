-- 20260206193733_fix_rls_helper_security_and_badge_counts.sql
-- Exported verbatim from supabase_migrations.schema_migrations on 2026-10-05.
-- This migration was applied to production through the Supabase MCP / dashboard before being committed.


-- Fix is_conversation_participant: must be SECURITY DEFINER because it's used
-- in RLS policies on the same table (conversation_participants) it queries.
-- SECURITY INVOKER causes recursive RLS evaluation -> 500 error.
CREATE OR REPLACE FUNCTION public.is_conversation_participant(conv_id uuid, check_user_id uuid)
RETURNS boolean
LANGUAGE sql
STABLE
SECURITY DEFINER
SET search_path = ''
AS $$
  SELECT EXISTS (
    SELECT 1
    FROM public.conversation_participants
    WHERE conversation_id = conv_id
    AND user_id = check_user_id
  );
$$;

-- Also fix is_admin_user and is_user_approved which are used in RLS policies
-- They were already correct (SECURITY DEFINER with public. prefix) but let's ensure consistency
-- is_admin_user already has search_path=public and uses public.profiles - OK
-- is_user_approved already has search_path="" and uses public.profiles - OK

-- Fix get_badge_counts: has search_path="" but uses unqualified table names
-- Also has wrong parameter signature causing 404 from PostgREST
-- Need to check and fix the function
CREATE OR REPLACE FUNCTION public.get_badge_counts(
    p_user_id uuid DEFAULT NULL,
    p_include_details boolean DEFAULT false
)
RETURNS jsonb
LANGUAGE plpgsql
STABLE
SECURITY INVOKER
SET search_path = ''
AS $$
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

    -- Messages: total unread messages for user
    select count(*)
    into v_messages_total
    from public.messages
    where from_id <> v_user_id
      and not (coalesce(read_by, array[]::uuid[]) @> array[v_user_id]::uuid[]);

    -- Cleanup: Mark 'message' and 'added_to_conversation' notifications as read
    -- if there are no unread messages in that conversation.
    update public.notifications n
    set read = true
    where n.user_id = v_user_id
      and n.read = false
      and n.type in ('message', 'added_to_conversation')
      and n.conversation_id is not null
      and not exists (
          select 1 from public.messages m
          where m.conversation_id = n.conversation_id
            and m.from_id <> v_user_id
            and not (coalesce(m.read_by, array[]::uuid[]) @> array[v_user_id]::uuid[])
      );

    -- Requests: distinct requests with unseen activity
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
              'new_ride', 'ride_update', 'ride_claimed', 'ride_unclaimed', 'ride_completed',
              'new_favor', 'favor_update', 'favor_claimed', 'favor_unclaimed', 'favor_completed',
              'completion_reminder', 'qa_activity', 'qa_question', 'qa_answer',
              'review_request', 'review_reminder'
          )
    )
    select count(*)
    into v_requests_total
    from unread_requests
    where request_key is not null;

    -- Community: unread Town Hall notifications
    select count(*)
    into v_community_total
    from public.notifications
    where user_id = v_user_id
      and read = false
      and type in ('town_hall_post', 'town_hall_comment', 'town_hall_reaction');

    -- Bell: unread grouped bell-feed notifications
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
    select count(*)
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
            select conversation_id, count(*)::int as unread_count
            from public.messages
            where from_id <> v_user_id
              and not (coalesce(read_by, array[]::uuid[]) @> array[v_user_id]::uuid[])
            group by conversation_id
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
                  'new_ride', 'ride_update', 'ride_claimed', 'ride_unclaimed', 'ride_completed',
                  'new_favor', 'favor_update', 'favor_claimed', 'favor_unclaimed', 'favor_completed',
                  'completion_reminder', 'qa_activity', 'qa_question', 'qa_answer',
                  'review_request', 'review_reminder'
              )
              and (ride_id is not null or favor_id is not null)
            group by request_type, request_id
        ) as per_request;
    end if;

    return jsonb_build_object(
        'user_id', v_user_id,
        'messages_total', v_messages_total,
        'requests_total', v_requests_total,
        'community_total', v_community_total,
        'bell_total', v_bell_total,
        'request_details', v_request_details,
        'conversation_details', v_conversation_details
    );
end;
$$;
