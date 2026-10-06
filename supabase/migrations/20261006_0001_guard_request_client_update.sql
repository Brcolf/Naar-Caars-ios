-- 20261006_0001_guard_request_client_update.sql
-- APPLIED 2026-10-06 through the Supabase MCP in two calls
-- (guard_request_client_update_function, guard_request_client_update_triggers).
--
-- Rides and favors: constrain what a client can change with a direct UPDATE.
--
-- The UPDATE policies on rides and favors are all PERMISSIVE, so Postgres ORs their USING
-- clauses and, separately, ORs their WITH CHECK clauses. "Authenticated users can claim open
-- rides" lets a non-owner reach any open, unclaimed row; "Users can update own or claimed
-- rides" then accepts any new row where the caller is user_id or claimed_by. Together they let
-- any signed-in member rewrite someone else's open request, make themselves its owner, hide it,
-- or mark it completed with themselves as the helper (which awards XP). Verified 2026-10-06
-- with rolled-back probes as a second account: all four updates touched one row.
--
-- This trigger leaves SECURITY DEFINER RPCs (complete_request, handle_completion_response,
-- admin_moderate_content, delete_user_account), the expiry job and the service role alone:
-- they do not run as a client role. It limits direct PostgREST writes to:
--   poster : any column except id, user_id, created_at, the moderation columns, and assigning
--            a helper (claimed_by may only be cleared);
--   others : claim (open -> confirmed, claimed_by = caller), unclaim (confirmed -> open by the
--            helper), and the helper marking a confirmed request completed (builds that predate
--            complete_request); nothing else changes. Review flags from a non-poster are kept
--            at their old values rather than rejected, so the invoker-rights
--            mark_request_reviewed trigger can never fail a review insert.
--
-- Probes after applying (begin; ... rollback; as two accounts): claim, unclaim, helper
-- complete, complete_request as helper and as poster, poster edit and poster review flags all
-- still succeed; takeover, rewrite, hide, open -> completed by a non-owner, a helper editing
-- notes, and a poster assigning a helper all fail with 42501.
--
-- To undo: drop trigger guard_request_client_update on public.rides; same on public.favors.

create or replace function public.guard_request_client_update()
returns trigger
language plpgsql
set search_path = ''
as $g$
declare
  v_uid uuid := (select auth.uid());
  v_free constant text[] := array['status', 'claimed_by', 'updated_at', 'reviewed', 'review_skipped', 'review_skipped_at'];
begin
  if current_user not in ('authenticated', 'anon') then
    return new;
  end if;

  if new.id is distinct from old.id
     or new.user_id is distinct from old.user_id
     or new.created_at is distinct from old.created_at
     or new.hidden_at is distinct from old.hidden_at
     or new.hidden_by is distinct from old.hidden_by
     or new.hidden_reason is distinct from old.hidden_reason then
    raise exception 'This change to a request is not allowed' using errcode = '42501';
  end if;

  if v_uid is not null and v_uid = old.user_id then
    if new.claimed_by is not null and new.claimed_by is distinct from old.claimed_by then
      raise exception 'A request is claimed by the person helping, not assigned by its poster' using errcode = '42501';
    end if;
    return new;
  end if;

  new.reviewed := old.reviewed;
  new.review_skipped := old.review_skipped;
  new.review_skipped_at := old.review_skipped_at;

  if (to_jsonb(new) - v_free) is distinct from (to_jsonb(old) - v_free) then
    raise exception 'Only the person who posted a request can edit it' using errcode = '42501';
  end if;

  if old.claimed_by is null and old.status::text = 'open'
     and new.claimed_by = v_uid and new.status::text = 'confirmed' then
    return new;
  end if;
  if old.claimed_by = v_uid and old.status::text = 'confirmed'
     and new.claimed_by is null and new.status::text = 'open' then
    return new;
  end if;
  if old.claimed_by = v_uid and old.status::text = 'confirmed'
     and new.claimed_by = v_uid and new.status::text = 'completed' then
    return new;
  end if;
  if new.claimed_by is not distinct from old.claimed_by and new.status is not distinct from old.status then
    return new;
  end if;

  raise exception 'This change to a request is not allowed' using errcode = '42501';
end
$g$;

create or replace trigger guard_request_client_update
  before update on public.rides
  for each row execute function public.guard_request_client_update();

create or replace trigger guard_request_client_update
  before update on public.favors
  for each row execute function public.guard_request_client_update();

-- Trigger functions are not callable through the API, but keep the grants tidy like the rest.
revoke all on function public.guard_request_client_update() from public, anon, authenticated;
