-- ============================================================================
-- Migration: 089_fix_public_storage_access.sql
-- Description: Fix storage bucket policies for public URL access
-- Date: 2026-01-21
-- Issue: Images uploaded to message-images bucket can't be loaded via public URL
-- ============================================================================

-- The issue is that storage policies need to allow unauthenticated access
-- for public URLs to work. The bucket is set to public=true, but the policy
-- restricts SELECT to authenticated users or specific conditions.

-- Fix message-images bucket
-- Drop existing select policy if it exists
DROP POLICY IF EXISTS "message_images_select_all" ON storage.objects;
DROP POLICY IF EXISTS "Allow public read access on message-images" ON storage.objects;

-- Create a proper public read policy (allows anyone, including unauthenticated users)
CREATE POLICY "Allow public read access on message-images"
ON storage.objects FOR SELECT
TO public
USING (bucket_id = 'message-images');

-- Fix group-images bucket  
DROP POLICY IF EXISTS "group_images_select_all" ON storage.objects;
DROP POLICY IF EXISTS "Allow public read access on group-images" ON storage.objects;

CREATE POLICY "Allow public read access on group-images"
ON storage.objects FOR SELECT
TO public
USING (bucket_id = 'group-images');

-- Fix audio-messages bucket
DROP POLICY IF EXISTS "audio_messages_select_all" ON storage.objects;
DROP POLICY IF EXISTS "Allow public read access on audio-messages" ON storage.objects;

CREATE POLICY "Allow public read access on audio-messages"
ON storage.objects FOR SELECT
TO public
USING (bucket_id = 'audio-messages');

-- Fix town-hall-images bucket (if not already fixed)
DROP POLICY IF EXISTS "town_hall_images_select_all" ON storage.objects;
DROP POLICY IF EXISTS "Allow public read access on town-hall-images" ON storage.objects;

CREATE POLICY "Allow public read access on town-hall-images"
ON storage.objects FOR SELECT
TO public
USING (bucket_id = 'town-hall-images');

-- Ensure buckets are marked as public
UPDATE storage.buckets SET public = true WHERE id = 'message-images';
UPDATE storage.buckets SET public = true WHERE id = 'group-images';
UPDATE storage.buckets SET public = true WHERE id = 'audio-messages';
UPDATE storage.buckets SET public = true WHERE id = 'town-hall-images';

-- ============================================================================
-- Verification Queries (run after migration)
-- ============================================================================
-- Check bucket public status:
-- SELECT id, name, public FROM storage.buckets;

-- Check policies:
-- SELECT policyname, tablename, permissive, roles, cmd, qual 
-- FROM pg_policies 
-- WHERE tablename = 'objects' AND schemaname = 'storage';
-- ============================================================================


