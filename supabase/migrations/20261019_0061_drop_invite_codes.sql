-- 20261019_0061_drop_invite_codes.sql
--
-- NOT APPLIED. GATED: apply only after the owner confirms from App Store Connect that no pre-community build
-- remains in use (A5 point 2). SQL EDITOR (owner), as ONE transaction: delete_user_account's body deletes
-- from auth.users and storage.objects and the file drops a table, which the Supabase MCP declines.
-- Phase 5b of the multi-community design (§4 "Phase 5": invite_codes and its policies / triggers dropped in a
-- SQL-editor file).
--
-- What it does.
--   0. (before the transaction, read only) the rollback capture: pg_get_functiondef of the four functions,
--      the table's columns, constraints, indexes, policies and triggers, saved to
--      supabase/migrations/20261019_0061a_invite_codes_rollback_capture.sql (DDL only, committed, never
--      applied); the 62 rows exported to a CSV kept OFF the repository (they hold user ids; the repo is public).
--   1. delete_user_account: its one statement on invite_codes (STEP 7, live line 269) goes, so account deletion
--      keeps working once the table is gone (App Store 5.1.1(v)). Derived from the live definition (D-S1).
--   2. drop table public.invite_codes (its four policies, two triggers, three foreign keys, the unique index
--      and the self reference go with it; no other table references it).
--   3. the four functions that existed only for it: validate_invite_code (EXECUTE for anon today: it tells
--      anyone whether a code exists), mark_invite_code_used, guard_invite_code_client_update,
--      handle_invite_code_used.
--
-- What old clients see. Nothing reachable: the installed build has no screen that reads or writes the table
-- (its AdminInviteView, InvitationWorkflowView and SignupInviteCodeView are never presented), and no
-- community build references it after iOS Tasks 1-3. Sign-up never used it (public sign-up,
-- create_signup_profile). Community invites (community_invites) are unaffected.
--
-- Verification. Dry run (now, owner, SQL editor): NOT this file. Paste only
-- supabase/dryruns/20261019_0061_drop_invite_codes.dryrun.sql, verbatim (it holds blocks 1-3 inside one
-- begin; ... rollback;, the probe helpers without their commit;, and invite_codes_dropped, account_deletion and
-- short as savepoints), after C0 and the CSV export; then the not-applied check in a new tab. At the gate: this
-- file as one transaction, then invite_codes_dropped, short and account_deletion.
-- C0, 2026-10-19 (orchestrator, read only, through the MCP, before any File C dry run). The DDL capture is
-- supabase/migrations/20261019_0061a_invite_codes_rollback_capture.sql: the four functions' live md5(prosrc) equal
-- the plan's P1, and their bodies in the capture hash to the same values. The 62 rows (54 never used) were exported
-- off this repository to /Users/bcolf/Documents/naars-cars-ios-roadmap-research/2026-10-19-invite_codes-backup.csv
-- (a header row and 62 rows; every line and the whole file checked against an md5 computed on the server; file md5
-- 50dc9c4c7d7751050f9dcd98dae873a8; owner-only permissions).
-- Outcomes of the owner's SQL-editor dry run: not yet run.
--
-- Rollback. Recreate the table, its constraints, policies and triggers and the four functions from
-- 20261019_0061a; load the CSV; re-run delete_user_account from 20261017_0004:214-499.

begin;

-- ============================================================================================
-- BLOCK 1: public.delete_user_account(uuid)   live md5 135aca113be1ebf5281c03c288ee32c6 (20261017_0004:214-496)
-- Removed, exactly once: "    delete from public.invite_codes where created_by = p_user_id;" (STEP 7).
-- Deployed md5 must be bd886e739d25dbe7497ff6b21c5aa248.
-- ============================================================================================
do $derive$
declare
  v_fn constant regprocedure := 'public.delete_user_account(uuid)'::regprocedure;
  v_cut constant text := E'    delete from public.invite_codes where created_by = p_user_id;\n';
  v_def text;
begin
  if (select md5(p.prosrc) from pg_catalog.pg_proc p where p.oid = v_fn) <> '135aca113be1ebf5281c03c288ee32c6' then
    raise exception 'delete_user_account is not the expected live body';
  end if;
  v_def := pg_catalog.pg_get_functiondef(v_fn);
  if (length(v_def) - length(replace(v_def, v_cut, ''))) / length(v_cut) <> 1 then
    raise exception 'delete_user_account: the invite_codes statement was not found exactly once';
  end if;
  execute replace(v_def, v_cut, '');
  if (select md5(p.prosrc) from pg_catalog.pg_proc p where p.oid = v_fn) <> 'bd886e739d25dbe7497ff6b21c5aa248' then
    raise exception 'delete_user_account: unexpected body after the edit';
  end if;
end
$derive$;

-- ============================================================================================
-- BLOCK 2: the table
-- ============================================================================================
drop table public.invite_codes;

-- ============================================================================================
-- BLOCK 3: the functions that existed only for it
-- ============================================================================================
drop function if exists public.validate_invite_code(text);
drop function if exists public.mark_invite_code_used(text, text, text, text);
drop function if exists public.guard_invite_code_client_update();
drop function if exists public.handle_invite_code_used();

-- the guard: no function body may still name the table
do $check$
begin
  if exists (select 1 from pg_catalog.pg_proc p
              where p.pronamespace = 'public'::regnamespace and position('invite_codes' in p.prosrc) > 0) then
    raise exception 'a public function still names invite_codes';
  end if;
end
$check$;

commit;
