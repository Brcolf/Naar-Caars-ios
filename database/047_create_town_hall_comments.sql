-- ============================================================================
-- 047_create_town_hall_comments.sql - Town Hall Comments Table
-- ============================================================================
-- Creates table for comments on town hall posts with support for nested comments
-- ============================================================================

-- Create comments table
CREATE TABLE IF NOT EXISTS town_hall_comments (
    id UUID PRIMARY KEY DEFAULT gen_random_uuid(),
    post_id UUID NOT NULL REFERENCES town_hall_posts(id) ON DELETE CASCADE,
    user_id UUID NOT NULL REFERENCES profiles(id) ON DELETE CASCADE,
    parent_comment_id UUID REFERENCES town_hall_comments(id) ON DELETE CASCADE,
    content TEXT NOT NULL,
    created_at TIMESTAMPTZ NOT NULL DEFAULT NOW(),
    updated_at TIMESTAMPTZ NOT NULL DEFAULT NOW(),
    
    -- Constraints
    CONSTRAINT valid_content CHECK (char_length(content) > 0 AND char_length(content) <= 5000),
    CONSTRAINT no_self_parent CHECK (parent_comment_id IS NULL OR parent_comment_id != id)
);

-- Create indexes for performance
CREATE INDEX IF NOT EXISTS idx_comments_post_id ON town_hall_comments(post_id);
CREATE INDEX IF NOT EXISTS idx_comments_user_id ON town_hall_comments(user_id);
CREATE INDEX IF NOT EXISTS idx_comments_parent_id ON town_hall_comments(parent_comment_id);
CREATE INDEX IF NOT EXISTS idx_comments_created_at ON town_hall_comments(created_at DESC);

-- Enable RLS
ALTER TABLE town_hall_comments ENABLE ROW LEVEL SECURITY;

-- RLS Policies
-- Users can view all comments
CREATE POLICY "Users can view all comments"
    ON town_hall_comments FOR SELECT
    TO authenticated
    USING (true);

-- Users can create comments on posts
CREATE POLICY "Users can create comments"
    ON town_hall_comments FOR INSERT
    TO authenticated
    WITH CHECK (auth.uid() = user_id);

-- Users can update their own comments
CREATE POLICY "Users can update own comments"
    ON town_hall_comments FOR UPDATE
    TO authenticated
    USING (auth.uid() = user_id)
    WITH CHECK (auth.uid() = user_id);

-- Users can delete their own comments
CREATE POLICY "Users can delete own comments"
    ON town_hall_comments FOR DELETE
    TO authenticated
    USING (auth.uid() = user_id);

-- Trigger to update updated_at
CREATE OR REPLACE FUNCTION update_town_hall_comments_updated_at()
RETURNS TRIGGER AS $$
BEGIN
    NEW.updated_at = NOW();
    RETURN NEW;
END;
$$ LANGUAGE plpgsql;

CREATE TRIGGER update_town_hall_comments_updated_at
    BEFORE UPDATE ON town_hall_comments
    FOR EACH ROW
    EXECUTE FUNCTION update_town_hall_comments_updated_at();

-- Add comment count to posts (optional helper column - can be computed via COUNT)
-- This would require a trigger to update, so we'll compute it in queries instead

COMMENT ON TABLE town_hall_comments IS 'Comments on town hall posts with support for nested replies';
COMMENT ON COLUMN town_hall_comments.parent_comment_id IS 'If set, this is a reply to another comment. NULL means it is a top-level comment on the post.';


