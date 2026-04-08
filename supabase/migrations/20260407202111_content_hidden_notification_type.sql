-- Allow new moderation/account notification types in notifications table.
-- The moderation redesign introduces `content_hidden`, and the app/registries
-- already recognize `account_restricted`. Keep the DB constraint in sync.

ALTER TABLE public.notifications
DROP CONSTRAINT IF EXISTS valid_notification_type;

ALTER TABLE public.notifications
ADD CONSTRAINT valid_notification_type
CHECK (
    type = ANY (
        ARRAY[
            'message'::text,
            'added_to_conversation'::text,
            'new_ride'::text,
            'ride_update'::text,
            'ride_claimed'::text,
            'ride_unclaimed'::text,
            'ride_completed'::text,
            'new_favor'::text,
            'favor_update'::text,
            'favor_claimed'::text,
            'favor_unclaimed'::text,
            'favor_completed'::text,
            'completion_reminder'::text,
            'qa_activity'::text,
            'qa_question'::text,
            'qa_answer'::text,
            'review'::text,
            'review_received'::text,
            'review_reminder'::text,
            'review_request'::text,
            'town_hall_post'::text,
            'town_hall_comment'::text,
            'town_hall_reaction'::text,
            'content_reported'::text,
            'content_hidden'::text,
            'announcement'::text,
            'admin_announcement'::text,
            'broadcast'::text,
            'pending_approval'::text,
            'user_approved'::text,
            'user_rejected'::text,
            'account_restricted'::text,
            'other'::text
        ]
    )
);
