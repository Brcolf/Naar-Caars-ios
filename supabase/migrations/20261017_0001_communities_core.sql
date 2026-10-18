-- 20261017_0001_communities_core.sql
-- APPLIED 2026-10-18 (Supabase MCP apply_migration, the whole file in one call; migration-history
-- version 20261018135301). Phase 0, step 1 of the multi-community build
-- (Docs/superpowers/specs/2026-10-07-multi-community-design.md §3.1-3.3 and §4 step 1, as amended by
-- Docs/superpowers/specs/2026-10-17-multi-community-decisions.md, which wins where they differ).
--
-- What this file does
--   Adds communities and memberships, puts every existing member into one default community
--   ("Naar's Cars Seattle", owned by the project owner's account, whose profile id the owner confirms
--   and which is written into [call] 1b.1 as a literal (D1); the platform admins are its admins), and
--   installs the server-side machinery that keeps the old flags working:
--     * tables: communities, community_invites, community_members, community_invite_redemptions,
--       community_invite_attempts, community_membership_events (append-only), community_limit_requests
--       (decision A1); nullable community_id on rides, favors, town_hall_posts, xp_events, notifications,
--       reports; reports.reported_community_id (decision A2); profiles.primary_community_id and
--       profiles.max_owned_communities (A1, default 3, server-owned). There is NO owner_vacant_since
--       column and no 'owner_vacated' / 'ownership_claimed' event (decision A3: no ownerless state).
--     * the caller-bound RLS helpers (my_community_ids, my_admin_community_ids, is_active_member,
--       is_community_admin, is_platform_admin, community_has_member, shares_community_with,
--       my_visible_profile_ids, default_community_id) and two service-role-only lookups;
--     * the mirror: profiles.approved / application_complete / primary_community_id are recomputed from
--       memberships (recompute_profile_membership_flags), with a transaction-local escape that
--       protect_admin_fields honours;
--     * the two legacy bridges: the installed build's application submit becomes a pending membership of
--       the default community, and its admin approve activates it;
--     * fill triggers so a row the installed build inserts without community_id gets one, the claim
--       membership guard, the community_members client-update guard, and the new applicant producer
--       notify_pending_membership (notify_pending_user becomes a no-op in the adjacent call).
--   It sets no NOT NULL on any community_id (step 6) and does not create guard_last_owner (step 4, SQL
--   editor, together with the new delete_user_account). guard_request_client_update gaining community_id
--   in its immutable set is step 3 (§4); with one community nothing can be misrouted before then.
--
-- How to apply (§4 step 1; decisions §2)
--   Step 0 comes first: 20261017_0000a_revoke_get_or_create_conversation.sql (its only forward change);
--   20261017_0000 is the rollback artefact and is not applied. Before anything in this file, the owner
--   confirms their profiles.id and it replaces the placeholder in [call] 1b.1 (and in its verbatim re-run,
--   1d.8); the placeholder makes both fail until then.
--   Dry-run the whole file once inside begin; ... rollback; together with the short probe. Then apply the
--   sub-steps 1a to 1h IN ORDER, one MCP call per "-- [call]" block (one CREATE OR REPLACE FUNCTION per
--   call), running the short probe after each sub-step. Stop at the first failed probe. No statement here
--   deletes from auth.* or storage.*, drops a policy, or issues a bare DELETE, so every call can go
--   through the MCP. After every single call the installed build's inserts, claims, completions,
--   reviews, approvals and account deletion still work: until 1e the new columns are simply null, and
--   from 1e on the fill triggers supply them. Order inside the steps matters twice: protect_admin_fields
--   and protect_admin_fields_on_insert (1a.3, 1a.4) come right after the columns they guard (1a.2), and
--   the bridge triggers (1d.6) come before the mirror triggers (1d.7).
--
-- Verification (2026-10-18)
--   Outcome. The whole file plus the short probe ran first inside one begin; ... rollback; ("DRY RUN
--   0001 + short: OK"). It was then applied as ONE migration rather than one MCP call per [call]
--   block: the dry run had already exercised every block in file order, and a single call leaves no
--   half-applied state if a block fails. After the apply (read-only, and the short probe rolled back):
--     * default community 7a8ed131-cb05-462b-a491-b433d70a3fe5 "Naar's Cars Seattle", public, approve,
--       America/Los_Angeles, created_by 0da568d8-924c-4420-8853-206a48d277b6 (its active owner);
--     * 19 active memberships (1 owner, 3 admin, 15 member), 0 pending; 19 of 19 profiles approved
--       with primary_community_id set; max_owned_communities = 3 everywhere; 0 membership events;
--     * 0 null community_id on rides (106) / favors (61) / town_hall_posts (34) / xp_events;
--       2436 notifications and 13 reports back-filled; max(updated_at) unchanged (rides and favors
--       2026-10-08 03:15:00.290545+00, posts 2026-10-06 09:03:45.754489+00); set_updated_at_rides /
--       _favors / _town_hall_posts enabled ('O');
--     * all 17 triggers present (guard_request_claim_membership on rides and favors); EXECUTE as
--       declared (anon and authenticated on the nine helpers, service_role only on the two lookups,
--       none for clients on recompute_profile_membership_flags);
--     * short probe after the apply: OK (18 active members inside the probe after its deletions).
--   md5(prosrc) of the deployed functions (pg_proc, 2026-10-18):
--     protect_admin_fields 48424e05ea801252b83ed8c893db5f4f
--     protect_admin_fields_on_insert 848e879c6a55d08815f3e576bd035e3b
--     my_community_ids a27ab2bc21f40a177775f3faf34e5512
--     my_admin_community_ids 77adf6e3199d5e6621b3e5c0eea010a3
--     is_active_member fc18ad7c0f3ba677b91c5e3293293dd1
--     is_community_admin 66483bcdc8d3f475ffc9549fb8cbe0ef
--     is_platform_admin 653070bd2a37711a8f72e03e131eaa69
--     community_has_member 9031a18bb80524dae34cf57ef7e675d7
--     shares_community_with 3b7e7feede3ce9bb175b703424d9a068
--     my_visible_profile_ids 534c017b224ddef0399887151b4e99ad
--     default_community_id 4208bb77b7de45ff85c1181ae69ad571
--     community_of_request 5661ed8595a53ac9a58cffa699f435a0
--     community_of_post 9203f60118edecda497b8b329f4db1b6
--     recompute_profile_membership_flags 1916634fb46766a4eab47096d78d9e23
--     maintain_profile_membership_flags 426c4e1bba7bf66b500a3bc388424ab8
--     recompute_flags_on_archive 6331a9e817be0b073bbb962abaa28cdb
--     legacy_application_to_membership 387361399eda45649d08c1332c2df72c
--     sync_legacy_approval_to_membership 523906605a77307bb088f34d820e9093
--     fill_request_community 6241f67fc4e8618ac782b99a7b6d9295
--     fill_xp_event_community d4f8d3aeb4d73e315b18087659cee8fc
--     derive_notification_community 55c06fd052dc3e6f48b259da89719dd8
--     derive_report_community affd44f0a8e3b2b44ff54740c779c14f
--     guard_request_claim_membership 91de54aa5834b4bab62248b939d8bee1
--     guard_community_members_client_update 5f076ca1f1e500b0a9a266e397577ce6
--     prevent_community_membership_events_mutation b0c70eccfffddef502564beb63d4d592
--     should_notify_user a68446277de8720faa48d1d0384f371a
--     notify_pending_membership 92d41ccdd20b33879dc2b5655f9f14b2
--     notify_pending_user 638e55b19c4a77f36c0b0e1d043bbb36
--   The live send-message-push edge function (version 32) already filters conversation_participants
--   on left_at is null in both of its paths, so no deploy was needed.
--   Expected: the consistency assertions at the end of 1d and 1f raise nothing; every approved profile
--   (19) has one active membership of the default community and primary_community_id set to it, and every
--   profile still has max_owned_communities = 3; no rides / favors / town_hall_posts / xp_events row has a
--   null community_id after 1f, and no updated_at on rides / favors / town_hall_posts moved; the short
--   probe (insert a ride and a favor without community_id, claim and complete as a second member, 5-star review,
--   three xp_events rows with a community, delete a probe member / probe admin / the owner's account)
--   passes after each sub-step; a non-admin's direct UPDATE of approved, is_admin, is_banned,
--   primary_community_id or max_owned_communities raises while the mirror's write and a no-JWT
--   maintenance write succeed; an old-client application UPDATE creates one pending default membership
--   and exactly one pending_approval row per default-community owner/admin (after 1h).
--
-- What old clients see
--   Nothing different: same rows, same pushes, same approval and admin screens. Responses carry an extra
--   community_id key, which the decoders ignore. Admins are told about an applicant when the application
--   is submitted rather than at sign-up. Back-fill Part B leaves updated_at alone (the set_updated_at_*
--   triggers are off for its three content updates), so completion dates and streaks do not move and no
--   cache row is rewritten. One accepted one-community change (1g, INV-M6): a banned account that is still
--   approved can no longer claim a ride or favor (the live claim policy allowed it; 0 banned accounts live).
--
-- To undo (the tables and nullable columns can stay)
--   drop the triggers created here (fill_community_*, guard_request_claim_membership,
--   maintain_profile_membership_flags, recompute_flags_on_archive, legacy_application_to_membership,
--   a_sync_legacy_approval_to_membership, derive_*_community, guard_community_members_client_update,
--   notify_pending_membership, community_membership_events_append_only, set_updated_at_communit*);
--   re-apply the step-0 snapshot bodies of protect_admin_fields, protect_admin_fields_on_insert,
--   should_notify_user and notify_pending_user (live md5 before this file: protect_admin_fields
--   57a4ac220177f3bda6c86f3c8a5ca450, protect_admin_fields_on_insert 4e633efc9535982003c39d103c704958,
--   should_notify_user df75c614219979f8fbc56f6b4c32a240, notify_pending_user
--   57634dd2df8f216a25302e2e8c6db0d4); restore report_target_check without reported_community_id.


-- =====================================================================================================
-- >>> STEP 1a: tables, nullable columns, indexes, the report_target_check extension (purely additive),
--     then protect_admin_fields and protect_admin_fields_on_insert, so the two new server-owned profile
--     columns are guarded from the call after the one that adds them.
-- =====================================================================================================

-- [call] 1a.1 tables and indexes
create table if not exists public.communities (
  id                 uuid primary key default gen_random_uuid(),
  name               text not null check (length(btrim(name)) between 2 and 60),
  description        text check (char_length(description) <= 300),
  slug               text unique,                                   -- reserved for the Phase 4 link
  created_by         uuid references public.profiles(id) on delete set null,   -- nullable: deletion must succeed for creators
  is_default         boolean not null default false,                -- exactly one: the legacy community (bridges, old-client fill)
  is_public          boolean not null default false,                -- guest browsing + request-to-join (platform admins only, D7)
  join_policy        text not null default 'approve' check (join_policy in ('invite','approve')),
  members_can_invite boolean not null default true,
  timezone           text not null default 'America/Los_Angeles',
  archived_at        timestamptz,
  archived_by        uuid references public.profiles(id) on delete set null,
  created_at         timestamptz not null default now(),
  updated_at         timestamptz not null default now()
);
create unique index if not exists communities_one_default on public.communities (is_default) where is_default;
create index if not exists communities_public_active on public.communities (is_public) where archived_at is null;

create table if not exists public.community_invites (
  id            uuid primary key default gen_random_uuid(),
  community_id  uuid not null references public.communities(id) on delete cascade,
  -- "NC" + 8 characters from the app's alphabet (Core/Utilities/InviteCodeGenerator.swift):
  -- ABCDEFGHJKMNPQRSTUVWXYZ23456789 (31 symbols: no I, L, O, 0, 1).
  code          text not null unique check (code ~ '^NC[A-HJKMNP-Z2-9]{8}$'),
  created_by    uuid references public.profiles(id) on delete set null,
  max_uses      int check (max_uses is null or max_uses between 1 and 1000),
  use_count     int not null default 0,
  expires_at    timestamptz,
  revoked_at    timestamptz,
  created_at    timestamptz not null default now()
);
create index if not exists community_invites_community_live on public.community_invites (community_id) where revoked_at is null;
create index if not exists community_invites_creator_live   on public.community_invites (created_by)   where revoked_at is null;

create table if not exists public.community_members (
  community_id        uuid not null references public.communities(id) on delete cascade,
  user_id             uuid not null references public.profiles(id) on delete cascade,
  role                text not null default 'member' check (role in ('owner','admin','member')),
  status              text not null default 'pending' check (status in ('pending','active','left','removed')),
  invited_by          uuid references public.profiles(id) on delete set null,
  invite_id           uuid references public.community_invites(id) on delete set null,
  approved_by         uuid references public.profiles(id) on delete set null,
  heard_about         text check (char_length(heard_about) <= 500),     -- readable by the member and the community's admins only
  join_reason         text check (char_length(join_reason) <= 500),
  removal_reason      text check (char_length(removal_reason) <= 500),
  notifications_muted boolean not null default false,
  muted_until         timestamptz,
  joined_at           timestamptz not null default now(),
  activated_at        timestamptz,
  ended_at            timestamptz,
  updated_at          timestamptz not null default now(),
  primary key (community_id, user_id),
  constraint community_members_role_requires_active check (role = 'member' or status = 'active')
);
-- the RLS hot path: "which communities am I an active member of"
create index if not exists community_members_user_active on public.community_members (user_id) include (community_id, role) where status = 'active';
-- admin lists and fan-out loops
create index if not exists community_members_community_status_role on public.community_members (community_id, status, role);

create table if not exists public.community_invite_redemptions (
  invite_id    uuid not null references public.community_invites(id) on delete cascade,
  user_id      uuid not null references public.profiles(id) on delete cascade,
  redeemed_at  timestamptz not null default now(),
  primary key (invite_id, user_id)
);

-- one row per validate / redeem call; the per-account rate limit counts these. No client access.
create table if not exists public.community_invite_attempts (
  user_id      uuid not null references public.profiles(id) on delete cascade,
  attempted_at timestamptz not null default now(),
  succeeded    boolean not null
);
create index if not exists community_invite_attempts_user_time on public.community_invite_attempts (user_id, attempted_at desc);

-- append-only audit of membership and community transitions (the content_moderation_events pattern).
-- No ownerless state exists (decision A3), so there is no 'owner_vacated' / 'ownership_claimed' event.
create table if not exists public.community_membership_events (
  id            uuid primary key default gen_random_uuid(),
  community_id  uuid not null references public.communities(id) on delete cascade,
  user_id       uuid references public.profiles(id) on delete set null,
  actor_id      uuid references public.profiles(id) on delete set null,
  event         text not null check (event in ('applied','invited','approved','rejected','removed','readmitted','left',
                                               'role_changed','ownership_transferred','archived','unarchived')),
  old_role      text,
  new_role      text,
  reason        text,
  created_at    timestamptz not null default now()
);
create index if not exists community_membership_events_community on public.community_membership_events (community_id, created_at desc);

-- decision A1: a member at their owned-community limit asks a platform admin for a higher one.
create table if not exists public.community_limit_requests (
  id             uuid primary key default gen_random_uuid(),
  user_id        uuid not null references public.profiles(id) on delete cascade,
  requested_max  integer not null check (requested_max between 4 and 20),
  reason         text not null check (length(btrim(reason)) between 1 and 500),
  status         text not null default 'pending' check (status in ('pending','approved','declined')),
  decided_by     uuid references public.profiles(id) on delete set null,
  decided_at     timestamptz,
  created_at     timestamptz not null default now()
);
create unique index if not exists community_limit_requests_one_open on public.community_limit_requests (user_id) where status = 'pending';

-- RLS on from the start; no policy yet means no client access. Policies and grants are step 2
-- (20261017_0002); the definer helpers, triggers and RPCs below do not depend on them.
alter table public.communities                  enable row level security;
alter table public.community_invites            enable row level security;
alter table public.community_members            enable row level security;
alter table public.community_invite_redemptions enable row level security;
alter table public.community_invite_attempts    enable row level security;
alter table public.community_membership_events  enable row level security;
alter table public.community_limit_requests     enable row level security;

-- [call] 1a.2 nullable columns on existing tables, their indexes, the report target check
alter table public.profiles        add column if not exists primary_community_id uuid references public.communities(id) on delete set null;
-- decision A1: server-owned (guarded in protect_admin_fields, forced on insert); a constant default never rejects a write
alter table public.profiles        add column if not exists max_owned_communities integer not null default 3
                                     check (max_owned_communities between 0 and 20);
alter table public.rides           add column if not exists community_id uuid references public.communities(id) on delete restrict;
alter table public.favors          add column if not exists community_id uuid references public.communities(id) on delete restrict;
alter table public.town_hall_posts add column if not exists community_id uuid references public.communities(id) on delete restrict;
alter table public.xp_events       add column if not exists community_id uuid references public.communities(id) on delete restrict;
alter table public.notifications   add column if not exists community_id uuid references public.communities(id) on delete set null;
alter table public.reports         add column if not exists community_id uuid references public.communities(id) on delete set null;
alter table public.reports         add column if not exists reported_community_id uuid references public.communities(id) on delete set null;

alter table public.reports
  drop constraint if exists report_target_check,
  add constraint report_target_check check (
    reported_user_id is not null or reported_message_id is not null or reported_post_id is not null
    or reported_comment_id is not null or reported_ride_id is not null or reported_favor_id is not null
    or reported_community_id is not null);

create index if not exists rides_community_visible   on public.rides  (community_id, date) where hidden_at is null;
create index if not exists rides_community_status    on public.rides  (community_id, status);
create index if not exists favors_community_visible  on public.favors (community_id, date) where hidden_at is null;
create index if not exists favors_community_status   on public.favors (community_id, status);
create index if not exists thp_community_created     on public.town_hall_posts (community_id, created_at desc) where hidden_at is null;
create index if not exists xp_events_community_user  on public.xp_events (community_id, user_id, created_at);
create index if not exists xp_events_community_time  on public.xp_events (community_id, created_at);
create index if not exists notifications_user_unread_community on public.notifications (user_id, community_id) where read = false;
create index if not exists reports_community_status  on public.reports (community_id, status);


-- [call] 1a.3 protect_admin_fields (invoker rights; was md5 57a4ac220177f3bda6c86f3c8a5ca450). Applied
-- immediately after 1a.2: authenticated holds a table-wide UPDATE / INSERT grant on profiles and own-row
-- policies, so from the moment 1a.2 adds primary_community_id and max_owned_communities until this call
-- and 1a.4, any user could write their own values (A1: never client-writable). The escape is inert until
-- the mirror exists (1d).
-- (1) a transaction-local escape that only three definer bodies switch on, around exactly one
--     UPDATE profiles each (the mirror, case 3 of the approve bridge, set_primary_community in step 5);
--     clients cannot set it (PostgREST exposes no set_config);
-- (2) the admin test is explicit: no end-user JWT (migrations, SQL editor, cron, service role) still
--     passes, as it does today through the NULL result; a JWT whose user has no profile row now raises;
-- (3) primary_community_id and max_owned_communities join the guarded set.
create or replace function public.protect_admin_fields()
returns trigger
language plpgsql
set search_path = ''
as $function$
begin
    if current_setting('naars.membership_mirror', true) = '1' then
        return new;
    end if;

    if (old.is_admin is distinct from new.is_admin
        or old.approved is distinct from new.approved
        or old.is_banned is distinct from new.is_banned
        or old.primary_community_id is distinct from new.primary_community_id
        or old.max_owned_communities is distinct from new.max_owned_communities) then
        if (select auth.uid()) is not null
           and not coalesce((select p.is_admin from public.profiles p where p.id = (select auth.uid())), false) then
            raise exception 'Only admins can modify is_admin, approved, is_banned, primary_community_id or max_owned_communities fields';
        end if;
    end if;
    return new;
end;
$function$;

-- [call] 1a.4 protect_admin_fields_on_insert (was md5 4e633efc9535982003c39d103c704958): also nulls the
-- primary community and resets the owned-community limit for non-admin inserts
create or replace function public.protect_admin_fields_on_insert()
returns trigger
language plpgsql
set search_path = ''
as $function$
begin
    if auth.uid() is not null and not coalesce(public.is_admin_user(auth.uid()), false) then
        new.is_admin := false;
        new.approved := false;
        new.is_banned := false;
        new.ban_reason := null;
        new.banned_at := null;
        new.banned_by := null;
        new.primary_community_id := null;
        new.max_owned_communities := 3;
    end if;
    return new;
end;
$function$;


-- =====================================================================================================
-- >>> STEP 1b: back-fill Part A (the community, memberships, the primary). Before any membership
--     trigger exists: no notifications, no mirror writes. Idempotent; re-run verbatim at the end of 1d.
-- =====================================================================================================

-- [call] 1b.1 back-fill Part A
-- the default community; owner per D1 = the project owner's account. The owner confirms their profile id
-- before 1b and it is written here as a literal: the oldest is_admin profile is not known to be theirs
-- (none of the 4 admin profiles carries the owner's known email), and a wrong owner can be corrected only
-- by SQL (transfer_community_ownership needs the current owner; platform admins cannot use it). Until the
-- placeholder is replaced the cast fails, so neither the dry-run nor the call can run with a guessed owner.
insert into public.communities (name, created_by, is_default, is_public, join_policy, timezone)
select 'Naar''s Cars Seattle',
       '0da568d8-924c-4420-8853-206a48d277b6'::uuid,   -- the owner-confirmed profiles.id (D1)
       true, true, 'approve', 'America/Los_Angeles'
 where not exists (select 1 from public.communities where is_default);

-- every approved profile -> active member; platform admins -> admin; the creator -> owner
insert into public.community_members (community_id, user_id, role, status, joined_at, activated_at, heard_about, join_reason)
select c.id, p.id, case when p.is_admin then 'admin' else 'member' end, 'active', p.created_at, p.created_at,
       p.heard_about, p.join_reason
  from public.profiles p cross join public.communities c
 where c.is_default and p.approved
on conflict (community_id, user_id) do update
   set status = 'active',
       activated_at = coalesce(public.community_members.activated_at, excluded.activated_at),
       updated_at = now()
 where public.community_members.status = 'pending';   -- approved since the row was created pending (re-run, 1d.8)

update public.community_members m set role = 'owner'
  from public.communities c
 where c.is_default and m.community_id = c.id and m.user_id = c.created_by and m.status = 'active' and m.role <> 'owner';

-- pending applicants (approved = false, application_complete = true) -> pending membership
insert into public.community_members (community_id, user_id, status, heard_about, join_reason)
select c.id, p.id, 'pending', p.heard_about, p.join_reason
  from public.profiles p cross join public.communities c
 where c.is_default and not p.approved and p.application_complete
on conflict (community_id, user_id) do nothing;

update public.profiles set primary_community_id = (select id from public.communities where is_default)
 where approved and primary_community_id is null;

-- a few legacy accounts were approved without ever submitting the form; align the flag the mirror will own
update public.profiles set application_complete = true where approved and not application_complete;


-- =====================================================================================================
-- >>> STEP 1c: the RLS vocabulary (caller-bound helpers, §3.2). All SECURITY DEFINER, STABLE.
--     An archived community is in neither array, so archiving cuts every scoped read and write at once.
-- =====================================================================================================

-- [call] 1c.1 my_community_ids
create or replace function public.my_community_ids()
returns uuid[]
language sql
stable
security definer
set search_path = ''
as $$
  select coalesce(array_agg(m.community_id), '{}'::uuid[])
    from public.community_members m
    join public.profiles p    on p.id = m.user_id
    join public.communities c on c.id = m.community_id and c.archived_at is null
   where m.user_id = (select auth.uid()) and m.status = 'active' and p.is_banned = false;
$$;

-- [call] 1c.2 my_admin_community_ids (platform admins get every non-archived community: the moderation fallback)
create or replace function public.my_admin_community_ids()
returns uuid[]
language sql
stable
security definer
set search_path = ''
as $$
  select case
    when exists (select 1 from public.profiles p where p.id = (select auth.uid()) and p.is_admin and not p.is_banned)
      then coalesce((select array_agg(c.id) from public.communities c where c.archived_at is null), '{}'::uuid[])
    else coalesce((select array_agg(m.community_id)
                     from public.community_members m
                     join public.profiles p    on p.id = m.user_id
                     join public.communities c on c.id = m.community_id and c.archived_at is null
                    where m.user_id = (select auth.uid()) and m.status = 'active'
                      and m.role in ('admin','owner') and p.is_banned = false),
                  '{}'::uuid[])
  end;
$$;

-- [call] 1c.3 is_active_member
create or replace function public.is_active_member(p_community_id uuid)
returns boolean
language sql
stable
security definer
set search_path = ''
as $$
  select p_community_id = any ((select public.my_community_ids())::uuid[]);
$$;

-- [call] 1c.4 is_community_admin
create or replace function public.is_community_admin(p_community_id uuid)
returns boolean
language sql
stable
security definer
set search_path = ''
as $$
  select p_community_id = any ((select public.my_admin_community_ids())::uuid[]);
$$;

-- [call] 1c.5 is_platform_admin
create or replace function public.is_platform_admin()
returns boolean
language sql
stable
security definer
set search_path = ''
as $$
  select exists (select 1 from public.profiles p where p.id = (select auth.uid()) and p.is_admin and not p.is_banned);
$$;

-- [call] 1c.6 community_has_member: answers only when the CALLER is an active member of the community (no oracle)
create or replace function public.community_has_member(p_community_id uuid, p_user_id uuid)
returns boolean
language sql
stable
security definer
set search_path = ''
as $$
  select public.is_active_member(p_community_id)
     and exists (select 1 from public.community_members m
                  where m.community_id = p_community_id and m.user_id = p_user_id and m.status = 'active');
$$;

-- [call] 1c.7 shares_community_with
create or replace function public.shares_community_with(p_other uuid)
returns boolean
language sql
stable
security definer
set search_path = ''
as $$
  select p_other = (select auth.uid()) or exists (
    select 1 from public.community_members m
     where m.user_id = p_other and m.status = 'active'
       and m.community_id = any ((select public.my_community_ids())::uuid[]));
$$;

-- [call] 1c.8 my_visible_profile_ids: self; co-members; co-participants of threads the caller is still in;
-- the other side of the caller's own reviews
create or replace function public.my_visible_profile_ids()
returns uuid[]
language sql
stable
security definer
set search_path = ''
as $$
  select coalesce(array_agg(distinct u), '{}'::uuid[]) from (
    select (select auth.uid()) as u
    union all select m.user_id from public.community_members m
               where m.status = 'active' and m.community_id = any ((select public.my_community_ids())::uuid[])
    union all select b.user_id from public.conversation_participants a
                join public.conversation_participants b on b.conversation_id = a.conversation_id
               where a.user_id = (select auth.uid()) and a.left_at is null
    union all select r.reviewer_id  from public.reviews r where r.fulfiller_id = (select auth.uid())
    union all select r.fulfiller_id from public.reviews r where r.reviewer_id  = (select auth.uid())
  ) s where u is not null;
$$;

-- [call] 1c.9 default_community_id
create or replace function public.default_community_id()
returns uuid
language sql
stable
security definer
set search_path = ''
as $$
  select c.id from public.communities c where c.is_default limit 1;
$$;

-- [call] 1c.10 community_of_request (non-caller-bound; definer bodies and triggers only)
create or replace function public.community_of_request(p_type text, p_id uuid)
returns uuid
language sql
stable
security definer
set search_path = ''
as $$
  select case p_type
           when 'ride'  then (select r.community_id from public.rides r  where r.id = p_id)
           when 'favor' then (select f.community_id from public.favors f where f.id = p_id)
         end;
$$;

-- [call] 1c.11 community_of_post (non-caller-bound; definer bodies and triggers only)
create or replace function public.community_of_post(p_post_id uuid)
returns uuid
language sql
stable
security definer
set search_path = ''
as $$
  select t.community_id from public.town_hall_posts t where t.id = p_post_id;
$$;

-- [call] 1c.12 grants. anon is granted the read helpers on purpose: they return '{}' / false / the default
-- id for a null auth.uid(), so a TO public policy or an EXISTS subquery under anon cannot fail.
revoke all on function public.my_community_ids(), public.my_admin_community_ids(), public.is_active_member(uuid),
  public.is_community_admin(uuid), public.is_platform_admin(), public.community_has_member(uuid, uuid),
  public.shares_community_with(uuid), public.my_visible_profile_ids(), public.default_community_id() from public;
grant execute on function public.my_community_ids(), public.my_admin_community_ids(), public.is_active_member(uuid),
  public.is_community_admin(uuid), public.is_platform_admin(), public.community_has_member(uuid, uuid),
  public.shares_community_with(uuid), public.my_visible_profile_ids(), public.default_community_id()
  to anon, authenticated, service_role;
revoke all on function public.community_of_request(text, uuid), public.community_of_post(uuid) from public, anon, authenticated;
grant execute on function public.community_of_request(text, uuid), public.community_of_post(uuid) to service_role;


-- =====================================================================================================
-- >>> STEP 1d: the mirror functions, the two legacy bridges and their triggers, then the two mirror
--     triggers (bridges first, see 1d.6; the escape in protect_admin_fields already exists from 1a.3);
--     then re-run Part A and assert the consistency query returns no row.
-- =====================================================================================================

-- [call] 1d.1 recompute_profile_membership_flags (the mirror, INV-M5)
--   approved             := the user has an active membership in a non-archived community
--   application_complete := the user has an active or a pending one
--   primary_community_id := kept while it is a live active membership, else the earliest one, else null
-- Every column is written only when it differs, so the mirror is re-entrant and cannot ping-pong. The
-- escape is restored to its previous value rather than cleared, so a caller's own escape is not ended.
create or replace function public.recompute_profile_membership_flags(p_user uuid)
returns void
language plpgsql
security definer
set search_path = ''
as $$
declare
  v_active  boolean;
  v_pending boolean;
  v_primary uuid;
  v_keep    uuid;
  v_prev    text := coalesce(current_setting('naars.membership_mirror', true), '');
begin
  select coalesce(bool_or(m.status = 'active'), false), coalesce(bool_or(m.status = 'pending'), false)
    into v_active, v_pending
    from public.community_members m
    join public.communities c on c.id = m.community_id and c.archived_at is null
   where m.user_id = p_user and m.status in ('active','pending');

  select m.community_id into v_primary
    from public.community_members m
    join public.communities c on c.id = m.community_id and c.archived_at is null
   where m.user_id = p_user and m.status = 'active'
   order by m.activated_at nulls last, m.community_id
   limit 1;

  select m.community_id into v_keep
    from public.profiles p
    join public.community_members m on m.user_id = p.id and m.community_id = p.primary_community_id and m.status = 'active'
    join public.communities c on c.id = m.community_id and c.archived_at is null
   where p.id = p_user;

  perform set_config('naars.membership_mirror', '1', true);   -- lets protect_admin_fields pass this one statement
  update public.profiles p
     set approved = v_active,
         application_complete = (v_active or v_pending),
         primary_community_id = coalesce(v_keep, v_primary)
   where p.id = p_user
     and (p.approved is distinct from v_active
          or p.application_complete is distinct from (v_active or v_pending)
          or p.primary_community_id is distinct from coalesce(v_keep, v_primary));
  perform set_config('naars.membership_mirror', v_prev, true);
end
$$;
-- revoked in the same call: the mirror and the bridges are live several calls before 1d.7
revoke all on function public.recompute_profile_membership_flags(uuid) from public, anon, authenticated;

-- [call] 1d.2 maintain_profile_membership_flags (trigger function)
create or replace function public.maintain_profile_membership_flags()
returns trigger
language plpgsql
security definer
set search_path = ''
as $$
begin
  perform public.recompute_profile_membership_flags(coalesce(new.user_id, old.user_id));
  return null;
end
$$;

-- [call] 1d.3 recompute_flags_on_archive (trigger function): archiving or restoring a community changes
-- every member's effective membership without touching their rows
create or replace function public.recompute_flags_on_archive()
returns trigger
language plpgsql
security definer
set search_path = ''
as $$
declare
  r record;
begin
  for r in
    select m.user_id from public.community_members m
     where m.community_id = new.id and m.status in ('active','pending')
  loop
    perform public.recompute_profile_membership_flags(r.user_id);
  end loop;
  return null;
end
$$;

-- [call] 1d.4 legacy_application_to_membership (bridge 1, state-based)
-- The installed build's application submit is a direct UPDATE profiles ... application_complete = true.
-- It becomes an application to the DEFAULT community, unless the person already has or is waiting on a
-- membership somewhere (then the flag was flipped by the mirror, not by the old form). A `removed` row is
-- never reopened by the applicant (D4); in that case, and when no default community is live, the closing
-- recompute puts application_complete back to what memberships say (INV-M5), so the old form shows again.
-- Re-entrancy: the mirror's own false->true write of application_complete fires this trigger, which
-- returns at the second guard (a live active or pending membership exists); the closing recompute writes
-- application_complete true->false at most, which returns at the first guard.
create or replace function public.legacy_application_to_membership()
returns trigger
language plpgsql
security definer
set search_path = ''
as $$
declare
  v_rows int;
  v_default uuid;
begin
  if not (new.application_complete and not old.application_complete) then
    return null;
  end if;
  if exists (select 1 from public.community_members m
               join public.communities c on c.id = m.community_id and c.archived_at is null
              where m.user_id = new.id and m.status in ('active','pending')) then
    return null;
  end if;

  select c.id into v_default from public.communities c where c.is_default and c.archived_at is null;
  if v_default is not null then
    insert into public.community_members (community_id, user_id, status, heard_about, join_reason)
    values (v_default, new.id, 'pending', new.heard_about, new.join_reason)
    on conflict (community_id, user_id) do update
       set status = 'pending', heard_about = excluded.heard_about, join_reason = excluded.join_reason,
           ended_at = null, updated_at = now()
     where public.community_members.status = 'left';
    get diagnostics v_rows = row_count;
    if v_rows > 0 then
      insert into public.community_membership_events (community_id, user_id, actor_id, event)
      values (v_default, new.id, new.id, 'applied');
    end if;
  end if;

  perform public.recompute_profile_membership_flags(new.id);
  return null;
end
$$;

-- [call] 1d.5 sync_legacy_approval_to_membership (bridge 2, state-based)
-- The installed admin build's approve is a direct UPDATE profiles SET approved = true. Three cases:
-- (1) a pending DEFAULT-community row -> activate it (today's flow);
-- (2) no membership row at all -> create an active default membership (a never-applied account a
--     platform admin vouches for);
-- (3) anything else (pending only in OTHER communities, or only ended rows) -> restore approved = false
--     in the same transaction (S6).
-- A no-op when a live active membership already exists (which is also how the mirror's own false->true
-- write returns). Re-entrancy, case (1): the activation fires the mirror, which finds approved already
-- true and writes at most primary_community_id, so this trigger never fires again with old.approved =
-- false. Case (3): the inner UPDATE re-fires this trigger with new.approved = false, which returns at the
-- first guard. (notify_user_approved gains its active-membership guard in step 3; until then case (3)
-- cannot arise for anyone, because no RPC can yet end a membership or create one outside the default.)
create or replace function public.sync_legacy_approval_to_membership()
returns trigger
language plpgsql
security definer
set search_path = ''
as $$
declare
  v_default uuid := public.default_community_id();
  v_actor   uuid := (select auth.uid());
  v_prev    text;
begin
  if not (new.approved and not old.approved) then
    return null;
  end if;
  if exists (select 1 from public.community_members m
               join public.communities c on c.id = m.community_id and c.archived_at is null
              where m.user_id = new.id and m.status = 'active') then
    return null;
  end if;
  if v_default is null then
    return null;
  end if;

  if exists (select 1 from public.community_members m
              where m.user_id = new.id and m.community_id = v_default and m.status = 'pending') then
    update public.community_members
       set status = 'active', activated_at = now(), approved_by = v_actor, updated_at = now()
     where user_id = new.id and community_id = v_default and status = 'pending';
    insert into public.community_membership_events (community_id, user_id, actor_id, event)
    values (v_default, new.id, v_actor, 'approved');
  elsif not exists (select 1 from public.community_members m where m.user_id = new.id) then
    insert into public.community_members (community_id, user_id, status, activated_at, approved_by, heard_about, join_reason)
    values (v_default, new.id, 'active', now(), v_actor, new.heard_about, new.join_reason);
    insert into public.community_membership_events (community_id, user_id, actor_id, event)
    values (v_default, new.id, v_actor, 'approved');
  else
    v_prev := coalesce(current_setting('naars.membership_mirror', true), '');
    perform set_config('naars.membership_mirror', '1', true);
    update public.profiles set approved = false where id = new.id;
    perform set_config('naars.membership_mirror', v_prev, true);
  end if;
  return null;
end
$$;

-- [call] 1d.6 the bridge triggers and grants. Before the mirror triggers (1d.7): an applicant approved
-- by the installed admin build from here on goes through bridge 2, and one approved between 1b and here is
-- promoted by the re-run (1d.8), so the assertion (1d.9) cannot find an approved profile with a pending row.
create or replace trigger legacy_application_to_membership
  after update of application_complete on public.profiles
  for each row execute function public.legacy_application_to_membership();

-- Named with an "a_" prefix on purpose: same-event triggers fire in alphabetical order, and this one must
-- run BEFORE on_user_approved_notify so that case (1) has an active membership when the welcome push is
-- built and case (3) has already restored approved = false.
create or replace trigger a_sync_legacy_approval_to_membership
  after update of approved on public.profiles
  for each row execute function public.sync_legacy_approval_to_membership();

revoke all on function public.legacy_application_to_membership(), public.sync_legacy_approval_to_membership()
  from public, anon, authenticated;

-- [call] 1d.7 the two mirror triggers and grants
create or replace trigger maintain_profile_membership_flags
  after insert or update of status or delete on public.community_members
  for each row execute function public.maintain_profile_membership_flags();

create or replace trigger recompute_flags_on_archive
  after update of archived_at on public.communities
  for each row when (old.archived_at is distinct from new.archived_at)
  execute function public.recompute_flags_on_archive();

revoke all on function public.maintain_profile_membership_flags(), public.recompute_flags_on_archive()
  from public, anon, authenticated;

-- [call] 1d.8 re-run back-fill Part A: repeat the [call] 1b.1 block verbatim. It catches anyone approved
-- or applying between 1b and here, and promotes a pending default row whose profile was approved in the
-- meantime (the ON CONFLICT ... DO UPDATE of the active-member insert); with the triggers live, each new
-- or promoted membership row now runs the mirror.

-- [call] 1d.9 consistency assertion (must raise nothing). The same query, without the DO wrapper, lists
-- the offending profiles.
do $$
declare
  v_bad int;
begin
  with live as (
    select m.user_id, m.community_id, m.status
      from public.community_members m
      join public.communities c on c.id = m.community_id and c.archived_at is null
     where m.status in ('active','pending')
  ), expected as (
    select p.id, p.approved, p.application_complete, p.primary_community_id,
           exists (select 1 from live l where l.user_id = p.id and l.status = 'active') as exp_approved,
           exists (select 1 from live l where l.user_id = p.id)                         as exp_application,
           exists (select 1 from live l where l.user_id = p.id and l.status = 'active'
                                          and l.community_id = p.primary_community_id) as primary_live
      from public.profiles p
  )
  select count(*) into v_bad
    from expected e
   where e.approved <> e.exp_approved
      or e.application_complete <> e.exp_application
      or (e.primary_community_id is not null and not e.primary_live)
      or (e.exp_approved and e.primary_community_id is null);
  if v_bad > 0 then
    raise exception 'membership consistency: % profile(s) out of step with their memberships', v_bad;
  end if;
  -- nobody raised their own owned-community limit before 1a.3 / 1a.4 guarded it (A1)
  select count(*) into v_bad from public.profiles p where p.max_owned_communities <> 3;
  if v_bad > 0 then
    raise exception 'max_owned_communities: % profile(s) differ from the default 3', v_bad;
  end if;
end
$$;


-- =====================================================================================================
-- >>> STEP 1e: fill and derive triggers. From here no new row can lack a community.
-- =====================================================================================================

-- [call] 1e.1 fill_request_community
-- Fills community_id when the client omits it (the installed build always omits it). Uses new.user_id,
-- not auth.uid(), so definer code that inserts for another user is covered too. The stored primary is
-- trusted only while it is a live active membership, so a stale or crafted value can never misroute a post.
create or replace function public.fill_request_community()
returns trigger
language plpgsql
security definer
set search_path = ''
as $$
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
  -- rollout safety only, removed in Phase 5: an approved legacy account the back-fill has not reached yet
  if v_c is null
     and not exists (select 1 from public.community_members m where m.user_id = new.user_id)
     and exists (select 1 from public.profiles p where p.id = new.user_id and p.approved) then
    v_c := public.default_community_id();
  end if;
  if v_c is null then
    raise exception 'Choose a community' using errcode = '42501';
  end if;
  new.community_id := v_c;
  return new;
end
$$;

-- [call] 1e.2 fill_request_community triggers
create or replace trigger fill_community_rides
  before insert on public.rides
  for each row execute function public.fill_request_community();
create or replace trigger fill_community_favors
  before insert on public.favors
  for each row execute function public.fill_request_community();
create or replace trigger fill_community_posts
  before insert on public.town_hall_posts
  for each row execute function public.fill_request_community();
revoke all on function public.fill_request_community() from public, anon, authenticated;

-- [call] 1e.3 fill_xp_event_community
-- xp_events rows are written only by the three record_xp_* triggers. This keeps them working unedited;
-- step 3 makes them pass the community explicitly. It never raises: a failure here would abort the ride
-- insert, completion or review that fired the writer.
create or replace function public.fill_xp_event_community()
returns trigger
language plpgsql
security definer
set search_path = ''
as $$
begin
  if new.community_id is not null then
    return new;
  end if;
  new.community_id := case
    when new.source_type in ('ride_requested','first_ride','ride_fulfilled')
      then (select r.community_id from public.rides r where r.id = new.source_id)
    when new.source_type in ('favor_requested','first_favor','favor_fulfilled')
      then (select f.community_id from public.favors f where f.id = new.source_id)
    when new.source_type = 'review_received'
      then (select coalesce(r.community_id, f.community_id)
              from public.reviews v
              left join public.rides r  on r.id = v.ride_id
              left join public.favors f on f.id = v.favor_id
             where v.id = new.source_id)
  end;
  if new.community_id is null then
    new.community_id := coalesce((select p.primary_community_id from public.profiles p where p.id = new.user_id),
                                 public.default_community_id());
  end if;
  return new;
end
$$;

-- [call] 1e.4 fill_xp_event_community trigger
create or replace trigger fill_community_xp_events
  before insert on public.xp_events
  for each row execute function public.fill_xp_event_community();
revoke all on function public.fill_xp_event_community() from public, anon, authenticated;

-- [call] 1e.5 derive_notification_community (INV-N1)
-- When community_id is null: from ride_id / favor_id / town_hall_post_id, else from review_id through the
-- reviewed request. Rows that carry only a conversation or a message stay null on purpose (messaging is
-- not community-scoped). Membership RPCs that create entity-less rows set community_id with a direct
-- UPDATE on the id create_notification returns.
create or replace function public.derive_notification_community()
returns trigger
language plpgsql
security definer
set search_path = ''
as $$
begin
  if new.community_id is not null then
    return new;
  end if;
  if new.ride_id is not null then
    new.community_id := (select r.community_id from public.rides r where r.id = new.ride_id);
  elsif new.favor_id is not null then
    new.community_id := (select f.community_id from public.favors f where f.id = new.favor_id);
  elsif new.town_hall_post_id is not null then
    new.community_id := (select t.community_id from public.town_hall_posts t where t.id = new.town_hall_post_id);
  elsif new.review_id is not null then
    new.community_id := (select coalesce(r.community_id, f.community_id)
                           from public.reviews v
                           left join public.rides r  on r.id = v.ride_id
                           left join public.favors f on f.id = v.favor_id
                          where v.id = new.review_id);
  end if;
  return new;
end
$$;

-- [call] 1e.6 derive_notification_community trigger
create or replace trigger derive_notification_community
  before insert on public.notifications
  for each row execute function public.derive_notification_community();
revoke all on function public.derive_notification_community() from public, anon, authenticated;

-- [call] 1e.7 derive_report_community (INV-P1)
-- Always derived (a supplied value is ignored), so the routing cannot be chosen by the writer:
--   content reports  -> the target's community (ride, favor, post, or the comment's post);
--   person reports   -> the one live community the reporter and the reported person both belong to,
--                       when there is exactly one (D27); otherwise null;
--   message reports and community reports -> null (platform admins only).
-- submit_report's signature is unchanged.
create or replace function public.derive_report_community()
returns trigger
language plpgsql
security definer
set search_path = ''
as $$
declare
  v_shared uuid[];
begin
  new.community_id := null;
  if new.reported_message_id is not null or new.reported_community_id is not null then
    return new;
  end if;

  if new.reported_ride_id is not null then
    new.community_id := (select r.community_id from public.rides r where r.id = new.reported_ride_id);
  elsif new.reported_favor_id is not null then
    new.community_id := (select f.community_id from public.favors f where f.id = new.reported_favor_id);
  elsif new.reported_post_id is not null then
    new.community_id := (select t.community_id from public.town_hall_posts t where t.id = new.reported_post_id);
  elsif new.reported_comment_id is not null then
    new.community_id := (select t.community_id
                           from public.town_hall_comments k
                           join public.town_hall_posts t on t.id = k.post_id
                          where k.id = new.reported_comment_id);
  elsif new.reported_user_id is not null then
    select coalesce(array_agg(a.community_id), '{}'::uuid[]) into v_shared
      from public.community_members a
      join public.community_members b on b.community_id = a.community_id
                                      and b.user_id = new.reported_user_id and b.status = 'active'
      join public.communities c on c.id = a.community_id and c.archived_at is null
     where a.user_id = new.reporter_id and a.status = 'active';
    if cardinality(v_shared) = 1 then
      new.community_id := v_shared[1];
    end if;
  end if;
  return new;
end
$$;

-- [call] 1e.8 derive_report_community trigger
create or replace trigger derive_report_community
  before insert on public.reports
  for each row execute function public.derive_report_community();
revoke all on function public.derive_report_community() from public, anon, authenticated;


-- =====================================================================================================
-- >>> STEP 1f: back-fill Part B (content rows, xp_events, notifications, reports). After the fill
--     triggers, so a row inserted in between is either filled by a trigger or picked up here.
--     Idempotent.
-- =====================================================================================================

-- [call] 1f.1 back-fill Part B, one transaction. The live BEFORE UPDATE triggers set_updated_at_* would set
-- updated_at = now() on every ride, favor and post; rides.updated_at / favors.updated_at are the completion
-- time in get_leaderboard_spotlights and get_community_spotlights (weeks, streaks, date windows), and the
-- old values could not be recovered. They are disabled for these three updates only and re-enabled in the
-- same transaction; the closing check raises (rolling the call back) if any row got this transaction's now().
-- DISABLE TRIGGER holds a SHARE ROW EXCLUSIVE lock to the end of the call, so a member's concurrent edit
-- waits for the commit and then runs with the trigger enabled.
alter table public.rides           disable trigger set_updated_at_rides;
alter table public.favors          disable trigger set_updated_at_favors;
alter table public.town_hall_posts disable trigger set_updated_at_town_hall_posts;
update public.rides           set community_id = (select id from public.communities where is_default) where community_id is null;
update public.favors          set community_id = (select id from public.communities where is_default) where community_id is null;
update public.town_hall_posts set community_id = (select id from public.communities where is_default) where community_id is null;
alter table public.rides           enable trigger set_updated_at_rides;
alter table public.favors          enable trigger set_updated_at_favors;
alter table public.town_hall_posts enable trigger set_updated_at_town_hall_posts;
update public.xp_events       set community_id = (select id from public.communities where is_default) where community_id is null;
update public.notifications n set community_id = (select id from public.communities where is_default)
 where n.community_id is null
   and (n.ride_id is not null or n.favor_id is not null or n.town_hall_post_id is not null or n.review_id is not null);
update public.reports r set community_id = (select id from public.communities where is_default)
 where r.community_id is null and r.reported_message_id is null and r.reported_community_id is null;  -- message reports stay null
do $$
begin
  if exists (select 1 from public.rides where updated_at = now())
     or exists (select 1 from public.favors where updated_at = now())
     or exists (select 1 from public.town_hall_posts where updated_at = now()) then
    raise exception 'back-fill Part B moved updated_at; the set_updated_at_* triggers were not disabled';
  end if;
end
$$;

-- [call] 1f.2 content assertion (must raise nothing; step 6 turns this fact into NOT NULL later). Also
-- compare max(updated_at) of rides, favors and town_hall_posts with the values read immediately before
-- 1f.1 (select max(updated_at) from each); they must not have moved except by a member's own edit in
-- between, and the set_updated_at_* triggers must be enabled again:
--   select tgrelid::regclass, tgname, tgenabled from pg_catalog.pg_trigger
--    where tgname in ('set_updated_at_rides','set_updated_at_favors','set_updated_at_town_hall_posts');
--   -- tgenabled = 'O' on all three
do $$
declare
  v_rides int; v_favors int; v_posts int; v_xp int;
begin
  select count(*) into v_rides  from public.rides           where community_id is null;
  select count(*) into v_favors from public.favors          where community_id is null;
  select count(*) into v_posts  from public.town_hall_posts where community_id is null;
  select count(*) into v_xp     from public.xp_events       where community_id is null;
  if v_rides + v_favors + v_posts + v_xp > 0 then
    raise exception 'community back-fill incomplete: rides %, favors %, posts %, xp_events %', v_rides, v_favors, v_posts, v_xp;
  end if;
  if exists (select 1 from pg_catalog.pg_trigger
              where tgname in ('set_updated_at_rides','set_updated_at_favors','set_updated_at_town_hall_posts')
                and tgenabled <> 'O') then
    raise exception 'a set_updated_at_* trigger on rides / favors / town_hall_posts is still disabled';
  end if;
end
$$;


-- =====================================================================================================
-- >>> STEP 1g: the claim membership guard, the community_members client-update guard, the append-only
--     trigger, updated_at triggers. The claim guard compares community_id, so it follows Part B.
-- =====================================================================================================

-- [call] 1g.1 guard_request_claim_membership (INV-R3): whenever claimed_by becomes non-null, the claimer
-- is an active, unbanned member of the request's live community. Binds definer code too.
create or replace function public.guard_request_claim_membership()
returns trigger
language plpgsql
security definer
set search_path = ''
as $$
begin
  if new.claimed_by is not null and new.claimed_by is distinct from old.claimed_by
     and not exists (select 1 from public.community_members m
                       join public.profiles p    on p.id = m.user_id
                       join public.communities c on c.id = m.community_id and c.archived_at is null
                      where m.community_id = new.community_id and m.user_id = new.claimed_by
                        and m.status = 'active' and p.is_banned = false) then
    raise exception 'Only members of this community can claim this request' using errcode = '42501';
  end if;
  return new;
end
$$;

-- [call] 1g.2 guard_request_claim_membership triggers
create or replace trigger guard_request_claim_membership
  before update on public.rides
  for each row execute function public.guard_request_claim_membership();
create or replace trigger guard_request_claim_membership
  before update on public.favors
  for each row execute function public.guard_request_claim_membership();
revoke all on function public.guard_request_claim_membership() from public, anon, authenticated;

-- [call] 1g.3 guard_community_members_client_update (invoker rights; defense in depth beside the step-2
-- column grant, mirrors guard_request_client_update): a direct client UPDATE may change only
-- notifications_muted, muted_until and updated_at. Definer RPCs and RI actions do not run as a client role.
create or replace function public.guard_community_members_client_update()
returns trigger
language plpgsql
set search_path = ''
as $g$
declare
  v_free constant text[] := array['notifications_muted', 'muted_until', 'updated_at'];
begin
  if current_user not in ('authenticated', 'anon') then
    return new;
  end if;
  if (to_jsonb(new) - v_free) is distinct from (to_jsonb(old) - v_free) then
    raise exception 'This change to a membership is not allowed' using errcode = '42501';
  end if;
  return new;
end
$g$;

-- [call] 1g.4 guard_community_members_client_update trigger
create or replace trigger guard_community_members_client_update
  before update on public.community_members
  for each row execute function public.guard_community_members_client_update();
revoke all on function public.guard_community_members_client_update() from public, anon, authenticated;

-- [call] 1g.5 prevent_community_membership_events_mutation (append-only, the 20261005_0024 pattern)
-- Permits exactly two kinds of UPDATE: a foreign key (user_id, actor_id) going to NULL (the ON DELETE SET
-- NULL action when a profile is deleted), and reason going to NULL (account deletion scrubs free text
-- written about the deleted user). Nothing else may change, and every DELETE raises.
create or replace function public.prevent_community_membership_events_mutation()
returns trigger
language plpgsql
set search_path = ''
as $function$
begin
    if tg_op = 'UPDATE'
       and (to_jsonb(new) - 'user_id' - 'actor_id' - 'reason') = (to_jsonb(old) - 'user_id' - 'actor_id' - 'reason')
       and (new.user_id  is null or new.user_id  = old.user_id)
       and (new.actor_id is null or new.actor_id = old.actor_id)
       and (new.reason   is null or new.reason   = old.reason)
    then
        return new;
    end if;
    raise exception 'community_membership_events is append-only';
end;
$function$;

-- [call] 1g.6 append-only and updated_at triggers
create or replace trigger community_membership_events_append_only
  before update or delete on public.community_membership_events
  for each row execute function public.prevent_community_membership_events_mutation();
revoke all on function public.prevent_community_membership_events_mutation() from public, anon, authenticated;

create or replace trigger set_updated_at_communities
  before update on public.communities
  for each row execute function public.handle_updated_at();
create or replace trigger set_updated_at_community_members
  before update on public.community_members
  for each row execute function public.handle_updated_at();


-- =====================================================================================================
-- >>> STEP 1h: should_notify_user (the two arms), then the function notify_pending_membership, then
--     notify_pending_user -> no-op, then the notify_pending_membership trigger, as consecutive calls.
--     The gate precedes the producer; the no-op and the new trigger are adjacent so an applicant is
--     announced once.
-- =====================================================================================================

-- [call] 1h.1 should_notify_user (was md5 df75c614219979f8fbc56f6b4c32a240; body otherwise unchanged)
-- pending_approval and content_reported: platform admins, or an active owner / admin of a live community.
-- The gate only answers "may this person ever receive this type"; the producers' recipient queries decide
-- which admins receive a given row. account_restricted gets an arm (it fell to ELSE false).
create or replace function public.should_notify_user(p_user_id uuid, p_notification_type text)
returns boolean
language plpgsql
security definer
set search_path = ''
as $function$
DECLARE
    v_profile RECORD;
BEGIN
    SELECT * INTO v_profile FROM public.profiles WHERE id = p_user_id;
    IF NOT FOUND THEN
        RETURN false;
    END IF;

    CASE
        WHEN p_notification_type IN ('new_ride', 'new_favor') THEN
            RETURN true;
        WHEN p_notification_type IN ('announcement', 'admin_announcement', 'broadcast') THEN
            RETURN true;
        WHEN p_notification_type IN ('user_approved', 'user_rejected') THEN
            RETURN true;
        WHEN p_notification_type = 'account_restricted' THEN
            RETURN true;
        WHEN p_notification_type IN ('pending_approval', 'content_reported') THEN
            RETURN v_profile.is_admin
                OR EXISTS (SELECT 1 FROM public.community_members m
                             JOIN public.communities c ON c.id = m.community_id AND c.archived_at IS NULL
                            WHERE m.user_id = p_user_id AND m.status = 'active' AND m.role IN ('owner', 'admin'));
        WHEN p_notification_type IN ('message', 'added_to_conversation') THEN
            RETURN v_profile.notify_messages;
        WHEN p_notification_type IN (
            'ride_update', 'ride_claimed', 'ride_unclaimed', 'ride_completed',
            'favor_update', 'favor_claimed', 'favor_unclaimed', 'favor_completed'
        ) THEN
            RETURN v_profile.notify_ride_updates;
        WHEN p_notification_type IN ('qa_activity', 'qa_question', 'qa_answer') THEN
            RETURN v_profile.notify_qa_activity;
        WHEN p_notification_type IN (
            'review', 'review_received', 'review_reminder', 'review_request', 'completion_reminder'
        ) THEN
            RETURN v_profile.notify_review_reminders;
        WHEN p_notification_type IN ('town_hall_post', 'town_hall_comment', 'town_hall_reaction') THEN
            RETURN v_profile.notify_town_hall;
        WHEN p_notification_type = 'content_hidden' THEN
            RETURN true;
        ELSE
            RETURN false;
    END CASE;
END;
$function$;

-- [call] 1h.2 notify_pending_membership (function; the trigger is 1h.4)
-- A membership that becomes pending is announced to the community's active, unbanned owner and admins;
-- to the platform admins instead when it has none (D21). Text per spec §2.4. The applicant's name only
-- (never the email: the recipients may be community owners who are not platform admins). The bell row's
-- community_id is set on the returned id, since the row carries no entity the derive trigger could use.
-- This is the function's only body: 20261017_0005 does not redefine it.
create or replace function public.notify_pending_membership()
returns trigger
language plpgsql
security definer
set search_path = ''
as $$
declare
  v_community   text;
  v_archived    timestamptz;
  v_name        text;
  v_title       text;
  v_body        text;
  v_has_admins  boolean;
  v_recipient   uuid;
  v_nid         uuid;
begin
  if new.status <> 'pending' then
    return null;
  end if;
  if tg_op = 'UPDATE' and old.status = 'pending' then
    return null;
  end if;

  select c.name, c.archived_at into v_community, v_archived
    from public.communities c where c.id = new.community_id;
  if v_community is null or v_archived is not null then
    return null;
  end if;

  select nullif(btrim(p.name), '') into v_name from public.profiles p where p.id = new.user_id;
  v_title := 'New request to join ' || v_community;
  v_body  := coalesce(v_name, 'Someone') || ' wants to join.';

  select exists (select 1 from public.community_members m
                   join public.profiles p on p.id = m.user_id
                  where m.community_id = new.community_id and m.status = 'active'
                    and m.role in ('owner','admin') and not p.is_banned and m.user_id <> new.user_id)
    into v_has_admins;

  for v_recipient in
    select m.user_id
      from public.community_members m
      join public.profiles p on p.id = m.user_id
     where v_has_admins
       and m.community_id = new.community_id and m.status = 'active'
       and m.role in ('owner','admin') and not p.is_banned and m.user_id <> new.user_id
    union
    select p.id
      from public.profiles p
     where not v_has_admins
       and p.is_admin and not p.is_banned and p.id <> new.user_id
  loop
    v_nid := public.create_notification(
      v_recipient, 'pending_approval'::text, v_title, v_body,
      null::uuid, null::uuid, null::uuid, null::uuid, null::uuid, new.user_id);
    if v_nid is not null then
      update public.notifications set community_id = new.community_id where id = v_nid;
      perform public.queue_push_notification(
        v_recipient, 'pending_approval'::text, v_title, v_body,
        jsonb_build_object('user_id', new.user_id::text, 'community_id', new.community_id::text),
        null::text, v_nid);
    end if;
  end loop;

  return null;
end
$$;

-- [call] 1h.3 notify_pending_user -> no-op (was md5 57634dd2df8f216a25302e2e8c6db0d4). The producer moves
-- to notify_pending_membership, which announces the application when it exists rather than at sign-up.
-- The on_pending_user_notify trigger stays attached and does nothing.
create or replace function public.notify_pending_user()
returns trigger
language plpgsql
security definer
set search_path = ''
as $function$
begin
    return new;
end;
$function$;

-- [call] 1h.4 notify_pending_membership trigger (immediately after 1h.3)
create or replace trigger notify_pending_membership
  after insert or update of status on public.community_members
  for each row when (new.status = 'pending')
  execute function public.notify_pending_membership();
revoke all on function public.notify_pending_membership() from public, anon, authenticated;
