-- 20261021_0022_community_merge.sql
--
-- APPLIED 2026-10-22, all ten blocks, through the Supabase MCP apply_migration, one call per block, in file order,
-- each block's text sent byte for byte from this file (from its banner to its last statement), after the rolled-back
-- dry run below passed. Migration-history versions (UTC): 20261022142444 20261021_0022_block_1, 20261022142621
-- 20261021_0022_block_2, 20261022142827 20261021_0022_block_3, 20261022142951 20261021_0022_block_4, 20261022143120
-- 20261021_0022_block_5, 20261022143245 20261021_0022_block_6, 20261022143413 20261021_0022_block_7, 20261022143538
-- 20261021_0022_block_8, 20261022143715 20261021_0022_block_9, 20261022143838 20261021_0022_block_10. No deviation:
-- every block ran as written below.
-- Deployed md5(prosrc), each read live after the apply and equal to the md5 of the text between this file's
-- $function$ delimiters (python3 -I over this file):
--   post_community_announcement(uuid, uuid, text, text, boolean, text, text, jsonb)
--                                                    1b18ac7ae87be252dffd5a7e41e17f31  new, internal
--   send_community_broadcast(uuid, text, text, boolean, text)
--                                                    1eab19f9d963821f0fcb5567ff97827b
--                                                    (was 1f4f2dfbe34141fa821967370d33a309)
--   merge_communities(uuid, uuid)                    9f13c599d609799e7c09601abe12b927  new, internal
--   search_merge_targets(uuid, text)                 f805e30122fb885018e6e139c4864541  new, stable
--   propose_community_merge(uuid, uuid, uuid, text)  71a9052450623653c2f6ffc0bac5cd8a  new
--   get_community_merge_proposal(uuid)               efb45b83f5424c5ae1195299e3a54142  new, stable
--   respond_to_community_merge(uuid, boolean)        ec309323b409e8a78a428745df5c3120  new
--   withdraw_community_merge(uuid)                   8454ecfdf8ddc0bcb4adc767d8287acb  new
--   get_my_community_merges()                        b025835dc0e9c80f72a1259427a5d562  new, stable
--   get_platform_communities()                       451f840aa2a66bc98ba38383fae61c7e
--                                                    (was a44cdb53dbbd040504e56bf7aa853494)
--   unarchive_community(uuid)                        9d22b665159f74c60efa3b74bf75d838
--                                                    (was b1fccb2583e0b20a61300da30ec3b419)
--   All eleven are plpgsql, security definer, search_path "".
-- ACL (proacl; has_function_privilege anon / authenticated / service_role), read live after the apply (ruling R-G1):
--   search_merge_targets, propose_community_merge, get_community_merge_proposal, respond_to_community_merge,
--     withdraw_community_merge, get_my_community_merges, and the re-created send_community_broadcast,
--     get_platform_communities and unarchive_community:
--     {postgres=X/postgres,authenticated=X/postgres,service_role=X/postgres}; false / true / true. For the three
--     re-created functions this is the live ACL restated unchanged (read before the apply: the same text).
--   post_community_announcement, merge_communities: {postgres=X/postgres,service_role=X/postgres};
--     false / false / true (internal; revoked from public, anon and authenticated).
-- After the apply: community_merge_proposals is empty, no community is merged, no post carries a system_event, the
-- three set_updated_at triggers are enabled, and no probe row was left behind (counted).
--
-- Closing run (task S6), 2026-10-22, after S5a's data (Test Community's area, the four test communities flagged
-- is_test, 4 example rides, 4 example favors and 3 example posts in Test Community). The whole probe file
-- (supabase/probes/communities_probe.sql, unchanged) ran through the MCP in seven rolled-back execute_sql calls,
-- PARAMETERS and HELPERS in each (the call for legacy_bridges .. blocks carried HELPERS up to probe_world, every
-- helper those blocks call), full-line comments stripped, text otherwise as committed: 34 blocks,
-- every one PROBE ... OK (legacy_bridges returns SKIPPED, as it has since 20261019_0060), each call's last row its
-- last block's OK. posts_delete_policy and storage_private are the owner's SQL-editor blocks; the final
-- 'PROBE ALL OK' row comes from the owner's whole-file run. Nothing was left behind (counted afterwards: no probe
-- account, community, request, post, proposal, listing event or merged community; 11 example rows, 4 test
-- communities, the cron job active, the five status and updated_at triggers enabled).
-- EXECUTE matrix (ruling R-G1 as amended after S1), read live: md5(prosrc) of all eleven functions equal the values
-- above. search_merge_targets, propose_community_merge, get_community_merge_proposal, respond_to_community_merge,
-- withdraw_community_merge, get_my_community_merges, send_community_broadcast, get_platform_communities,
-- unarchive_community: anon false, authenticated true. post_community_announcement, merge_communities: anon false,
-- authenticated false. community_merge_proposals is empty and no community is merged. No header or grant changed.
--
-- File C of Community Release 2 (discovery: community areas, search, listing rules, merging, example content;
-- Docs/superpowers/specs/2026-10-21-community-discovery-and-trust-design.md 4.12; plan
-- Docs/superpowers/plans/2026-10-21-community-release2-discovery-sql.md, task S3, with the orchestrator's rulings
-- R-G1, R1, R2, R5, R13, R14, R15, R16, R17, R22 and R23). Two owners merge their communities: proposals, the
-- answer, one transaction that moves members and content, the notices, and a merge that cannot be undone. Built on
-- File A (20261021_0020: communities.merged_into_id / merged_at, community_merge_proposals, the 'merged' membership
-- event, town_hall_posts.system_event) and File B (20261021_0021: can_discover_community's discoverable rule,
-- get_platform_communities and get_community_preview's 'merged' answer).
--
-- What it does. Refusals are {"success": false, "error", "code"}; codes not_owner, invalid, default_community,
-- merge_pending, recently_declined, proposal_closed, rate_limited.
--   * Block 1, post_community_announcement(...) -> integer (new; internal): the announcement post (written with
--     naars.broadcast_post = '1' so notify_town_hall_post adds no Town Hall notice, and with system_event =
--     p_system_event) and the recipient loop of the live send_community_broadcast, moved verbatim: every unmuted,
--     unbanned active member but the author gets a bell row and one immediate push whose data is {community_id,
--     town_hall_post_id} || p_push_data (plus notification_id, added by queue_push_notification). Returns the number
--     of bell rows. No permission check, no cap.
--   * Block 2, send_community_broadcast (same signature): the live refusals, advisory lock and D14 cap, which now
--     counts only posts with no system_event, then post_community_announcement(..., v_type, null, '{}'). Behaviour is
--     otherwise unchanged (probes broadcast_cap and broadcast_push).
--   * Block 3, merge_communities(p_proposal_id, p_actor) -> jsonb (new; internal; called only by
--     respond_to_community_merge). One body inside begin ... exception when lock_not_available (lock_timeout 5s) ->
--     rate_limited. S is the survivor, M the other community. The proposal is locked and must be pending; both
--     community rows are locked in id order and must be unarchived (else proposal_closed). Members of M, active
--     rows first: active in M and nothing in S -> inserted active in S with ROLE (owner and admin -> admin, member ->
--     member), M's joined_at, activated_at, notifications_muted and muted_until; active in both -> the higher role
--     (owner > admin > member); pending or left in S -> active, ROLE, M's activated_at, ended_at null (ruling R13);
--     removed from S -> stays removed, unwind_member_requests(M, user) runs before the content moves, and the person
--     gets M's archive notice '<M> was archived' (announcement, no push; ruling R15); pending in M and nothing in S ->
--     inserted pending in S with M's heard_about, join_reason and invited_by (notify_pending_membership tells S's
--     owners and admins, push included; ruling R14); pending in M with any S row, and left or removed in M -> nothing.
--     These writes run with naars.suppress_approval_notice = '1'. M's own rows stay as they were. Every person moved
--     whose primary community was M gets S, written under naars.membership_mirror = '1' and reset to the previous
--     value (ruling R1; protect_admin_fields refuses the column under a non-admin JWT). Content: rides, favors and
--     town_hall_posts move to S with set_updated_at_rides / _favors / _town_hall_posts disabled for those three
--     updates and re-enabled in the same body (the 20261017_0001 [call] 1f.1 idiom, so completed history keeps its
--     updated_at); then xp_events, notifications and reports (community_id only; reported_community_id stays M).
--     M's live invites are revoked. M is archived (archived_by the actor, merged_into_id S, merged_at), which fires
--     recompute_flags_on_archive after the moves; events: M 'archived' (reason 'merged into <S>'), S 'merged'
--     (reason 'merged <M name> (<M>)'). The proposal becomes accepted. One system announcement in S, 'Communities
--     merged' / '<from> and <to> are now one community: <S name>.', type announcement, system_event
--     'community_merged', push data {community_id, town_hall_post_id, community_event: 'merged'} (plus
--     notification_id), to every unmuted active member of S but the accepting owner. Returns {success, survivor_id,
--     merged_id}.
--   * Block 4, search_merge_targets(p_community_id, p_query) -> jsonb (new; stable): an active owner of the
--     community only (not_owner); the query trimmed and cut to 60 characters, fewer than 2 -> []; unarchived, not
--     default, not itself, not merged; a discoverable community whose name contains the text (case-insensitive,
--     strpos), or a hidden one whose trimmed name equals the text exactly; test communities only for their members
--     and platform admins; exact matches first, then name, id; at most 20 rows {id, name, join_policy, is_public,
--     member_count (active, unbanned), area_name (discoverable rows only, null otherwise; ruling R23)}.
--   * Block 5, propose_community_merge(p_community_id, p_other_id, p_survivor_id, p_note default null) -> jsonb
--     {success, proposal_id} (new): an active owner of p_community_id only (not_owner); the same id twice or no other
--     id -> invalid; transaction advisory locks on both ids, smaller first; pending proposals of either community past
--     expires_at become 'expired'; a survivor that is not one of the two, a note over 300 characters (trimmed), or an
--     other community that is missing, archived or merged -> invalid; either is the default -> default_community; a
--     pending proposal involving either -> merge_pending; one between the two, either direction, declined within 7
--     days -> recently_declined. The proposal is inserted (expires in 7 days) and every other active, unbanned owner
--     of the other community gets 'Merge proposal from <from>' / '<from> proposes making <from> and <to> one
--     community: <survivor>. Open Manage in <to> to accept or decline.' (announcement, bell row and push, community
--     the other one).
--   * Block 6, get_community_merge_proposal(p_community_id) -> jsonb (new; stable): an active owner or a platform
--     admin (not_owner); the newest pending, unexpired proposal with the community as from ('outgoing') or to
--     ('incoming'), {id, direction, from: {id, name, join_policy, member_count}, to: {...}, survivor_id, note,
--     proposed_by_name, created_at, expires_at}, or null.
--   * Block 7, respond_to_community_merge(p_proposal_id, p_accept) -> jsonb (new): the proposal is locked; not
--     pending -> proposal_closed; past expires_at -> marked expired, proposal_closed; either community archived ->
--     marked withdrawn, proposal_closed (before the role check: an archived community answers no role); the caller
--     not an active owner of the 'to' community -> not_owner; decline -> declined, decided_*, and the other active
--     owners of the 'from' community get 'Merge declined' / '<to> declined merging with <from>.' (no push); accept ->
--     merge_communities(p_proposal_id, caller).
--   * Block 8, withdraw_community_merge(p_proposal_id) -> jsonb (new): an active owner of either community
--     (not_owner); not pending -> proposal_closed; withdrawn, decided_*; the other community's other active owners
--     get 'Merge proposal withdrawn' / '<caller's community> withdrew the merge proposal.' (no push).
--   * Block 9, get_my_community_merges() -> jsonb {success, merges: [{merged_id, merged_name, survivor_id,
--     survivor_name, merged_at}]} (new; stable): communities merged in the last 90 days in which the caller had an
--     active membership; and get_platform_communities() from its live body (20261021_0021 Block 8, ruling R5) with
--     merge_proposals filled: every proposal pending and unexpired, or decided or expired within 30 days, newest
--     first, {id, from_id, from_name, to_id, to_name, survivor_id, survivor_name, status (a pending one past
--     expires_at reads 'expired'), note, created_at, expires_at, decided_at}.
--   * Block 10 (ruling R16), unarchive_community(uuid) from its live body: the update also requires merged_into_id is
--     null, and a merged community answers 'This community was merged and cannot be restored'. A merge is
--     irreversible (spec 4.12).
--
-- Ruling R22. respond_to_community_merge (a client call) disables and re-enables set_updated_at_rides, _favors and
-- _town_hall_posts inside merge_communities: the call holds SHARE ROW EXCLUSIVE on rides, favors and
-- town_hall_posts until it commits (a member's concurrent edit waits for it; lock_timeout 5s turns a wait on the
-- locks into rate_limited), and each merge causes one PostgREST schema-cache reload, as the nightly
-- expire_past_open_requests already does.
--
-- What old clients see. Installed builds (Release 1 and earlier) call none of Blocks 3-9's new RPCs. An
-- announcement sent from an installed build behaves as before (same refusals, cap, bell rows and pushes). Once a
-- Release 2 client merges, members on installed builds get one 'Communities merged' announcement push and bell row
-- in the survivor (their builds open announcements), the merged community leaves their memberships as an archived
-- community, and its preview answers code 'merged', which a Release 1 build shows as its generic load-failed state.
-- get_platform_communities answers merge_proposals with rows instead of [], which installed builds ignore.
-- unarchive_community refuses a merged community; no merged community exists until a Release 2 client merges.
--
-- Apply order. Blocks 1-10 in file order, one Supabase MCP apply_migration per block, named
-- 20261021_0022_block_<n>, each block's text byte for byte from this file (banner to last statement), after the
-- rolled-back dry run (supabase/dryruns/20261021_0022_community_merge.dryrun.sql) passed; probe short after each
-- block, broadcast_cap and broadcast_push after Block 2. Block 1 before Block 2 (send_community_broadcast calls it);
-- Block 3 before Block 7. Nothing here is declined by the MCP: the DDL inside merge_communities is function body
-- text, and the only deletes are inside unwind_member_requests, which is not edited here.
--
-- Verification (supabase/probes/communities_probe.sql; every run through execute_sql, rolled back, with the probe
-- PARAMETERS and the whole HELPERS section in the same call). Outcomes, 2026-10-22:
--   P0-P4 read before the file was written: P1 below equal to the live bodies and the source files' text; none of the
--   eight new functions existed; no 20261021_0022 file or migration-history entry; community_merge_proposals empty.
--   Dry run: supabase/dryruns/20261021_0022_community_merge.dryrun.sql, assembled by script from the committed files
--   (the same assembler reproduces 20261021_0021's committed dry run byte for byte), structural check passed (no
--   commit; one begin; one rollback; 6 savepoints and 6 releases; 6 PROBE selects; helpers before begin; last two
--   statements the DRYRUN select and rollback;), sent verbatim in one call: DRYRUN 20261021_0022 OK after
--   community_merge, broadcast_cap, broadcast_push, archive, listing_rules and short (each raises on its first failed
--   check, so the final row means all six passed), on the first attempt. Afterwards none of the eight new functions
--   existed and the three P1 md5 values were unchanged.
--   Apply: PROBE short OK after each of the ten blocks; after Block 2 also broadcast_cap and broadcast_push (one call,
--   last row PROBE broadcast_push OK). The P1 md5 values of get_platform_communities and unarchive_community were read
--   again just before Blocks 9 and 10: unchanged.
--   After Block 10: short, archive and community_merge in one call (last row PROBE community_merge OK), listing_rules
--   in another (PROBE listing_rules OK). No probe community, profile, proposal, merged community, system post,
--   'merged' event or merge notice was left behind (counted afterwards).
--
-- Implementer decisions (recorded for the review).
--   1. Ruling R16 names md5 9ed636b9f664f5301ea7147a1744b381 for unarchive_community; that is my_community_role's
--      deployed md5 (20261017_0005 header line 12). unarchive_community's live md5 is
--      b1fccb2583e0b20a61300da30ec3b419, equal to 20261017_0005's header value and to the md5 of that file's Block
--      14 text, so the live body has not drifted; Block 10 is derived from it and records it as the rollback source.
--      R16's block is numbered 10 (the brief's Blocks 1-9 keep their numbers).
--   2. Block 5 checks the caller's ownership (and a missing or identical other id) before the advisory locks and the
--      expiry update; the refusal order of the brief is kept, only the housekeeping does not run for a non-owner.
--   3. Notice loops (Blocks 5, 7, 8) skip banned accounts and the caller; create_notification already returns null for
--      a row whose source is its recipient, so skipping the caller changes nothing that is written (one owner of
--      both communities gets no notice of their own proposal).
--   4. respond_to_community_merge refuses p_accept null with code invalid (a null would otherwise reach the merge);
--      no signed-in caller -> not_owner; an unknown proposal -> proposal_closed (as in Block 8).
--   5. A proposal closed because a side was archived is 'withdrawn' with decided_at now() and decided_by null (the
--      caller did not decide it); an expired one keeps decided_at null. get_platform_communities' 30-day window uses
--      decided_at, or expires_at when there is none.
--   6. A pending proposal past expires_at can still be withdrawn (Block 8 checks only status = 'pending').
--   7. merge_communities re-reads and locks the proposal (pending) before step 1, although its only caller already
--      did; the applicant moved as pending keeps only heard_about, join_reason and invited_by (joined_at is the
--      move). Active rows are processed before pending ones, so admins moved from M also receive the
--      pending_approval rows for applicants moved from M (R14). Banned members are moved like any other.
--   8. search_merge_targets cuts the query to 60 characters and trims with btrim, as search_communities_by_name does.
--   9. Error texts not given by the brief are mine: 'Only the owner can merge this community' (not_owner), 'Choose
--      another community to merge with' (invalid), 'Choose accept or decline' (invalid, Block 7), 'The default
--      community cannot be merged', 'A merge proposal is already open for one of these communities', 'This merge
--      was declined in the last 7 days', 'This merge proposal is no longer open' (proposal_closed); 'Busy, try again'
--      (rate_limited) and R16's refusal are the brief's.
--   10. Probes: community_merge (new) also covers search_merge_targets, every function's EXECUTE / definer /
--      volatility, the R1, R14, R15 and R16 checks, and a stale pending proposal; listing_rules now reads
--      merge_proposals as a list without probe proposals (live proposals may exist after this file); the dry run ran
--      six probes (archive for Block 10 and listing_rules for Block 9 beside the brief's four).
--
-- P1, the live values read on 2026-10-22 before this file (the rollback sources; each equal to the md5 of the text
-- between its source file's delimiters, python3 -I):
--   send_community_broadcast(uuid, text, text, boolean, text)  1f4f2dfbe34141fa821967370d33a309
--     (20261019_0002 block 2)
--   get_platform_communities()                                 a44cdb53dbbd040504e56bf7aa853494
--     (20261021_0021 Block 8; ruling R5)
--   unarchive_community(uuid)                                  b1fccb2583e0b20a61300da30ec3b419
--     (20261017_0005 Block 14)
--
-- Rollback (in reverse order). No merge can be undone by rollback: a merge already done has moved members, content,
-- notifications and reports into the survivor and archived the merged community, and restoring the functions below
-- moves none of it back (after Block 10's rollback a platform admin could unarchive a merged community, but it would
-- come back empty, with its members already in the survivor).
--   Block 10 (MCP): unarchive_community(uuid) from 20261017_0005 Block 14 (md5 b1fccb2583e0b20a61300da30ec3b419); the
--     ACL stays as it is.
--   Block 9 (MCP): get_platform_communities() from 20261021_0021 Block 8 (md5 a44cdb53dbbd040504e56bf7aa853494); the
--     ACL stays as it is.
--   Block 2 (MCP): send_community_broadcast(uuid, text, text, boolean, text) from 20261019_0002 block 2 (md5
--     1f4f2dfbe34141fa821967370d33a309); the ACL stays as it is. Before Block 1's drop.
--   Blocks 1, 3-8 and Block 9's new function (SQL editor, owner; the MCP declines DROP FUNCTION), after the three
--   above:
--     drop function public.get_my_community_merges();
--     drop function public.withdraw_community_merge(uuid);
--     drop function public.respond_to_community_merge(uuid, boolean);
--     drop function public.get_community_merge_proposal(uuid);
--     drop function public.propose_community_merge(uuid, uuid, uuid, text);
--     drop function public.search_merge_targets(uuid, text);
--     drop function public.merge_communities(uuid, uuid);
--     drop function public.post_community_announcement(uuid, uuid, text, text, boolean, text, text, jsonb);
--   community_merge_proposals rows and 'merged' events written meanwhile stay (File A's tables; its own rollback
--   handles them).


-- ============================================================================================
-- BLOCK 1: public.post_community_announcement(uuid, uuid, text, text, boolean, text, text, jsonb)   (new; internal)
-- The announcement post and its recipient loop, moved verbatim from the live send_community_broadcast (20261019_0002
-- block 2, md5 1f4f2dfbe34141fa821967370d33a309), with the author, the notification type and the post's
-- system_event as arguments and p_push_data merged into each push's data. No permission check, no cap.
-- ============================================================================================
create or replace function public.post_community_announcement(
    p_community_id uuid,
    p_author uuid,
    p_title text,
    p_body text,
    p_pinned boolean,
    p_type text,
    p_system_event text,
    p_push_data jsonb
)
returns integer
language plpgsql
security definer
set search_path = ''
as $function$
declare
    v_post_id uuid;
    v_member record;
    v_notification_id uuid;
    v_inserted_count integer := 0;
begin
    -- The announcement has its own push below: notify_town_hall_post skips this one post (20261019_0002 block 1).
    perform set_config('naars.broadcast_post', '1', true);
    insert into public.town_hall_posts (
        user_id, title, content, pinned, type, community_id, created_at, updated_at, system_event
    ) values (
        p_author, p_title, p_body, coalesce(p_pinned, false), 'announcement', p_community_id, now(), now(),
        p_system_event
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
           and m.user_id <> p_author
           and not m.notifications_muted
           and (m.muted_until is null or m.muted_until < now())
    loop
        v_notification_id := public.create_notification(
            v_member.user_id, p_type, p_title, p_body,
            null, null, null, null, v_post_id, p_author, coalesce(p_pinned, false)
        );
        if v_notification_id is not null then
            v_inserted_count := v_inserted_count + 1;
            -- D13: one immediate push per bell row (no batch key). should_notify_user is true for the three
            -- announcement types whatever the preferences (canBeDisabled == false); the mute is the loop's.
            perform public.queue_push_notification(
                v_member.user_id, p_type, left(p_title, 100), left(p_body, 180),
                jsonb_build_object('community_id', p_community_id::text, 'town_hall_post_id', v_post_id::text)
                    || coalesce(p_push_data, '{}'::jsonb),
                null, v_notification_id
            );
        end if;
    end loop;

    return v_inserted_count;
end;
$function$;

revoke all on function public.post_community_announcement(uuid, uuid, text, text, boolean, text, text, jsonb)
  from public, anon, authenticated;


-- ============================================================================================
-- BLOCK 2: public.send_community_broadcast(uuid, text, text, boolean, text)
--          live md5(prosrc) 1f4f2dfbe34141fa821967370d33a309 (20261019_0002 block 2)
-- Changes: the D14 cap counts only posts with no system_event, and the post and its pushes are written by
-- post_community_announcement (Block 1). The 42501 / 22023 / P0001 refusals, the advisory lock, the cap and the
-- recipients are the live body's.
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
    -- 'announcement' through the insert policy, and must not be able to use up the community's cap. A system
    -- announcement (system_event set, the merge notice of 20261021_0022) never counts.
    if (select count(*)
          from public.town_hall_posts t
          left join public.profiles a on a.id = t.user_id
         where t.community_id = p_community_id
           and t.type = 'announcement'
           and t.created_at > now() - interval '24 hours'
           and t.system_event is null
           and (coalesce(a.is_admin, false) or public.is_community_staff(p_community_id, t.user_id))) >= 3 then
        raise exception 'This community has already sent 3 announcements today' using errcode = 'P0001';
    end if;

    return public.post_community_announcement(p_community_id, v_uid, p_title, p_body, coalesce(p_pinned, false),
                                              v_type, null, '{}'::jsonb);
end;
$function$;

revoke all on function public.send_community_broadcast(uuid, text, text, boolean, text) from public, anon;
grant execute on function public.send_community_broadcast(uuid, text, text, boolean, text)
  to authenticated, service_role;


-- ============================================================================================
-- BLOCK 3: public.merge_communities(uuid, uuid)   (new; internal, called by respond_to_community_merge)
-- One transaction: members, content, invites, the archive of the merged community, the proposal and the notice.
-- ============================================================================================
create or replace function public.merge_communities(p_proposal_id uuid, p_actor uuid)
returns jsonb
language plpgsql
security definer
set search_path = ''
as $function$
declare
  v_prop record;
  v_s uuid;            -- the survivor
  v_m uuid;            -- the merged community
  v_s_name text;
  v_m_name text;
  v_from_name text;
  v_to_name text;
  v_live integer;
  v_row record;
  v_srow record;
  v_found boolean;
  v_role text;
  v_user uuid;
  v_moved uuid[] := '{}'::uuid[];
  v_removed uuid[] := '{}'::uuid[];
  v_prev_mirror text;
begin
  begin
    perform set_config('lock_timeout', '5s', true);

    select p.* into v_prop
      from public.community_merge_proposals p
     where p.id = p_proposal_id
       for update;
    if not found or v_prop.status <> 'pending' then
      return jsonb_build_object('success', false, 'error', 'This merge proposal is no longer open',
                                'code', 'proposal_closed');
    end if;
    v_s := v_prop.survivor_community_id;
    v_m := case when v_prop.from_community_id = v_s then v_prop.to_community_id else v_prop.from_community_id end;

    -- 1. Both community rows, locked in id order; both must be unarchived.
    perform 1 from public.communities c where c.id = least(v_s, v_m) for update;
    perform 1 from public.communities c where c.id = greatest(v_s, v_m) for update;
    select count(*) into v_live from public.communities c where c.id in (v_s, v_m) and c.archived_at is null;
    if v_live <> 2 then
      return jsonb_build_object('success', false, 'error', 'This merge proposal is no longer open',
                                'code', 'proposal_closed');
    end if;
    select c.name into v_s_name from public.communities c where c.id = v_s;
    select c.name into v_m_name from public.communities c where c.id = v_m;
    v_from_name := case when v_prop.from_community_id = v_s then v_s_name else v_m_name end;
    v_to_name := case when v_prop.to_community_id = v_s then v_s_name else v_m_name end;

    -- 2. The members of M, by their status in M (active first, so applicants moved below are announced to the
    --    survivor's admins as they stand after the move). ROLE: owner and admin -> admin, member -> member; the
    --    higher of two roles wins (owner > admin > member). M's own rows stay as they are (history).
    perform set_config('naars.suppress_approval_notice', '1', true);
    for v_row in
      select m.user_id, m.role, m.status, m.joined_at, m.activated_at, m.notifications_muted, m.muted_until,
             m.heard_about, m.join_reason, m.invited_by
        from public.community_members m
       where m.community_id = v_m and m.status in ('active', 'pending')
       order by case m.status when 'active' then 0 else 1 end, m.joined_at, m.user_id
    loop
      select s.role, s.status into v_srow
        from public.community_members s
       where s.community_id = v_s and s.user_id = v_row.user_id
         for update;
      v_found := found;

      if v_row.status = 'active' then
        v_role := case when v_row.role in ('owner', 'admin') then 'admin' else 'member' end;
        if not v_found then
          insert into public.community_members (community_id, user_id, role, status, joined_at, activated_at,
                                                notifications_muted, muted_until)
          values (v_s, v_row.user_id, v_role, 'active', v_row.joined_at, v_row.activated_at,
                  v_row.notifications_muted, v_row.muted_until);
          v_moved := v_moved || v_row.user_id;
        elsif v_srow.status = 'active' then
          if v_srow.role = 'member' and v_role = 'admin' then
            update public.community_members set role = 'admin', updated_at = now()
             where community_id = v_s and user_id = v_row.user_id;
          end if;
          v_moved := v_moved || v_row.user_id;
        elsif v_srow.status in ('pending', 'left') then
          update public.community_members
             set status = 'active', role = v_role, activated_at = v_row.activated_at, ended_at = null,
                 updated_at = now()
           where community_id = v_s and user_id = v_row.user_id;
          v_moved := v_moved || v_row.user_id;
        else
          -- removed from S: stays removed; their requests and claims in M are unwound before the content moves
          perform public.unwind_member_requests(v_m, v_row.user_id);
          v_removed := v_removed || v_row.user_id;
        end if;
      elsif not v_found then
        -- an applicant to M with no row in S applies to S (notify_pending_membership tells S's admins)
        insert into public.community_members (community_id, user_id, role, status, heard_about, join_reason,
                                              invited_by)
        values (v_s, v_row.user_id, 'member', 'pending', v_row.heard_about, v_row.join_reason, v_row.invited_by);
      end if;
    end loop;
    perform set_config('naars.suppress_approval_notice', '', true);

    -- Ruling R1: protect_admin_fields refuses primary_community_id under a non-admin JWT; the membership mirror
    -- setting is the recompute_profile_membership_flags idiom.
    v_prev_mirror := coalesce(current_setting('naars.membership_mirror', true), '');
    perform set_config('naars.membership_mirror', '1', true);
    update public.profiles p
       set primary_community_id = v_s
     where p.primary_community_id = v_m
       and p.id = any (v_moved);
    perform set_config('naars.membership_mirror', v_prev_mirror, true);

    -- 3. Content. set_updated_at_* would stamp every moved row with now(); rides.updated_at / favors.updated_at
    --    are the completion time in the spotlights, so the three triggers are off for these three updates only
    --    (the 20261017_0001 [call] 1f.1 idiom). DISABLE TRIGGER holds SHARE ROW EXCLUSIVE until commit.
    alter table public.rides           disable trigger set_updated_at_rides;
    alter table public.favors          disable trigger set_updated_at_favors;
    alter table public.town_hall_posts disable trigger set_updated_at_town_hall_posts;
    update public.rides           set community_id = v_s where community_id = v_m;
    update public.favors          set community_id = v_s where community_id = v_m;
    update public.town_hall_posts set community_id = v_s where community_id = v_m;
    alter table public.rides           enable trigger set_updated_at_rides;
    alter table public.favors          enable trigger set_updated_at_favors;
    alter table public.town_hall_posts enable trigger set_updated_at_town_hall_posts;
    update public.xp_events     set community_id = v_s where community_id = v_m;
    update public.notifications set community_id = v_s where community_id = v_m;
    update public.reports       set community_id = v_s where community_id = v_m;   -- reported_community_id stays

    -- 4. M's invite codes stop working.
    update public.community_invites set revoked_at = now() where community_id = v_m and revoked_at is null;

    -- 5. M is archived (recompute_flags_on_archive runs after step 2, so moved people keep S as primary).
    update public.communities
       set archived_at = now(), archived_by = p_actor, merged_into_id = v_s, merged_at = now(), updated_at = now()
     where id = v_m;
    insert into public.community_membership_events (community_id, user_id, actor_id, event, reason)
    values (v_m, null, p_actor, 'archived', 'merged into ' || v_s::text),
           (v_s, null, p_actor, 'merged', 'merged ' || v_m_name || ' (' || v_m::text || ')');
    -- Ruling R15: a person active in M but removed from S gets M's archive notice (no push), after step 3 so it
    -- keeps M's community_id.
    foreach v_user in array v_removed loop
      perform public.notify_user_in_community(
        v_user, 'announcement', v_m_name || ' was archived',
        'Its requests and posts are no longer visible.', v_m, false, '{}'::jsonb, null
      );
    end loop;

    -- 6. The proposal.
    update public.community_merge_proposals
       set status = 'accepted', decided_at = now(), decided_by = p_actor
     where id = p_proposal_id;

    -- 7. One system announcement in S (not counted by the D14 cap): a bell row and a push for every unmuted
    --    active member but the accepting owner.
    perform public.post_community_announcement(
      v_s, p_actor, 'Communities merged',
      v_from_name || ' and ' || v_to_name || ' are now one community: ' || v_s_name || '.',
      false, 'announcement', 'community_merged', '{"community_event": "merged"}'::jsonb
    );

    -- 8.
    return jsonb_build_object('success', true, 'survivor_id', v_s, 'merged_id', v_m);
  exception when lock_not_available then
    return jsonb_build_object('success', false, 'error', 'Busy, try again', 'code', 'rate_limited');
  end;
end
$function$;

revoke all on function public.merge_communities(uuid, uuid) from public, anon, authenticated;


-- ============================================================================================
-- BLOCK 4: public.search_merge_targets(uuid, text)   (new; authenticated, service_role)
-- ============================================================================================
create or replace function public.search_merge_targets(p_community_id uuid, p_query text)
returns jsonb
language plpgsql
stable
security definer
set search_path = ''
as $function$
declare
  v_q text := left(btrim(coalesce(p_query, '')), 60);
  v_rows jsonb;
begin
  if (select auth.uid()) is null or not coalesce(public.my_community_role(p_community_id) = 'owner', false) then
    return jsonb_build_object('success', false, 'error', 'Only the owner can merge this community',
                              'code', 'not_owner');
  end if;
  if char_length(v_q) < 2 then
    return jsonb_build_object('success', true, 'communities', '[]'::jsonb);
  end if;

  -- A listed community the caller may discover matches on part of its name; a hidden one only on its exact name.
  -- Its area is shown only when it is discoverable (ruling R23).
  select coalesce(jsonb_agg(jsonb_build_object(
           'id', s.id,
           'name', s.name,
           'join_policy', s.join_policy,
           'is_public', s.is_public,
           'member_count', s.member_count,
           'area_name', case when s.discoverable then s.area_name end)
         order by s.exact desc, s.name, s.id), '[]'::jsonb)
    into v_rows
    from (
      select c.id, c.name, c.join_policy, c.is_public, c.area_name,
             lower(btrim(c.name)) = lower(v_q) as exact,
             c.is_public and public.can_discover_community(c.id) as discoverable,
             (select count(*) from public.community_members m
                join public.profiles p on p.id = m.user_id
               where m.community_id = c.id and m.status = 'active'
                 and not coalesce(p.is_banned, false))::integer as member_count
        from public.communities c
       where c.archived_at is null
         and not c.is_default
         and c.id <> p_community_id
         and c.merged_into_id is null
         and (not c.is_test or public.is_platform_admin()
              or c.id = any ((select public.my_community_ids())::uuid[]))
         and ((c.is_public and strpos(lower(c.name), lower(v_q)) > 0 and public.can_discover_community(c.id))
              or (not c.is_public and lower(btrim(c.name)) = lower(v_q)))
       order by lower(btrim(c.name)) = lower(v_q) desc, c.name, c.id
       limit 20
    ) s;

  return jsonb_build_object('success', true, 'communities', v_rows);
end
$function$;

revoke all on function public.search_merge_targets(uuid, text) from public, anon;
grant execute on function public.search_merge_targets(uuid, text) to authenticated, service_role;


-- ============================================================================================
-- BLOCK 5: public.propose_community_merge(uuid, uuid, uuid, text)   (new; authenticated, service_role)
-- ============================================================================================
create or replace function public.propose_community_merge(
  p_community_id uuid,
  p_other_id uuid,
  p_survivor_id uuid,
  p_note text default null
)
returns jsonb
language plpgsql
security definer
set search_path = ''
as $function$
declare
  v_uid uuid := (select auth.uid());
  v_note text := nullif(btrim(coalesce(p_note, '')), '');
  v_from record;
  v_other record;
  v_survivor_name text;
  v_body text;
  v_id uuid;
  v_owner uuid;
begin
  if v_uid is null or not coalesce(public.my_community_role(p_community_id) = 'owner', false) then
    return jsonb_build_object('success', false, 'error', 'Only the owner can merge this community',
                              'code', 'not_owner');
  end if;
  if p_other_id is null or p_other_id = p_community_id then
    return jsonb_build_object('success', false, 'error', 'Choose another community to merge with', 'code', 'invalid');
  end if;

  -- Two owners proposing at the same moment: one at a time per community, smaller id first.
  perform pg_advisory_xact_lock(hashtextextended('community_merge:' || least(p_community_id, p_other_id)::text, 0));
  perform pg_advisory_xact_lock(hashtextextended('community_merge:' || greatest(p_community_id, p_other_id)::text, 0));

  update public.community_merge_proposals
     set status = 'expired'
   where status = 'pending' and expires_at <= now()
     and (from_community_id in (p_community_id, p_other_id) or to_community_id in (p_community_id, p_other_id));

  if p_survivor_id is null or p_survivor_id not in (p_community_id, p_other_id)
     or char_length(coalesce(v_note, '')) > 300 then
    return jsonb_build_object('success', false, 'error', 'Choose another community to merge with', 'code', 'invalid');
  end if;

  select c.name, c.is_default into v_from from public.communities c where c.id = p_community_id;
  select c.name, c.is_default, c.archived_at, c.merged_into_id into v_other
    from public.communities c where c.id = p_other_id;
  if not found or v_other.archived_at is not null or v_other.merged_into_id is not null then
    return jsonb_build_object('success', false, 'error', 'Choose another community to merge with', 'code', 'invalid');
  end if;
  if v_from.is_default or v_other.is_default then
    return jsonb_build_object('success', false, 'error', 'The default community cannot be merged',
                              'code', 'default_community');
  end if;
  if exists (select 1 from public.community_merge_proposals p
              where p.status = 'pending'
                and (p.from_community_id in (p_community_id, p_other_id)
                     or p.to_community_id in (p_community_id, p_other_id))) then
    return jsonb_build_object('success', false,
                              'error', 'A merge proposal is already open for one of these communities',
                              'code', 'merge_pending');
  end if;
  if exists (select 1 from public.community_merge_proposals p
              where p.status = 'declined' and p.decided_at > now() - interval '7 days'
                and ((p.from_community_id = p_community_id and p.to_community_id = p_other_id)
                     or (p.from_community_id = p_other_id and p.to_community_id = p_community_id))) then
    return jsonb_build_object('success', false, 'error', 'This merge was declined in the last 7 days',
                              'code', 'recently_declined');
  end if;

  insert into public.community_merge_proposals (from_community_id, to_community_id, survivor_community_id,
                                                proposed_by, note)
  values (p_community_id, p_other_id, p_survivor_id, v_uid, v_note)
  returning id into v_id;

  v_survivor_name := case when p_survivor_id = p_community_id then v_from.name else v_other.name end;
  v_body := v_from.name || ' proposes making ' || v_from.name || ' and ' || v_other.name || ' one community: '
            || v_survivor_name || '. Open Manage in ' || v_other.name || ' to accept or decline.';
  for v_owner in
    select m.user_id
      from public.community_members m
      join public.profiles p on p.id = m.user_id
     where m.community_id = p_other_id and m.status = 'active' and m.role = 'owner'
       and not coalesce(p.is_banned, false) and m.user_id <> v_uid
  loop
    perform public.notify_user_in_community(
      v_owner, 'announcement', 'Merge proposal from ' || v_from.name, v_body, p_other_id, true, '{}'::jsonb, v_uid
    );
  end loop;

  return jsonb_build_object('success', true, 'proposal_id', v_id);
end
$function$;

revoke all on function public.propose_community_merge(uuid, uuid, uuid, text) from public, anon;
grant execute on function public.propose_community_merge(uuid, uuid, uuid, text) to authenticated, service_role;


-- ============================================================================================
-- BLOCK 6: public.get_community_merge_proposal(uuid)   (new; authenticated, service_role)
-- ============================================================================================
create or replace function public.get_community_merge_proposal(p_community_id uuid)
returns jsonb
language plpgsql
stable
security definer
set search_path = ''
as $function$
declare
  v_proposal jsonb;
begin
  if (select auth.uid()) is null
     or not (coalesce(public.my_community_role(p_community_id) = 'owner', false) or public.is_platform_admin()) then
    return jsonb_build_object('success', false, 'error', 'Only the owner can merge this community',
                              'code', 'not_owner');
  end if;

  select jsonb_build_object(
           'id', p.id,
           'direction', case when p.from_community_id = p_community_id then 'outgoing' else 'incoming' end,
           'from', jsonb_build_object('id', f.id, 'name', f.name, 'join_policy', f.join_policy,
                                      'member_count', fm.n),
           'to', jsonb_build_object('id', t.id, 'name', t.name, 'join_policy', t.join_policy,
                                    'member_count', tm.n),
           'survivor_id', p.survivor_community_id,
           'note', p.note,
           'proposed_by_name', pb.name,
           'created_at', p.created_at,
           'expires_at', p.expires_at)
    into v_proposal
    from public.community_merge_proposals p
    join public.communities f on f.id = p.from_community_id
    join public.communities t on t.id = p.to_community_id
    left join public.profiles pb on pb.id = p.proposed_by
    cross join lateral (
      select count(*)::integer as n from public.community_members m
        join public.profiles x on x.id = m.user_id
       where m.community_id = f.id and m.status = 'active' and not coalesce(x.is_banned, false)) fm
    cross join lateral (
      select count(*)::integer as n from public.community_members m
        join public.profiles x on x.id = m.user_id
       where m.community_id = t.id and m.status = 'active' and not coalesce(x.is_banned, false)) tm
   where p.status = 'pending' and p.expires_at > now()
     and (p.from_community_id = p_community_id or p.to_community_id = p_community_id)
   order by p.created_at desc, p.id desc
   limit 1;

  return jsonb_build_object('success', true, 'proposal', v_proposal);
end
$function$;

revoke all on function public.get_community_merge_proposal(uuid) from public, anon;
grant execute on function public.get_community_merge_proposal(uuid) to authenticated, service_role;


-- ============================================================================================
-- BLOCK 7: public.respond_to_community_merge(uuid, boolean)   (new; authenticated, service_role)
-- ============================================================================================
create or replace function public.respond_to_community_merge(p_proposal_id uuid, p_accept boolean)
returns jsonb
language plpgsql
security definer
set search_path = ''
as $function$
declare
  v_uid uuid := (select auth.uid());
  v_prop record;
  v_from_name text;
  v_to_name text;
  v_owner uuid;
begin
  if v_uid is null then
    return jsonb_build_object('success', false, 'error', 'Only the owner can merge this community',
                              'code', 'not_owner');
  end if;
  if p_accept is null then
    return jsonb_build_object('success', false, 'error', 'Choose accept or decline', 'code', 'invalid');
  end if;

  select p.* into v_prop
    from public.community_merge_proposals p
   where p.id = p_proposal_id
     for update;
  if not found or v_prop.status <> 'pending' then
    return jsonb_build_object('success', false, 'error', 'This merge proposal is no longer open',
                              'code', 'proposal_closed');
  end if;
  if v_prop.expires_at <= now() then
    update public.community_merge_proposals set status = 'expired' where id = p_proposal_id;
    return jsonb_build_object('success', false, 'error', 'This merge proposal is no longer open',
                              'code', 'proposal_closed');
  end if;
  -- before the role: an archived community answers no role
  if exists (select 1 from public.communities c
              where c.id in (v_prop.from_community_id, v_prop.to_community_id) and c.archived_at is not null) then
    update public.community_merge_proposals set status = 'withdrawn', decided_at = now() where id = p_proposal_id;
    return jsonb_build_object('success', false, 'error', 'This merge proposal is no longer open',
                              'code', 'proposal_closed');
  end if;
  if not coalesce(public.my_community_role(v_prop.to_community_id) = 'owner', false) then
    return jsonb_build_object('success', false, 'error', 'Only the owner can merge this community',
                              'code', 'not_owner');
  end if;

  if not p_accept then
    update public.community_merge_proposals
       set status = 'declined', decided_at = now(), decided_by = v_uid
     where id = p_proposal_id;
    select c.name into v_from_name from public.communities c where c.id = v_prop.from_community_id;
    select c.name into v_to_name from public.communities c where c.id = v_prop.to_community_id;
    for v_owner in
      select m.user_id
        from public.community_members m
        join public.profiles p on p.id = m.user_id
       where m.community_id = v_prop.from_community_id and m.status = 'active' and m.role = 'owner'
         and not coalesce(p.is_banned, false) and m.user_id <> v_uid
    loop
      perform public.notify_user_in_community(
        v_owner, 'announcement', 'Merge declined', v_to_name || ' declined merging with ' || v_from_name || '.',
        v_prop.from_community_id, false, '{}'::jsonb, v_uid
      );
    end loop;
    return jsonb_build_object('success', true);
  end if;

  return public.merge_communities(p_proposal_id, v_uid);
end
$function$;

revoke all on function public.respond_to_community_merge(uuid, boolean) from public, anon;
grant execute on function public.respond_to_community_merge(uuid, boolean) to authenticated, service_role;


-- ============================================================================================
-- BLOCK 8: public.withdraw_community_merge(uuid)   (new; authenticated, service_role)
-- ============================================================================================
create or replace function public.withdraw_community_merge(p_proposal_id uuid)
returns jsonb
language plpgsql
security definer
set search_path = ''
as $function$
declare
  v_uid uuid := (select auth.uid());
  v_prop record;
  v_mine uuid;
  v_other uuid;
  v_mine_name text;
  v_owner uuid;
begin
  if v_uid is null then
    return jsonb_build_object('success', false, 'error', 'Only the owner can merge this community',
                              'code', 'not_owner');
  end if;

  select p.* into v_prop
    from public.community_merge_proposals p
   where p.id = p_proposal_id
     for update;
  if not found then
    return jsonb_build_object('success', false, 'error', 'This merge proposal is no longer open',
                              'code', 'proposal_closed');
  end if;
  if coalesce(public.my_community_role(v_prop.from_community_id) = 'owner', false) then
    v_mine := v_prop.from_community_id;
    v_other := v_prop.to_community_id;
  elsif coalesce(public.my_community_role(v_prop.to_community_id) = 'owner', false) then
    v_mine := v_prop.to_community_id;
    v_other := v_prop.from_community_id;
  else
    return jsonb_build_object('success', false, 'error', 'Only the owner can merge this community',
                              'code', 'not_owner');
  end if;
  if v_prop.status <> 'pending' then
    return jsonb_build_object('success', false, 'error', 'This merge proposal is no longer open',
                              'code', 'proposal_closed');
  end if;

  update public.community_merge_proposals
     set status = 'withdrawn', decided_at = now(), decided_by = v_uid
   where id = p_proposal_id;

  select c.name into v_mine_name from public.communities c where c.id = v_mine;
  for v_owner in
    select m.user_id
      from public.community_members m
      join public.profiles p on p.id = m.user_id
     where m.community_id = v_other and m.status = 'active' and m.role = 'owner'
       and not coalesce(p.is_banned, false) and m.user_id <> v_uid
  loop
    perform public.notify_user_in_community(
      v_owner, 'announcement', 'Merge proposal withdrawn', v_mine_name || ' withdrew the merge proposal.',
      v_other, false, '{}'::jsonb, v_uid
    );
  end loop;

  return jsonb_build_object('success', true);
end
$function$;

revoke all on function public.withdraw_community_merge(uuid) from public, anon;
grant execute on function public.withdraw_community_merge(uuid) to authenticated, service_role;


-- ============================================================================================
-- BLOCK 9: public.get_my_community_merges()   (new; authenticated, service_role) and
-- public.get_platform_communities()   live md5 a44cdb53dbbd040504e56bf7aa853494 (20261021_0021 Block 8, ruling R5)
-- with merge_proposals filled
-- ============================================================================================
create or replace function public.get_my_community_merges()
returns jsonb
language plpgsql
stable
security definer
set search_path = ''
as $function$
declare
  v_uid uuid := (select auth.uid());
  v_rows jsonb;
begin
  if v_uid is null then
    return jsonb_build_object('success', true, 'merges', '[]'::jsonb);
  end if;

  -- The merged communities of the last 90 days in which the caller was an active member when they merged (the
  -- merged community's rows are kept as they were).
  select coalesce(jsonb_agg(jsonb_build_object(
           'merged_id', m.id,
           'merged_name', m.name,
           'survivor_id', s.id,
           'survivor_name', s.name,
           'merged_at', m.merged_at)
         order by m.merged_at desc, m.id), '[]'::jsonb)
    into v_rows
    from public.communities m
    join public.communities s on s.id = m.merged_into_id
   where m.merged_into_id is not null
     and m.merged_at > now() - interval '90 days'
     and exists (select 1 from public.community_members cm
                  where cm.community_id = m.id and cm.user_id = v_uid and cm.status = 'active');

  return jsonb_build_object('success', true, 'merges', v_rows);
end
$function$;

revoke all on function public.get_my_community_merges() from public, anon;
grant execute on function public.get_my_community_merges() to authenticated, service_role;

create or replace function public.get_platform_communities()
returns jsonb
language plpgsql
stable
security definer
set search_path = ''
as $function$
declare
  v_communities jsonb;
  v_requests jsonb;
  v_merges jsonb;
begin
  if (select auth.uid()) is null or not public.is_platform_admin() then
    return jsonb_build_object('success', false, 'error', 'Not authorized - admin access required');
  end if;

  select coalesce(jsonb_agg(to_jsonb(s) order by s.archived_at nulls first, s.created_at desc), '[]'::jsonb)
    into v_communities
    from (
      select c.id, c.name, c.description, c.created_by, cp.name as creator_name, c.created_at,
             c.is_public, c.is_default, c.join_policy, c.archived_at, c.archived_by,
             (select count(*) from public.community_members m
               where m.community_id = c.id and m.status = 'active') as member_count,
             (select count(*) from public.community_members m
               where m.community_id = c.id and m.status = 'pending') as pending_count,
             (select count(*) from public.community_members m
               where m.community_id = c.id and m.status = 'active' and m.role = 'owner') as owner_count,
             (select count(*) from public.reports r
               where r.reported_community_id = c.id and r.status = 'pending') as open_report_count,
             c.area_name, c.area_center_lat, c.area_center_lng, c.area_radius_miles, c.is_test,
             c.merged_into_id, mi.name as merged_into_name,
             le.event as listing_event,
             le.reason as listing_reason,
             case when le.event is null then null::text[]
                  else coalesce((select array_agg(o.name order by u.ord)
                                   from unnest(le.overlapping_ids) with ordinality as u(id, ord)
                                   join public.communities o on o.id = u.id), '{}'::text[])
             end as listing_overlaps,
             le.created_at as listing_event_at
        from public.communities c
        left join public.profiles cp on cp.id = c.created_by
        left join public.communities mi on mi.id = c.merged_into_id
        left join lateral (
          select e.event, e.reason, e.overlapping_ids, e.created_at
            from public.community_listing_events e
           where e.community_id = c.id
           order by e.created_at desc, e.id desc
           limit 1
        ) le on true
    ) s;

  select coalesce(jsonb_agg(to_jsonb(s) order by s.created_at), '[]'::jsonb)
    into v_requests
    from (
      select r.id as request_id, r.user_id, p.name as user_name, r.requested_max, r.reason, r.created_at,
             coalesce(p.max_owned_communities, 3) as current_max,
             (select count(*) from public.community_members m
                join public.communities c on c.id = m.community_id and c.archived_at is null
               where m.user_id = r.user_id and m.status = 'active' and m.role = 'owner') as owned_count
        from public.community_limit_requests r
        join public.profiles p on p.id = r.user_id
       where r.status = 'pending'
    ) s;

  -- Every merge proposal still pending, or decided or expired within 30 days, newest first; a pending one past
  -- its expiry reads 'expired' (20261021_0022).
  select coalesce(jsonb_agg(to_jsonb(s) order by s.created_at desc, s.id desc), '[]'::jsonb)
    into v_merges
    from (
      select p.id, p.from_community_id as from_id, fc.name as from_name, p.to_community_id as to_id,
             tc.name as to_name, p.survivor_community_id as survivor_id, sc.name as survivor_name,
             case when p.status = 'pending' and p.expires_at <= now() then 'expired' else p.status end as status,
             p.note, p.created_at, p.expires_at, p.decided_at
        from public.community_merge_proposals p
        join public.communities fc on fc.id = p.from_community_id
        join public.communities tc on tc.id = p.to_community_id
        join public.communities sc on sc.id = p.survivor_community_id
       where (p.status = 'pending' and p.expires_at > now())
          or coalesce(p.decided_at, p.expires_at) > now() - interval '30 days'
    ) s;

  return jsonb_build_object('success', true, 'communities', v_communities, 'limit_requests', v_requests,
                            'merge_proposals', v_merges);
end
$function$;

revoke all on function public.get_platform_communities() from public, anon;
grant execute on function public.get_platform_communities() to authenticated, service_role;


-- ============================================================================================
-- BLOCK 10: public.unarchive_community(uuid)   live md5 b1fccb2583e0b20a61300da30ec3b419 (20261017_0005 Block 14)
-- Ruling R16: a merged community cannot be restored (the update skips it and the refusal says why).
-- ============================================================================================
create or replace function public.unarchive_community(p_community_id uuid)
returns jsonb
language plpgsql
security definer
set search_path = ''
as $function$
declare
  v_uid uuid := (select auth.uid());
begin
  if v_uid is null or not public.is_platform_admin() then
    return jsonb_build_object('success', false, 'error', 'Not authorized - admin access required');
  end if;

  update public.communities
     set archived_at = null, archived_by = null, updated_at = now()
   where id = p_community_id and archived_at is not null and merged_into_id is null;
  if not found then
    -- 20261021_0022 (ruling R16): a merge cannot be undone; its members and content are in the survivor now.
    if exists (select 1 from public.communities c where c.id = p_community_id and c.merged_into_id is not null) then
      return jsonb_build_object('success', false, 'error', 'This community was merged and cannot be restored');
    end if;
    return jsonb_build_object('success', false, 'error', 'This community is not archived');
  end if;

  insert into public.community_membership_events (community_id, user_id, actor_id, event)
  values (p_community_id, null, v_uid, 'unarchived');

  return jsonb_build_object('success', true);
end
$function$;

revoke all on function public.unarchive_community(uuid) from public, anon;
grant execute on function public.unarchive_community(uuid) to authenticated, service_role;
