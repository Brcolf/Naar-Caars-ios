-- Fix: Add auth.uid() verification to delete_user_account
-- The live DB already has this guard, but it was never captured in a migration.
-- Without this, any authenticated user could delete another user's account.

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

    -- ========================================================
    -- STEP 1: Claimer leaves — reopen their claimed requests
    -- Notify each poster that the request is available again.
    -- ========================================================

    -- Rides: notify poster, then reopen
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

    -- Favors: notify poster, then reopen
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

    -- ========================================================
    -- STEP 2: Poster leaves — notify claimers before deleting
    -- The existing DELETE FROM rides/favors will remove these.
    -- ========================================================

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

    -- ========================================================
    -- STEP 3: Clean up orphaned review notifications
    -- Mark review_request/review_reminder as read for completed
    -- requests where the departing user was the claimer.
    -- ========================================================

    UPDATE notifications SET read = true
    WHERE type IN ('review_request', 'review_reminder')
      AND read = false
      AND (
        ride_id IN (SELECT id FROM rides WHERE claimed_by = p_user_id AND status = 'completed')
        OR favor_id IN (SELECT id FROM favors WHERE claimed_by = p_user_id AND status = 'completed')
      );

    -- Clear claimed_by on completed requests (no review possible)
    UPDATE rides SET claimed_by = NULL
    WHERE claimed_by = p_user_id AND status = 'completed';

    UPDATE favors SET claimed_by = NULL
    WHERE claimed_by = p_user_id AND status = 'completed';

    -- ========================================================
    -- STEP 4: Clean up completion reminders
    -- ========================================================

    DELETE FROM completion_reminders
    WHERE claimer_user_id = p_user_id;

    -- ========================================================
    -- EXISTING CASCADE DELETES (unchanged)
    -- ========================================================

    DELETE FROM push_tokens WHERE user_id = p_user_id;
    DELETE FROM notifications WHERE user_id = p_user_id;
    DELETE FROM reviews WHERE fulfiller_id = p_user_id OR reviewer_id = p_user_id;
    -- town_hall_comments: CASCADE-deleted via town_hall_comments_post_id_fkey
    -- reports.reported_post_id: SET NULL via reports_reported_post_id_fkey
    -- reports.reported_comment_id: SET NULL via reports_reported_comment_id_fkey
    DELETE FROM town_hall_posts WHERE user_id = p_user_id;
    DELETE FROM invite_codes WHERE created_by = p_user_id;
    DELETE FROM messages WHERE from_id = p_user_id;
    DELETE FROM conversation_participants WHERE user_id = p_user_id;
    DELETE FROM conversations WHERE created_by = p_user_id;
    DELETE FROM rides WHERE user_id = p_user_id;
    DELETE FROM favors WHERE user_id = p_user_id;
    DELETE FROM request_qa WHERE user_id = p_user_id;
    -- reports.reporter_id: CASCADE-deleted via reports_reporter_id_fkey
    -- reports.reported_user_id: CASCADE-deleted via reports_reported_user_id_fkey
    -- blocked_users: CASCADE-deleted via both blocker_id and blocked_id FKs
    DELETE FROM profiles WHERE id = p_user_id;
    DELETE FROM auth.users WHERE id = p_user_id;
END $function$;
