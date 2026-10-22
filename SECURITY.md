# Naar's Cars Security Requirements

## Document Information
- **Type**: Security Requirements
- **Last Updated**: 2026-10-05 (sections 2.1.1, 2.13 and 2.26.1 updated for Community Release 1 on 2026-10-22)
- **Status**: Live app; reflects production RLS as of 2026-10-05

---

## 1. Overview

This document defines security requirements for the Naar's Cars iOS application. All developers MUST read and follow these requirements. Security is not optional and takes precedence over feature velocity.

### Security Principles

1. **Defense in Depth**: Multiple layers of protection (client + server)
2. **Least Privilege**: Users only access what they need
3. **Fail Secure**: Errors default to denying access
4. **Don't Trust the Client**: All security enforced server-side

---

## 2. Row Level Security (RLS) Policies

All Supabase tables MUST have RLS enabled. The following policies are REQUIRED before any production deployment.

### 2.1 profiles

The `profiles` table contains PII (`email`, `phone_number`, `is_admin`, `is_banned`, `ban_reason`, `banned_by`, `heard_about`, `join_reason`, `application_submitted_at`, `application_complete`, `notify_*`). Direct SELECT on `profiles` is restricted to **self and admin only**. As of the October 2026 client update, all cross-user profile reads — messaging sender hydration, town-hall author lookup, user search, invite flows, profile cards — go through the **`public_profiles` view**, which exposes only non-PII columns (`id`, `name`, `avatar_url`, `car`, `approved`, `created_at`, `updated_at`). Own-row and admin reads still SELECT from `profiles` directly. (Until 2026-10-05 the shipped client still joined `profiles` for cross-user reads; the view existed server-side but was not yet the client's read path.)

This split was introduced by audit-CRIT-7 in `supabase/migrations/20260417015221_security_profiles_projection_split.sql`. See [§2.1.1 The `public_profiles` view](#211-the-public_profiles-view) below for the design rationale.

| Policy Name | Operation | Roles | SQL Check |
|-------------|-----------|-------|-----------|
| `profiles_select_own` | SELECT | authenticated | `auth.uid() = id` |
| `profiles_select_admin` | SELECT | authenticated | `is_admin_user(auth.uid())` |
| `Users can insert own profile` | INSERT | (all) | `WITH CHECK (auth.uid() = id)` |
| `Users can update own profile` | UPDATE | (all) | `auth.uid() = id` |
| `profiles_update_own` | UPDATE | (all) | `auth.uid() = id` |
| `profiles_update_admin` | UPDATE | (all) | `is_admin_user(auth.uid())` |
| `profiles_admin_delete` | DELETE | authenticated | `approved = false AND <caller is admin>` |

```sql
ALTER TABLE public.profiles ENABLE ROW LEVEL SECURITY;

-- Self-read full row
CREATE POLICY "profiles_select_own"
ON public.profiles FOR SELECT TO authenticated
USING (auth.uid() = id);

-- Admin-read full row
CREATE POLICY "profiles_select_admin"
ON public.profiles FOR SELECT TO authenticated
USING (is_admin_user(auth.uid()));

-- Anyone can create their own profile during signup
CREATE POLICY "Users can insert own profile"
ON public.profiles FOR INSERT
WITH CHECK (auth.uid() = id);

-- Self and admin can update
CREATE POLICY "profiles_update_own"
ON public.profiles FOR UPDATE
USING (auth.uid() = id) WITH CHECK (auth.uid() = id);

CREATE POLICY "profiles_update_admin"
ON public.profiles FOR UPDATE
USING (is_admin_user(auth.uid())) WITH CHECK (is_admin_user(auth.uid()));

-- Admins can prune unapproved applications
CREATE POLICY "profiles_admin_delete"
ON public.profiles FOR DELETE TO authenticated
USING (
  approved = false
  AND EXISTS (
    SELECT 1 FROM public.profiles p
    WHERE p.id = auth.uid() AND p.is_admin = true
  )
);
```

#### 2.1.1 The `public_profiles` view

```sql
CREATE OR REPLACE VIEW public.public_profiles
WITH (security_barrier = true, security_invoker = false) AS
SELECT id, name, avatar_url, car, approved, created_at, updated_at
FROM public.profiles;

REVOKE ALL  ON public.public_profiles FROM PUBLIC;
GRANT SELECT ON public.public_profiles TO authenticated, anon, service_role;
```

**Design decision: `security_invoker = false` is intentional.** The Supabase advisor `0010_security_definer_view` flags this view because it bypasses the underlying RLS on `profiles` and runs with the view-creator's (postgres) privileges. **This is the mechanism that makes the split work** — if the view ran as the invoker, the narrowed RLS on `profiles` (self + admin only) would block every cross-user profile lookup the app does (messaging, town hall, search, invites).

Realistic alternatives evaluated and rejected:

| Alternative | Why rejected |
|---|---|
| Convert to `security_invoker = true` + permissive RLS on `profiles` + column-level GRANTs | Would require self/admin to read PII through a separate SECURITY DEFINER RPC, weakens defense-in-depth (PII becomes column-grant-protected instead of network-unreachable on the base table), and column-level GRANT semantics are easy to misconfigure. |
| Convert to a SECURITY DEFINER RPC (`get_public_profiles(ids[])`) | Breaks every relationship-style join in `MessageService`, `ConversationService`, `TownHallService`, `TownHallCommentService`, `InviteService`, `ProfileService`, `UserSearchView`, `SupabaseService` (e.g. `sender:public_profiles!messages_from_id_fkey(id, name, avatar_url)`). PostgREST doesn't join RPCs. Trades one advisor warning for another. |

**The view stays as-is.** The advisor warning is a known accepted exception — record it as such, do not auto-remediate. If the underlying `profiles` schema changes (new PII columns), update the view's column list at the same time.

**Which rows (multi-community, live as of 2026-10-21).** The SQL block above shows only the column list. The live view also filters rows: a signed-in caller reads the ids `public.my_visible_profile_ids()` returns, and a caller with no JWT subject (a guest) reads the active members of listed communities (`is_public`, not archived). `my_visible_profile_ids()` (SECURITY DEFINER, `search_path = ''`) returns the caller, the active members of the caller's communities, the people in the caller's conversations, the caller's review counterparts, and, since Community Release 1 (`20261021_0001` Block 1), **the active members of every listed, unarchived community, for every signed-in caller**, so a signed-in visitor reads the same names and photos a guest already reads (the community page shows the poster of a listed request). The same function gates `get_profile_stats`, `get_user_stats`, `get_user_badges` and `is_user_approved`. Members of private communities stay visible only to people who share a community with them (probe `listed_profiles`). The set grows with listed membership; revisit its cost for town-sized communities, and Release 2 must leave `is_test` communities out of this arm for non-members.

#### 2.1.2 Common policy patterns

Three idioms recur across most tables. Documented here once instead of repeated in every section:

- **`is_active_user(auth.uid())`** — SECURITY DEFINER helper meaning "approved AND not banned". This is the standard INSERT/CREATE gate on user-generated content (rides, favors, messages, reviews, town hall posts). Replaces the older "approved-only" check from earlier migrations.
- **`is_admin_user(auth.uid())`** — SECURITY DEFINER helper. Returns true if the caller has `is_admin = true` on their profile.
- **Content-moderation hide pattern (`hidden_at IS NULL OR <author>`)** — added by `20260403_0011_content_moderation_redesign.sql`. SELECT policies on `messages`, `rides`, `favors`, `town_hall_posts`, `town_hall_comments` filter hidden rows from everyone except the author, who can still see their own hidden content (so they get the "this was hidden" affordance).
- **Guest-mode anon SELECT policies** — added by `20260320_0001_guest_mode_anon_read_policies.sql`. Tables that are browseable without an account (`rides`, `favors`, `town_hall_posts`, `request_qa`, `reviews`) have a dedicated `*_select_anon_guest` (or similarly named) policy `TO anon`. Auth-required actions remain gated by the authenticated-role policies.

### 2.2 rides

Rides are visible to authenticated users (with hide-state filter) and to anon guests (visible rows only). Inserts require an active user (approved + not banned). Updates split between owner-edit and claim-flow (open→confirmed via `Authenticated users can claim open rides`, confirmed→open via `Claimers can unclaim rides`).

| Policy | Op | Roles | USING / CHECK |
|---|---|---|---|
| `Authenticated users can view visible or own hidden rides` | SELECT | authenticated | `hidden_at IS NULL OR user_id = auth.uid()` |
| `Guests can view visible rides` | SELECT | anon | `hidden_at IS NULL` |
| `rides_insert_active_user` | INSERT | (all) | CHECK `auth.uid() = user_id AND is_active_user(auth.uid())` |
| `Users can update own or claimed rides` | UPDATE | (all) | `auth.uid() = user_id OR auth.uid() = claimed_by` |
| `Users can update their own rides` | UPDATE | authenticated | `user_id = auth.uid()` (subset of the above; redundant) |
| `Authenticated users can claim open rides` | UPDATE | (all) | USING `claimed_by IS NULL AND status = 'open' AND user_id <> auth.uid()`, CHECK `claimed_by = auth.uid() AND status = 'confirmed'` |
| `Claimers can unclaim rides` | UPDATE | (all) | USING `claimed_by = auth.uid() AND status = 'confirmed'`, CHECK `claimed_by IS NULL AND status = 'open'` |
| `Users can delete own rides` | DELETE | (all) | `auth.uid() = user_id` |

> The two UPDATE policies that overlap (`Users can update own or claimed rides` and `Users can update their own rides`) are a known minor cleanup target — both are PERMISSIVE so they OR together; effective permission is the broader `auth.uid() = user_id OR auth.uid() = claimed_by`. Removing the narrower one is a low-risk follow-up.

### 2.3 favors

Mirror of `rides`. Same 8 policies with names substituting `favors`/`favor_status` where applicable.

| Policy | Op | Roles | USING / CHECK |
|---|---|---|---|
| `Authenticated users can view visible or own hidden favors` | SELECT | authenticated | `hidden_at IS NULL OR user_id = auth.uid()` |
| `Guests can view visible favors` | SELECT | anon | `hidden_at IS NULL` |
| `favors_insert_active_user` | INSERT | (all) | CHECK `auth.uid() = user_id AND is_active_user(auth.uid())` |
| `Users can update own or claimed favors` | UPDATE | (all) | `auth.uid() = user_id OR auth.uid() = claimed_by` |
| `Users can update their own favors` | UPDATE | authenticated | `user_id = auth.uid()` (redundant subset) |
| `Authenticated users can claim open favors` | UPDATE | (all) | USING `claimed_by IS NULL AND status = 'open' AND user_id <> auth.uid()`, CHECK `claimed_by = auth.uid() AND status = 'confirmed'` |
| `Claimers can unclaim favors` | UPDATE | (all) | USING `claimed_by = auth.uid() AND status = 'confirmed'`, CHECK `claimed_by IS NULL AND status = 'open'` |
| `Users can delete own favors` | DELETE | (all) | `auth.uid() = user_id` |

### 2.4 ride_participants

Participants are visible to all approved users. Only the ride owner may add or remove participants, and the `added_by` column must equal the caller — this prevents the ride owner from impersonating attribution.

| Policy | Op | USING / CHECK |
|---|---|---|
| `ride_participants_select` | SELECT | caller is approved (via `profiles.approved`) |
| `ride_participants_insert` | INSERT | CHECK ride owner is `auth.uid()` AND `added_by = auth.uid()` |
| `ride_participants_delete` | DELETE | ride owner is `auth.uid()` |

### 2.5 favor_participants

Mirror of `ride_participants`.

| Policy | Op | USING / CHECK |
|---|---|---|
| `favor_participants_select` | SELECT | caller is approved |
| `favor_participants_insert` | INSERT | CHECK favor owner is `auth.uid()` AND `added_by = auth.uid()` |
| `favor_participants_delete` | DELETE | favor owner is `auth.uid()` |

### 2.6 request_qa

| Policy | Op | Roles | USING / CHECK |
|---|---|---|---|
| `Approved users can view Q&A` | SELECT | (all) | caller is approved |
| `request_qa_select_anon_guest` | SELECT | anon | `true` (guest browseable) |
| `Approved users can create Q&A` | INSERT | (all) | CHECK caller is approved AND `auth.uid() = user_id` |
| `Users can delete own Q&A` | DELETE | (all) | `auth.uid() = user_id` |

### 2.7 messages

Two policies — but the SELECT policy is the most subtle in the database and it does three things at once. Read it carefully before changing it.

| Policy | Op | Roles | USING / CHECK |
|---|---|---|---|
| `Users can view messages in their conversations` | SELECT | authenticated | (1) caller is in `conversation_participants` for this conversation, (2) `messages.created_at` is within `[joined_at, left_at]` of the caller's participant row, (3) `hidden_at IS NULL OR from_id = auth.uid()` |
| `Users can send messages in their conversations` | INSERT | (all) | CHECK `from_id = auth.uid()` AND `is_active_user(auth.uid())` AND (caller is the conversation creator OR caller is an active participant with `left_at IS NULL`) |

```sql
-- The SELECT policy in full — drop or modify with extreme care.
CREATE POLICY "Users can view messages in their conversations"
ON public.messages FOR SELECT TO authenticated
USING (
  EXISTS (
    SELECT 1 FROM public.conversation_participants cp
    WHERE cp.conversation_id = messages.conversation_id
      AND cp.user_id = auth.uid()
      AND messages.created_at >= cp.joined_at
      AND (cp.left_at IS NULL OR messages.created_at <= cp.left_at)
  )
  AND (messages.hidden_at IS NULL OR messages.from_id = auth.uid())
);
```

Why the `joined_at` / `left_at` window matters: when a user is added to an existing group conversation they only see messages from that point forward; if they leave they only see messages up to the moment they left. Removing this window would either back-leak history to new joiners or front-leak messages to past members.

### 2.8 conversations

A user has access if they are the creator OR a current participant. Two SELECT and two UPDATE policies are present — they OR together as PERMISSIVE policies.

| Policy | Op | Roles | USING / CHECK |
|---|---|---|---|
| `users_can_view_their_conversations` | SELECT | authenticated | caller is in `conversation_participants` |
| `conversations_select_creator` | SELECT | (all) | `created_by = auth.uid()` |
| `conversations_insert_approved` | INSERT | (all) | CHECK caller is approved AND `created_by = auth.uid()` |
| `conversations_update_creator` | UPDATE | (all) | `created_by = auth.uid()` |
| `participants_can_update_conversations` | UPDATE | authenticated | caller is in `conversation_participants` |
| `conversations_delete_creator` | DELETE | (all) | `created_by = auth.uid()` |

### 2.9 conversation_participants

Reads use a SECURITY DEFINER helper to avoid infinite recursion (the policy needs to query the same table it protects).

```sql
-- Helper used by the SELECT policy.
CREATE OR REPLACE FUNCTION public.is_conversation_participant(
  p_conversation_id UUID,
  p_user_id UUID
) RETURNS BOOLEAN
LANGUAGE sql SECURITY DEFINER STABLE
AS $$
  SELECT EXISTS (
    SELECT 1 FROM public.conversation_participants
    WHERE conversation_id = p_conversation_id AND user_id = p_user_id
  );
$$;
```

| Policy | Op | Roles | USING / CHECK |
|---|---|---|---|
| `users_can_view_participants_in_their_conversations` | SELECT | authenticated | `is_conversation_participant(conversation_id, auth.uid())` |
| `authenticated_users_can_add_participants` | INSERT | authenticated | CHECK `user_id = auth.uid()` (self-join) OR caller is the conversation creator |
| `Users can update own participant record` | UPDATE | (all) | `user_id = auth.uid()` |
| `users_can_remove_themselves` | DELETE | authenticated | `user_id = auth.uid()` |

### 2.10 notifications

Despite its name, `notifications_insert_service_only` is a self-only check, not a service-role-only check. Cross-user notification inserts (the legitimate path) are issued by SECURITY DEFINER triggers/RPCs which run as `postgres` and bypass RLS — those don't need a policy. The named policy here exists as a defense-in-depth denial for client-direct INSERTs.

| Policy | Op | Roles | USING / CHECK |
|---|---|---|---|
| `notifications_select_own` | SELECT | (all) | `user_id = auth.uid()` |
| `notifications_update_own` | UPDATE | (all) | `user_id = auth.uid()` |
| `notifications_insert_service_only` | INSERT | authenticated | CHECK `auth.uid() = user_id` (denies cross-user direct inserts; legitimate cross-user inserts go through SECURITY DEFINER paths) |

### 2.11 invite_codes

**Status (2026-10-19):** since Phase 5a no client code reads or writes this table; community invites (`community_invites` and the community RPCs) are the only codes. File C (`20261019_0061`) dropped the table on 2026-10-20: the owner ran it in the SQL editor after confirming from App Store Connect that no pre-community build remains in use. The table, its policies, `validate_invite_code()` and `mark_invite_code_used()` no longer exist, and `delete_user_account()` no longer references the table. The policies below are kept as a record of the retired table.

The redemption flow has a non-obvious split: the `invite_codes_update_mark_as_used` policy lets *any* authenticated user transition an unused code to "used by self" — that's how strangers redeem the code they were given. There is a row-level UPDATE on the lookup, not an INSERT into a redemptions table.

| Policy | Op | Roles | USING / CHECK |
|---|---|---|---|
| `Users can view own created codes` | SELECT | (all) | `created_by = auth.uid()` |
| `Users can view unused codes` | SELECT | (all) | `used_at IS NULL` (allows anonymous lookup during signup) |
| `Approved users can create invite codes` | INSERT | (all) | CHECK caller is approved |
| `invite_codes_insert_allowed` | INSERT | (all) | CHECK either (bulk-code redemption: `used_by = auth.uid() AND bulk_code_id IS NOT NULL AND is_bulk = false`) OR (creator-of-row is caller AND caller is approved) |
| `invite_codes_update_mark_as_used` | UPDATE | (all) | USING `used_by IS NULL AND auth.uid() IS NOT NULL`, CHECK `used_by = auth.uid() AND used_at IS NOT NULL` |

### 2.12 push_tokens

Owner-only on every operation.

| Policy | Op | USING / CHECK |
|---|---|---|
| `Users can view own tokens` | SELECT | `auth.uid() = user_id` |
| `Users can create own tokens` | INSERT | CHECK `auth.uid() = user_id` |
| `Users can update own tokens` | UPDATE | `auth.uid() = user_id` |
| `Users can delete own tokens` | DELETE | `auth.uid() = user_id` |

### 2.13 reviews

| Policy | Op | Roles | USING / CHECK |
|---|---|---|---|
| `Approved users can view reviews` | SELECT | (all) | caller is approved |
| `reviews_select_anon_guest` | SELECT | anon | `true` (guest browseable; see the live policy text below for the signed-in policy widened on 2026-10-21) |
| `reviews_insert_active_user` | INSERT | (all) | CHECK `auth.uid() = reviewer_id AND is_active_user(auth.uid())` |

**Live policy text (2026-10-21).** The table above is the pre-community summary. `Approved users can view reviews` reads: the caller is approved, and the caller is the reviewer or the fulfiller, or the review's ride or favor is readable to the caller (the `rides` / `favors` SELECT policies), or `public.is_listed_request(ride_id, favor_id)`. The last arm was added by Community Release 1 (`20261021_0001` Block 3): `is_listed_request` (SECURITY DEFINER, `search_path = ''`, stable) is true when the ride or favor exists, is not hidden, and belongs to a listed, unarchived community, so a signed-in visitor reads the reviews of a listed community's requests, as a guest already does; it does not make the request row itself readable. Because the arm sits inside the approved gate, an account with no active membership does not read them (Release 2 widens this for Get started visitors). `reviews_select_anon_guest` reads `EXISTS` in `guest_rides` or `guest_favors` (the listed, visible requests), not `true`.

### 2.14 town_hall_posts

| Policy | Op | Roles | USING / CHECK |
|---|---|---|---|
| `Authenticated users can view visible or own hidden town hall posts` | SELECT | authenticated | `(hidden_at IS NULL AND caller is approved) OR user_id = auth.uid()` |
| `Guests can view visible town hall posts` | SELECT | anon | `hidden_at IS NULL` |
| `town_hall_posts_insert_active_user` | INSERT | (all) | CHECK `auth.uid() = user_id AND is_active_user(auth.uid())` |
| `Users or admins can delete posts` | DELETE | (all) | `auth.uid() = user_id OR caller is a platform admin OR the post's community is in my_admin_community_ids()` (Phase 3, `20261018_0001`) |

### 2.15 town_hall_comments

Mirror of `town_hall_posts` (§2.14): authenticated approved users see visible rows + their own hidden rows; anon guests see visible rows only; inserts gated by `is_active_user`. Adds an UPDATE policy so users can edit their own comments — `town_hall_posts` does not currently have an analogous UPDATE policy (posts are insert-then-immutable from the client side).

| Policy | Op | Roles | USING / CHECK |
|---|---|---|---|
| `Authenticated users can view visible or own hidden town hall comments` | SELECT | authenticated | `hidden_at IS NULL OR user_id = auth.uid()` |
| `Guests can view visible town hall comments` | SELECT | anon | `hidden_at IS NULL` |
| `town_hall_comments_insert_active_user` | INSERT | (all) | CHECK `auth.uid() = user_id AND is_active_user(auth.uid())` |
| `Users can update own comments` | UPDATE | authenticated | `auth.uid() = user_id` |
| `Users can delete own comments` | DELETE | authenticated | `auth.uid() = user_id` |

### 2.16 town_hall_votes

Owner-write, all-read. The deliberate choice to expose vote rows publicly (`USING true` for SELECT) is what enables vote-count transparency and per-user "you voted X" UI; the privacy tradeoff is that vote authorship is not anonymous.

| Policy | Op | Roles | USING / CHECK |
|---|---|---|---|
| `Users can view all votes` | SELECT | authenticated | `true` |
| `Users can create votes` | INSERT | authenticated | CHECK `auth.uid() = user_id` |
| `Users can update own votes` | UPDATE | authenticated | `auth.uid() = user_id` |
| `Users can delete own votes` | DELETE | authenticated | `auth.uid() = user_id` |

### 2.17 town_hall_post_interactions

Per-user post interactions (e.g. saves, dismissals, "I helped"). Approved users can see all interactions; mutations are owner-only.

| Policy | Op | Roles | USING / CHECK |
|---|---|---|---|
| `interactions_select_approved` | SELECT | authenticated | caller is approved |
| `interactions_insert_own` | INSERT | authenticated | CHECK `user_id = auth.uid()` |
| `interactions_delete_own` | DELETE | authenticated | `user_id = auth.uid()` |

### 2.18 message_reactions

Reactions inherit visibility from messages: a row is visible only if the caller is a participant in the message's conversation. Mutations are owner-only and the INSERT also re-checks conversation participation, so a participant cannot react to a message in a conversation they aren't in (defense-in-depth against forged `message_id`).

This table is part of the active-conversation realtime subscription (see CLAUDE.md → Realtime Rules). RLS gates both the WebSocket-delivered events and the REST hydration path.

| Policy | Op | USING / CHECK |
|---|---|---|
| `message_reactions_select` | SELECT | caller is in `conversation_participants` for the message's conversation (joined to `messages`) |
| `message_reactions_insert` | INSERT | CHECK `user_id = auth.uid()` AND caller is in the message's conversation |
| `message_reactions_update` | UPDATE | `user_id = auth.uid()` |
| `message_reactions_delete` | DELETE | `user_id = auth.uid()` |

### 2.19 typing_indicators

Active-participants only on every operation (`left_at IS NULL`). A user who has been removed from the conversation cannot see or write typing state.

| Policy | Op | Roles | USING / CHECK |
|---|---|---|---|
| `Users can view typing in their conversations` | SELECT | authenticated | caller has an active (`left_at IS NULL`) row in `conversation_participants` |
| `Users can insert own typing indicator` | INSERT | authenticated | CHECK `user_id = auth.uid()` AND caller is an active participant |
| `Users can update own typing indicator` | UPDATE | authenticated | `user_id = auth.uid()` |
| `Users can delete own typing indicator` | DELETE | authenticated | `user_id = auth.uid()` |

### 2.20 reports

User-facing reporting endpoint for the App Store moderation requirement. Three-way SELECT split: reporters see their own reports, reported users see reports filed against them, admins see everything. Updates (status transitions like "resolved" / "dismissed") are admin-only — the client-side report-creation flow never updates an existing row.

| Policy | Op | Roles | USING / CHECK |
|---|---|---|---|
| `Users can view own reports` | SELECT | authenticated | `auth.uid() = reporter_id` |
| `Users can view reports about them` | SELECT | authenticated | `auth.uid() = reported_user_id` |
| `Admins can view all reports` | SELECT | authenticated | caller is admin |
| `Users can create reports` | INSERT | authenticated | CHECK `auth.uid() = reporter_id` |
| `Admins can update reports` | UPDATE | authenticated | caller is admin |

### 2.21 blocked_users

Owner-only on every operation. Blocking is one-directional in the schema (`blocker_id` / `blocked_id`); a `B blocks A` row is invisible to A, which is intentional — A should not be able to detect that they have been blocked.

| Policy | Op | Roles | USING / CHECK |
|---|---|---|---|
| `Users can view own blocks` | SELECT | authenticated | `auth.uid() = blocker_id` |
| `Users can create blocks` | INSERT | authenticated | CHECK `auth.uid() = blocker_id` |
| `Users can delete own blocks` | DELETE | authenticated | `auth.uid() = blocker_id` |

### 2.22 notification_queue

Outbound push-notification queue, processed by edge functions (`send-message-push`, `send-notification`). Service-role-only on every operation — no client (anon or authenticated) has any access. If an APNs send fails the row stays in the queue for retry; client code never reads or writes this table.

| Policy | Op | Roles | USING / CHECK |
|---|---|---|---|
| `notification_queue_select_service_role` | SELECT | service_role | `true` |
| `notification_queue_insert_service_role` | INSERT | service_role | CHECK `true` |
| `notification_queue_update_service_role` | UPDATE | service_role | `true` |

### 2.23 completion_reminders

Scheduled reminders to ride/favor claimers asking them to mark a request complete. Split client/service-role: the claimer reads and updates their own reminder rows (e.g. snooze, dismiss); the service role manages the underlying schedule (insert when a request is claimed, update when the reminder fires).

| Policy | Op | Roles | USING / CHECK |
|---|---|---|---|
| `completion_reminders_select_own` | SELECT | authenticated | `claimer_user_id = auth.uid()` |
| `completion_reminders_update_own` | UPDATE | authenticated | `claimer_user_id = auth.uid()` |
| `completion_reminders_insert_service_only` | INSERT | service_role | CHECK `true` |
| `completion_reminders_update_service_role` | UPDATE | service_role | `true` |

### 2.24 geocoding_cache

**Update (2026-10-19):** the live policies read `is_active_user` in all three operations (the table below says `true`, which is out of date). Since Phase 5a the client reads and writes only through `get_geocoding_multiplier(text)` and `put_geocoding_multiplier(text, numeric, numeric, numeric)` (`20261019_0050`, applied): SECURITY DEFINER, `search_path=""`, an active account is required, the key, the coordinates and the multiplier range (0.9-1.5) are validated, and only the multiplier is returned or stored; no placemark data is written. File D (`20261019_0062`, applied 2026-10-20) revoked direct table access from `anon` and `authenticated`: the three policies below can no longer be reached from a client role, and only the two definer functions touch the table.

Shared cache of address-to-coordinates lookups. Any authenticated user can read or write any row — there's no per-user ownership and no row-level filtering. The cache key is the (address, region) tuple; collisions overwrite.

This is a deliberate trade: cache hit-rate matters more than per-user isolation, the cached values are coarse-grained (lat/lng + display address) and not sensitive, and the alternative (per-user caches) would multiply Google Places API spend. If the data ever becomes sensitive (PII in addresses, per-user prefix searches), this needs revisiting.

| Policy | Op | Roles | USING / CHECK |
|---|---|---|---|
| `geocoding_cache_select_authenticated` | SELECT | authenticated | `true` |
| `geocoding_cache_insert_authenticated` | INSERT | authenticated | CHECK `true` |
| `geocoding_cache_update_authenticated` | UPDATE | authenticated | `true` |

### 2.28 Storage buckets

State read on 2026-10-19: six buckets, all public (`message-images`, `group-images`, `town-hall-images`, `review-images`, `audio-messages`, `avatars`), each with public SELECT policies on `storage.objects`; INSERT, UPDATE and DELETE policies are separate and unchanged by Phase 5.

- **Phase 5a (applied in the client):** the app reads the four image buckets and `audio-messages` through signed URLs (`StorageURLSigner`), with a 1-hour lifetime and an in-memory cache only. A signed URL is never stored in the database, SwiftData, a disk-cache file name or `URLCache`, and is never logged. Avatars stay public. Stored values are unchanged (the plain public URL the upload returned).
- **Phase 5b File E (`20261019_0063`, applied 2026-10-20; the bucket flips and the five new policies through the MCP, the nine `drop policy` statements by the owner in the SQL editor):** the five buckets are private, the old public SELECT policies are dropped, and the public route answers 400. Who can read an object: `message-images`, `group-images` and `audio-messages`, the uploader or a participant of the conversation in the path (including one who left, within their window); `town-hall-images` and `review-images`, the uploader or anyone, guests included, who can read a post or review that names the object (the post's and review's own policies decide). Owners read their own uploads. The gate (no pre-community build in use, and every build in use contains the Phase 5a client, since without it those photos stop loading) was confirmed by the owner from App Store Connect on 2026-10-20.

### 2.25 xp_events

Append-only XP/gamification log used for leaderboards. Read-only from the client (caller sees own rows); writes flow through SECURITY DEFINER triggers and RPCs (e.g. when a request is completed, a review is posted, an invite is redeemed). No client-direct INSERT, UPDATE, or DELETE policies.

| Policy | Op | USING / CHECK |
|---|---|---|
| `Users can read own xp_events` | SELECT | `auth.uid() = user_id` |

### 2.26 Admin Operations

Any operation that requires admin privileges MUST verify via RLS:

```sql
-- Example: Only admins can update other users' approved status
CREATE POLICY "admin_approve_users" ON public.profiles
  FOR UPDATE USING (
    -- Either updating own profile OR is admin updating others
    auth.uid() = id 
    OR EXISTS (SELECT 1 FROM public.profiles WHERE id = auth.uid() AND is_admin = true)
  );

-- Only admins can toggle admin status
-- IMPORTANT: This should be an Edge Function for additional safety
```

#### 2.26.1 Function EXECUTE lockdown (2026-10-05)

RLS does not cover `/rest/v1/rpc`: any function with EXECUTE granted to `anon` or `authenticated` is callable by that role, and SECURITY DEFINER functions run with their owner's privileges. On 2026-10-05, `supabase/migrations/20261005_0001_security_lockdown_definer_functions.sql` applied the following to production:

- EXECUTE revoked from `anon` and `authenticated` on **all trigger functions and internal helpers** (they are only invoked by triggers, cron, other SECURITY DEFINER functions, or edge functions via `service_role`).
- `anon` EXECUTE revoked on **authenticated-only RPCs**. `anon` keeps EXECUTE only on what guest mode and signup genuinely need (`validate_invite_code`, leaderboard/stat getters, RLS helper predicates).
- `upsert_profile_for_signup` **neutralised** — EXECUTE revoked from every API role. It was anon-callable and its `ON CONFLICT DO UPDATE` let any caller overwrite another user's name/email/car given their id. The client uses `create_signup_profile()`, which checks `auth.uid()`. **Pending manual step:** `DROP FUNCTION public.upsert_profile_for_signup(uuid, text, text, text, uuid);` from the SQL editor.

**Pending manual step — not yet applied to production:** `supabase/migrations/20261005_0004_function_caller_guards.sql` (admin-only guard on `send_approval_notification`, self-only guards on `set_typing_status` / `clear_typing_status`) must be run from the Supabase SQL editor; the MCP tool holds `CREATE OR REPLACE` statements for interactive confirmation. Until it runs, those three RPCs are protected only by the `anon` EXECUTE revoke, not by caller checks.

New RPCs must follow the same rule: grant EXECUTE only to the roles that need it, and verify `auth.uid()` inside any function that acts on behalf of a user.

**Community Release 1 (`20261021_0001`, applied 2026-10-21).** Two new functions, both with EXECUTE for `anon`, `authenticated` and `service_role` and none for PUBLIC:

- `public.get_community_preview(p_community_id uuid) → jsonb` (SECURITY DEFINER, stable, `search_path = ''`) is the only way a visitor (a guest or a signed-in non-member) reads a community. It answers only for a listed (`is_public`), unarchived community and otherwise returns `{"success": false, "code": "not_listed"}` (also for a null or unknown id, and for a private community even to its own members). It returns the community's public fields (name, description, join policy, member count, time zone), at most 10 open, unclaimed, visible requests dated today or later (type, title, date, time, seats, poster id, name and avatar), and at most 5 recent visible posts (content cut to 280 characters, comment count). No pickup, destination, location, notes, description of a request, gift, flight or cost key is returned. Banned posters are left out, and for a signed-in caller so is anyone the caller blocked or who blocked the caller. Probe `community_preview`.
- `public.is_listed_request(p_ride_id uuid, p_favor_id uuid) → boolean` (SECURITY DEFINER, stable, `search_path = ''`) is the predicate of the reviews arm in §2.13. It is anon-callable because the policy is `TO public`; it reveals only what a guest can already derive from `guest_rides` / `guest_favors`.

### 2.27 content_moderation_events (audit log)

Append-only audit log of moderation actions: which content (`message`, `town_hall_post`, `town_hall_comment`, `ride`, `favor`) was hidden / dismissed / restored / auto-hidden, by which admin, with what reason, linked to which report. Created by `supabase/migrations/20260403_0011_content_moderation_redesign.sql`. RLS enabled and a single admin-only SELECT policy added in `supabase/migrations/20260502_0001_enable_rls_content_moderation_events.sql` (audit ref: Supabase advisor `rls_disabled_in_public`).

| Policy Name | Operation | Roles | SQL Check |
|---|---|---|---|
| `moderation_events_select_admin` | SELECT | authenticated | `is_admin_user(auth.uid())` |

```sql
ALTER TABLE public.content_moderation_events ENABLE ROW LEVEL SECURITY;

CREATE POLICY "moderation_events_select_admin"
ON public.content_moderation_events FOR SELECT TO authenticated
USING (is_admin_user(auth.uid()));
```

**Insert path:** legitimate inserts come from SECURITY DEFINER RPCs in `20260403_0011` (e.g. `hide_content`, `dismiss_report`, `restore_content`, the auto-hide trigger). Those run as `postgres` (the table owner) and bypass RLS — RLS does not need an INSERT policy. Direct client INSERTs are denied by default.

**UPDATE/DELETE:** blocked by the `content_moderation_events_append_only` trigger from `20260403_0011`, which raises an exception. The trigger catches row-level mutations; RLS adds belt-and-braces denial.

**Pre-fix exposure (now closed):** before `20260502_0001` enabled RLS, anon/authenticated callers with the publishable anon key could `SELECT *` (see who hid what), and could `INSERT` arbitrary rows (planting fake `auto_hide` events into the audit trail).

---

## 3. Credential Management

### 3.1 Supabase Keys

The Supabase anon key is intentionally client-exposed (this is Supabase's design). Security comes from:
1. Row Level Security (RLS) policies
2. Server-side validation

**Requirement SEC-CRED-001**: Apply basic obfuscation to deter casual extraction:

```swift
// Secrets.swift - DO NOT COMMIT TO GIT
import Foundation

enum Secrets {
    // XOR-obfuscated values (not true encryption, but deters casual inspection)
    private static let key: [UInt8] = [0x4E, 0x61, 0x61, 0x72, 0x73] // "Naars"
    
    private static func deobfuscate(_ encoded: [UInt8]) -> String {
        let decoded = encoded.enumerated().map { index, byte in
            byte ^ key[index % key.count]
        }
        return String(bytes: decoded, encoding: .utf8) ?? ""
    }
    
    // Obfuscated URL bytes (generate with helper script)
    private static let urlBytes: [UInt8] = [/* generated bytes */]
    
    // Obfuscated anon key bytes (generate with helper script)
    private static let anonKeyBytes: [UInt8] = [/* generated bytes */]
    
    static var supabaseURL: String {
        deobfuscate(urlBytes)
    }
    
    static var supabaseAnonKey: String {
        deobfuscate(anonKeyBytes)
    }
}
```

**Important**: Obfuscation is NOT security. It deters casual inspection only. Real security comes from RLS policies.

### 3.2 Key Rotation

If the anon key needs rotation:
1. Generate new key in Supabase dashboard
2. Update obfuscated bytes in Secrets.swift
3. Release app update
4. Revoke old key after 30 days (allow update propagation)

**Credential rotation required (2026-10-05):** a production `service_role` key was committed to a markdown file in this repository. The file has been redacted, but the key remains in git history and must be treated as compromised and rotated. Recommended path: migrate the app to the `sb_publishable_...` key (and edge functions / webhooks to `sb_secret_...`), then disable the legacy JWT-based keys in the Supabase dashboard. Disabling the legacy keys also invalidates the legacy anon key embedded in the shipped app, so a client release following the steps above must be live before the legacy keys are turned off.

**Update (2026-10-05):** the client moved to the publishable key (`sb_publishable_...`) on 2026-10-05. The legacy `service_role` JWT must be rotated by disabling the legacy keys in the Supabase API settings once the publishable-key build has shipped. Nothing server-side depends on it (webhooks use the Vault secret).

### 3.3 What NOT to Store Client-Side

Never store in the iOS app:
- Supabase service role key
- Database connection strings
- Admin credentials
- API keys for third-party services (use Edge Functions instead)

---

## 4. Admin Authorization

### 4.1 Defense in Depth

Admin operations are protected at three layers:

| Layer | Purpose | Bypassed By |
|-------|---------|-------------|
| Client UI | UX convenience | Memory editing, direct navigation |
| Client verification | Defense in depth | Skilled attacker with modified client |
| Server RLS | Actual security | Nothing (if properly configured) |

### 4.1a Two admin notions

- **Platform admin:** `profiles.is_admin`, checked on the client by `verifyAdminStatus` and on the server by the admin RPCs.
- **Community admin:** the member's role in that community, checked inside each community RPC (the client never decides it). Community admins never see an applicant's email or phone, or who filed a report. They see the reports filed in their community (without the reporter) and can hide, restore or dismiss content there through `get_community_reports` / `moderate_community_content`. Staff matters (a report about an owner or admin of the community), message reports and community reports stay with platform admins. Platform moderation wins: a community decision is recorded in `reports.community_status` / `community_reviewed_at`, never in `status` / `reviewed_*`, so every report stays in the platform queue; a community admin cannot undo a platform decision or the 3-reporter auto-hide, or act on a report a platform admin reviewed. SEC-ADMIN-001 below covers platform operations only.
- Only the user can delete an account, plus, for a default-community applicant with no other membership, a platform admin (INV-M9).

### 4.2 AdminService Implementation

**Requirement SEC-ADMIN-001**: All admin operations MUST verify admin status server-side:

```swift
// Core/Services/AdminService.swift
@MainActor
final class AdminService {
    static let shared = AdminService()
    private let supabase = SupabaseService.shared.client
    
    /// Verify current user is admin before any admin operation
    private func verifyAdminStatus() async throws {
        guard let userId = AuthService.shared.currentUserId else {
            throw AppError.unauthorized
        }
        
        // Fresh check from server, not cached
        let response = try await supabase
            .from("profiles")
            .select("is_admin")
            .eq("id", userId.uuidString)
            .single()
            .execute()
        
        struct AdminCheck: Decodable {
            let isAdmin: Bool
            enum CodingKeys: String, CodingKey {
                case isAdmin = "is_admin"
            }
        }
        
        let check = try JSONDecoder().decode(AdminCheck.self, from: response.data)
        
        guard check.isAdmin else {
            Log.security("Non-admin attempted admin operation: \(userId)")
            throw AppError.unauthorized
        }
    }
    
    func approveUser(userId: UUID) async throws {
        try await verifyAdminStatus()
        // ... implementation
    }
    
    func setAdminStatus(userId: UUID, isAdmin: Bool) async throws {
        try await verifyAdminStatus()
        // ... implementation
    }
    
    func sendBroadcast(title: String, message: String, pinToNotifications: Bool) async throws {
        try await verifyAdminStatus()
        // ... implementation
    }
}
```

### 4.3 Security Logging

**Requirement SEC-ADMIN-002**: Log all admin operation attempts:

```swift
Log.security("Admin operation: \(operation) by \(userId) - \(success ? "SUCCESS" : "DENIED")")
```

Review logs for:
- Failed admin operations from non-admins (possible attack)
- Unusual patterns (many approvals in short time)

---

## 5. Rate Limiting

### 5.1 Client-Side Rate Limiting

**Requirement SEC-RATE-001**: Implement client-side rate limiting:

```swift
// Core/Utilities/RateLimiter.swift
actor RateLimiter {
    static let shared = RateLimiter()
    private var lastActionTime: [String: Date] = [:]
    
    func checkAndRecord(action: String, minimumInterval: TimeInterval) -> Bool {
        let now = Date()
        if let last = lastActionTime[action],
           now.timeIntervalSince(last) < minimumInterval {
            return false
        }
        lastActionTime[action] = now
        return true
    }
}
```

### 5.2 Client-Side Limits

| Action | Minimum Interval | Rationale |
|--------|------------------|-----------|
| Claim/unclaim request | 5 seconds | Prevent toggle spam |
| Send message | 1 second | Prevent flood |
| Generate invite code | 10 seconds | Prevent mass generation |
| Refresh data (pull-to-refresh) | 2 seconds | Prevent API spam |
| Login attempt | 2 seconds | Prevent rapid retries |
| Invite code validation | 3 seconds | Prevent brute force |
| Password reset request | 30 seconds | Prevent enumeration |

### 5.3 Server-Side Rate Limiting

For production deployment, implement server-side rate limiting via Supabase Edge Functions or database triggers:

| Action | Limit | Window | Implementation |
|--------|-------|--------|----------------|
| Claim/unclaim | 3 | 1 minute | Database trigger |
| Messages | 10 | 1 minute | Edge Function |
| Invite validation | 5 | 1 hour | Edge Function with IP tracking |
| Login failures | 5 | 15 minutes | Supabase Auth config |
| Password reset | 3 | 1 hour | Edge Function |
| Invite generation | 5 | 24 hours | Database trigger |
| Announcements | 3 per community | 24 hours | `send_community_broadcast` (platform admins included since `20261018_0002`; counts only announcements by platform admins and community staff) |

### 5.4 Implementation Priority

1. **MVP**: Client-side rate limiting (required)
2. **Pre-launch**: Server-side for auth operations (strongly recommended)
3. **Post-launch**: Server-side for all operations (recommended)

---

## 6. Invite Code Security

**Legacy codes retired (Phase 5a, 2026-10-19):** the `NC` + 8 character codes below were the single-use invite codes of the old sign-up flow. No client code generates, validates or redeems them any more, and File C (`20261019_0061`, applied 2026-10-20) dropped the table. Community invites are the only codes. The generator shown below was deleted with the client code and is kept as a record of the format.

### 6.1 Code Format

- Format: `NC` + 8 alphanumeric characters (uppercase)
- Character set: A-Z, 0-9 (excluding confusing: 0/O, 1/I/L)
- Effective set: 32 characters
- Combinations: 32^8 = ~1.1 trillion

```swift
enum InviteCodeGenerator {
    private static let characters = Array("ABCDEFGHJKMNPQRSTUVWXYZ23456789")
    
    static func generate() -> String {
        var code = "NC"
        for _ in 0..<8 {
            let randomIndex = Int.random(in: 0..<characters.count)
            code.append(characters[randomIndex])
        }
        return code
    }
}
```

### 6.1a Invite Links (Phase 4)

- A join link is `https://naarscars.com/join#<code>`. The code is in the URL fragment only, so it is not sent to the web server, not put in a Referer, and not written to server logs.
- The app saves a received code on the device (`PendingInviteStore`, in the app's own storage) until it is redeemed or 7 days pass, then discards it. It is never logged.
- The landing page loads no third-party script and sends `Referrer-Policy: no-referrer`.
- Entitlement: Associated Domains, `applinks:naarscars.com` only (not `www`). The `apple-app-site-association` file lists the paths `/join` and `/join/`.

### 6.2 Brute Force Protection

1. **Rate limiting**: 5 attempts per hour per device (see section 5)
2. **Uniform errors**: Don't reveal if code exists but is used
3. **Strong randomness**: Use cryptographic random generation

### 6.3 Error Messages

| Scenario | User-Facing Message |
|----------|---------------------|
| Code doesn't exist | "Invalid or expired invite code" |
| Code already used | "Invalid or expired invite code" |
| Rate limited | "Too many attempts. Please try again later." |

---

## 7. Push Token Security

### 7.1 Token Storage

- Tokens stored in `push_tokens` table
- RLS ensures users can only see/modify their own tokens
- `device_id` prevents token accumulation from same device

### 7.2 Token Cleanup

Server-side cleanup job (weekly):

```sql
-- Remove tokens older than 90 days
DELETE FROM push_tokens 
WHERE last_used_at < NOW() - INTERVAL '90 days'
   OR (last_used_at IS NULL AND created_at < NOW() - INTERVAL '90 days');
```

### 7.3 APNs Invalid Token Handling

When APNs returns 410 (Unregistered), immediately delete token:

```javascript
// In Edge Function sending push
if (apnsResponse.status === 410) {
    await supabase.from('push_tokens').delete().eq('token', token);
}
```

### 7.4 Webhook Authentication

Database webhooks that invoke the edge functions (`send-message-push`, `send-notification`) carry **no API key in the trigger definition**. The generic trigger function `public.invoke_edge_webhook()` reads a shared secret (`edge_webhook_secret`) from Supabase Vault at fire time and sends it in an `x-webhook-secret` header. On the receiving side, `supabase/functions/_shared/webhookAuth.ts` accepts a request only if it presents the service-role key as a bearer token (internal / cron callers) or an `x-webhook-secret` that the `service_role`-only RPC `verify_webhook_secret(p_secret)` confirms against Vault; anything else gets a 401. Because both sides read the secret from Vault, rotating it is a Vault update — no trigger or function redeploy. Introduced in `supabase/migrations/20261005_0002_webhook_shared_secret.sql`.

---

## 8. Security Logging

### 8.1 Log Categories

```swift
enum Log {
    static func security(_ message: String) {
        print("🔒 [SECURITY] \(message)")
        // In production: send to analytics/monitoring service
    }
}
```

### 8.2 Events to Log

| Event | Log Level | Example |
|-------|-----------|---------|
| Admin operation attempt | Security | "Admin operation: approve_user by UUID - SUCCESS/DENIED" |
| Rate limit triggered | Warning | "Rate limit: claim action by UUID" |
| Auth failure | Info | "Login failed for email@example.com" |
| Invite code attempt | Security | "Invite code attempt: NC•••••••• - INVALID" |
| Session expired | Info | "Session expired for UUID" |

---

## 9. Pre-Launch Security Checklist

### 9.1 RLS Policies

- [ ] All tables have RLS enabled
- [ ] All policies created per this document
- [ ] Tested: Non-owner cannot read private data
- [ ] Tested: Non-owner cannot modify others' data
- [ ] Tested: Non-admin cannot perform admin actions
- [ ] Tested: Unapproved user cannot access approved-only content

### 9.2 Client Security

- [ ] Credentials obfuscated in Secrets.swift
- [ ] Secrets.swift in .gitignore
- [ ] Rate limiter implemented
- [ ] AdminService verifies status server-side
- [ ] Security logging implemented

### 9.3 Server Security

- [ ] Server-side rate limiting for auth operations
- [ ] Push token cleanup scheduled
- [ ] APNs invalid token handling implemented

---

## 10. Incident Response

If a security issue is discovered:

1. **Assess severity**: Data exposed? Users affected?
2. **Contain**: Disable affected feature if necessary
3. **Notify**: Inform team immediately
4. **Fix**: Deploy patch ASAP
5. **Communicate**: Notify affected users if required
6. **Review**: Post-incident analysis

---

*End of Security Requirements*
