-- 20261019_0060_retire_legacy_bridges.sql
--
-- NOT APPLIED. GATED: apply only after the owner confirms from App Store Connect that no pre-community build
-- remains in use (Docs/superpowers/specs/2026-10-17-multi-community-decisions.md, A5 point 2). Phase 5b of the
-- multi-community design (§4 "Phase 5": retire the legacy bridges, the rollout fallback in
-- fill_request_community and the is_default dependence; admin_reject_pending_user revoked from authenticated;
-- stop maintaining profiles.heard_about / join_reason for new rows).
--
-- What it does.
--   1. fill_request_community: the "rollout safety only, removed in Phase 5" branch goes (spec lines 433-437):
--      an account with no membership row is no longer placed in the default community because profiles.approved
--      is true. Primary, then oldest active membership, else 'Choose a community' (42501), as before.
--   2-3. redeem_community_invite / request_to_join_community: the copy of a default-community applicant's
--      answers into profiles.heard_about / join_reason goes (it existed only for the installed build's Pending
--      Users screen, D19). Answers stay on the community_members row. Derived from the live body (D-S1).
--   4. protect_admin_fields: approved and application_complete become mirror-only. With the bridges gone a
--      direct write would leave the mirror wrong, so any UPDATE that carries an end-user JWT and changes either
--      column raises 42501, platform admins included; recompute_profile_membership_flags (the flag
--      naars.membership_mirror) and writes with no JWT (migrations, SQL editor, service role) pass. The other
--      guarded columns keep today's rule (admins may change them).
--   5. The two bridge triggers on profiles and their functions are dropped.
--   6. admin_reject_pending_user: EXECUTE revoked from authenticated (service_role keeps it). No community
--      build calls it after iOS Task 2.
--   7. (optional, D-S3) The installed build's remaining default-community wrappers: EXECUTE revoked on
--      get_leaderboard (both overloads; no build calls them) and send_broadcast_notifications (only the
--      installed admin build calls it; community builds call send_community_broadcast).
--
-- What old clients see (the installed pre-community build; the gate says none is left).
--   1: an approved account with no membership row cannot post (0 such accounts on 2026-10-19). 2-3: its Pending
--   Users screen shows "Not provided" for answers of applicants who joined through a community build. 4: its
--   application form's submit and its admin Approve both fail with their error alerts
--   (application_error_submit_failed, admin_approve_failed). 5: nothing beyond 4. 6: its Reject fails
--   (admin_reject_failed). 7: its Send Broadcast fails. Community builds (Phase 2 and later) see nothing: they
--   never write approved / application_complete, never call these functions, and read answers from
--   community_members.
--
-- Apply. Supabase MCP apply_migration, one block per call, in order 1 → 6 (7 if kept); block 4 before block 5
-- (see the plan's runbook). Before blocks 1-4 compare md5(prosrc) with the value above each; blocks 2-3 check
-- it themselves and raise on a mismatch. If the MCP declines a block, SQL editor (owner), verbatim.
-- Verification. Dry run (now): supabase/dryruns/20261019_0060_retire_legacy_bridges.dryrun.sql through the MCP
-- (every block inside one begin; ... rollback;, with legacy_retired, legacy_bridges, broadcast_cap,
-- privileged_columns, account_deletion and short as savepoints), then the not-applied check. Outcomes: not yet run. At the gate: short after every block; legacy_retired,
-- privileged_columns, account_deletion at the end.
--
-- Rollback, in reverse order. 7: grant execute on the three functions back to the roles in the plan's P2.
-- 6: grant execute on function public.admin_reject_pending_user(uuid) to authenticated. 5: re-run
-- 20261017_0001_communities_core.sql:657-694, 709-752, 757-769 (functions, triggers, revoke). 4: re-run
-- 20261017_0001:290-312. 3: 20261017_0005_communities_rpcs.sql:1226-1327. 2: 20261017_0005:1076-1213.
-- 1: 20261017_0001:834-871. Answers not copied while the file was live are still on community_members.


-- ============================================================================================
-- BLOCK 1: public.fill_request_community()   live md5(prosrc) 6241f67fc4e8618ac782b99a7b6d9295
-- (20261017_0001:834-871). Removed: the third branch (default_community_id() for an approved account with no
-- membership row). Deployed md5 must be 9d4cfb03912a7c4a874cffae239ee605.
-- ============================================================================================
create or replace function public.fill_request_community()
returns trigger
language plpgsql
security definer
set search_path = ''
as $function$
declare
  v_c uuid;
begin
  if new.community_id is not null then
    return new;
  end if;
  select m.community_id into v_c
    from public.profiles p
    join public.community_members m on m.user_id = p.id and m.community_id = p.primary_community_id and m.status = 'active'
    join public.communities c on c.id = m.community_id and c.archived_at is null
   where p.id = new.user_id;
  if v_c is null then
    select m.community_id into v_c
      from public.community_members m
      join public.communities c on c.id = m.community_id and c.archived_at is null
     where m.user_id = new.user_id and m.status = 'active'
     order by m.activated_at nulls last, m.community_id
     limit 1;
  end if;
  if v_c is null then
    raise exception 'Choose a community' using errcode = '42501';
  end if;
  new.community_id := v_c;
  return new;
end
$function$;


-- ============================================================================================
-- BLOCK 2: public.redeem_community_invite(text, text, text)   live md5 f18e6af6f7ca7a53acd193db115b1f27
-- (20261017_0005:1076-1213). Derived from the live definition (D-S1). Removed, exactly once, these 8 lines
-- (the default-community copy into profiles):
--     select c.is_default into v_is_default from public.communities c where c.id = v_inv.community_id;
--     if v_status = 'pending' and v_is_default then
--       update public.profiles
--          set heard_about = coalesce(v_heard, heard_about),
--              join_reason = coalesce(v_reason, join_reason)
--        where id = v_uid;
--     end if;
--     <blank line>
-- The declared v_is_default stays (unused). Grants are kept by CREATE OR REPLACE.
-- Deployed md5 must be 2ec0702dc3a4d400ca2599d0ebb15693.
-- ============================================================================================
do $derive$
declare
  v_fn constant regprocedure := 'public.redeem_community_invite(text, text, text)'::regprocedure;
  v_cut constant text := E'  select c.is_default into v_is_default from public.communities c where c.id = v_inv.community_id;\n  if v_status = ''pending'' and v_is_default then\n    update public.profiles\n       set heard_about = coalesce(v_heard, heard_about),\n           join_reason = coalesce(v_reason, join_reason)\n     where id = v_uid;\n  end if;\n\n';
  v_def text;
begin
  if (select md5(p.prosrc) from pg_catalog.pg_proc p where p.oid = v_fn) <> 'f18e6af6f7ca7a53acd193db115b1f27' then
    raise exception 'redeem_community_invite is not the expected live body';
  end if;
  v_def := pg_catalog.pg_get_functiondef(v_fn);
  if (length(v_def) - length(replace(v_def, v_cut, ''))) / length(v_cut) <> 1 then
    raise exception 'redeem_community_invite: the answer copy was not found exactly once';
  end if;
  execute replace(v_def, v_cut, '');
  if (select md5(p.prosrc) from pg_catalog.pg_proc p where p.oid = v_fn) <> '2ec0702dc3a4d400ca2599d0ebb15693' then
    raise exception 'redeem_community_invite: unexpected body after the edit';
  end if;
end
$derive$;


-- ============================================================================================
-- BLOCK 3: public.request_to_join_community(uuid, text, text)   live md5 da89c2337d8102d4c284440c534c2b2a
-- (20261017_0005:1226-1327). Derived from the live definition (D-S1). Removed, exactly once, these 7 lines:
--     if v_c.is_default then
--       update public.profiles
--          set heard_about = coalesce(v_heard, heard_about),
--              join_reason = coalesce(v_reason, join_reason)
--        where id = v_uid;
--     end if;
--     <blank line>
-- Deployed md5 must be af9a2f5c560d2d74f35ab979e2f3856c.
-- ============================================================================================
do $derive$
declare
  v_fn constant regprocedure := 'public.request_to_join_community(uuid, text, text)'::regprocedure;
  v_cut constant text := E'  if v_c.is_default then\n    update public.profiles\n       set heard_about = coalesce(v_heard, heard_about),\n           join_reason = coalesce(v_reason, join_reason)\n     where id = v_uid;\n  end if;\n\n';
  v_def text;
begin
  if (select md5(p.prosrc) from pg_catalog.pg_proc p where p.oid = v_fn) <> 'da89c2337d8102d4c284440c534c2b2a' then
    raise exception 'request_to_join_community is not the expected live body';
  end if;
  v_def := pg_catalog.pg_get_functiondef(v_fn);
  if (length(v_def) - length(replace(v_def, v_cut, ''))) / length(v_cut) <> 1 then
    raise exception 'request_to_join_community: the answer copy was not found exactly once';
  end if;
  execute replace(v_def, v_cut, '');
  if (select md5(p.prosrc) from pg_catalog.pg_proc p where p.oid = v_fn) <> 'af9a2f5c560d2d74f35ab979e2f3856c' then
    raise exception 'request_to_join_community: unexpected body after the edit';
  end if;
end
$derive$;


-- ============================================================================================
-- BLOCK 4: public.protect_admin_fields()   live md5 48424e05ea801252b83ed8c893db5f4f (20261017_0001:290-312)
-- Changes: approved and application_complete are mirror-only for every end-user JWT (D-S2); approved leaves the
-- admin-guarded list, whose message changes accordingly. Deployed md5 must be d963a013278b5ace77565b8397683bf2.
-- Before this block: confirm no function other than recompute_profile_membership_flags and
-- sync_legacy_approval_to_membership writes either column (both set naars.membership_mirror; read 2026-10-19).
-- ============================================================================================
create or replace function public.protect_admin_fields()
returns trigger
language plpgsql
set search_path = ''
as $function$
begin
    if current_setting('naars.membership_mirror', true) = '1' then
        return new;
    end if;

    -- Phase 5b: approved and application_complete follow memberships only. With the legacy bridges
    -- retired a direct write would leave the mirror wrong, so a write that carries an end-user JWT
    -- (platform admins included) is refused; writes with no JWT (migrations, SQL editor, service role) pass.
    if (old.approved is distinct from new.approved
        or old.application_complete is distinct from new.application_complete)
       and (select auth.uid()) is not null then
        raise exception 'approved and application_complete follow community memberships'
            using errcode = '42501';
    end if;

    if (old.is_admin is distinct from new.is_admin
        or old.is_banned is distinct from new.is_banned
        or old.primary_community_id is distinct from new.primary_community_id
        or old.max_owned_communities is distinct from new.max_owned_communities) then
        if (select auth.uid()) is not null
           and not coalesce((select p.is_admin from public.profiles p where p.id = (select auth.uid())), false) then
            raise exception 'Only admins can modify is_admin, is_banned, primary_community_id or max_owned_communities fields';
        end if;
    end if;
    return new;
end;
$function$;


-- ============================================================================================
-- BLOCK 5: the two legacy bridges (20261017_0001 [call] 1d.4-1d.6)
-- ============================================================================================
drop trigger if exists legacy_application_to_membership on public.profiles;
drop trigger if exists a_sync_legacy_approval_to_membership on public.profiles;
drop function if exists public.legacy_application_to_membership();
drop function if exists public.sync_legacy_approval_to_membership();


-- ============================================================================================
-- BLOCK 6: public.admin_reject_pending_user(uuid)   body unchanged (md5 f5366ee20a4fa51908b3e8173cb1e400)
-- ============================================================================================
revoke execute on function public.admin_reject_pending_user(uuid) from public, anon, authenticated;


-- ============================================================================================
-- BLOCK 7 (optional, D-S3): the installed build's default-community wrappers that no community build calls
-- ============================================================================================
revoke execute on function public.get_leaderboard(text, integer) from public, anon, authenticated;
revoke execute on function public.get_leaderboard(date, date) from public, anon, authenticated;
revoke execute on function public.send_broadcast_notifications(text, text, text, boolean) from public, anon, authenticated;
