# Multi-community Phase 3: server migrations and probes

> Companion of `2026-10-18-multi-community-phase3.md` (the iOS plan). This file holds the complete SQL of Phase 3 and the probe blocks. **Nothing here is applied.** The orchestrator copies each fenced block to the file named above it, applies it, records the outcomes in the file headers, and commits the migration files and the probe file in the same change (CLAUDE.md, migration rules). Agents executing the iOS plan never write under `supabase/`.

**Spec:** `Docs/superpowers/specs/2026-10-07-multi-community-design.md` §4 "Phase 3 - Community admin and moderation" (in full), §3.5 (the `handle_new_report`, `admin_*` stats, `get_community_reports`, `moderate_community_content`, `get_community_stats` rows and "Reporter privacy for community admins (INV-P2)"), §3.4 (the one Phase 3 policy), §2.1 rule 10, §2.4, D14, D27, under `Docs/superpowers/specs/2026-10-17-multi-community-decisions.md` (wins where they differ) and the owner decision recorded in `20261017_0003_communities_fanout.sql:193-198` (platform admins exempt from the broadcast cap "until Phase 3").

## What Phase 3 needs from the server, and where each piece is

| Spec §4 Phase 3 item | Where |
|---|---|
| `handle_new_report` recipients extended under INV-P2 | File A block 2 |
| `get_community_reports`, `moderate_community_content` | File A blocks 3, 4 (block 1: their shared internal test and the community's own decision columns on `reports`, so the platform admins' queue is never changed by a community admin) |
| `town_hall_posts` DELETE policy gains the community's admins | File A block 5 |
| `get_community_stats` + the three breakdowns, the `admin_*` wrappers | File B blocks 1-9 |
| the 3-per-day broadcast cap applies to platform admins | File B block 10 (the cap also stops counting announcement-typed rows a member inserts directly) |
| `user_rejected` / `account_restricted` producers in `reject_community_member` / `remove_community_member` | **already live** (shipped with Phase 0 step 5, `20261017_0005_communities_rpcs.sql:121-125`, blocks 21-22). Nothing to apply; the probe `community_moderation` does not repeat them (`archive` already checks `user_rejected`). |
| "confirm both raw values pass the live `notifications.type` CHECK and run `scripts/validate-notification-types.sh`" | Precondition P2 below. The CHECK was read on 2026-10-18 and contains both `user_rejected` and `account_restricted` (`valid_notification_type`). |
| Probe additions (report on a probe-community post; report on the owner's own post; moderating one's own content) | probe blocks `community_moderation` (also: platform moderation wins over a community admin), `posts_delete_policy`; plus `admin_community_reports` (blocks 6-8), `community_stats`, `broadcast_cap` |
| Carry-over from the Phase 2 gate: community reports cannot be dismissed from Admin → Reports | File A blocks 6-8 (optional, see Deviations D-S1) |

## Statements the MCP declines

None of the migration blocks contains a `DELETE` statement, `DROP POLICY`, or a delete from `auth.*` / `storage.*`, so every block is meant for `apply_migration`. Two are flagged:

- **File A block 5** (`alter policy "Users or admins can delete posts"`): the policy's *name* contains the word "delete". The permission layer has accepted calls whose text names `delete_user_account` (the `short` probe), so it is not expected to decline this. **If it does: SQL editor (owner)**, the exact block.
- **File A block 6** (`alter table ... drop constraint ..., add constraint ...`): `DROP CONSTRAINT` is not one of the statements the MCP is known to decline. **If it does: SQL editor (owner)**, the exact block.

One probe block contains `DELETE` statements and is marked **SQL editor (owner)**: `posts_delete_policy`.

The orchestrator sends one block per call and never a file header: the headers name the DELETE policy and the owner-only probe in prose, and the in-block comments avoid those words, so a text scan of a call sees only that block's statements.

## Preconditions (read only, orchestrator; values observed on 2026-10-18)

- **P1. Live bodies.** `select proname, pg_get_function_identity_arguments(oid), md5(prosrc) from pg_proc where pronamespace = 'public'::regnamespace and proname in (...)` must return exactly these before the block that replaces each one; stop on any difference:

  | Function | md5(prosrc) on 2026-10-18 | Source of that body (rollback) |
  |---|---|---|
  | `handle_new_report()` | `a470284db164ca45c1eaa23a4cd32cd6` | `20261017_0003_communities_fanout.sql:684-880` (call 10) |
  | `admin_get_reports(uuid, text)` | `9a3f9b9ab04327bf9d9cd052eaad61a7` | `20260403_0011_content_moderation_redesign.sql:311-458` (read live and compared: identical) |
  | `admin_moderate_content(uuid, uuid, text, text)` | `f569cf95a6d7bc8e8cdb44a303edaa78` | `20260403_0011_content_moderation_redesign.sql:460-787` |
  | `admin_dashboard_stats()` | `5e27ad2aa06507f20a3ada5efd78646b` | `20260302173326_admin_stats_include_favors.sql:6-47` (compared live: identical) |
  | `admin_stats_fulfilled(text, integer)` | `687d59d37ad68aad9c736a4224f2bbea` | `20260302171609_admin_stats_fulfilled.sql:8-68` (identical) |
  | `admin_stats_savings(text, integer)` | `81653c495a17d65d350fbac3c7eb0214` | `20260302171619_admin_stats_savings.sql:8-47` (identical) |
  | `admin_stats_active_rides()` | `50a14b5c0e97e06f30f424898f90f84a` | `20260302173734_fix_active_rides_status_cast.sql:6-58` (identical) |
  | `send_community_broadcast(uuid, text, text, boolean, text)` | `df908ac4cf41a160e4f5285af8580c5d` | `20261017_0003_communities_fanout.sql:893-972` (call 11) |

  The `town_hall_posts` DELETE policy reads, live: `((SELECT auth.uid()) = user_id) OR ((SELECT profiles.is_admin FROM profiles WHERE profiles.id = (SELECT auth.uid())) = true)`, roles `{public}` (the rollback text is `20261017_0000_communities_live_bodies_snapshot.sql:2181-2184`). `content_moderation_events_target_type_check` reads `target_type IN ('message','town_hall_post','town_hall_comment','ride','favor','user')`.
- **P2. Registry.** `valid_notification_type` contains `user_rejected` and `account_restricted` (it does); `scripts/validate-notification-types.sh` exits 0 on the branch.
- **P3. None of the new names exists:** `is_community_staff`, `get_community_reports`, `moderate_community_content`, `can_read_community_stats`, `get_community_stats`, `get_community_stats_fulfilled`, `get_community_stats_savings`, `get_community_stats_active_requests`; no column `reports.community_status` / `community_reviewed_at`, no constraint `reports_community_status_check`.

## Runbook (orchestrator)

1. **Snapshot before**, as the platform admin probe subject (`pg_temp.probe_run(<platform admin>, ...)` after the probe file's HELPERS): `admin_get_reports(<id>, null)`, `admin_dashboard_stats()`, `admin_stats_fulfilled('month', 12)`, `admin_stats_fulfilled('week', 12)`, `admin_stats_savings('year', 12)`, `admin_stats_active_rides()`. Keep the JSON.
2. **Dry run** (one `execute_sql` call): `begin;` File A blocks 1-8, File B blocks 1-10, the probe PARAMETERS and HELPERS (with the additions below, and without the HELPERS section's `commit;`), the blocks `community_moderation`, `admin_community_reports`, `community_stats`, `broadcast_cap`, `short`, the six snapshot calls again, `rollback;`. Each probe block's own `begin;` / `rollback;` becomes `savepoint probe;` / `rollback to savepoint probe;` (the method recorded in `20261017_0005`'s header), so a block's rollback does not undo the migration blocks under test. Pass when every probe prints OK and: the five stats snapshots are equal (compare `admin_stats_active_rides` as a set of rows), and `admin_get_reports` is equal except rows whose report has `reported_community_id`, which now read `target_type = 'community'` with the community's name as `content_preview`.
3. **Apply File A**, blocks 1 → 8, one `apply_migration` per block (names `20261018_0001_block_<n>`). After each block: P1's md5 check for the next one, then the `short` probe.
4. **Apply File B**, blocks 1 → 10 the same way (names `20261018_0002_block_<n>`), `short` after each.
5. **Full probe:** `community_moderation`, `admin_community_reports`, `community_stats`, `broadcast_cap` through the MCP; then the **owner runs `posts_delete_policy` in the SQL editor** (paste PARAMETERS, HELPERS and that block).
6. **Record** in each file header: APPLIED with the date, the migration-history versions, `md5(prosrc)` of every deployed body (`select proname, md5(prosrc) ...`), the probe outcomes. Commit both migration files and the probe file together.

**Sequencing.** Every block keeps the installed build and the Phase 2 build working. Two blocks change what a person sees before the Phase 3 client ships, and both are deliberate:
- File A block 2: a community owner or admin who is not a platform admin starts receiving `content_reported`. On the Phase 2 build (and on any installed-build device of theirs) the tap opens the platform reports route and lands on "Access denied" until the Phase 3 client is installed (spec §4 Phase 3, "What old clients see"). At 2026-10-18 the only community admins outside the platform admins are testers. The gate's live matrix needs this block live; apply it with the rest unless the owner asks to hold it until the release.
- File B block 10: a platform admin's fourth announcement within 24 hours in one community is refused, on every build (owner decision, `20261017_0003:193-198`). Announcement-typed rows a member inserted stop counting toward anyone's cap (a relaxation).
- File A block 4 changes nothing for platform admins: a community admin's hide or dismissal leaves the report pending in Admin → Reports.

---

## File A — `supabase/migrations/20261018_0001_community_moderation.sql`

````sql
-- 20261018_0001_community_moderation.sql
--
-- NOT APPLIED. Phase 3 of the multi-community design (Docs/superpowers/specs/2026-10-07-multi-community-design.md
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
-- editor (it holds DELETE statements). Outcomes: not yet run.
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
````

The only edits in blocks 7 and 8 against the live bodies are the lines that mention `reported_community_id`, `comm` or `'community'`; the rest is the live text, reflowed in block 8's `CASE` arms (statement order and conditions unchanged). The implementer of the orchestration verifies this with a diff against `20260403_0011:311-787` before applying.

---

## File B — `supabase/migrations/20261018_0002_community_stats_and_broadcast_cap.sql`

````sql
-- 20261018_0002_community_stats_and_broadcast_cap.sql
--
-- NOT APPLIED. Phase 3 of the multi-community design (spec §3.5 rows "admin_dashboard_stats() ..." and
-- "get_community_stats(p_community_id) and the three breakdowns", §4 Phase 3, D14), with the owner decision of
-- 2026-10-17 that platform admins are exempt from the broadcast cap until Phase 3 (20261017_0003:193-198).
--
-- What it does.
--   * can_read_community_stats (new, internal): the caller may read one community's statistics (its admins and the
--     platform admins: is_community_admin), or, for a null community, every community's (platform admins only).
--   * get_community_stats(p_community_id default null) and the breakdowns get_community_stats_fulfilled,
--     get_community_stats_savings, get_community_stats_active_requests (new): the live admin_* bodies with
--     `community_id = p_community_id` on every rides / favors scan, or no filter for a null community. jsonb
--     envelopes: {success:true, fulfilled_count, total_savings, active_rides_count} and {success:true, rows:[...]}
--     with exactly the legacy row keys; {success:false, error} for anyone else.
--   * admin_dashboard_stats(), admin_stats_fulfilled(text, int), admin_stats_savings(text, int),
--     admin_stats_active_rides() (edited in place; live md5 in each block): thin wrappers that keep their signatures,
--     return types and the legacy platform-admin check and message, and return the null-community (every community)
--     result of the new functions. For the installed admin build nothing changes: the numbers already covered every
--     community. (Spec "resolving as above" is read as "platform admins see every community", the platform admins'
--     answer today; see the plan's D-S3.)
--   * send_community_broadcast (edited in place, live md5 df908ac4cf41a160e4f5285af8580c5d): the 3-per-day cap
--     (D14) now applies to platform admins too, and counts only announcements by platform admins and by the
--     community's owners and admins (a member's directly inserted 'announcement' row no longer counts, for anyone).
--     Nothing else changes; the send_broadcast_notifications wrapper is untouched and inherits the cap. Needs
--     is_community_staff (20261018_0001 block 1).
--
-- Apply. After 20261018_0001. Supabase MCP apply_migration, one block per call, in order (blocks 1-5 before the
-- wrappers that call them). No block removes rows, drops a policy, or writes to auth.* / storage.*.
--
-- Verification. Before applying, snapshot as a platform admin: admin_dashboard_stats(), admin_stats_fulfilled('month',
-- 12), admin_stats_fulfilled('week', 12), admin_stats_savings('year', 12), admin_stats_active_rides(). Dry run all
-- ten blocks in one begin; ... rollback; with the probe blocks community_stats, broadcast_cap and short (each block's
-- begin / rollback turned into a savepoint and a rollback to it), and the same
-- five calls after the blocks: equal (active rides compared as a set). Then short after each block, community_stats
-- and broadcast_cap at the end. Outcomes: not yet run.
--
-- What old clients see. Admin dashboard figures and breakdowns: identical. Broadcasts: a platform admin's fourth
-- announcement within 24 hours in the default community is refused; the installed build shows the server's text
-- ("This community has already sent 3 announcements today"). Rows a member typed 'announcement' no longer use up
-- anyone's cap.
--
-- Rollback: send_community_broadcast from 20261017_0003 call 11 (:893-972); the four admin_* bodies from
-- 20260302173326_admin_stats_include_favors.sql:6-47 (admin_dashboard_stats), 20260302171609_admin_stats_fulfilled.sql
-- :8-68, 20260302171619_admin_stats_savings.sql:8-47, 20260302173734_fix_active_rides_status_cast.sql:6-58 (each
-- compared with the live body on 2026-10-18: identical); then drop the five new functions.


-- ============================================================================================
-- BLOCK 1: public.can_read_community_stats(uuid)  (internal)
-- ============================================================================================
create or replace function public.can_read_community_stats(p_community_id uuid)
returns boolean
language sql
stable
security definer
set search_path = ''
as $$
  select (select auth.uid()) is not null
     and case when p_community_id is null then public.is_platform_admin()
              else public.is_community_admin(p_community_id) end;
$$;

revoke all on function public.can_read_community_stats(uuid) from public, anon, authenticated;


-- ============================================================================================
-- BLOCK 2: public.get_community_stats(uuid)
-- The admin_dashboard_stats body (20260302173326), scoped.
-- ============================================================================================
create or replace function public.get_community_stats(p_community_id uuid default null)
returns jsonb
language plpgsql
stable
security definer
set search_path = ''
as $$
declare
  v_fulfilled bigint;
  v_savings numeric(12,2);
  v_active bigint;
begin
  if not public.can_read_community_stats(p_community_id) then
    return jsonb_build_object('success', false, 'error', 'Only this community''s admins can see its statistics');
  end if;

  select coalesce((select count(*) from public.rides r
                    where r.status = 'completed'
                      and (p_community_id is null or r.community_id = p_community_id)), 0)
       + coalesce((select count(*) from public.favors f
                    where f.status = 'completed'
                      and (p_community_id is null or f.community_id = p_community_id)), 0)
    into v_fulfilled;

  select coalesce(sum(r.estimated_cost), 0)
    into v_savings
    from public.rides r
   where r.estimated_cost is not null
     and (p_community_id is null or r.community_id = p_community_id);

  select (select count(*) from public.rides r
           where r.status in ('open', 'pending', 'confirmed')
             and (p_community_id is null or r.community_id = p_community_id))
       + (select count(*) from public.favors f
           where f.status in ('open', 'pending', 'confirmed')
             and (p_community_id is null or f.community_id = p_community_id))
    into v_active;

  return jsonb_build_object(
    'success', true,
    'fulfilled_count', v_fulfilled,
    'total_savings', v_savings,
    'active_rides_count', v_active
  );
end
$$;

revoke all on function public.get_community_stats(uuid) from public, anon;
grant execute on function public.get_community_stats(uuid) to authenticated;


-- ============================================================================================
-- BLOCK 3: public.get_community_stats_fulfilled(uuid, text, integer)
-- The admin_stats_fulfilled body (20260302171609), scoped. p_count is bounded 1..520 (ten years of weeks); the
-- installed build always sends 12.
-- ============================================================================================
create or replace function public.get_community_stats_fulfilled(
  p_community_id uuid default null,
  p_period text default 'month',
  p_count integer default 12
)
returns jsonb
language plpgsql
stable
security definer
set search_path = ''
as $$
declare
  v_trunc text := case p_period when 'week' then 'week' when 'year' then 'year' else 'month' end;
  v_count integer := least(greatest(coalesce(p_count, 12), 1), 520);
  v_rows jsonb;
begin
  if not public.can_read_community_stats(p_community_id) then
    return jsonb_build_object('success', false, 'error', 'Only this community''s admins can see its statistics');
  end if;

  select coalesce(jsonb_agg(to_jsonb(t) order by t.period_start desc), '[]'::jsonb)
    into v_rows
    from (
      select combined.period_start,
             sum(combined.ride_count)::bigint as ride_count,
             sum(combined.favor_count)::bigint as favor_count,
             sum(combined.ride_count + combined.favor_count)::bigint as total_count
        from (
          select date_trunc(v_trunc, r.updated_at)::date as period_start,
                 count(*) as ride_count,
                 0 as favor_count
            from public.rides r
           where r.status = 'completed'
             and (p_community_id is null or r.community_id = p_community_id)
           group by date_trunc(v_trunc, r.updated_at)
          union all
          select date_trunc(v_trunc, f.updated_at)::date,
                 0,
                 count(*)
            from public.favors f
           where f.status = 'completed'
             and (p_community_id is null or f.community_id = p_community_id)
           group by date_trunc(v_trunc, f.updated_at)
        ) combined
       group by combined.period_start
       order by combined.period_start desc
       limit v_count
    ) t;

  return jsonb_build_object('success', true, 'rows', v_rows);
end
$$;

revoke all on function public.get_community_stats_fulfilled(uuid, text, integer) from public, anon;
grant execute on function public.get_community_stats_fulfilled(uuid, text, integer) to authenticated;


-- ============================================================================================
-- BLOCK 4: public.get_community_stats_savings(uuid, text, integer)
-- The admin_stats_savings body (20260302171619), scoped.
-- ============================================================================================
create or replace function public.get_community_stats_savings(
  p_community_id uuid default null,
  p_period text default 'month',
  p_count integer default 12
)
returns jsonb
language plpgsql
stable
security definer
set search_path = ''
as $$
declare
  v_trunc text := case p_period when 'week' then 'week' when 'year' then 'year' else 'month' end;
  v_count integer := least(greatest(coalesce(p_count, 12), 1), 520);
  v_rows jsonb;
begin
  if not public.can_read_community_stats(p_community_id) then
    return jsonb_build_object('success', false, 'error', 'Only this community''s admins can see its statistics');
  end if;

  select coalesce(jsonb_agg(to_jsonb(t) order by t.period_start desc), '[]'::jsonb)
    into v_rows
    from (
      select date_trunc(v_trunc, r.created_at)::date as period_start,
             coalesce(sum(r.estimated_cost), 0)::numeric(12,2) as total_savings,
             count(*)::bigint as ride_count
        from public.rides r
       where r.estimated_cost is not null
         and (p_community_id is null or r.community_id = p_community_id)
       group by date_trunc(v_trunc, r.created_at)
       order by period_start desc
       limit v_count
    ) t;

  return jsonb_build_object('success', true, 'rows', v_rows);
end
$$;

revoke all on function public.get_community_stats_savings(uuid, text, integer) from public, anon;
grant execute on function public.get_community_stats_savings(uuid, text, integer) to authenticated;


-- ============================================================================================
-- BLOCK 5: public.get_community_stats_active_requests(uuid)
-- The admin_stats_active_rides body (20260302173734), scoped. A community admin is a member of it and already reads
-- its addresses.
-- ============================================================================================
create or replace function public.get_community_stats_active_requests(p_community_id uuid default null)
returns jsonb
language plpgsql
stable
security definer
set search_path = ''
as $$
declare
  v_rows jsonb;
begin
  if not public.can_read_community_stats(p_community_id) then
    return jsonb_build_object('success', false, 'error', 'Only this community''s admins can see its statistics');
  end if;

  select coalesce(jsonb_agg(to_jsonb(t) order by t.date asc, t."time" asc), '[]'::jsonb)
    into v_rows
    from (
      select r.id,
             'ride' as type,
             r.pickup as title,
             r.destination as subtitle,
             r.date,
             r."time",
             r.status::text as status,
             r.claimed_by,
             poster.name as poster_name,
             claimer.name as claimer_name
        from public.rides r
        left join public.profiles poster  on poster.id  = r.user_id
        left join public.profiles claimer on claimer.id = r.claimed_by
       where r.status in ('open', 'pending', 'confirmed')
         and (p_community_id is null or r.community_id = p_community_id)
      union all
      select f.id,
             'favor' as type,
             f.title as title,
             f.location as subtitle,
             f.date,
             f."time",
             f.status::text as status,
             f.claimed_by,
             poster.name as poster_name,
             claimer.name as claimer_name
        from public.favors f
        left join public.profiles poster  on poster.id  = f.user_id
        left join public.profiles claimer on claimer.id = f.claimed_by
       where f.status in ('open', 'pending', 'confirmed')
         and (p_community_id is null or f.community_id = p_community_id)
    ) t;

  return jsonb_build_object('success', true, 'rows', v_rows);
end
$$;

revoke all on function public.get_community_stats_active_requests(uuid) from public, anon;
grant execute on function public.get_community_stats_active_requests(uuid) to authenticated;


-- ============================================================================================
-- BLOCK 6: public.admin_dashboard_stats()   live md5(prosrc) 5e27ad2aa06507f20a3ada5efd78646b
-- Wrapper. The legacy check and message are kept (a banned platform admin, whom the legacy body let through, is now
-- refused by is_platform_admin with the same message; such an account cannot use the app).
-- ============================================================================================
create or replace function public.admin_dashboard_stats()
returns json
language plpgsql
security definer
set search_path = ''
as $$
declare
  v jsonb;
begin
  if not exists (select 1 from public.profiles where id = (select auth.uid()) and is_admin = true) then
    raise exception 'Unauthorized: admin access required';
  end if;
  v := public.get_community_stats(null);
  if coalesce((v ->> 'success')::boolean, false) is not true then
    raise exception 'Unauthorized: admin access required';
  end if;
  return (v - 'success')::json;
end
$$;

revoke all on function public.admin_dashboard_stats() from public, anon;
grant execute on function public.admin_dashboard_stats() to authenticated;


-- ============================================================================================
-- BLOCK 7: public.admin_stats_fulfilled(text, integer)   live md5(prosrc) 687d59d37ad68aad9c736a4224f2bbea
-- ============================================================================================
create or replace function public.admin_stats_fulfilled(
    p_period text default 'month',
    p_count integer default 12
)
returns json
language plpgsql
security definer
set search_path = ''
as $$
declare
  v jsonb;
begin
  if not exists (select 1 from public.profiles where id = (select auth.uid()) and is_admin = true) then
    raise exception 'Unauthorized: admin access required';
  end if;
  v := public.get_community_stats_fulfilled(null, p_period, p_count);
  if coalesce((v ->> 'success')::boolean, false) is not true then
    raise exception 'Unauthorized: admin access required';
  end if;
  return coalesce(v -> 'rows', '[]'::jsonb)::json;
end
$$;

revoke all on function public.admin_stats_fulfilled(text, integer) from public, anon;
grant execute on function public.admin_stats_fulfilled(text, integer) to authenticated;


-- ============================================================================================
-- BLOCK 8: public.admin_stats_savings(text, integer)   live md5(prosrc) 81653c495a17d65d350fbac3c7eb0214
-- ============================================================================================
create or replace function public.admin_stats_savings(
    p_period text default 'month',
    p_count integer default 12
)
returns json
language plpgsql
security definer
set search_path = ''
as $$
declare
  v jsonb;
begin
  if not exists (select 1 from public.profiles where id = (select auth.uid()) and is_admin = true) then
    raise exception 'Unauthorized: admin access required';
  end if;
  v := public.get_community_stats_savings(null, p_period, p_count);
  if coalesce((v ->> 'success')::boolean, false) is not true then
    raise exception 'Unauthorized: admin access required';
  end if;
  return coalesce(v -> 'rows', '[]'::jsonb)::json;
end
$$;

revoke all on function public.admin_stats_savings(text, integer) from public, anon;
grant execute on function public.admin_stats_savings(text, integer) to authenticated;


-- ============================================================================================
-- BLOCK 9: public.admin_stats_active_rides()   live md5(prosrc) 50a14b5c0e97e06f30f424898f90f84a
-- ============================================================================================
create or replace function public.admin_stats_active_rides()
returns json
language plpgsql
security definer
set search_path = ''
as $$
declare
  v jsonb;
begin
  if not exists (select 1 from public.profiles where id = (select auth.uid()) and is_admin = true) then
    raise exception 'Unauthorized: admin access required';
  end if;
  v := public.get_community_stats_active_requests(null);
  if coalesce((v ->> 'success')::boolean, false) is not true then
    raise exception 'Unauthorized: admin access required';
  end if;
  return coalesce(v -> 'rows', '[]'::jsonb)::json;
end
$$;

revoke all on function public.admin_stats_active_rides() from public, anon;
grant execute on function public.admin_stats_active_rides() to authenticated;


-- ============================================================================================
-- BLOCK 10: public.send_community_broadcast(uuid, text, text, boolean, text)
--   live md5(prosrc) df908ac4cf41a160e4f5285af8580c5d (20261017_0003 call 11)
-- Two changes. (1) The D14 cap (3 announcements per community in any 24 hours) applies to platform admins too
-- (owner decision 2026-10-17: "exempt until Phase 3"). (2) The cap counts only announcements written by a platform
-- admin or by an active owner or admin of the community, read when the new one is sent. town_hall_posts_insert_active_user
-- (20261017_0002 [A09]) does not restrict `type`, so any active member can insert rows typed 'announcement' directly;
-- counted, three of them would lock the community, platform admins included, out of announcements for a day. A
-- demoted admin's earlier announcements stop counting (no role history is kept); that can only loosen the cap.
-- The refusal keeps SQLSTATE P0001, which the Phase 3 client maps to its daily-limit message.
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
            v_member.user_id, v_type, p_title, p_body,
            null, null, null, null, v_post_id, v_uid, coalesce(p_pinned, false)
        );
        if v_notification_id is not null then
            v_inserted_count := v_inserted_count + 1;
        end if;
    end loop;

    return v_inserted_count;
end;
$function$;

revoke all on function public.send_community_broadcast(uuid, text, text, boolean, text) from public, anon;
grant execute on function public.send_community_broadcast(uuid, text, text, boolean, text) to authenticated, service_role;
````

---

## Probe additions — `supabase/probes/communities_probe.sql`

Three edits to the file.

**(1) Header, "WHEN TO RUN WHAT" (`:18-26`):** add one bullet after the second:

```text
--   * The Phase 3 blocks (community_moderation, admin_community_reports, community_stats, broadcast_cap) need
--     20261018_0001 and 20261018_0002 live and fail with "Phase 3 is not live" otherwise (admin_community_reports
--     also needs File A blocks 6-8). posts_delete_policy holds DELETE statements: SQL editor (owner) only; the MCP
--     declines it.
```

and extend the RPC list (`:72-83`) with: `get_community_reports(p_community_id, p_status), moderate_community_content(p_report_id, p_action, p_reason), get_community_stats(p_community_id) and get_community_stats_fulfilled / _savings(p_community_id, p_period, p_count), get_community_stats_active_requests(p_community_id), send_community_broadcast(p_community_id, p_title, p_body, p_pinned[, p_type])`.

**(2) HELPERS:** insert before the `commit;` at `:327`:

```sql
-- Phase 3: fails unless steps 1-5 and both Phase 3 files (20261018_0001 / 0002) are live
create or replace function pg_temp.probe_require_phase3(p_probe text) returns void language plpgsql as $f$
declare
  v_missing text[];
begin
  perform pg_temp.probe_require(p_probe);
  select array_agg(f) into v_missing
    from unnest(array['is_community_staff', 'get_community_reports', 'moderate_community_content',
                      'can_read_community_stats', 'get_community_stats', 'get_community_stats_fulfilled',
                      'get_community_stats_savings', 'get_community_stats_active_requests']) f
   where not exists (select 1 from pg_catalog.pg_proc p
                      where p.pronamespace = 'public'::regnamespace and p.proname = f);
  if v_missing is not null then
    raise exception 'PROBE % FAILED: Phase 3 is not live; missing %', p_probe, v_missing;
  end if;
  if not exists (select 1 from information_schema.columns
                  where table_schema = 'public' and table_name = 'reports' and column_name = 'community_status') then
    raise exception 'PROBE % FAILED: Phase 3 is not live; missing reports.community_status', p_probe;
  end if;
end $f$;

-- a Town Hall post written as the table owner (no JWT); ids 00000000-0000-4000-d000-0000000005NN
create or replace function pg_temp.probe_post(n int, p_author uuid, p_community uuid) returns uuid language plpgsql as $f$
declare
  v uuid := ('00000000-0000-4000-d000-' || lpad((500 + n)::text, 12, '0'))::uuid;
begin
  perform set_config('request.jwt.claims', '', true);
  insert into public.town_hall_posts (id, user_id, title, content, community_id)
  values (v, p_author, 'Probe post ' || n, 'communities probe post ' || n, p_community);
  return v;
end $f$;
```

**(3) Blocks:** insert before the final `select 'PROBE ALL OK' as probe;` (`:1376`). `community_moderation`, `admin_community_reports`, `community_stats` and `broadcast_cap` run through the MCP; `posts_delete_policy` is **SQL editor (owner)**. If the owner drops File A blocks 6-8 (D-S1), drop `admin_community_reports` with them.

```sql
-- =============================================================================================================
-- community_moderation (Phase 3, INV-P2, D27): a report on a probe-community post reaches its owner and admin
-- with no source user and a push carrying community_id, never the author or the reporter, and the platform
-- admins' rows are unchanged; get_community_reports has no reporter field and refuses non-admins; a report on an
-- admin's post reaches no admin of the community, is not in their lists and cannot be moderated by them (nor by
-- its author); a person report between two people sharing one community reaches that community's admins but not
-- the reported person, and one about an admin reaches none; hide / restore / dismiss write the content, the events
-- and the community's own decision, and leave the report pending in the platform admins' queue; platform moderation
-- wins (no restore of a platform admin's hide or of the auto-hide, no hide or dismiss on a report a platform admin
-- reviewed, no hide of hidden content); a community report is out of reach; an archived community's reports are
-- refused.
-- =============================================================================================================
begin;
do $probe$
declare
  v_probe constant text := 'community_moderation';
  v_admin uuid := pg_temp.probe_subject('platform_admin');
  u3 uuid := pg_temp.u(3);  u4 uuid := pg_temp.u(4);  u5 uuid := pg_temp.u(5);  u7 uuid := pg_temp.u(7);  u12 uuid := pg_temp.u(12);
  u11 uuid := pg_temp.u(11);
  c1 uuid := pg_temp.c(1);
  v_post3 uuid;  v_post5 uuid;  v_post11 uuid;  v_post7b uuid;  v_r_post11 uuid;  v_r_auto uuid;
  v_comment uuid := '00000000-0000-4000-d000-000000000601'::uuid;
  v_r_post3 uuid;  v_r_post5 uuid;  v_r_comment uuid;  v_r_person uuid;  v_r_person_admin uuid;  v_r_community uuid;
  v_padmins bigint;
  v_list jsonb;
  j jsonb;
begin
  perform pg_temp.probe_require_phase3(v_probe);
  perform pg_temp.probe_world();
  v_padmins := (select count(*) from public.profiles where is_admin);

  v_post3 := pg_temp.probe_post(1, u3, c1);    -- a plain member's post
  v_post5 := pg_temp.probe_post(2, u5, c1);    -- an admin's post
  insert into public.town_hall_comments (id, post_id, user_id, content)
  values (v_comment, v_post3, u7, 'communities probe comment');

  -- (a) a member reports a member's post
  j := pg_temp.probe_call(u7, format($q$public.submit_report(%L::uuid, %L::uuid, null, %L::uuid, null, null, null,
                                         'harassment', 'Probe post report')$q$, u7, u3, v_post3));
  perform pg_temp.probe_ok(v_probe, 'a member reports a post: ' || j::text, not pg_temp.probe_refused(j));
  v_r_post3 := (j #>> '{}')::uuid;
  perform pg_temp.probe_ok(v_probe, 'the report carries C1', (select community_id from public.reports where id = v_r_post3) = c1);
  perform pg_temp.probe_ok(v_probe, 'the owner and the admin each hold one content_reported row with no source user, in C1',
    (select count(*) from public.notifications n
      where n.user_id in (u4, u5) and n.type = 'content_reported' and n.town_hall_post_id = v_post3
        and n.source_user_id is null and n.community_id = c1) = 2);
  perform pg_temp.probe_ok(v_probe, 'each holds one queued push carrying community_id',
    (select count(*) from public.notification_queue q
      where q.recipient_user_id in (u4, u5) and q.notification_type = 'content_reported'
        and q.payload -> 'data' ->> 'town_hall_post_id' = v_post3::text
        and q.payload -> 'data' ->> 'community_id' = c1::text) = 2);
  perform pg_temp.probe_ok(v_probe, 'the author and the reporter hold none',
    not exists (select 1 from public.notifications n
                 where n.user_id in (u3, u7) and n.type = 'content_reported' and n.town_hall_post_id = v_post3));
  perform pg_temp.probe_ok(v_probe, 'the platform admins'' rows are unchanged: one each, with the reporter',
    (select count(*) from public.notifications n join public.profiles p on p.id = n.user_id
      where p.is_admin and n.type = 'content_reported' and n.town_hall_post_id = v_post3
        and n.source_user_id = u7) = v_padmins);

  v_list := pg_temp.probe_call(u4, format('public.get_community_reports(%L::uuid, null)', c1));
  perform pg_temp.probe_ok(v_probe, 'the owner lists the report: ' || v_list::text,
    coalesce(v_list ->> 'success', '') = 'true'
    and exists (select 1 from jsonb_array_elements(v_list -> 'reports') e
                 where (e ->> 'report_id')::uuid = v_r_post3 and (e ->> 'author_id')::uuid = u3));
  perform pg_temp.probe_ok(v_probe, 'no row has a reporter field, and the reporter''s id appears nowhere in the list',
    not exists (select 1 from jsonb_array_elements(v_list -> 'reports') e where e ? 'reporter_id' or e ? 'reporter_name')
    and position(u7::text in (v_list -> 'reports')::text) = 0);
  j := pg_temp.probe_call(u3, format('public.get_community_reports(%L::uuid, null)', c1));
  perform pg_temp.probe_ok(v_probe, 'a plain member is refused: ' || j::text, pg_temp.probe_refused(j));
  j := pg_temp.probe_call(u12, format('public.get_community_reports(%L::uuid, null)', c1));
  perform pg_temp.probe_ok(v_probe, 'another community''s owner is refused: ' || j::text, pg_temp.probe_refused(j));
  j := pg_temp.probe_call(null, format('public.get_community_reports(%L::uuid, null)', c1), 'anon');
  perform pg_temp.probe_ok(v_probe, 'anon cannot call it: ' || j::text, coalesce(j ->> 'raised', '') = 'true');

  -- (b) a report on an admin's post: platform admins only (INV-P2 rule 3)
  j := pg_temp.probe_call(u3, format($q$public.submit_report(%L::uuid, %L::uuid, null, %L::uuid, null, null, null,
                                         'spam', 'Probe admin post report')$q$, u3, u5, v_post5));
  v_r_post5 := (j #>> '{}')::uuid;
  perform pg_temp.probe_ok(v_probe, 'the report on the admin''s post is filed: ' || j::text, v_r_post5 is not null);
  perform pg_temp.probe_ok(v_probe, 'it reaches no owner or admin of C1',
    not exists (select 1 from public.notifications n
                  join public.community_members m on m.user_id = n.user_id and m.community_id = c1
                                                 and m.status = 'active' and m.role in ('owner', 'admin')
                 where n.type = 'content_reported' and n.town_hall_post_id = v_post5));
  perform pg_temp.probe_ok(v_probe, 'it reaches every platform admin',
    (select count(*) from public.notifications n join public.profiles p on p.id = n.user_id
      where p.is_admin and n.type = 'content_reported' and n.town_hall_post_id = v_post5) = v_padmins);
  v_list := pg_temp.probe_call(u4, format('public.get_community_reports(%L::uuid, null)', c1));
  perform pg_temp.probe_ok(v_probe, 'it is not in the owner''s list',
    not exists (select 1 from jsonb_array_elements(v_list -> 'reports') e where (e ->> 'report_id')::uuid = v_r_post5));
  v_list := pg_temp.probe_call(u5, format('public.get_community_reports(%L::uuid, null)', c1));
  perform pg_temp.probe_ok(v_probe, 'nor in its author''s list',
    not exists (select 1 from jsonb_array_elements(v_list -> 'reports') e where (e ->> 'report_id')::uuid = v_r_post5));
  v_list := pg_temp.probe_call(v_admin, format('public.get_community_reports(%L::uuid, null)', c1));
  perform pg_temp.probe_ok(v_probe, 'a platform admin reads C1''s list, without it: ' || v_list::text,
    coalesce(v_list ->> 'success', '') = 'true'
    and not exists (select 1 from jsonb_array_elements(v_list -> 'reports') e where (e ->> 'report_id')::uuid = v_r_post5));
  j := pg_temp.probe_call(u4, format('public.moderate_community_content(%L::uuid, %L, %L)', v_r_post5, 'hide', 'Probe reason'));
  perform pg_temp.probe_ok(v_probe, 'the owner cannot moderate a report about an admin''s post: ' || j::text, pg_temp.probe_refused(j));
  j := pg_temp.probe_call(u5, format('public.moderate_community_content(%L::uuid, %L, %L)', v_r_post5, 'dismiss', null));
  perform pg_temp.probe_ok(v_probe, 'the author cannot moderate a report about their own content: ' || j::text, pg_temp.probe_refused(j));
  j := pg_temp.probe_call(v_admin, format('public.moderate_community_content(%L::uuid, %L, %L)', v_r_post5, 'dismiss', null));
  perform pg_temp.probe_ok(v_probe, 'nor can a platform admin through this function (admin_moderate_content is theirs): ' || j::text,
    pg_temp.probe_refused(j));
  perform pg_temp.probe_ok(v_probe, 'the admin''s post is untouched and its report pending',
    (select hidden_at from public.town_hall_posts where id = v_post5) is null
    and (select status from public.reports where id = v_r_post5) = 'pending');

  -- (c) an admin reports a member's comment: the reporting admin is not told, the owner is
  j := pg_temp.probe_call(u5, format($q$public.submit_report(%L::uuid, %L::uuid, null, null, %L::uuid, null, null,
                                         'inappropriate_content', 'Probe comment report')$q$, u5, u7, v_comment));
  v_r_comment := (j #>> '{}')::uuid;
  perform pg_temp.probe_ok(v_probe, 'the comment report is filed: ' || j::text, v_r_comment is not null);
  perform pg_temp.probe_ok(v_probe, 'the reporting admin holds no new row; the owner holds one more',
    (select count(*) from public.notifications n
      where n.user_id = u5 and n.type = 'content_reported' and n.town_hall_post_id = v_post3) = 1
    and (select count(*) from public.notifications n
      where n.user_id = u4 and n.type = 'content_reported' and n.town_hall_post_id = v_post3) = 2);
  perform pg_temp.probe_ok(v_probe, 'the comment''s author is not told',
    not exists (select 1 from public.notifications n where n.user_id = u7 and n.type = 'content_reported'));

  -- (d) person reports (D27)
  j := pg_temp.probe_call(u7, format($q$public.submit_report(%L::uuid, %L::uuid, null, null, null, null, null,
                                         'harassment', 'Probe person report')$q$, u7, u3));
  v_r_person := (j #>> '{}')::uuid;
  perform pg_temp.probe_ok(v_probe, 'a person report between two C1-only members carries C1',
    (select community_id from public.reports where id = v_r_person) = c1);
  perform pg_temp.probe_ok(v_probe, 'the owner and the admin each hold one entity-less row for it, tagged C1, no source user',
    (select count(*) from public.notifications n
      where n.user_id in (u4, u5) and n.type = 'content_reported' and n.ride_id is null and n.favor_id is null
        and n.town_hall_post_id is null and n.source_user_id is null and n.community_id = c1) = 2);
  perform pg_temp.probe_ok(v_probe, 'the reported person holds none',
    not exists (select 1 from public.notifications n where n.user_id = u3 and n.type = 'content_reported'));
  j := pg_temp.probe_call(u3, format($q$public.submit_report(%L::uuid, %L::uuid, null, null, null, null, null,
                                         'harassment', 'Probe admin person report')$q$, u3, u5));
  v_r_person_admin := (j #>> '{}')::uuid;
  perform pg_temp.probe_ok(v_probe, 'a person report about an admin reaches no admin of C1 (the owner still has one entity-less row)',
    v_r_person_admin is not null
    and (select count(*) from public.notifications n
          where n.user_id = u4 and n.type = 'content_reported' and n.ride_id is null and n.favor_id is null
            and n.town_hall_post_id is null) = 1);

  -- (e) moderation by the owner on the member's post; the platform admins' queue is not changed
  j := pg_temp.probe_call(u4, format('public.moderate_community_content(%L::uuid, %L, %L)', v_r_post3, 'hide', '   '));
  perform pg_temp.probe_ok(v_probe, 'hide without a reason is refused: ' || j::text, pg_temp.probe_refused(j));
  j := pg_temp.probe_call(u3, format('public.moderate_community_content(%L::uuid, %L, %L)', v_r_post3, 'hide', 'Probe'));
  perform pg_temp.probe_ok(v_probe, 'a plain member cannot moderate: ' || j::text, pg_temp.probe_refused(j));
  j := pg_temp.probe_call(u4, format('public.moderate_community_content(%L::uuid, %L, %L)', v_r_post3, 'hide', 'Probe hide reason'));
  perform pg_temp.probe_ok(v_probe, 'the owner hides the post: ' || j::text, coalesce(j ->> 'success', '') = 'true');
  perform pg_temp.probe_ok(v_probe, 'the post is hidden by the owner with the reason',
    exists (select 1 from public.town_hall_posts
             where id = v_post3 and hidden_at is not null and hidden_by = u4 and hidden_reason = 'Probe hide reason'));
  perform pg_temp.probe_ok(v_probe, 'the report is action_taken for the community and still pending for the platform admins',
    exists (select 1 from public.reports
             where id = v_r_post3 and community_status = 'action_taken' and community_reviewed_at is not null
               and content_hidden and status = 'pending' and reviewed_by is null and reviewed_at is null));
  perform pg_temp.probe_ok(v_probe, 'one hide event acted by the owner',
    (select count(*) from public.content_moderation_events
      where target_type = 'town_hall_post' and target_id = v_post3 and action = 'hide' and acted_by = u4) = 1);
  perform pg_temp.probe_ok(v_probe, 'the author is told (content_hidden)',
    exists (select 1 from public.notifications where user_id = u3 and type = 'content_hidden' and town_hall_post_id = v_post3));
  v_list := pg_temp.probe_call(u4, format('public.get_community_reports(%L::uuid, null)', c1));
  perform pg_temp.probe_ok(v_probe, 'the owner''s list reads action_taken, restorable, not platform-handled: ' || v_list::text,
    exists (select 1 from jsonb_array_elements(v_list -> 'reports') e
             where (e ->> 'report_id')::uuid = v_r_post3 and e ->> 'status' = 'action_taken'
               and (e ->> 'can_restore')::boolean and not (e ->> 'platform_handled')::boolean));
  j := pg_temp.probe_run(v_admin, format($q$select coalesce(jsonb_agg(x.report_id), '[]'::jsonb)
                                            from public.admin_get_reports(%L::uuid, 'pending') x$q$, v_admin));
  perform pg_temp.probe_ok(v_probe, 'it is still in the platform admins'' pending queue', j @> to_jsonb(array[v_r_post3]));
  j := pg_temp.probe_call(u5, format('public.moderate_community_content(%L::uuid, %L, %L)', v_r_post3, 'hide', 'Probe again'));
  perform pg_temp.probe_ok(v_probe, 'hiding hidden content is refused (no hidden_by overwrite): ' || j::text,
    pg_temp.probe_refused(j) and j ->> 'code' = 'already_hidden'
    and (select hidden_by from public.town_hall_posts where id = v_post3) = u4);
  j := pg_temp.probe_call(u5, format('public.moderate_community_content(%L::uuid, %L, %L)', v_r_post3, 'restore', null));
  perform pg_temp.probe_ok(v_probe, 'C1''s admin restores the owner''s hide: ' || j::text,
    coalesce(j ->> 'success', '') = 'true'
    and (select hidden_at from public.town_hall_posts where id = v_post3) is null
    and exists (select 1 from public.content_moderation_events
                 where target_id = v_post3 and action = 'restore' and acted_by = u5));

  -- (f) a person report: dismiss only, recorded for the community, still pending for the platform admins
  j := pg_temp.probe_call(u5, format('public.moderate_community_content(%L::uuid, %L, %L)', v_r_person, 'hide', 'Probe'));
  perform pg_temp.probe_ok(v_probe, 'a person report cannot be hidden: ' || j::text, pg_temp.probe_refused(j));
  j := pg_temp.probe_call(u5, format('public.moderate_community_content(%L::uuid, %L, %L)', v_r_person, 'dismiss', null));
  perform pg_temp.probe_ok(v_probe, 'the admin dismisses it for the community: ' || j::text,
    coalesce(j ->> 'success', '') = 'true'
    and exists (select 1 from public.reports
                 where id = v_r_person and community_status = 'dismissed' and status = 'pending' and reviewed_by is null)
    and exists (select 1 from public.content_moderation_events
                 where report_id = v_r_person and action = 'dismiss' and acted_by = u5));
  v_list := pg_temp.probe_call(u4, format($q$public.get_community_reports(%L::uuid, 'dismissed')$q$, c1));
  perform pg_temp.probe_ok(v_probe, 'the owner''s Dismissed list holds it: ' || v_list::text,
    exists (select 1 from jsonb_array_elements(v_list -> 'reports') e where (e ->> 'report_id')::uuid = v_r_person));
  v_list := pg_temp.probe_call(u4, format($q$public.get_community_reports(%L::uuid, 'pending')$q$, c1));
  perform pg_temp.probe_ok(v_probe, 'the owner''s Pending list does not',
    not exists (select 1 from jsonb_array_elements(v_list -> 'reports') e where (e ->> 'report_id')::uuid = v_r_person));
  j := pg_temp.probe_run(v_admin, format($q$select coalesce(jsonb_agg(x.report_id), '[]'::jsonb)
                                            from public.admin_get_reports(%L::uuid, 'pending') x$q$, v_admin));
  perform pg_temp.probe_ok(v_probe, 'the platform admins'' pending queue still holds it', j @> to_jsonb(array[v_r_person]));
  j := pg_temp.probe_call(u4, format('public.moderate_community_content(%L::uuid, %L, %L)', v_r_person, 'dismiss', null));
  perform pg_temp.probe_ok(v_probe, 'a second dismissal is refused: ' || j::text,
    pg_temp.probe_refused(j) and j ->> 'code' = 'already_closed');

  -- (g) a community report never reaches community admins
  j := pg_temp.probe_call(u3, format($q$public.report_community(p_community_id => %L::uuid, p_code => null,
                                         p_report_type => 'spam', p_description => 'Probe community report')$q$, c1));
  v_r_community := (select id from public.reports where reporter_id = u3 and reported_community_id = c1 order by created_at desc limit 1);
  perform pg_temp.probe_ok(v_probe, 'the community report exists', v_r_community is not null);
  j := pg_temp.probe_call(u4, format('public.moderate_community_content(%L::uuid, %L, %L)', v_r_community, 'dismiss', null));
  perform pg_temp.probe_ok(v_probe, 'the owner cannot act on a report about the community: ' || j::text, pg_temp.probe_refused(j));
  v_list := pg_temp.probe_call(u4, format('public.get_community_reports(%L::uuid, null)', c1));
  perform pg_temp.probe_ok(v_probe, 'nor list it',
    not exists (select 1 from jsonb_array_elements(v_list -> 'reports') e where (e ->> 'report_id')::uuid = v_r_community));

  -- (h) platform moderation wins: a platform admin's hide and review close the report to the community
  v_post11 := pg_temp.probe_post(3, u11, c1);
  j := pg_temp.probe_call(u3, format($q$public.submit_report(%L::uuid, %L::uuid, null, %L::uuid, null, null, null,
                                         'spam', 'Probe platform-handled report')$q$, u3, u11, v_post11));
  v_r_post11 := (j #>> '{}')::uuid;
  perform pg_temp.probe_ok(v_probe, 'the report on the member''s post is filed: ' || j::text, v_r_post11 is not null);
  j := pg_temp.probe_call(v_admin, format('public.admin_moderate_content(%L::uuid, %L::uuid, %L, %L)',
                                          v_admin, v_r_post11, 'hide', 'Probe platform hide'));
  perform pg_temp.probe_ok(v_probe, 'a platform admin hides it through admin_moderate_content: ' || j::text,
    not pg_temp.probe_refused(j)
    and (select hidden_by from public.town_hall_posts where id = v_post11) = v_admin
    and (select status from public.reports where id = v_r_post11) = 'action_taken');
  v_list := pg_temp.probe_call(u4, format('public.get_community_reports(%L::uuid, null)', c1));
  perform pg_temp.probe_ok(v_probe, 'the owner''s list reads it platform-handled and not restorable: ' || v_list::text,
    exists (select 1 from jsonb_array_elements(v_list -> 'reports') e
             where (e ->> 'report_id')::uuid = v_r_post11 and e ->> 'status' = 'action_taken'
               and (e ->> 'platform_handled')::boolean and not (e ->> 'can_restore')::boolean));
  j := pg_temp.probe_call(u4, format('public.moderate_community_content(%L::uuid, %L, %L)', v_r_post11, 'restore', null));
  perform pg_temp.probe_ok(v_probe, 'the owner cannot restore a platform admin''s hide: ' || j::text,
    pg_temp.probe_refused(j) and j ->> 'code' = 'platform_hidden'
    and (select hidden_by from public.town_hall_posts where id = v_post11) = v_admin);
  j := pg_temp.probe_call(u5, format('public.moderate_community_content(%L::uuid, %L, %L)', v_r_post11, 'dismiss', null));
  perform pg_temp.probe_ok(v_probe, 'nor dismiss the report a platform admin reviewed: ' || j::text,
    pg_temp.probe_refused(j) and j ->> 'code' = 'platform_handled');
  j := pg_temp.probe_call(u5, format('public.moderate_community_content(%L::uuid, %L, %L)', v_r_post11, 'hide', 'Probe'));
  perform pg_temp.probe_ok(v_probe, 'nor hide on it: ' || j::text,
    pg_temp.probe_refused(j) and j ->> 'code' = 'platform_handled');
  perform pg_temp.probe_ok(v_probe, 'the platform admin''s decision is intact',
    exists (select 1 from public.reports
             where id = v_r_post11 and status = 'action_taken' and reviewed_by = v_admin and community_status is null));

  -- (i) the 3-reporter auto-hide (hidden_by null) is restored only by platform admins
  v_post7b := pg_temp.probe_post(4, u7, c1);
  j := pg_temp.probe_call(u3, format($q$public.submit_report(%L::uuid, %L::uuid, null, %L::uuid, null, null, null,
                                         'spam', 'Probe auto-hide 1')$q$, u3, u7, v_post7b));
  j := pg_temp.probe_call(u11, format($q$public.submit_report(%L::uuid, %L::uuid, null, %L::uuid, null, null, null,
                                          'spam', 'Probe auto-hide 2')$q$, u11, u7, v_post7b));
  j := pg_temp.probe_call(u5, format($q$public.submit_report(%L::uuid, %L::uuid, null, %L::uuid, null, null, null,
                                         'spam', 'Probe auto-hide 3')$q$, u5, u7, v_post7b));
  v_r_auto := (j #>> '{}')::uuid;
  perform pg_temp.probe_ok(v_probe, 'three distinct reporters auto-hide the post, hidden_by null: ' || j::text,
    v_r_auto is not null
    and exists (select 1 from public.town_hall_posts where id = v_post7b and hidden_at is not null and hidden_by is null)
    and exists (select 1 from public.content_moderation_events
                 where target_id = v_post7b and action = 'auto_hide' and acted_by is null));
  v_list := pg_temp.probe_call(u4, format('public.get_community_reports(%L::uuid, null)', c1));
  perform pg_temp.probe_ok(v_probe, 'the owner''s list offers no restore for it',
    exists (select 1 from jsonb_array_elements(v_list -> 'reports') e
             where (e ->> 'report_id')::uuid = v_r_auto and (e ->> 'content_hidden')::boolean
               and not (e ->> 'can_restore')::boolean));
  j := pg_temp.probe_call(u4, format('public.moderate_community_content(%L::uuid, %L, %L)', v_r_auto, 'restore', null));
  perform pg_temp.probe_ok(v_probe, 'the owner cannot undo the auto-hide: ' || j::text,
    pg_temp.probe_refused(j) and j ->> 'code' = 'platform_hidden'
    and (select hidden_at from public.town_hall_posts where id = v_post7b) is not null);
  j := pg_temp.probe_call(u4, format('public.moderate_community_content(%L::uuid, %L, %L)', v_r_auto, 'hide', 'Probe takeover'));
  perform pg_temp.probe_ok(v_probe, 'nor take it over by hiding it again: ' || j::text,
    pg_temp.probe_refused(j) and j ->> 'code' = 'already_hidden'
    and (select hidden_by from public.town_hall_posts where id = v_post7b) is null);
  j := pg_temp.probe_call(v_admin, format('public.moderate_community_content(%L::uuid, %L, %L)', v_r_auto, 'restore', null));
  perform pg_temp.probe_ok(v_probe, 'a platform admin may restore it here (admin_moderate_content gives them that already): ' || j::text,
    coalesce(j ->> 'success', '') = 'true'
    and (select hidden_at from public.town_hall_posts where id = v_post7b) is null);

  -- (j) an archived community's reports are out of reach
  perform set_config('request.jwt.claims', '', true);
  update public.communities set archived_at = now() where id = c1;
  j := pg_temp.probe_call(u4, format('public.get_community_reports(%L::uuid, null)', c1));
  perform pg_temp.probe_ok(v_probe, 'after archiving, the owner is refused: ' || j::text, pg_temp.probe_refused(j));

  raise notice 'PROBE % OK', v_probe;
end
$probe$;
rollback;
select 'PROBE community_moderation OK' as probe;


-- =============================================================================================================
-- admin_community_reports (Phase 3 carry-over, File A blocks 6-8, D-S1): admin_get_reports lists a community
-- report as target 'community' with the community's name; a platform admin dismisses it through
-- admin_moderate_content, which logs one content_moderation_events row with target_type 'community'; Hide on it
-- raises; a caller who is not a platform admin (here the community's own owner) is refused.
-- =============================================================================================================
begin;
do $probe$
declare
  v_probe constant text := 'admin_community_reports';
  v_admin uuid := pg_temp.probe_subject('platform_admin');
  u3 uuid := pg_temp.u(3);  u4 uuid := pg_temp.u(4);
  c1 uuid := pg_temp.c(1);
  v_r uuid;
  v_rows jsonb;
  j jsonb;
begin
  perform pg_temp.probe_require_phase3(v_probe);
  if not exists (select 1 from pg_catalog.pg_constraint
                  where conname = 'content_moderation_events_target_type_check'
                    and pg_catalog.pg_get_constraintdef(oid) like '%community%') then
    raise exception 'PROBE % FAILED: File A blocks 6-8 are not live (D-S1)', v_probe;
  end if;
  perform pg_temp.probe_world();

  j := pg_temp.probe_call(u3, format($q$public.report_community(p_community_id => %L::uuid, p_code => null,
                                         p_report_type => 'spam', p_description => 'Probe community report')$q$, c1));
  v_r := (select id from public.reports where reporter_id = u3 and reported_community_id = c1 order by created_at desc limit 1);
  perform pg_temp.probe_ok(v_probe, 'the community report exists: ' || j::text, v_r is not null);

  v_rows := pg_temp.probe_run(v_admin, format($q$select coalesce(jsonb_agg(to_jsonb(x)), '[]'::jsonb)
                                                 from public.admin_get_reports(%L::uuid, 'pending') x
                                                where x.report_id = %L::uuid$q$, v_admin, v_r));
  perform pg_temp.probe_ok(v_probe, 'admin_get_reports lists it as a community target with the name as preview: ' || v_rows::text,
    jsonb_typeof(v_rows) = 'array' and jsonb_array_length(v_rows) = 1
    and v_rows -> 0 ->> 'target_type' = 'community'
    and v_rows -> 0 ->> 'content_preview' = 'Probe Community One'
    and (v_rows -> 0 ->> 'reporter_id')::uuid = u3);

  j := pg_temp.probe_call(v_admin, format('public.admin_moderate_content(%L::uuid, %L::uuid, %L, %L)',
                                          v_admin, v_r, 'hide', 'Probe hide'));
  perform pg_temp.probe_ok(v_probe, 'Hide on a community report raises: ' || j::text,
    coalesce(j ->> 'raised', '') = 'true' and (select status from public.reports where id = v_r) = 'pending');

  j := pg_temp.probe_call(u4, format('public.admin_moderate_content(%L::uuid, %L::uuid, %L, %L)',
                                     u4, v_r, 'dismiss', null));
  perform pg_temp.probe_ok(v_probe, 'the community''s owner, not a platform admin, is refused: ' || j::text,
    coalesce(j ->> 'raised', '') = 'true' and (select status from public.reports where id = v_r) = 'pending');
  j := pg_temp.probe_run(u4, format($q$select coalesce(jsonb_agg(x.report_id), '[]'::jsonb)
                                       from public.admin_get_reports(%L::uuid, null) x$q$, u4));
  perform pg_temp.probe_ok(v_probe, 'and cannot list platform reports: ' || j::text, coalesce(j ->> 'raised', '') = 'true');

  j := pg_temp.probe_call(v_admin, format('public.admin_moderate_content(%L::uuid, %L::uuid, %L, %L)',
                                          v_admin, v_r, 'dismiss', 'Probe dismissal'));
  perform pg_temp.probe_ok(v_probe, 'the platform admin dismisses it: ' || j::text,
    not pg_temp.probe_refused(j)
    and exists (select 1 from public.reports
                 where id = v_r and status = 'dismissed' and reviewed_by = v_admin and admin_notes = 'Probe dismissal'));
  perform pg_temp.probe_ok(v_probe, 'one dismiss event with target_type community and the community as target',
    (select count(*) from public.content_moderation_events
      where report_id = v_r and target_type = 'community' and target_id = c1
        and action = 'dismiss' and acted_by = v_admin) = 1);

  raise notice 'PROBE % OK', v_probe;
end
$probe$;
rollback;
select 'PROBE admin_community_reports OK' as probe;


-- =============================================================================================================
-- community_stats (Phase 3): get_community_stats and the three breakdowns read only the community's requests;
-- members, other communities and anon are refused; the null scope is platform admins only; the legacy admin_*
-- functions return the null scope's answer to a platform admin and refuse a community owner.
-- =============================================================================================================
begin;
do $probe$
declare
  v_probe constant text := 'community_stats';
  v_admin uuid := pg_temp.probe_subject('platform_admin');
  u3 uuid := pg_temp.u(3);  u4 uuid := pg_temp.u(4);  u12 uuid := pg_temp.u(12);
  c1 uuid := pg_temp.c(1);
  j jsonb;
  k jsonb;
begin
  perform pg_temp.probe_require_phase3(v_probe);
  perform pg_temp.probe_world();
  -- r(1): completed in C1; r(2): open in C1
  update public.rides set estimated_cost = 12.50 where id = pg_temp.r(1);

  j := pg_temp.probe_call(u4, format('public.get_community_stats(%L::uuid)', c1));
  perform pg_temp.probe_ok(v_probe, 'the owner reads C1''s figures: ' || j::text,
    coalesce(j ->> 'success', '') = 'true'
    and (j ->> 'fulfilled_count')::int = 1 and (j ->> 'active_rides_count')::int = 1
    and (j ->> 'total_savings')::numeric = 12.50);
  j := pg_temp.probe_call(u3, format('public.get_community_stats(%L::uuid)', c1));
  perform pg_temp.probe_ok(v_probe, 'a plain member is refused: ' || j::text, pg_temp.probe_refused(j));
  j := pg_temp.probe_call(u12, format('public.get_community_stats(%L::uuid)', c1));
  perform pg_temp.probe_ok(v_probe, 'another community''s owner is refused: ' || j::text, pg_temp.probe_refused(j));
  j := pg_temp.probe_call(u4, 'public.get_community_stats(null)');
  perform pg_temp.probe_ok(v_probe, 'the null (every community) scope is refused to a community owner: ' || j::text, pg_temp.probe_refused(j));
  j := pg_temp.probe_call(null, format('public.get_community_stats(%L::uuid)', c1), 'anon');
  perform pg_temp.probe_ok(v_probe, 'anon cannot call it: ' || j::text, coalesce(j ->> 'raised', '') = 'true');

  j := pg_temp.probe_call(u4, format('public.get_community_stats_active_requests(%L::uuid)', c1));
  perform pg_temp.probe_ok(v_probe, 'active requests: C1''s open ride, and nothing from another community: ' || j::text,
    coalesce(j ->> 'success', '') = 'true'
    and exists (select 1 from jsonb_array_elements(j -> 'rows') e where (e ->> 'id')::uuid = pg_temp.r(2))
    and not exists (select 1 from jsonb_array_elements(j -> 'rows') e
                     where (e ->> 'id')::uuid not in (select id from public.rides where community_id = c1
                                                      union all select id from public.favors where community_id = c1)));
  j := pg_temp.probe_call(u4, format($q$public.get_community_stats_fulfilled(%L::uuid, 'month', 12)$q$, c1));
  perform pg_temp.probe_ok(v_probe, 'fulfilled breakdown counts C1''s one completed request: ' || j::text,
    coalesce(j ->> 'success', '') = 'true'
    and (select coalesce(sum((e ->> 'total_count')::int), 0) from jsonb_array_elements(j -> 'rows') e) = 1);
  j := pg_temp.probe_call(u4, format($q$public.get_community_stats_savings(%L::uuid, 'month', 12)$q$, c1));
  perform pg_temp.probe_ok(v_probe, 'savings breakdown sums C1''s estimate: ' || j::text,
    coalesce(j ->> 'success', '') = 'true'
    and (select coalesce(sum((e ->> 'total_savings')::numeric), 0) from jsonb_array_elements(j -> 'rows') e) = 12.50);

  -- the legacy wrappers
  j := pg_temp.probe_call(v_admin, 'public.get_community_stats(null)');
  k := pg_temp.probe_call(v_admin, 'public.admin_dashboard_stats()');
  perform pg_temp.probe_ok(v_probe, format('admin_dashboard_stats equals the every-community scope: %s vs %s', k, j), k = (j - 'success'));
  j := pg_temp.probe_call(v_admin, $q$public.get_community_stats_fulfilled(null, 'week', 12)$q$);
  k := pg_temp.probe_call(v_admin, $q$public.admin_stats_fulfilled('week', 12)$q$);
  perform pg_temp.probe_ok(v_probe, 'admin_stats_fulfilled equals the every-community rows', k = j -> 'rows');
  j := pg_temp.probe_call(v_admin, $q$public.get_community_stats_savings(null, 'year', 12)$q$);
  k := pg_temp.probe_call(v_admin, $q$public.admin_stats_savings('year', 12)$q$);
  perform pg_temp.probe_ok(v_probe, 'admin_stats_savings equals the every-community rows', k = j -> 'rows');
  j := pg_temp.probe_run(v_admin, $q$select coalesce(jsonb_agg(e order by e ->> 'id'), '[]'::jsonb)
                                     from jsonb_array_elements(public.get_community_stats_active_requests(null) -> 'rows') e$q$);
  k := pg_temp.probe_run(v_admin, $q$select coalesce(jsonb_agg(e order by e ->> 'id'), '[]'::jsonb)
                                     from jsonb_array_elements(public.admin_stats_active_rides()::jsonb) e$q$);
  perform pg_temp.probe_ok(v_probe, 'admin_stats_active_rides equals the every-community rows (as a set)', k = j);
  j := pg_temp.probe_call(u4, 'public.admin_dashboard_stats()');
  perform pg_temp.probe_ok(v_probe, 'a community owner who is not a platform admin is refused by the legacy function: ' || j::text,
    coalesce(j ->> 'raised', '') = 'true');

  raise notice 'PROBE % OK', v_probe;
end
$probe$;
rollback;
select 'PROBE community_stats OK' as probe;


-- =============================================================================================================
-- broadcast_cap (Phase 3, D14): announcement-typed rows a plain member writes do not count; a platform admin's
-- fourth announcement within 24 hours in one community is refused with P0001, as a community admin's already was;
-- the installed admin build's wrapper (default community) is capped the same way.
-- =============================================================================================================
begin;
do $probe$
declare
  v_probe constant text := 'broadcast_cap';
  v_admin uuid := pg_temp.probe_subject('platform_admin');
  u3 uuid := pg_temp.u(3);  u4 uuid := pg_temp.u(4);
  c1 uuid := pg_temp.c(1);
  d uuid;
  v_existing int;
  n int;
  j jsonb;
begin
  perform pg_temp.probe_require_phase3(v_probe);
  perform pg_temp.probe_world();
  d := public.default_community_id();

  -- (a) three rows typed 'announcement' by a plain member of C1: what town_hall_posts_insert_active_user lets an
  --     active member write (it does not restrict type). Written as the table owner so the case does not depend on
  --     the probe account's approval flags; the cap must not count them.
  perform set_config('request.jwt.claims', '', true);
  insert into public.town_hall_posts (user_id, title, content, type, community_id)
  select u3, 'Probe member announcement ' || g, 'communities probe', 'announcement', c1
    from generate_series(1, 3) g;

  for n in 1..3 loop
    j := pg_temp.probe_call(v_admin, format($q$public.send_community_broadcast(%L::uuid, %L, %L, false)$q$,
                                            c1, 'Probe announcement ' || n, 'communities probe'));
    perform pg_temp.probe_ok(v_probe, format('the platform admin''s announcement %s in C1 is sent: %s', n, j), not pg_temp.probe_refused(j));
  end loop;
  j := pg_temp.probe_call(v_admin, format($q$public.send_community_broadcast(%L::uuid, %L, %L, false)$q$,
                                          c1, 'Probe announcement 4', 'communities probe'));
  perform pg_temp.probe_ok(v_probe, 'the platform admin''s fourth in 24 hours is refused with P0001: ' || j::text,
    coalesce(j ->> 'raised', '') = 'true' and j ->> 'sqlstate' = 'P0001');
  j := pg_temp.probe_call(u4, format($q$public.send_community_broadcast(%L::uuid, %L, %L, false)$q$,
                                     c1, 'Probe owner announcement', 'communities probe'));
  perform pg_temp.probe_ok(v_probe, 'the owner is refused too (the cap is per community): ' || j::text,
    coalesce(j ->> 'raised', '') = 'true' and j ->> 'sqlstate' = 'P0001');
  perform pg_temp.probe_ok(v_probe, 'C1 holds six announcement rows, three of them by the platform admin',
    (select count(*) from public.town_hall_posts where community_id = c1 and type = 'announcement') = 6
    and (select count(*) from public.town_hall_posts
          where community_id = c1 and type = 'announcement' and user_id = v_admin) = 3);

  -- the installed admin build's wrapper posts into the default community
  -- the same counting rule as the function: announcements by platform admins and by the community's staff
  v_existing := (select count(*)::int from public.town_hall_posts t
                   left join public.profiles a on a.id = t.user_id
                  where t.community_id = d and t.type = 'announcement' and t.created_at > now() - interval '24 hours'
                    and (coalesce(a.is_admin, false) or public.is_community_staff(d, t.user_id)));
  for n in 1..greatest(3 - v_existing, 0) loop
    j := pg_temp.probe_call(v_admin, format($q$public.send_broadcast_notifications(%L, %L, 'broadcast', false)$q$,
                                            'Probe wrapper ' || n, 'communities probe'));
    perform pg_temp.probe_ok(v_probe, format('wrapper announcement %s is sent: %s', n, j), not pg_temp.probe_refused(j));
  end loop;
  j := pg_temp.probe_call(v_admin, $q$public.send_broadcast_notifications('Probe wrapper over', 'communities probe', 'broadcast', false)$q$);
  perform pg_temp.probe_ok(v_probe, 'the wrapper refuses the platform admin once the default community has three today: ' || j::text,
    coalesce(j ->> 'raised', '') = 'true' and j ->> 'sqlstate' = 'P0001');

  raise notice 'PROBE % OK', v_probe;
end
$probe$;
rollback;
select 'PROBE broadcast_cap OK' as probe;


-- =============================================================================================================
-- posts_delete_policy (Phase 3, spec §3.4)   ** SQL editor (owner): this block holds DELETE statements, which
-- the MCP's permission layer declines. Paste PARAMETERS, HELPERS and this block. **
-- A community admin may remove a member's post in their community, not an owner's post; a plain member may not
-- remove another member's post; the owner of another community may not; an author may remove their own.
-- =============================================================================================================
begin;
do $probe$
declare
  v_probe constant text := 'posts_delete_policy';
  u3 uuid := pg_temp.u(3);  u4 uuid := pg_temp.u(4);  u5 uuid := pg_temp.u(5);  u7 uuid := pg_temp.u(7);  u12 uuid := pg_temp.u(12);
  c1 uuid := pg_temp.c(1);
  v_p3 uuid;  v_p4 uuid;  v_p7 uuid;  v_p7b uuid;
  v_sql constant text := $q$with x as (delete from public.town_hall_posts where id = %L returning 1)
                            select to_jsonb(count(*)) from x$q$;
  j jsonb;
begin
  perform pg_temp.probe_require_phase3(v_probe);
  perform pg_temp.probe_world();
  v_p3  := pg_temp.probe_post(11, u3, c1);
  v_p4  := pg_temp.probe_post(12, u4, c1);   -- the owner's
  v_p7  := pg_temp.probe_post(13, u7, c1);
  v_p7b := pg_temp.probe_post(14, u7, c1);

  j := pg_temp.probe_run(u3, format(v_sql, v_p7));
  perform pg_temp.probe_ok(v_probe, 'a plain member cannot remove another member''s post: ' || j::text, j = '0'::jsonb);
  j := pg_temp.probe_run(u12, format(v_sql, v_p7b));
  perform pg_temp.probe_ok(v_probe, 'another community''s owner cannot: ' || j::text, j = '0'::jsonb);
  j := pg_temp.probe_run(u5, format(v_sql, v_p7));
  perform pg_temp.probe_ok(v_probe, 'C1''s admin removes a member''s post: ' || j::text, j = '1'::jsonb);
  j := pg_temp.probe_run(u5, format(v_sql, v_p4));
  perform pg_temp.probe_ok(v_probe, 'C1''s admin cannot remove the owner''s post: ' || j::text, j = '0'::jsonb);
  j := pg_temp.probe_run(u3, format(v_sql, v_p3));
  perform pg_temp.probe_ok(v_probe, 'an author removes their own post: ' || j::text, j = '1'::jsonb);

  raise notice 'PROBE % OK', v_probe;
end
$probe$;
rollback;
select 'PROBE posts_delete_policy OK' as probe;
```

---

## Deviations and choices the owner can veto

- **D-S1. Admin → Reports learns community reports (File A blocks 6-8).** Spec §3.5 says `admin_get_reports` and `admin_moderate_content` stay "unchanged in every phase"; the intent recorded there is that they are never widened to community admins and keep returning the reporter to platform admins, which these blocks keep. They add only a `community` target (name as preview; dismiss only), because the Phase 2 gate recorded that community reports cannot be resolved from the app (`Docs/qa/2026-10-18-multi-community-phase2-gate.md`, follow-ups; the uncommitted `[P2-fix]` client in `AdminModerationService.swift` already reads `targetType == "community"`). To keep the two functions untouched, drop blocks 6-8; the Communities list's "Reported" marker then stays until a later change.
- **D-S2. The DELETE policy protects owners' and admins' posts (File A block 5).** The spec gives the predicate as `community_id = any((select my_admin_community_ids()))` alone. The extra `not exists` keeps INV-P2 rule 3's principle (an admin does not act on a fellow admin's content) on a path no client uses. Without it, a plain admin could remove the owner's post with a direct API call.
- **D-S3. The legacy statistics wrappers answer "every community" (File B blocks 6-9).** Spec §3.5 says they resolve "as above". The installed admin build is reachable only by platform admins, whose numbers already covered every community; resolving them to the default community would shrink the installed build's figures as soon as a second community has activity. The new functions take a null community for exactly that view, which the Phase 3 client calls "All communities".
- **D-S4. `get_community_reports` returns `author_id` / `author_name` and a jsonb envelope.** The spec describes it as the rows of `admin_get_reports`; a content report's author is the person the admin needs to see, and the envelope lets the client tell "not an admin" from "no reports" (the `get_community_members` table shape cannot).
- **D-S5. A platform admin's `moderate_community_content` follows the same INV-P2 exclusions as a community admin's,** but passes the three "platform moderation wins" checks of D-S7 (it already holds those powers through `admin_moderate_content`). Platform admins handle reports about owners and admins through `admin_moderate_content`, which keeps the reporter; one INV-P2 rule for the community surface is simpler to probe.
- **D-S6. Push routing by payload.** Community-admin pushes carry `community_id`; platform-admin pushes keep today's data (no `community_id`). The client routes a `content_reported` push to the community list only when the key is present, so a platform admin's push never needs a client-side role check (the iOS plan, Task 8).
- **D-S7. Platform moderation wins over a community admin, and a community admin never changes the platform admins' queue (File A blocks 1, 3, 4).** The spec gives community admins hide / unhide / dismiss without saying what happens when a platform admin or the 3-reporter auto-hide got there first. In a tiny or hostile community the platform admins are the real moderators (spec §5 "Moderation" row; App Store 1.2), so for a caller who is not a platform admin: (1) restore only of content the caller, or another owner or admin of the community who is not a platform admin, hid: never a platform admin's hide, never the auto-hide (`hidden_by` null); (2) no hide of content that is already hidden, which closes the route "hide over the platform's hide, take over `hidden_by`, then restore"; (3) no hide or dismiss on a report a platform admin reviewed (`status <> 'pending'`; after this file only `admin_moderate_content` moves `status`, and `reviewed_by` is then that platform admin); (4) the community's decision is stored in `reports.community_status` / `community_reviewed_at`, never in `status` / `reviewed_*`, so every report stays pending in Admin → Reports until a platform admin reviews it, and a hide followed by a restore cannot clear the platform queue either. `get_community_reports` shows the community its own decision (`status`), and `platform_handled` / `can_restore` so the client offers only what the server allows. Costs: two nullable columns on `reports` (no client reads the table; a reporter's own-row SELECT now also returns the two columns of their own report, which say only that the community acted); in the installed build's Admin → Reports a pending report whose content a community admin hid carries the existing "Auto-hidden" label (a later `admin_get_reports` with the community decision can label it; follow-up). To give community decisions platform effect instead, drop block 1's columns and write `status` / `reviewed_*` as before; the probe sections (e), (f), (h), (i) then need rewriting.
- **D-S8. The broadcast cap counts only announcements by platform admins and the community's owners and admins (File B block 10).** `town_hall_posts_insert_active_user` does not restrict `type`, so a member can insert rows typed `'announcement'`; counting them would let any member lock the community, platform admins included, out of announcements for a day. Roles are read when the new announcement is sent (no role history exists), so a demoted admin's earlier announcements stop counting; that only loosens the cap. **Follow-up, not in this phase:** a member-written row typed `'announcement'` still exists and may be shown as an announcement in the feed; guarding `type = 'announcement'` against client inserts and updates (a trigger that lets definer functions through) is the real fix and needs its own check of every server path that writes that type.
