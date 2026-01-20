-- Migration: 075_fix_invite_codes_fk_constraint.sql
-- Purpose: Remove the foreign key constraint on invite_codes.used_by
-- 
-- The foreign key constraint causes issues during signup because:
-- 1. Profile creation and invite code marking are separate operations
-- 2. Transaction isolation can cause the profile to not be visible yet
-- 3. For bulk codes, we INSERT a new tracking record which triggers the FK check
--
-- This is safe because:
-- - used_by is only set by our controlled RPC functions
-- - Application logic maintains referential integrity
-- - The SECURITY DEFINER functions handle validation

-- First, find and drop the foreign key constraint on used_by
-- The constraint name is typically: invite_codes_used_by_fkey

ALTER TABLE invite_codes 
DROP CONSTRAINT IF EXISTS invite_codes_used_by_fkey;

-- Also try common alternative naming patterns
ALTER TABLE invite_codes 
DROP CONSTRAINT IF EXISTS fk_invite_codes_used_by;

ALTER TABLE invite_codes 
DROP CONSTRAINT IF EXISTS invite_codes_used_by_profiles_fkey;

ALTER TABLE invite_codes 
DROP CONSTRAINT IF EXISTS invite_codes_used_by_auth_users_fkey;

-- Verify the constraint is gone by listing remaining constraints
DO $$
DECLARE
    constraint_record RECORD;
    found_used_by_fk BOOLEAN := FALSE;
BEGIN
    FOR constraint_record IN 
        SELECT conname, pg_get_constraintdef(oid) as definition
        FROM pg_constraint 
        WHERE conrelid = 'invite_codes'::regclass 
        AND contype = 'f'
    LOOP
        IF constraint_record.definition LIKE '%used_by%' THEN
            found_used_by_fk := TRUE;
            RAISE WARNING 'Found remaining FK on used_by: % - %', constraint_record.conname, constraint_record.definition;
        END IF;
    END LOOP;
    
    IF NOT found_used_by_fk THEN
        RAISE NOTICE 'Success: No foreign key constraints on used_by column';
    END IF;
END $$;

-- List all remaining foreign key constraints on invite_codes for verification
SELECT 
    conname as constraint_name,
    pg_get_constraintdef(oid) as definition
FROM pg_constraint 
WHERE conrelid = 'invite_codes'::regclass 
AND contype = 'f';

