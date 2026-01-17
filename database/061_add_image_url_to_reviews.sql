-- ============================================================================
-- 061_add_image_url_to_reviews.sql - Add image_url to reviews table
-- ============================================================================
-- Adds image_url column to store URL of an optional image attached to a review
-- ============================================================================

-- Add image_url column if it doesn't exist
DO $$
BEGIN
    IF NOT EXISTS (
        SELECT 1 FROM information_schema.columns 
        WHERE table_name = 'reviews' 
        AND column_name = 'image_url'
    ) THEN
        ALTER TABLE public.reviews
        ADD COLUMN image_url TEXT DEFAULT NULL;
        
        COMMENT ON COLUMN public.reviews.image_url IS 'URL of an optional image attached to the review.';
    END IF;
END $$;

