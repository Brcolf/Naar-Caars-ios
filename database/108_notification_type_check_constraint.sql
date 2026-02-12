-- Ensure notifications.type only contains known application notification values.
DO $$
BEGIN
    IF NOT EXISTS (
        SELECT 1
        FROM pg_constraint
        WHERE conname = 'valid_notification_type'
    ) THEN
        ALTER TABLE notifications
        ADD CONSTRAINT valid_notification_type
        CHECK (
            type IN (
                'message',
                'added_to_conversation',
                'new_ride',
                'ride_update',
                'ride_claimed',
                'ride_unclaimed',
                'ride_completed',
                'new_favor',
                'favor_update',
                'favor_claimed',
                'favor_unclaimed',
                'favor_completed',
                'completion_reminder',
                'qa_activity',
                'qa_question',
                'qa_answer',
                'review',
                'review_received',
                'review_reminder',
                'review_request',
                'town_hall_post',
                'town_hall_comment',
                'town_hall_reaction',
                'announcement',
                'admin_announcement',
                'broadcast',
                'pending_approval',
                'user_approved',
                'user_rejected',
                'other'
            )
        );
    END IF;
END $$;
