-- 20261022_0001_archive_community_guard.sql
--
-- APPLIED 2026-10-22, one block, through the Supabase MCP apply_migration (migration-history version 20261022114848
-- 20261022_0001_block_1), after a rolled-back dry run (Community Release 2 server plan, task S0, run before every
-- other Release 2 server task). Deployed md5(prosrc) f66ac46feddff13eba34ad97ecbcf01c, equal to the text between this
-- file's $function$ delimiters (python3 -I over this file); the same text with the old guard line hashes to the
-- pre-change value below. ACL after the block unchanged: {postgres=X/postgres,authenticated=X/postgres,
-- service_role=X/postgres}; has_function_privilege anon false, authenticated true, service_role true. Still
-- security definer with search_path "". No deviation: the block ran as written below.
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
-- EXECUTE (ruling R-G1 as amended after S1), read live: md5(prosrc) f66ac46feddff13eba34ad97ecbcf01c and the ACL
-- above, unchanged by 0020-0023 (anon false, authenticated true); archive OK in the closing run. No header or grant
-- changed.
--
-- What it fixes. public.archive_community(uuid): a signed-in caller with no active membership in the community was
-- not refused. The guard compared public.my_community_role(...) = 'owner', which is NULL when the caller has no
-- active membership, so the whole condition was NULL and the refusal did not fire. The guard now reads
-- coalesce(public.my_community_role(p_community_id) = 'owner', false), so only the community's owner or a platform
-- admin passes it. Everything else is the live body, byte for byte.
--
-- Live body before the change. md5(prosrc) b6de43a4db32d8b42b945f573c019920, which is 20261017_0005 block 13.
-- Pre-change ACL (proacl): {postgres=X/postgres,authenticated=X/postgres,service_role=X/postgres};
-- has_function_privilege: anon false, authenticated true, service_role true. CREATE OR REPLACE keeps it, so the block
-- has no GRANT or REVOKE (anon has no EXECUTE, so ruling R-G1 adds nothing).
--
-- What old clients see. Nothing changes for owners and platform admins. A refused caller gets the existing answer
-- {"success": false, "error": "Only the owner can archive this community"}, which every client build already
-- handles; no client offers archiving to anyone but the owner.
--
-- Apply. One block. Before it, compare the live md5(prosrc) with b6de43a4db32d8b42b945f573c019920; stop on a mismatch.
-- No statement removes rows, drops a policy or writes to auth.* / storage.*.
--
-- Verification. supabase/probes/communities_probe.sql, block archive (a non-member, a pending applicant and a plain
-- member are refused; the owner archives; a platform admin restores; the default community cannot be archived) and
-- block short. Outcomes, 2026-10-22, each through one execute_sql with PARAMETERS and HELPERS:
--   Before the change, the amended archive block against the live function failed at its first new check (the
--   signed-in account with no membership was not refused), as expected; nothing was kept.
--   Dry run (begin; PARAMETERS and helpers; this block; an in-transaction check of the new md5 and the ACL; the
--   archive block under a savepoint; rollback): archive OK; afterwards the live md5 was still the pre-change value.
--   After the block: short OK, archive OK; md5 and ACL as recorded above.
--
-- Rollback. Re-create the function from 20261017_0005 block 13 (md5(prosrc) b6de43a4db32d8b42b945f573c019920). That
-- reopens the gap this block closes; do not roll back without a replacement guard.


-- ============================================================================================
-- BLOCK 1: public.archive_community(uuid)   live md5(prosrc) b6de43a4db32d8b42b945f573c019920 (20261017_0005 block 13)
-- Change: the guard's role comparison is wrapped in coalesce(..., false). Everything else is the live body.
-- ============================================================================================
create or replace function public.archive_community(p_community_id uuid)
returns jsonb
language plpgsql
security definer
set search_path to ''
as $function$
declare
  v_uid uuid := (select auth.uid());
  v_c record;
begin
  if v_uid is null or not (coalesce(public.my_community_role(p_community_id) = 'owner', false) or public.is_platform_admin()) then
    return jsonb_build_object('success', false, 'error', 'Only the owner can archive this community');
  end if;

  select c.is_default, c.archived_at into v_c from public.communities c where c.id = p_community_id;
  if not found then
    return jsonb_build_object('success', false, 'error', 'Community not found');
  end if;
  if v_c.is_default then
    return jsonb_build_object('success', false, 'error', 'The default community cannot be archived');
  end if;
  if v_c.archived_at is not null then
    return jsonb_build_object('success', false, 'error', 'This community is already archived');
  end if;

  perform public.archive_community_with_notices(p_community_id, v_uid);

  return jsonb_build_object('success', true);
end
$function$;
