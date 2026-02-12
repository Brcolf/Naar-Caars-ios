-- Fix notification functions that have SET search_path TO '' but reference
-- tables and functions without the public. schema prefix.
-- This causes "relation does not exist" errors which cascade into
-- RLS violation errors on town_hall_posts inserts (and any other table
-- with notification triggers).

-- Fix should_notify_user: add public. prefix to profiles table
CREATE OR REPLACE FUNCTION public.should_notify_user(p_user_id uuid, p_notification_type text)
 RETURNS boolean
 LANGUAGE plpgsql
 SECURITY DEFINER
 SET search_path TO ''
AS $function$
declare
    v_profile record;
begin
    select * into v_profile from public.profiles where id = p_user_id;

    if not found then
        return false;
    end if;

    case p_notification_type
        when 'new_ride', 'new_favor' then
            return true;
        when 'announcement', 'admin_announcement', 'broadcast' then
            return true;
        when 'user_approved', 'user_rejected' then
            return true;
        when 'pending_approval' then
            return v_profile.is_admin;
        when 'message', 'added_to_conversation' then
            return v_profile.notify_messages;
        when 'ride_update', 'ride_claimed', 'ride_unclaimed', 'ride_completed',
             'favor_update', 'favor_claimed', 'favor_unclaimed', 'favor_completed' then
            return v_profile.notify_ride_updates;
        when 'qa_activity', 'qa_question', 'qa_answer' then
            return v_profile.notify_qa_activity;
        when 'review', 'review_received', 'review_reminder', 'review_request', 'completion_reminder' then
            return v_profile.notify_review_reminders;
        when 'town_hall_post', 'town_hall_comment', 'town_hall_reaction' then
            return v_profile.notify_town_hall;
        else
            return true;
    end case;
end;
$function$;

-- Fix create_notification: add public. prefix to notifications table and should_notify_user call
CREATE OR REPLACE FUNCTION public.create_notification(p_user_id uuid, p_type text, p_title text, p_body text DEFAULT NULL::text, p_ride_id uuid DEFAULT NULL::uuid, p_favor_id uuid DEFAULT NULL::uuid, p_conversation_id uuid DEFAULT NULL::uuid, p_review_id uuid DEFAULT NULL::uuid, p_town_hall_post_id uuid DEFAULT NULL::uuid, p_source_user_id uuid DEFAULT NULL::uuid, p_pinned boolean DEFAULT false)
 RETURNS uuid
 LANGUAGE plpgsql
 SECURITY DEFINER
 SET search_path TO ''
AS $function$
declare
    v_notification_id uuid;
begin
    if not public.should_notify_user(p_user_id, p_type) then
        return null;
    end if;

    if p_source_user_id is not null and p_source_user_id = p_user_id then
        return null;
    end if;

    insert into public.notifications (
        user_id, type, title, body, read, pinned,
        ride_id, favor_id, conversation_id, review_id,
        town_hall_post_id, source_user_id
    ) values (
        p_user_id, p_type, p_title, p_body, false, p_pinned,
        p_ride_id, p_favor_id, p_conversation_id, p_review_id,
        p_town_hall_post_id, p_source_user_id
    )
    returning id into v_notification_id;

    return v_notification_id;
end;
$function$;

-- Fix queue_push_notification (6-param overload):
-- add public. prefix to should_notify_user and notification_queue
CREATE OR REPLACE FUNCTION public.queue_push_notification(p_recipient_user_id uuid, p_notification_type text, p_title text, p_body text, p_data jsonb DEFAULT '{}'::jsonb, p_batch_key text DEFAULT NULL::text)
 RETURNS uuid
 LANGUAGE plpgsql
 SECURITY DEFINER
 SET search_path TO ''
AS $function$
DECLARE
    v_queue_id UUID;
    v_payload JSONB;
BEGIN
    -- Check if user wants this notification type
    IF NOT public.should_notify_user(p_recipient_user_id, p_notification_type) THEN
        RETURN NULL;
    END IF;
    
    -- Build payload
    v_payload := jsonb_build_object(
        'title', p_title,
        'body', p_body,
        'type', p_notification_type,
        'data', p_data
    );
    
    INSERT INTO public.notification_queue (
        notification_type, recipient_user_id, payload, batch_key
    ) VALUES (
        p_notification_type, p_recipient_user_id, v_payload, p_batch_key
    )
    RETURNING id INTO v_queue_id;
    
    RETURN v_queue_id;
END;
$function$;

-- Fix queue_push_notification (7-param overload with p_notification_id):
-- add public. prefix to should_notify_user and notification_queue
CREATE OR REPLACE FUNCTION public.queue_push_notification(p_recipient_user_id uuid, p_notification_type text, p_title text, p_body text, p_data jsonb DEFAULT '{}'::jsonb, p_batch_key text DEFAULT NULL::text, p_notification_id uuid DEFAULT NULL::uuid)
 RETURNS uuid
 LANGUAGE plpgsql
 SECURITY DEFINER
 SET search_path TO ''
AS $function$
DECLARE
    v_queue_id UUID;
    v_payload JSONB;
    v_data JSONB;
BEGIN
    -- Check if user wants this notification type
    IF NOT public.should_notify_user(p_recipient_user_id, p_notification_type) THEN
        RETURN NULL;
    END IF;
    
    v_data := COALESCE(p_data, '{}'::jsonb);
    IF p_notification_id IS NOT NULL THEN
        v_data := v_data || jsonb_build_object('notification_id', p_notification_id::text);
    END IF;
    
    -- Build payload
    v_payload := jsonb_build_object(
        'title', p_title,
        'body', p_body,
        'type', p_notification_type,
        'data', v_data
    );
    
    INSERT INTO public.notification_queue (
        notification_type, recipient_user_id, payload, batch_key
    ) VALUES (
        p_notification_type, p_recipient_user_id, v_payload, p_batch_key
    )
    RETURNING id INTO v_queue_id;
    
    RETURN v_queue_id;
END;
$function$;
