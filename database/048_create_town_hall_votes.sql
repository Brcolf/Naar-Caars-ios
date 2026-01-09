-- ============================================================================
-- 048_create_town_hall_votes.sql - Town Hall Votes Table
-- ============================================================================
-- Creates table for upvotes/downvotes on posts and comments
-- ============================================================================

-- Create votes table
CREATE TABLE IF NOT EXISTS town_hall_votes (
    id UUID PRIMARY KEY DEFAULT gen_random_uuid(),
    user_id UUID NOT NULL REFERENCES profiles(id) ON DELETE CASCADE,
    post_id UUID REFERENCES town_hall_posts(id) ON DELETE CASCADE,
    comment_id UUID REFERENCES town_hall_comments(id) ON DELETE CASCADE,
    vote_type VARCHAR(10) NOT NULL CHECK (vote_type IN ('upvote', 'downvote')),
    created_at TIMESTAMPTZ NOT NULL DEFAULT NOW(),
    updated_at TIMESTAMPTZ NOT NULL DEFAULT NOW(),
    
    -- Constraints
    CONSTRAINT vote_target CHECK (
        (post_id IS NOT NULL AND comment_id IS NULL) OR
        (post_id IS NULL AND comment_id IS NOT NULL)
    )
);

-- Create indexes for performance
CREATE INDEX IF NOT EXISTS idx_votes_post_id ON town_hall_votes(post_id);
CREATE INDEX IF NOT EXISTS idx_votes_comment_id ON town_hall_votes(comment_id);
CREATE INDEX IF NOT EXISTS idx_votes_user_id ON town_hall_votes(user_id);
CREATE INDEX IF NOT EXISTS idx_votes_type ON town_hall_votes(vote_type);

-- Create partial unique indexes for vote uniqueness
-- Only one vote per user per post
CREATE UNIQUE INDEX IF NOT EXISTS idx_unique_user_post_vote 
    ON town_hall_votes(user_id, post_id) 
    WHERE post_id IS NOT NULL;

-- Only one vote per user per comment
CREATE UNIQUE INDEX IF NOT EXISTS idx_unique_user_comment_vote 
    ON town_hall_votes(user_id, comment_id) 
    WHERE comment_id IS NOT NULL;

-- Enable RLS
ALTER TABLE town_hall_votes ENABLE ROW LEVEL SECURITY;

-- RLS Policies
-- Users can view all votes (needed to show vote counts)
CREATE POLICY "Users can view all votes"
    ON town_hall_votes FOR SELECT
    TO authenticated
    USING (true);

-- Users can create/update votes on posts and comments
CREATE POLICY "Users can create votes"
    ON town_hall_votes FOR INSERT
    TO authenticated
    WITH CHECK (auth.uid() = user_id);

-- Users can update their own votes (to change upvote to downvote or vice versa)
CREATE POLICY "Users can update own votes"
    ON town_hall_votes FOR UPDATE
    TO authenticated
    USING (auth.uid() = user_id)
    WITH CHECK (auth.uid() = user_id);

-- Users can delete their own votes (to remove vote)
CREATE POLICY "Users can delete own votes"
    ON town_hall_votes FOR DELETE
    TO authenticated
    USING (auth.uid() = user_id);

-- Trigger to update updated_at
CREATE OR REPLACE FUNCTION update_town_hall_votes_updated_at()
RETURNS TRIGGER AS $$
BEGIN
    NEW.updated_at = NOW();
    RETURN NEW;
END;
$$ LANGUAGE plpgsql;

CREATE TRIGGER update_town_hall_votes_updated_at
    BEFORE UPDATE ON town_hall_votes
    FOR EACH ROW
    EXECUTE FUNCTION update_town_hall_votes_updated_at();

COMMENT ON TABLE town_hall_votes IS 'Upvotes and downvotes on town hall posts and comments';
COMMENT ON COLUMN town_hall_votes.vote_type IS 'Either "upvote" or "downvote"';
COMMENT ON COLUMN town_hall_votes.post_id IS 'Vote on a post (mutually exclusive with comment_id)';
COMMENT ON COLUMN town_hall_votes.comment_id IS 'Vote on a comment (mutually exclusive with post_id)';

