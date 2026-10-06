-- Security follow-up: restore content_reported preference handling.
-- Batch 1 changed should_notify_user() to deny-by-default for unknown types.
-- Live DB still emits content_reported notifications for admins, but that type
-- was not included in the CASE statement, causing moderation notifications to
-- be suppressed.

CREATE OR REPLACE FUNCTION public.should_notify_user(
    p_user_id UUID,
    p_notification_type TEXT
) RETURNS BOOLEAN
LANGUAGE plpgsql
SECURITY DEFINER
SET search_path TO ''
AS $function$
DECLARE
    v_profile RECORD;
BEGIN
    SELECT * INTO v_profile FROM public.profiles WHERE id = p_user_id;
    IF NOT FOUND THEN
        RETURN false;
    END IF;

    CASE p_notification_type
        WHEN 'new_ride', 'new_favor' THEN
            RETURN true;
        WHEN 'announcement', 'admin_announcement', 'broadcast' THEN
            RETURN true;
        WHEN 'user_approved', 'user_rejected' THEN
            RETURN true;
        WHEN 'pending_approval' THEN
            RETURN v_profile.is_admin;
        WHEN 'message', 'added_to_conversation' THEN
            RETURN v_profile.notify_messages;
        WHEN 'ride_update', 'ride_claimed', 'ride_unclaimed', 'ride_completed',
             'favor_update', 'favor_claimed', 'favor_unclaimed', 'favor_completed' THEN
            RETURN v_profile.notify_ride_updates;
        WHEN 'qa_activity', 'qa_question', 'qa_answer' THEN
            RETURN v_profile.notify_qa_activity;
        WHEN 'review', 'review_received', 'review_reminder', 'review_request', 'completion_reminder' THEN
            RETURN v_profile.notify_review_reminders;
        WHEN 'town_hall_post', 'town_hall_comment', 'town_hall_reaction' THEN
            RETURN v_profile.notify_town_hall;
        WHEN 'content_reported' THEN
            RETURN v_profile.is_admin;
        ELSE
            RETURN false;
    END CASE;
END;
$function$;
