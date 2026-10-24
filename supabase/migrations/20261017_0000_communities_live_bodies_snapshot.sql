-- 20261017_0000_communities_live_bodies_snapshot.sql
--
-- ROLLBACK ARTEFACT, NOT APPLIED IN THE FORWARD ROLLOUT. Run this file only to roll Phase 0 of
-- the multi-community build back (Docs/superpowers/specs/2026-10-07-multi-community-design.md
-- §4, Phase 0 step 0, as amended by 2026-10-17-multi-community-decisions.md). Running it on a
-- database where Phase 0 has not started is a no-op: every statement below restores exactly
-- what is live today.
--
-- What it holds, captured read-only from the live project on 2026-10-17 (pg_get_functiondef,
-- pg_policies, pg_get_viewdef), before any Phase 0 call:
--   1. the 26 function bodies that Phase 0 edits or wraps, verbatim, each preceded by the
--      md5(prosrc) of the live body (the spec's step 0 list of 23, plus protect_admin_fields_on_insert,
--      which 20261017_0001 [call] 1a.4 replaces, and the two get_leaderboard overloads, which
--      20261017_0003 calls 17 and 18 replace; call 18 also makes get_leaderboard(date, date) SECURITY
--      DEFINER, and the body here, which has no SECURITY clause, puts it back to invoker rights);
--   2. ALTER POLICY statements restoring the roles and predicates (qual / with_check) of the
--      28 policies spec §3.4 alters in Phase 0, plus the town_hall_posts DELETE policy that
--      Phase 3 alters;
--   3. the definitions of the three views Phase 0 replaces (guest_rides, guest_favors,
--      public_profiles), with their grants.
--
-- How this file was verified (2026-10-17, read-only): the text between each function's
-- $function$ quotes hashes to the live md5(prosrc) (26 of 26; the last three were added the
-- same day and checked the same way); the 29 policies' roles, qual and
-- with_check as written here equal pg_policies character for character (one md5 over all 29,
-- and a row-by-row comparison, 29 of 29); each view body hashes to the live
-- md5(pg_get_viewdef(oid, true)) once the table name is unqualified (3 of 3). Nothing was run
-- against the database with this file.
--
-- The one real change of step 0 is the forward migration
-- 20261017_0000a_revoke_get_or_create_conversation.sql (applied through the MCP, not by this file):
--   revoke execute on function public.get_or_create_conversation(uuid[]) from authenticated, anon;
--   revoke execute on function public.get_or_create_request_conversation(uuid, uuid, uuid) from authenticated, anon;
-- Neither function is called by the iOS app or an edge function; the second references columns
-- that do not exist live. Before the revoke both are executable by postgres, authenticated and
-- service_role (anon already has no EXECUTE). Section 4 below undoes the revoke.
--
-- Edge function: the send-message-push left_at IS NULL recipient filter is already in this
-- branch's source (supabase/functions/send-message-push/index.ts). Step 0 deploys it only if
-- the live function lacks the filter; the apply runner checks the deployed source first. This
-- file does not touch edge functions; rolling the filter back is never needed (it only stops
-- pushes to members who left a conversation).
--
-- How to run a rollback:
--   * In the SQL editor, in one run, after disabling the triggers Phase 0 added (spec §4,
--     Rollback) and dropping NOT NULL on community_id if step 6 is live. Run the sections in
--     order: policies are restored before the views, because the Phase 0 versions of the
--     request_qa and reviews anon policies reference guest_rides / guest_favors.
--   * Or through the MCP, one statement per call, in the same order, except
--     delete_user_account and admin_reject_pending_user: their bodies delete from auth.* /
--     storage.*, which the MCP declines, so those two always go through the SQL editor. The MCP
--     also declines DROP VIEW (seen 2026-10-17 in the step 0 dry-run), so the two
--     `drop view if exists` statements of section 3 go through the SQL editor too.
--   * Unqualified names inside the policy predicates are as pg_policies prints them and resolve
--     to public under the default search_path of both the SQL editor and the MCP.
--   * CREATE OR REPLACE FUNCTION cannot change a return type, argument names or remove a
--     default. If a later step changed one of those for a function below, drop that version
--     first (drop function public.<name>(<new signature>);) and then run the body here.
--     CREATE OR REPLACE keeps the function's existing EXECUTE grants.
--   * guest_rides / guest_favors gain community_id in step 2, and CREATE OR REPLACE VIEW cannot
--     drop a column, so section 3 drops and recreates them and restores today's grants
--     (select for anon only, as 20261006_0005). public_profiles keeps its column list in Phase 0
--     and is replaced in place (its grants are kept).
--   * New tables, columns, helpers and triggers from steps 1-6 are left in place; the spec's
--     rollback disables the new triggers and keeps the additive objects.
--
-- What clients see after a rollback: exactly today's behaviour on every build.

-- =========================================================================================
-- 1. Functions (live bodies, verbatim)
-- =========================================================================================

-- should_notify_user: md5(prosrc) = df75c614219979f8fbc56f6b4c32a240
CREATE OR REPLACE FUNCTION public.should_notify_user(p_user_id uuid, p_notification_type text)
 RETURNS boolean
 LANGUAGE plpgsql
 SECURITY DEFINER
 SET search_path TO ''
AS $function$
DECLARE
    v_profile RECORD;
BEGIN
    SELECT * INTO v_profile FROM public.profiles WHERE id = p_user_id;
    IF NOT FOUND THEN
        RETURN false;
    END IF;

    CASE
        WHEN p_notification_type IN ('new_ride', 'new_favor') THEN
            RETURN true;
        WHEN p_notification_type IN ('announcement', 'admin_announcement', 'broadcast') THEN
            RETURN true;
        WHEN p_notification_type IN ('user_approved', 'user_rejected') THEN
            RETURN true;
        WHEN p_notification_type = 'pending_approval' THEN
            RETURN v_profile.is_admin;
        WHEN p_notification_type IN ('message', 'added_to_conversation') THEN
            RETURN v_profile.notify_messages;
        WHEN p_notification_type IN (
            'ride_update', 'ride_claimed', 'ride_unclaimed', 'ride_completed',
            'favor_update', 'favor_claimed', 'favor_unclaimed', 'favor_completed'
        ) THEN
            RETURN v_profile.notify_ride_updates;
        WHEN p_notification_type IN ('qa_activity', 'qa_question', 'qa_answer') THEN
            RETURN v_profile.notify_qa_activity;
        WHEN p_notification_type IN (
            'review', 'review_received', 'review_reminder', 'review_request', 'completion_reminder'
        ) THEN
            RETURN v_profile.notify_review_reminders;
        WHEN p_notification_type IN ('town_hall_post', 'town_hall_comment', 'town_hall_reaction') THEN
            RETURN v_profile.notify_town_hall;
        WHEN p_notification_type = 'content_reported' THEN
            RETURN v_profile.is_admin;
        WHEN p_notification_type = 'content_hidden' THEN
            RETURN true;
        ELSE
            RETURN false;
    END CASE;
END;
$function$
;

-- notify_new_ride: md5(prosrc) = ee08d0b5f0448949b8bce8e5a99af862
CREATE OR REPLACE FUNCTION public.notify_new_ride()
 RETURNS trigger
 LANGUAGE plpgsql
 SECURITY DEFINER
 SET search_path TO ''
AS $function$
DECLARE
    v_poster_name TEXT;
    v_destination TEXT;
    v_user_record RECORD;
    v_notification_id UUID;
BEGIN
    SELECT name INTO v_poster_name FROM public.profiles WHERE id = NEW.user_id;
    v_poster_name := COALESCE(v_poster_name, 'Someone');
    v_destination := COALESCE(NEW.destination, 'a destination');

    FOR v_user_record IN
        SELECT id FROM public.profiles WHERE approved = true AND id != NEW.user_id
    LOOP
        v_notification_id := public.create_notification(
            v_user_record.id, 'new_ride', 'New Ride Request',
            v_poster_name || ' needs a ride to ' || v_destination,
            NEW.id, NULL, NULL, NULL, NULL, NEW.user_id
        );
        IF v_notification_id IS NOT NULL THEN
            PERFORM public.queue_push_notification(
                v_user_record.id, 'new_ride', 'New Ride Request',
                v_poster_name || ' needs a ride to ' || v_destination,
                jsonb_build_object('ride_id', NEW.id::text), NULL, v_notification_id
            );
        END IF;
    END LOOP;

    RETURN NEW;
END;
$function$
;

-- notify_new_favor: md5(prosrc) = 6e07ec5265d469b932bee6357c0ded30
CREATE OR REPLACE FUNCTION public.notify_new_favor()
 RETURNS trigger
 LANGUAGE plpgsql
 SECURITY DEFINER
 SET search_path TO ''
AS $function$
DECLARE
    v_poster_name TEXT;
    v_user_record RECORD;
    v_notification_id UUID;
BEGIN
    SELECT name INTO v_poster_name FROM public.profiles WHERE id = NEW.user_id;
    v_poster_name := COALESCE(v_poster_name, 'Someone');

    FOR v_user_record IN
        SELECT id FROM public.profiles WHERE approved = true AND id != NEW.user_id
    LOOP
        v_notification_id := public.create_notification(
            v_user_record.id, 'new_favor', 'New Favor Request',
            v_poster_name || ' needs help: ' || LEFT(NEW.title, 50),
            NULL, NEW.id, NULL, NULL, NULL, NEW.user_id
        );
        IF v_notification_id IS NOT NULL THEN
            PERFORM public.queue_push_notification(
                v_user_record.id, 'new_favor', 'New Favor Request',
                v_poster_name || ' needs help: ' || LEFT(NEW.title, 50),
                jsonb_build_object('favor_id', NEW.id::text), NULL, v_notification_id
            );
        END IF;
    END LOOP;

    RETURN NEW;
END;
$function$
;

-- notify_town_hall_post: md5(prosrc) = ccc627969694f1177df307b8edc033e1
CREATE OR REPLACE FUNCTION public.notify_town_hall_post()
 RETURNS trigger
 LANGUAGE plpgsql
 SECURITY DEFINER
 SET search_path TO ''
AS $function$
DECLARE
    v_poster_name TEXT;
    v_user_record RECORD;
    v_batch_key TEXT;
    v_notification_id UUID;
BEGIN
    SELECT name INTO v_poster_name FROM public.profiles WHERE id = NEW.user_id;
    v_poster_name := COALESCE(v_poster_name, 'Someone');

    v_batch_key := 'town_hall_' || to_char(date_trunc('minute', NOW()) -
        (EXTRACT(MINUTE FROM NOW())::int % 5) * INTERVAL '1 minute', 'YYYY-MM-DD-HH24-MI');

    FOR v_user_record IN
        SELECT id FROM public.profiles
        WHERE approved = true
          AND id != NEW.user_id
          AND notify_town_hall = true
    LOOP
        v_notification_id := public.create_notification(
            v_user_record.id, 'town_hall_post', 'New in Town Hall',
            v_poster_name || ' posted: "' || LEFT(NEW.content, 40) || '"',
            NULL, NULL, NULL, NULL, NEW.id, NEW.user_id
        );
        IF v_notification_id IS NOT NULL THEN
            PERFORM public.queue_push_notification(
                v_user_record.id, 'town_hall_post', 'New in Town Hall',
                v_poster_name || ' posted: "' || LEFT(NEW.content, 40) || '"',
                jsonb_build_object('town_hall_post_id', NEW.id::text), v_batch_key, v_notification_id
            );
        END IF;
    END LOOP;

    RETURN NEW;
END;
$function$
;

-- notify_pending_user: md5(prosrc) = 57634dd2df8f216a25302e2e8c6db0d4
CREATE OR REPLACE FUNCTION public.notify_pending_user()
 RETURNS trigger
 LANGUAGE plpgsql
 SECURITY DEFINER
 SET search_path TO 'public'
AS $function$
DECLARE
    v_admin_id UUID;
    v_user_name TEXT;
    v_notification_id UUID;
BEGIN
    IF NEW.approved = true THEN
        RETURN NEW;
    END IF;

    v_user_name := COALESCE(NEW.name, NEW.email);

    FOR v_admin_id IN
        SELECT id FROM public.profiles WHERE is_admin = true AND approved = true
    LOOP
        v_notification_id := public.create_notification(
            v_admin_id,
            'pending_approval'::TEXT,
            'New User Pending Approval'::TEXT,
            (v_user_name || ' is waiting for approval')::TEXT,
            NULL::UUID, NULL::UUID, NULL::UUID, NULL::UUID, NULL::UUID, NEW.id
        );
        IF v_notification_id IS NOT NULL THEN
            PERFORM public.queue_push_notification(
                v_admin_id,
                'pending_approval'::TEXT,
                'New User Pending Approval'::TEXT,
                (v_user_name || ' is waiting for approval')::TEXT,
                jsonb_build_object('user_id', NEW.id::text),
                NULL::TEXT,
                v_notification_id
            );
        END IF;
    END LOOP;

    RETURN NEW;
END;
$function$
;

-- notify_user_approved: md5(prosrc) = f7ba95aafa8b371b203e52e2dcf45f9f
CREATE OR REPLACE FUNCTION public.notify_user_approved()
 RETURNS trigger
 LANGUAGE plpgsql
 SECURITY DEFINER
 SET search_path TO 'public'
AS $function$
DECLARE
    v_notification_id UUID;
BEGIN
    IF OLD.approved = false AND NEW.approved = true THEN
        v_notification_id := create_notification(
            NEW.id,
            'user_approved'::TEXT,
            'Welcome to Naar''s Cars!'::TEXT,
            'Your account has been approved. Tap to enter the app.'::TEXT,
            NULL::UUID,
            NULL::UUID,
            NULL::UUID,
            NULL::UUID,
            NULL::UUID,
            NULL::UUID
        );

        IF v_notification_id IS NOT NULL THEN
            PERFORM queue_push_notification(
                NEW.id,
                'user_approved'::TEXT,
                'Welcome to Naar''s Cars!'::TEXT,
                'Your account has been approved. Tap to enter the app.'::TEXT,
                jsonb_build_object('action', 'enter_app'),
                NULL::TEXT,
                v_notification_id
            );
        END IF;
    END IF;

    RETURN NEW;
END;
$function$
;

-- handle_new_report: md5(prosrc) = d2cfc188ab5306952e6ecfaf59c0fac6
CREATE OR REPLACE FUNCTION public.handle_new_report()
 RETURNS trigger
 LANGUAGE plpgsql
 SECURITY DEFINER
 SET search_path TO ''
AS $function$
DECLARE
    v_report_count INT;
    v_content_preview TEXT;
    v_admin RECORD;
    v_notification_id UUID;
    v_body TEXT;
    v_target_type TEXT;
    v_conversation_id UUID;
    v_town_hall_post_id UUID;
BEGIN
    IF NEW.reported_post_id IS NOT NULL THEN
        v_target_type := 'town_hall_post';

        SELECT COUNT(DISTINCT r.reporter_id)::INT
        INTO v_report_count
        FROM public.reports r
        WHERE r.reported_post_id = NEW.reported_post_id;

        SELECT LEFT(p.content, 80), p.id
        INTO v_content_preview, v_town_hall_post_id
        FROM public.town_hall_posts p
        WHERE p.id = NEW.reported_post_id;

        IF v_report_count >= 3 THEN
            UPDATE public.reports
            SET content_hidden = true
            WHERE reported_post_id = NEW.reported_post_id;

            UPDATE public.town_hall_posts
            SET hidden_at = NOW(),
                hidden_by = NULL,
                hidden_reason = NULL
            WHERE id = NEW.reported_post_id
              AND hidden_at IS NULL;

            IF FOUND THEN
                INSERT INTO public.content_moderation_events (
                    target_type,
                    target_id,
                    report_id,
                    action,
                    acted_by,
                    reason
                )
                VALUES (
                    'town_hall_post',
                    NEW.reported_post_id,
                    NEW.id,
                    'auto_hide',
                    NULL,
                    NULL
                );
            END IF;
        END IF;
    ELSIF NEW.reported_comment_id IS NOT NULL THEN
        v_target_type := 'town_hall_comment';

        SELECT COUNT(DISTINCT r.reporter_id)::INT
        INTO v_report_count
        FROM public.reports r
        WHERE r.reported_comment_id = NEW.reported_comment_id;

        SELECT LEFT(c.content, 80), c.post_id
        INTO v_content_preview, v_town_hall_post_id
        FROM public.town_hall_comments c
        WHERE c.id = NEW.reported_comment_id;

        IF v_report_count >= 3 THEN
            UPDATE public.reports
            SET content_hidden = true
            WHERE reported_comment_id = NEW.reported_comment_id;

            UPDATE public.town_hall_comments
            SET hidden_at = NOW(),
                hidden_by = NULL,
                hidden_reason = NULL
            WHERE id = NEW.reported_comment_id
              AND hidden_at IS NULL;

            IF FOUND THEN
                INSERT INTO public.content_moderation_events (
                    target_type,
                    target_id,
                    report_id,
                    action,
                    acted_by,
                    reason
                )
                VALUES (
                    'town_hall_comment',
                    NEW.reported_comment_id,
                    NEW.id,
                    'auto_hide',
                    NULL,
                    NULL
                );
            END IF;
        END IF;
    ELSIF NEW.reported_message_id IS NOT NULL THEN
        v_target_type := 'message';

        SELECT LEFT(m.text, 80), m.conversation_id
        INTO v_content_preview, v_conversation_id
        FROM public.messages m
        WHERE m.id = NEW.reported_message_id;
    ELSIF NEW.reported_ride_id IS NOT NULL THEN
        v_target_type := 'ride';

        SELECT LEFT(CONCAT_WS(' -> ', r.pickup, r.destination), 80)
        INTO v_content_preview
        FROM public.rides r
        WHERE r.id = NEW.reported_ride_id;
    ELSIF NEW.reported_favor_id IS NOT NULL THEN
        v_target_type := 'favor';

        SELECT LEFT(CONCAT_WS(': ', f.title, NULLIF(f.description, '')), 80)
        INTO v_content_preview
        FROM public.favors f
        WHERE f.id = NEW.reported_favor_id;
    ELSE
        v_target_type := 'user';

        SELECT LEFT(COALESCE(p.name, 'User report'), 80)
        INTO v_content_preview
        FROM public.profiles p
        WHERE p.id = NEW.reported_user_id;
    END IF;

    IF v_content_preview IS NULL THEN
        v_content_preview := 'Reported content';
    END IF;

    v_body := INITCAP(REPLACE(COALESCE(NEW.report_type, 'other'), '_', ' ')) || ': ' || LEFT(v_content_preview, 60);

    FOR v_admin IN
        SELECT p.id
        FROM public.profiles p
        WHERE p.is_admin = true
    LOOP
        v_notification_id := public.create_notification(
            v_admin.id,
            'content_reported',
            'Content Reported',
            v_body,
            NEW.reported_ride_id,
            NEW.reported_favor_id,
            v_conversation_id,
            NULL,
            v_town_hall_post_id,
            NEW.reporter_id
        );

        IF v_notification_id IS NOT NULL THEN
            PERFORM public.queue_push_notification(
                v_admin.id,
                'content_reported',
                'Content Reported',
                v_body,
                jsonb_strip_nulls(jsonb_build_object(
                    'report_id', NEW.id::TEXT,
                    'target_type', v_target_type,
                    'reported_user_id', NEW.reported_user_id::TEXT,
                    'reported_message_id', NEW.reported_message_id::TEXT,
                    'reported_post_id', NEW.reported_post_id::TEXT,
                    'reported_comment_id', NEW.reported_comment_id::TEXT,
                    'reported_ride_id', NEW.reported_ride_id::TEXT,
                    'reported_favor_id', NEW.reported_favor_id::TEXT,
                    'ride_id', NEW.reported_ride_id::TEXT,
                    'favor_id', NEW.reported_favor_id::TEXT,
                    'conversation_id', v_conversation_id::TEXT,
                    'town_hall_post_id', v_town_hall_post_id::TEXT
                )),
                NULL,
                v_notification_id
            );
        END IF;
    END LOOP;

    RETURN NEW;
END;
$function$
;

-- send_broadcast_notifications: md5(prosrc) = 8b3eb719ce8f0d4bc57b50f7a228d873
CREATE OR REPLACE FUNCTION public.send_broadcast_notifications(p_title text, p_body text, p_type text DEFAULT 'broadcast'::text, p_pinned boolean DEFAULT false)
 RETURNS integer
 LANGUAGE plpgsql
 SECURITY DEFINER
 SET search_path TO 'public'
AS $function$
DECLARE
    v_user_id UUID;
    v_admin_id UUID;
    v_inserted_count INTEGER := 0;
    v_notification_id UUID;
    v_post_id UUID;
BEGIN
    v_admin_id := auth.uid();

    -- SECURITY FIX: Verify caller is an admin
    IF NOT EXISTS (
        SELECT 1 FROM profiles
        WHERE id = v_admin_id AND is_admin = true
    ) THEN
        RAISE EXCEPTION 'Only admins can send broadcast notifications';
    END IF;

    INSERT INTO town_hall_posts (
        user_id, title, content, pinned, type, created_at, updated_at
    ) VALUES (
        v_admin_id, p_title, p_body, p_pinned, 'announcement', NOW(), NOW()
    )
    RETURNING id INTO v_post_id;

    FOR v_user_id IN
        SELECT id FROM profiles WHERE approved = true
    LOOP
        INSERT INTO notifications (
            user_id, type, title, body, read, pinned,
            town_hall_post_id, source_user_id, created_at
        ) VALUES (
            v_user_id, p_type, p_title, p_body, false, p_pinned,
            v_post_id, v_admin_id, NOW()
        )
        RETURNING id INTO v_notification_id;

        v_inserted_count := v_inserted_count + 1;
    END LOOP;

    RETURN v_inserted_count;
END;
$function$
;

-- handle_new_review: md5(prosrc) = 7d2ea7b2860f79f509ba288d1885bb50
CREATE OR REPLACE FUNCTION public.handle_new_review()
 RETURNS trigger
 LANGUAGE plpgsql
 SECURITY DEFINER
 SET search_path TO 'public'
AS $function$
BEGIN
    INSERT INTO public.town_hall_posts (user_id, title, content, review_id, type, image_url)
    VALUES (
        NEW.reviewer_id,
        'New Review',
        format('%s %s', repeat('⭐', NEW.rating), COALESCE(NEW.comment, '')),
        NEW.id,
        'review',
        NEW.image_url
    );

    RETURN NEW;
END;
$function$
;

-- record_xp_on_request_created: md5(prosrc) = 619620a04d2a1a541d6d5a5b59be88f9
CREATE OR REPLACE FUNCTION public.record_xp_on_request_created()
 RETURNS trigger
 LANGUAGE plpgsql
 SECURITY DEFINER
 SET search_path TO 'public'
AS $function$
DECLARE
    v_is_first BOOLEAN;
BEGIN
    IF TG_TABLE_NAME = 'rides' THEN
        INSERT INTO public.xp_events (user_id, amount, source_type, source_id, description, created_at)
        VALUES (
            NEW.user_id, 5, 'ride_requested', NEW.id,
            'Requested: ' || COALESCE(NEW.pickup || ' → ' || NEW.destination, 'Ride'),
            NEW.created_at
        )
        ON CONFLICT (source_type, source_id) DO NOTHING;

        SELECT NOT EXISTS (
            SELECT 1 FROM public.rides WHERE user_id = NEW.user_id AND id != NEW.id
        ) INTO v_is_first;

        IF v_is_first THEN
            INSERT INTO public.xp_events (user_id, amount, source_type, source_id, description, created_at)
            VALUES (NEW.user_id, 10, 'first_ride', NEW.id, 'First ride milestone', NEW.created_at)
            ON CONFLICT (source_type, source_id) DO NOTHING;
        END IF;
    ELSE
        INSERT INTO public.xp_events (user_id, amount, source_type, source_id, description, created_at)
        VALUES (
            NEW.user_id, 5, 'favor_requested', NEW.id,
            'Requested: ' || COALESCE(NEW.title, 'Favor'),
            NEW.created_at
        )
        ON CONFLICT (source_type, source_id) DO NOTHING;

        SELECT NOT EXISTS (
            SELECT 1 FROM public.favors WHERE user_id = NEW.user_id AND id != NEW.id
        ) INTO v_is_first;

        IF v_is_first THEN
            INSERT INTO public.xp_events (user_id, amount, source_type, source_id, description, created_at)
            VALUES (NEW.user_id, 10, 'first_favor', NEW.id, 'First favor milestone', NEW.created_at)
            ON CONFLICT (source_type, source_id) DO NOTHING;
        END IF;
    END IF;
    RETURN NEW;
END;
$function$
;

-- record_xp_on_completion: md5(prosrc) = b0a3a0261e08546a6adbb512a347c5fc
CREATE OR REPLACE FUNCTION public.record_xp_on_completion()
 RETURNS trigger
 LANGUAGE plpgsql
 SECURITY DEFINER
 SET search_path TO 'public'
AS $function$
BEGIN
    IF NEW.status = 'completed' AND OLD.status IS DISTINCT FROM 'completed' AND NEW.claimed_by IS NOT NULL THEN
        IF TG_TABLE_NAME = 'rides' THEN
            INSERT INTO public.xp_events (user_id, amount, source_type, source_id, description, created_at)
            VALUES (
                NEW.claimed_by,
                (5 + COALESCE(FLOOR(NEW.estimated_cost / 5), 0))::INTEGER,
                'ride_fulfilled',
                NEW.id,
                COALESCE(NEW.pickup || ' → ' || NEW.destination, 'Ride'),
                COALESCE(NEW.updated_at, now())
            )
            ON CONFLICT (source_type, source_id) DO NOTHING;
        ELSE
            INSERT INTO public.xp_events (user_id, amount, source_type, source_id, description, created_at)
            VALUES (
                NEW.claimed_by,
                10,
                'favor_fulfilled',
                NEW.id,
                COALESCE(NEW.title, 'Favor'),
                COALESCE(NEW.updated_at, now())
            )
            ON CONFLICT (source_type, source_id) DO NOTHING;
        END IF;
    END IF;
    RETURN NEW;
END;
$function$
;

-- record_xp_on_review: md5(prosrc) = ad5d8e55d7953e0c6353c9ee3ed275a8
CREATE OR REPLACE FUNCTION public.record_xp_on_review()
 RETURNS trigger
 LANGUAGE plpgsql
 SECURITY DEFINER
 SET search_path TO 'public'
AS $function$
BEGIN
    IF NEW.rating >= 4 THEN
        INSERT INTO public.xp_events (user_id, amount, source_type, source_id, description, created_at)
        VALUES (
            NEW.fulfiller_id,
            CASE WHEN NEW.rating = 5 THEN 5 ELSE 2 END,
            'review_received',
            NEW.id,
            CASE WHEN NEW.rating = 5 THEN '5-star review' ELSE '4-star review' END,
            NEW.created_at
        )
        ON CONFLICT (source_type, source_id) DO NOTHING;
    END IF;
    RETURN NEW;
END;
$function$
;

-- protect_admin_fields: md5(prosrc) = 57a4ac220177f3bda6c86f3c8a5ca450
CREATE OR REPLACE FUNCTION public.protect_admin_fields()
 RETURNS trigger
 LANGUAGE plpgsql
 SET search_path TO ''
AS $function$
BEGIN
    -- Only admins can modify is_admin, approved, or is_banned
    IF (OLD.is_admin != NEW.is_admin
        OR OLD.approved != NEW.approved
        OR (OLD.is_banned IS DISTINCT FROM NEW.is_banned)) THEN
        IF NOT (SELECT is_admin FROM public.profiles WHERE id = auth.uid()) THEN
            RAISE EXCEPTION 'Only admins can modify is_admin, approved, or is_banned fields';
        END IF;
    END IF;
    RETURN NEW;
END;
$function$
;

-- protect_admin_fields_on_insert: md5(prosrc) = 4e633efc9535982003c39d103c704958
CREATE OR REPLACE FUNCTION public.protect_admin_fields_on_insert()
 RETURNS trigger
 LANGUAGE plpgsql
 SET search_path TO ''
AS $function$
begin
    if auth.uid() is not null and not coalesce(public.is_admin_user(auth.uid()), false) then
        new.is_admin := false;
        new.approved := false;
        new.is_banned := false;
        new.ban_reason := null;
        new.banned_at := null;
        new.banned_by := null;
    end if;
    return new;
end;
$function$
;

-- guard_request_client_update: md5(prosrc) = d5ba2e3d5bebc33d21dd9835b96e46b0
CREATE OR REPLACE FUNCTION public.guard_request_client_update()
 RETURNS trigger
 LANGUAGE plpgsql
 SET search_path TO ''
AS $function$
declare
  v_uid uuid := (select auth.uid());
  v_free constant text[] := array['status', 'claimed_by', 'updated_at', 'reviewed', 'review_skipped', 'review_skipped_at'];
begin
  if current_user not in ('authenticated', 'anon') then
    return new;
  end if;

  if new.id is distinct from old.id
     or new.user_id is distinct from old.user_id
     or new.created_at is distinct from old.created_at
     or new.hidden_at is distinct from old.hidden_at
     or new.hidden_by is distinct from old.hidden_by
     or new.hidden_reason is distinct from old.hidden_reason then
    raise exception 'This change to a request is not allowed' using errcode = '42501';
  end if;

  if v_uid is not null and v_uid = old.user_id then
    if new.claimed_by is not null and new.claimed_by is distinct from old.claimed_by then
      raise exception 'A request is claimed by the person helping, not assigned by its poster' using errcode = '42501';
    end if;
    return new;
  end if;

  new.reviewed := old.reviewed;
  new.review_skipped := old.review_skipped;
  new.review_skipped_at := old.review_skipped_at;

  if (to_jsonb(new) - v_free) is distinct from (to_jsonb(old) - v_free) then
    raise exception 'Only the person who posted a request can edit it' using errcode = '42501';
  end if;

  if old.claimed_by is null and old.status::text = 'open'
     and new.claimed_by = v_uid and new.status::text = 'confirmed' then
    return new;
  end if;
  if old.claimed_by = v_uid and old.status::text = 'confirmed'
     and new.claimed_by is null and new.status::text = 'open' then
    return new;
  end if;
  if old.claimed_by = v_uid and old.status::text = 'confirmed'
     and new.claimed_by = v_uid and new.status::text = 'completed' then
    return new;
  end if;
  if new.claimed_by is not distinct from old.claimed_by and new.status is not distinct from old.status then
    return new;
  end if;

  raise exception 'This change to a request is not allowed' using errcode = '42501';
end
$function$
;

-- get_xp_leaderboard: md5(prosrc) = e2275c4e9fb5bbfc8be556e2716fdd4b
CREATE OR REPLACE FUNCTION public.get_xp_leaderboard(start_date date DEFAULT '1970-01-01'::date, end_date date DEFAULT CURRENT_DATE)
 RETURNS TABLE(user_id uuid, name text, avatar_url text, xp bigint, badges jsonb, streak_weeks bigint, requests_fulfilled bigint, requests_made bigint)
 LANGUAGE plpgsql
 SECURITY DEFINER
 SET search_path TO 'public'
AS $function$
BEGIN
    RETURN QUERY
    WITH
    user_xp AS (
        SELECT
            xe.user_id,
            SUM(xe.amount)::BIGINT AS event_xp
        FROM public.xp_events xe
        WHERE xe.created_at::date BETWEEN start_date AND end_date
        GROUP BY xe.user_id
    ),
    fulfilled_weeks AS (
        SELECT DISTINCT
            xe.user_id AS uid,
            DATE_TRUNC('week', xe.created_at)::DATE AS week_start
        FROM public.xp_events xe
        WHERE xe.source_type IN ('ride_fulfilled', 'favor_fulfilled')
          AND xe.created_at::date BETWEEN start_date AND end_date
    ),
    week_numbered AS (
        SELECT uid, week_start,
            ROW_NUMBER() OVER (PARTITION BY uid ORDER BY week_start) AS rn
        FROM fulfilled_weeks
    ),
    streaks AS (
        SELECT uid, COUNT(*)::BIGINT AS streak_len
        FROM week_numbered
        GROUP BY uid, (week_start - (rn * INTERVAL '7 days'))
    ),
    longest_streaks AS (
        SELECT uid, MAX(streak_len)::BIGINT AS longest_streak
        FROM streaks GROUP BY uid
    ),
    user_stats AS (
        SELECT
            ux.user_id,
            ux.event_xp,
            COALESCE(ls.longest_streak, 0) AS streak_wks,
            (SELECT COUNT(*) FROM public.xp_events x2
             WHERE x2.user_id = ux.user_id
               AND x2.source_type IN ('ride_fulfilled', 'favor_fulfilled')
               AND x2.created_at::date BETWEEN start_date AND end_date)::BIGINT AS fulfilled_total,
            (SELECT COUNT(*) FROM public.xp_events x3
             WHERE x3.user_id = ux.user_id
               AND x3.source_type IN ('ride_requested', 'favor_requested')
               AND x3.created_at::date BETWEEN start_date AND end_date)::BIGINT AS made_total,
            (SELECT COUNT(*) FROM public.xp_events x4
             WHERE x4.user_id = ux.user_id AND x4.source_type = 'ride_fulfilled'
               AND x4.created_at::date BETWEEN start_date AND end_date)::BIGINT AS rides_fulfilled_cnt,
            (SELECT COUNT(*) FROM public.xp_events x5
             WHERE x5.user_id = ux.user_id AND x5.source_type = 'favor_fulfilled'
               AND x5.created_at::date BETWEEN start_date AND end_date)::BIGINT AS favors_fulfilled_cnt,
            (SELECT COUNT(*) FROM public.xp_events x6
             WHERE x6.user_id = ux.user_id AND x6.source_type = 'review_received' AND x6.amount = 5
               AND x6.created_at::date BETWEEN start_date AND end_date)::BIGINT AS five_star_cnt,
            (SELECT COUNT(*) FROM public.xp_events x7
             WHERE x7.user_id = ux.user_id
               AND x7.source_type IN ('ride_requested', 'favor_requested')
               AND x7.created_at::date BETWEEN start_date AND end_date)::BIGINT AS requests_made_cnt,
            -- FIX: Only count savings from rides the user FULFILLED (claimed_by), not requested
            COALESCE((SELECT SUM(r.estimated_cost)
             FROM public.rides r
             WHERE r.claimed_by = ux.user_id
               AND r.status = 'completed'), 0) AS savings
        FROM user_xp ux
        LEFT JOIN longest_streaks ls ON ls.uid = ux.user_id
    )
    SELECT
        p.id AS user_id,
        p.name AS name,
        p.avatar_url AS avatar_url,
        (us.event_xp + us.streak_wks * 5)::BIGINT AS xp,
        (
            SELECT COALESCE(jsonb_agg(badge), '[]'::jsonb)
            FROM (
                SELECT 'road_warrior' AS badge WHERE us.rides_fulfilled_cnt >= 10
                UNION ALL
                SELECT 'good_neighbor' WHERE us.favors_fulfilled_cnt >= 10
                UNION ALL
                SELECT 'streak_champion' WHERE us.streak_wks >= 3
                UNION ALL
                SELECT 'five_star' WHERE us.five_star_cnt >= 10
                UNION ALL
                SELECT 'big_saver' WHERE us.savings >= 250
                UNION ALL
                SELECT 'frequent_carbardian' WHERE us.requests_made_cnt >= 10
            ) b
        ) AS badges,
        us.streak_wks::BIGINT AS streak_weeks,
        us.fulfilled_total::BIGINT AS requests_fulfilled,
        us.made_total::BIGINT AS requests_made
    FROM user_stats us
    JOIN profiles p ON p.id = us.user_id
    WHERE p.approved = true
      AND (us.event_xp + us.streak_wks * 5) > 0
    ORDER BY (us.event_xp + us.streak_wks * 5) DESC
    LIMIT 100;
END;
$function$
;

-- get_leaderboard_spotlights: md5(prosrc) = 20c425ccb0cfb6a1e849280305a281e9
CREATE OR REPLACE FUNCTION public.get_leaderboard_spotlights(start_date date DEFAULT '1970-01-01'::date, end_date date DEFAULT CURRENT_DATE)
 RETURNS TABLE(category text, user_id uuid, name text, avatar_url text, value bigint)
 LANGUAGE plpgsql
 SECURITY DEFINER
 SET search_path TO 'public'
AS $function$
BEGIN

    -- Temp table to track already-claimed user IDs (dropped at end of txn)
    CREATE TEMP TABLE IF NOT EXISTS _claimed_users (
        uid UUID PRIMARY KEY
    ) ON COMMIT DROP;
    TRUNCATE _claimed_users;

    -- -----------------------------------------------------------------
    -- Category 1: longest_streak
    -- The user with the most consecutive weeks of fulfilling at least
    -- one request (ride or favor) in the date range.
    -- Uses DATE_TRUNC('week', ...) gaps-and-islands approach.
    -- -----------------------------------------------------------------
    RETURN QUERY
    WITH
    fulfilled_weeks AS (
        SELECT DISTINCT
            r.claimed_by AS uid,
            DATE_TRUNC('week', r.updated_at)::DATE AS week_start
        FROM rides r
        WHERE r.claimed_by IS NOT NULL
          AND r.status = 'completed'
          AND r.updated_at::date BETWEEN start_date AND end_date

        UNION

        SELECT DISTINCT
            f.claimed_by AS uid,
            DATE_TRUNC('week', f.updated_at)::DATE AS week_start
        FROM favors f
        WHERE f.claimed_by IS NOT NULL
          AND f.status = 'completed'
          AND f.updated_at::date BETWEEN start_date AND end_date
    ),
    week_numbered AS (
        SELECT
            fw.uid,
            fw.week_start,
            ROW_NUMBER() OVER (PARTITION BY fw.uid ORDER BY fw.week_start) AS rn
        FROM fulfilled_weeks fw
    ),
    streaks AS (
        SELECT
            wn.uid,
            COUNT(*)::BIGINT AS streak_len
        FROM week_numbered wn
        GROUP BY wn.uid, (wn.week_start - (wn.rn * INTERVAL '7 days'))
    ),
    longest_per_user AS (
        SELECT
            s.uid,
            MAX(s.streak_len)::BIGINT AS longest_streak
        FROM streaks s
        GROUP BY s.uid
    )
    SELECT
        'longest_streak'::TEXT        AS category,
        p.id                          AS user_id,
        p.name                        AS name,
        p.avatar_url                  AS avatar_url,
        lpu.longest_streak            AS value
    FROM longest_per_user lpu
    JOIN profiles p ON p.id = lpu.uid
    WHERE p.approved = true
      AND lpu.longest_streak > 0
      AND lpu.uid NOT IN (SELECT cu.uid FROM _claimed_users cu)
    ORDER BY lpu.longest_streak DESC, p.name ASC
    LIMIT 1;

    -- Claim the longest_streak winner
    INSERT INTO _claimed_users (uid)
    WITH
    fulfilled_weeks AS (
        SELECT DISTINCT
            r.claimed_by AS uid,
            DATE_TRUNC('week', r.updated_at)::DATE AS week_start
        FROM rides r
        WHERE r.claimed_by IS NOT NULL
          AND r.status = 'completed'
          AND r.updated_at::date BETWEEN start_date AND end_date

        UNION

        SELECT DISTINCT
            f.claimed_by AS uid,
            DATE_TRUNC('week', f.updated_at)::DATE AS week_start
        FROM favors f
        WHERE f.claimed_by IS NOT NULL
          AND f.status = 'completed'
          AND f.updated_at::date BETWEEN start_date AND end_date
    ),
    week_numbered AS (
        SELECT
            fw.uid,
            fw.week_start,
            ROW_NUMBER() OVER (PARTITION BY fw.uid ORDER BY fw.week_start) AS rn
        FROM fulfilled_weeks fw
    ),
    streaks AS (
        SELECT
            wn.uid,
            COUNT(*)::BIGINT AS streak_len
        FROM week_numbered wn
        GROUP BY wn.uid, (wn.week_start - (wn.rn * INTERVAL '7 days'))
    ),
    longest_per_user AS (
        SELECT
            s.uid,
            MAX(s.streak_len)::BIGINT AS longest_streak
        FROM streaks s
        GROUP BY s.uid
    )
    SELECT lpu.uid
    FROM longest_per_user lpu
    JOIN profiles p ON p.id = lpu.uid
    WHERE p.approved = true
      AND lpu.longest_streak > 0
      AND lpu.uid NOT IN (SELECT cu.uid FROM _claimed_users cu)
    ORDER BY lpu.longest_streak DESC, p.name ASC
    LIMIT 1
    ON CONFLICT DO NOTHING;

    -- -----------------------------------------------------------------
    -- Category 2: rising_star
    -- The user who gained the most direct-action XP in the date range.
    -- XP formula:
    --   Ride fulfilled:  5 + floor(estimated_cost / 5)
    --   Favor fulfilled: 10 flat
    --   Ride requested:  5
    --   Favor requested: 5
    --   5-star review:   5
    --   4-star review:   2
    -- -----------------------------------------------------------------
    RETURN QUERY
    WITH
    rides_fulfilled_xp AS (
        SELECT
            r.claimed_by AS uid,
            SUM(5 + COALESCE(FLOOR(r.estimated_cost / 5), 0))::BIGINT AS xp
        FROM rides r
        WHERE r.claimed_by IS NOT NULL
          AND r.status = 'completed'
          AND r.updated_at::date BETWEEN start_date AND end_date
        GROUP BY r.claimed_by
    ),
    favors_fulfilled_xp AS (
        SELECT
            f.claimed_by AS uid,
            (COUNT(*) * 10)::BIGINT AS xp
        FROM favors f
        WHERE f.claimed_by IS NOT NULL
          AND f.status = 'completed'
          AND f.updated_at::date BETWEEN start_date AND end_date
        GROUP BY f.claimed_by
    ),
    rides_requested_xp AS (
        SELECT
            r.user_id AS uid,
            (COUNT(*) * 5)::BIGINT AS xp
        FROM rides r
        WHERE r.created_at::date BETWEEN start_date AND end_date
        GROUP BY r.user_id
    ),
    favors_requested_xp AS (
        SELECT
            f.user_id AS uid,
            (COUNT(*) * 5)::BIGINT AS xp
        FROM favors f
        WHERE f.created_at::date BETWEEN start_date AND end_date
        GROUP BY f.user_id
    ),
    review_xp AS (
        SELECT
            rv.fulfiller_id AS uid,
            SUM(CASE WHEN rv.rating = 5 THEN 5
                     WHEN rv.rating = 4 THEN 2
                     ELSE 0 END)::BIGINT AS xp
        FROM reviews rv
        WHERE rv.created_at::date BETWEEN start_date AND end_date
        GROUP BY rv.fulfiller_id
    ),
    all_users AS (
        SELECT uid FROM rides_fulfilled_xp
        UNION SELECT uid FROM favors_fulfilled_xp
        UNION SELECT uid FROM rides_requested_xp
        UNION SELECT uid FROM favors_requested_xp
        UNION SELECT uid FROM review_xp
    ),
    user_totals AS (
        SELECT
            au.uid,
            (
                COALESCE(rf.xp, 0)
                + COALESCE(ff.xp, 0)
                + COALESCE(rr.xp, 0)
                + COALESCE(fr.xp, 0)
                + COALESCE(rv.xp, 0)
            )::BIGINT AS total_xp
        FROM all_users au
        LEFT JOIN rides_fulfilled_xp  rf ON rf.uid = au.uid
        LEFT JOIN favors_fulfilled_xp ff ON ff.uid = au.uid
        LEFT JOIN rides_requested_xp  rr ON rr.uid = au.uid
        LEFT JOIN favors_requested_xp fr ON fr.uid = au.uid
        LEFT JOIN review_xp           rv ON rv.uid = au.uid
    )
    SELECT
        'rising_star'::TEXT           AS category,
        p.id                          AS user_id,
        p.name                        AS name,
        p.avatar_url                  AS avatar_url,
        ut.total_xp                   AS value
    FROM user_totals ut
    JOIN profiles p ON p.id = ut.uid
    WHERE p.approved = true
      AND ut.total_xp > 0
      AND ut.uid NOT IN (SELECT cu.uid FROM _claimed_users cu)
    ORDER BY ut.total_xp DESC, p.name ASC
    LIMIT 1;

    -- Claim the rising_star winner
    INSERT INTO _claimed_users (uid)
    WITH
    rides_fulfilled_xp AS (
        SELECT
            r.claimed_by AS uid,
            SUM(5 + COALESCE(FLOOR(r.estimated_cost / 5), 0))::BIGINT AS xp
        FROM rides r
        WHERE r.claimed_by IS NOT NULL
          AND r.status = 'completed'
          AND r.updated_at::date BETWEEN start_date AND end_date
        GROUP BY r.claimed_by
    ),
    favors_fulfilled_xp AS (
        SELECT
            f.claimed_by AS uid,
            (COUNT(*) * 10)::BIGINT AS xp
        FROM favors f
        WHERE f.claimed_by IS NOT NULL
          AND f.status = 'completed'
          AND f.updated_at::date BETWEEN start_date AND end_date
        GROUP BY f.claimed_by
    ),
    rides_requested_xp AS (
        SELECT
            r.user_id AS uid,
            (COUNT(*) * 5)::BIGINT AS xp
        FROM rides r
        WHERE r.created_at::date BETWEEN start_date AND end_date
        GROUP BY r.user_id
    ),
    favors_requested_xp AS (
        SELECT
            f.user_id AS uid,
            (COUNT(*) * 5)::BIGINT AS xp
        FROM favors f
        WHERE f.created_at::date BETWEEN start_date AND end_date
        GROUP BY f.user_id
    ),
    review_xp AS (
        SELECT
            rv.fulfiller_id AS uid,
            SUM(CASE WHEN rv.rating = 5 THEN 5
                     WHEN rv.rating = 4 THEN 2
                     ELSE 0 END)::BIGINT AS xp
        FROM reviews rv
        WHERE rv.created_at::date BETWEEN start_date AND end_date
        GROUP BY rv.fulfiller_id
    ),
    all_users AS (
        SELECT uid FROM rides_fulfilled_xp
        UNION SELECT uid FROM favors_fulfilled_xp
        UNION SELECT uid FROM rides_requested_xp
        UNION SELECT uid FROM favors_requested_xp
        UNION SELECT uid FROM review_xp
    ),
    user_totals AS (
        SELECT
            au.uid,
            (
                COALESCE(rf.xp, 0)
                + COALESCE(ff.xp, 0)
                + COALESCE(rr.xp, 0)
                + COALESCE(fr.xp, 0)
                + COALESCE(rv.xp, 0)
            )::BIGINT AS total_xp
        FROM all_users au
        LEFT JOIN rides_fulfilled_xp  rf ON rf.uid = au.uid
        LEFT JOIN favors_fulfilled_xp ff ON ff.uid = au.uid
        LEFT JOIN rides_requested_xp  rr ON rr.uid = au.uid
        LEFT JOIN favors_requested_xp fr ON fr.uid = au.uid
        LEFT JOIN review_xp           rv ON rv.uid = au.uid
    )
    SELECT ut.uid
    FROM user_totals ut
    JOIN profiles p ON p.id = ut.uid
    WHERE p.approved = true
      AND ut.total_xp > 0
      AND ut.uid NOT IN (SELECT cu.uid FROM _claimed_users cu)
    ORDER BY ut.total_xp DESC, p.name ASC
    LIMIT 1
    ON CONFLICT DO NOTHING;

    -- -----------------------------------------------------------------
    -- Category 3: top_requester
    -- The user who posted the most requests (rides + favors) in the
    -- date range.
    -- -----------------------------------------------------------------
    RETURN QUERY
    WITH
    ride_counts AS (
        SELECT
            r.user_id AS uid,
            COUNT(*)::BIGINT AS cnt
        FROM rides r
        WHERE r.created_at::date BETWEEN start_date AND end_date
        GROUP BY r.user_id
    ),
    favor_counts AS (
        SELECT
            f.user_id AS uid,
            COUNT(*)::BIGINT AS cnt
        FROM favors f
        WHERE f.created_at::date BETWEEN start_date AND end_date
        GROUP BY f.user_id
    ),
    all_requesters AS (
        SELECT uid FROM ride_counts
        UNION SELECT uid FROM favor_counts
    ),
    requester_totals AS (
        SELECT
            ar.uid,
            (COALESCE(rc.cnt, 0) + COALESCE(fc.cnt, 0))::BIGINT AS total_requests
        FROM all_requesters ar
        LEFT JOIN ride_counts  rc ON rc.uid = ar.uid
        LEFT JOIN favor_counts fc ON fc.uid = ar.uid
    )
    SELECT
        'top_requester'::TEXT         AS category,
        p.id                          AS user_id,
        p.name                        AS name,
        p.avatar_url                  AS avatar_url,
        rt.total_requests             AS value
    FROM requester_totals rt
    JOIN profiles p ON p.id = rt.uid
    WHERE p.approved = true
      AND rt.total_requests > 0
      AND rt.uid NOT IN (SELECT cu.uid FROM _claimed_users cu)
    ORDER BY rt.total_requests DESC, p.name ASC
    LIMIT 1;

    -- Claim the top_requester winner
    INSERT INTO _claimed_users (uid)
    WITH
    ride_counts AS (
        SELECT
            r.user_id AS uid,
            COUNT(*)::BIGINT AS cnt
        FROM rides r
        WHERE r.created_at::date BETWEEN start_date AND end_date
        GROUP BY r.user_id
    ),
    favor_counts AS (
        SELECT
            f.user_id AS uid,
            COUNT(*)::BIGINT AS cnt
        FROM favors f
        WHERE f.created_at::date BETWEEN start_date AND end_date
        GROUP BY f.user_id
    ),
    all_requesters AS (
        SELECT uid FROM ride_counts
        UNION SELECT uid FROM favor_counts
    ),
    requester_totals AS (
        SELECT
            ar.uid,
            (COALESCE(rc.cnt, 0) + COALESCE(fc.cnt, 0))::BIGINT AS total_requests
        FROM all_requesters ar
        LEFT JOIN ride_counts  rc ON rc.uid = ar.uid
        LEFT JOIN favor_counts fc ON fc.uid = ar.uid
    )
    SELECT rt.uid
    FROM requester_totals rt
    JOIN profiles p ON p.id = rt.uid
    WHERE p.approved = true
      AND rt.total_requests > 0
      AND rt.uid NOT IN (SELECT cu.uid FROM _claimed_users cu)
    ORDER BY rt.total_requests DESC, p.name ASC
    LIMIT 1
    ON CONFLICT DO NOTHING;

END;
$function$
;

-- get_leaderboard(text, integer): md5(prosrc) = aa577f5aeff40103e8ca5e4488d7216c (SECURITY DEFINER)
CREATE OR REPLACE FUNCTION public.get_leaderboard(p_time_filter text DEFAULT 'all_time'::text, p_limit integer DEFAULT 50)
 RETURNS TABLE(user_id uuid, name text, avatar_url text, fulfilled_count bigint, average_rating numeric, review_count bigint, rank bigint)
 LANGUAGE plpgsql
 SECURITY DEFINER
 SET search_path TO ''
AS $function$
BEGIN
    RETURN QUERY
    SELECT
        p.id as user_id,
        p.name,
        p.avatar_url,
        COALESCE(fulfilled.count, 0)::BIGINT as fulfilled_count,
        COALESCE(ROUND(reviews.avg_rating, 2), 0)::NUMERIC as average_rating,
        COALESCE(reviews.review_count, 0)::BIGINT as review_count,
        RANK() OVER (ORDER BY COALESCE(fulfilled.count, 0) DESC) as rank
    FROM public.profiles p
    LEFT JOIN (
        SELECT 
            fulfiller_id,
            COUNT(*) as count
        FROM public.reviews
        WHERE (p_time_filter = 'all_time' OR created_at >= CASE
            WHEN p_time_filter = 'week' THEN NOW() - INTERVAL '7 days'
            WHEN p_time_filter = 'month' THEN NOW() - INTERVAL '30 days'
            WHEN p_time_filter = 'year' THEN NOW() - INTERVAL '365 days'
            ELSE '1970-01-01'::TIMESTAMPTZ
        END)
        GROUP BY fulfiller_id
    ) fulfilled ON fulfilled.fulfiller_id = p.id
    LEFT JOIN (
        SELECT
            fulfiller_id,
            AVG(rating) as avg_rating,
            COUNT(*) as review_count
        FROM public.reviews
        GROUP BY fulfiller_id
    ) reviews ON reviews.fulfiller_id = p.id
    WHERE p.approved = true
    ORDER BY fulfilled_count DESC, average_rating DESC
    LIMIT p_limit;
END;
$function$
;

-- get_leaderboard(date, date): md5(prosrc) = 3147db83803aba7db4a49dbc5eb04e2d (invoker rights; Phase 0
-- step 3 call 18 makes it SECURITY DEFINER. CREATE OR REPLACE without a SECURITY clause sets it back to
-- SECURITY INVOKER, as live.)
CREATE OR REPLACE FUNCTION public.get_leaderboard(start_date date DEFAULT '1970-01-01'::date, end_date date DEFAULT CURRENT_DATE)
 RETURNS TABLE(user_id uuid, name text, avatar_url text, requests_fulfilled bigint, requests_made bigint)
 LANGUAGE plpgsql
 STABLE
 SET search_path TO ''
AS $function$
BEGIN
    RETURN QUERY
    SELECT
        p.id,
        p.name,
        p.avatar_url,
        (
            SELECT COUNT(*) FROM public.rides r
            WHERE r.claimed_by = p.id
            AND r.status = 'completed'
            AND DATE(r.updated_at) BETWEEN start_date AND end_date
        ) + (
            SELECT COUNT(*) FROM public.favors f
            WHERE f.claimed_by = p.id
            AND f.status = 'completed'
            AND DATE(f.updated_at) BETWEEN start_date AND end_date
        ) as requests_fulfilled,
        (
            SELECT COUNT(*) FROM public.rides r
            WHERE r.user_id = p.id
            AND DATE(r.created_at) BETWEEN start_date AND end_date
        ) + (
            SELECT COUNT(*) FROM public.favors f
            WHERE f.user_id = p.id
            AND DATE(f.created_at) BETWEEN start_date AND end_date
        ) as requests_made
    FROM public.profiles p
    WHERE p.approved = true
    ORDER BY requests_fulfilled DESC
    LIMIT 100;
END;
$function$
;

-- get_badge_counts: md5(prosrc) = 5002e87acb71fdf5249c8a1280fa5967
CREATE OR REPLACE FUNCTION public.get_badge_counts(p_include_details boolean DEFAULT false, p_user_id uuid DEFAULT NULL::uuid)
 RETURNS jsonb
 LANGUAGE plpgsql
 SECURITY DEFINER
 SET search_path TO ''
AS $function$
declare
    v_user_id uuid;
    v_messages_total integer;
    v_requests_total integer;
    v_community_total integer;
    v_bell_total integer;
    v_request_details jsonb := '[]'::jsonb;
    v_conversation_details jsonb := '[]'::jsonb;
begin
    v_user_id := coalesce(auth.uid(), p_user_id);

    if auth.uid() is not null and p_user_id is not null and auth.uid() != p_user_id then
        raise exception 'Cannot query badge counts for other users';
    end if;

    if v_user_id is null then
        raise exception 'User not authenticated';
    end if;

    -- Messages: total unread for user only in active conversations, excluding blocked senders
    select coalesce(count(*), 0)::int
    into v_messages_total
    from public.messages m
    join public.conversation_participants cp
        on cp.conversation_id = m.conversation_id
        and cp.user_id = v_user_id
    where cp.left_at is null
      and m.from_id <> v_user_id
      and not (coalesce(m.read_by, array[]::uuid[]) @> array[v_user_id]::uuid[])
      and not exists (
          select 1 from public.blocked_users b
          where b.blocker_id = v_user_id and b.blocked_id = m.from_id
      );

    update public.notifications n
    set read = true
    where n.user_id = v_user_id
      and n.read = false
      and n.type in ('message', 'added_to_conversation')
      and n.conversation_id is not null
      and not exists (
          select 1 from public.messages m
          join public.conversation_participants cp
              on cp.conversation_id = m.conversation_id
              and cp.user_id = v_user_id
          where m.conversation_id = n.conversation_id
            and cp.left_at is null
            and m.from_id <> v_user_id
            and not (coalesce(m.read_by, array[]::uuid[]) @> array[v_user_id]::uuid[])
      );

    with unread_requests as (
        select distinct
            case
                when ride_id is not null then 'ride:' || ride_id::text
                when favor_id is not null then 'favor:' || favor_id::text
                else null
            end as request_key
        from public.notifications
        where user_id = v_user_id
          and read = false
          and type in (
              'new_ride', 'ride_update', 'ride_claimed', 'ride_unclaimed',
              'new_favor', 'favor_update', 'favor_claimed', 'favor_unclaimed',
              'completion_reminder', 'qa_activity', 'qa_question', 'qa_answer'
          )
    )
    select coalesce(count(*), 0)::int
    into v_requests_total
    from unread_requests
    where request_key is not null;

    select coalesce(count(*), 0)::int
    into v_community_total
    from public.notifications
    where user_id = v_user_id
      and read = false
      and type in ('town_hall_post', 'town_hall_comment', 'town_hall_reaction');

    with bell_fresh as (
        select *
        from public.notifications
        where user_id = v_user_id
          and type not in ('message', 'added_to_conversation')
          and (read = false or created_at > now() - interval '24 hours')
    ),
    latest_announcement as (
        select id
        from bell_fresh
        where type in ('announcement', 'admin_announcement', 'broadcast')
        order by created_at desc
        limit 1
    ),
    bell_pruned as (
        select * from bell_fresh
        where type not in ('announcement', 'admin_announcement', 'broadcast')
        union all
        select bf.* from bell_fresh bf
        where bf.id in (select id from latest_announcement)
    ),
    bell_groups as (
        select
            case
                when type in ('announcement', 'admin_announcement', 'broadcast')
                    then 'announcement:' || id::text
                when type in ('town_hall_post', 'town_hall_comment', 'town_hall_reaction')
                    and town_hall_post_id is not null
                    then 'townHall:' || town_hall_post_id::text
                when type = 'pending_approval'
                    then 'admin:pendingApproval'
                when type in (
                    'new_ride', 'ride_update', 'ride_claimed', 'ride_unclaimed', 'ride_completed',
                    'new_favor', 'favor_update', 'favor_claimed', 'favor_unclaimed', 'favor_completed',
                    'completion_reminder', 'qa_activity', 'qa_question', 'qa_answer',
                    'review_request', 'review_reminder', 'review_received'
                ) and ride_id is not null
                    then 'ride:' || ride_id::text
                when type in (
                    'new_ride', 'ride_update', 'ride_claimed', 'ride_unclaimed', 'ride_completed',
                    'new_favor', 'favor_update', 'favor_claimed', 'favor_unclaimed', 'favor_completed',
                    'completion_reminder', 'qa_activity', 'qa_question', 'qa_answer',
                    'review_request', 'review_reminder', 'review_received'
                ) and favor_id is not null
                    then 'favor:' || favor_id::text
                else 'notification:' || id::text
            end as group_key,
            bool_or(read = false) as has_unread
        from bell_pruned
        group by group_key
    )
    select coalesce(count(*), 0)::int
    into v_bell_total
    from bell_groups
    where has_unread = true;

    if p_include_details then
        select coalesce(jsonb_agg(jsonb_build_object(
            'conversation_id', conversation_id,
            'unread_count', unread_count
        )), '[]'::jsonb)
        into v_conversation_details
        from (
            select m.conversation_id, count(*)::int as unread_count
            from public.messages m
            join public.conversation_participants cp
                on cp.conversation_id = m.conversation_id
                and cp.user_id = v_user_id
            where cp.left_at is null
              and m.from_id <> v_user_id
              and not (coalesce(m.read_by, array[]::uuid[]) @> array[v_user_id]::uuid[])
              and not exists (
                  select 1 from public.blocked_users b
                  where b.blocker_id = v_user_id and b.blocked_id = m.from_id
              )
            group by m.conversation_id
        ) as per_conversation;

        select coalesce(jsonb_agg(jsonb_build_object(
            'request_type', request_type,
            'request_id', request_id,
            'unread_count', unread_count
        )), '[]'::jsonb)
        into v_request_details
        from (
            select
                case when ride_id is not null then 'ride' else 'favor' end as request_type,
                coalesce(ride_id, favor_id) as request_id,
                count(*)::int as unread_count
            from public.notifications
            where user_id = v_user_id
              and read = false
              and type in (
                  'new_ride', 'ride_update', 'ride_claimed', 'ride_unclaimed',
                  'new_favor', 'favor_update', 'favor_claimed', 'favor_unclaimed',
                  'completion_reminder', 'qa_activity', 'qa_question', 'qa_answer'
              )
              and (ride_id is not null or favor_id is not null)
            group by request_type, request_id
        ) as per_request;
    end if;

    return jsonb_build_object(
        'user_id', v_user_id,
        'messages_total', coalesce(v_messages_total, 0),
        'requests_total', coalesce(v_requests_total, 0),
        'community_total', coalesce(v_community_total, 0),
        'bell_total', coalesce(v_bell_total, 0),
        'request_details', coalesce(v_request_details, '[]'::jsonb),
        'conversation_details', coalesce(v_conversation_details, '[]'::jsonb)
    );
end;
$function$
;

-- get_user_badges: md5(prosrc) = 374c12dd8163e3be4a1a235db6da48c9
CREATE OR REPLACE FUNCTION public.get_user_badges(target_user_id uuid)
 RETURNS jsonb
 LANGUAGE plpgsql
 SECURITY DEFINER
 SET search_path TO 'public'
AS $function$
DECLARE
    v_rides_fulfilled   BIGINT;
    v_favors_fulfilled  BIGINT;
    v_five_star_count   BIGINT;
    v_total_savings     NUMERIC;
    v_longest_streak    BIGINT;
    v_requests_made     BIGINT;
    v_badges            JSONB := '[]'::jsonb;
BEGIN
    -- 1. Road warrior: completed rides fulfilled (all-time)
    SELECT COUNT(*)
    INTO v_rides_fulfilled
    FROM rides
    WHERE claimed_by = target_user_id
      AND status = 'completed';

    -- 2. Good neighbor: completed favors fulfilled (all-time)
    SELECT COUNT(*)
    INTO v_favors_fulfilled
    FROM favors
    WHERE claimed_by = target_user_id
      AND status = 'completed';

    -- 3. Five star: 5-star reviews received (all-time)
    SELECT COUNT(*)
    INTO v_five_star_count
    FROM reviews
    WHERE fulfiller_id = target_user_id
      AND rating = 5;

    -- 4. Big saver: total estimated_cost savings from fulfilled rides (all-time)
    SELECT COALESCE(SUM(estimated_cost), 0)
    INTO v_total_savings
    FROM rides
    WHERE claimed_by = target_user_id
      AND status = 'completed';

    -- 5. Streak champion: longest consecutive-week streak (gaps-and-islands)
    --    Using DATE_TRUNC('week', updated_at)::DATE for correct year-boundary handling
    WITH fulfilled_weeks AS (
        SELECT DISTINCT DATE_TRUNC('week', updated_at)::DATE AS week_start
        FROM rides
        WHERE claimed_by = target_user_id
          AND status = 'completed'

        UNION

        SELECT DISTINCT DATE_TRUNC('week', updated_at)::DATE AS week_start
        FROM favors
        WHERE claimed_by = target_user_id
          AND status = 'completed'
    ),
    week_numbered AS (
        SELECT
            week_start,
            ROW_NUMBER() OVER (ORDER BY week_start) AS rn
        FROM fulfilled_weeks
    ),
    streaks AS (
        SELECT COUNT(*)::BIGINT AS streak_len
        FROM week_numbered
        GROUP BY (week_start - (rn * INTERVAL '7 days'))
    )
    SELECT COALESCE(MAX(streak_len), 0)
    INTO v_longest_streak
    FROM streaks;

    -- 6. Frequent Carbardian: total requests made (rides + favors, all-time)
    SELECT COUNT(*) INTO v_requests_made
    FROM (
        SELECT id FROM rides  WHERE user_id = target_user_id
        UNION ALL
        SELECT id FROM favors WHERE user_id = target_user_id
    ) sub;

    -- Assemble badge array
    SELECT COALESCE(jsonb_agg(badge), '[]'::jsonb)
    INTO v_badges
    FROM (
        SELECT 'road_warrior'    AS badge WHERE v_rides_fulfilled  >= 10
        UNION ALL
        SELECT 'good_neighbor'   AS badge WHERE v_favors_fulfilled >= 10
        UNION ALL
        SELECT 'streak_champion' AS badge WHERE v_longest_streak   >= 3
        UNION ALL
        SELECT 'five_star'       AS badge WHERE v_five_star_count  >= 10
        UNION ALL
        SELECT 'big_saver'       AS badge WHERE v_total_savings    >= 250
        UNION ALL
        SELECT 'frequent_carbardian' AS badge WHERE v_requests_made >= 10
    ) b;

    RETURN v_badges;
END;
$function$
;

-- get_user_stats: md5(prosrc) = aa3a44c11c10520809ca0f0c9c452806
CREATE OR REPLACE FUNCTION public.get_user_stats(p_user_id uuid)
 RETURNS TABLE(avg_rating numeric, review_count bigint, fulfilled_count bigint)
 LANGUAGE plpgsql
 SECURITY DEFINER
 SET search_path TO ''
AS $function$
BEGIN
    RETURN QUERY
    SELECT
        COALESCE(AVG(r.rating)::NUMERIC, 0) as avg_rating,
        COUNT(r.id)::BIGINT as review_count,
        COUNT(DISTINCT CASE WHEN r.fulfiller_id = p_user_id THEN r.ride_id END) +
        COUNT(DISTINCT CASE WHEN r.fulfiller_id = p_user_id THEN r.favor_id END) as fulfilled_count
    FROM public.reviews r
    WHERE r.fulfiller_id = p_user_id;
END;
$function$
;

-- is_user_approved: md5(prosrc) = 1c0d84cf3020fe2f830fb60b29aca4c9
CREATE OR REPLACE FUNCTION public.is_user_approved(user_id uuid)
 RETURNS boolean
 LANGUAGE sql
 STABLE SECURITY DEFINER
 SET search_path TO ''
AS $function$
    SELECT approved FROM public.profiles WHERE id = user_id;
$function$
;

-- create_signup_profile: md5(prosrc) = 2da330dc9e980d4819ead406a29185c8
CREATE OR REPLACE FUNCTION public.create_signup_profile(p_user_id uuid, p_email text, p_name text, p_invited_by uuid DEFAULT NULL::uuid, p_car text DEFAULT NULL::text, p_heard_about text DEFAULT NULL::text, p_join_reason text DEFAULT NULL::text)
 RETURNS jsonb
 LANGUAGE plpgsql
 SECURITY DEFINER
 SET search_path TO 'public'
AS $function$
BEGIN
    -- SECURITY FIX: Verify caller is creating their own profile
    IF auth.uid() IS NULL OR auth.uid() != p_user_id THEN
        RETURN jsonb_build_object(
            'success', false,
            'error', 'Unauthorized: can only create your own profile'
        );
    END IF;

    -- Validate input
    IF p_user_id IS NULL THEN
        RETURN jsonb_build_object(
            'success', false,
            'error', 'User ID is required'
        );
    END IF;

    IF p_email IS NULL OR p_email = '' THEN
        RETURN jsonb_build_object(
            'success', false,
            'error', 'Email is required'
        );
    END IF;

    IF p_name IS NULL OR p_name = '' THEN
        RETURN jsonb_build_object(
            'success', false,
            'error', 'Name is required'
        );
    END IF;

    -- Upsert the profile
    INSERT INTO profiles (
        id,
        email,
        name,
        invited_by,
        car,
        heard_about,
        join_reason,
        is_admin,
        approved,
        application_complete,
        application_submitted_at,
        created_at,
        updated_at
    ) VALUES (
        p_user_id,
        p_email,
        p_name,
        p_invited_by,
        p_car,
        p_heard_about,
        p_join_reason,
        false,
        false,
        false,
        NULL,
        NOW(),
        NOW()
    )
    ON CONFLICT (id) DO UPDATE SET
        email = EXCLUDED.email,
        name = EXCLUDED.name,
        invited_by = COALESCE(EXCLUDED.invited_by, profiles.invited_by),
        car = EXCLUDED.car,
        heard_about = COALESCE(EXCLUDED.heard_about, profiles.heard_about),
        join_reason = COALESCE(EXCLUDED.join_reason, profiles.join_reason),
        is_admin = false,
        approved = false,
        application_complete = false,
        application_submitted_at = NULL,
        updated_at = NOW();

    RETURN jsonb_build_object(
        'success', true,
        'user_id', p_user_id,
        'message', 'Profile created/updated successfully'
    );

EXCEPTION WHEN OTHERS THEN
    RETURN jsonb_build_object(
        'success', false,
        'error', SQLERRM
    );
END;
$function$
;

-- delete_user_account: md5(prosrc) = e427a88440bbf72c1af040b786d54d45
CREATE OR REPLACE FUNCTION public.delete_user_account(p_user_id uuid)
 RETURNS void
 LANGUAGE plpgsql
 SECURITY DEFINER
 SET search_path TO 'public'
AS $function$
declare
    v_record record;
begin
    if auth.uid() is null or auth.uid() != p_user_id then
        raise exception 'Not authorized to delete this account';
    end if;

    -- STEP 1: Claimer leaves — reopen their claimed requests
    for v_record in
        select id, user_id from rides where claimed_by = p_user_id and status = 'confirmed'
    loop
        perform create_notification(
            v_record.user_id, 'ride_unclaimed', 'Ride Reopened',
            'The neighbor who claimed your ride has left. Your ride is open for others to claim.',
            v_record.id, null, null, null, null, p_user_id
        );
    end loop;
    update rides set status = 'open', claimed_by = null where claimed_by = p_user_id and status = 'confirmed';

    for v_record in
        select id, user_id from favors where claimed_by = p_user_id and status = 'confirmed'
    loop
        perform create_notification(
            v_record.user_id, 'favor_unclaimed', 'Favor Reopened',
            'The neighbor who claimed your favor has left. Your favor is open for others to claim.',
            null, v_record.id, null, null, null, p_user_id
        );
    end loop;
    update favors set status = 'open', claimed_by = null where claimed_by = p_user_id and status = 'confirmed';

    -- STEP 2: Poster leaves — notify claimers before deleting
    for v_record in
        select id, claimed_by from rides where user_id = p_user_id and claimed_by is not null and status = 'confirmed'
    loop
        perform create_notification(
            v_record.claimed_by, 'ride_unclaimed', 'Ride Cancelled',
            'A ride you claimed has been cancelled because the poster left.',
            v_record.id, null, null, null, null, p_user_id
        );
    end loop;
    for v_record in
        select id, claimed_by from favors where user_id = p_user_id and claimed_by is not null and status = 'confirmed'
    loop
        perform create_notification(
            v_record.claimed_by, 'favor_unclaimed', 'Favor Cancelled',
            'A favor you claimed has been cancelled because the poster left.',
            null, v_record.id, null, null, null, p_user_id
        );
    end loop;

    -- STEP 3: Orphaned review notifications
    update notifications set read = true
    where type in ('review_request', 'review_reminder') and read = false
      and (
        ride_id in (select id from rides where claimed_by = p_user_id and status = 'completed')
        or favor_id in (select id from favors where claimed_by = p_user_id and status = 'completed')
      );
    update rides set claimed_by = null where claimed_by = p_user_id and status = 'completed';
    update favors set claimed_by = null where claimed_by = p_user_id and status = 'completed';

    -- STEP 4: Reminders and storage objects
    delete from completion_reminders where claimer_user_id = p_user_id;
    -- Storage rows: best effort inside a sub-block. storage.protect_delete() blocks direct
    -- deletes unless the flag below is set (transaction-local; the sub-block's rollback also
    -- restores it). A failure here is logged and skipped so it can never abort deletion.
    begin
        perform set_config('storage.allow_delete_query', 'true', true);
        delete from storage.objects o
        where (
                o.owner = p_user_id
             or o.owner_id = p_user_id::text
             or (o.bucket_id = 'avatars' and lower(o.name) = p_user_id::text || '.jpg')
             or (o.bucket_id in ('message-images','audio-messages','town-hall-images','review-images','group-images')
                 and lower(o.name) like p_user_id::text || '/%')
              )
          -- keep the avatar of a group that outlives this user (see STEP 6)
          and not (
                o.bucket_id = 'group-images'
            and exists (
                select 1 from conversations c
                where c.id::text = lower(split_part(o.name, '/', 1))
                  and (
                        c.created_by <> p_user_id
                     or (select count(*) from conversation_participants cp
                         where cp.conversation_id = c.id and cp.user_id <> p_user_id and cp.left_at is null) >= 2
                      )
            )
          );
        perform set_config('storage.allow_delete_query', 'false', true);
    exception when others then
        raise warning 'delete_user_account(%): storage cleanup skipped: % [%]', p_user_id, sqlerrm, sqlstate;
    end;

    -- STEP 5: NO ACTION foreign keys that would otherwise block the profile delete
    update conversation_participants set added_by = null where added_by = p_user_id;
    update profiles set banned_by = null where banned_by = p_user_id;

    -- STEP 6: Hand group conversations the user created to the longest-standing remaining
    -- member when at least two other active members remain; the user's own participant row
    -- and messages are removed below as before.
    update conversations c
    set created_by = (
        select cp.user_id from conversation_participants cp
        where cp.conversation_id = c.id and cp.user_id <> p_user_id and cp.left_at is null
        order by cp.joined_at nulls last, cp.id
        limit 1
    )
    where c.created_by = p_user_id
      and (
        select count(*) from conversation_participants cp
        where cp.conversation_id = c.id and cp.user_id <> p_user_id and cp.left_at is null
      ) >= 2;

    -- STEP 7: Rows that only concern this user (the remaining FKs cascade from profiles)
    delete from push_tokens where user_id = p_user_id;
    delete from notifications where user_id = p_user_id;
    delete from reviews where fulfiller_id = p_user_id or reviewer_id = p_user_id;
    delete from town_hall_posts where user_id = p_user_id;
    delete from invite_codes where created_by = p_user_id;
    delete from messages where from_id = p_user_id;
    delete from conversation_participants where user_id = p_user_id;
    delete from conversations where created_by = p_user_id;
    delete from rides where user_id = p_user_id;
    delete from favors where user_id = p_user_id;
    delete from request_qa where user_id = p_user_id;
    delete from profiles where id = p_user_id;
    delete from auth.users where id = p_user_id;
end $function$
;

-- admin_reject_pending_user: md5(prosrc) = 5d3f8ec66b57078946e446dbbf2c01ab
CREATE OR REPLACE FUNCTION public.admin_reject_pending_user(p_user_id uuid)
 RETURNS jsonb
 LANGUAGE plpgsql
 SECURITY DEFINER
 SET search_path TO 'public'
AS $function$
DECLARE
    v_caller_id UUID;
    v_target_approved BOOLEAN;
    v_rows_deleted INTEGER;
BEGIN
    v_caller_id := auth.uid();

    -- NULL-safe admin check (a caller with no profiles row used to pass).
    IF v_caller_id IS NULL OR NOT EXISTS (
        SELECT 1 FROM public.profiles WHERE id = v_caller_id AND is_admin = true
    ) THEN
        RETURN jsonb_build_object('success', false, 'error', 'Not authorized - admin access required');
    END IF;

    SELECT approved INTO v_target_approved FROM public.profiles WHERE id = p_user_id;
    IF v_target_approved = true THEN
        RETURN jsonb_build_object('success', false, 'error', 'Cannot reject an already approved user');
    END IF;

    DELETE FROM public.profiles WHERE id = p_user_id AND approved = false;
    GET DIAGNOSTICS v_rows_deleted = ROW_COUNT;

    DELETE FROM auth.users WHERE id = p_user_id;

    RETURN jsonb_build_object(
        'success', true,
        'deleted_user_id', p_user_id,
        'rows_deleted', v_rows_deleted
    );
END $function$
;

-- =========================================================================================
-- 2. Policies (roles and predicates as live on 2026-10-17; spec §3.4, 28 altered in Phase 0)
-- =========================================================================================

-- rides (3 of 8) -------------------------------------------------------------------------
-- SELECT, roles {authenticated}
alter policy "Authenticated users can view visible or own hidden rides" on public.rides
  to authenticated
  using (((user_id = ( SELECT auth.uid() AS uid)) OR ((hidden_at IS NULL) AND ( SELECT is_active_user(( SELECT auth.uid() AS uid)) AS is_active_user))));
-- INSERT, roles {public}
alter policy "rides_insert_active_user" on public.rides
  to public
  with check (((( SELECT auth.uid() AS uid) = user_id) AND is_active_user(( SELECT auth.uid() AS uid))));
-- UPDATE, roles {public}
alter policy "Authenticated users can claim open rides" on public.rides
  to public
  using (((claimed_by IS NULL) AND (status = 'open'::ride_status) AND (user_id <> ( SELECT auth.uid() AS uid))))
  with check (((claimed_by = ( SELECT auth.uid() AS uid)) AND (status = 'confirmed'::ride_status)));

-- favors (3 of 8) ------------------------------------------------------------------------
-- SELECT, roles {authenticated}
alter policy "Authenticated users can view visible or own hidden favors" on public.favors
  to authenticated
  using (((user_id = ( SELECT auth.uid() AS uid)) OR ((hidden_at IS NULL) AND ( SELECT is_active_user(( SELECT auth.uid() AS uid)) AS is_active_user))));
-- INSERT, roles {public}
alter policy "favors_insert_active_user" on public.favors
  to public
  with check (((( SELECT auth.uid() AS uid) = user_id) AND is_active_user(( SELECT auth.uid() AS uid))));
-- UPDATE, roles {public}
alter policy "Authenticated users can claim open favors" on public.favors
  to public
  using (((claimed_by IS NULL) AND (status = 'open'::favor_status) AND (user_id <> ( SELECT auth.uid() AS uid))))
  with check (((claimed_by = ( SELECT auth.uid() AS uid)) AND (status = 'confirmed'::favor_status)));

-- town_hall_posts (3 of 4) ---------------------------------------------------------------
-- SELECT, roles {authenticated} (the stored name is truncated to 63 bytes)
alter policy "Authenticated users can view visible or own hidden town hall po" on public.town_hall_posts
  to authenticated
  using ((((hidden_at IS NULL) AND COALESCE(( SELECT p.approved
   FROM profiles p
  WHERE (p.id = ( SELECT auth.uid() AS uid))), false)) OR (user_id = ( SELECT auth.uid() AS uid))));
-- SELECT, roles {anon}
alter policy "Guests can view visible town hall posts" on public.town_hall_posts
  to anon
  using ((hidden_at IS NULL));
-- INSERT, roles {public}
alter policy "town_hall_posts_insert_active_user" on public.town_hall_posts
  to public
  with check (((( SELECT auth.uid() AS uid) = user_id) AND is_active_user(( SELECT auth.uid() AS uid))));

-- town_hall_comments (3 of 5) ------------------------------------------------------------
-- SELECT, roles {authenticated} (the stored name is truncated to 63 bytes)
alter policy "Authenticated users can view visible or own hidden town hall co" on public.town_hall_comments
  to authenticated
  using (((hidden_at IS NULL) OR (user_id = ( SELECT auth.uid() AS uid))));
-- SELECT, roles {anon}
alter policy "Guests can view visible town hall comments" on public.town_hall_comments
  to anon
  using ((hidden_at IS NULL));
-- INSERT, roles {public}
alter policy "town_hall_comments_insert_active_user" on public.town_hall_comments
  to public
  with check (((( SELECT auth.uid() AS uid) = user_id) AND is_active_user(( SELECT auth.uid() AS uid))));

-- town_hall_votes (2 of 4) ---------------------------------------------------------------
-- SELECT, roles {authenticated}
alter policy "Users can view all votes" on public.town_hall_votes
  to authenticated
  using (true);
-- INSERT, roles {authenticated}
alter policy "Users can create votes" on public.town_hall_votes
  to authenticated
  with check ((( SELECT auth.uid() AS uid) = user_id));

-- town_hall_post_interactions (1 of 3) ---------------------------------------------------
-- SELECT, roles {authenticated}
alter policy "interactions_select_approved" on public.town_hall_post_interactions
  to authenticated
  using ((EXISTS ( SELECT 1
   FROM profiles
  WHERE ((profiles.id = ( SELECT auth.uid() AS uid)) AND (profiles.approved = true)))));

-- request_qa (3 of 4) --------------------------------------------------------------------
-- SELECT, roles {public}
alter policy "Approved users can view Q&A" on public.request_qa
  to public
  using ((( SELECT profiles.approved
   FROM profiles
  WHERE (profiles.id = ( SELECT auth.uid() AS uid))) = true));
-- SELECT, roles {anon}
alter policy "request_qa_select_anon_guest" on public.request_qa
  to anon
  using (true);
-- INSERT, roles {public}
alter policy "Approved users can create Q&A" on public.request_qa
  to public
  with check (((( SELECT profiles.approved
   FROM profiles
  WHERE (profiles.id = ( SELECT auth.uid() AS uid))) = true) AND (( SELECT auth.uid() AS uid) = user_id)));

-- ride_participants (2 of 3) -------------------------------------------------------------
-- SELECT, roles {public}
alter policy "ride_participants_select" on public.ride_participants
  to public
  using ((EXISTS ( SELECT 1
   FROM profiles
  WHERE ((profiles.id = ( SELECT auth.uid() AS uid)) AND (profiles.approved = true)))));
-- INSERT, roles {public}
alter policy "ride_participants_insert" on public.ride_participants
  to public
  with check (((EXISTS ( SELECT 1
   FROM rides
  WHERE ((rides.id = ride_participants.ride_id) AND (rides.user_id = ( SELECT auth.uid() AS uid))))) AND (added_by = ( SELECT auth.uid() AS uid))));

-- favor_participants (2 of 3) ------------------------------------------------------------
-- SELECT, roles {public}
alter policy "favor_participants_select" on public.favor_participants
  to public
  using ((EXISTS ( SELECT 1
   FROM profiles
  WHERE ((profiles.id = ( SELECT auth.uid() AS uid)) AND (profiles.approved = true)))));
-- INSERT, roles {public}
alter policy "favor_participants_insert" on public.favor_participants
  to public
  with check (((EXISTS ( SELECT 1
   FROM favors
  WHERE ((favors.id = favor_participants.favor_id) AND (favors.user_id = ( SELECT auth.uid() AS uid))))) AND (added_by = ( SELECT auth.uid() AS uid))));

-- reviews (2 of 3) -----------------------------------------------------------------------
-- SELECT, roles {public}
alter policy "Approved users can view reviews" on public.reviews
  to public
  using ((( SELECT profiles.approved
   FROM profiles
  WHERE (profiles.id = ( SELECT auth.uid() AS uid))) = true));
-- SELECT, roles {anon}
alter policy "reviews_select_anon_guest" on public.reviews
  to anon
  using (true);

-- conversation_participants (1 of 4) -----------------------------------------------------
-- INSERT, roles {authenticated}
alter policy "authenticated_users_can_add_participants" on public.conversation_participants
  to authenticated
  with check (is_conversation_creator(conversation_id, ( SELECT auth.uid() AS uid)));

-- geocoding_cache (3 of 3) ---------------------------------------------------------------
-- SELECT, roles {authenticated}
alter policy "geocoding_cache_select_authenticated" on public.geocoding_cache
  to authenticated
  using (true);
-- INSERT, roles {authenticated}
alter policy "geocoding_cache_insert_authenticated" on public.geocoding_cache
  to authenticated
  with check (true);
-- UPDATE, roles {authenticated}
alter policy "geocoding_cache_update_authenticated" on public.geocoding_cache
  to authenticated
  using (true)
  with check (true);

-- Phase 3 (not altered in Phase 0; recorded so a Phase 3 rollback has it) ------------------
-- town_hall_posts DELETE, roles {public}
alter policy "Users or admins can delete posts" on public.town_hall_posts
  to public
  using (((( SELECT auth.uid() AS uid) = user_id) OR (( SELECT profiles.is_admin
   FROM profiles
  WHERE (profiles.id = ( SELECT auth.uid() AS uid))) = true)));

-- =========================================================================================
-- 3. Views (as live on 2026-10-17; reloptions security_barrier=true, security_invoker=false)
--    The md5 is of pg_get_viewdef(oid, true) as printed live (the table name there is
--    unqualified; it is schema-qualified below, which stores the same view).
-- =========================================================================================

-- guest_rides: md5(pg_get_viewdef) = 0ddd748d07b9f87231c717d32d3536cf
-- live ACL: postgres=arwdDxtm, service_role=arwdDxtm, anon=r
drop view if exists public.guest_rides;
create or replace view public.guest_rides
with (security_barrier = true, security_invoker = false) as
 SELECT id,
    user_id,
    type,
    date,
    "time",
    ''::text AS pickup,
    ''::text AS destination,
    seats,
    notes,
    gift,
    status,
    claimed_by,
    reviewed,
    review_skipped,
    review_skipped_at,
    created_at,
    updated_at,
    estimated_cost,
    flight_normalized,
    timezone,
    hidden_at,
    hidden_by,
    hidden_reason
   FROM public.rides r
  WHERE hidden_at IS NULL;

-- guest_favors: md5(pg_get_viewdef) = 92a042a84f488c642725e9571fe5646f
-- live ACL: postgres=arwdDxtm, service_role=arwdDxtm, anon=r
drop view if exists public.guest_favors;
create or replace view public.guest_favors
with (security_barrier = true, security_invoker = false) as
 SELECT id,
    user_id,
    title,
    description,
    ''::text AS location,
    duration,
    requirements,
    date,
    "time",
    gift,
    status,
    claimed_by,
    reviewed,
    review_skipped,
    review_skipped_at,
    created_at,
    updated_at,
    timezone,
    hidden_at,
    hidden_by,
    hidden_reason
   FROM public.favors f
  WHERE hidden_at IS NULL;

revoke all on public.guest_rides from public, anon, authenticated;
revoke all on public.guest_favors from public, anon, authenticated;
grant select on public.guest_rides to anon;
grant select on public.guest_favors to anon;

-- public_profiles: md5(pg_get_viewdef) = 49f65eb0e0dc5672b94386b65e2c39cb
-- live ACL: postgres=arwdDxtm, anon=rm, authenticated=rm, service_role=arwdDxtm (kept by
-- CREATE OR REPLACE; Phase 0 changes only its predicate, not its columns)
create or replace view public.public_profiles
with (security_barrier = true, security_invoker = false) as
 SELECT id,
    name,
    avatar_url,
    car,
    approved,
    created_at,
    updated_at
   FROM public.profiles;

-- =========================================================================================
-- 4. Undo the one real change of step 0 (EXECUTE as it was before the revoke)
-- =========================================================================================

grant execute on function public.get_or_create_conversation(uuid[]) to authenticated;
grant execute on function public.get_or_create_request_conversation(uuid, uuid, uuid) to authenticated;
