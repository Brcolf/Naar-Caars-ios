-- ============================================================================
-- 050_add_title_to_conversations.sql - Add title column to conversations
-- ============================================================================
-- Adds title column for storing editable group conversation names
-- ============================================================================

-- Add title column if it doesn't exist
DO $$
BEGIN
    IF NOT EXISTS (
        SELECT 1 FROM information_schema.columns 
        WHERE table_name = 'conversations' 
        AND column_name = 'title'
    ) THEN
        ALTER TABLE conversations
        ADD COLUMN title VARCHAR(100);
        
        -- Create index for performance (if needed for searches)
        -- CREATE INDEX IF NOT EXISTS idx_conversations_title 
        -- ON conversations(title) WHERE title IS NOT NULL;
        
        COMMENT ON COLUMN conversations.title IS 'Editable name for group conversations. NULL for direct messages and activity-based conversations.';
    END IF;
END $$;

