-- 20261019_0002_broadcast_push.sql
--
-- NOT APPLIED. GATED (decision A5 point 2): apply only after the owner confirms from App Store Connect that no
-- pre-community build remains in use. Phase 4 of the multi-community design (spec §4 "Phase 4", D13: "a real
-- broadcast push honouring canBeDisabled = false and the community mute, routed to Announcements, replacing the
-- Town Hall side door").
--
-- What it does.
--   * send_community_broadcast (block 2, edited in place from the live body, md5(prosrc)
--     b49920cb7b9aacbb0a5b0bc9cf85f864, which is 20261018_0002 block 10): every recipient of the bell row (active,
--     unbanned, not muted, not the sender: the loop is unchanged) also gets one immediate push of the announcement's
--     type (broadcast by default) through queue_push_notification, with community_id, town_hall_post_id and (added by
--     queue_push_notification) notification_id; the title and body are cut to 100 and 180 characters for APNs.
--     should_notify_user answers true for the three announcement types whatever the person's preferences, so
--     canBeDisabled == false holds; the community mute holds because the loop already skips muted members. The
--     announcement's Town Hall post is inserted with the transaction-local setting naars.broadcast_post = '1', reset
--     right after.
--   * notify_town_hall_post (block 1, edited in place from the live body, md5(prosrc)
--     5c5d85a295dd292f6a92f73f2bfa2ce0, which is 20261017_0003): returns at once for a post typed 'announcement'
--     inserted while naars.broadcast_post = '1', so the announcement no longer also produces a "New in Town Hall"
--     bell row and batched push (the side door). Every other post, including an 'announcement'-typed row a member
--     inserts directly (20261018_0002 D-S8), is notified exactly as before.
--   * The cap, the rate of announcements and the bell rows are unchanged. send_broadcast_notifications (the
--     installed admin build's wrapper) calls send_community_broadcast and therefore pushes too.
--
-- Apply. After 20261019_0001. Supabase MCP apply_migration, one block per call, block 1 before block 2 (block 2's
-- setting is harmless without block 1, but then both pushes would go out). Before each block compare md5(prosrc)
-- with the value above; stop on a mismatch. No block removes rows, drops a policy, or writes to auth.* / storage.*.
--
-- Verification. Dry run (with 20261019_0001 and 20261019_0003) and probe broadcast_push and broadcast_cap
-- (supabase/probes/communities_probe.sql). Outcomes: not yet run.
--
-- What old clients see (why it is gated). The installed pre-community build's members stop receiving the "New in
-- Town Hall" bell row and batched push for an announcement; instead each receives one push of type broadcast with
-- the announcement's own title and body, also when Town Hall notifications are off. The installed build routes a
-- broadcast push to its Announcements list (DeepLinkParser on main), so nothing breaks, but what it receives
-- changes. Phase 1-4 builds route it to Announcements (NaarsCars/Core/Utilities/DeepLinkParser.swift:162-165).
--
-- Rollback, in reverse order: send_community_broadcast from 20261018_0002 block 10; notify_town_hall_post from
-- 20261017_0003.


-- ============================================================================================
-- BLOCK 1: public.notify_town_hall_post()   live md5(prosrc) 5c5d85a295dd292f6a92f73f2bfa2ce0 (20261017_0003)
-- Change: the early return for an announcement written by send_community_broadcast. Everything else is the live body.
-- ============================================================================================
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
    -- send_community_broadcast sends this announcement's own push (20261019_0002 block 2); the Town Hall notice
    -- would be a second, batched one. The setting is transaction-local and set only around that one insert.
    IF NEW.type = 'announcement'
       AND coalesce(current_setting('naars.broadcast_post', true), '') = '1' THEN
        RETURN NEW;
    END IF;

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


-- ============================================================================================
-- BLOCK 2: public.send_community_broadcast(uuid, text, text, boolean, text)
--          live md5(prosrc) b49920cb7b9aacbb0a5b0bc9cf85f864 (20261018_0002 block 10)
-- Changes: naars.broadcast_post around the post insert; one queue_push_notification per bell row. Everything else
-- (the 42501 / 22023 / P0001 refusals, the advisory lock, the D14 cap, the recipients) is the live body.
-- ============================================================================================
create or replace function public.send_community_broadcast(
    p_community_id uuid,
    p_title text,
    p_body text,
    p_pinned boolean,
    p_type text default 'broadcast'
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
    v_type text;
begin
    if v_uid is null then
        raise exception 'Only admins can send broadcast notifications' using errcode = '42501';
    end if;

    -- Deviation 4 of 20261017_0003 (owner decision 2026-10-17): the type is passed through, limited to the three
    -- announcement types should_notify_user already accepts.
    v_type := coalesce(nullif(btrim(p_type), ''), 'broadcast');
    if v_type not in ('broadcast', 'admin_announcement', 'announcement') then
        raise exception 'Unsupported announcement type' using errcode = '22023';
    end if;

    if p_community_id is null or not public.is_community_admin(p_community_id) then
        raise exception 'Only admins of this community can send announcements' using errcode = '42501';
    end if;

    perform pg_advisory_xact_lock(hashtextextended('community_broadcast:' || p_community_id::text, 0));

    -- D14: at most 3 announcements per community in any 24 hours, for every sender (Phase 3). Only announcements
    -- by a platform admin or by this community's owners and admins count: a member can write a row typed
    -- 'announcement' through the insert policy, and must not be able to use up the community's cap.
    if (select count(*)
          from public.town_hall_posts t
          left join public.profiles a on a.id = t.user_id
         where t.community_id = p_community_id
           and t.type = 'announcement'
           and t.created_at > now() - interval '24 hours'
           and (coalesce(a.is_admin, false) or public.is_community_staff(p_community_id, t.user_id))) >= 3 then
        raise exception 'This community has already sent 3 announcements today' using errcode = 'P0001';
    end if;

    -- The announcement has its own push below: notify_town_hall_post skips this one post (20261019_0002 block 1).
    perform set_config('naars.broadcast_post', '1', true);
    insert into public.town_hall_posts (
        user_id, title, content, pinned, type, community_id, created_at, updated_at
    ) values (
        v_uid, p_title, p_body, coalesce(p_pinned, false), 'announcement', p_community_id, now(), now()
    )
    returning id into v_post_id;
    perform set_config('naars.broadcast_post', '', true);

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
            v_member.user_id, v_type, p_title, p_body,
            null, null, null, null, v_post_id, v_uid, coalesce(p_pinned, false)
        );
        if v_notification_id is not null then
            v_inserted_count := v_inserted_count + 1;
            -- D13: one immediate push per bell row (no batch key). should_notify_user is true for the three
            -- announcement types whatever the preferences (canBeDisabled == false); the mute is the loop's.
            perform public.queue_push_notification(
                v_member.user_id, v_type, left(p_title, 100), left(p_body, 180),
                jsonb_build_object('community_id', p_community_id::text, 'town_hall_post_id', v_post_id::text),
                null, v_notification_id
            );
        end if;
    end loop;

    return v_inserted_count;
end;
$function$;
