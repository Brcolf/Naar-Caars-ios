-- ============================================================================
-- Create Message Images Storage Bucket
-- ============================================================================
-- This migration creates the storage bucket for message images
-- and sets appropriate access policies
-- ============================================================================

-- Create the bucket if it doesn't exist
INSERT INTO storage.buckets (id, name, public)
VALUES ('message-images', 'message-images', true)
ON CONFLICT (id) DO NOTHING;

-- ============================================================================
-- Storage Policies for message-images bucket
-- ============================================================================

-- Drop existing policies if they exist
DROP POLICY IF EXISTS "message_images_select_all" ON storage.objects;
DROP POLICY IF EXISTS "message_images_insert_authenticated" ON storage.objects;
DROP POLICY IF EXISTS "message_images_update_own" ON storage.objects;
DROP POLICY IF EXISTS "message_images_delete_own" ON storage.objects;

-- SELECT: Anyone can view message images (public bucket)
CREATE POLICY "message_images_select_all"
ON storage.objects FOR SELECT
USING (bucket_id = 'message-images');

-- INSERT: Authenticated users can upload images
-- File path format: {conversation_id}/{uuid}.jpg
CREATE POLICY "message_images_insert_authenticated"
ON storage.objects FOR INSERT
WITH CHECK (
  bucket_id = 'message-images'
  AND auth.role() = 'authenticated'
);

-- UPDATE: Users can update their own uploaded images (metadata)
-- This is rarely needed but included for completeness
CREATE POLICY "message_images_update_own"
ON storage.objects FOR UPDATE
USING (
  bucket_id = 'message-images'
  AND auth.uid() = owner
)
WITH CHECK (
  bucket_id = 'message-images'
  AND auth.uid() = owner
);

-- DELETE: Users can delete their own uploaded images
CREATE POLICY "message_images_delete_own"
ON storage.objects FOR DELETE
USING (
  bucket_id = 'message-images'
  AND auth.uid() = owner
);

-- ============================================================================
-- Bucket Configuration Notes
-- ============================================================================
-- Bucket: message-images
-- Public: Yes (images are accessible via public URL)
-- File Path: {conversation_id}/{uuid}.jpg
-- Max File Size: 5MB (configured in Supabase dashboard)
-- Allowed MIME Types: image/jpeg, image/png, image/webp
--
-- Images are compressed before upload using ImageCompressor.swift
-- Compression preset: .messageImage (1024px max dimension, 0.75 quality)
-- ============================================================================

-- Verification query (run in Supabase SQL editor):
-- SELECT * FROM storage.buckets WHERE id = 'message-images';
-- SELECT * FROM storage.objects WHERE bucket_id = 'message-images' LIMIT 10;

