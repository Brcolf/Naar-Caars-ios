-- 20260206231433_fix_queue_push_notification_overload.sql
-- Exported verbatim from supabase_migrations.schema_migrations on 2026-10-05.
-- This migration was applied to production through the Supabase MCP / dashboard before being committed.


-- Fix the second overload of queue_push_notification (with p_notification_id parameter)
-- that is called from the notify_town_hall_post trigger.
-- Add public. prefix to should_notify_user and notification_queue references.
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
