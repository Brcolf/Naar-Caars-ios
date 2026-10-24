-- 20261021_0001_community_preview.sql
--
-- APPLIED 2026-10-21, all four blocks, through the Supabase MCP apply_migration, one call per block, in order, each
-- block's text sent byte for byte from this file, after a rolled-back dry run (migration-history versions are UTC:
-- 20261022004045 20261021_0001_block_1, 20261022004149 20261021_0001_block_2, 20261022004225 20261021_0001_block_3,
-- 20261022004308 20261021_0001_block_4). Deployed md5(prosrc): my_visible_profile_ids() d313d5213ce5e5790357dfec161d4087
-- (was 534c017b224ddef0399887151b4e99ad), is_listed_request(uuid, uuid) dd27ebff7dbe18618e7b57a96cfacfb4,
-- get_community_preview(uuid) 6cf9b87e5ed8cb8214f1e1f4b8a5035c; each equals the md5 of the text between this file's
-- $function$ delimiters. All three are SECURITY DEFINER, stable, search_path="", EXECUTE for anon, authenticated and
-- service_role, none for PUBLIC. Policy "Approved users can view reviews": md5(qual) 07c042cd0afb86dbbeb7e8cc470e762d
-- (was 7e238f6c96644e2333fc64d4e21e2da1), still TO public, SELECT, permissive.
-- Release 1 of community discovery and trust (Docs/superpowers/specs/2026-10-21-community-discovery-and-trust-design.md;
-- plan Docs/superpowers/plans/2026-10-21-community-release1-navigation.md, Task 1): the community page a visitor opens
-- from Explore, and the people on it.
--
-- What it does.
--   * Block 1, my_visible_profile_ids() (changed): one more arm, the active members of listed communities (public and
--     not archived). A signed-in visitor therefore reads those people in public_profiles, get_profile_stats,
--     get_user_badges, get_user_stats and is_user_approved exactly as a guest already does (each of the five already
--     answers anon for an active member of a public community). No other function, view or policy calls it
--     (pg_proc, pg_policies and the view definitions read on 2026-10-21). Members of private communities stay
--     visible only to their co-members, thread co-participants and review partners, as before.
--   * Block 2, is_listed_request(p_ride_id, p_favor_id) -> boolean (new): true when the ride, or the favor, is not
--     hidden and belongs to a listed community. SECURITY DEFINER so the reviews policy can ask it without the
--     caller's read access to the request. EXECUTE for anon too: the policy in Block 3 is TO public, and Postgres
--     checks EXECUTE when it plans the query even where the approved test is false.
--   * Block 3, policy "Approved users can view reviews" on public.reviews (changed): the [A23] expression of
--     20261017_0002 with one more arm inside its parenthesised or-list, public.is_listed_request(ride_id, favor_id).
--     An approved signed-in visitor reads the reviews of visible requests in listed communities, as a guest does
--     through reviews_select_anon_guest. The arm sits inside [A23]'s approved gate, so an account with no active
--     membership (approved false) does not read them; Release 2 widens that gate for its search-first visitors.
--   * Block 4, get_community_preview(p_community_id) -> jsonb (new): what a visitor sees of a listed community.
--     Refused with {"success": false, "error": "Community not found", "code": "not_listed"} for a null id, an unknown
--     id, a private community and an archived one (a member of a private community is refused too; members read
--     their membership row). Otherwise {"success": true, "community": {id, name, description, join_policy,
--     is_public, is_default, member_count (active members), timezone}, "requests": at most 10 open, unclaimed,
--     visible rides and favors dated today or later in the request's time zone, poster not banned and, for a
--     signed-in caller, not blocked in either direction, ordered by date, time (nulls last), id: [{type ("ride" |
--     "favor"), id, title (favors; null for a ride), date (yyyy-mm-dd), time (hh:mm:ss text or null), timezone,
--     seats (rides; null for a favor), poster_id, poster_name, poster_avatar_url}], "posts": the 5 newest visible
--     Town Hall posts, same author rules: [{id, type, title, content (first 280 characters), created_at, author_id,
--     author_name, author_avatar_url, comment_count (visible comments)}]}. No pickup, destination, location, notes,
--     description, gift, flight or cost is returned. Keys may be added later (Release 3 adds area keys); none is
--     removed or renamed. EXECUTE for anon, authenticated and service_role.
--
-- What old clients see. Nothing. The installed build and Phase 1-5a builds call neither new function; the two
-- widenings (Block 1 and Block 3) answer reads that such a build only makes for people and requests it already
-- shows, and add rows only for screens it cannot reach (another community's people and reviews). One consequence:
-- the review-images objects of such reviews become readable to signed-in visitors through 20261019_0063's
-- review_images_read_visible policy (which defers to whoever can read the review), as they already are to guests.
--
-- Apply. Supabase MCP apply_migration, one block per call, in order, named 20261021_0001_block_<n>. Nothing here is
-- declined (no DELETE, no DROP).
-- Verification. Dry run: blocks 1-4 in one begin; ... rollback; with the probe PARAMETERS, the HELPERS without their
-- commit;, and the probe blocks community_preview, listed_profiles, reputation, isolation, noop_default and short with
-- begin;/rollback; turned into savepoints. Then short after each block, and community_preview, listed_profiles,
-- reputation, isolation, noop_default and short at the end.
-- Outcomes, 2026-10-21. Preconditions read just before the dry run: P1 md5(prosrc) of my_visible_profile_ids() was
-- 534c017b224ddef0399887151b4e99ad; P2 the live qual of "Approved users can view reviews" equalled [A23] applied in a
-- rolled-back transaction (both md5(qual) 7e238f6c96644e2333fc64d4e21e2da1); P3 neither new name existed; P4 no file
-- and no migration-history entry used 20261021_0001. The only callers of my_visible_profile_ids() were the five named
-- above (pg_proc, pg_policies and view definitions). Dry run (one rolled-back execute_sql: begin; blocks 1-4,
-- PARAMETERS, HELPERS without their commit;, the six probe blocks as savepoints, select 'DRYRUN 20261021_0001 OK',
-- rollback;): DRYRUN 20261021_0001 OK, and afterwards neither new function existed and my_visible_profile_ids() and the
-- policy were unchanged. A rolled-back run with only a stub get_community_preview (Blocks 1-3 absent) failed as it
-- should: "PROBE listed_profiles FAILED: u3 reads u12 (public C2 only) in public_profiles". Apply: short after block 1,
-- block 2, block 3 and block 4: OK. After block 4: community_preview, listed_profiles, reputation (its Release 1 branch),
-- isolation and noop_default: OK (the short after block 4 stands for the last run; nothing changed in between). Each
-- probe ran in its own begin; ... rollback; with PARAMETERS and the helpers it calls recreated in the same call; no probe
-- account, community, request, post or block was left behind. Live listed communities answer success with the eight
-- community keys; a rolled-back sample showed the ten request keys and nine post keys above, dates as yyyy-mm-dd, times
-- as hh:mm:ss or null, seats null for a favor and content cut to 280 characters.
--
-- Rollback (per block, in reverse order).
--   Block 4 and Block 2: drop function public.get_community_preview(uuid); drop function
--     public.is_listed_request(uuid, uuid); (SQL editor, owner: the MCP declines DROP FUNCTION; Block 3's rollback
--     must run first, because the policy calls is_listed_request).
--   Block 3 (MCP): alter policy "Approved users can view reviews" on public.reviews using (<[A23]>), where <[A23]> is
--     the expression of 20261017_0002_communities_rls.sql [A23] (this file's Block 3 without its last or-arm). The
--     deparsed pg_policies.qual it restores, read live before this file and equal to [A23] applied in a rolled-back
--     transaction (md5(qual) 7e238f6c96644e2333fc64d4e21e2da1), one deparsed line per "--   | " line:
--   | (COALESCE(( SELECT p.approved
--   |    FROM profiles p
--   |   WHERE (p.id = ( SELECT auth.uid() AS uid))), false) AND ((reviewer_id = ( SELECT auth.uid() AS uid)) OR (fulfiller_id = ( SELECT auth.uid() AS uid)) OR (EXISTS ( SELECT 1
--   |    FROM rides r
--   |   WHERE (r.id = reviews.ride_id))) OR (EXISTS ( SELECT 1
--   |    FROM favors f
--   |   WHERE (f.id = reviews.favor_id)))))
--   Block 1 (MCP): the body of 20261017_0001_communities_core.sql [call] 1c.8 (md5(prosrc)
--     534c017b224ddef0399887151b4e99ad, read on 2026-10-21 before this file).


-- ============================================================================================
-- BLOCK 1: public.my_visible_profile_ids()   (changed: the active members of listed communities)
-- The 20261017_0001 [call] 1c.8 body with one more arm before ") s where u is not null". Grants unchanged
-- (create or replace keeps them: anon, authenticated, service_role).
-- ============================================================================================
create or replace function public.my_visible_profile_ids()
returns uuid[]
language sql
stable
security definer
set search_path = ''
as $function$
  select coalesce(array_agg(distinct u), '{}'::uuid[]) from (
    select (select auth.uid()) as u
    union all select m.user_id from public.community_members m
               where m.status = 'active' and m.community_id = any ((select public.my_community_ids())::uuid[])
    union all select b.user_id from public.conversation_participants a
                join public.conversation_participants b on b.conversation_id = a.conversation_id
               where a.user_id = (select auth.uid()) and a.left_at is null
    union all select r.reviewer_id  from public.reviews r where r.fulfiller_id = (select auth.uid())
    union all select r.fulfiller_id from public.reviews r where r.reviewer_id  = (select auth.uid())
    union all select m.user_id from public.community_members m
                join public.communities c on c.id = m.community_id
               where m.status = 'active' and c.is_public and c.archived_at is null
  ) s where u is not null;
$function$;


-- ============================================================================================
-- BLOCK 2: public.is_listed_request(uuid, uuid)   (new)
-- ============================================================================================
create or replace function public.is_listed_request(p_ride_id uuid, p_favor_id uuid)
returns boolean
language sql
stable
security definer
set search_path = ''
as $function$
  select exists (select 1 from public.rides r
                   join public.communities c on c.id = r.community_id
                  where r.id = p_ride_id and r.hidden_at is null and c.is_public and c.archived_at is null)
      or exists (select 1 from public.favors f
                   join public.communities c on c.id = f.community_id
                  where f.id = p_favor_id and f.hidden_at is null and c.is_public and c.archived_at is null);
$function$;

revoke all on function public.is_listed_request(uuid, uuid) from public;
grant execute on function public.is_listed_request(uuid, uuid) to anon, authenticated, service_role;


-- ============================================================================================
-- BLOCK 3: public.reviews / "Approved users can view reviews"   (changed: [A23] plus the listed-request arm)
-- ============================================================================================
alter policy "Approved users can view reviews" on public.reviews
  using (
    coalesce((select p.approved from public.profiles p where p.id = (select auth.uid())), false)
    and (
      reviewer_id = (select auth.uid())
      or fulfiller_id = (select auth.uid())
      or exists (select 1 from public.rides r where r.id = reviews.ride_id)
      or exists (select 1 from public.favors f where f.id = reviews.favor_id)
      or public.is_listed_request(reviews.ride_id, reviews.favor_id)
    )
  );


-- ============================================================================================
-- BLOCK 4: public.get_community_preview(uuid)   (new)
-- ============================================================================================
create or replace function public.get_community_preview(p_community_id uuid)
returns jsonb
language plpgsql
stable
security definer
set search_path = ''
as $function$
declare
  v_uid uuid := (select auth.uid());
  v_c public.communities%rowtype;
  v_member_count bigint;
  v_requests jsonb;
  v_posts jsonb;
begin
  if p_community_id is not null then
    select c.* into v_c
      from public.communities c
     where c.id = p_community_id and c.is_public and c.archived_at is null;
  end if;
  if v_c.id is null then
    return jsonb_build_object('success', false, 'error', 'Community not found', 'code', 'not_listed');
  end if;

  select count(*) into v_member_count
    from public.community_members m
   where m.community_id = v_c.id and m.status = 'active';

  select coalesce(jsonb_agg(jsonb_build_object(
           'type', q.kind,
           'id', q.id,
           'title', q.title,
           'date', to_char(q.date, 'YYYY-MM-DD'),
           'time', q."time"::text,
           'timezone', q.timezone,
           'seats', q.seats,
           'poster_id', q.poster_id,
           'poster_name', q.poster_name,
           'poster_avatar_url', q.poster_avatar_url)
         order by q.date, q."time" nulls last, q.id), '[]'::jsonb)
    into v_requests
    from (
      select x.kind, x.id, x.title, x.date, x."time", x.timezone, x.seats, x.poster_id,
             p.name as poster_name, p.avatar_url as poster_avatar_url
        from (
          select 'ride'::text as kind, r.id, null::text as title, r.date, r."time", r.timezone, r.seats,
                 r.user_id as poster_id
            from public.rides r
           where r.community_id = v_c.id and r.status = 'open' and r.claimed_by is null and r.hidden_at is null
             and r.date >= (now() at time zone coalesce(r.timezone, v_c.timezone))::date
          union all
          select 'favor'::text, f.id, f.title, f.date, f."time", f.timezone, null::integer,
                 f.user_id
            from public.favors f
           where f.community_id = v_c.id and f.status = 'open' and f.claimed_by is null and f.hidden_at is null
             and f.date >= (now() at time zone coalesce(f.timezone, v_c.timezone))::date
        ) x
        join public.profiles p on p.id = x.poster_id
       where not coalesce(p.is_banned, false)
         and (v_uid is null or not exists (
               select 1 from public.blocked_users b
                where (b.blocker_id = v_uid and b.blocked_id = x.poster_id)
                   or (b.blocker_id = x.poster_id and b.blocked_id = v_uid)))
       order by x.date, x."time" nulls last, x.id
       limit 10
    ) q;

  select coalesce(jsonb_agg(jsonb_build_object(
           'id', q.id,
           'type', q.type,
           'title', q.title,
           'content', q.content,
           'created_at', q.created_at,
           'author_id', q.author_id,
           'author_name', q.author_name,
           'author_avatar_url', q.author_avatar_url,
           'comment_count', q.comment_count)
         order by q.created_at desc, q.id desc), '[]'::jsonb)
    into v_posts
    from (
      select t.id, t.type, t.title, left(t.content, 280) as content, t.created_at, t.user_id as author_id,
             p.name as author_name, p.avatar_url as author_avatar_url,
             (select count(*) from public.town_hall_comments k
               where k.post_id = t.id and k.hidden_at is null) as comment_count
        from public.town_hall_posts t
        join public.profiles p on p.id = t.user_id
       where t.community_id = v_c.id and t.hidden_at is null
         and not coalesce(p.is_banned, false)
         and (v_uid is null or not exists (
               select 1 from public.blocked_users b
                where (b.blocker_id = v_uid and b.blocked_id = t.user_id)
                   or (b.blocker_id = t.user_id and b.blocked_id = v_uid)))
       order by t.created_at desc, t.id desc
       limit 5
    ) q;

  return jsonb_build_object(
    'success', true,
    'community', jsonb_build_object(
      'id', v_c.id,
      'name', v_c.name,
      'description', v_c.description,
      'join_policy', v_c.join_policy,
      'is_public', v_c.is_public,
      'is_default', v_c.is_default,
      'member_count', v_member_count,
      'timezone', v_c.timezone),
    'requests', v_requests,
    'posts', v_posts);
end
$function$;

revoke all on function public.get_community_preview(uuid) from public;
grant execute on function public.get_community_preview(uuid) to anon, authenticated, service_role;
