-- ============================================================================
-- 086_audio_location_messages.sql - Support for audio and location messages
-- ============================================================================
-- Adds support for:
-- 1. Audio message fields (audio_url, audio_duration)
-- 2. Location message fields (latitude, longitude, location_name)
-- 3. Storage bucket for audio messages
-- ============================================================================

-- ============================================================================
-- PART 1: Add audio message fields to messages table
-- ============================================================================

-- Add audio_url column for audio message storage URL
ALTER TABLE public.messages 
ADD COLUMN IF NOT EXISTS audio_url TEXT DEFAULT NULL;

-- Add audio_duration column for playback duration in seconds
ALTER TABLE public.messages 
ADD COLUMN IF NOT EXISTS audio_duration REAL DEFAULT NULL;

-- Add comments
COMMENT ON COLUMN public.messages.audio_url IS 
    'URL to the audio file stored in Supabase Storage for audio messages.';
COMMENT ON COLUMN public.messages.audio_duration IS 
    'Duration of the audio message in seconds.';

-- ============================================================================
-- PART 2: Add location message fields to messages table
-- ============================================================================

-- Add latitude column
ALTER TABLE public.messages 
ADD COLUMN IF NOT EXISTS latitude DOUBLE PRECISION DEFAULT NULL;

-- Add longitude column
ALTER TABLE public.messages 
ADD COLUMN IF NOT EXISTS longitude DOUBLE PRECISION DEFAULT NULL;

-- Add location_name column for human-readable address/place name
ALTER TABLE public.messages 
ADD COLUMN IF NOT EXISTS location_name TEXT DEFAULT NULL;

-- Add comments
COMMENT ON COLUMN public.messages.latitude IS 
    'Latitude coordinate for location messages.';
COMMENT ON COLUMN public.messages.longitude IS 
    'Longitude coordinate for location messages.';
COMMENT ON COLUMN public.messages.location_name IS 
    'Human-readable name or address for location messages.';

-- ============================================================================
-- PART 3: Create storage bucket for audio messages
-- ============================================================================

-- Create bucket for audio messages (if not exists)
INSERT INTO storage.buckets (id, name, public, file_size_limit, allowed_mime_types)
VALUES (
    'audio-messages', 
    'audio-messages', 
    true,
    10485760, -- 10MB limit for audio
    ARRAY['audio/m4a', 'audio/mp4', 'audio/mpeg', 'audio/aac', 'audio/wav']
)
ON CONFLICT (id) DO UPDATE SET
    public = EXCLUDED.public,
    file_size_limit = EXCLUDED.file_size_limit,
    allowed_mime_types = EXCLUDED.allowed_mime_types;

-- ============================================================================
-- PART 4: Storage RLS policies for audio messages
-- ============================================================================

-- Drop existing policies if they exist (to avoid conflicts)
DROP POLICY IF EXISTS "Authenticated users can upload audio messages" ON storage.objects;
DROP POLICY IF EXISTS "Anyone can view audio messages" ON storage.objects;
DROP POLICY IF EXISTS "Authenticated users can delete own audio messages" ON storage.objects;

-- Policy: Authenticated users can upload audio messages
CREATE POLICY "Authenticated users can upload audio messages"
ON storage.objects FOR INSERT
TO authenticated
WITH CHECK (bucket_id = 'audio-messages');

-- Policy: Anyone can view audio messages (they're public)
CREATE POLICY "Anyone can view audio messages"
ON storage.objects FOR SELECT
TO public
USING (bucket_id = 'audio-messages');

-- Policy: Authenticated users can delete audio messages
CREATE POLICY "Authenticated users can delete audio messages"
ON storage.objects FOR DELETE
TO authenticated
USING (bucket_id = 'audio-messages');

-- ============================================================================
-- PART 5: Create index for location queries
-- ============================================================================

-- Index for finding messages with location data
CREATE INDEX IF NOT EXISTS idx_messages_location 
ON public.messages(conversation_id, latitude, longitude) 
WHERE latitude IS NOT NULL AND longitude IS NOT NULL;

-- Index for audio messages
CREATE INDEX IF NOT EXISTS idx_messages_audio 
ON public.messages(conversation_id) 
WHERE audio_url IS NOT NULL;

-- ============================================================================
-- PART 6: Update message_type check constraint
-- ============================================================================

-- Drop existing constraint if it exists
ALTER TABLE public.messages 
DROP CONSTRAINT IF EXISTS messages_message_type_check;

-- Add updated constraint with all message types
ALTER TABLE public.messages 
ADD CONSTRAINT messages_message_type_check 
CHECK (message_type IN ('text', 'image', 'system', 'audio', 'location', 'link'));

-- ============================================================================
-- PART 7: Verify changes
-- ============================================================================

DO $$
BEGIN
    RAISE NOTICE 'Migration 086_audio_location_messages.sql completed successfully';
    RAISE NOTICE 'Added columns: audio_url, audio_duration, latitude, longitude, location_name';
    RAISE NOTICE 'Created storage bucket: audio-messages';
END $$;

