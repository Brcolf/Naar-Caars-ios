-- 20261022_0002_merge_followups.sql
--
-- APPLIED 2026-10-22, one block, through the Supabase MCP apply_migration (migration-history version 20261022212210
-- 20261022_0002_block_1), the block's text sent byte for byte from this file (banner to last statement), after the
-- rolled-back dry run below passed. Deployed md5(prosrc) e738f413c655ee89dcc6c05f080e8f1c, read live after the apply
-- and equal to the md5 of the text between this file's $function$ delimiters (python3 -I). ACL after the block
-- unchanged: {postgres=X/postgres,service_role=X/postgres}; has_function_privilege anon false, authenticated false,
-- service_role true (internal; ruling R-G1, the revoke restated from 20261021_0022 Block 3). Still plpgsql, security
-- definer, search_path "", volatile, same signature and return type. No deviation: the block ran as written below.
--
-- Community Release 2, task S7 (Docs/superpowers/specs/2026-10-21-community-discovery-and-trust-design.md 4.12). Two
-- owner decisions of 2026-10-22, made after the server final review (finding M3) and the co-owner question:
--   (1) the merged community's owner joins the surviving community as an owner (the two are co-owners), not as an
--       admin; its admins still become admins;
--   (2) Town Hall posts and comments of a person who had been removed from the survivor arrive hidden (restorable
--       by a platform admin); their requests are still withdrawn, as before.
--
-- What it changes. public.merge_communities(p_proposal_id uuid, p_actor uuid) -> jsonb (internal; called only by
-- respond_to_community_merge), re-created from its live body (20261021_0022 Block 3) with these edits only:
--   (a) ROLE: owner -> owner, admin -> admin, member -> member (was owner and admin -> admin). It applies to a person
--       active in M with no row in S (inserted) and to one pending or left in S (reactivated).
--   (b) Active in both: the higher role still wins (owner > admin > member). The member -> admin promotion is kept as
--       it was (no event row, as before); new: an S row that is member or admin becomes owner when the M row is
--       owner, with one community_membership_events row in set_member_role's shape (event 'role_changed', user,
--       actor p_actor, old_role the S role, new_role 'owner'). An owner of both stays owner.
--   (c) Content: when anyone was removed from S, the ids of M's posts are read just before they move (inside the
--       trigger window, under the SHARE ROW EXCLUSIVE lock the disabled trigger holds); right after the move, and
--       before set_updated_at_town_hall_posts is re-enabled, the moved posts of those people and their comments on
--       the moved posts get hidden_at now(), hidden_by p_actor (the accepting owner) and hidden_reason 'Moved in a
--       merge into a community you were removed from', the columns moderate_community_content writes for a hide
--       (the reason is the author's: the app shows it to them as "Reason: ..." on their own hidden post or
--       comment); rows already hidden are left alone. Their earlier posts and comments in S are not touched.
--   (d) Nothing else: notices, the archive notice, the announcement, invites, the proposal, the archive of M, the
--       primary-community mirror and unwind_member_requests are as before. No signature, return or ACL change;
--       get_community_merge_proposal and the client payloads are unchanged.
--   Hidden content stays counted where hidden content is counted today (spotlights, stats; a known Release 1 note).
--   Restoring: no report row exists for these rows, and both moderation RPCs (admin_moderate_content,
--   moderate_community_content) act through a report, so a platform admin restores one in SQL (hidden_at, hidden_by
--   and hidden_reason set to null, as the RPCs' restore writes).
--   A hidden comment's updated_at is stamped by update_town_hall_comments_updated_at, as it is when
--   moderate_community_content hides a comment; only the posts trigger is disabled by the merge.
--
-- Live body before the change (the rollback source). md5(prosrc) 9f13c599d609799e7c09601abe12b927, read live on
-- 2026-10-22 and equal to the text between 20261021_0022 Block 3's $function$ delimiters (python3 -I). ACL (proacl)
-- {postgres=X/postgres,service_role=X/postgres}; has_function_privilege anon false, authenticated false,
-- service_role true; plpgsql, security definer, search_path "", volatile.
--
-- What old clients see. No installed build calls merge_communities. After a merge the merged owner appears as an
-- owner in the survivor's members list (installed builds show roles as the server sends them), a removed person's
-- moved posts and comments are absent from other members' feeds, and their author, who can still read their own
-- rows, sees the existing "Reason: %@" line with the text above.
--
-- Apply. One block. Before it, compare the live md5(prosrc) with 9f13c599d609799e7c09601abe12b927; stop on a
-- mismatch. Nothing here is declined by the MCP (no row removal, policy drop or write to auth.* / storage.*).
--
-- Verification (supabase/probes/communities_probe.sql; every run through execute_sql, rolled back, PARAMETERS and
-- HELPERS in the same call, full-line comments stripped). Outcomes, 2026-10-22:
--   Before: live md5(prosrc) 9f13c599d609799e7c09601abe12b927 (equal to 20261021_0022 Block 3's text); the three
--   passages edited here found once each; the moderation columns read live (hidden_at, hidden_by, hidden_reason on
--   both tables, no CHECK on hidden_reason) and the hide statement of moderate_community_content read live; no
--   20261022_0002 file or migration-history entry.
--   Dry run: supabase/dryruns/20261022_0002_merge_followups.dryrun.sql (PARAMETERS, HELPERS without commit, begin,
--   this block, the probes community_merge, broadcast_cap, broadcast_push, archive, listing_rules and short as
--   savepoints, rollback; structural check: no commit statement, one begin, one rollback, 6 savepoints, 6 releases,
--   6 PROBE selects), sent in one execute_sql call: DRYRUN 20261022_0002 OK on the first attempt (any failed check
--   raises and aborts the call, so every probe passed); the live md5 was still 9f13c599... afterwards.
--   After the block: one rolled-back call with short, community_merge and broadcast_push as savepoints (HELPERS
--   without probe_require_phase5 and probe_storage_object, which these blocks do not call): PROBE short OK, then
--   PROBE community_merge OK, then PROBE broadcast_push OK. community_merge now checks: C3's owner u14 is an owner of
--   C2 beside u12 with no role_changed event (u14 had no C2 row) and u3 is admin; u7 (removed from C2) has their
--   moved post and both of their comments on moved posts hidden by u14 with the merge reason, the post keeping its
--   updated_at; u14's post and u3's comment (the control) and u7's earlier post and comment in C2 are not hidden;
--   a C2 member reads the control and none of u7's moved rows, and u7 reads their own hidden post; u14, now an
--   owner of C2, is told of the C6 proposal; C11 (owners u11, a member of C2, and u3, an admin of C2) merged into
--   C2 makes both owners with one role_changed event each (actor u12, old roles member and admin). Every earlier
--   check of the block, unwind_member_requests' included, still passes.
--   Afterwards: no probe account, community, proposal or merged community; no post carries the merge reason; the
--   three set_updated_at triggers enabled.
--
-- Rollback (MCP). Re-create the function from 20261021_0022 Block 3 (md5 9f13c599d609799e7c09601abe12b927); the
-- ACL stays as it is. Merges made in between keep their co-owners and hidden rows; restoring a hidden row is a
-- platform admin's SQL step (above).


-- ============================================================================================
-- BLOCK 1: public.merge_communities(uuid, uuid)   live md5(prosrc) 9f13c599d609799e7c09601abe12b927
-- (20261021_0022 Block 3). Changes: the owner role maps to owner; the owner promotion for a person active in both;
-- the moved posts and comments of people removed from the survivor arrive hidden. Everything else is the live body.
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
  v_m_posts uuid[] := '{}'::uuid[];
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
    --    survivor's admins as they stand after the move). ROLE: owner -> owner (M's owners become co-owners of S),
    --    admin -> admin, member -> member; the higher of two roles wins (owner > admin > member). M's own rows stay
    --    as they are (history).
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
        v_role := case when v_row.role in ('owner', 'admin') then v_row.role else 'member' end;
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
          elsif v_srow.role in ('member', 'admin') and v_role = 'owner' then
            -- an owner of M becomes a co-owner of S, recorded as set_member_role records a role change
            update public.community_members set role = 'owner', updated_at = now()
             where community_id = v_s and user_id = v_row.user_id;
            insert into public.community_membership_events (community_id, user_id, actor_id, event, old_role, new_role)
            values (v_s, v_row.user_id, p_actor, 'role_changed', v_srow.role, 'owner');
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
    --    are the completion time in the spotlights, so the three triggers are off for these three updates and the
    --    hide below only (the 20261017_0001 [call] 1f.1 idiom). DISABLE TRIGGER holds SHARE ROW EXCLUSIVE until
    --    commit.
    alter table public.rides           disable trigger set_updated_at_rides;
    alter table public.favors          disable trigger set_updated_at_favors;
    alter table public.town_hall_posts disable trigger set_updated_at_town_hall_posts;
    update public.rides           set community_id = v_s where community_id = v_m;
    update public.favors          set community_id = v_s where community_id = v_m;
    if cardinality(v_removed) > 0 then
      select coalesce(array_agg(t.id), '{}'::uuid[]) into v_m_posts
        from public.town_hall_posts t
       where t.community_id = v_m;
    end if;
    update public.town_hall_posts set community_id = v_s where community_id = v_m;
    -- Posts and comments that arrive from M by a person removed from S arrive hidden, written as
    -- moderate_community_content writes a hide (hidden_by the accepting owner). Only what moved: the person's
    -- earlier posts and comments in S stay as they are. Before the posts trigger is re-enabled, so a hidden post
    -- keeps its updated_at as the move does.
    if cardinality(v_removed) > 0 then
      update public.town_hall_posts
         set hidden_at = now(), hidden_by = p_actor,
             hidden_reason = 'Moved in a merge into a community you were removed from'
       where id = any (v_m_posts) and user_id = any (v_removed) and hidden_at is null;
      update public.town_hall_comments
         set hidden_at = now(), hidden_by = p_actor,
             hidden_reason = 'Moved in a merge into a community you were removed from'
       where post_id = any (v_m_posts) and user_id = any (v_removed) and hidden_at is null;
    end if;
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
