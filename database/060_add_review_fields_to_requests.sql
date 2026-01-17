-- ============================================================================
-- 060_add_review_fields_to_requests.sql - Add review fields to rides and favors
-- ============================================================================
-- Adds 'reviewed', 'review_skipped', and 'review_skipped_at' columns to track review status
-- ============================================================================

-- Add 'reviewed' column to rides table if it doesn't exist
DO $$
BEGIN
    IF NOT EXISTS (
        SELECT 1 FROM information_schema.columns 
        WHERE table_name = 'rides' 
        AND column_name = 'reviewed'
    ) THEN
        ALTER TABLE public.rides
        ADD COLUMN reviewed BOOLEAN NOT NULL DEFAULT FALSE;
        
        COMMENT ON COLUMN public.rides.reviewed IS 'True if the ride has been reviewed by the poster.';
    END IF;
END $$;

-- Add 'review_skipped' column to rides table if it doesn't exist
DO $$
BEGIN
    IF NOT EXISTS (
        SELECT 1 FROM information_schema.columns 
        WHERE table_name = 'rides' 
        AND column_name = 'review_skipped'
    ) THEN
        ALTER TABLE public.rides
        ADD COLUMN review_skipped BOOLEAN DEFAULT FALSE;
        
        COMMENT ON COLUMN public.rides.review_skipped IS 'True if the review prompt for this ride was explicitly skipped by the poster.';
    END IF;
END $$;

-- Add 'review_skipped_at' column to rides table if it doesn't exist
DO $$
BEGIN
    IF NOT EXISTS (
        SELECT 1 FROM information_schema.columns 
        WHERE table_name = 'rides' 
        AND column_name = 'review_skipped_at'
    ) THEN
        ALTER TABLE public.rides
        ADD COLUMN review_skipped_at TIMESTAMPTZ DEFAULT NULL;
        
        COMMENT ON COLUMN public.rides.review_skipped_at IS 'Timestamp when the review for this ride was skipped.';
    END IF;
END $$;

-- Add 'reviewed' column to favors table if it doesn't exist
DO $$
BEGIN
    IF NOT EXISTS (
        SELECT 1 FROM information_schema.columns 
        WHERE table_name = 'favors' 
        AND column_name = 'reviewed'
    ) THEN
        ALTER TABLE public.favors
        ADD COLUMN reviewed BOOLEAN NOT NULL DEFAULT FALSE;
        
        COMMENT ON COLUMN public.favors.reviewed IS 'True if the favor has been reviewed by the poster.';
    END IF;
END $$;

-- Add 'review_skipped' column to favors table if it doesn't exist
DO $$
BEGIN
    IF NOT EXISTS (
        SELECT 1 FROM information_schema.columns 
        WHERE table_name = 'favors' 
        AND column_name = 'review_skipped'
    ) THEN
        ALTER TABLE public.favors
        ADD COLUMN review_skipped BOOLEAN DEFAULT FALSE;
        
        COMMENT ON COLUMN public.favors.review_skipped IS 'True if the review prompt for this favor was explicitly skipped by the poster.';
    END IF;
END $$;

-- Add 'review_skipped_at' column to favors table if it doesn't exist
DO $$
BEGIN
    IF NOT EXISTS (
        SELECT 1 FROM information_schema.columns 
        WHERE table_name = 'favors' 
        AND column_name = 'review_skipped_at'
    ) THEN
        ALTER TABLE public.favors
        ADD COLUMN review_skipped_at TIMESTAMPTZ DEFAULT NULL;
        
        COMMENT ON COLUMN public.favors.review_skipped_at IS 'Timestamp when the review for this favor was skipped.';
    END IF;
END $$;

