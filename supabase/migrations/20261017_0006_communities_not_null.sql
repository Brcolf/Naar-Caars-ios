-- 20261017_0006_communities_not_null.sql
-- APPLIED 2026-10-18 (Supabase MCP apply_migration, the whole file in one call; migration-history
-- version 20261018182957), after steps 0-5 were live and the full probe matrix had passed once after
-- step 5. Dry run first inside begin; ... rollback;: the assertion raised nothing, all four columns read
-- is_nullable = 'NO', and a member's ride and post inserted without community_id still landed in the
-- default community (the fill triggers run before the constraint). After the apply: is_nullable = 'NO'
-- on rides, favors, town_hall_posts and xp_events; the full matrix (noop_default with the pre-Phase-0 XP
-- baseline, isolation, legacy_bridges, owner_notifications, privileged_columns, membership_end, archive,
-- invites, account_deletion, reports, reputation, blocks, creation_limits) and short all passed in one
-- rolled-back transaction; no probe row leaked. Phase 0 is complete.
-- Phase 0, step 6 of the multi-community build, and the LAST Phase 0 file
-- (Docs/superpowers/specs/2026-10-07-multi-community-design.md §4 "Step 6", §3.6 INV-R1, as amended by
-- Docs/superpowers/specs/2026-10-17-multi-community-decisions.md).
--
-- Apply only after ALL of these are live, each followed by a passing short probe:
--   20261017_0001 (core, with back-fill Part B), 0002 (RLS), 0003 (fan-out), 0004 (account lifecycle,
--   SQL editor) and 0005 (RPCs); and after the full probe matrix of supabase/probes/communities_probe.sql
--   has passed once after step 5. Then run the full matrix again after this file.
--
-- What this file does
--   1. Asserts that no row of rides, favors, town_hall_posts or xp_events has a null community_id, and
--      that the four fill triggers that supply it for the installed build (fill_community_rides,
--      fill_community_favors, fill_community_posts, fill_community_xp_events) exist and are enabled.
--      Either failing raises and nothing is changed.
--   2. Sets community_id NOT NULL on those four tables, turning the step-1 fact (back-fill Part B plus
--      the fill triggers) into a constraint (INV-R1: every request, post and XP event belongs to exactly
--      one community). notifications.community_id and reports.community_id stay nullable on purpose:
--      message rows, community reports and person reports with no single shared community have none.
--
-- How to apply
--   ONE Supabase MCP apply_migration call with the whole file (it holds no function, so the
--   one-function-per-call rule does not apply; the assertion and the four ALTERs commit or fail
--   together). Each SET NOT NULL scans its table under an ACCESS EXCLUSIVE lock; on 2026-10-17 the
--   tables held about 110 rides, 65 favors, 35 posts and a few hundred xp_events, so the lock lasts
--   milliseconds. Dry-run first inside begin; ... rollback; with the short probe.
--
-- Verification (to be filled in at apply time)
--   Assertion: 0 / 0 / 0 / 0 null rows; four fill triggers present and enabled.
--   After applying: information_schema.columns.is_nullable = 'NO' for the four columns; the short probe
--   (a ride and a favor inserted without community_id by an existing member are filled and accepted,
--   claim, complete, 5-star review, three xp_events rows with the default community, deletion of a
--   probe member, a probe admin and the default community's owner) and the full matrix: ________.
--
-- What old clients see
--   Nothing. The installed build never sends community_id; the BEFORE INSERT fill triggers set it before
--   the NOT NULL check runs. An account with no active membership was already refused by
--   fill_request_community ('Choose a community', 42501) before this file, and fill_xp_event_community
--   never leaves the column null while a default community exists, so no write that succeeds today
--   fails after it. Responses are unchanged.
--
-- To undo (one call)
--   alter table public.rides           alter column community_id drop not null;
--   alter table public.favors          alter column community_id drop not null;
--   alter table public.town_hall_posts alter column community_id drop not null;
--   alter table public.xp_events       alter column community_id drop not null;

do $$
declare
  v_rides  bigint;
  v_favors bigint;
  v_posts  bigint;
  v_xp     bigint;
  v_fill   int;
begin
  select count(*) into v_rides  from public.rides           where community_id is null;
  select count(*) into v_favors from public.favors          where community_id is null;
  select count(*) into v_posts  from public.town_hall_posts where community_id is null;
  select count(*) into v_xp     from public.xp_events       where community_id is null;
  if v_rides + v_favors + v_posts + v_xp > 0 then
    raise exception 'community_id is null on rides %, favors %, town_hall_posts %, xp_events %; re-run back-fill Part B (20261017_0001 [call] 1f.1) first',
      v_rides, v_favors, v_posts, v_xp;
  end if;

  -- without these, the installed build's inserts (no community_id) would fail the constraint below
  select count(*) into v_fill
    from pg_catalog.pg_trigger t
   where not t.tgisinternal
     and t.tgenabled <> 'D'
     and (   (t.tgrelid = 'public.rides'::regclass           and t.tgname = 'fill_community_rides')
          or (t.tgrelid = 'public.favors'::regclass          and t.tgname = 'fill_community_favors')
          or (t.tgrelid = 'public.town_hall_posts'::regclass and t.tgname = 'fill_community_posts')
          or (t.tgrelid = 'public.xp_events'::regclass       and t.tgname = 'fill_community_xp_events'));
  if v_fill <> 4 then
    raise exception 'expected the 4 fill_community_* triggers to exist and be enabled, found %', v_fill;
  end if;
end
$$;

alter table public.rides           alter column community_id set not null;
alter table public.favors          alter column community_id set not null;
alter table public.town_hall_posts alter column community_id set not null;
alter table public.xp_events       alter column community_id set not null;
