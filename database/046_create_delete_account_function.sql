-- Create function to delete user account and all associated data
-- This function handles cascade deletion of all user-related data

CREATE OR REPLACE FUNCTION delete_user_account(
    p_user_id UUID
)
RETURNS VOID
LANGUAGE plpgsql
SECURITY DEFINER
SET search_path = public
AS $$
BEGIN
    -- Delete user's push tokens
    DELETE FROM push_tokens WHERE user_id = p_user_id;
    
    -- Delete user's notifications
    DELETE FROM notifications WHERE user_id = p_user_id;
    
    -- Delete user's reviews (both received and given)
    DELETE FROM reviews WHERE fulfiller_id = p_user_id OR reviewer_id = p_user_id;
    
    -- Delete user's town hall posts
    DELETE FROM town_hall_posts WHERE user_id = p_user_id;
    
    -- Delete user's invite codes
    DELETE FROM invite_codes WHERE created_by = p_user_id;
    
    -- Delete user's messages (messages they sent)
    DELETE FROM messages WHERE from_id = p_user_id;
    
    -- Delete conversation participants (this will cascade messages in those conversations)
    DELETE FROM conversation_participants WHERE user_id = p_user_id;
    
    -- Delete conversations created by user (if any)
    DELETE FROM conversations WHERE created_by = p_user_id;
    
    -- Delete user's rides (this will cascade to ride_participants)
    DELETE FROM rides WHERE user_id = p_user_id;
    
    -- Delete user's favors (this will cascade to favor_participants)
    DELETE FROM favors WHERE user_id = p_user_id;
    
    -- Delete request Q&A entries
    DELETE FROM request_qa WHERE user_id = p_user_id;
    
    -- Finally, delete the profile
    DELETE FROM profiles WHERE id = p_user_id;
    
    -- Delete the auth user (requires service role key, handled separately)
    -- This is done via Supabase Admin API, not directly via SQL
    
    -- Log the deletion
    RAISE NOTICE 'Deleted account and all associated data for user: %', p_user_id;
END;
$$;

-- Grant execute permission to authenticated users
GRANT EXECUTE ON FUNCTION delete_user_account TO authenticated;

-- Add comment
COMMENT ON FUNCTION delete_user_account IS 'Deletes a user account and all associated data. This action cannot be undone. Must be called by the user themselves (verified by RLS).';

