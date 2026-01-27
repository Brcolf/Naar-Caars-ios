-- ============================================================================
-- Migration: 088_update_storage_bucket_limits.sql
-- Description: Updates storage bucket file size limits to allow larger uploads
-- Date: 2026-01-21
-- ============================================================================

-- Update message-images bucket to allow 5MB uploads
UPDATE storage.buckets 
SET file_size_limit = 5242880  -- 5MB in bytes
WHERE id = 'message-images';

-- Update group-images bucket to allow 5MB uploads
UPDATE storage.buckets 
SET file_size_limit = 5242880  -- 5MB in bytes
WHERE id = 'group-images';

-- Update audio-messages bucket to allow 10MB uploads (audio can be larger)
UPDATE storage.buckets 
SET file_size_limit = 10485760  -- 10MB in bytes
WHERE id = 'audio-messages';

-- Update town-hall-images bucket to allow 5MB uploads
UPDATE storage.buckets 
SET file_size_limit = 5242880  -- 5MB in bytes
WHERE id = 'town-hall-images';

-- Update review-images bucket to allow 5MB uploads
UPDATE storage.buckets 
SET file_size_limit = 5242880  -- 5MB in bytes
WHERE id = 'review-images';

-- Update profile-avatars bucket to allow 2MB uploads
UPDATE storage.buckets 
SET file_size_limit = 2097152  -- 2MB in bytes
WHERE id = 'profile-avatars';

-- ============================================================================
-- Verification Query (run after migration)
-- ============================================================================
-- SELECT id, name, file_size_limit FROM storage.buckets;


