-- 20260312031113_fix_votes_reactions_report_notifications.sql
-- Exported verbatim from supabase_migrations.schema_migrations on 2026-10-05.
-- This migration was applied to production through the Supabase MCP / dashboard before being committed.

-- FIX 1: Guard town_hall_post_interactions insert for comment votes
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

-- FIX 2: Expand message_reactions CHECK constraint to match app's 21 emojis
ALTER TABLE public.message_reactions DROP CONSTRAINT IF EXISTS message_reactions_reaction_check;
ALTER TABLE public.message_reactions ADD CONSTRAINT message_reactions_reaction_check
    CHECK (reaction IN (
        '❤️', '👍', '👎', '😂', '‼️', '❓',
        '🔥', '👏', '😢', '😮', '🙏', '💯',
        '🎉', '😍', '🤔', '💀', '😱', '👀',
        '✅', '❌', '🙌'
    ));

-- FIX 3: Add report notification trigger for admins
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

CREATE OR REPLACE FUNCTION public.notify_report_submitted()
 RETURNS trigger
 LANGUAGE plpgsql
 SECURITY DEFINER
 SET search_path TO ''
AS $function$
declare
    v_admin_id uuid;
    v_reporter_name text;
    v_notification_id uuid;
begin
    select name into v_reporter_name from public.profiles where id = new.reporter_id;
    v_reporter_name := coalesce(v_reporter_name, 'A user');

    for v_admin_id in
        select id from public.profiles where is_admin = true and approved = true
    loop
        v_notification_id := public.create_notification(
            v_admin_id,
            'content_reported',
            'Content Reported',
            v_reporter_name || ' submitted a ' || new.report_type || ' report',
            null,
            null,
            null,
            null,
            null,
            new.reporter_id
        );
    end loop;

    return new;
end;
$function$;

DROP TRIGGER IF EXISTS on_report_submitted_notify ON public.reports;
CREATE TRIGGER on_report_submitted_notify
AFTER INSERT ON public.reports
FOR EACH ROW
EXECUTE FUNCTION public.notify_report_submitted();