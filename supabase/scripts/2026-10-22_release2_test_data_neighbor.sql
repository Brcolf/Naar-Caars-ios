-- 2026-10-22_release2_test_data_neighbor.sql
--
-- STATUS: APPLIED 2026-10-23 (committed at about 12:42 UTC), once, through one Supabase MCP execute_sql call carrying
-- the text from "begin;" to "commit;" below byte for byte. Do not run it again: Part A stops a second run (the
-- neighbor already has a Test Community row). No migration-history entry (a data script, as S5a).
-- A one-off data script, not a migration: do not move it to supabase/migrations and never `supabase db push`.
-- It runs as one transaction (one Supabase MCP execute_sql call, or the SQL editor) and stops, writing nothing, on
-- any mismatch in Part A or Part E.
--
-- OUTCOMES, 2026-10-23
--   Before (read live): NC Test Neighbor had no community_members row, no comment and no Q&A, profiles.approved false;
--   the three target rows matched their prefixes, by NC Test Owner, open where a request; 0 request_qa and 0
--   town_hall_comments rows anywhere; Test Community had 20 active members; platform totals 2911 notifications, 3077
--   notification_queue rows, 252 xp_events, 45 membership events. The MCP accepted the four `alter table ...
--   disable / enable trigger` statements.
--   Dry run: the same text with "commit;" replaced by a totals select and "rollback;", in one execute_sql call. Part E
--   raised nothing; inside the transaction the totals read 2911 notifications, 3077 queued pushes, 252 xp_events
--   (all unchanged), 2 Q&A, 1 comment, 46 membership events, the neighbor approved. Afterwards nothing was left (0
--   Q&A, 0 comments, 20 members, 45 events, the neighbor not approved, both triggers 'O').
--   Run: Part E raised nothing and printed {qa: 2, comments: 1, notifications_created: 0, pushes_queued: 0,
--   xp_events_created: 0, active_members: 21, triggers_enabled: 2, outcome: "S5b OK"}; the transaction committed.
--   After (read live): totals 2911 notifications, 3077 queued pushes, 252 xp_events (equal to before), 0 of either
--   in the 15 minutes after the run; 2 Q&A, 1 comment, 46 membership events; Test Community 21 active members; the
--   neighbor approved, application_complete, primary community Test Community; both triggers 'O'. Rolled back, as NC
--   Test Owner (role authenticated, request.jwt.claims sub): the airport ride's Q&A returns "How much luggage will
--   you have?" with "One carry-on and a backpack.", the apples favor's returns its question and answer, the post
--   returns the comment; as anon (no expectation, recorded): request_qa 2 rows and town_hall_comments 1 row visible.
--
-- Task S5b of Community Release 2 (plan Docs/superpowers/plans/2026-10-21-community-release2-discovery-sql.md, task
-- S5, split by the orchestrator's ruling R-G3; design Docs/superpowers/specs/2026-10-21-community-discovery-and-trust-
-- design.md 4.11). S5a (supabase/scripts/2026-10-21_release2_test_data.sql, applied 2026-10-22) wrote NC Test Owner's
-- example requests and posts; this script writes NC Test Neighbor's rows.
--
-- Owner's go-ahead: their message of 2026-10-23, "Go ahead and create it so you can run the checks", on top of the
-- standing SQL authorization for the multi-community build; the owner also said no real users are live yet. NC Test
-- Neighbor (id first 8 76396234, Docs/qa/test-data.md) was made on 2026-10-23 through the app's Sign Up by the
-- orchestrator. The rows are written as postgres by resolved id; no sign-in detail is used.
--
-- WHAT IT WRITES (everything inside one transaction; nobody is told: 0 notifications, 0 pushes, 0 XP)
--   Part A (read only): resolves NC Test Owner (exactly one profile with that name, id starting eebf5514) and NC Test
--     Neighbor (exactly one, id starting 76396234); Test Community 7a8ed131-cb05-462b-a491-b433d70a3fe5 (default, not
--     archived); the example airport ride (pickup Westlake Station, open, id starting e3327efa), the example apples
--     favor (open, id starting d17edf4c) and the example post "Is the Ballard Farmers Market open on holidays?" (id
--     starting 0422cce4), all in Test Community and by NC Test Owner; checks that the neighbor has no
--     community_members row in Test Community, no Town Hall comment and no Q&A anywhere, that no example request has a
--     Q&A row and no example post a comment yet, and that every column this script writes exists. Any mismatch raises.
--   Part C: NC Test Neighbor becomes an active member of Test Community (role member), as S5a's Part C:
--     naars.suppress_approval_notice = '1' around the insert (the membership mirror turns profiles.approved from false
--     to true, and notify_user_approved returns early under this setting), then one membership event 'approved'
--     (new_role member, actor null, reason 'example content account').
--   Part D: inside this transaction only (no other session ever sees them off), the two insert notifiers are
--     disabled, `alter table public.town_hall_comments disable trigger on_town_hall_comment_notify;` and
--     `alter table public.request_qa disable trigger on_qa_created_notify;`, then:
--       the comment by NC Test Neighbor on the farmers market post: "It's open every Sunday, holidays included.";
--       on the airport ride, asked by NC Test Neighbor and answered by NC Test Owner in the same insert
--         (answered_by, answered_at = now()): "How much luggage will you have?" / "One carry-on and a backpack.";
--       on the apples favor, the same way: "Which stall do you usually buy from?" / "Any stall with Honeycrisp apples
--         is fine.";
--     then both triggers are enabled again.
--     The other triggers on the two tables (read live 2026-10-23): on_qa_answer_notify (AFTER UPDATE only, so an
--     insert that carries the answer does not fire it) and update_town_hall_comments_updated_at (BEFORE UPDATE,
--     timestamps only). No trigger on either table writes xp_events or queues a push. They stay as they are.
--   Part E (read only, raises on any mismatch): 2 Q&A rows and 1 comment by the neighbor, each on its target; 0
--     notifications and 0 notification_queue rows created in this transaction (created_at >= transaction_timestamp());
--     0 xp_events for the neighbor, for the three new ids or created in this transaction; the neighbor active in Test
--     Community with one 'approved' event and profiles.approved true; Test Community has 21 active members; both
--     notify triggers enabled ('O'). Then it prints one outcome row and the transaction commits.
--
-- ROLLBACK (owner's SQL-editor steps; the MCP declines DELETE, so they are not rephrased here; resolve the ids with
-- the Part A queries first):
--   delete from public.request_qa where user_id = <NC Test Neighbor id> and ride_id = <airport ride id>;
--   delete from public.request_qa where user_id = <NC Test Neighbor id> and favor_id = <apples favor id>;
--   delete from public.town_hall_comments where user_id = <NC Test Neighbor id> and post_id = <farmers market post id>;
--   The membership: leave through the app as NC Test Neighbor (writes the 'left' event and runs the mirror), not a
--   DELETE. The membership event is append-only (community_membership_events_append_only refuses UPDATE and DELETE);
--   removing it, and the membership row with it, would be:
--   delete from public.community_members where community_id = '7a8ed131-cb05-462b-a491-b433d70a3fe5'
--     and user_id = <NC Test Neighbor id>;
--   (the event row stays as the record; the mirror then sets the neighbor's profiles.approved back to false)

begin;

-- =============================================================================================================
-- Parts A and C
-- =============================================================================================================
do $s5b$
declare
  v_tc   constant uuid := '7a8ed131-cb05-462b-a491-b433d70a3fe5';
  v_owner uuid;
  v_neighbor uuid;
  v_ride uuid;
  v_favor uuid;
  v_post uuid;
  v_n integer;
begin
  -- ---------------------------------------------------------------------------------------------------------
  -- Part A (read only)
  -- ---------------------------------------------------------------------------------------------------------
  select count(*) into v_n from public.profiles where name = 'NC Test Owner';
  if v_n <> 1 then
    raise exception 'S5b stop: expected exactly one profile named NC Test Owner, found %', v_n;
  end if;
  select id into v_owner from public.profiles where name = 'NC Test Owner';
  if left(v_owner::text, 8) <> 'eebf5514' then
    raise exception 'S5b stop: NC Test Owner id does not start with eebf5514';
  end if;

  select count(*) into v_n from public.profiles where name = 'NC Test Neighbor';
  if v_n <> 1 then
    raise exception 'S5b stop: expected exactly one profile named NC Test Neighbor, found %', v_n;
  end if;
  select id into v_neighbor from public.profiles where name = 'NC Test Neighbor';
  if left(v_neighbor::text, 8) <> '76396234' then
    raise exception 'S5b stop: NC Test Neighbor id does not start with 76396234';
  end if;

  select count(*) into v_n from public.communities c
   where c.id = v_tc and c.name = 'Test Community' and c.is_default and c.archived_at is null;
  if v_n <> 1 then
    raise exception 'S5b stop: Test Community is not the default, unarchived row expected';
  end if;

  select count(*) into v_n from public.rides
   where community_id = v_tc and is_example and status = 'open' and user_id = v_owner
     and pickup = 'Westlake Station' and destination = 'Seattle-Tacoma International Airport';
  if v_n <> 1 then raise exception 'S5b stop: expected one example airport ride, found %', v_n; end if;
  select id into v_ride from public.rides
   where community_id = v_tc and is_example and status = 'open' and user_id = v_owner
     and pickup = 'Westlake Station' and destination = 'Seattle-Tacoma International Airport';
  if left(v_ride::text, 8) <> 'e3327efa' then
    raise exception 'S5b stop: the airport ride id does not start with e3327efa';
  end if;

  select count(*) into v_n from public.favors
   where community_id = v_tc and is_example and status = 'open' and user_id = v_owner
     and title = 'Pick up a box of apples at the farmers market';
  if v_n <> 1 then raise exception 'S5b stop: expected one example apples favor, found %', v_n; end if;
  select id into v_favor from public.favors
   where community_id = v_tc and is_example and status = 'open' and user_id = v_owner
     and title = 'Pick up a box of apples at the farmers market';
  if left(v_favor::text, 8) <> 'd17edf4c' then
    raise exception 'S5b stop: the apples favor id does not start with d17edf4c';
  end if;

  select count(*) into v_n from public.town_hall_posts
   where community_id = v_tc and is_example and user_id = v_owner
     and title = 'Is the Ballard Farmers Market open on holidays?';
  if v_n <> 1 then raise exception 'S5b stop: expected one example farmers market post, found %', v_n; end if;
  select id into v_post from public.town_hall_posts
   where community_id = v_tc and is_example and user_id = v_owner
     and title = 'Is the Ballard Farmers Market open on holidays?';
  if left(v_post::text, 8) <> '0422cce4' then
    raise exception 'S5b stop: the farmers market post id does not start with 0422cce4';
  end if;

  if exists (select 1 from public.community_members where community_id = v_tc and user_id = v_neighbor) then
    raise exception 'S5b stop: NC Test Neighbor already has a Test Community row';
  end if;
  select (select count(*) from public.town_hall_comments where user_id = v_neighbor)
       + (select count(*) from public.request_qa where user_id = v_neighbor)
    into v_n;
  if v_n <> 0 then raise exception 'S5b stop: NC Test Neighbor already has % comments or Q&A rows', v_n; end if;
  select (select count(*) from public.request_qa q
           where q.ride_id in (select id from public.rides where is_example)
              or q.favor_id in (select id from public.favors where is_example))
       + (select count(*) from public.town_hall_comments c
           where c.post_id in (select id from public.town_hall_posts where is_example))
    into v_n;
  if v_n <> 0 then raise exception 'S5b stop: % Q&A or comment rows already on example content', v_n; end if;

  select count(*) into v_n
    from information_schema.columns
   where table_schema = 'public'
     and (table_name, column_name) in (
       ('community_members', 'community_id'), ('community_members', 'user_id'), ('community_members', 'role'),
       ('community_members', 'status'), ('community_members', 'activated_at'),
       ('community_membership_events', 'community_id'), ('community_membership_events', 'user_id'),
       ('community_membership_events', 'actor_id'), ('community_membership_events', 'event'),
       ('community_membership_events', 'new_role'), ('community_membership_events', 'reason'),
       ('town_hall_comments', 'post_id'), ('town_hall_comments', 'user_id'), ('town_hall_comments', 'content'),
       ('request_qa', 'ride_id'), ('request_qa', 'favor_id'), ('request_qa', 'user_id'),
       ('request_qa', 'question'), ('request_qa', 'answer'), ('request_qa', 'answered_by'),
       ('request_qa', 'answered_at'));
  if v_n <> 21 then
    raise exception 'S5b stop: expected 21 columns, found %', v_n;
  end if;

  -- ---------------------------------------------------------------------------------------------------------
  -- Part C: NC Test Neighbor active in Test Community
  -- ---------------------------------------------------------------------------------------------------------
  perform set_config('naars.suppress_approval_notice', '1', true);
  insert into public.community_members (community_id, user_id, role, status, activated_at)
  values (v_tc, v_neighbor, 'member', 'active', now());
  perform set_config('naars.suppress_approval_notice', '', true);

  insert into public.community_membership_events (community_id, user_id, actor_id, event, new_role, reason)
  values (v_tc, v_neighbor, null, 'approved', 'member', 'example content account');
end
$s5b$;

-- =============================================================================================================
-- Part D: the comment and the two answered questions, the two insert notifiers off inside this transaction
-- =============================================================================================================
alter table public.town_hall_comments disable trigger on_town_hall_comment_notify;
alter table public.request_qa disable trigger on_qa_created_notify;

do $s5b_content$
declare
  v_tc   constant uuid := '7a8ed131-cb05-462b-a491-b433d70a3fe5';
  v_owner uuid;
  v_neighbor uuid;
  v_ride uuid;
  v_favor uuid;
  v_post uuid;
begin
  -- the same rows Part A resolved and asserted
  select id into strict v_owner from public.profiles where name = 'NC Test Owner';
  select id into strict v_neighbor from public.profiles where name = 'NC Test Neighbor';
  select id into strict v_ride from public.rides
   where community_id = v_tc and is_example and status = 'open' and user_id = v_owner
     and pickup = 'Westlake Station' and destination = 'Seattle-Tacoma International Airport';
  select id into strict v_favor from public.favors
   where community_id = v_tc and is_example and status = 'open' and user_id = v_owner
     and title = 'Pick up a box of apples at the farmers market';
  select id into strict v_post from public.town_hall_posts
   where community_id = v_tc and is_example and user_id = v_owner
     and title = 'Is the Ballard Farmers Market open on holidays?';

  insert into public.town_hall_comments (post_id, user_id, content)
  values (v_post, v_neighbor, 'It''s open every Sunday, holidays included.');

  insert into public.request_qa (ride_id, favor_id, user_id, question, answer, answered_by, answered_at)
  values
    (v_ride, null, v_neighbor, 'How much luggage will you have?', 'One carry-on and a backpack.', v_owner, now()),
    (null, v_favor, v_neighbor, 'Which stall do you usually buy from?', 'Any stall with Honeycrisp apples is fine.',
     v_owner, now());
end
$s5b_content$;

alter table public.town_hall_comments enable trigger on_town_hall_comment_notify;
alter table public.request_qa enable trigger on_qa_created_notify;

-- =============================================================================================================
-- Part E (read only; raises on any mismatch)
-- =============================================================================================================
do $s5b_check$
declare
  v_tc constant uuid := '7a8ed131-cb05-462b-a491-b433d70a3fe5';
  v_owner uuid;
  v_neighbor uuid;
  v_n integer;
begin
  select id into v_owner from public.profiles where name = 'NC Test Owner';
  select id into v_neighbor from public.profiles where name = 'NC Test Neighbor';

  select count(*) into v_n from public.request_qa q
   where q.user_id = v_neighbor and q.answered_by = v_owner and q.answer is not null and q.answered_at is not null
     and ((q.question = 'How much luggage will you have?' and q.answer = 'One carry-on and a backpack.'
           and q.ride_id in (select id from public.rides where community_id = v_tc and is_example
                               and pickup = 'Westlake Station'))
          or (q.question = 'Which stall do you usually buy from?'
              and q.answer = 'Any stall with Honeycrisp apples is fine.'
              and q.favor_id in (select id from public.favors where community_id = v_tc and is_example
                                   and title = 'Pick up a box of apples at the farmers market')));
  if v_n <> 2 then raise exception 'S5b check: expected 2 answered Q&A rows on their targets, found %', v_n; end if;
  select count(*) into v_n from public.request_qa where user_id = v_neighbor;
  if v_n <> 2 then raise exception 'S5b check: expected 2 Q&A rows by the neighbor, found %', v_n; end if;
  raise notice 'S5b check: qa = %', v_n;

  select count(*) into v_n from public.town_hall_comments c
   where c.user_id = v_neighbor and c.content = 'It''s open every Sunday, holidays included.'
     and c.post_id in (select id from public.town_hall_posts where community_id = v_tc and is_example
                         and title = 'Is the Ballard Farmers Market open on holidays?');
  if v_n <> 1 then raise exception 'S5b check: expected 1 comment on the farmers market post, found %', v_n; end if;
  select count(*) into v_n from public.town_hall_comments where user_id = v_neighbor;
  if v_n <> 1 then raise exception 'S5b check: expected 1 comment by the neighbor, found %', v_n; end if;
  raise notice 'S5b check: comments = %', v_n;

  select count(*) into v_n from public.notifications where created_at >= transaction_timestamp();
  if v_n <> 0 then raise exception 'S5b check: % notifications created in this transaction', v_n; end if;
  raise notice 'S5b check: notifications_created = %', v_n;
  select count(*) into v_n from public.notification_queue where created_at >= transaction_timestamp();
  if v_n <> 0 then raise exception 'S5b check: % pushes queued in this transaction', v_n; end if;
  raise notice 'S5b check: pushes_queued = %', v_n;

  select count(*) into v_n from public.xp_events x
   where x.created_at >= transaction_timestamp()
      or x.user_id = v_neighbor
      or x.source_id in (select id from public.request_qa where user_id = v_neighbor
                         union all select id from public.town_hall_comments where user_id = v_neighbor);
  if v_n <> 0 then raise exception 'S5b check: % xp_events for the neighbor or the new rows', v_n; end if;
  raise notice 'S5b check: xp_events = %', v_n;

  select count(*) into v_n from public.community_members
   where community_id = v_tc and user_id = v_neighbor and status = 'active' and role = 'member';
  if v_n <> 1 then raise exception 'S5b check: NC Test Neighbor is not an active member of Test Community'; end if;
  select count(*) into v_n from public.community_membership_events
   where community_id = v_tc and user_id = v_neighbor and event = 'approved' and reason = 'example content account';
  if v_n <> 1 then raise exception 'S5b check: expected one approved event, found %', v_n; end if;
  select count(*) into v_n from public.profiles where id = v_neighbor and approved;
  if v_n <> 1 then raise exception 'S5b check: the membership mirror did not approve the neighbor'; end if;

  select count(*) into v_n from public.community_members where community_id = v_tc and status = 'active';
  if v_n <> 21 then raise exception 'S5b check: Test Community has % active members, expected 21', v_n; end if;
  raise notice 'S5b check: active_members = %', v_n;

  select count(*) into v_n from pg_trigger
   where not tgisinternal and tgenabled = 'O'
     and (tgrelid, tgname) in (
       ('public.town_hall_comments'::regclass, 'on_town_hall_comment_notify'),
       ('public.request_qa'::regclass, 'on_qa_created_notify'));
  if v_n <> 2 then raise exception 'S5b check: % of 2 notify triggers enabled', v_n; end if;
  raise notice 'S5b check: triggers_enabled = %', v_n;
end
$s5b_check$;

select jsonb_build_object(
  'qa', (select count(*) from public.request_qa q join public.profiles p on p.id = q.user_id
          where p.name = 'NC Test Neighbor'),
  'comments', (select count(*) from public.town_hall_comments c join public.profiles p on p.id = c.user_id
                where p.name = 'NC Test Neighbor'),
  'notifications_created', (select count(*) from public.notifications where created_at >= transaction_timestamp()),
  'pushes_queued', (select count(*) from public.notification_queue where created_at >= transaction_timestamp()),
  'xp_events_created', (select count(*) from public.xp_events where created_at >= transaction_timestamp()),
  'active_members', (select count(*) from public.community_members
                      where community_id = '7a8ed131-cb05-462b-a491-b433d70a3fe5' and status = 'active'),
  'triggers_enabled', (select count(*) from pg_trigger where not tgisinternal and tgenabled = 'O'
                        and tgname in ('on_town_hall_comment_notify', 'on_qa_created_notify')),
  'outcome', 'S5b OK') as s5b;

commit;
