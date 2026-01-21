-- Migration: Fix missing review_id column in notifications table
-- The create_notification function expects a review_id column but it was never added
-- This migration adds the missing column to fix signup/notification errors

-- Add review_id column to notifications table if it doesn't exist
DO $$
BEGIN
    -- Check if column exists
    IF NOT EXISTS (
        SELECT 1 
        FROM information_schema.columns 
        WHERE table_name = 'notifications' 
        AND column_name = 'review_id'
    ) THEN
        ALTER TABLE notifications 
        ADD COLUMN review_id UUID REFERENCES reviews(id) ON DELETE SET NULL;
        
        CREATE INDEX IF NOT EXISTS idx_notifications_review_id 
        ON notifications(review_id);
        
        COMMENT ON COLUMN notifications.review_id IS 'Links notification to a review for review-related notifications';
    END IF;
END $$;

