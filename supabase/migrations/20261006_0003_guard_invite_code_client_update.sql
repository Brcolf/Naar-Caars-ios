-- 20261006_0003_guard_invite_code_client_update.sql
-- APPLIED 2026-10-06 through the Supabase MCP (guard_invite_code_client_update).
--
-- invite_codes: the one direct client UPDATE is "mark this unused code as used by me" during
-- sign-up (InviteService, single-use codes). The policy invite_codes_update_mark_as_used
-- allowed that but did not stop the same statement from rewriting the code text, its inviter,
-- its expiry or the bulk flags. This trigger keeps a client write to used_by / used_at.
--
-- Probes after applying (rolled back, as a second account): marking one unused code as used by
-- the caller still succeeds; the same update that also changes `code` or `created_by` fails
-- with 42501.
--
-- CORRECTION (2026-10-06): an earlier note here said a signed-in account could mark every
-- unused code as used. It cannot. The only SELECT policy on invite_codes is "created_by =
-- auth.uid()", and Postgres applies SELECT policies to an UPDATE that has a WHERE clause, so
-- an account can only touch codes it created. Rolled-back probe as a fresh signed-in account:
-- it sees 0 of the 47 unused single-use codes, the app's update-by-id marks 0 rows, and a
-- blanket update marks 0 rows (the 18 rows in the earlier probe were that account's own codes).
-- The same rule means the client's own path cannot work either: AuthService.validateInviteCode
-- reads the table directly and InviteService.markInviteCodeAsUsed updates it, and both match
-- nothing for a newcomer. Neither is reachable today (SignupInviteCodeView is not presented and
-- sign-up is open with admin approval). If invite codes come back, use the SECURITY DEFINER
-- functions validate_invite_code() and mark_invite_code_used() (the latter needs a
-- p_user_id = auth.uid() check and a grant) instead of table access.

create or replace function public.guard_invite_code_client_update()
returns trigger
language plpgsql
set search_path = ''
as $g$
begin
  if current_user not in ('authenticated', 'anon') then
    return new;
  end if;
  if (to_jsonb(new) - array['used_by', 'used_at']) is distinct from (to_jsonb(old) - array['used_by', 'used_at'])
     or old.used_by is not null
     or new.used_by is distinct from (select auth.uid())
     or new.used_at is null then
    raise exception 'An invite code can only be marked as used by the person signing up with it' using errcode = '42501';
  end if;
  return new;
end
$g$;

create or replace trigger guard_invite_code_client_update
  before update on public.invite_codes
  for each row execute function public.guard_invite_code_client_update();

revoke all on function public.guard_invite_code_client_update() from public, anon, authenticated;
