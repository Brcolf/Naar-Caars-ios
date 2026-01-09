-- Migration: Enhance invite_codes table for new invite system
-- Adds fields for invitation statements, bulk invites, and expiration
-- FIXED: Removed NOW() from index predicate (not immutable)

-- Add new columns to invite_codes table
ALTER TABLE invite_codes
ADD COLUMN IF NOT EXISTS invite_statement TEXT,
ADD COLUMN IF NOT EXISTS is_bulk BOOLEAN DEFAULT FALSE,
ADD COLUMN IF NOT EXISTS expires_at TIMESTAMPTZ,
ADD COLUMN IF NOT EXISTS bulk_code_id UUID REFERENCES invite_codes(id) ON DELETE SET NULL;

-- Add index for bulk code lookups
CREATE INDEX IF NOT EXISTS idx_invite_codes_bulk_code_id 
ON invite_codes(bulk_code_id) 
WHERE bulk_code_id IS NOT NULL;

-- Add index for expiration checks
CREATE INDEX IF NOT EXISTS idx_invite_codes_expires_at 
ON invite_codes(expires_at) 
WHERE expires_at IS NOT NULL;

-- Add index for active code lookups (unused codes)
-- Note: We can't use NOW() in index predicate (not immutable), so expiration filtering happens in application code
CREATE INDEX IF NOT EXISTS idx_invite_codes_active 
ON invite_codes(created_by, created_at DESC) 
WHERE used_by IS NULL;

-- Add comment explaining the new fields
COMMENT ON COLUMN invite_codes.invite_statement IS 'Statement provided by inviter explaining who they are inviting and why';
COMMENT ON COLUMN invite_codes.is_bulk IS 'True if this is a bulk invite code that can be used by multiple users';
COMMENT ON COLUMN invite_codes.expires_at IS 'Expiration time for bulk invite codes (48 hours from creation)';
COMMENT ON COLUMN invite_codes.bulk_code_id IS 'For individual signups from bulk invites, links back to the bulk code that created them';

