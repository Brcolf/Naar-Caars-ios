-- Add timezone column to rides table
ALTER TABLE rides ADD COLUMN IF NOT EXISTS timezone TEXT NOT NULL DEFAULT 'America/Los_Angeles';

-- Add timezone column to favors table
ALTER TABLE favors ADD COLUMN IF NOT EXISTS timezone TEXT NOT NULL DEFAULT 'America/Los_Angeles';
