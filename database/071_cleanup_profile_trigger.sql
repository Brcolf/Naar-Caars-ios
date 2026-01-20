-- Migration: 071_cleanup_profile_trigger.sql
-- Purpose: Remove the handle_new_user trigger if it exists
-- This trigger was created in migration 070 but is causing issues:
-- 1. When admin rejects a user (deletes profile), the trigger recreates it
-- 2. The profile should only be created during the signup flow, not automatically
--
-- Run this migration if you previously ran 070_fix_profile_creation_for_signup.sql

-- Drop the trigger if it exists
DROP TRIGGER IF EXISTS on_auth_user_created ON auth.users;

-- Drop the function if it exists
DROP FUNCTION IF EXISTS public.handle_new_user();

-- Also drop the RPC function if it exists (it's not needed)
DROP FUNCTION IF EXISTS public.upsert_profile_for_signup(UUID, TEXT, TEXT, UUID, TEXT);

-- Verify cleanup
DO $$
BEGIN
    -- Check if trigger still exists
    IF EXISTS (
        SELECT 1 FROM pg_trigger 
        WHERE tgname = 'on_auth_user_created'
    ) THEN
        RAISE EXCEPTION 'Trigger on_auth_user_created still exists!';
    END IF;
    
    RAISE NOTICE 'Cleanup complete: trigger and functions removed';
END $$;

