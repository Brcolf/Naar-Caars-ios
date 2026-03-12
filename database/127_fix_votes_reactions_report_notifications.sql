-- ============================================================================
-- 127_fix_votes_reactions_report_notifications.sql
-- ============================================================================
-- Fixes two bugs and updates a constraint:
-- 1. Town hall comment votes fail because trigger unconditionally inserts
--    NULL post_id into town_hall_post_interactions (NOT NULL column)
-- 2. Message reactions rejected by CHECK constraint that only allows 6 emojis
--    while app offers 21
-- 3. Notification type constraint was missing 'content_reported'
-- ============================================================================

-- ============================================================================
-- FIX 1: Guard town_hall_post_interactions insert for comment votes
-- ============================================================================
-- The trigger fires for ALL votes (post + comment), but unconditionally
-- inserts into town_hall_post_interactions with new.post_id. For comment
-- votes, post_id is NULL, violating the NOT NULL constraint and rolling
-- back the entire vote transaction.
-- Fix: Only insert interaction when post_id IS NOT NULL.
-- ============================================================================

CREATE OR REPLACE FUNCTION public.notify_town_hall_vote()
 RETURNS trigger
 LANGUAGE plpgsql
 SECURITY DEFINER
 SET search_path TO ''
AS $function$
declare
    v_voter_name text;
    v_post record;
    v_vote_type text;
begin
    select name into v_voter_name from public.profiles where id = new.user_id;
    v_voter_name := coalesce(v_voter_name, 'Someone');

    v_vote_type := case when new.vote_type = 'upvote' then 'upvote' else 'downvote' end;

    -- Only record interaction and notify for post votes (not comment votes)
    if new.post_id is not null then
        select * into v_post from public.town_hall_posts where id = new.post_id;

        insert into public.town_hall_post_interactions (post_id, user_id, interaction_type)
        values (new.post_id, new.user_id, v_vote_type)
        on conflict (post_id, user_id, interaction_type) do nothing;

        if new.vote_type = 'upvote' then
            if v_post.user_id != new.user_id then
                perform public.create_notification(
                    v_post.user_id,
                    'town_hall_reaction',
                    'Post Upvoted',
                    v_voter_name || ' upvoted your post',
                    null,
                    null,
                    null,
                    null,
                    new.post_id,
                    new.user_id
                );
            end if;
        end if;
    end if;

    return new;
end;
$function$;

-- ============================================================================
-- FIX 2: Expand message_reactions CHECK constraint to match app's 21 emojis
-- ============================================================================
-- The app (MessageReaction.swift) offers 21 emojis but the DB CHECK constraint
-- only allows 6. Any of the 15 extended emojis silently fail on insert.
-- ============================================================================

ALTER TABLE public.message_reactions DROP CONSTRAINT IF EXISTS message_reactions_reaction_check;
ALTER TABLE public.message_reactions ADD CONSTRAINT message_reactions_reaction_check
    CHECK (reaction IN (
        '❤️', '👍', '👎', '😂', '‼️', '❓',
        '🔥', '👏', '😢', '😮', '🙏', '💯',
        '🎉', '😍', '🤔', '💀', '😱', '👀',
        '✅', '❌', '🙌'
    ));

-- ============================================================================
-- FIX 3: Add 'content_reported' to notification type constraint
-- ============================================================================
-- The existing handle_new_report trigger already notifies admins on reports.
-- The constraint was just missing this type, which could block future inserts.
-- ============================================================================
ALTER TABLE public.notifications DROP CONSTRAINT IF EXISTS valid_notification_type;
ALTER TABLE public.notifications ADD CONSTRAINT valid_notification_type
    CHECK (
        type IN (
            'message',
            'added_to_conversation',
            'new_ride',
            'ride_update',
            'ride_claimed',
            'ride_unclaimed',
            'ride_completed',
            'new_favor',
            'favor_update',
            'favor_claimed',
            'favor_unclaimed',
            'favor_completed',
            'completion_reminder',
            'qa_activity',
            'qa_question',
            'qa_answer',
            'review',
            'review_received',
            'review_reminder',
            'review_request',
            'town_hall_post',
            'town_hall_comment',
            'town_hall_reaction',
            'content_reported',
            'announcement',
            'admin_announcement',
            'broadcast',
            'pending_approval',
            'user_approved',
            'user_rejected',
            'other'
        )
    );

-- ============================================================================
-- Verify
-- ============================================================================
DO $$
BEGIN
    RAISE NOTICE 'Migration 127 completed:';
    RAISE NOTICE '  - Fixed notify_town_hall_vote: guarded post_interactions insert for comment votes';
    RAISE NOTICE '  - Expanded message_reactions CHECK to 21 emojis';
    RAISE NOTICE '  - Added content_reported to notification type constraint';
END $$;
