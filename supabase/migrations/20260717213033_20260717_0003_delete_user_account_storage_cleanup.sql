-- 20260717213033_20260717_0003_delete_user_account_storage_cleanup.sql
-- Exported verbatim from supabase_migrations.schema_migrations on 2026-10-05.
-- This migration was applied to production through the Supabase MCP / dashboard before being committed.

-- AS-3: account deletion must also remove the user's storage objects so their
-- avatar / message media stop being publicly fetchable. Verbatim reproduction of
-- delete_user_account with a storage.objects cleanup added to the cascade section.
CREATE OR REPLACE FUNCTION public.delete_user_account(p_user_id uuid)
 RETURNS void
 LANGUAGE plpgsql
 SECURITY DEFINER
 SET search_path TO 'public'
AS $function$
DECLARE
    v_record RECORD;
BEGIN
    -- CRITICAL: Verify the caller is deleting their own account
    IF auth.uid() IS NULL OR auth.uid() != p_user_id THEN
        RAISE EXCEPTION 'Not authorized to delete this account';
    END IF;

    -- STEP 1: Claimer leaves — reopen their claimed requests
    FOR v_record IN
        SELECT id, user_id FROM rides
        WHERE claimed_by = p_user_id AND status = 'confirmed'
    LOOP
        PERFORM create_notification(
            v_record.user_id,
            'ride_unclaimed',
            'Ride Reopened',
            'The neighbor who claimed your ride has left. Your ride is open for others to claim.',
            v_record.id, NULL, NULL, NULL, NULL, p_user_id
        );
    END LOOP;

    UPDATE rides SET status = 'open', claimed_by = NULL
    WHERE claimed_by = p_user_id AND status = 'confirmed';

    FOR v_record IN
        SELECT id, user_id FROM favors
        WHERE claimed_by = p_user_id AND status = 'confirmed'
    LOOP
        PERFORM create_notification(
            v_record.user_id,
            'favor_unclaimed',
            'Favor Reopened',
            'The neighbor who claimed your favor has left. Your favor is open for others to claim.',
            NULL, v_record.id, NULL, NULL, NULL, p_user_id
        );
    END LOOP;

    UPDATE favors SET status = 'open', claimed_by = NULL
    WHERE claimed_by = p_user_id AND status = 'confirmed';

    -- STEP 2: Poster leaves — notify claimers before deleting
    FOR v_record IN
        SELECT id, claimed_by FROM rides
        WHERE user_id = p_user_id AND claimed_by IS NOT NULL AND status = 'confirmed'
    LOOP
        PERFORM create_notification(
            v_record.claimed_by,
            'ride_unclaimed',
            'Ride Cancelled',
            'A ride you claimed has been cancelled because the poster left.',
            v_record.id, NULL, NULL, NULL, NULL, p_user_id
        );
    END LOOP;

    FOR v_record IN
        SELECT id, claimed_by FROM favors
        WHERE user_id = p_user_id AND claimed_by IS NOT NULL AND status = 'confirmed'
    LOOP
        PERFORM create_notification(
            v_record.claimed_by,
            'favor_unclaimed',
            'Favor Cancelled',
            'A favor you claimed has been cancelled because the poster left.',
            NULL, v_record.id, NULL, NULL, NULL, p_user_id
        );
    END LOOP;

    -- STEP 3: Clean up orphaned review notifications
    UPDATE notifications SET read = true
    WHERE type IN ('review_request', 'review_reminder')
      AND read = false
      AND (
        ride_id IN (SELECT id FROM rides WHERE claimed_by = p_user_id AND status = 'completed')
        OR favor_id IN (SELECT id FROM favors WHERE claimed_by = p_user_id AND status = 'completed')
      );

    UPDATE rides SET claimed_by = NULL
    WHERE claimed_by = p_user_id AND status = 'completed';

    UPDATE favors SET claimed_by = NULL
    WHERE claimed_by = p_user_id AND status = 'completed';

    -- STEP 4: Clean up completion reminders
    DELETE FROM completion_reminders
    WHERE claimer_user_id = p_user_id;

    -- STEP 4b: Remove the user's storage objects (avatar, message media, uploads).
    -- Deleting the object rows makes the public URLs unservable (404) immediately.
    DELETE FROM storage.objects
    WHERE owner = p_user_id
       OR (bucket_id = 'avatars' AND name = p_user_id::text || '.jpg')
       OR (bucket_id IN ('message-images','audio-messages','town-hall-images','review-images','group-images')
           AND name LIKE p_user_id::text || '/%');

    -- CASCADE DELETES
    DELETE FROM push_tokens WHERE user_id = p_user_id;
    DELETE FROM notifications WHERE user_id = p_user_id;
    DELETE FROM reviews WHERE fulfiller_id = p_user_id OR reviewer_id = p_user_id;
    DELETE FROM town_hall_posts WHERE user_id = p_user_id;
    DELETE FROM invite_codes WHERE created_by = p_user_id;
    DELETE FROM messages WHERE from_id = p_user_id;
    DELETE FROM conversation_participants WHERE user_id = p_user_id;
    DELETE FROM conversations WHERE created_by = p_user_id;
    DELETE FROM rides WHERE user_id = p_user_id;
    DELETE FROM favors WHERE user_id = p_user_id;
    DELETE FROM request_qa WHERE user_id = p_user_id;
    DELETE FROM profiles WHERE id = p_user_id;
    DELETE FROM auth.users WHERE id = p_user_id;
END $function$;
