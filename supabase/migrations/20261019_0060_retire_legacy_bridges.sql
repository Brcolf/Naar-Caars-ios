-- 20261019_0060_retire_legacy_bridges.sql
--
-- APPLIED 2026-10-20, all seven blocks. Blocks 1, 2, 3, 4, 6 and 7 through the Supabase MCP apply_migration (the
-- migration-history versions in the paragraph below); block 5 (its two DROP TRIGGER and two DROP FUNCTION
-- statements, quoted below) by the owner in the SQL editor the same day, as Step 1 of
-- Docs/qa/2026-10-20-5b-owner-sql-steps.md (not in the migration history). Verified through the MCP afterwards:
-- neither bridge trigger nor either bridge function exists; fill_request_community 9d4cfb03912a7c4a874cffae239ee605,
-- redeem_community_invite 2ec0702dc3a4d400ca2599d0ebb15693, request_to_join_community
-- af9a2f5c560d2d74f35ab979e2f3856c, protect_admin_fields d963a013278b5ace77565b8397683bf2 (unchanged since the MCP
-- apply). Probes after all four owner steps (rolled back; probe PARAMETERS and HELPERS in each call, each probe under
-- a savepoint): account_deletion OK (run first), legacy_retired OK (the full block), legacy_bridges SKIPPED (the
-- trigger it tests for is gone, so it takes its SKIPPED branch), privileged_columns OK, short OK, broadcast_cap OK
-- (its 42501 branch). Final not-applied check (supabase/dryruns/20261019_phase5b_not_applied_check.sql, verbatim):
-- every column false, all_unchanged false. The paragraphs that follow are the partial-apply record, kept as history.
--
-- PARTIALLY APPLIED 2026-10-20: blocks 1, 2, 3, 4, 6 and 7 through the Supabase MCP apply_migration, one call per
-- block, in file order (migration-history versions 20261020163133 20261019_0060_block_1, 20261020163217
-- 20261019_0060_block_2, 20261020163259 20261019_0060_block_3, 20261020163341 20261019_0060_block_4, 20261020163419
-- 20261019_0060_block_6, 20261020163456 20261019_0060_block_7). BLOCK 5 IS NOT APPLIED: it is DROP TRIGGER / DROP
-- FUNCTION, which the MCP declines, so it is the owner's SQL-editor step (text below and in
-- Docs/qa/2026-10-20-5b-owner-sql-steps.md). The gate (A5 point 2: no pre-community build remains in use) opened on
-- 2026-10-20, when the owner confirmed it from App Store Connect. Deployed md5(prosrc): fill_request_community
-- 9d4cfb03912a7c4a874cffae239ee605, redeem_community_invite(text, text, text) 2ec0702dc3a4d400ca2599d0ebb15693,
-- request_to_join_community(uuid, text, text) af9a2f5c560d2d74f35ab979e2f3856c, protect_admin_fields
-- d963a013278b5ace77565b8397683bf2: the four values this file names (blocks 2-3 also checked them themselves).
-- Grants after the apply: fill_request_community postgres, service_role; redeem_community_invite and
-- request_to_join_community postgres, authenticated, service_role (kept by CREATE OR REPLACE); protect_admin_fields
-- unchanged; admin_reject_pending_user postgres, service_role (block 6); get_leaderboard (both) and
-- send_broadcast_notifications postgres, service_role (block 7). The two bridge triggers and their functions are
-- still in place until block 5 runs.
--   The state between block 4 and block 5 is the one the plan's runbook orders ("block 4 before block 5"): a
--   direct write of approved or application_complete under an end-user JWT raises 42501 before a bridge could act,
--   so the installed build's two direct writes fail and change nothing; the mirror (naars.membership_mirror) and
--   writes with no JWT pass as before. Blocks 6 and 7 are revokes on functions unrelated to block 5 and were applied
--   before it in file order; the runbook names no order between them and block 5.
--
-- Owner's SQL-editor step, the exact text of block 5 (run it alone in a new tab; it is one transaction there):
--   drop trigger if exists legacy_application_to_membership on public.profiles;
--   drop trigger if exists a_sync_legacy_approval_to_membership on public.profiles;
--   drop function if exists public.legacy_application_to_membership();
--   drop function if exists public.sync_legacy_approval_to_membership();
-- Then the not-applied check: bridges_present false as well, every File C / D / E column as before; then the probes
-- legacy_retired (OK), legacy_bridges (SKIPPED), privileged_columns, account_deletion and short. Block 5 runs before
-- File C (the plan's order: File B, then D, then the owner's C and E).
--
-- (Before the gate.) GATED: apply only after the owner confirms from App Store Connect that no pre-community build
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
-- privileged_columns, account_deletion and short as savepoints), then the not-applied check. At the gate: short
-- after every block; legacy_retired, privileged_columns, account_deletion at the end.
-- Outcomes, 2026-10-19. The script passed the plan's structural check (no commit;, one begin; and one rollback;,
-- six savepoint pairs, the helpers before begin;) and was sent verbatim as one execute_sql call: the Supabase MCP
-- DECLINED it ({"status":"declined"}, no reason given; nothing ran). The plan expected nothing in the script to be
-- declined. The likely cause is block 5's two DROP FUNCTION statements: the MCP declined DROP FUNCTION in
-- execute_sql and apply_migration alike on 2026-10-19 (20261019_0001 header). The script was not edited and the
-- dry run was not retried. The not-applied check right after answered all_unchanged = true. Still to do: this
-- dry run in the SQL editor (owner; the script verbatim, alone in a tab), then the not-applied check in a new tab.
-- At the gate, expect block 5 to need the SQL editor too.
-- Outcomes, 2026-10-20 (the gate). P1 re-read: the eight live values above (fill_request_community 6241f67f…,
-- redeem_community_invite f18e6af6…, request_to_join_community da89c233…, protect_admin_fields 48424e05…,
-- legacy_application_to_membership 38736139…, sync_legacy_approval_to_membership 52390660…, admin_reject_pending_user
-- f5366ee2…, get_leaderboard f97d8b82… / c52c79d1…, send_broadcast_notifications e238abe6…) all unchanged. P2 grants
-- as the plan records them. P3: approved accounts with no membership row 0, approved and application_complete mirror
-- drift 0 and 0, pending default-community applicants 0, profiles with heard_about or join_reason 5, live
-- communities 2, profiles 19. Block 4's precondition holds: only recompute_profile_membership_flags and
-- sync_legacy_approval_to_membership write either flag.
--   Subset dry run (the MCP declines the committed script because of block 5): blocks 1-4, 6, 7 inside
--   begin; ... rollback; with set local lock_timeout = '5s', the probe PARAMETERS and HELPERS, the probes under
--   savepoints and an in-transaction md5 check of the four edited bodies; three execute_sql calls, because a failing
--   probe ends its call: (S1) broadcast_cap (its block-7 branch, 42501), privileged_columns, account_deletion, short:
--   all OK. (S2) legacy_retired: FAILED as expected, "File B (20261019_0060) is not live; the legacy bridges still
--   exist" (its first statement requires block 5). (S3) legacy_bridges: FAILED as expected, "the old application
--   UPDATE succeeds: {... sqlstate 42501, approved and application_complete follow community memberships}" (it
--   prints SKIPPED only once block 5 has dropped the bridges; with block 4 in and the bridges present, block 4
--   refuses the write first, which is the intended state). After each call the live state was unchanged (md5s,
--   grants, both bridges, no probe rows). The probes were not edited.
--   Apply: short after each of the six blocks (rolled back): OK. At the end, one rolled-back call with the full
--   HELPERS: short, broadcast_cap (42501 branch), privileged_columns and account_deletion OK; legacy_retired FAILED
--   as expected with the S2 message (in this call its block was sent cut after its first two checks, which does
--   not change the outcome: it stops at its first statement; the unedited block ran in S2).
--   Not-applied check after the apply: false in fill_request_community_unchanged,
--   redeem_community_invite_unchanged, request_to_join_community_unchanged, protect_admin_fields_unchanged,
--   admin_reject_pending_user_open and send_broadcast_notifications_open (the six blocks applied); true in
--   bridges_present (block 5 pending) and in every File C, D and E column; all_unchanged false.
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
