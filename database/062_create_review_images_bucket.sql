-- ============================================================================
-- 062_create_review_images_bucket.sql - Create Supabase Storage bucket for review images
-- ============================================================================
-- Creates a new storage bucket named 'review-images' for storing review-related images.
-- Note: Reviews will use the existing 'town-hall-images' bucket as a fallback.
-- This migration is optional - if review-images bucket doesn't exist, reviews will use town-hall-images.
-- ============================================================================

-- Create the 'review-images' bucket if it doesn't already exist
INSERT INTO storage.buckets (id, name, public)
VALUES ('review-images', 'review-images', true)
ON CONFLICT (id) DO NOTHING;

-- Ensure the bucket is public
UPDATE storage.buckets
SET public = true
WHERE id = 'review-images';

-- Remove existing policies for 'review-images' to prevent conflicts
DROP POLICY IF EXISTS "Allow public access to review images" ON storage.objects;
DROP POLICY IF EXISTS "Allow authenticated users to upload review images" ON storage.objects;
DROP POLICY IF EXISTS "Allow authenticated users to update their own review images" ON storage.objects;
DROP POLICY IF EXISTS "Allow authenticated users to delete their own review images" ON storage.objects;

-- Allow public access to download/view images in 'review-images' bucket
CREATE POLICY "Allow public access to review images"
ON storage.objects FOR SELECT
TO public
USING (bucket_id = 'review-images');

-- Allow authenticated users to upload images to 'review-images' bucket
CREATE POLICY "Allow authenticated users to upload review images"
ON storage.objects FOR INSERT
TO authenticated
WITH CHECK (bucket_id = 'review-images' AND auth.role() = 'authenticated');

-- Allow authenticated users to update their own images in 'review-images' bucket
CREATE POLICY "Allow authenticated users to update their own review images"
ON storage.objects FOR UPDATE
TO authenticated
USING (bucket_id = 'review-images' AND auth.uid() = owner)
WITH CHECK (bucket_id = 'review-images' AND auth.uid() = owner);

-- Allow authenticated users to delete their own images in 'review-images' bucket
CREATE POLICY "Allow authenticated users to delete their own review images"
ON storage.objects FOR DELETE
TO authenticated
USING (bucket_id = 'review-images' AND auth.uid() = owner);

