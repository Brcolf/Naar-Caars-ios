-- 20261017_0003_communities_fanout.sql
-- NOT APPLIED. Phase 0, step 3 of the multi-community rollout
-- (Docs/superpowers/specs/2026-10-07-multi-community-design.md section 3.5 and section 4, as
-- amended by Docs/superpowers/specs/2026-10-17-multi-community-decisions.md).
--
-- Requires steps 1 and 2 to be live: the communities / community_members tables, the
-- community_id columns on rides, favors, town_hall_posts, xp_events, notifications and
-- reports, reports.reported_community_id, the caller-bound helpers (my_community_ids,
-- my_admin_community_ids, is_community_admin, is_platform_admin, my_visible_profile_ids,
-- default_community_id), the fill triggers and derive_notification_community.
--
-- What it does. Every function below except the four new ones is edited in place with its
-- signature unchanged, starting from the LIVE body (pg_get_functiondef, 2026-10-17); the
-- md5(prosrc) of that live body is recorded above each one and is the rollback reference
-- together with the step 0 snapshot. Nothing else in a body was changed except where noted.
--   * notify_new_ride / notify_new_favor / notify_town_hall_post: the recipient loop is the
--     request's (or post's) community: active members, not banned, not the poster, in a
--     non-archived community, not muted (notifications_muted false and muted_until null or
--     past). community_id is added to the push data (reaches userInfo through the ...data
--     spread in send-notification; installed builds ignore it). The Town Hall batch key now
--     carries the community so a revived batcher cannot merge two communities.
--   * notify_user_approved: sends nothing unless the user holds an active membership in a
--     live community, nothing when naars.suppress_approval_notice = '1' (create_community and
--     instant invite joins), and names the community (section 2.4 text). The bell row gets the
--     community_id with a direct UPDATE on the returned id (it carries no entity to derive from).
--   * guard_request_client_update: community_id joins the immutable set (INV-R1).
--   * handle_new_review: the review post inherits the reviewed request's community.
--   * record_xp_on_request_created / _on_completion / _on_review: write xp_events.community_id
--     explicitly (INV-X1); fill_xp_event_community (step 1) stays as the fallback.
--   * handle_new_report: a branch for community reports (preview = the community's name,
--     target_type 'community', reported_community_id in the push data). Recipients stay the
--     platform admins, exactly as today; community admins are added in Phase 3.
--   * send_community_broadcast (new) and send_broadcast_notifications (now a wrapper).
--   * get_community_leaderboard / get_community_spotlights (new) with the per-RPC predicates of
--     section 10 COMPLETENESS-5; get_xp_leaderboard / get_leaderboard_spotlights become thin
--     wrappers resolving the caller's primary community when it is a live active membership,
--     else the default community (anon: the default community).
--   * the two get_leaderboard overloads: see the deviation note below.
--   * get_profile_stats (new): per-person rating, review count and fulfilled count over every
--     community, under the public_profiles visibility rule.
--   * get_user_badges / get_user_stats / is_user_approved: bodies unchanged, one visibility gate
--     (the target is the caller, is in my_visible_profile_ids(), or, for anon, is an active
--     member of a public live community); otherwise '[]' / no row / false.
--   * create_signup_profile: the ON CONFLICT branch no longer assigns approved or
--     application_complete (both are mirrored from memberships now, INV-M5).
--   * get_badge_counts: pending_members_total (always) and community_details (with
--     p_include_details) in one call; then the additive total key (D28) as a SEPARATE
--     CREATE OR REPLACE of the full body, so it can be reverted alone by re-applying call 24.
--
-- NOT in this file: the should_notify_user edit (the pending_approval / content_reported arms
-- and the account_restricted arm). Section 4 step 1h puts it in step 1, ahead of the
-- notify_pending_membership producer, and it stays there.
--
-- Deviations from the spec's wording, each deliberate:
--   1. get_community_leaderboard's badges column stays per person (spec 3.5 "the badges column
--      stays per person (D5)", rule 8). In the live body the badge inputs (fulfilled ride and
--      favor counts, five-star count, requests made, longest streak, savings) come from the same
--      xp_events / rides scans that feed the ranking, so they are computed twice: scoped to the
--      community for xp, streak_weeks, requests_fulfilled and requests_made, and unscoped
--      (still within the date window, as today) for the badges. The savings subquery feeds only
--      the big_saver badge, so it is left unscoped rather than given the r.community_id
--      predicate COMPLETENESS-5 lists; the streak bonus in the live body is read from
--      xp_events, so its scoping is the xe.community_id predicate.
--   2. get_community_spotlights also scopes its review_xp CTE (it reads reviews, not rides or
--      favors) through the reviewed request's community; otherwise rising_star would count
--      review XP earned in other communities.
--   3. The two get_leaderboard overloads (no caller in the iOS app; neither shape can be
--      expressed through get_community_leaderboard's columns) keep their bodies and are scoped
--      in place with the same community resolution: members of that community instead of
--      approved, and the request-counting subqueries limited to it. get_leaderboard(date, date)
--      becomes SECURITY DEFINER: as an invoker function its new community_members join would
--      see only the caller's own row under step 2's policy. Average rating and review count in
--      get_leaderboard(text, integer) stay per person (rule 8).
--   4. send_broadcast_notifications keeps its 4-argument signature; p_type is accepted and
--      ignored (rows are always type 'broadcast', the default the installed build relies on;
--      a free-form type would be refused by should_notify_user inside create_notification).
--   5. search_path: functions rewritten here are pinned to '' with every name qualified (the
--      repo convention). create_signup_profile and get_user_badges keep their live
--      search_path ('public') because only one branch / one gate changes in them.
--
-- Apply through the Supabase MCP, one CREATE OR REPLACE FUNCTION per call, in this order (the
-- new inner functions precede their wrappers; every single call leaves the installed build's
-- inserts, completions, reviews, approvals and broadcasts working):
--   1 notify_new_ride            9 record_xp_on_review          17 get_leaderboard(text, int)
--   2 notify_new_favor          10 handle_new_report            18 get_leaderboard(date, date)
--   3 notify_town_hall_post     11 send_community_broadcast     19 get_profile_stats
--   4 notify_user_approved      12 send_broadcast_notifications 20 get_user_badges
--   5 guard_request_client_upd. 13 get_community_leaderboard    21 get_user_stats
--   6 handle_new_review         14 get_community_spotlights     22 is_user_approved
--   7 record_xp_on_req_created  15 get_xp_leaderboard           23 create_signup_profile
--   8 record_xp_on_completion   16 get_leaderboard_spotlights   24 get_badge_counts
--                                                               25 get_badge_counts + total (D28)
--
-- Verification (to be filled in when applied): dry-run the whole file inside one
-- begin; ... rollback; with the short probe (insert a ride and a favor without community_id,
-- claim and complete as a second member, 5-star review, read the ride's community and three
-- xp_events rows with a community, delete a probe member / probe admin / the default owner),
-- then after each call the short probe again. Specific checks: notify_new_ride queues exactly
-- one push per unmuted member of the request's community and none for a muted member or for a
-- member of another community; get_xp_leaderboard for a Seattle member returns the same rows
-- and xp as before this file; get_community_leaderboard for a private community the caller is
-- not in raises 42501; get_user_badges / get_user_stats / get_profile_stats for a user in no
-- shared community return '[]' / no row / '{}'; create_signup_profile re-run by a member leaves
-- approved true; a legacy approve sends one "Welcome to Naar's Cars Seattle!"; a creator's own
-- create_community sends none; get_badge_counts returns every existing key unchanged, and
-- pending_members_total equals the installed build's pending count for a platform admin.
--
-- What old clients see: the same rows, pushes and screens, except for the accepted changes below.
-- The approval welcome now reads "Welcome to Naar's Cars Seattle!" / "You've been approved. Tap to
-- enter the app." After call 25 the number APNs puts on the app icon is requests + messages +
-- community (D28; check on a device that it equals the in-app number after a push). community_id
-- and the two new get_badge_counts keys appear in responses and are ignored.
--
-- Accepted Phase 0 behaviour changes with one community (so "steps 0-3 change nothing for one
-- community" does not hold for broadcasts; list these in the Phase 0 "What old clients see" summary
-- and the PR's Impact Summary). A broadcast from the installed admin build, through the
-- send_broadcast_notifications wrapper (call 12):
--   * goes to the default community's active, unbanned, unmuted members and no longer gives the
--     sender a bell row;
--   * ignores p_type (rows are always 'broadcast', deviation 4);
--   * is refused as the 4th within 24 hours in the community (D14), for platform admins too;
--   * creates its bell rows through create_notification, so should_notify_user gates each one,
--     instead of the live body's direct inserts.
-- The cap applies to platform admins as decided in D14. Exempting platform admins until Phase 3
-- would make this step behaviour-neutral for the installed admin build; that is the owner's call
-- and is not done here.
--
-- Rollback: re-apply the live bodies recorded in the step 0 snapshot (md5 below), in reverse
-- order; drop the four new functions after their wrappers are restored. The snapshot holds every
-- body replaced here, both get_leaderboard overloads included; its get_leaderboard(date, date)
-- body has no SECURITY clause, so re-applying it also undoes call 18's SECURITY DEFINER. Call 25 alone is
-- reverted by re-applying call 24.


-- ---------------------------------------------------------------------------------------------
-- Call 1. notify_new_ride   live md5(prosrc) ee08d0b5f0448949b8bce8e5a99af862
-- ---------------------------------------------------------------------------------------------
create or replace function public.notify_new_ride()
returns trigger
language plpgsql
security definer
set search_path = ''
as $function$
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
        SELECT m.user_id AS id
        FROM public.community_members m
        JOIN public.profiles p ON p.id = m.user_id
        JOIN public.communities c ON c.id = m.community_id AND c.archived_at IS NULL
        WHERE m.community_id = NEW.community_id
          AND m.status = 'active'
          AND NOT p.is_banned
          AND m.user_id <> NEW.user_id
          AND NOT m.notifications_muted
          AND (m.muted_until IS NULL OR m.muted_until < now())
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
                jsonb_build_object('ride_id', NEW.id::text, 'community_id', NEW.community_id::text),
                NULL, v_notification_id
            );
        END IF;
    END LOOP;

    RETURN NEW;
END;
$function$;

revoke all on function public.notify_new_ride() from public, anon, authenticated;


-- ---------------------------------------------------------------------------------------------
-- Call 2. notify_new_favor   live md5(prosrc) 6e07ec5265d469b932bee6357c0ded30
-- ---------------------------------------------------------------------------------------------
create or replace function public.notify_new_favor()
returns trigger
language plpgsql
security definer
set search_path = ''
as $function$
DECLARE
    v_poster_name TEXT;
    v_user_record RECORD;
    v_notification_id UUID;
BEGIN
    SELECT name INTO v_poster_name FROM public.profiles WHERE id = NEW.user_id;
    v_poster_name := COALESCE(v_poster_name, 'Someone');

    FOR v_user_record IN
        SELECT m.user_id AS id
        FROM public.community_members m
        JOIN public.profiles p ON p.id = m.user_id
        JOIN public.communities c ON c.id = m.community_id AND c.archived_at IS NULL
        WHERE m.community_id = NEW.community_id
          AND m.status = 'active'
          AND NOT p.is_banned
          AND m.user_id <> NEW.user_id
          AND NOT m.notifications_muted
          AND (m.muted_until IS NULL OR m.muted_until < now())
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
                jsonb_build_object('favor_id', NEW.id::text, 'community_id', NEW.community_id::text),
                NULL, v_notification_id
            );
        END IF;
    END LOOP;

    RETURN NEW;
END;
$function$;

revoke all on function public.notify_new_favor() from public, anon, authenticated;


-- ---------------------------------------------------------------------------------------------
-- Call 3. notify_town_hall_post   live md5(prosrc) ccc627969694f1177df307b8edc033e1
-- ---------------------------------------------------------------------------------------------
create or replace function public.notify_town_hall_post()
returns trigger
language plpgsql
security definer
set search_path = ''
as $function$
DECLARE
    v_poster_name TEXT;
    v_user_record RECORD;
    v_batch_key TEXT;
    v_notification_id UUID;
BEGIN
    SELECT name INTO v_poster_name FROM public.profiles WHERE id = NEW.user_id;
    v_poster_name := COALESCE(v_poster_name, 'Someone');

    v_batch_key := 'town_hall_' || NEW.community_id::text || '_' || to_char(date_trunc('minute', NOW()) -
        (EXTRACT(MINUTE FROM NOW())::int % 5) * INTERVAL '1 minute', 'YYYY-MM-DD-HH24-MI');

    FOR v_user_record IN
        SELECT m.user_id AS id
        FROM public.community_members m
        JOIN public.profiles p ON p.id = m.user_id
        JOIN public.communities c ON c.id = m.community_id AND c.archived_at IS NULL
        WHERE m.community_id = NEW.community_id
          AND m.status = 'active'
          AND NOT p.is_banned
          AND m.user_id <> NEW.user_id
          AND p.notify_town_hall = true
          AND NOT m.notifications_muted
          AND (m.muted_until IS NULL OR m.muted_until < now())
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
                jsonb_build_object('town_hall_post_id', NEW.id::text, 'community_id', NEW.community_id::text),
                v_batch_key, v_notification_id
            );
        END IF;
    END LOOP;

    RETURN NEW;
END;
$function$;

revoke all on function public.notify_town_hall_post() from public, anon, authenticated;


-- ---------------------------------------------------------------------------------------------
-- Call 4. notify_user_approved   live md5(prosrc) f7ba95aafa8b371b203e52e2dcf45f9f
-- Still the single producer of the first-approval user_approved. It must run after
-- a_sync_legacy_approval_to_membership (step 1, alphabetical trigger order); the membership
-- guard keeps a declined legacy approve (bridge case 3) silent even if that order ever changes.
-- ---------------------------------------------------------------------------------------------
create or replace function public.notify_user_approved()
returns trigger
language plpgsql
security definer
set search_path = ''
as $function$
DECLARE
    v_notification_id UUID;
    v_community_id UUID;
    v_community_name TEXT;
    v_title TEXT;
    v_body TEXT := 'You''ve been approved. Tap to enter the app.';
BEGIN
    IF OLD.approved = false AND NEW.approved = true THEN
        -- create_community and the instant branch of redeem_community_invite set this for their
        -- own transaction: the person is already in the app and must not be told they were approved.
        IF current_setting('naars.suppress_approval_notice', true) = '1' THEN
            RETURN NEW;
        END IF;

        SELECT c.id, c.name
          INTO v_community_id, v_community_name
          FROM public.community_members m
          JOIN public.communities c ON c.id = m.community_id AND c.archived_at IS NULL
         WHERE m.user_id = NEW.id
           AND m.status = 'active'
         ORDER BY m.activated_at DESC NULLS LAST, m.community_id
         LIMIT 1;

        IF v_community_id IS NULL THEN
            RETURN NEW;
        END IF;

        v_title := 'Welcome to ' || COALESCE(v_community_name, 'Naar''s Cars') || '!';

        v_notification_id := public.create_notification(
            NEW.id,
            'user_approved'::TEXT,
            v_title,
            v_body,
            NULL::UUID,
            NULL::UUID,
            NULL::UUID,
            NULL::UUID,
            NULL::UUID,
            NULL::UUID
        );

        IF v_notification_id IS NOT NULL THEN
            UPDATE public.notifications
               SET community_id = v_community_id
             WHERE id = v_notification_id;

            PERFORM public.queue_push_notification(
                NEW.id,
                'user_approved'::TEXT,
                v_title,
                v_body,
                jsonb_build_object('action', 'enter_app', 'community_id', v_community_id::text),
                NULL::TEXT,
                v_notification_id
            );
        END IF;
    END IF;

    RETURN NEW;
END;
$function$;

revoke all on function public.notify_user_approved() from public, anon, authenticated;


-- ---------------------------------------------------------------------------------------------
-- Call 5. guard_request_client_update   live md5(prosrc) d5ba2e3d5bebc33d21dd9835b96e46b0
-- (identical to 20261006_0001). One line added: community_id is immutable for clients.
-- ---------------------------------------------------------------------------------------------
create or replace function public.guard_request_client_update()
returns trigger
language plpgsql
set search_path = ''
as $g$
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
     or new.community_id is distinct from old.community_id
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
$g$;

revoke all on function public.guard_request_client_update() from public, anon, authenticated;


-- ---------------------------------------------------------------------------------------------
-- Call 6. handle_new_review   live md5(prosrc) 7d2ea7b2860f79f509ba288d1885bb50
-- The review post carries the reviewed request's community (fill_request_community would
-- otherwise use the reviewer's primary, which can be another community).
-- ---------------------------------------------------------------------------------------------
create or replace function public.handle_new_review()
returns trigger
language plpgsql
security definer
set search_path = ''
as $function$
BEGIN
    INSERT INTO public.town_hall_posts (user_id, title, content, review_id, type, image_url, community_id)
    VALUES (
        NEW.reviewer_id,
        'New Review',
        format('%s %s', repeat('⭐', NEW.rating), COALESCE(NEW.comment, '')),
        NEW.id,
        'review',
        NEW.image_url,
        COALESCE(
            (SELECT r.community_id FROM public.rides r WHERE r.id = NEW.ride_id),
            (SELECT f.community_id FROM public.favors f WHERE f.id = NEW.favor_id)
        )
    );

    RETURN NEW;
END;
$function$;

revoke all on function public.handle_new_review() from public, anon, authenticated;


-- ---------------------------------------------------------------------------------------------
-- Call 7. record_xp_on_request_created   live md5(prosrc) 619620a04d2a1a541d6d5a5b59be88f9
-- AFTER INSERT, so NEW.community_id has already been filled by fill_request_community.
-- The first_ride / first_favor milestone stays per person (any community).
-- ---------------------------------------------------------------------------------------------
create or replace function public.record_xp_on_request_created()
returns trigger
language plpgsql
security definer
set search_path = ''
as $function$
DECLARE
    v_is_first BOOLEAN;
BEGIN
    IF TG_TABLE_NAME = 'rides' THEN
        INSERT INTO public.xp_events (user_id, amount, source_type, source_id, description, created_at, community_id)
        VALUES (
            NEW.user_id, 5, 'ride_requested', NEW.id,
            'Requested: ' || COALESCE(NEW.pickup || ' → ' || NEW.destination, 'Ride'),
            NEW.created_at, NEW.community_id
        )
        ON CONFLICT (source_type, source_id) DO NOTHING;

        SELECT NOT EXISTS (
            SELECT 1 FROM public.rides WHERE user_id = NEW.user_id AND id != NEW.id
        ) INTO v_is_first;

        IF v_is_first THEN
            INSERT INTO public.xp_events (user_id, amount, source_type, source_id, description, created_at, community_id)
            VALUES (NEW.user_id, 10, 'first_ride', NEW.id, 'First ride milestone', NEW.created_at, NEW.community_id)
            ON CONFLICT (source_type, source_id) DO NOTHING;
        END IF;
    ELSE
        INSERT INTO public.xp_events (user_id, amount, source_type, source_id, description, created_at, community_id)
        VALUES (
            NEW.user_id, 5, 'favor_requested', NEW.id,
            'Requested: ' || COALESCE(NEW.title, 'Favor'),
            NEW.created_at, NEW.community_id
        )
        ON CONFLICT (source_type, source_id) DO NOTHING;

        SELECT NOT EXISTS (
            SELECT 1 FROM public.favors WHERE user_id = NEW.user_id AND id != NEW.id
        ) INTO v_is_first;

        IF v_is_first THEN
            INSERT INTO public.xp_events (user_id, amount, source_type, source_id, description, created_at, community_id)
            VALUES (NEW.user_id, 10, 'first_favor', NEW.id, 'First favor milestone', NEW.created_at, NEW.community_id)
            ON CONFLICT (source_type, source_id) DO NOTHING;
        END IF;
    END IF;
    RETURN NEW;
END;
$function$;

revoke all on function public.record_xp_on_request_created() from public, anon, authenticated;


-- ---------------------------------------------------------------------------------------------
-- Call 8. record_xp_on_completion   live md5(prosrc) b0a3a0261e08546a6adbb512a347c5fc
-- ---------------------------------------------------------------------------------------------
create or replace function public.record_xp_on_completion()
returns trigger
language plpgsql
security definer
set search_path = ''
as $function$
BEGIN
    IF NEW.status = 'completed' AND OLD.status IS DISTINCT FROM 'completed' AND NEW.claimed_by IS NOT NULL THEN
        IF TG_TABLE_NAME = 'rides' THEN
            INSERT INTO public.xp_events (user_id, amount, source_type, source_id, description, created_at, community_id)
            VALUES (
                NEW.claimed_by,
                (5 + COALESCE(FLOOR(NEW.estimated_cost / 5), 0))::INTEGER,
                'ride_fulfilled',
                NEW.id,
                COALESCE(NEW.pickup || ' → ' || NEW.destination, 'Ride'),
                COALESCE(NEW.updated_at, now()),
                NEW.community_id
            )
            ON CONFLICT (source_type, source_id) DO NOTHING;
        ELSE
            INSERT INTO public.xp_events (user_id, amount, source_type, source_id, description, created_at, community_id)
            VALUES (
                NEW.claimed_by,
                10,
                'favor_fulfilled',
                NEW.id,
                COALESCE(NEW.title, 'Favor'),
                COALESCE(NEW.updated_at, now()),
                NEW.community_id
            )
            ON CONFLICT (source_type, source_id) DO NOTHING;
        END IF;
    END IF;
    RETURN NEW;
END;
$function$;

revoke all on function public.record_xp_on_completion() from public, anon, authenticated;


-- ---------------------------------------------------------------------------------------------
-- Call 9. record_xp_on_review   live md5(prosrc) ad5d8e55d7953e0c6353c9ee3ed275a8
-- A NULL here (request gone) is filled by fill_xp_event_community; it never raises.
-- ---------------------------------------------------------------------------------------------
create or replace function public.record_xp_on_review()
returns trigger
language plpgsql
security definer
set search_path = ''
as $function$
BEGIN
    IF NEW.rating >= 4 THEN
        INSERT INTO public.xp_events (user_id, amount, source_type, source_id, description, created_at, community_id)
        VALUES (
            NEW.fulfiller_id,
            CASE WHEN NEW.rating = 5 THEN 5 ELSE 2 END,
            'review_received',
            NEW.id,
            CASE WHEN NEW.rating = 5 THEN '5-star review' ELSE '4-star review' END,
            NEW.created_at,
            COALESCE(
                (SELECT r.community_id FROM public.rides r WHERE r.id = NEW.ride_id),
                (SELECT f.community_id FROM public.favors f WHERE f.id = NEW.favor_id)
            )
        )
        ON CONFLICT (source_type, source_id) DO NOTHING;
    END IF;
    RETURN NEW;
END;
$function$;

revoke all on function public.record_xp_on_review() from public, anon, authenticated;


-- ---------------------------------------------------------------------------------------------
-- Call 10. handle_new_report   live md5(prosrc) d2cfc188ab5306952e6ecfaf59c0fac6
-- Phase 0: one new branch (community reports). Recipients, auto-hide threshold and
-- source_user_id unchanged.
-- ---------------------------------------------------------------------------------------------
create or replace function public.handle_new_report()
returns trigger
language plpgsql
security definer
set search_path = ''
as $function$
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
    ELSIF NEW.reported_community_id IS NOT NULL THEN
        v_target_type := 'community';

        SELECT LEFT(c.name, 80)
        INTO v_content_preview
        FROM public.communities c
        WHERE c.id = NEW.reported_community_id;
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
                    'reported_community_id', NEW.reported_community_id::TEXT,
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
$function$;

revoke all on function public.handle_new_report() from public, anon, authenticated;


-- ---------------------------------------------------------------------------------------------
-- Call 11. send_community_broadcast (new)
-- Community admin (is_community_admin: its owner and admins, and platform admins). An
-- announcement post in the community, then one 'broadcast' bell row per active, unbanned,
-- unmuted member other than the sender, through create_notification (the row's community_id
-- derives from town_hall_post_id). At most 3 per community in any 24 hours (D14). The Town Hall
-- push the post triggers goes through notify_town_hall_post, which honours notify_town_hall and
-- the mute. Returns the number of bell rows created (the wrapper's contract).
-- ---------------------------------------------------------------------------------------------
create or replace function public.send_community_broadcast(
    p_community_id uuid,
    p_title text,
    p_body text,
    p_pinned boolean
)
returns integer
language plpgsql
security definer
set search_path = ''
as $function$
declare
    v_uid uuid := (select auth.uid());
    v_post_id uuid;
    v_member record;
    v_notification_id uuid;
    v_inserted_count integer := 0;
begin
    if v_uid is null then
        raise exception 'Only admins can send broadcast notifications' using errcode = '42501';
    end if;

    if p_community_id is null or not public.is_community_admin(p_community_id) then
        raise exception 'Only admins of this community can send announcements' using errcode = '42501';
    end if;

    perform pg_advisory_xact_lock(hashtextextended('community_broadcast:' || p_community_id::text, 0));

    if (select count(*)
          from public.town_hall_posts t
         where t.community_id = p_community_id
           and t.type = 'announcement'
           and t.created_at > now() - interval '24 hours') >= 3 then
        raise exception 'This community has already sent 3 announcements today' using errcode = 'P0001';
    end if;

    insert into public.town_hall_posts (
        user_id, title, content, pinned, type, community_id, created_at, updated_at
    ) values (
        v_uid, p_title, p_body, coalesce(p_pinned, false), 'announcement', p_community_id, now(), now()
    )
    returning id into v_post_id;

    for v_member in
        select m.user_id
          from public.community_members m
          join public.profiles p on p.id = m.user_id
          join public.communities c on c.id = m.community_id and c.archived_at is null
         where m.community_id = p_community_id
           and m.status = 'active'
           and not p.is_banned
           and m.user_id <> v_uid
           and not m.notifications_muted
           and (m.muted_until is null or m.muted_until < now())
    loop
        v_notification_id := public.create_notification(
            v_member.user_id, 'broadcast', p_title, p_body,
            null, null, null, null, v_post_id, v_uid, coalesce(p_pinned, false)
        );
        if v_notification_id is not null then
            v_inserted_count := v_inserted_count + 1;
        end if;
    end loop;

    return v_inserted_count;
end;
$function$;

revoke all on function public.send_community_broadcast(uuid, text, text, boolean) from public, anon;
grant execute on function public.send_community_broadcast(uuid, text, text, boolean) to authenticated, service_role;


-- ---------------------------------------------------------------------------------------------
-- Call 12. send_broadcast_notifications   live md5(prosrc) 8b3eb719ce8f0d4bc57b50f7a228d873
-- Wrapper; the installed admin build's 4-argument call keeps working. A platform admin
-- broadcasts to the default community; a community admin of exactly one community to that
-- community; anyone else is refused with today's message. p_type is ignored (deviation 4).
-- ---------------------------------------------------------------------------------------------
create or replace function public.send_broadcast_notifications(
    p_title text,
    p_body text,
    p_type text default 'broadcast'::text,
    p_pinned boolean default false
)
returns integer
language plpgsql
security definer
set search_path = ''
as $function$
declare
    v_admin_communities uuid[];
    v_community_id uuid;
begin
    if (select auth.uid()) is null then
        raise exception 'Only admins can send broadcast notifications';
    end if;

    if public.is_platform_admin() then
        v_community_id := public.default_community_id();
    else
        v_admin_communities := (select public.my_admin_community_ids());
        if coalesce(cardinality(v_admin_communities), 0) = 1 then
            v_community_id := v_admin_communities[1];
        end if;
    end if;

    if v_community_id is null then
        raise exception 'Only admins can send broadcast notifications';
    end if;

    return public.send_community_broadcast(v_community_id, p_title, p_body, p_pinned);
end;
$function$;


-- ---------------------------------------------------------------------------------------------
-- Call 13. get_community_leaderboard (new)
-- The live get_xp_leaderboard body (md5 e2275c4e9fb5bbfc8be556e2716fdd4b) with:
--   xe.community_id = p_community_id on the ranking scans (xp, the streak bonus's fulfilled
--   weeks, requests_fulfilled, requests_made); the active-membership join instead of
--   profiles.approved; the badges column per person (deviation 1).
-- Readable by the community's active members, platform admins, and anyone (anon included)
-- when the community is public and live. Otherwise 42501.
-- ---------------------------------------------------------------------------------------------
create or replace function public.get_community_leaderboard(
    p_community_id uuid,
    start_date date default '1970-01-01'::date,
    end_date date default current_date
)
returns table(user_id uuid, name text, avatar_url text, xp bigint, badges jsonb, streak_weeks bigint, requests_fulfilled bigint, requests_made bigint)
language plpgsql
security definer
set search_path = ''
as $function$
BEGIN
    IF p_community_id IS NULL
       OR NOT (p_community_id = ANY ((SELECT public.my_community_ids())::uuid[])
               OR public.is_platform_admin()
               OR EXISTS (SELECT 1 FROM public.communities c
                           WHERE c.id = p_community_id AND c.is_public AND c.archived_at IS NULL)) THEN
        RAISE EXCEPTION 'This leaderboard is visible to the community''s members only' USING ERRCODE = '42501';
    END IF;

    RETURN QUERY
    WITH
    user_xp AS (
        SELECT
            xe.user_id,
            SUM(xe.amount)::BIGINT AS event_xp
        FROM public.xp_events xe
        WHERE xe.community_id = p_community_id
          AND xe.created_at::date BETWEEN start_date AND end_date
        GROUP BY xe.user_id
    ),
    fulfilled_weeks AS (
        SELECT DISTINCT
            xe.user_id AS uid,
            DATE_TRUNC('week', xe.created_at)::DATE AS week_start
        FROM public.xp_events xe
        WHERE xe.community_id = p_community_id
          AND xe.source_type IN ('ride_fulfilled', 'favor_fulfilled')
          AND xe.created_at::date BETWEEN start_date AND end_date
    ),
    week_numbered AS (
        SELECT fw.uid, fw.week_start,
            ROW_NUMBER() OVER (PARTITION BY fw.uid ORDER BY fw.week_start) AS rn
        FROM fulfilled_weeks fw
    ),
    streaks AS (
        SELECT wn.uid, COUNT(*)::BIGINT AS streak_len
        FROM week_numbered wn
        GROUP BY wn.uid, (wn.week_start - (wn.rn * INTERVAL '7 days'))
    ),
    longest_streaks AS (
        SELECT s.uid, MAX(s.streak_len)::BIGINT AS longest_streak
        FROM streaks s GROUP BY s.uid
    ),
    -- Per person, every community, same window: feeds only the badges column (rule 8, D5).
    person_fulfilled_weeks AS (
        SELECT DISTINCT
            xe.user_id AS uid,
            DATE_TRUNC('week', xe.created_at)::DATE AS week_start
        FROM public.xp_events xe
        WHERE xe.source_type IN ('ride_fulfilled', 'favor_fulfilled')
          AND xe.created_at::date BETWEEN start_date AND end_date
          AND xe.user_id IN (SELECT ux.user_id FROM user_xp ux)
    ),
    person_week_numbered AS (
        SELECT pw.uid, pw.week_start,
            ROW_NUMBER() OVER (PARTITION BY pw.uid ORDER BY pw.week_start) AS rn
        FROM person_fulfilled_weeks pw
    ),
    person_streaks AS (
        SELECT pn.uid, COUNT(*)::BIGINT AS streak_len
        FROM person_week_numbered pn
        GROUP BY pn.uid, (pn.week_start - (pn.rn * INTERVAL '7 days'))
    ),
    person_longest_streaks AS (
        SELECT ps.uid, MAX(ps.streak_len)::BIGINT AS longest_streak
        FROM person_streaks ps GROUP BY ps.uid
    ),
    user_stats AS (
        SELECT
            ux.user_id,
            ux.event_xp,
            COALESCE(ls.longest_streak, 0) AS streak_wks,
            COALESCE(pls.longest_streak, 0) AS badge_streak_wks,
            (SELECT COUNT(*) FROM public.xp_events x2
             WHERE x2.user_id = ux.user_id
               AND x2.community_id = p_community_id
               AND x2.source_type IN ('ride_fulfilled', 'favor_fulfilled')
               AND x2.created_at::date BETWEEN start_date AND end_date)::BIGINT AS fulfilled_total,
            (SELECT COUNT(*) FROM public.xp_events x3
             WHERE x3.user_id = ux.user_id
               AND x3.community_id = p_community_id
               AND x3.source_type IN ('ride_requested', 'favor_requested')
               AND x3.created_at::date BETWEEN start_date AND end_date)::BIGINT AS made_total,
            -- badge inputs: per person, not scoped to the community
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
            -- Only count savings from rides the user FULFILLED (claimed_by), not requested
            COALESCE((SELECT SUM(r.estimated_cost)
             FROM public.rides r
             WHERE r.claimed_by = ux.user_id
               AND r.status = 'completed'), 0) AS savings
        FROM user_xp ux
        LEFT JOIN longest_streaks ls ON ls.uid = ux.user_id
        LEFT JOIN person_longest_streaks pls ON pls.uid = ux.user_id
    )
    SELECT
        p.id AS user_id,
        p.name AS name,
        p.avatar_url AS avatar_url,
        (us.event_xp + us.streak_wks * 5)::BIGINT AS xp,
        (
            SELECT COALESCE(jsonb_agg(b.badge), '[]'::jsonb)
            FROM (
                SELECT 'road_warrior' AS badge WHERE us.rides_fulfilled_cnt >= 10
                UNION ALL
                SELECT 'good_neighbor' WHERE us.favors_fulfilled_cnt >= 10
                UNION ALL
                SELECT 'streak_champion' WHERE us.badge_streak_wks >= 3
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
    JOIN public.profiles p ON p.id = us.user_id
    JOIN public.community_members m
      ON m.user_id = p.id AND m.community_id = p_community_id AND m.status = 'active'
    WHERE (us.event_xp + us.streak_wks * 5) > 0
    ORDER BY (us.event_xp + us.streak_wks * 5) DESC
    LIMIT 100;
END;
$function$;

revoke all on function public.get_community_leaderboard(uuid, date, date) from public;
grant execute on function public.get_community_leaderboard(uuid, date, date) to anon, authenticated, service_role;


-- ---------------------------------------------------------------------------------------------
-- Call 14. get_community_spotlights (new)
-- The live get_leaderboard_spotlights body (md5 20c425ccb0cfb6a1e849280305a281e9) with every
-- CTE over rides / favors scoped by community_id in both the SELECT and the de-dup step of each
-- category (the live temp table _claimed_users is a local uuid[] here: same winners, no writes, and
-- no statement that empties a table, which the Supabase MCP declines; found in the 2026-10-17
-- dry-run), review_xp scoped through the reviewed request (deviation 2),
-- and the active-membership join instead of profiles.approved. This body never reads
-- xp_events. Same access rule as get_community_leaderboard.
-- ---------------------------------------------------------------------------------------------
create or replace function public.get_community_spotlights(
    p_community_id uuid,
    start_date date default '1970-01-01'::date,
    end_date date default current_date
)
returns table(category text, user_id uuid, name text, avatar_url text, value bigint)
language plpgsql
security definer
set search_path = ''
as $function$
DECLARE
    -- user ids already given a category; a local array instead of the live body's temp table, so
    -- the function writes nothing and has no table to empty (the MCP will not send that statement)
    v_claimed uuid[] := '{}'::uuid[];
BEGIN
    IF p_community_id IS NULL
       OR NOT (p_community_id = ANY ((SELECT public.my_community_ids())::uuid[])
               OR public.is_platform_admin()
               OR EXISTS (SELECT 1 FROM public.communities c
                           WHERE c.id = p_community_id AND c.is_public AND c.archived_at IS NULL)) THEN
        RAISE EXCEPTION 'These spotlights are visible to the community''s members only' USING ERRCODE = '42501';
    END IF;


    -- -----------------------------------------------------------------
    -- Category 1: longest_streak
    -- -----------------------------------------------------------------
    RETURN QUERY
    WITH
    fulfilled_weeks AS (
        SELECT DISTINCT
            r.claimed_by AS uid,
            DATE_TRUNC('week', r.updated_at)::DATE AS week_start
        FROM public.rides r
        WHERE r.claimed_by IS NOT NULL
          AND r.community_id = p_community_id
          AND r.status = 'completed'
          AND r.updated_at::date BETWEEN start_date AND end_date

        UNION

        SELECT DISTINCT
            f.claimed_by AS uid,
            DATE_TRUNC('week', f.updated_at)::DATE AS week_start
        FROM public.favors f
        WHERE f.claimed_by IS NOT NULL
          AND f.community_id = p_community_id
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
    JOIN public.profiles p ON p.id = lpu.uid
    JOIN public.community_members m
      ON m.user_id = p.id AND m.community_id = p_community_id AND m.status = 'active'
    WHERE lpu.longest_streak > 0
      AND NOT (lpu.uid = ANY (v_claimed))
    ORDER BY lpu.longest_streak DESC, p.name ASC
    LIMIT 1;

    -- Claim the longest_streak winner
    v_claimed := v_claimed || ARRAY(
    WITH
    fulfilled_weeks AS (
        SELECT DISTINCT
            r.claimed_by AS uid,
            DATE_TRUNC('week', r.updated_at)::DATE AS week_start
        FROM public.rides r
        WHERE r.claimed_by IS NOT NULL
          AND r.community_id = p_community_id
          AND r.status = 'completed'
          AND r.updated_at::date BETWEEN start_date AND end_date

        UNION

        SELECT DISTINCT
            f.claimed_by AS uid,
            DATE_TRUNC('week', f.updated_at)::DATE AS week_start
        FROM public.favors f
        WHERE f.claimed_by IS NOT NULL
          AND f.community_id = p_community_id
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
    JOIN public.profiles p ON p.id = lpu.uid
    JOIN public.community_members m
      ON m.user_id = p.id AND m.community_id = p_community_id AND m.status = 'active'
    WHERE lpu.longest_streak > 0
      AND NOT (lpu.uid = ANY (v_claimed))
    ORDER BY lpu.longest_streak DESC, p.name ASC
    LIMIT 1
    );

    -- -----------------------------------------------------------------
    -- Category 2: rising_star
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
        FROM public.rides r
        WHERE r.claimed_by IS NOT NULL
          AND r.community_id = p_community_id
          AND r.status = 'completed'
          AND r.updated_at::date BETWEEN start_date AND end_date
        GROUP BY r.claimed_by
    ),
    favors_fulfilled_xp AS (
        SELECT
            f.claimed_by AS uid,
            (COUNT(*) * 10)::BIGINT AS xp
        FROM public.favors f
        WHERE f.claimed_by IS NOT NULL
          AND f.community_id = p_community_id
          AND f.status = 'completed'
          AND f.updated_at::date BETWEEN start_date AND end_date
        GROUP BY f.claimed_by
    ),
    rides_requested_xp AS (
        SELECT
            r.user_id AS uid,
            (COUNT(*) * 5)::BIGINT AS xp
        FROM public.rides r
        WHERE r.community_id = p_community_id
          AND r.created_at::date BETWEEN start_date AND end_date
        GROUP BY r.user_id
    ),
    favors_requested_xp AS (
        SELECT
            f.user_id AS uid,
            (COUNT(*) * 5)::BIGINT AS xp
        FROM public.favors f
        WHERE f.community_id = p_community_id
          AND f.created_at::date BETWEEN start_date AND end_date
        GROUP BY f.user_id
    ),
    review_xp AS (
        SELECT
            rv.fulfiller_id AS uid,
            SUM(CASE WHEN rv.rating = 5 THEN 5
                     WHEN rv.rating = 4 THEN 2
                     ELSE 0 END)::BIGINT AS xp
        FROM public.reviews rv
        LEFT JOIN public.rides rr ON rr.id = rv.ride_id
        LEFT JOIN public.favors ff ON ff.id = rv.favor_id
        WHERE COALESCE(rr.community_id, ff.community_id) = p_community_id
          AND rv.created_at::date BETWEEN start_date AND end_date
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
    JOIN public.profiles p ON p.id = ut.uid
    JOIN public.community_members m
      ON m.user_id = p.id AND m.community_id = p_community_id AND m.status = 'active'
    WHERE ut.total_xp > 0
      AND NOT (ut.uid = ANY (v_claimed))
    ORDER BY ut.total_xp DESC, p.name ASC
    LIMIT 1;

    -- Claim the rising_star winner
    v_claimed := v_claimed || ARRAY(
    WITH
    rides_fulfilled_xp AS (
        SELECT
            r.claimed_by AS uid,
            SUM(5 + COALESCE(FLOOR(r.estimated_cost / 5), 0))::BIGINT AS xp
        FROM public.rides r
        WHERE r.claimed_by IS NOT NULL
          AND r.community_id = p_community_id
          AND r.status = 'completed'
          AND r.updated_at::date BETWEEN start_date AND end_date
        GROUP BY r.claimed_by
    ),
    favors_fulfilled_xp AS (
        SELECT
            f.claimed_by AS uid,
            (COUNT(*) * 10)::BIGINT AS xp
        FROM public.favors f
        WHERE f.claimed_by IS NOT NULL
          AND f.community_id = p_community_id
          AND f.status = 'completed'
          AND f.updated_at::date BETWEEN start_date AND end_date
        GROUP BY f.claimed_by
    ),
    rides_requested_xp AS (
        SELECT
            r.user_id AS uid,
            (COUNT(*) * 5)::BIGINT AS xp
        FROM public.rides r
        WHERE r.community_id = p_community_id
          AND r.created_at::date BETWEEN start_date AND end_date
        GROUP BY r.user_id
    ),
    favors_requested_xp AS (
        SELECT
            f.user_id AS uid,
            (COUNT(*) * 5)::BIGINT AS xp
        FROM public.favors f
        WHERE f.community_id = p_community_id
          AND f.created_at::date BETWEEN start_date AND end_date
        GROUP BY f.user_id
    ),
    review_xp AS (
        SELECT
            rv.fulfiller_id AS uid,
            SUM(CASE WHEN rv.rating = 5 THEN 5
                     WHEN rv.rating = 4 THEN 2
                     ELSE 0 END)::BIGINT AS xp
        FROM public.reviews rv
        LEFT JOIN public.rides rr ON rr.id = rv.ride_id
        LEFT JOIN public.favors ff ON ff.id = rv.favor_id
        WHERE COALESCE(rr.community_id, ff.community_id) = p_community_id
          AND rv.created_at::date BETWEEN start_date AND end_date
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
    JOIN public.profiles p ON p.id = ut.uid
    JOIN public.community_members m
      ON m.user_id = p.id AND m.community_id = p_community_id AND m.status = 'active'
    WHERE ut.total_xp > 0
      AND NOT (ut.uid = ANY (v_claimed))
    ORDER BY ut.total_xp DESC, p.name ASC
    LIMIT 1
    );

    -- -----------------------------------------------------------------
    -- Category 3: top_requester
    -- -----------------------------------------------------------------
    RETURN QUERY
    WITH
    ride_counts AS (
        SELECT
            r.user_id AS uid,
            COUNT(*)::BIGINT AS cnt
        FROM public.rides r
        WHERE r.community_id = p_community_id
          AND r.created_at::date BETWEEN start_date AND end_date
        GROUP BY r.user_id
    ),
    favor_counts AS (
        SELECT
            f.user_id AS uid,
            COUNT(*)::BIGINT AS cnt
        FROM public.favors f
        WHERE f.community_id = p_community_id
          AND f.created_at::date BETWEEN start_date AND end_date
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
    JOIN public.profiles p ON p.id = rt.uid
    JOIN public.community_members m
      ON m.user_id = p.id AND m.community_id = p_community_id AND m.status = 'active'
    WHERE rt.total_requests > 0
      AND NOT (rt.uid = ANY (v_claimed))
    ORDER BY rt.total_requests DESC, p.name ASC
    LIMIT 1;

    -- Claim the top_requester winner
    v_claimed := v_claimed || ARRAY(
    WITH
    ride_counts AS (
        SELECT
            r.user_id AS uid,
            COUNT(*)::BIGINT AS cnt
        FROM public.rides r
        WHERE r.community_id = p_community_id
          AND r.created_at::date BETWEEN start_date AND end_date
        GROUP BY r.user_id
    ),
    favor_counts AS (
        SELECT
            f.user_id AS uid,
            COUNT(*)::BIGINT AS cnt
        FROM public.favors f
        WHERE f.community_id = p_community_id
          AND f.created_at::date BETWEEN start_date AND end_date
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
    JOIN public.profiles p ON p.id = rt.uid
    JOIN public.community_members m
      ON m.user_id = p.id AND m.community_id = p_community_id AND m.status = 'active'
    WHERE rt.total_requests > 0
      AND NOT (rt.uid = ANY (v_claimed))
    ORDER BY rt.total_requests DESC, p.name ASC
    LIMIT 1
    );

END;
$function$;

revoke all on function public.get_community_spotlights(uuid, date, date) from public;
grant execute on function public.get_community_spotlights(uuid, date, date) to anon, authenticated, service_role;


-- ---------------------------------------------------------------------------------------------
-- Call 15. get_xp_leaderboard   live md5(prosrc) e2275c4e9fb5bbfc8be556e2716fdd4b
-- Thin wrapper. Community: the caller's primary while it is a live active membership, else the
-- default community; anon gets the default community (public).
-- ---------------------------------------------------------------------------------------------
create or replace function public.get_xp_leaderboard(
    start_date date default '1970-01-01'::date,
    end_date date default current_date
)
returns table(user_id uuid, name text, avatar_url text, xp bigint, badges jsonb, streak_weeks bigint, requests_fulfilled bigint, requests_made bigint)
language plpgsql
security definer
set search_path = ''
as $function$
DECLARE
    v_community_id UUID;
BEGIN
    v_community_id := COALESCE(
        (SELECT p.primary_community_id
           FROM public.profiles p
          WHERE p.id = (SELECT auth.uid())
            AND p.primary_community_id = ANY ((SELECT public.my_community_ids())::uuid[])),
        public.default_community_id()
    );

    RETURN QUERY
    SELECT l.user_id, l.name, l.avatar_url, l.xp, l.badges, l.streak_weeks, l.requests_fulfilled, l.requests_made
    FROM public.get_community_leaderboard(v_community_id, start_date, end_date) l;
END;
$function$;


-- ---------------------------------------------------------------------------------------------
-- Call 16. get_leaderboard_spotlights   live md5(prosrc) 20c425ccb0cfb6a1e849280305a281e9
-- Thin wrapper, same resolution as call 15.
-- ---------------------------------------------------------------------------------------------
create or replace function public.get_leaderboard_spotlights(
    start_date date default '1970-01-01'::date,
    end_date date default current_date
)
returns table(category text, user_id uuid, name text, avatar_url text, value bigint)
language plpgsql
security definer
set search_path = ''
as $function$
DECLARE
    v_community_id UUID;
BEGIN
    v_community_id := COALESCE(
        (SELECT p.primary_community_id
           FROM public.profiles p
          WHERE p.id = (SELECT auth.uid())
            AND p.primary_community_id = ANY ((SELECT public.my_community_ids())::uuid[])),
        public.default_community_id()
    );

    RETURN QUERY
    SELECT s.category, s.user_id, s.name, s.avatar_url, s.value
    FROM public.get_community_spotlights(v_community_id, start_date, end_date) s;
END;
$function$;


-- ---------------------------------------------------------------------------------------------
-- Call 17. get_leaderboard(text, integer)   live md5(prosrc) aa577f5aeff40103e8ca5e4488d7216c
-- No caller in the iOS app. Scoped in place (deviation 3): members of the resolved community,
-- fulfilled count from reviews of that community's requests; rating stays per person.
-- ---------------------------------------------------------------------------------------------
create or replace function public.get_leaderboard(
    p_time_filter text default 'all_time'::text,
    p_limit integer default 50
)
returns table(user_id uuid, name text, avatar_url text, fulfilled_count bigint, average_rating numeric, review_count bigint, rank bigint)
language plpgsql
security definer
set search_path = ''
as $function$
DECLARE
    v_community_id UUID;
BEGIN
    v_community_id := COALESCE(
        (SELECT pr.primary_community_id
           FROM public.profiles pr
          WHERE pr.id = (SELECT auth.uid())
            AND pr.primary_community_id = ANY ((SELECT public.my_community_ids())::uuid[])),
        public.default_community_id()
    );

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
    JOIN public.community_members cm
      ON cm.user_id = p.id AND cm.community_id = v_community_id AND cm.status = 'active'
    LEFT JOIN (
        SELECT
            rv.fulfiller_id,
            COUNT(*) as count
        FROM public.reviews rv
        LEFT JOIN public.rides rr ON rr.id = rv.ride_id
        LEFT JOIN public.favors ff ON ff.id = rv.favor_id
        WHERE COALESCE(rr.community_id, ff.community_id) = v_community_id
          AND (p_time_filter = 'all_time' OR rv.created_at >= CASE
            WHEN p_time_filter = 'week' THEN NOW() - INTERVAL '7 days'
            WHEN p_time_filter = 'month' THEN NOW() - INTERVAL '30 days'
            WHEN p_time_filter = 'year' THEN NOW() - INTERVAL '365 days'
            ELSE '1970-01-01'::TIMESTAMPTZ
        END)
        GROUP BY rv.fulfiller_id
    ) fulfilled ON fulfilled.fulfiller_id = p.id
    LEFT JOIN (
        SELECT
            rv2.fulfiller_id,
            AVG(rv2.rating) as avg_rating,
            COUNT(*) as review_count
        FROM public.reviews rv2
        GROUP BY rv2.fulfiller_id
    ) reviews ON reviews.fulfiller_id = p.id
    ORDER BY fulfilled_count DESC, average_rating DESC
    LIMIT p_limit;
END;
$function$;


-- ---------------------------------------------------------------------------------------------
-- Call 18. get_leaderboard(date, date)   live md5(prosrc) 3147db83803aba7db4a49dbc5eb04e2d
-- No caller in the iOS app. Scoped in place (deviation 3) and now SECURITY DEFINER.
-- ---------------------------------------------------------------------------------------------
create or replace function public.get_leaderboard(
    start_date date default '1970-01-01'::date,
    end_date date default current_date
)
returns table(user_id uuid, name text, avatar_url text, requests_fulfilled bigint, requests_made bigint)
language plpgsql
stable
security definer
set search_path = ''
as $function$
DECLARE
    v_community_id UUID;
BEGIN
    v_community_id := COALESCE(
        (SELECT pr.primary_community_id
           FROM public.profiles pr
          WHERE pr.id = (SELECT auth.uid())
            AND pr.primary_community_id = ANY ((SELECT public.my_community_ids())::uuid[])),
        public.default_community_id()
    );

    RETURN QUERY
    SELECT
        p.id,
        p.name,
        p.avatar_url,
        (
            SELECT COUNT(*) FROM public.rides r
            WHERE r.claimed_by = p.id
            AND r.community_id = v_community_id
            AND r.status = 'completed'
            AND DATE(r.updated_at) BETWEEN start_date AND end_date
        ) + (
            SELECT COUNT(*) FROM public.favors f
            WHERE f.claimed_by = p.id
            AND f.community_id = v_community_id
            AND f.status = 'completed'
            AND DATE(f.updated_at) BETWEEN start_date AND end_date
        ) as requests_fulfilled,
        (
            SELECT COUNT(*) FROM public.rides r
            WHERE r.user_id = p.id
            AND r.community_id = v_community_id
            AND DATE(r.created_at) BETWEEN start_date AND end_date
        ) + (
            SELECT COUNT(*) FROM public.favors f
            WHERE f.user_id = p.id
            AND f.community_id = v_community_id
            AND DATE(f.created_at) BETWEEN start_date AND end_date
        ) as requests_made
    FROM public.profiles p
    JOIN public.community_members cm
      ON cm.user_id = p.id AND cm.community_id = v_community_id AND cm.status = 'active'
    ORDER BY requests_fulfilled DESC
    LIMIT 100;
END;
$function$;


-- ---------------------------------------------------------------------------------------------
-- Call 19. get_profile_stats (new)
-- Per person over every community (rule 8). fulfilled_count is the client's definition
-- (ProfileService.fetchFulfilledCount): rides and favors claimed by the user, status confirmed
-- or completed. avg_rating is null when there are no reviews (calculateAverageRating returns
-- nil). Same visibility rule as public_profiles; otherwise an empty object.
-- ---------------------------------------------------------------------------------------------
create or replace function public.get_profile_stats(p_user_id uuid)
returns jsonb
language plpgsql
stable
security definer
set search_path = ''
as $function$
declare
    v_avg_rating numeric;
    v_review_count bigint;
    v_fulfilled_count bigint;
begin
    if p_user_id is null
       or not (p_user_id = any ((select public.my_visible_profile_ids())::uuid[])
               or ((select auth.uid()) is null
                   and exists (select 1
                                 from public.community_members m
                                 join public.communities c on c.id = m.community_id
                                where m.user_id = p_user_id and m.status = 'active'
                                  and c.is_public and c.archived_at is null))) then
        return '{}'::jsonb;
    end if;

    select avg(r.rating)::numeric, count(*)::bigint
      into v_avg_rating, v_review_count
      from public.reviews r
     where r.fulfiller_id = p_user_id;

    select (select count(*) from public.rides r
             where r.claimed_by = p_user_id and r.status::text in ('confirmed', 'completed'))
         + (select count(*) from public.favors f
             where f.claimed_by = p_user_id and f.status::text in ('confirmed', 'completed'))
      into v_fulfilled_count;

    return jsonb_build_object(
        'avg_rating', v_avg_rating,
        'review_count', coalesce(v_review_count, 0),
        'fulfilled_count', coalesce(v_fulfilled_count, 0)
    );
end;
$function$;

revoke all on function public.get_profile_stats(uuid) from public;
grant execute on function public.get_profile_stats(uuid) to anon, authenticated, service_role;


-- ---------------------------------------------------------------------------------------------
-- Call 20. get_user_badges   live md5(prosrc) 374c12dd8163e3be4a1a235db6da48c9
-- Body unchanged (live search_path 'public' kept); the visibility gate is the first statement.
-- ---------------------------------------------------------------------------------------------
create or replace function public.get_user_badges(target_user_id uuid)
returns jsonb
language plpgsql
security definer
set search_path = 'public'
as $function$
DECLARE
    v_rides_fulfilled   BIGINT;
    v_favors_fulfilled  BIGINT;
    v_five_star_count   BIGINT;
    v_total_savings     NUMERIC;
    v_longest_streak    BIGINT;
    v_requests_made     BIGINT;
    v_badges            JSONB := '[]'::jsonb;
BEGIN
    -- Visibility gate (same rule as public_profiles): self, a visible profile, or for anon an
    -- active member of a public community. Anyone else gets no badges.
    IF target_user_id IS NULL
       OR NOT (target_user_id = ANY ((SELECT public.my_visible_profile_ids())::uuid[])
               OR ((SELECT auth.uid()) IS NULL
                   AND EXISTS (SELECT 1
                                 FROM public.community_members m
                                 JOIN public.communities c ON c.id = m.community_id
                                WHERE m.user_id = target_user_id AND m.status = 'active'
                                  AND c.is_public AND c.archived_at IS NULL))) THEN
        RETURN '[]'::jsonb;
    END IF;

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
$function$;


-- ---------------------------------------------------------------------------------------------
-- Call 21. get_user_stats   live md5(prosrc) aa3a44c11c10520809ca0f0c9c452806
-- Body unchanged; the gate returns no row for a profile the caller cannot see.
-- ---------------------------------------------------------------------------------------------
create or replace function public.get_user_stats(p_user_id uuid)
returns table(avg_rating numeric, review_count bigint, fulfilled_count bigint)
language plpgsql
security definer
set search_path = ''
as $function$
BEGIN
    IF p_user_id IS NULL
       OR NOT (p_user_id = ANY ((SELECT public.my_visible_profile_ids())::uuid[])
               OR ((SELECT auth.uid()) IS NULL
                   AND EXISTS (SELECT 1
                                 FROM public.community_members m
                                 JOIN public.communities c ON c.id = m.community_id
                                WHERE m.user_id = p_user_id AND m.status = 'active'
                                  AND c.is_public AND c.archived_at IS NULL))) THEN
        RETURN;
    END IF;

    RETURN QUERY
    SELECT
        COALESCE(AVG(r.rating)::NUMERIC, 0) as avg_rating,
        COUNT(r.id)::BIGINT as review_count,
        COUNT(DISTINCT CASE WHEN r.fulfiller_id = p_user_id THEN r.ride_id END) +
        COUNT(DISTINCT CASE WHEN r.fulfiller_id = p_user_id THEN r.favor_id END) as fulfilled_count
    FROM public.reviews r
    WHERE r.fulfiller_id = p_user_id;
END;
$function$;


-- ---------------------------------------------------------------------------------------------
-- Call 22. is_user_approved   live md5(prosrc) 1c0d84cf3020fe2f830fb60b29aca4c9
-- Body unchanged inside the gate; false for a profile the caller cannot see. The parameter is
-- named user_id, so the body refers to it as $1 (a bare user_id would bind to the
-- community_members column inside the subquery).
-- ---------------------------------------------------------------------------------------------
create or replace function public.is_user_approved(user_id uuid)
returns boolean
language sql
stable
security definer
set search_path = ''
as $function$
    SELECT CASE
        WHEN $1 = ANY ((SELECT public.my_visible_profile_ids())::uuid[])
          OR ((SELECT auth.uid()) IS NULL
              AND EXISTS (SELECT 1
                            FROM public.community_members m
                            JOIN public.communities c ON c.id = m.community_id
                           WHERE m.user_id = $1 AND m.status = 'active'
                             AND c.is_public AND c.archived_at IS NULL))
        THEN (SELECT p.approved FROM public.profiles p WHERE p.id = $1)
        ELSE false
    END;
$function$;


-- ---------------------------------------------------------------------------------------------
-- Call 23. create_signup_profile   live md5(prosrc) 2da330dc9e980d4819ead406a29185c8
-- Only the ON CONFLICT branch changes: it no longer assigns approved or application_complete
-- (mirrored from memberships; resetting them beside an existing membership would break INV-M5).
-- A fresh insert still writes both false, as before.
-- ---------------------------------------------------------------------------------------------
create or replace function public.create_signup_profile(
    p_user_id uuid,
    p_email text,
    p_name text,
    p_invited_by uuid default null::uuid,
    p_car text default null::text,
    p_heard_about text default null::text,
    p_join_reason text default null::text
)
returns jsonb
language plpgsql
security definer
set search_path = 'public'
as $function$
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
$function$;


-- ---------------------------------------------------------------------------------------------
-- Call 24. get_badge_counts   live md5(prosrc) 5002e87acb71fdf5249c8a1280fa5967
-- Every existing key unchanged. Adds:
--   pending_members_total  pending rows in live communities where the user is an active,
--                          unbanned owner or admin, plus, for an unbanned platform admin, in
--                          live communities that have no such owner or admin. Computed for
--                          v_user_id (not auth.uid()), because the edge functions call this RPC
--                          with the service role and p_user_id.
--   community_details      with p_include_details: [{community_id, requests_total,
--                          community_total, bell_total}] over notifications.community_id, one
--                          entry per community with an unread row; same definitions as the
--                          totals (the announcement pruning stays global).
-- Re-applying this call is also the revert of call 25.
-- ---------------------------------------------------------------------------------------------
create or replace function public.get_badge_counts(p_include_details boolean default false, p_user_id uuid default null::uuid)
returns jsonb
language plpgsql
security definer
set search_path = ''
as $function$
declare
    v_user_id uuid;
    v_messages_total integer;
    v_requests_total integer;
    v_community_total integer;
    v_bell_total integer;
    v_pending_members_total integer;
    v_is_platform_admin boolean;
    v_request_details jsonb := '[]'::jsonb;
    v_conversation_details jsonb := '[]'::jsonb;
    v_community_details jsonb := '[]'::jsonb;
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

    -- Pending applicants this user can act on (the Profile badge's one authoritative source).
    select exists (
        select 1 from public.profiles pa
        where pa.id = v_user_id and pa.is_admin and not pa.is_banned
    ) into v_is_platform_admin;

    select coalesce(count(*), 0)::int
    into v_pending_members_total
    from public.community_members pm
    join public.communities pc on pc.id = pm.community_id and pc.archived_at is null
    where pm.status = 'pending'
      and (
          exists (
              select 1
              from public.community_members am
              join public.profiles ap on ap.id = am.user_id
              where am.community_id = pm.community_id
                and am.user_id = v_user_id
                and am.status = 'active'
                and am.role in ('owner', 'admin')
                and not ap.is_banned
          )
          or (
              v_is_platform_admin
              and not exists (
                  select 1
                  from public.community_members am
                  join public.profiles ap on ap.id = am.user_id
                  where am.community_id = pm.community_id
                    and am.status = 'active'
                    and am.role in ('owner', 'admin')
                    and not ap.is_banned
              )
          )
      );

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

        with cd_unread_requests as (
            select distinct
                n.community_id,
                case
                    when n.ride_id is not null then 'ride:' || n.ride_id::text
                    when n.favor_id is not null then 'favor:' || n.favor_id::text
                    else null
                end as request_key
            from public.notifications n
            where n.user_id = v_user_id
              and n.read = false
              and n.community_id is not null
              and n.type in (
                  'new_ride', 'ride_update', 'ride_claimed', 'ride_unclaimed',
                  'new_favor', 'favor_update', 'favor_claimed', 'favor_unclaimed',
                  'completion_reminder', 'qa_activity', 'qa_question', 'qa_answer'
              )
        ),
        cd_requests as (
            select ur.community_id, count(*)::int as cnt
            from cd_unread_requests ur
            where ur.request_key is not null
            group by ur.community_id
        ),
        cd_community as (
            select n.community_id, count(*)::int as cnt
            from public.notifications n
            where n.user_id = v_user_id
              and n.read = false
              and n.community_id is not null
              and n.type in ('town_hall_post', 'town_hall_comment', 'town_hall_reaction')
            group by n.community_id
        ),
        cd_bell_fresh as (
            select *
            from public.notifications n
            where n.user_id = v_user_id
              and n.type not in ('message', 'added_to_conversation')
              and (n.read = false or n.created_at > now() - interval '24 hours')
        ),
        cd_latest_announcement as (
            select bf.id
            from cd_bell_fresh bf
            where bf.type in ('announcement', 'admin_announcement', 'broadcast')
            order by bf.created_at desc
            limit 1
        ),
        cd_bell_pruned as (
            select * from cd_bell_fresh bf
            where bf.type not in ('announcement', 'admin_announcement', 'broadcast')
            union all
            select bf.* from cd_bell_fresh bf
            where bf.id in (select la.id from cd_latest_announcement la)
        ),
        cd_bell_groups as (
            select
                bp.community_id,
                case
                    when bp.type in ('announcement', 'admin_announcement', 'broadcast')
                        then 'announcement:' || bp.id::text
                    when bp.type in ('town_hall_post', 'town_hall_comment', 'town_hall_reaction')
                        and bp.town_hall_post_id is not null
                        then 'townHall:' || bp.town_hall_post_id::text
                    when bp.type = 'pending_approval'
                        then 'admin:pendingApproval'
                    when bp.type in (
                        'new_ride', 'ride_update', 'ride_claimed', 'ride_unclaimed', 'ride_completed',
                        'new_favor', 'favor_update', 'favor_claimed', 'favor_unclaimed', 'favor_completed',
                        'completion_reminder', 'qa_activity', 'qa_question', 'qa_answer',
                        'review_request', 'review_reminder', 'review_received'
                    ) and bp.ride_id is not null
                        then 'ride:' || bp.ride_id::text
                    when bp.type in (
                        'new_ride', 'ride_update', 'ride_claimed', 'ride_unclaimed', 'ride_completed',
                        'new_favor', 'favor_update', 'favor_claimed', 'favor_unclaimed', 'favor_completed',
                        'completion_reminder', 'qa_activity', 'qa_question', 'qa_answer',
                        'review_request', 'review_reminder', 'review_received'
                    ) and bp.favor_id is not null
                        then 'favor:' || bp.favor_id::text
                    else 'notification:' || bp.id::text
                end as group_key,
                bool_or(bp.read = false) as has_unread
            from cd_bell_pruned bp
            where bp.community_id is not null
            group by 1, 2
        ),
        cd_bell as (
            select bg.community_id, count(*)::int as cnt
            from cd_bell_groups bg
            where bg.has_unread
            group by bg.community_id
        ),
        cd_ids as (
            select community_id from cd_requests
            union select community_id from cd_community
            union select community_id from cd_bell
        )
        select coalesce(jsonb_agg(jsonb_build_object(
            'community_id', i.community_id,
            'requests_total', coalesce(rq.cnt, 0),
            'community_total', coalesce(cm.cnt, 0),
            'bell_total', coalesce(bl.cnt, 0)
        ) order by i.community_id), '[]'::jsonb)
        into v_community_details
        from cd_ids i
        left join cd_requests rq on rq.community_id = i.community_id
        left join cd_community cm on cm.community_id = i.community_id
        left join cd_bell bl on bl.community_id = i.community_id;
    end if;

    return jsonb_build_object(
        'user_id', v_user_id,
        'messages_total', coalesce(v_messages_total, 0),
        'requests_total', coalesce(v_requests_total, 0),
        'community_total', coalesce(v_community_total, 0),
        'bell_total', coalesce(v_bell_total, 0),
        'request_details', coalesce(v_request_details, '[]'::jsonb),
        'conversation_details', coalesce(v_conversation_details, '[]'::jsonb),
        'pending_members_total', coalesce(v_pending_members_total, 0),
        'community_details', coalesce(v_community_details, '[]'::jsonb)
    );
end;
$function$;


-- ---------------------------------------------------------------------------------------------
-- Call 25. get_badge_counts + total (D28)   body = call 24 plus one key
-- total = requests_total + messages_total + community_total, the number the app sets on its
-- icon when it is open. _shared/badges.ts already prefers data.total, so after this call the
-- icon number a push sets changes from (all unread notifications + unread messages) to this.
-- Its own MCP call so it can be reverted alone (re-apply call 24). Check on a device.
-- ---------------------------------------------------------------------------------------------
create or replace function public.get_badge_counts(p_include_details boolean default false, p_user_id uuid default null::uuid)
returns jsonb
language plpgsql
security definer
set search_path = ''
as $function$
declare
    v_user_id uuid;
    v_messages_total integer;
    v_requests_total integer;
    v_community_total integer;
    v_bell_total integer;
    v_pending_members_total integer;
    v_is_platform_admin boolean;
    v_request_details jsonb := '[]'::jsonb;
    v_conversation_details jsonb := '[]'::jsonb;
    v_community_details jsonb := '[]'::jsonb;
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

    -- Pending applicants this user can act on (the Profile badge's one authoritative source).
    select exists (
        select 1 from public.profiles pa
        where pa.id = v_user_id and pa.is_admin and not pa.is_banned
    ) into v_is_platform_admin;

    select coalesce(count(*), 0)::int
    into v_pending_members_total
    from public.community_members pm
    join public.communities pc on pc.id = pm.community_id and pc.archived_at is null
    where pm.status = 'pending'
      and (
          exists (
              select 1
              from public.community_members am
              join public.profiles ap on ap.id = am.user_id
              where am.community_id = pm.community_id
                and am.user_id = v_user_id
                and am.status = 'active'
                and am.role in ('owner', 'admin')
                and not ap.is_banned
          )
          or (
              v_is_platform_admin
              and not exists (
                  select 1
                  from public.community_members am
                  join public.profiles ap on ap.id = am.user_id
                  where am.community_id = pm.community_id
                    and am.status = 'active'
                    and am.role in ('owner', 'admin')
                    and not ap.is_banned
              )
          )
      );

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

        with cd_unread_requests as (
            select distinct
                n.community_id,
                case
                    when n.ride_id is not null then 'ride:' || n.ride_id::text
                    when n.favor_id is not null then 'favor:' || n.favor_id::text
                    else null
                end as request_key
            from public.notifications n
            where n.user_id = v_user_id
              and n.read = false
              and n.community_id is not null
              and n.type in (
                  'new_ride', 'ride_update', 'ride_claimed', 'ride_unclaimed',
                  'new_favor', 'favor_update', 'favor_claimed', 'favor_unclaimed',
                  'completion_reminder', 'qa_activity', 'qa_question', 'qa_answer'
              )
        ),
        cd_requests as (
            select ur.community_id, count(*)::int as cnt
            from cd_unread_requests ur
            where ur.request_key is not null
            group by ur.community_id
        ),
        cd_community as (
            select n.community_id, count(*)::int as cnt
            from public.notifications n
            where n.user_id = v_user_id
              and n.read = false
              and n.community_id is not null
              and n.type in ('town_hall_post', 'town_hall_comment', 'town_hall_reaction')
            group by n.community_id
        ),
        cd_bell_fresh as (
            select *
            from public.notifications n
            where n.user_id = v_user_id
              and n.type not in ('message', 'added_to_conversation')
              and (n.read = false or n.created_at > now() - interval '24 hours')
        ),
        cd_latest_announcement as (
            select bf.id
            from cd_bell_fresh bf
            where bf.type in ('announcement', 'admin_announcement', 'broadcast')
            order by bf.created_at desc
            limit 1
        ),
        cd_bell_pruned as (
            select * from cd_bell_fresh bf
            where bf.type not in ('announcement', 'admin_announcement', 'broadcast')
            union all
            select bf.* from cd_bell_fresh bf
            where bf.id in (select la.id from cd_latest_announcement la)
        ),
        cd_bell_groups as (
            select
                bp.community_id,
                case
                    when bp.type in ('announcement', 'admin_announcement', 'broadcast')
                        then 'announcement:' || bp.id::text
                    when bp.type in ('town_hall_post', 'town_hall_comment', 'town_hall_reaction')
                        and bp.town_hall_post_id is not null
                        then 'townHall:' || bp.town_hall_post_id::text
                    when bp.type = 'pending_approval'
                        then 'admin:pendingApproval'
                    when bp.type in (
                        'new_ride', 'ride_update', 'ride_claimed', 'ride_unclaimed', 'ride_completed',
                        'new_favor', 'favor_update', 'favor_claimed', 'favor_unclaimed', 'favor_completed',
                        'completion_reminder', 'qa_activity', 'qa_question', 'qa_answer',
                        'review_request', 'review_reminder', 'review_received'
                    ) and bp.ride_id is not null
                        then 'ride:' || bp.ride_id::text
                    when bp.type in (
                        'new_ride', 'ride_update', 'ride_claimed', 'ride_unclaimed', 'ride_completed',
                        'new_favor', 'favor_update', 'favor_claimed', 'favor_unclaimed', 'favor_completed',
                        'completion_reminder', 'qa_activity', 'qa_question', 'qa_answer',
                        'review_request', 'review_reminder', 'review_received'
                    ) and bp.favor_id is not null
                        then 'favor:' || bp.favor_id::text
                    else 'notification:' || bp.id::text
                end as group_key,
                bool_or(bp.read = false) as has_unread
            from cd_bell_pruned bp
            where bp.community_id is not null
            group by 1, 2
        ),
        cd_bell as (
            select bg.community_id, count(*)::int as cnt
            from cd_bell_groups bg
            where bg.has_unread
            group by bg.community_id
        ),
        cd_ids as (
            select community_id from cd_requests
            union select community_id from cd_community
            union select community_id from cd_bell
        )
        select coalesce(jsonb_agg(jsonb_build_object(
            'community_id', i.community_id,
            'requests_total', coalesce(rq.cnt, 0),
            'community_total', coalesce(cm.cnt, 0),
            'bell_total', coalesce(bl.cnt, 0)
        ) order by i.community_id), '[]'::jsonb)
        into v_community_details
        from cd_ids i
        left join cd_requests rq on rq.community_id = i.community_id
        left join cd_community cm on cm.community_id = i.community_id
        left join cd_bell bl on bl.community_id = i.community_id;
    end if;

    return jsonb_build_object(
        'user_id', v_user_id,
        'messages_total', coalesce(v_messages_total, 0),
        'requests_total', coalesce(v_requests_total, 0),
        'community_total', coalesce(v_community_total, 0),
        'bell_total', coalesce(v_bell_total, 0),
        'request_details', coalesce(v_request_details, '[]'::jsonb),
        'conversation_details', coalesce(v_conversation_details, '[]'::jsonb),
        'pending_members_total', coalesce(v_pending_members_total, 0),
        'community_details', coalesce(v_community_details, '[]'::jsonb),
        'total', coalesce(v_requests_total, 0) + coalesce(v_messages_total, 0) + coalesce(v_community_total, 0)
    );
end;
$function$;
