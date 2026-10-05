-- 20260305024250_add_content_reported_notification_type.sql
-- Exported verbatim from supabase_migrations.schema_migrations on 2026-10-05.
-- This migration was applied to production through the Supabase MCP / dashboard before being committed.


-- Add content_reported to the valid_notification_type check constraint
ALTER TABLE public.notifications DROP CONSTRAINT IF EXISTS valid_notification_type;
ALTER TABLE public.notifications ADD CONSTRAINT valid_notification_type CHECK (
    type = ANY (ARRAY[
        'message', 'added_to_conversation',
        'new_ride', 'ride_update', 'ride_claimed', 'ride_unclaimed', 'ride_completed',
        'new_favor', 'favor_update', 'favor_claimed', 'favor_unclaimed', 'favor_completed',
        'completion_reminder',
        'qa_activity', 'qa_question', 'qa_answer',
        'review', 'review_received', 'review_reminder', 'review_request',
        'town_hall_post', 'town_hall_comment', 'town_hall_reaction',
        'announcement', 'admin_announcement', 'broadcast',
        'pending_approval', 'user_approved', 'user_rejected',
        'content_reported',
        'other'
    ])
);
