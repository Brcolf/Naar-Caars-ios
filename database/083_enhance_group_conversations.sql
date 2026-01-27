-- ============================================================================
-- 083_enhance_group_conversations.sql - Enhance group conversation features
-- ============================================================================
-- Adds support for:
-- 1. Users leaving groups (left_at timestamp)
-- 2. Group avatars/images (group_image_url)
-- 3. Ensures is_archived column exists
-- 4. Storage bucket for group images
-- ============================================================================

-- ============================================================================
-- PART 1: Add left_at column to conversation_participants
-- This tracks when a user leaves a group conversation
-- ============================================================================

-- Add left_at column for tracking when users leave groups
ALTER TABLE public.conversation_participants 
ADD COLUMN IF NOT EXISTS left_at TIMESTAMPTZ DEFAULT NULL;

-- Add comment
COMMENT ON COLUMN public.conversation_participants.left_at IS 
    'Timestamp when user left the conversation. NULL means actively participating.';

-- Create index for active participants (not left)
-- This optimizes queries that filter out users who have left
CREATE INDEX IF NOT EXISTS idx_conversation_participants_active 
ON public.conversation_participants(conversation_id) 
WHERE left_at IS NULL;

-- ============================================================================
-- PART 2: Add group_image_url column to conversations
-- This stores the URL of the group avatar/image
-- ============================================================================

-- Add group_image_url column
ALTER TABLE public.conversations 
ADD COLUMN IF NOT EXISTS group_image_url TEXT DEFAULT NULL;

-- Add comment
COMMENT ON COLUMN public.conversations.group_image_url IS 
    'URL to the group conversation avatar image stored in Supabase Storage.';

-- ============================================================================
-- PART 3: Ensure is_archived column exists
-- The iOS model expects this column
-- ============================================================================

-- Add is_archived column if it doesn't exist
ALTER TABLE public.conversations 
ADD COLUMN IF NOT EXISTS is_archived BOOLEAN DEFAULT FALSE;

-- Add comment
COMMENT ON COLUMN public.conversations.is_archived IS 
    'Whether the conversation is archived by the user.';

-- Create index for non-archived conversations
CREATE INDEX IF NOT EXISTS idx_conversations_not_archived 
ON public.conversations(updated_at DESC) 
WHERE is_archived = FALSE;

-- ============================================================================
-- PART 4: Create storage bucket for group images
-- ============================================================================

-- Create bucket for group images (if not exists)
INSERT INTO storage.buckets (id, name, public, file_size_limit, allowed_mime_types)
VALUES (
    'group-images', 
    'group-images', 
    true,
    5242880, -- 5MB limit
    ARRAY['image/jpeg', 'image/png', 'image/webp']
)
ON CONFLICT (id) DO UPDATE SET
    public = EXCLUDED.public,
    file_size_limit = EXCLUDED.file_size_limit,
    allowed_mime_types = EXCLUDED.allowed_mime_types;

-- ============================================================================
-- PART 5: Storage RLS policies for group images
-- ============================================================================

-- Drop existing policies if they exist (to avoid conflicts)
DROP POLICY IF EXISTS "Group participants can upload group images" ON storage.objects;
DROP POLICY IF EXISTS "Anyone can view group images" ON storage.objects;
DROP POLICY IF EXISTS "Group participants can delete group images" ON storage.objects;

-- Policy: Authenticated users can upload group images
-- Note: We allow any authenticated user to upload since they might be creating a new group
CREATE POLICY "Authenticated users can upload group images"
ON storage.objects FOR INSERT
TO authenticated
WITH CHECK (bucket_id = 'group-images');

-- Policy: Anyone can view group images (they're public)
CREATE POLICY "Anyone can view group images"
ON storage.objects FOR SELECT
TO public
USING (bucket_id = 'group-images');

-- Policy: Authenticated users can update their uploads
CREATE POLICY "Authenticated users can update group images"
ON storage.objects FOR UPDATE
TO authenticated
USING (bucket_id = 'group-images')
WITH CHECK (bucket_id = 'group-images');

-- Policy: Authenticated users can delete group images
CREATE POLICY "Authenticated users can delete group images"
ON storage.objects FOR DELETE
TO authenticated
USING (bucket_id = 'group-images');

-- ============================================================================
-- PART 6: Update RLS policies for conversation_participants
-- Allow participants to update their own left_at (for leaving)
-- ============================================================================

-- Drop and recreate update policy to include left_at updates
DROP POLICY IF EXISTS "conversation_participants_update_own" ON public.conversation_participants;
DROP POLICY IF EXISTS "Users can update own participant record" ON public.conversation_participants;

-- Allow users to update their own participant record (for leaving/last_seen)
CREATE POLICY "Users can update own participant record"
ON public.conversation_participants
FOR UPDATE
USING (user_id = auth.uid())
WITH CHECK (user_id = auth.uid());

-- ============================================================================
-- PART 7: Create helper function for leaving conversations
-- This function sets left_at and handles cleanup
-- ============================================================================

-- Function to leave a conversation
CREATE OR REPLACE FUNCTION public.leave_conversation(
    p_conversation_id UUID,
    p_user_id UUID
)
RETURNS BOOLEAN
LANGUAGE plpgsql
SECURITY DEFINER
SET search_path = public
AS $$
DECLARE
    v_participant_exists BOOLEAN;
    v_already_left BOOLEAN;
BEGIN
    -- Check if user is a participant
    SELECT EXISTS (
        SELECT 1 FROM conversation_participants
        WHERE conversation_id = p_conversation_id
        AND user_id = p_user_id
    ) INTO v_participant_exists;
    
    IF NOT v_participant_exists THEN
        RAISE EXCEPTION 'User is not a participant in this conversation';
    END IF;
    
    -- Check if already left
    SELECT EXISTS (
        SELECT 1 FROM conversation_participants
        WHERE conversation_id = p_conversation_id
        AND user_id = p_user_id
        AND left_at IS NOT NULL
    ) INTO v_already_left;
    
    IF v_already_left THEN
        RETURN FALSE; -- Already left
    END IF;
    
    -- Update left_at timestamp
    UPDATE conversation_participants
    SET left_at = NOW()
    WHERE conversation_id = p_conversation_id
    AND user_id = p_user_id;
    
    RETURN TRUE;
END;
$$;

-- Grant execute permission
GRANT EXECUTE ON FUNCTION public.leave_conversation(UUID, UUID) TO authenticated;

-- Add comment
COMMENT ON FUNCTION public.leave_conversation IS 
    'Marks a user as having left a conversation by setting left_at timestamp.';

-- ============================================================================
-- PART 8: Create helper function for removing participants
-- This is an admin action (can remove others from group)
-- ============================================================================

-- Function to remove a participant (admin action)
CREATE OR REPLACE FUNCTION public.remove_conversation_participant(
    p_conversation_id UUID,
    p_user_id UUID,
    p_removed_by UUID
)
RETURNS BOOLEAN
LANGUAGE plpgsql
SECURITY DEFINER
SET search_path = public
AS $$
DECLARE
    v_remover_is_participant BOOLEAN;
    v_target_exists BOOLEAN;
    v_conversation_creator UUID;
BEGIN
    -- Check if remover is a participant (and not left)
    SELECT EXISTS (
        SELECT 1 FROM conversation_participants
        WHERE conversation_id = p_conversation_id
        AND user_id = p_removed_by
        AND left_at IS NULL
    ) INTO v_remover_is_participant;
    
    -- Also check if remover is the conversation creator
    SELECT created_by INTO v_conversation_creator
    FROM conversations
    WHERE id = p_conversation_id;
    
    IF NOT v_remover_is_participant AND v_conversation_creator != p_removed_by THEN
        RAISE EXCEPTION 'You must be a participant to remove others';
    END IF;
    
    -- Check if target user exists as participant
    SELECT EXISTS (
        SELECT 1 FROM conversation_participants
        WHERE conversation_id = p_conversation_id
        AND user_id = p_user_id
        AND left_at IS NULL
    ) INTO v_target_exists;
    
    IF NOT v_target_exists THEN
        RETURN FALSE; -- Target not found or already left
    END IF;
    
    -- Set left_at timestamp (soft remove)
    UPDATE conversation_participants
    SET left_at = NOW()
    WHERE conversation_id = p_conversation_id
    AND user_id = p_user_id;
    
    RETURN TRUE;
END;
$$;

-- Grant execute permission
GRANT EXECUTE ON FUNCTION public.remove_conversation_participant(UUID, UUID, UUID) TO authenticated;

-- Add comment
COMMENT ON FUNCTION public.remove_conversation_participant IS 
    'Removes a participant from a conversation. Can only be called by existing participants.';

-- ============================================================================
-- PART 9: Add message_type column for system messages
-- This helps distinguish system messages from regular messages
-- ============================================================================

-- Create enum type for message types if it doesn't exist
DO $$
BEGIN
    IF NOT EXISTS (SELECT 1 FROM pg_type WHERE typname = 'message_type') THEN
        CREATE TYPE message_type AS ENUM ('text', 'image', 'system', 'audio', 'location');
    END IF;
EXCEPTION
    WHEN duplicate_object THEN NULL;
END $$;

-- Add message_type column with default 'text'
-- Using TEXT instead of enum for flexibility and easier migration
ALTER TABLE public.messages 
ADD COLUMN IF NOT EXISTS message_type TEXT DEFAULT 'text' 
CHECK (message_type IN ('text', 'image', 'system', 'audio', 'location'));

-- Add comment
COMMENT ON COLUMN public.messages.message_type IS 
    'Type of message: text, image, system (announcements), audio, or location.';

-- Create index for filtering by message type
CREATE INDEX IF NOT EXISTS idx_messages_type 
ON public.messages(message_type) 
WHERE message_type != 'text';

-- ============================================================================
-- PART 10: Verify all changes
-- ============================================================================

-- Log the changes
DO $$
BEGIN
    RAISE NOTICE 'Migration 083_enhance_group_conversations.sql completed successfully';
    RAISE NOTICE 'Added columns: conversation_participants.left_at, conversations.group_image_url, conversations.is_archived, messages.message_type';
    RAISE NOTICE 'Created storage bucket: group-images';
    RAISE NOTICE 'Created functions: leave_conversation, remove_conversation_participant';
END $$;


