-- 20261018_0001_community_moderation.sql
--
-- APPLIED 2026-10-18 (Supabase MCP apply_migration, one block per call, as 20261018_0001_block_1 .. _8;
-- migration-history versions 20261019024747, 024934, 025138, 025252, 025427, 025517, 025621, 025758 UTC).
-- Outcomes are under "Verification" below. Phase 3 of the multi-community design (Docs/superpowers/specs/2026-10-07-multi-community-design.md
-- §4 "Phase 3", §3.5 "Reporter privacy for community admins (INV-P2)", §3.4 last row, §2.1 rule 10, D27), under the
-- owner's decisions (Docs/superpowers/specs/2026-10-17-multi-community-decisions.md, which wins where they differ).
--
-- What it does.
--   * reports.community_status / community_reviewed_at (new nullable columns): the community's own
--     decision on a report (action_taken after a community hide, dismissed after a community dismissal). A community
--     admin never writes status / reviewed_at / reviewed_by, so every report stays in the platform admins' pending
--     queue until a platform admin reviews it (spec §2.1 rule 10 "every report always reaches the platform admins";
--     the plan's D-S7).
--   * is_community_staff (new, internal): is this user an active owner or admin of this community. The INV-P2
--     rule (3) test shared by handle_new_report, get_community_reports and moderate_community_content. It is not
--     caller-bound, so it is revoked from every client role (like community_of_request, 20261017_0001).
--   * handle_new_report (edited in place from the live body, md5(prosrc) a470284db164ca45c1eaa23a4cd32cd6, which is
--     20261017_0003 call 10): a report that carries reports.community_id (content in a community, or a person report
--     between two people who share exactly one, derive_report_community) now also reaches that community's active,
--     unbanned owners and admins, under INV-P2: (1) their bell row has source_user_id null and their push carries
--     community_id and no reporter; (2) the reporter, the reported person and the content's author are never among
--     them; (3) when the reported person or the author is an owner or admin of that community, no admin of it is
--     told (platform admins handle it); (4) no table policy on reports (none is added anywhere). Platform admins are
--     left out of the community loop: they keep exactly today's row (with the reporter) and push. The auto-hide
--     threshold (3 distinct reporters) and the community-report branch are unchanged.
--   * get_community_reports (new): community admin (is_community_admin: the community's owners and admins, and
--     platform admins). The rows of admin_get_reports for reports.community_id = the community, without reporter_id
--     and reporter_name, without any report whose reported person or author is the caller or one of the community's
--     owners and admins, plus author_id / author_name and two flags: platform_handled (a platform admin reviewed it)
--     and can_restore (the caller may restore the hidden content). `status` is the platform status once a platform
--     admin reviewed the report, else community_status, else 'pending'. Message and community reports never carry a
--     community, so they never appear. {success:false, error} for anyone else (no rows are ever returned to them).
--   * moderate_community_content (new): hide / restore / dismiss for posts, comments, rides and favors, dismiss only
--     for a person report, by an admin of the report's community; refused for any report the caller could not see in
--     get_community_reports. Platform moderation wins for a caller who is not a platform admin: no hide or dismiss on
--     a report a platform admin reviewed, no hide of content that is already hidden, and restore only of content the
--     caller or another (non-platform-admin) owner or admin of the community hid, never a platform admin's hide or
--     the 3-reporter auto-hide. Effects: the hidden_* columns, reports.content_hidden, community_status /
--     community_reviewed_at (never status / reviewed_*), one content_moderation_events row with acted_by, and on hide
--     the author's content_hidden notice.
--   * town_hall_posts DELETE policy: the community's admins may remove posts in it, except posts written by that
--     community's owners and admins (deliberate, INV-P2 rule 3; see the plan's D-S2). No client path removes a post
--     as an admin; hiding is the moderation action.
--   * Carry-over from the Phase 2 gate (blocks 6-8, not in spec §4 Phase 3; the plan's D-S1): admin_get_reports
--     returns a community report as target_type 'community' with the community's name as content_preview, and
--     admin_moderate_content dismisses one; content_moderation_events accepts target_type 'community'. Platform
--     admins only; signatures and returned columns unchanged.
--
-- Not in this file: the statistics functions and the broadcast cap (20261018_0002); the user_rejected and
-- account_restricted producers, live since 20261017_0005 blocks 21-22; no new notification type (both values pass
-- the live notifications.type CHECK, read 2026-10-18).
--
-- Apply. Supabase MCP apply_migration, one block per call, in order (block 1 before 2-4, which call it). Before each
-- CREATE OR REPLACE of an existing function compare md5(prosrc) with the value written above it; stop on a mismatch.
-- No block removes rows, drops a policy, or writes to auth.* / storage.*. Block 5 names a policy
-- whose name contains "delete" and block 6 drops and re-adds a CHECK constraint: if the MCP declines either, run
-- that block in the SQL editor (owner).
--
-- Verification. Dry run: blocks 1-8 in one begin; ... rollback; with the probe blocks community_moderation,
-- admin_community_reports and short
-- (supabase/probes/communities_probe.sql; each block's begin / rollback turned into a savepoint and a rollback to it)
-- and a before/after snapshot of admin_get_reports(<platform admin>, null),
-- identical except community reports (target 'community', the name as preview). Then short after each block, and
-- community_moderation and admin_community_reports after block 8; posts_delete_policy is an owner step in the SQL
-- editor (it holds DELETE statements).
-- Outcomes (2026-10-18): preconditions passed (P1: the live md5(prosrc) of handle_new_report, admin_get_reports and
-- admin_moderate_content matched the values in the plan; P2: notifications.type's CHECK holds both values; P3: none
-- of the new names existed); the gate before block 2 found 0 owners or admins who are not platform admins. The dry
-- run (blocks 1-8 with community_moderation, admin_community_reports and short, one rolled-back transaction) passed
-- and the platform admin's admin_get_reports digest was unchanged. The MCP accepted blocks 5 and 6. After each
-- block: short passed (rolled back) and the deployed md5(prosrc) equalled the md5 of the block's body:
-- is_community_staff e810ba35c816c463f58496e0e4e1fb5f, handle_new_report de0d0dae37ae48e6a52cd2f50a05a66d,
-- get_community_reports 7c85e31db1ffe89405fd384acc866e04, moderate_community_content 8f0218c330e68832bfc69e8c5845a409,
-- admin_get_reports bd3199058f643c92a840e223577b6df9, admin_moderate_content 02b2b1ac5ca23110d22b36d8bc2887aa;
-- EXECUTE: is_community_staff none of anon / authenticated, the others authenticated only. community_moderation
-- and admin_community_reports passed after block 8 and again after 20261018_0002 block 10, each rolled back, and no
-- probe account, community, post, ride, report, moderation event or notification was left behind.
-- posts_delete_policy was run by the owner in the Supabase SQL editor on 2026-10-18 (rolled back) and passed, so
-- every Phase 3 probe block has now passed against the live project.
--
-- What old clients see. Installed build: platform admins get the same rows and pushes as before, and a report a
-- community admin hid or dismissed is still pending in Admin → Reports; one whose content a community admin hid
-- carries the existing "Auto-hidden" label there (the installed build labels every hidden pending report so) and
-- offers Hide and Restore. A community admin's
-- installed-build device that taps a content_reported push lands on the platform reports screen's permission error
-- (spec §4 Phase 3); the Phase 2 build does the same until the Phase 3 client is installed. In Admin → Reports a
-- community report now reads its community's name; the installed build labels it "User" and offers Hide (refused
-- with the server's text) and Dismiss (works); the Phase 2 build with the [P2-fix] client labels it Community and
-- offers Dismiss.
--
-- Rollback, in reverse order: admin_moderate_content and admin_get_reports from
-- 20260403_0011_content_moderation_redesign.sql:460-787 and :311-458; the CHECK without 'community' (only while no
-- event row has target_type 'community': the log is append-only, so after a community dismissal the wider CHECK
-- stays); the policy from 20261017_0000_communities_live_bodies_snapshot.sql:2181-2184; handle_new_report from
-- 20261017_0003 call 10 (:684-880); then drop moderate_community_content, get_community_reports and
-- is_community_staff; last, the two reports columns and their CHECK (the community's decisions are then lost; the
-- platform queue never depended on them).


-- ============================================================================================
-- BLOCK 1: the community's own decision on a report (two columns on public.reports), and
--          public.is_community_staff(uuid, uuid)  (internal)
-- A community admin's hide or dismiss is written to community_status / community_reviewed_at, never to status /
-- reviewed_at / reviewed_by, which stay the platform admins' queue (D-S7): a report stays pending for the platform
-- admins until one of them reviews it, whatever the community decided. Nullable, no default: every existing row
-- reads "no community decision". No client reads public.reports directly (20261005_0022), and reports has no client
-- UPDATE path, so only moderate_community_content writes them.
-- is_community_staff: true when p_user_id is an active owner or admin of p_community_id. Null arguments answer false.
-- ============================================================================================
alter table public.reports
  add column if not exists community_status text,
  add column if not exists community_reviewed_at timestamptz,
  add constraint reports_community_status_check
    check (community_status is null or community_status in ('action_taken', 'dismissed'));

create or replace function public.is_community_staff(p_community_id uuid, p_user_id uuid)
returns boolean
language sql
stable
security definer
set search_path = ''
as $$
  select p_community_id is not null
     and p_user_id is not null
     and exists (select 1 from public.community_members m
                  where m.community_id = p_community_id
                    and m.user_id = p_user_id
                    and m.status = 'active'
                    and m.role in ('owner', 'admin'));
$$;

revoke all on function public.is_community_staff(uuid, uuid) from public, anon, authenticated;


-- ============================================================================================
-- BLOCK 2: public.handle_new_report()   live md5(prosrc) a470284db164ca45c1eaa23a4cd32cd6 (20261017_0003 call 10)
-- Changes: v_author_id is read with each content preview; the community-admin loop after the platform loop.
-- Everything else is the live body.
-- ============================================================================================
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
    v_cadmin RECORD;
    v_notification_id UUID;
    v_body TEXT;
    v_target_type TEXT;
    v_conversation_id UUID;
    v_town_hall_post_id UUID;
    v_author_id UUID;
BEGIN
    IF NEW.reported_post_id IS NOT NULL THEN
        v_target_type := 'town_hall_post';

        SELECT COUNT(DISTINCT r.reporter_id)::INT
        INTO v_report_count
        FROM public.reports r
        WHERE r.reported_post_id = NEW.reported_post_id;

        SELECT LEFT(p.content, 80), p.id, p.user_id
        INTO v_content_preview, v_town_hall_post_id, v_author_id
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
                    target_type, target_id, report_id, action, acted_by, reason
                )
                VALUES (
                    'town_hall_post', NEW.reported_post_id, NEW.id, 'auto_hide', NULL, NULL
                );
            END IF;
        END IF;
    ELSIF NEW.reported_comment_id IS NOT NULL THEN
        v_target_type := 'town_hall_comment';

        SELECT COUNT(DISTINCT r.reporter_id)::INT
        INTO v_report_count
        FROM public.reports r
        WHERE r.reported_comment_id = NEW.reported_comment_id;

        SELECT LEFT(c.content, 80), c.post_id, c.user_id
        INTO v_content_preview, v_town_hall_post_id, v_author_id
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
                    target_type, target_id, report_id, action, acted_by, reason
                )
                VALUES (
                    'town_hall_comment', NEW.reported_comment_id, NEW.id, 'auto_hide', NULL, NULL
                );
            END IF;
        END IF;
    ELSIF NEW.reported_message_id IS NOT NULL THEN
        v_target_type := 'message';

        SELECT LEFT(m.text, 80), m.conversation_id, m.from_id
        INTO v_content_preview, v_conversation_id, v_author_id
        FROM public.messages m
        WHERE m.id = NEW.reported_message_id;
    ELSIF NEW.reported_ride_id IS NOT NULL THEN
        v_target_type := 'ride';

        SELECT LEFT(CONCAT_WS(' -> ', r.pickup, r.destination), 80), r.user_id
        INTO v_content_preview, v_author_id
        FROM public.rides r
        WHERE r.id = NEW.reported_ride_id;
    ELSIF NEW.reported_favor_id IS NOT NULL THEN
        v_target_type := 'favor';

        SELECT LEFT(CONCAT_WS(': ', f.title, NULLIF(f.description, '')), 80), f.user_id
        INTO v_content_preview, v_author_id
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

    -- Platform admins: unchanged (every report, with the reporter as source_user_id).
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

    -- Phase 3 (INV-P2, D27): the active owners and admins of the report's community. Only content in a community,
    -- or a person report between two people who share exactly one, carries community_id (derive_report_community);
    -- message and community reports have none and stay with the platform admins.
    IF NEW.community_id IS NOT NULL
       AND NOT public.is_community_staff(NEW.community_id, NEW.reported_user_id)
       AND NOT public.is_community_staff(NEW.community_id, v_author_id) THEN
        FOR v_cadmin IN
            SELECT m.user_id
            FROM public.community_members m
            JOIN public.profiles p ON p.id = m.user_id
            JOIN public.communities c ON c.id = m.community_id AND c.archived_at IS NULL
            WHERE m.community_id = NEW.community_id
              AND m.status = 'active'
              AND m.role IN ('owner', 'admin')
              AND NOT COALESCE(p.is_banned, false)
              AND NOT COALESCE(p.is_admin, false)            -- already told above, with the reporter
              AND m.user_id <> NEW.reporter_id               -- INV-P2 (2)
              AND m.user_id IS DISTINCT FROM NEW.reported_user_id
              AND m.user_id IS DISTINCT FROM v_author_id
        LOOP
            v_notification_id := public.create_notification(
                v_cadmin.user_id,
                'content_reported',
                'Content Reported',
                v_body,
                NEW.reported_ride_id,
                NEW.reported_favor_id,
                NULL,
                NULL,
                v_town_hall_post_id,
                NULL                                         -- INV-P2 (1): no source user for a community admin
            );

            IF v_notification_id IS NOT NULL THEN
                -- a person report carries no entity the derive trigger could read the community from
                UPDATE public.notifications SET community_id = NEW.community_id
                 WHERE id = v_notification_id AND community_id IS NULL;

                PERFORM public.queue_push_notification(
                    v_cadmin.user_id,
                    'content_reported',
                    'Content Reported',
                    v_body,
                    jsonb_strip_nulls(jsonb_build_object(
                        'report_id', NEW.id::TEXT,
                        'target_type', v_target_type,
                        'community_id', NEW.community_id::TEXT,
                        'reported_user_id', NEW.reported_user_id::TEXT,
                        'reported_post_id', NEW.reported_post_id::TEXT,
                        'reported_comment_id', NEW.reported_comment_id::TEXT,
                        'reported_ride_id', NEW.reported_ride_id::TEXT,
                        'reported_favor_id', NEW.reported_favor_id::TEXT,
                        'ride_id', NEW.reported_ride_id::TEXT,
                        'favor_id', NEW.reported_favor_id::TEXT,
                        'town_hall_post_id', v_town_hall_post_id::TEXT
                    )),
                    NULL,
                    v_notification_id
                );
            END IF;
        END LOOP;
    END IF;

    RETURN NEW;
END;
$function$;

revoke all on function public.handle_new_report() from public, anon, authenticated;


-- ============================================================================================
-- BLOCK 3: public.get_community_reports(uuid, text)
-- Community admin. The community's reports without the reporter (INV-P2), without reports about the caller or about
-- the community's owners and admins. The ride and favor previews use NULLIF(CONCAT_WS(...), '') because CONCAT_WS of
-- two nulls is '' (not null), which would stop the COALESCE before a person report's name.
-- `status` is the community's view: the platform status once a platform admin has reviewed the report, else the
-- community's own decision (block 1), else 'pending'; p_status filters on it. Two flags per row tell the client what
-- the caller may still do (block 4 enforces the same rules): platform_handled (a platform admin reviewed it: no hide,
-- no dismiss) and can_restore (the content is hidden and the caller may restore it: they hid it, or another active
-- owner or admin of this community who is not a platform admin did; never a platform admin's hide or the 3-reporter
-- auto-hide, whose hidden_by is null). A platform-admin caller is never platform_handled and may always restore,
-- because admin_moderate_content already gives them both.
-- ============================================================================================
create or replace function public.get_community_reports(p_community_id uuid, p_status text default null)
returns jsonb
language plpgsql
stable
security definer
set search_path = ''
as $$
declare
  v_uid uuid := (select auth.uid());
  v_is_platform boolean := public.is_platform_admin();
  v_reports jsonb;
begin
  if v_uid is null or p_community_id is null or not public.is_community_admin(p_community_id) then
    return jsonb_build_object('success', false, 'error', 'Only this community''s admins can see its reports');
  end if;
  if p_status is not null and p_status not in ('pending', 'reviewed', 'action_taken', 'dismissed') then
    return jsonb_build_object('success', false, 'error', 'Unknown report status');
  end if;

  with enriched as (
    select r.id as report_id,
           case when r.reported_post_id    is not null then 'town_hall_post'
                when r.reported_comment_id is not null then 'town_hall_comment'
                when r.reported_ride_id    is not null then 'ride'
                when r.reported_favor_id   is not null then 'favor'
                else 'user' end as target_type,
           coalesce(r.reported_post_id, r.reported_comment_id, r.reported_ride_id,
                    r.reported_favor_id, r.reported_user_id) as target_id,
           r.reported_user_id,
           ru.name as reported_user_name,
           coalesce(post.user_id, cmt.user_id, ride.user_id, fav.user_id) as author_id,
           r.reported_post_id,
           r.reported_comment_id,
           r.reported_ride_id,
           r.reported_favor_id,
           coalesce(post.id, cmt.post_id) as town_hall_post_id,
           r.report_type,
           r.description,
           r.status as platform_status,
           case when r.status <> 'pending' then r.status
                else coalesce(r.community_status, 'pending') end as status,
           r.created_at,
           case when r.status <> 'pending' then r.reviewed_at
                else r.community_reviewed_at end as reviewed_at,
           coalesce(post.hidden_by, cmt.hidden_by, ride.hidden_by, fav.hidden_by) as hidden_by,
           coalesce(left(post.content, 200),
                    left(cmt.content, 200),
                    left(nullif(concat_ws(' -> ', ride.pickup, ride.destination), ''), 200),
                    left(nullif(concat_ws(': ', fav.title, nullif(fav.description, '')), ''), 200),
                    ru.name) as content_preview,
           case when r.reported_post_id    is not null then post.hidden_at is not null
                when r.reported_comment_id is not null then cmt.hidden_at is not null
                when r.reported_ride_id    is not null then ride.hidden_at is not null
                when r.reported_favor_id   is not null then fav.hidden_at is not null
                else false end as content_hidden
      from public.reports r
      left join public.profiles ru            on ru.id   = r.reported_user_id
      left join public.town_hall_posts post   on post.id = r.reported_post_id
      left join public.town_hall_comments cmt on cmt.id  = r.reported_comment_id
      left join public.rides ride             on ride.id = r.reported_ride_id
      left join public.favors fav             on fav.id  = r.reported_favor_id
     where r.community_id = p_community_id
       and r.reported_message_id is null
       and r.reported_community_id is null
  ),
  visible as (
    select e.*, ap.name as author_name,
           (not v_is_platform and e.platform_status <> 'pending') as platform_handled,
           (e.content_hidden
            and (v_is_platform
                 or coalesce(e.hidden_by = v_uid, false)
                 or (e.hidden_by is not null
                     and public.is_community_staff(p_community_id, e.hidden_by)
                     and not coalesce(hb.is_admin, false)))) as can_restore
      from enriched e
      left join public.profiles ap on ap.id = e.author_id
      left join public.profiles hb on hb.id = e.hidden_by
     where v_uid is distinct from e.reported_user_id                       -- INV-P2 (2): never about the caller
       and v_uid is distinct from e.author_id
       and not public.is_community_staff(p_community_id, e.reported_user_id)  -- INV-P2 (3)
       and not public.is_community_staff(p_community_id, e.author_id)
  ),
  grouped as (
    select v.target_type, v.target_id, count(*)::int as report_count
      from visible v
     group by v.target_type, v.target_id
  )
  select coalesce(jsonb_agg(jsonb_build_object(
           'report_id',           v.report_id,
           'target_type',         v.target_type,
           'reported_user_id',    v.reported_user_id,
           'reported_user_name',  v.reported_user_name,
           'author_id',           v.author_id,
           'author_name',         v.author_name,
           'reported_post_id',    v.reported_post_id,
           'reported_comment_id', v.reported_comment_id,
           'reported_ride_id',    v.reported_ride_id,
           'reported_favor_id',   v.reported_favor_id,
           'town_hall_post_id',   v.town_hall_post_id,
           'report_type',         v.report_type,
           'description',         v.description,
           'status',              v.status,
           'created_at',          v.created_at,
           'reviewed_at',         v.reviewed_at,
           'content_preview',     v.content_preview,
           'content_hidden',      v.content_hidden,
           'can_restore',         v.can_restore,
           'platform_handled',    v.platform_handled,
           'report_count',        g.report_count
         ) order by v.created_at desc, v.report_id), '[]'::jsonb)
    into v_reports
    from visible v
    join grouped g on g.target_type = v.target_type and g.target_id is not distinct from v.target_id
   where p_status is null or v.status = p_status;

  return jsonb_build_object('success', true, 'reports', v_reports);
end
$$;

revoke all on function public.get_community_reports(uuid, text) from public, anon;
grant execute on function public.get_community_reports(uuid, text) to authenticated;


-- ============================================================================================
-- BLOCK 4: public.moderate_community_content(uuid, text, text)
-- Community admin of the report's community. hide (reason required) / restore / dismiss for a post, comment, ride or
-- favor report; dismiss only for a person report. One refusal text for "no such report", "not your community", a
-- message report and a community report (no oracle). Refused for reports about the caller or about the community's
-- owners and admins (INV-P2; platform admins handle those through admin_moderate_content).
-- Platform moderation wins (spec §2.1 rule 10, §5; App Store 1.2), for a caller who is not a platform admin:
--   * hide and dismiss are refused on a report a platform admin has reviewed (status <> 'pending'; after this file
--     only admin_moderate_content moves reports.status, and it sets reviewed_by to that platform admin);
--   * hide is refused on content that is already hidden, so a community admin can never overwrite a platform admin's
--     or the auto-hide's hidden_by and then restore it;
--   * restore is allowed only when the caller hid the content, or another active owner or admin of this community who
--     is not a platform admin did; never after a platform admin's hide or the 3-reporter auto-hide (hidden_by null);
--   * the community's decision goes to community_status / community_reviewed_at (block 1), never to status /
--     reviewed_at / reviewed_by, so the report stays in the platform admins' pending queue (D-S7).
-- A platform-admin caller passes the three precedence checks (admin_moderate_content already gives them those powers)
-- but not the INV-P2 exclusions (D-S5). The content row is locked before it is read, so two hides cannot race.
-- Refusal codes: platform_handled, already_hidden, not_hidden, platform_hidden, already_closed (this client build does
-- not know them and reads them as a refusal without a code).
-- ============================================================================================
create or replace function public.moderate_community_content(
  p_report_id uuid,
  p_action text,
  p_reason text default null
)
returns jsonb
language plpgsql
security definer
set search_path = ''
as $$
declare
  v_uid uuid := (select auth.uid());
  v_is_platform boolean := public.is_platform_admin();
  v_report public.reports%rowtype;
  v_target_type text;
  v_target_id uuid;
  v_author_id uuid;
  v_post_id uuid;
  v_hidden boolean := false;
  v_hidden_by uuid;
  v_reason text := left(nullif(btrim(coalesce(p_reason, '')), ''), 500);
begin
  if v_uid is null then
    return jsonb_build_object('success', false, 'error', 'Sign in first');
  end if;
  if p_action is null or p_action not in ('hide', 'restore', 'dismiss') then
    return jsonb_build_object('success', false, 'error', 'Unknown moderation action');
  end if;

  select * into v_report from public.reports r where r.id = p_report_id for update;
  if not found
     or v_report.community_id is null
     or v_report.reported_message_id is not null
     or v_report.reported_community_id is not null
     or not public.is_community_admin(v_report.community_id) then
    return jsonb_build_object('success', false, 'error', 'Only this community''s admins can act on this report');
  end if;

  v_target_type := case when v_report.reported_post_id    is not null then 'town_hall_post'
                        when v_report.reported_comment_id is not null then 'town_hall_comment'
                        when v_report.reported_ride_id    is not null then 'ride'
                        when v_report.reported_favor_id   is not null then 'favor'
                        else 'user' end;
  v_target_id := coalesce(v_report.reported_post_id, v_report.reported_comment_id, v_report.reported_ride_id,
                          v_report.reported_favor_id, v_report.reported_user_id);

  case v_target_type
    when 'town_hall_post' then
      select p.user_id, p.id, p.hidden_at is not null, p.hidden_by
        into v_author_id, v_post_id, v_hidden, v_hidden_by
        from public.town_hall_posts p where p.id = v_target_id for update;
    when 'town_hall_comment' then
      select c.user_id, c.post_id, c.hidden_at is not null, c.hidden_by
        into v_author_id, v_post_id, v_hidden, v_hidden_by
        from public.town_hall_comments c where c.id = v_target_id for update;
    when 'ride' then
      select r.user_id, r.hidden_at is not null, r.hidden_by
        into v_author_id, v_hidden, v_hidden_by
        from public.rides r where r.id = v_target_id for update;
    when 'favor' then
      select f.user_id, f.hidden_at is not null, f.hidden_by
        into v_author_id, v_hidden, v_hidden_by
        from public.favors f where f.id = v_target_id for update;
    else
      v_author_id := null;
      v_hidden := coalesce(v_report.content_hidden, false);
      v_hidden_by := null;
  end case;

  -- INV-P2: never about the caller, never about the community's owners and admins
  if v_uid is not distinct from v_report.reported_user_id
     or v_uid is not distinct from v_author_id
     or public.is_community_staff(v_report.community_id, v_report.reported_user_id)
     or public.is_community_staff(v_report.community_id, v_author_id) then
    return jsonb_build_object('success', false, 'error', 'Platform moderators handle this report');
  end if;

  -- Platform moderation wins: a report a platform admin has reviewed is closed to hide and dismiss here
  if p_action in ('hide', 'dismiss') and not v_is_platform and v_report.status <> 'pending' then
    return jsonb_build_object('success', false,
      'error', 'Platform moderators have already handled this report', 'code', 'platform_handled');
  end if;

  if v_target_type = 'user' and p_action <> 'dismiss' then
    return jsonb_build_object('success', false,
      'error', 'A report about a person can only be dismissed. Remove the member instead.');
  end if;
  if p_action <> 'dismiss' and v_author_id is null then
    return jsonb_build_object('success', false, 'error', 'This content no longer exists');
  end if;
  if p_action = 'hide' and v_reason is null then
    return jsonb_build_object('success', false, 'error', 'Say why you are hiding it');
  end if;
  if p_action = 'hide' and v_hidden then
    return jsonb_build_object('success', false, 'error', 'This content is already hidden', 'code', 'already_hidden');
  end if;
  if p_action = 'restore' then
    if not v_hidden then
      return jsonb_build_object('success', false, 'error', 'This content is not hidden', 'code', 'not_hidden');
    end if;
    -- the same rule as get_community_reports' can_restore (block 3)
    if not (v_is_platform
            or coalesce(v_hidden_by = v_uid, false)
            or (v_hidden_by is not null
                and public.is_community_staff(v_report.community_id, v_hidden_by)
                and not exists (select 1 from public.profiles pa where pa.id = v_hidden_by and pa.is_admin))) then
      return jsonb_build_object('success', false,
        'error', 'Platform moderators hid this content. Only they can restore it.', 'code', 'platform_hidden');
    end if;
  end if;
  if p_action = 'dismiss' and v_report.community_status is not null then
    return jsonb_build_object('success', false, 'error', 'This report is already closed', 'code', 'already_closed');
  end if;

  if p_action = 'hide' then
    case v_target_type
      when 'town_hall_post' then
        update public.town_hall_posts
           set hidden_at = now(), hidden_by = v_uid, hidden_reason = v_reason
         where id = v_target_id and hidden_at is null;
      when 'town_hall_comment' then
        update public.town_hall_comments
           set hidden_at = now(), hidden_by = v_uid, hidden_reason = v_reason
         where id = v_target_id and hidden_at is null;
      when 'ride' then
        update public.rides
           set hidden_at = now(), hidden_by = v_uid, hidden_reason = v_reason
         where id = v_target_id and hidden_at is null;
      when 'favor' then
        update public.favors
           set hidden_at = now(), hidden_by = v_uid, hidden_reason = v_reason
         where id = v_target_id and hidden_at is null;
    end case;

    update public.reports
       set content_hidden = true
     where (v_target_type = 'town_hall_post'    and reported_post_id    = v_target_id)
        or (v_target_type = 'town_hall_comment' and reported_comment_id = v_target_id)
        or (v_target_type = 'ride'              and reported_ride_id    = v_target_id)
        or (v_target_type = 'favor'             and reported_favor_id   = v_target_id);

    -- the community's decision: this report, and the other reports on the same content that neither the platform
    -- admins nor the community have decided yet. status / reviewed_* are left to the platform admins.
    update public.reports
       set community_status = 'action_taken', community_reviewed_at = now()
     where ((v_target_type = 'town_hall_post'    and reported_post_id    = v_target_id)
         or (v_target_type = 'town_hall_comment' and reported_comment_id = v_target_id)
         or (v_target_type = 'ride'              and reported_ride_id    = v_target_id)
         or (v_target_type = 'favor'             and reported_favor_id   = v_target_id))
       and (id = v_report.id or (status = 'pending' and community_status is null));

    insert into public.content_moderation_events (target_type, target_id, report_id, action, acted_by, reason)
    values (v_target_type, v_target_id, v_report.id, 'hide', v_uid, v_reason);

    perform public.create_content_hidden_notification(
      v_author_id, v_reason, null::uuid, v_post_id,
      case when v_target_type = 'ride'  then v_target_id end,
      case when v_target_type = 'favor' then v_target_id end);

  elsif p_action = 'restore' then
    case v_target_type
      when 'town_hall_post' then
        update public.town_hall_posts set hidden_at = null, hidden_by = null, hidden_reason = null where id = v_target_id;
      when 'town_hall_comment' then
        update public.town_hall_comments set hidden_at = null, hidden_by = null, hidden_reason = null where id = v_target_id;
      when 'ride' then
        update public.rides set hidden_at = null, hidden_by = null, hidden_reason = null where id = v_target_id;
      when 'favor' then
        update public.favors set hidden_at = null, hidden_by = null, hidden_reason = null where id = v_target_id;
    end case;

    update public.reports
       set content_hidden = false
     where (v_target_type = 'town_hall_post'    and reported_post_id    = v_target_id)
        or (v_target_type = 'town_hall_comment' and reported_comment_id = v_target_id)
        or (v_target_type = 'ride'              and reported_ride_id    = v_target_id)
        or (v_target_type = 'favor'             and reported_favor_id   = v_target_id);

    insert into public.content_moderation_events (target_type, target_id, report_id, action, acted_by, reason)
    values (v_target_type, v_target_id, v_report.id, 'restore', v_uid, v_reason);

  else
    update public.reports
       set community_status = 'dismissed', community_reviewed_at = now()
     where id = v_report.id;

    insert into public.content_moderation_events (target_type, target_id, report_id, action, acted_by, reason)
    values (v_target_type, v_target_id, v_report.id, 'dismiss', v_uid, v_reason);
  end if;

  return jsonb_build_object('success', true);
end
$$;

revoke all on function public.moderate_community_content(uuid, text, text) from public, anon;
grant execute on function public.moderate_community_content(uuid, text, text) to authenticated;


-- ============================================================================================
-- BLOCK 5: town_hall_posts "Users or admins can delete posts"  (spec §3.4: "plus 1 altered in Phase 3")
-- The community's admins gain the policy, except for posts by that community's owners and admins. The subquery runs
-- with invoker rights; community_members' SELECT policy lets an admin read their community's rows
-- (20261017_0002 [N3]), and that policy never reads town_hall_posts (no recursion). If the MCP declines this call
-- because of the word in the policy's name: SQL editor (owner).
-- ============================================================================================
alter policy "Users or admins can delete posts" on public.town_hall_posts
  to public
  using (
    ((select auth.uid()) = user_id)
    or ((select profiles.is_admin from public.profiles where profiles.id = (select auth.uid())) = true)
    or (
      community_id = any ((select public.my_admin_community_ids())::uuid[])
      and not exists (
        select 1 from public.community_members m
         where m.community_id = town_hall_posts.community_id
           and m.user_id = town_hall_posts.user_id
           and m.status = 'active'
           and m.role in ('owner', 'admin')
      )
    )
  );


-- ============================================================================================
-- BLOCK 6 (carry-over, D-S1): content_moderation_events accepts target_type 'community'
-- One ALTER TABLE statement, so the table is never without the CHECK. If the MCP declines DROP CONSTRAINT:
-- SQL editor (owner).
-- ============================================================================================
alter table public.content_moderation_events
  drop constraint content_moderation_events_target_type_check,
  add constraint content_moderation_events_target_type_check
    check (target_type in ('message', 'town_hall_post', 'town_hall_comment', 'ride', 'favor', 'user', 'community'));


-- ============================================================================================
-- BLOCK 7 (carry-over, D-S1): public.admin_get_reports(uuid, text)   live md5(prosrc) 9a3f9b9ab04327bf9d9cd052eaad61a7
-- Platform admins only, unchanged signature and columns. Three edits: target_type 'community' before 'user';
-- reported_community_id in the target id; the community's name as the preview, placed BEFORE the ride and favor
-- CONCAT_WS entries (they yield '' for any other report, so a later entry would never be reached; the existing
-- '' preview of person reports is left as it is).
-- ============================================================================================
create or replace function public.admin_get_reports(
    p_admin_id uuid,
    p_status text default null
)
returns table (
    report_id uuid,
    reporter_id uuid,
    reporter_name text,
    reported_user_id uuid,
    reported_user_name text,
    reported_message_id uuid,
    reported_post_id uuid,
    reported_comment_id uuid,
    reported_ride_id uuid,
    reported_favor_id uuid,
    target_type text,
    report_type text,
    description text,
    status text,
    created_at timestamptz,
    reviewed_at timestamptz,
    content_preview text,
    content_hidden boolean,
    report_count integer
)
language plpgsql
security definer
set search_path = ''
as $function$
DECLARE
    v_actor_id UUID;
BEGIN
    v_actor_id := auth.uid();
    IF v_actor_id IS NULL OR v_actor_id <> p_admin_id THEN
        RAISE EXCEPTION 'Unauthorized: caller mismatch';
    END IF;

    IF NOT EXISTS (
        SELECT 1
        FROM public.profiles
        WHERE id = v_actor_id
          AND is_admin = true
    ) THEN
        RAISE EXCEPTION 'Unauthorized: caller is not an admin';
    END IF;

    RETURN QUERY
    WITH enriched AS (
        SELECT
            r.id AS report_id,
            r.reporter_id,
            rp.name AS reporter_name,
            r.reported_user_id,
            ru.name AS reported_user_name,
            r.reported_message_id,
            r.reported_post_id,
            r.reported_comment_id,
            r.reported_ride_id,
            r.reported_favor_id,
            CASE
                WHEN r.reported_message_id IS NOT NULL THEN 'message'
                WHEN r.reported_post_id IS NOT NULL THEN 'town_hall_post'
                WHEN r.reported_comment_id IS NOT NULL THEN 'town_hall_comment'
                WHEN r.reported_ride_id IS NOT NULL THEN 'ride'
                WHEN r.reported_favor_id IS NOT NULL THEN 'favor'
                WHEN r.reported_community_id IS NOT NULL THEN 'community'
                ELSE 'user'
            END AS target_type,
            COALESCE(
                r.reported_message_id,
                r.reported_post_id,
                r.reported_comment_id,
                r.reported_ride_id,
                r.reported_favor_id,
                r.reported_community_id,
                r.reported_user_id
            ) AS target_id,
            r.report_type,
            r.description,
            r.status,
            r.created_at,
            r.reviewed_at,
            COALESCE(
                LEFT(msg.text, 200),
                LEFT(post.content, 200),
                LEFT(cmt.content, 200),
                LEFT(comm.name, 200),
                LEFT(CONCAT_WS(' -> ', ride.pickup, ride.destination), 200),
                LEFT(CONCAT_WS(': ', fav.title, NULLIF(fav.description, '')), 200),
                ru.name
            ) AS content_preview,
            CASE
                WHEN r.reported_message_id IS NOT NULL THEN msg.hidden_at IS NOT NULL
                WHEN r.reported_post_id IS NOT NULL THEN post.hidden_at IS NOT NULL
                WHEN r.reported_comment_id IS NOT NULL THEN cmt.hidden_at IS NOT NULL
                WHEN r.reported_ride_id IS NOT NULL THEN ride.hidden_at IS NOT NULL
                WHEN r.reported_favor_id IS NOT NULL THEN fav.hidden_at IS NOT NULL
                ELSE false
            END AS content_hidden
        FROM public.reports r
        LEFT JOIN public.profiles rp
            ON rp.id = r.reporter_id
        LEFT JOIN public.profiles ru
            ON ru.id = r.reported_user_id
        LEFT JOIN public.messages msg
            ON msg.id = r.reported_message_id
        LEFT JOIN public.town_hall_posts post
            ON post.id = r.reported_post_id
        LEFT JOIN public.town_hall_comments cmt
            ON cmt.id = r.reported_comment_id
        LEFT JOIN public.rides ride
            ON ride.id = r.reported_ride_id
        LEFT JOIN public.favors fav
            ON fav.id = r.reported_favor_id
        LEFT JOIN public.communities comm
            ON comm.id = r.reported_community_id
    ),
    grouped AS (
        SELECT
            e.target_type,
            e.target_id,
            COUNT(*)::INT AS dup_count
        FROM enriched e
        GROUP BY e.target_type, e.target_id
    )
    SELECT
        e.report_id,
        e.reporter_id,
        e.reporter_name,
        e.reported_user_id,
        e.reported_user_name,
        e.reported_message_id,
        e.reported_post_id,
        e.reported_comment_id,
        e.reported_ride_id,
        e.reported_favor_id,
        e.target_type,
        e.report_type,
        e.description,
        e.status,
        e.created_at,
        e.reviewed_at,
        e.content_preview,
        e.content_hidden,
        COALESCE(g.dup_count, 1) AS report_count
    FROM enriched e
    LEFT JOIN grouped g
        ON g.target_type = e.target_type
       AND g.target_id = e.target_id
    WHERE p_status IS NULL OR e.status = p_status
    ORDER BY e.created_at DESC;
END;
$function$;

revoke all on function public.admin_get_reports(uuid, text) from public, anon;
grant execute on function public.admin_get_reports(uuid, text) to authenticated;


-- ============================================================================================
-- BLOCK 8 (carry-over, D-S1): public.admin_moderate_content(uuid, uuid, text, text)
--   live md5(prosrc) f569cf95a6d7bc8e8cdb44a303edaa78
-- Platform admins only, unchanged signature. A community report is target 'community' (target id = the community)
-- and can only be dismissed; the dismissal is logged with that target (needs block 6). The remedy for a community
-- itself stays archive or make-private in Admin → Communities (decision A2).
-- ============================================================================================
create or replace function public.admin_moderate_content(
    p_admin_id uuid,
    p_report_id uuid,
    p_action text,
    p_admin_notes text default null
)
returns void
language plpgsql
security definer
set search_path = ''
as $function$
DECLARE
    v_actor_id UUID;
    v_report public.reports%ROWTYPE;
    v_target_type TEXT;
    v_target_id UUID;
    v_reason TEXT;
    v_author_id UUID;
    v_conversation_id UUID;
    v_town_hall_post_id UUID;
    v_content_hidden BOOLEAN := false;
BEGIN
    v_actor_id := auth.uid();
    IF v_actor_id IS NULL OR v_actor_id <> p_admin_id THEN
        RAISE EXCEPTION 'Unauthorized: caller mismatch';
    END IF;

    IF NOT EXISTS (
        SELECT 1
        FROM public.profiles
        WHERE id = v_actor_id
          AND is_admin = true
    ) THEN
        RAISE EXCEPTION 'Unauthorized: caller is not an admin';
    END IF;

    IF p_action NOT IN ('hide', 'restore', 'dismiss') THEN
        RAISE EXCEPTION 'Invalid action: %', p_action;
    END IF;

    SELECT *
    INTO v_report
    FROM public.reports
    WHERE id = p_report_id;

    IF NOT FOUND THEN
        RAISE EXCEPTION 'Report % not found', p_report_id;
    END IF;

    v_reason := NULLIF(BTRIM(p_admin_notes), '');
    IF p_action = 'hide' AND v_reason IS NULL THEN
        RAISE EXCEPTION 'Hide action requires admin notes';
    END IF;

    v_target_type := CASE
        WHEN v_report.reported_message_id IS NOT NULL THEN 'message'
        WHEN v_report.reported_post_id IS NOT NULL THEN 'town_hall_post'
        WHEN v_report.reported_comment_id IS NOT NULL THEN 'town_hall_comment'
        WHEN v_report.reported_ride_id IS NOT NULL THEN 'ride'
        WHEN v_report.reported_favor_id IS NOT NULL THEN 'favor'
        WHEN v_report.reported_community_id IS NOT NULL THEN 'community'
        ELSE 'user'
    END;

    v_target_id := COALESCE(
        v_report.reported_message_id,
        v_report.reported_post_id,
        v_report.reported_comment_id,
        v_report.reported_ride_id,
        v_report.reported_favor_id,
        v_report.reported_community_id,
        v_report.reported_user_id
    );

    CASE v_target_type
        WHEN 'message' THEN
            SELECT m.from_id, m.conversation_id, NULL::UUID, m.hidden_at IS NOT NULL
            INTO v_author_id, v_conversation_id, v_town_hall_post_id, v_content_hidden
            FROM public.messages m
            WHERE m.id = v_target_id;
        WHEN 'town_hall_post' THEN
            SELECT p.user_id, NULL::UUID, p.id, p.hidden_at IS NOT NULL
            INTO v_author_id, v_conversation_id, v_town_hall_post_id, v_content_hidden
            FROM public.town_hall_posts p
            WHERE p.id = v_target_id;
        WHEN 'town_hall_comment' THEN
            SELECT c.user_id, NULL::UUID, c.post_id, c.hidden_at IS NOT NULL
            INTO v_author_id, v_conversation_id, v_town_hall_post_id, v_content_hidden
            FROM public.town_hall_comments c
            WHERE c.id = v_target_id;
        WHEN 'ride' THEN
            SELECT r.user_id, NULL::UUID, NULL::UUID, r.hidden_at IS NOT NULL
            INTO v_author_id, v_conversation_id, v_town_hall_post_id, v_content_hidden
            FROM public.rides r
            WHERE r.id = v_target_id;
        WHEN 'favor' THEN
            SELECT f.user_id, NULL::UUID, NULL::UUID, f.hidden_at IS NOT NULL
            INTO v_author_id, v_conversation_id, v_town_hall_post_id, v_content_hidden
            FROM public.favors f
            WHERE f.id = v_target_id;
        WHEN 'community' THEN
            v_author_id := NULL;
            v_conversation_id := NULL;
            v_town_hall_post_id := NULL;
            v_content_hidden := false;
        ELSE
            v_author_id := v_report.reported_user_id;
            v_conversation_id := NULL;
            v_town_hall_post_id := NULL;
            v_content_hidden := COALESCE(v_report.content_hidden, false);
    END CASE;

    IF v_target_type = 'user' AND p_action <> 'dismiss' THEN
        RAISE EXCEPTION 'User reports only support dismiss';
    END IF;

    IF v_target_type = 'community' AND p_action <> 'dismiss' THEN
        RAISE EXCEPTION 'Community reports only support dismiss';
    END IF;

    IF p_action <> 'dismiss' AND v_author_id IS NULL THEN
        RAISE EXCEPTION 'Moderation target % not found', v_target_id;
    END IF;

    IF p_action = 'hide' THEN
        CASE v_target_type
            WHEN 'message' THEN
                UPDATE public.messages
                SET hidden_at = COALESCE(hidden_at, NOW()), hidden_by = v_actor_id, hidden_reason = v_reason
                WHERE id = v_target_id;
            WHEN 'town_hall_post' THEN
                UPDATE public.town_hall_posts
                SET hidden_at = COALESCE(hidden_at, NOW()), hidden_by = v_actor_id, hidden_reason = v_reason
                WHERE id = v_target_id;
            WHEN 'town_hall_comment' THEN
                UPDATE public.town_hall_comments
                SET hidden_at = COALESCE(hidden_at, NOW()), hidden_by = v_actor_id, hidden_reason = v_reason
                WHERE id = v_target_id;
            WHEN 'ride' THEN
                UPDATE public.rides
                SET hidden_at = COALESCE(hidden_at, NOW()), hidden_by = v_actor_id, hidden_reason = v_reason
                WHERE id = v_target_id;
            WHEN 'favor' THEN
                UPDATE public.favors
                SET hidden_at = COALESCE(hidden_at, NOW()), hidden_by = v_actor_id, hidden_reason = v_reason
                WHERE id = v_target_id;
        END CASE;

        UPDATE public.reports
        SET content_hidden = true
        WHERE (
            (v_target_type = 'message' AND reported_message_id = v_target_id)
            OR (v_target_type = 'town_hall_post' AND reported_post_id = v_target_id)
            OR (v_target_type = 'town_hall_comment' AND reported_comment_id = v_target_id)
            OR (v_target_type = 'ride' AND reported_ride_id = v_target_id)
            OR (v_target_type = 'favor' AND reported_favor_id = v_target_id)
        );

        UPDATE public.reports
        SET status = 'action_taken',
            reviewed_at = NOW(),
            reviewed_by = v_actor_id,
            admin_notes = v_reason,
            content_hidden = true
        WHERE (
            (v_target_type = 'message' AND reported_message_id = v_target_id)
            OR (v_target_type = 'town_hall_post' AND reported_post_id = v_target_id)
            OR (v_target_type = 'town_hall_comment' AND reported_comment_id = v_target_id)
            OR (v_target_type = 'ride' AND reported_ride_id = v_target_id)
            OR (v_target_type = 'favor' AND reported_favor_id = v_target_id)
        )
          AND (
              id = v_report.id
              OR status = 'pending'
          );

        INSERT INTO public.content_moderation_events (target_type, target_id, report_id, action, acted_by, reason)
        VALUES (v_target_type, v_target_id, v_report.id, 'hide', v_actor_id, v_reason);

        PERFORM public.create_content_hidden_notification(
            v_author_id,
            v_reason,
            v_conversation_id,
            v_town_hall_post_id,
            CASE WHEN v_target_type = 'ride' THEN v_target_id ELSE NULL END,
            CASE WHEN v_target_type = 'favor' THEN v_target_id ELSE NULL END
        );
    ELSIF p_action = 'restore' THEN
        CASE v_target_type
            WHEN 'message' THEN
                UPDATE public.messages SET hidden_at = NULL, hidden_by = NULL, hidden_reason = NULL WHERE id = v_target_id;
            WHEN 'town_hall_post' THEN
                UPDATE public.town_hall_posts SET hidden_at = NULL, hidden_by = NULL, hidden_reason = NULL WHERE id = v_target_id;
            WHEN 'town_hall_comment' THEN
                UPDATE public.town_hall_comments SET hidden_at = NULL, hidden_by = NULL, hidden_reason = NULL WHERE id = v_target_id;
            WHEN 'ride' THEN
                UPDATE public.rides SET hidden_at = NULL, hidden_by = NULL, hidden_reason = NULL WHERE id = v_target_id;
            WHEN 'favor' THEN
                UPDATE public.favors SET hidden_at = NULL, hidden_by = NULL, hidden_reason = NULL WHERE id = v_target_id;
        END CASE;

        UPDATE public.reports
        SET content_hidden = false
        WHERE (
            (v_target_type = 'message' AND reported_message_id = v_target_id)
            OR (v_target_type = 'town_hall_post' AND reported_post_id = v_target_id)
            OR (v_target_type = 'town_hall_comment' AND reported_comment_id = v_target_id)
            OR (v_target_type = 'ride' AND reported_ride_id = v_target_id)
            OR (v_target_type = 'favor' AND reported_favor_id = v_target_id)
        );

        INSERT INTO public.content_moderation_events (target_type, target_id, report_id, action, acted_by, reason)
        VALUES (v_target_type, v_target_id, v_report.id, 'restore', v_actor_id, v_reason);
    ELSE
        UPDATE public.reports
        SET status = 'dismissed',
            reviewed_at = NOW(),
            reviewed_by = v_actor_id,
            admin_notes = COALESCE(v_reason, admin_notes),
            content_hidden = v_content_hidden
        WHERE id = v_report.id;

        INSERT INTO public.content_moderation_events (target_type, target_id, report_id, action, acted_by, reason)
        VALUES (v_target_type, v_target_id, v_report.id, 'dismiss', v_actor_id, v_reason);
    END IF;
END;
$function$;

revoke all on function public.admin_moderate_content(uuid, uuid, text, text) from public, anon;
grant execute on function public.admin_moderate_content(uuid, uuid, text, text) to authenticated;
