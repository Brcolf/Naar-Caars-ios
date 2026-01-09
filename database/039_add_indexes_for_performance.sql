-- Add indexes to optimize conversation queries
-- These indexes ensure efficient queries even at scale

-- ============================================================================
-- Indexes for conversation_participants
-- ============================================================================

-- Index on user_id for fast lookups of user's conversations
CREATE INDEX IF NOT EXISTS idx_conversation_participants_user_id 
ON public.conversation_participants(user_id);

-- Index on conversation_id for fast lookups of conversation participants
CREATE INDEX IF NOT EXISTS idx_conversation_participants_conversation_id 
ON public.conversation_participants(conversation_id);

-- Composite index for common query pattern (conversation_id + user_id)
CREATE INDEX IF NOT EXISTS idx_conversation_participants_conv_user 
ON public.conversation_participants(conversation_id, user_id);

-- ============================================================================
-- Indexes for conversations
-- ============================================================================

-- Index on created_by for fast lookups of user's created conversations
CREATE INDEX IF NOT EXISTS idx_conversations_created_by 
ON public.conversations(created_by);

-- Index on updated_at for efficient sorting
CREATE INDEX IF NOT EXISTS idx_conversations_updated_at 
ON public.conversations(updated_at DESC);

-- Index on ride_id for request-based conversations
CREATE INDEX IF NOT EXISTS idx_conversations_ride_id 
ON public.conversations(ride_id) WHERE ride_id IS NOT NULL;

-- Index on favor_id for request-based conversations
CREATE INDEX IF NOT EXISTS idx_conversations_favor_id 
ON public.conversations(favor_id) WHERE favor_id IS NOT NULL;

-- ============================================================================
-- Indexes for messages
-- ============================================================================

-- Index on conversation_id for fast message lookups
CREATE INDEX IF NOT EXISTS idx_messages_conversation_id 
ON public.messages(conversation_id);

-- Composite index for common query pattern (conversation_id + created_at)
CREATE INDEX IF NOT EXISTS idx_messages_conv_created 
ON public.messages(conversation_id, created_at);

-- Index on from_id for sender lookups
CREATE INDEX IF NOT EXISTS idx_messages_from_id 
ON public.messages(from_id);

-- ============================================================================
-- Performance Notes
-- ============================================================================

-- With these indexes:
-- 1. Querying conversation_participants WHERE user_id = X is O(log n) with index
-- 2. Querying conversations WHERE id IN (list) is O(m log n) where m = list size
-- 3. Both queries are efficient even with thousands of conversations
--
-- The two-query approach (participants first, then conversations) is actually
-- more efficient than a JOIN in many cases because:
-- - The first query filters to a small set (user's conversations)
-- - The second query uses an indexed IN clause
-- - PostgreSQL can optimize both queries independently
--
-- For even better performance at very large scale, consider:
-- - Pagination (limit/offset)
-- - Cursor-based pagination
-- - Materialized views for frequently accessed data


