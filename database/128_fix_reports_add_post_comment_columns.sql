-- Fix: Add reported_post_id and reported_comment_id to reports table
-- The live DB already has these columns, but they were never captured in a migration.

-- Add columns with ON DELETE SET NULL (reports survive when content is deleted)
ALTER TABLE reports ADD COLUMN IF NOT EXISTS reported_post_id UUID
  REFERENCES town_hall_posts(id) ON DELETE SET NULL;
ALTER TABLE reports ADD COLUMN IF NOT EXISTS reported_comment_id UUID
  REFERENCES town_hall_comments(id) ON DELETE SET NULL;

-- Update the check constraint to include new columns.
-- Drop BOTH possible names to handle any DB state:
--   report_target_check  (original name from 087_reports_and_blocking.sql)
--   reports_target_check (erroneously created by earlier version of this migration)
ALTER TABLE reports DROP CONSTRAINT IF EXISTS report_target_check;
ALTER TABLE reports DROP CONSTRAINT IF EXISTS reports_target_check;
ALTER TABLE reports ADD CONSTRAINT report_target_check CHECK (
    reported_user_id IS NOT NULL OR
    reported_message_id IS NOT NULL OR
    reported_post_id IS NOT NULL OR
    reported_comment_id IS NOT NULL
);
