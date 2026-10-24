-- 2026-10-21_release2_test_data.sql
--
-- STATUS: APPLIED 2026-10-22 (committed at about 18:24 UTC), once, through one Supabase MCP execute_sql call carrying
-- the text from "begin;" to "commit;" below byte for byte. Do not run it again: Part A stops a second run (Test
-- Community already has example rows). No migration-history entry (a data script, not a migration).
-- A one-off data script, not a migration: do not move it to supabase/migrations and never `supabase db push`.
-- It runs as one transaction (one Supabase MCP execute_sql call, or the SQL editor) and stops, writing nothing, on
-- any mismatch in Part A or Part E.
--
-- OUTCOMES, 2026-10-22
--   Before: Test Community had 0 rides, 0 favors, 0 Town Hall posts, 0 comments and 0 Q&A (the member content
--   that supabase/scripts/2026-10-21_test_community_cleanup.sql targets no longer existed), no example row anywhere,
--   no community with an area or is_test, 19 active members; NC Test Owner had no Test Community row.
--   Dry run: the same text with "commit;" replaced by anon visitor reads and "rollback;", in one execute_sql call.
--   Part E raised nothing; as anon, get_community_preview(Test Community) listed the 8 open examples (each
--   is_example true, dates today + 1 .. today + 7 in Los Angeles) and the 3 posts, search_communities_by_name('test')
--   returned Test Community only, find_communities_near(47.6062, -122.3321) returned Test Community at distance_miles
--   0. Afterwards nothing was left (0 example rows, 0 is_test, 0 areas, 19 members).
--   Run: Part E printed {example_requests: 8, example_posts: 3, notifications_created: 0, pushes_queued: 0,
--   xp_events_created: 0, test_communities: 4, triggers_enabled: 7, outcome: "S5a OK"} and the transaction committed.
--   After (read live): 8 example requests and 3 example posts, all in Test Community, no other row in it; 0
--   notifications and 0 notification_queue rows since the insert, 0 naming an example row; 0 xp_events for the
--   examples; 0 community_listing_events rows; 20 active members. Step 4 as anon (rolled back): the preview lists the
--   8 examples (is_example true) and the welcome post, the name search for "test" returns Test Community and none of
--   the four test communities, the place search at Test Community's centre returns it at distance_miles 0;
--   guest_rides / guest_favors show 4 / 4 examples; refresh_example_requests() changes 0 rows (rolled back).
--
-- Task S5a of Community Release 2 (plan Docs/superpowers/plans/2026-10-21-community-release2-discovery-sql.md, task
-- S5, split by the orchestrator's ruling R-G3; design Docs/superpowers/specs/2026-10-21-community-discovery-and-trust-
-- design.md 4.10 and 4.11). S5b (supabase/scripts/2026-10-22_release2_test_data_neighbor.sql, written and APPLIED
-- 2026-10-23) carries NC Test Neighbor's rows: the neighbor's active membership in Test Community, the one Town Hall
-- comment and the two answered questions, written once that account existed (id prefix in Docs/qa/test-data.md).
--
-- Owner's go-ahead (Step 2), their message of 2026-10-21: "Feel free to delete data that appears private and write in
-- new example data for future users to see." Test Community has 19 real active members; nothing here notifies them.
--
-- WHAT IT WRITES (everything inside one transaction)
--   Part A (read only): resolves NC Test Owner (exactly one profile with that name, id starting eebf5514) and the five
--     communities by name and id prefix (Test Community 7a8ed131-cb05-462b-a491-b433d70a3fe5: default, listed,
--     approve, not archived; Test Public A 86916d6c and Test Public B b546bf31: listed, approve; Test Private A
--     9dac5e11 and Test Private B e84d026f: hidden, invite; all four owned by NC Test Owner, none archived); checks
--     that Test Community has no is_example ride, favor or post yet, that NC Test Owner has no Test Community row that
--     is not active, and that every column this script writes exists. Any mismatch raises and nothing is written.
--   Part B: service areas (Test Community 'Seattle' 47.6062, -122.3321, 10 miles; Test Public A 'Capitol Hill,
--     Seattle' 47.6253, -122.3222, 1 mile; Test Public B 'Bellevue' 47.6101, -122.2015, 2 miles) and is_test = true on
--     the four test communities. Test Community stays is_test = false. One update per row, by resolved id. No
--     community_listing_events row is written (those record owner actions through the RPCs; this is setup in SQL).
--   Part C: NC Test Owner becomes an active member of Test Community (role member) when it has no active row there:
--     naars.suppress_approval_notice = '1' around the insert (as create_community does), then one membership event
--     'approved' (new_role member, actor null, reason 'example content account').
--   Part D: example content in Test Community, all is_example = true, posted by NC Test Owner. Requests: timezone
--     America/Los_Angeles, status open, date = today in Los Angeles + the day below:
--       1 ride   +2 10:00 Ballard Branch Library -> Pike Place Market, 1 seat, notes
--       2 ride   +3 06:30 Westlake Station -> Seattle-Tacoma International Airport, 1 seat, notes
--       3 ride   +5 18:30 Capitol Hill Station -> Seattle Center, 2 seats, notes
--       4 ride   +6 09:00 Green Lake Park -> University of Washington Station, 1 seat, gift
--       5 favor  +1 (no time) apples, Ballard Farmers Market, under_hour, description
--       6 favor  +4 14:00 library books, Seattle Central Library, under_hour, description
--       7 favor  +5 (no time) folding chairs, Gas Works Park, couple_hours, description
--       8 favor  +7 11:00 plant sale, Volunteer Park, couple_hours, gift
--     Posts: a pinned announcement "Welcome to Test Community"; two user posts (type user_post, title = content, as
--     the app titles a post with its first line).
--     The notifiers and the XP trigger return early for an example row (20261021_0023 Blocks 1-3), so no trigger is
--     disabled and nobody is told. The daily refresh_example_requests() job keeps the requests in the coming week.
--   Part E (read only, raises on any mismatch): 8 example requests (4 rides, 4 favors, all open) and 3 example posts in
--     Test Community; 0 notifications rows and 0 notification_queue rows created in this transaction (created_at =
--     now(), the transaction's start time); 0 xp_events for the new ids or created in this transaction; the areas
--     and flags read back; NC Test Owner active in Test Community with one 'approved' event; the notify and XP
--     triggers on rides, favors, town_hall_posts, town_hall_comments and request_qa enabled ('O'). Then it prints one
--     outcome row and the transaction commits.
--
-- WHAT A MEMBER ON THE INSTALLED CLIENT SEES. The example rows appear without an "Example" chip (the pre-Release 2
-- client does not decode is_example), and a claim attempt fails with the generic claim error (guard_example_content
-- refuses it) until the Release 2 client ships. Test Community's description already says nothing in it is real.
--
-- ROLLBACK (owner's SQL-editor steps; the MCP declines DELETE, so they are not rephrased here):
--   delete from public.town_hall_posts where community_id = '7a8ed131-cb05-462b-a491-b433d70a3fe5' and is_example;
--   delete from public.rides  where community_id = '7a8ed131-cb05-462b-a491-b433d70a3fe5' and is_example;
--   delete from public.favors where community_id = '7a8ed131-cb05-462b-a491-b433d70a3fe5' and is_example;
--   (or hide them instead, through the app's moderation or set_example_content; see Docs/qa/test-data.md)
--   NC Test Owner's Test Community membership: leave through the app (writes the 'left' event), not a DELETE.
--   Areas and flags (plain updates, MCP or SQL editor):
--   update public.communities set area_name = null, area_center_lat = null, area_center_lng = null,
--     area_radius_miles = null where id in (<Test Community>, <Test Public A>, <Test Public B>);
--   update public.communities set is_test = false where id in (<the four test communities>);
--   (the full ids of the four test communities are in the owner's local file, see Docs/qa/test-data.md)

begin;

-- =============================================================================================================
-- Parts A-D
-- =============================================================================================================
do $s5a$
declare
  v_tc   constant uuid := '7a8ed131-cb05-462b-a491-b433d70a3fe5';
  v_owner uuid;
  v_pub_a uuid;
  v_pub_b uuid;
  v_priv_a uuid;
  v_priv_b uuid;
  v_n integer;
  v_day date;
  r record;
begin
  -- ---------------------------------------------------------------------------------------------------------
  -- Part A (read only)
  -- ---------------------------------------------------------------------------------------------------------
  select count(*) into v_n from public.profiles where name = 'NC Test Owner';
  if v_n <> 1 then
    raise exception 'S5a stop: expected exactly one profile named NC Test Owner, found %', v_n;
  end if;
  select id into v_owner from public.profiles where name = 'NC Test Owner';
  if left(v_owner::text, 8) <> 'eebf5514' then
    raise exception 'S5a stop: NC Test Owner id does not start with eebf5514';
  end if;

  select count(*) into v_n from public.communities c
   where c.id = v_tc and c.name = 'Test Community' and c.is_default and c.is_public
     and c.join_policy = 'approve' and c.archived_at is null and not c.is_test;
  if v_n <> 1 then
    raise exception 'S5a stop: Test Community is not the default, listed, approve, unarchived, untested row expected';
  end if;

  for r in
    select * from (values
      ('Test Public A',  '86916d6c', true,  'approve'),
      ('Test Public B',  'b546bf31', true,  'approve'),
      ('Test Private A', '9dac5e11', false, 'invite'),
      ('Test Private B', 'e84d026f', false, 'invite')) as t(name, prefix, listed, policy)
  loop
    select count(*) into v_n from public.communities c where c.name = r.name;
    if v_n <> 1 then
      raise exception 'S5a stop: expected exactly one community named %, found %', r.name, v_n;
    end if;
    select count(*) into v_n
      from public.communities c
      join public.community_members m on m.community_id = c.id and m.user_id = v_owner
                                     and m.role = 'owner' and m.status = 'active'
     where c.name = r.name and left(c.id::text, 8) = r.prefix and c.is_public = r.listed
       and c.join_policy = r.policy and c.archived_at is null;
    if v_n <> 1 then
      raise exception 'S5a stop: % does not match its prefix, type or owner', r.name;
    end if;
  end loop;
  select id into v_pub_a  from public.communities where name = 'Test Public A';
  select id into v_pub_b  from public.communities where name = 'Test Public B';
  select id into v_priv_a from public.communities where name = 'Test Private A';
  select id into v_priv_b from public.communities where name = 'Test Private B';

  select (select count(*) from public.rides where community_id = v_tc and is_example)
       + (select count(*) from public.favors where community_id = v_tc and is_example)
       + (select count(*) from public.town_hall_posts where community_id = v_tc and is_example)
    into v_n;
  if v_n <> 0 then
    raise exception 'S5a stop: Test Community already has % example rows', v_n;
  end if;

  if exists (select 1 from public.community_members
              where community_id = v_tc and user_id = v_owner and status <> 'active') then
    raise exception 'S5a stop: NC Test Owner has a Test Community row that is not active';
  end if;

  select count(*) into v_n
    from information_schema.columns
   where table_schema = 'public'
     and (table_name, column_name) in (
       ('communities', 'area_name'), ('communities', 'area_center_lat'), ('communities', 'area_center_lng'),
       ('communities', 'area_radius_miles'), ('communities', 'is_test'),
       ('community_members', 'activated_at'),
       ('community_membership_events', 'new_role'), ('community_membership_events', 'reason'),
       ('rides', 'is_example'), ('rides', 'timezone'), ('rides', 'community_id'), ('rides', 'pickup'),
       ('rides', 'destination'), ('rides', 'seats'), ('rides', 'notes'), ('rides', 'gift'),
       ('favors', 'is_example'), ('favors', 'timezone'), ('favors', 'community_id'), ('favors', 'title'),
       ('favors', 'location'), ('favors', 'duration'), ('favors', 'description'), ('favors', 'gift'),
       ('town_hall_posts', 'is_example'), ('town_hall_posts', 'community_id'), ('town_hall_posts', 'pinned'),
       ('town_hall_posts', 'type'), ('town_hall_posts', 'title'), ('town_hall_posts', 'content'));
  if v_n <> 30 then
    raise exception 'S5a stop: expected 30 columns, found %', v_n;
  end if;

  -- ---------------------------------------------------------------------------------------------------------
  -- Part B: areas and test flags
  -- ---------------------------------------------------------------------------------------------------------
  update public.communities
     set area_name = 'Seattle', area_center_lat = 47.6062, area_center_lng = -122.3321, area_radius_miles = 10
   where id = v_tc;
  get diagnostics v_n = row_count;
  if v_n <> 1 then raise exception 'S5a stop: Test Community area update wrote % rows', v_n; end if;

  update public.communities
     set area_name = 'Capitol Hill, Seattle', area_center_lat = 47.6253, area_center_lng = -122.3222,
         area_radius_miles = 1
   where id = v_pub_a;
  get diagnostics v_n = row_count;
  if v_n <> 1 then raise exception 'S5a stop: Test Public A area update wrote % rows', v_n; end if;

  update public.communities
     set area_name = 'Bellevue', area_center_lat = 47.6101, area_center_lng = -122.2015, area_radius_miles = 2
   where id = v_pub_b;
  get diagnostics v_n = row_count;
  if v_n <> 1 then raise exception 'S5a stop: Test Public B area update wrote % rows', v_n; end if;

  update public.communities set is_test = true where id in (v_pub_a, v_pub_b, v_priv_a, v_priv_b);
  get diagnostics v_n = row_count;
  if v_n <> 4 then raise exception 'S5a stop: is_test update wrote % rows', v_n; end if;

  -- ---------------------------------------------------------------------------------------------------------
  -- Part C: NC Test Owner active in Test Community
  -- ---------------------------------------------------------------------------------------------------------
  if not exists (select 1 from public.community_members
                  where community_id = v_tc and user_id = v_owner and status = 'active') then
    perform set_config('naars.suppress_approval_notice', '1', true);
    insert into public.community_members (community_id, user_id, role, status, activated_at)
    values (v_tc, v_owner, 'member', 'active', now());
    perform set_config('naars.suppress_approval_notice', '', true);

    insert into public.community_membership_events (community_id, user_id, actor_id, event, new_role, reason)
    values (v_tc, v_owner, null, 'approved', 'member', 'example content account');
  end if;

  -- ---------------------------------------------------------------------------------------------------------
  -- Part D: example requests and posts
  -- ---------------------------------------------------------------------------------------------------------
  v_day := (now() at time zone 'America/Los_Angeles')::date;

  insert into public.rides (user_id, community_id, is_example, timezone, status, date, time, pickup, destination,
                            seats, notes, gift)
  values
    (v_owner, v_tc, true, 'America/Los_Angeles', 'open', v_day + 2, '10:00', 'Ballard Branch Library',
     'Pike Place Market', 1, 'Meeting a friend for lunch. Happy to chip in for parking.', null),
    (v_owner, v_tc, true, 'America/Los_Angeles', 'open', v_day + 3, '06:30', 'Westlake Station',
     'Seattle-Tacoma International Airport', 1, 'Early flight, one carry-on.', null),
    (v_owner, v_tc, true, 'America/Los_Angeles', 'open', v_day + 5, '18:30', 'Capitol Hill Station',
     'Seattle Center', 2, 'Two of us going to a show.', null),
    (v_owner, v_tc, true, 'America/Los_Angeles', 'open', v_day + 6, '09:00', 'Green Lake Park',
     'University of Washington Station', 1, null, 'Coffee on me');

  insert into public.favors (user_id, community_id, is_example, timezone, status, date, time, title, location,
                             duration, description, gift)
  values
    (v_owner, v_tc, true, 'America/Los_Angeles', 'open', v_day + 1, null,
     'Pick up a box of apples at the farmers market', 'Ballard Farmers Market', 'under_hour',
     'Any stall with Honeycrisp apples is fine.', null),
    (v_owner, v_tc, true, 'America/Los_Angeles', 'open', v_day + 4, '14:00',
     'Return two library books', 'Seattle Central Library', 'under_hour',
     'They''re due Friday.', null),
    (v_owner, v_tc, true, 'America/Los_Angeles', 'open', v_day + 5, null,
     'Help carry folding chairs for a picnic', 'Gas Works Park', 'couple_hours',
     'About twenty chairs from the parking lot to the lawn.', null),
    (v_owner, v_tc, true, 'America/Los_Angeles', 'open', v_day + 7, '11:00',
     'Walk with me to the plant sale', 'Volunteer Park', 'couple_hours',
     null, 'A tomato start for your garden');

  insert into public.town_hall_posts (user_id, community_id, is_example, title, content, pinned, type)
  values
    (v_owner, v_tc, true, 'Welcome to Test Community',
     'This is the example community for exploring Naar''s Cars. The rides, favors and posts here are examples: '
       || 'open them to see how a request, its questions and its answers look. Real neighborhoods have their own '
       || 'communities; search for yours in Explore.',
     true, 'announcement'),
    (v_owner, v_tc, true, 'Is the Ballard Farmers Market open on holidays?',
     'Is the Ballard Farmers Market open on holidays?', false, 'user_post'),
    (v_owner, v_tc, true, 'Thank you to whoever helped carry the chairs at Gas Works Park last weekend!',
     'Thank you to whoever helped carry the chairs at Gas Works Park last weekend!', false, 'user_post');
end
$s5a$;

-- =============================================================================================================
-- Part E (read only; raises on any mismatch)
-- =============================================================================================================
do $s5a_check$
declare
  v_tc constant uuid := '7a8ed131-cb05-462b-a491-b433d70a3fe5';
  v_owner uuid;
  v_rides integer;
  v_favors integer;
  v_posts integer;
  v_n integer;
begin
  select id into v_owner from public.profiles where name = 'NC Test Owner';

  select count(*) into v_rides from public.rides
   where community_id = v_tc and is_example and status = 'open' and user_id = v_owner and claimed_by is null;
  select count(*) into v_favors from public.favors
   where community_id = v_tc and is_example and status = 'open' and user_id = v_owner and claimed_by is null;
  select count(*) into v_posts from public.town_hall_posts
   where community_id = v_tc and is_example and user_id = v_owner and hidden_at is null;
  if v_rides <> 4 or v_favors <> 4 or v_posts <> 3 then
    raise exception 'S5a check: expected 4 rides, 4 favors, 3 posts; found %, %, %', v_rides, v_favors, v_posts;
  end if;
  select count(*) into v_n from public.town_hall_posts
   where community_id = v_tc and is_example and pinned and type = 'announcement';
  if v_n <> 1 then raise exception 'S5a check: expected one pinned example announcement, found %', v_n; end if;

  select count(*) into v_n from public.notifications where created_at = now();
  if v_n <> 0 then raise exception 'S5a check: % notifications created in this transaction', v_n; end if;
  select count(*) into v_n from public.notification_queue where created_at = now();
  if v_n <> 0 then raise exception 'S5a check: % pushes queued in this transaction', v_n; end if;
  select count(*) into v_n from public.xp_events x
   where x.created_at = now()
      or x.source_id in (select id from public.rides where community_id = v_tc and is_example
                         union all select id from public.favors where community_id = v_tc and is_example
                         union all select id from public.town_hall_posts where community_id = v_tc and is_example);
  if v_n <> 0 then raise exception 'S5a check: % xp_events for the new rows', v_n; end if;

  select count(*) into v_n from public.communities c
   where (c.id = v_tc and c.area_name = 'Seattle' and c.area_center_lat = 47.6062
          and c.area_center_lng = -122.3321 and c.area_radius_miles = 10 and not c.is_test)
      or (c.name = 'Test Public A' and c.area_name = 'Capitol Hill, Seattle' and c.area_center_lat = 47.6253
          and c.area_center_lng = -122.3222 and c.area_radius_miles = 1 and c.is_test)
      or (c.name = 'Test Public B' and c.area_name = 'Bellevue' and c.area_center_lat = 47.6101
          and c.area_center_lng = -122.2015 and c.area_radius_miles = 2 and c.is_test)
      or (c.name in ('Test Private A', 'Test Private B') and c.area_name is null and c.is_test);
  if v_n <> 5 then raise exception 'S5a check: areas and flags read back on % of 5 communities', v_n; end if;
  select count(*) into v_n from public.communities where is_test;
  if v_n <> 4 then raise exception 'S5a check: % communities are is_test, expected 4', v_n; end if;

  select count(*) into v_n from public.community_members
   where community_id = v_tc and user_id = v_owner and status = 'active' and role = 'member';
  if v_n <> 1 then raise exception 'S5a check: NC Test Owner is not an active member of Test Community'; end if;
  select count(*) into v_n from public.community_membership_events
   where community_id = v_tc and user_id = v_owner and event = 'approved' and reason = 'example content account';
  if v_n <> 1 then raise exception 'S5a check: expected one approved event, found %', v_n; end if;

  select count(*) into v_n from pg_trigger
   where not tgisinternal and tgenabled = 'O'
     and (tgrelid, tgname) in (
       ('public.rides'::regclass, 'on_ride_created_notify'), ('public.rides'::regclass, 'trg_rides_xp_on_create'),
       ('public.favors'::regclass, 'on_favor_created_notify'), ('public.favors'::regclass, 'trg_favors_xp_on_create'),
       ('public.town_hall_posts'::regclass, 'on_town_hall_post_notify'),
       ('public.town_hall_comments'::regclass, 'on_town_hall_comment_notify'),
       ('public.request_qa'::regclass, 'on_qa_created_notify'));
  if v_n <> 7 then raise exception 'S5a check: % of 7 notify and XP triggers enabled', v_n; end if;
end
$s5a_check$;

select jsonb_build_object(
  'example_requests', (select count(*) from public.rides where community_id = '7a8ed131-cb05-462b-a491-b433d70a3fe5' and is_example)
                    + (select count(*) from public.favors where community_id = '7a8ed131-cb05-462b-a491-b433d70a3fe5' and is_example),
  'example_posts', (select count(*) from public.town_hall_posts where community_id = '7a8ed131-cb05-462b-a491-b433d70a3fe5' and is_example),
  'notifications_created', (select count(*) from public.notifications where created_at = now()),
  'pushes_queued', (select count(*) from public.notification_queue where created_at = now()),
  'xp_events_created', (select count(*) from public.xp_events where created_at = now()),
  'test_communities', (select count(*) from public.communities where is_test),
  'triggers_enabled', (select count(*) from pg_trigger where not tgisinternal and tgenabled = 'O'
                        and tgname in ('on_ride_created_notify', 'on_favor_created_notify', 'on_town_hall_post_notify',
                                       'on_town_hall_comment_notify', 'on_qa_created_notify',
                                       'trg_rides_xp_on_create', 'trg_favors_xp_on_create')),
  'outcome', 'S5a OK') as s5a;

commit;
