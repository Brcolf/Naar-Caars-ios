# Database Migration Instructions - Invite System

## Error
```
column invite_codes.expires_at does not exist
```

## Solution
Run the database migration `044_enhance_invite_codes.sql` in your Supabase project.

## Steps to Run Migration

### Option 1: Supabase Dashboard (Recommended)

1. **Open Supabase Dashboard**
   - Go to https://supabase.com/dashboard
   - Select your project: `easlpsksbylyceqiqecq`

2. **Navigate to SQL Editor**
   - In the left sidebar, click **"SQL Editor"**
   - Click **"New query"** button (top right)

3. **Copy and Paste Migration**
   - Open the file: `database/044_enhance_invite_codes.sql`
   - Copy the entire contents
   - Paste into the SQL Editor

4. **Run the Migration**
   - Click **"Run"** button (or press `Cmd+Enter` / `Ctrl+Enter`)
   - Wait for success message: "Success. No rows returned"

5. **Verify Migration**
   - Run this query to verify the columns exist:
   ```sql
   SELECT column_name, data_type 
   FROM information_schema.columns 
   WHERE table_name = 'invite_codes' 
   ORDER BY ordinal_position;
   ```
   - You should see:
     - `invite_statement` (text)
     - `is_bulk` (boolean)
     - `expires_at` (timestamp with time zone)
     - `bulk_code_id` (uuid)

### Option 2: Supabase CLI

If you have Supabase CLI set up:

```bash
cd /Users/bcolf/.cursor/worktrees/naars-cars-ios/vcs
supabase db push
```

Or run the migration directly:

```bash
supabase db execute --file database/044_enhance_invite_codes.sql
```

## Migration Contents

The migration adds:
- `invite_statement TEXT` - Statement about who is being invited
- `is_bulk BOOLEAN DEFAULT FALSE` - Flag for bulk invite codes
- `expires_at TIMESTAMPTZ` - Expiration time for bulk codes (48 hours)
- `bulk_code_id UUID` - Reference to parent bulk code

Plus indexes for performance.

## After Running Migration

1. **Restart the app** (or just navigate away and back to Profile)
2. The error should be resolved
3. You should be able to:
   - Generate invite codes
   - View current invite code
   - Generate bulk invite codes (as admin)

## Troubleshooting

### Migration Fails with "column already exists"
- The migration uses `IF NOT EXISTS`, so this shouldn't happen
- If it does, the columns are already added - you're good to go!

### Still Getting the Error After Migration
1. **Clear app cache**: Delete and reinstall the app
2. **Check Supabase connection**: Verify you're connected to the correct project
3. **Verify columns exist**: Run the verification query above

### Need to Rollback?
If you need to remove these columns (not recommended):

```sql
ALTER TABLE invite_codes
DROP COLUMN IF EXISTS invite_statement,
DROP COLUMN IF EXISTS is_bulk,
DROP COLUMN IF EXISTS expires_at,
DROP COLUMN IF EXISTS bulk_code_id;
```

## Quick Copy-Paste SQL

Here's the migration SQL ready to paste:

```sql
-- Migration: Enhance invite_codes table for new invite system
-- Adds fields for invitation statements, bulk invites, and expiration

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

-- Add index for active code lookups (unused, not expired, not bulk)
CREATE INDEX IF NOT EXISTS idx_invite_codes_active 
ON invite_codes(created_by, created_at DESC) 
WHERE used_by IS NULL AND (expires_at IS NULL OR expires_at > NOW());

-- Add comment explaining the new fields
COMMENT ON COLUMN invite_codes.invite_statement IS 'Statement provided by inviter explaining who they are inviting and why';
COMMENT ON COLUMN invite_codes.is_bulk IS 'True if this is a bulk invite code that can be used by multiple users';
COMMENT ON COLUMN invite_codes.expires_at IS 'Expiration time for bulk invite codes (48 hours from creation)';
COMMENT ON COLUMN invite_codes.bulk_code_id IS 'For individual signups from bulk invites, links back to the bulk code that created them';
```

