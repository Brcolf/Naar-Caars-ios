-- Migration: Notification System Overhaul
-- Adds new notification preferences, updates notifications table, and creates triggers
-- for comprehensive in-app and push notification support

-- ============================================================================
-- PART 1: Update profiles table with new notification preference
-- ============================================================================

-- Add notify_town_hall column to profiles
ALTER TABLE profiles 
ADD COLUMN IF NOT EXISTS notify_town_hall BOOLEAN DEFAULT true;

-- Update existing profiles to have town hall notifications enabled by default
UPDATE profiles SET notify_town_hall = true WHERE notify_town_hall IS NULL;

-- ============================================================================
-- PART 2: Update notifications table with new columns
-- ============================================================================

-- Add new columns to notifications table for enhanced linking
ALTER TABLE notifications 
ADD COLUMN IF NOT EXISTS town_hall_post_id UUID REFERENCES town_hall_posts(id) ON DELETE SET NULL,
ADD COLUMN IF NOT EXISTS source_user_id UUID REFERENCES profiles(id) ON DELETE SET NULL;

-- Create index for faster lookups
CREATE INDEX IF NOT EXISTS idx_notifications_town_hall_post_id ON notifications(town_hall_post_id);
CREATE INDEX IF NOT EXISTS idx_notifications_source_user_id ON notifications(source_user_id);
CREATE INDEX IF NOT EXISTS idx_notifications_type ON notifications(type);
CREATE INDEX IF NOT EXISTS idx_notifications_user_read ON notifications(user_id, read);

-- ============================================================================
-- PART 3: Create notification queue table for batching Town Hall notifications
-- ============================================================================

CREATE TABLE IF NOT EXISTS notification_queue (
    id UUID PRIMARY KEY DEFAULT gen_random_uuid(),
    notification_type TEXT NOT NULL,
    recipient_user_id UUID REFERENCES profiles(id) ON DELETE CASCADE,
    payload JSONB NOT NULL,
    batch_key TEXT,  -- Used to group similar notifications for batching
    created_at TIMESTAMPTZ DEFAULT NOW(),
    processed_at TIMESTAMPTZ,
    sent_at TIMESTAMPTZ
);

-- Index for processing pending notifications
CREATE INDEX IF NOT EXISTS idx_notification_queue_pending 
ON notification_queue(created_at) 
WHERE processed_at IS NULL;

CREATE INDEX IF NOT EXISTS idx_notification_queue_batch_key 
ON notification_queue(batch_key, created_at) 
WHERE processed_at IS NULL;

-- ============================================================================
-- PART 4: Create completion_reminders table for tracking scheduled reminders
-- ============================================================================

CREATE TABLE IF NOT EXISTS completion_reminders (
    id UUID PRIMARY KEY DEFAULT gen_random_uuid(),
    ride_id UUID REFERENCES rides(id) ON DELETE CASCADE,
    favor_id UUID REFERENCES favors(id) ON DELETE CASCADE,
    claimer_user_id UUID NOT NULL REFERENCES profiles(id) ON DELETE CASCADE,
    scheduled_for TIMESTAMPTZ NOT NULL,
    reminder_count INT DEFAULT 0,  -- How many times we've reminded
    last_reminded_at TIMESTAMPTZ,
    completed BOOLEAN DEFAULT false,
    created_at TIMESTAMPTZ DEFAULT NOW(),
    
    -- Either ride_id or favor_id must be set, not both
    CONSTRAINT completion_reminder_request_check 
        CHECK ((ride_id IS NOT NULL AND favor_id IS NULL) OR (ride_id IS NULL AND favor_id IS NOT NULL))
);

-- Index for finding due reminders
CREATE INDEX IF NOT EXISTS idx_completion_reminders_due 
ON completion_reminders(scheduled_for) 
WHERE completed = false;

CREATE INDEX IF NOT EXISTS idx_completion_reminders_ride ON completion_reminders(ride_id);
CREATE INDEX IF NOT EXISTS idx_completion_reminders_favor ON completion_reminders(favor_id);

-- ============================================================================
-- PART 5: Create town_hall_interactions table for tracking who interacted
-- ============================================================================

-- This table tracks all users who have interacted with a post (for notification targeting)
CREATE TABLE IF NOT EXISTS town_hall_post_interactions (
    id UUID PRIMARY KEY DEFAULT gen_random_uuid(),
    post_id UUID NOT NULL REFERENCES town_hall_posts(id) ON DELETE CASCADE,
    user_id UUID NOT NULL REFERENCES profiles(id) ON DELETE CASCADE,
    interaction_type TEXT NOT NULL,  -- 'comment', 'upvote', 'downvote'
    created_at TIMESTAMPTZ DEFAULT NOW(),
    
    -- One entry per user per post per interaction type
    UNIQUE(post_id, user_id, interaction_type)
);

CREATE INDEX IF NOT EXISTS idx_town_hall_interactions_post ON town_hall_post_interactions(post_id);
CREATE INDEX IF NOT EXISTS idx_town_hall_interactions_user ON town_hall_post_interactions(user_id);

-- ============================================================================
-- PART 6: Helper function to check if user wants notification type
-- ============================================================================

CREATE OR REPLACE FUNCTION should_notify_user(
    p_user_id UUID,
    p_notification_type TEXT
) RETURNS BOOLEAN AS $$
DECLARE
    v_profile RECORD;
BEGIN
    -- Get user's notification preferences
    SELECT * INTO v_profile FROM profiles WHERE id = p_user_id;
    
    IF NOT FOUND THEN
        RETURN false;
    END IF;
    
    -- Check based on notification type
    CASE p_notification_type
        -- Mandatory notifications (cannot be disabled)
        WHEN 'new_ride', 'new_favor' THEN
            RETURN true;  -- All users must receive new request notifications
        WHEN 'announcement', 'admin_announcement', 'broadcast' THEN
            RETURN true;  -- Board announcements cannot be disabled
        WHEN 'user_approved', 'user_rejected' THEN
            RETURN true;  -- Account status notifications
        WHEN 'pending_approval' THEN
            RETURN v_profile.is_admin;  -- Only admins get pending approval notifications
            
        -- Message notifications
        WHEN 'message', 'added_to_conversation' THEN
            RETURN v_profile.notify_messages;
            
        -- Ride/Favor update notifications
        WHEN 'ride_update', 'ride_claimed', 'ride_unclaimed', 'ride_completed',
             'favor_update', 'favor_claimed', 'favor_unclaimed', 'favor_completed' THEN
            RETURN v_profile.notify_ride_updates;
            
        -- Q&A notifications
        WHEN 'qa_activity', 'qa_question', 'qa_answer' THEN
            RETURN v_profile.notify_qa_activity;
            
        -- Review notifications
        WHEN 'review', 'review_received', 'review_reminder', 'review_request', 'completion_reminder' THEN
            RETURN v_profile.notify_review_reminders;
            
        -- Town Hall notifications
        WHEN 'town_hall_post', 'town_hall_comment', 'town_hall_reaction' THEN
            RETURN v_profile.notify_town_hall;
            
        ELSE
            RETURN true;  -- Default to sending
    END CASE;
END;
$$ LANGUAGE plpgsql SECURITY DEFINER;

-- ============================================================================
-- PART 7: Function to create in-app notification
-- ============================================================================

CREATE OR REPLACE FUNCTION create_notification(
    p_user_id UUID,
    p_type TEXT,
    p_title TEXT,
    p_body TEXT DEFAULT NULL,
    p_ride_id UUID DEFAULT NULL,
    p_favor_id UUID DEFAULT NULL,
    p_conversation_id UUID DEFAULT NULL,
    p_review_id UUID DEFAULT NULL,
    p_town_hall_post_id UUID DEFAULT NULL,
    p_source_user_id UUID DEFAULT NULL,
    p_pinned BOOLEAN DEFAULT false
) RETURNS UUID AS $$
DECLARE
    v_notification_id UUID;
BEGIN
    -- Check if user wants this notification type
    IF NOT should_notify_user(p_user_id, p_type) THEN
        RETURN NULL;
    END IF;
    
    -- Don't notify user about their own actions
    IF p_source_user_id IS NOT NULL AND p_source_user_id = p_user_id THEN
        RETURN NULL;
    END IF;
    
    INSERT INTO notifications (
        user_id, type, title, body, read, pinned,
        ride_id, favor_id, conversation_id, review_id,
        town_hall_post_id, source_user_id
    ) VALUES (
        p_user_id, p_type, p_title, p_body, false, p_pinned,
        p_ride_id, p_favor_id, p_conversation_id, p_review_id,
        p_town_hall_post_id, p_source_user_id
    )
    RETURNING id INTO v_notification_id;
    
    RETURN v_notification_id;
END;
$$ LANGUAGE plpgsql SECURITY DEFINER;

-- Grant execute to authenticated users
GRANT EXECUTE ON FUNCTION create_notification TO authenticated;
GRANT EXECUTE ON FUNCTION should_notify_user TO authenticated;

-- ============================================================================
-- PART 8: Function to queue notification for push delivery
-- ============================================================================

CREATE OR REPLACE FUNCTION queue_push_notification(
    p_recipient_user_id UUID,
    p_notification_type TEXT,
    p_title TEXT,
    p_body TEXT,
    p_data JSONB DEFAULT '{}'::jsonb,
    p_batch_key TEXT DEFAULT NULL
) RETURNS UUID AS $$
DECLARE
    v_queue_id UUID;
    v_payload JSONB;
BEGIN
    -- Check if user wants this notification type
    IF NOT should_notify_user(p_recipient_user_id, p_notification_type) THEN
        RETURN NULL;
    END IF;
    
    -- Build payload
    v_payload := jsonb_build_object(
        'title', p_title,
        'body', p_body,
        'type', p_notification_type,
        'data', p_data
    );
    
    INSERT INTO notification_queue (
        notification_type, recipient_user_id, payload, batch_key
    ) VALUES (
        p_notification_type, p_recipient_user_id, v_payload, p_batch_key
    )
    RETURNING id INTO v_queue_id;
    
    RETURN v_queue_id;
END;
$$ LANGUAGE plpgsql SECURITY DEFINER;

GRANT EXECUTE ON FUNCTION queue_push_notification TO authenticated;

-- ============================================================================
-- COMMENTS
-- ============================================================================

COMMENT ON TABLE notification_queue IS 'Queue for push notifications, supports batching for high-volume notification types like Town Hall';
COMMENT ON TABLE completion_reminders IS 'Tracks scheduled completion reminder notifications for claimed requests';
COMMENT ON TABLE town_hall_post_interactions IS 'Tracks users who have interacted with Town Hall posts for targeted notifications';
COMMENT ON FUNCTION should_notify_user IS 'Checks if a user should receive a specific notification type based on their preferences';
COMMENT ON FUNCTION create_notification IS 'Creates an in-app notification respecting user preferences';
COMMENT ON FUNCTION queue_push_notification IS 'Queues a push notification for delivery, supports batching via batch_key';

