-- Migration: Add last_seen column to conversation_participants
-- This tracks when users last viewed a conversation to prevent push notifications
-- when they're actively viewing it

-- Add last_seen column
ALTER TABLE conversation_participants 
ADD COLUMN IF NOT EXISTS last_seen TIMESTAMPTZ;

-- Create index for efficient lookups when checking if user is viewing
CREATE INDEX IF NOT EXISTS idx_conversation_participants_last_seen 
ON conversation_participants(conversation_id, last_seen);

-- Add comment for documentation
COMMENT ON COLUMN conversation_participants.last_seen IS 'Timestamp of when user last viewed this conversation. Used to prevent push notifications when user is actively viewing.';


