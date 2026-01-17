-- ============================================================================
-- 049_add_review_id_to_town_hall_posts.sql - Add review_id to town_hall_posts
-- ============================================================================
-- Adds review_id column to link posts to reviews for displaying star ratings
-- ============================================================================

-- Add review_id column if it doesn't exist
DO $$
BEGIN
    IF NOT EXISTS (
        SELECT 1 FROM information_schema.columns 
        WHERE table_name = 'town_hall_posts' 
        AND column_name = 'review_id'
    ) THEN
        ALTER TABLE town_hall_posts
        ADD COLUMN review_id UUID REFERENCES reviews(id) ON DELETE SET NULL;
        
        -- Create index for performance
        CREATE INDEX IF NOT EXISTS idx_town_hall_posts_review_id 
        ON town_hall_posts(review_id);
        
        COMMENT ON COLUMN town_hall_posts.review_id IS 'Links post to a review for displaying star ratings. NULL for non-review posts.';
    END IF;
END $$;


