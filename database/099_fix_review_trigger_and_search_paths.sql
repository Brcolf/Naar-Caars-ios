-- Fix handle_new_review trigger: was inserting town_hall_posts with
-- user_id = fulfiller_id, but RLS requires auth.uid() = user_id.
-- The authenticated user is the reviewer, not the fulfiller.
-- Fix: Make SECURITY DEFINER and use reviewer_id. Also add review_id link.

CREATE OR REPLACE FUNCTION public.handle_new_review()
 RETURNS trigger
 LANGUAGE plpgsql
 SECURITY DEFINER
 SET search_path TO ''
AS $function$
DECLARE
    reviewer_name TEXT;
    fulfiller_name TEXT;
BEGIN
    SELECT name INTO reviewer_name FROM public.profiles WHERE id = NEW.reviewer_id;
    SELECT name INTO fulfiller_name FROM public.profiles WHERE id = NEW.fulfiller_id;
    
    INSERT INTO public.town_hall_posts (user_id, title, content, review_id)
    VALUES (
        NEW.reviewer_id,
        format('%s reviewed %s', COALESCE(reviewer_name, 'Someone'), COALESCE(fulfiller_name, 'someone')),
        COALESCE(NEW.comment, format('Rating: %s/5', NEW.rating::text)),
        NEW.id
    );
    
    RETURN NEW;
END;
$function$;

-- Fix mark_request_notifications_read: unqualified notifications reference
CREATE OR REPLACE FUNCTION public.mark_request_notifications_read(p_request_type text, p_request_id uuid, p_notification_types text[] DEFAULT NULL::text[], p_include_reviews boolean DEFAULT false)
 RETURNS integer
 LANGUAGE plpgsql
 SET search_path TO ''
AS $function$
declare
    v_types text[];
    v_count integer;
begin
    if p_notification_types is null then
        v_types := array[
            'new_ride', 'ride_update', 'ride_claimed', 'ride_unclaimed', 'ride_completed',
            'new_favor', 'favor_update', 'favor_claimed', 'favor_unclaimed', 'favor_completed',
            'completion_reminder', 'qa_activity', 'qa_question', 'qa_answer'
        ];

        if p_include_reviews then
            v_types := v_types || array['review_request', 'review_reminder'];
        end if;
    else
        v_types := p_notification_types;
    end if;

    update public.notifications
    set read = true
    where user_id = auth.uid()
      and read = false
      and created_at <= now()
      and (
        (p_request_type = 'ride' and ride_id = p_request_id) or
        (p_request_type = 'favor' and favor_id = p_request_id)
      )
      and type = any(v_types);

    get diagnostics v_count = row_count;
    return v_count;
end;
$function$;

-- Fix notify_town_hall_vote: unqualified table/function references
CREATE OR REPLACE FUNCTION public.notify_town_hall_vote()
 RETURNS trigger
 LANGUAGE plpgsql
 SECURITY DEFINER
 SET search_path TO ''
AS $function$
declare
    v_voter_name text;
    v_post record;
    v_vote_type text;
begin
    select name into v_voter_name from public.profiles where id = new.user_id;
    v_voter_name := coalesce(v_voter_name, 'Someone');

    select * into v_post from public.town_hall_posts where id = new.post_id;

    v_vote_type := case when new.vote_type = 'upvote' then 'upvote' else 'downvote' end;

    insert into public.town_hall_post_interactions (post_id, user_id, interaction_type)
    values (new.post_id, new.user_id, v_vote_type)
    on conflict (post_id, user_id, interaction_type) do nothing;

    if new.vote_type = 'upvote' then
        if v_post.user_id != new.user_id then
            perform public.create_notification(
                v_post.user_id,
                'town_hall_reaction',
                'Post Upvoted',
                v_voter_name || ' upvoted your post',
                null,
                null,
                null,
                null,
                new.post_id,
                new.user_id
            );
        end if;
    end if;

    return new;
end;
$function$;

-- Fix process_batched_notifications: unqualified notification_queue reference
CREATE OR REPLACE FUNCTION public.process_batched_notifications()
 RETURNS integer
 LANGUAGE plpgsql
 SECURITY DEFINER
 SET search_path TO ''
AS $function$
declare
    v_batch record;
    v_count integer := 0;
    v_notifications_in_batch integer;
begin
    for v_batch in
        select batch_key, recipient_user_id, count(*) as notification_count
        from public.notification_queue
        where batch_key is not null
          and processed_at is null
          and created_at <= now() - interval '3 minutes'
        group by batch_key, recipient_user_id
    loop
        v_notifications_in_batch := v_batch.notification_count;

        if v_notifications_in_batch = 1 then
            update public.notification_queue nq
            set processed_at = now()
            where nq.batch_key = v_batch.batch_key
              and nq.recipient_user_id = v_batch.recipient_user_id
              and nq.processed_at is null;
        else
            update public.notification_queue
            set
                processed_at = now(),
                payload = jsonb_set(
                    payload,
                    '{body}',
                    to_jsonb(v_notifications_in_batch || ' new posts in Town Hall')
                ),
                sent_at = case
                    when id = (
                        select id from public.notification_queue nq2
                        where nq2.batch_key = v_batch.batch_key
                          and nq2.recipient_user_id = v_batch.recipient_user_id
                        order by created_at asc
                        limit 1
                    ) then null
                    else now()
                end
            where batch_key = v_batch.batch_key
              and recipient_user_id = v_batch.recipient_user_id
              and processed_at is null;
        end if;

        v_count := v_count + 1;
    end loop;

    return v_count;
end;
$function$;

-- Fix send_push_notification_direct: unqualified references
CREATE OR REPLACE FUNCTION public.send_push_notification_direct(p_user_id uuid, p_notification_type text, p_title text, p_body text, p_data jsonb DEFAULT '{}'::jsonb)
 RETURNS void
 LANGUAGE plpgsql
 SECURITY DEFINER
 SET search_path TO ''
AS $function$
declare
    v_payload jsonb;
begin
    if not public.should_notify_user(p_user_id, p_notification_type) then
        return;
    end if;

    v_payload := jsonb_build_object(
        'recipient_user_id', p_user_id::text,
        'notification_type', p_notification_type,
        'title', p_title,
        'body', p_body,
        'data', p_data
    );

    insert into public.notification_queue (
        notification_type,
        recipient_user_id,
        payload,
        batch_key,
        processed_at
    ) values (
        p_notification_type,
        p_user_id,
        jsonb_build_object(
            'title', p_title,
            'body', p_body,
            'type', p_notification_type,
            'data', p_data
        ),
        null,
        now()
    );

    perform pg_notify(
        'push_notification',
        v_payload::text
    );
end;
$function$;
