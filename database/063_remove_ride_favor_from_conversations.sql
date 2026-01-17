-- ============================================================================
-- 063_remove_ride_favor_from_conversations.sql - Remove ride_id and favor_id from conversations
-- ============================================================================
-- Removes ride_id and favor_id columns from conversations table
-- Conversations are now independent of rides/favors
-- ============================================================================

-- Remove foreign key constraints first
DO $$
BEGIN
    -- Drop foreign key constraint for ride_id if it exists
    IF EXISTS (
        SELECT 1 FROM information_schema.table_constraints 
        WHERE constraint_name = 'conversations_ride_id_fkey'
    ) THEN
        ALTER TABLE public.conversations
        DROP CONSTRAINT conversations_ride_id_fkey;
    END IF;
    
    -- Drop foreign key constraint for favor_id if it exists
    IF EXISTS (
        SELECT 1 FROM information_schema.table_constraints 
        WHERE constraint_name = 'conversations_favor_id_fkey'
    ) THEN
        ALTER TABLE public.conversations
        DROP CONSTRAINT conversations_favor_id_fkey;
    END IF;
END $$;

-- Remove indexes if they exist
DROP INDEX IF EXISTS idx_conversations_ride_id;
DROP INDEX IF EXISTS idx_conversations_favor_id;

-- Remove columns
DO $$
BEGIN
    -- Remove ride_id column
    IF EXISTS (
        SELECT 1 FROM information_schema.columns 
        WHERE table_name = 'conversations' 
        AND column_name = 'ride_id'
    ) THEN
        ALTER TABLE public.conversations
        DROP COLUMN ride_id;
    END IF;
    
    -- Remove favor_id column
    IF EXISTS (
        SELECT 1 FROM information_schema.columns 
        WHERE table_name = 'conversations' 
        AND column_name = 'favor_id'
    ) THEN
        ALTER TABLE public.conversations
        DROP COLUMN favor_id;
    END IF;
END $$;

-- Add comment to document the change
COMMENT ON TABLE public.conversations IS 'Conversations are now independent of rides/favors. Use conversation_participants to link users.';

