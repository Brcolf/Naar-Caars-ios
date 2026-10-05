-- 20260403074116_security_notify_deny_default.sql
-- Exported verbatim from supabase_migrations.schema_migrations on 2026-10-05.
-- This migration was applied to production through the Supabase MCP / dashboard before being committed.


-- Security fix: Change should_notify_user() ELSE branch from true to false.
-- Live confirmed: ELSE returns true, allowing unknown types to bypass preferences.
-- Audit ref: Tier 3 #18.

CREATE OR REPLACE FUNCTION public.should_notify_user(
    p_user_id uuid,
    p_notification_type text
) RETURNS boolean
LANGUAGE plpgsql
SECURITY DEFINER
SET search_path TO ''
AS $$
DECLARE
    v_profile RECORD;
BEGIN
    SELECT * INTO v_profile FROM public.profiles WHERE id = p_user_id;
    IF NOT FOUND THEN RETURN false; END IF;

    CASE p_notification_type
        WHEN 'new_ride', 'new_favor' THEN RETURN true;
        WHEN 'announcement', 'admin_announcement', 'broadcast' THEN RETURN true;
        WHEN 'user_approved', 'user_rejected' THEN RETURN true;
        WHEN 'pending_approval' THEN RETURN v_profile.is_admin;
        WHEN 'message', 'added_to_conversation' THEN RETURN v_profile.notify_messages;
        WHEN 'ride_update', 'ride_claimed', 'ride_unclaimed', 'ride_completed',
             'favor_update', 'favor_claimed', 'favor_unclaimed', 'favor_completed'
            THEN RETURN v_profile.notify_ride_updates;
        WHEN 'qa_activity', 'qa_question', 'qa_answer' THEN RETURN v_profile.notify_qa_activity;
        WHEN 'review', 'review_received', 'review_reminder', 'review_request', 'completion_reminder'
            THEN RETURN v_profile.notify_review_reminders;
        WHEN 'town_hall_post', 'town_hall_comment', 'town_hall_reaction'
            THEN RETURN v_profile.notify_town_hall;
        ELSE
            RETURN false;  -- SECURITY FIX: deny-by-default for unknown types
    END CASE;
END;
$$;
