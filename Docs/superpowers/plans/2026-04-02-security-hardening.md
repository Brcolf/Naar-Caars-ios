# Security Hardening Implementation Plan (Live-DB-Corrected)

> **For agentic workers:** REQUIRED SUB-SKILL: Use superpowers:subagent-driven-development (recommended) or superpowers:executing-plans to implement this plan task-by-task. Steps use checkbox (`- [ ]`) syntax for tracking.

**Goal:** Fix all launch-blocking security vulnerabilities identified in the adjudicated dual-audit (Claude + ChatGPT), corrected against live Supabase MCP state on 2026-04-03.

**Architecture:** Two batches ordered by risk of breaking app flows. Batch 1 is pure backend SQL — safe to apply without client changes. Batch 2 requires coordinated backend + Swift client changes.

**Tech Stack:** PostgreSQL (Supabase migrations), TypeScript (Supabase Edge Functions), Swift (iOS client)

**Live DB verification date:** 2026-04-03 via Supabase MCP (`execute_sql` against `pg_policies`, `routine_privileges`, `pg_proc`, `pg_indexes`)

---

## Live DB Findings That Changed The Plan

These findings corrected stale repo-based assumptions:

| Item | Repo Said | Live Reality | Plan Impact |
|------|-----------|--------------|-------------|
| `conversation_participants` RLS | Disabled (CRIT-6) | Enabled, participant-scoped SELECT via `is_conversation_participant()`, own-row UPDATE/DELETE | **Removed from critical findings** |
| `message_reactions` SELECT | `USING(true)` (HIGH-3) | Participant-scoped via join through messages + conversation_participants | **Removed from findings** |
| `completion_reminders` RLS | Not enabled (HIGH-4) | Enabled, but INSERT `true` and UPDATE `true` for authenticated | **Rewritten: tighten policies** |
| `messages` SELECT | Checks `joined_at` not `left_at` | Checks **neither** — only conversation participation | **Rewritten: add both bounds** |
| Function grants | Varied per repo GRANTs | **ALL functions: PUBLIC + anon + authenticated** | **Added bulk grant revocation task** |

---

## File Structure

### Batch 1: Server-Only Safe Fixes
- Create: `supabase/migrations/20260403_0001_security_broadcast_admin_check.sql`
- Create: `supabase/migrations/20260403_0002_security_blocking_rpcs_auth_guard.sql`
- Create: `supabase/migrations/20260403_0003_security_review_uniqueness.sql`
- Create: `supabase/migrations/20260403_0004_security_notify_deny_default.sql`
- Create: `supabase/migrations/20260403_0005_security_storage_owner_policies.sql`
- Create: `supabase/migrations/20260403_0006_security_messages_select_bounds.sql`
- Create: `supabase/migrations/20260403_0007_security_completion_reminders_tighten.sql`
- Create: `supabase/migrations/20260403_0008_security_bulk_grant_revocations.sql`

### Batch 2: Coordinated Backend + Client Fixes
- Create: `supabase/migrations/20260403_0010_security_message_edit_unsend_rls.sql`
- Modify: `NaarsCars/Core/Services/MessageService.swift:688-723`
- Create: `supabase/migrations/20260403_0011_security_signup_profile_auth_guard.sql`
- Create: `supabase/migrations/20260403_0012_security_invite_code_auth_guard.sql`
- Create: `supabase/migrations/20260403_0013_security_notification_rpcs_redesign.sql`
- Create: `supabase/migrations/20260403_0014_security_profiles_projection_view.sql`
- Modify: Multiple Swift files querying profiles
- Modify: `supabase/functions/send-notification/index.ts`
- Modify: `supabase/functions/send-message-push/index.ts`

---

## Batch 1: Server-Only Safe Fixes

These can be applied without any Swift client changes. Each fix is backward-compatible — the app already passes correct values through normal code paths.

### Task 1: Add Admin Check to `send_broadcast_notifications`

**Audit finding:** CRIT-2 — Any authenticated user can broadcast to all members.
**Live confirmed:** Function has no `is_admin` check. Granted to PUBLIC + anon + authenticated.

**Files:**
- Create: `supabase/migrations/20260403_0001_security_broadcast_admin_check.sql`

**Why this is safe:** The app only calls this from `AdminService.sendBroadcast()` which already verifies admin status client-side. Adding the server-side check means the same call succeeds for admins and now correctly rejects non-admins.

- [ ] **Step 1: Write the migration**

```sql
-- Security fix: Add server-side admin check to send_broadcast_notifications.
-- Live state: SECURITY DEFINER, no is_admin check, granted to PUBLIC/anon/authenticated.
-- Audit ref: CRIT-2 — any authenticated user could broadcast to all members.

CREATE OR REPLACE FUNCTION public.send_broadcast_notifications(
    p_title TEXT,
    p_body TEXT,
    p_type TEXT DEFAULT 'broadcast',
    p_pinned BOOLEAN DEFAULT false
)
RETURNS INTEGER
LANGUAGE plpgsql
SECURITY DEFINER
SET search_path TO 'public'
AS $$
DECLARE
    v_admin_id UUID;
    v_post_id UUID;
    v_user_id UUID;
    v_count INTEGER := 0;
    v_notification_id UUID;
BEGIN
    v_admin_id := auth.uid();

    -- SECURITY FIX: Verify caller is an admin
    IF NOT EXISTS (
        SELECT 1 FROM profiles
        WHERE id = v_admin_id AND is_admin = true
    ) THEN
        RAISE EXCEPTION 'Only admins can send broadcast notifications';
    END IF;

    INSERT INTO town_hall_posts (
        user_id, title, content, pinned, type, created_at, updated_at
    ) VALUES (
        v_admin_id, p_title, p_body, p_pinned, 'announcement', NOW(), NOW()
    )
    RETURNING id INTO v_post_id;

    FOR v_user_id IN
        SELECT id FROM profiles WHERE approved = true
    LOOP
        IF v_user_id != v_admin_id THEN
            INSERT INTO notifications (
                user_id, type, title, body, read, pinned,
                town_hall_post_id, source_user_id, created_at
            ) VALUES (
                v_user_id, p_type, p_title, p_body, false, p_pinned,
                v_post_id, v_admin_id, NOW()
            )
            RETURNING id INTO v_notification_id;

            v_count := v_count + 1;
        END IF;
    END LOOP;

    RETURN v_count;
END;
$$;

-- Tighten grants: revoke public/anon, keep authenticated (function enforces admin)
REVOKE ALL ON FUNCTION public.send_broadcast_notifications FROM PUBLIC;
REVOKE ALL ON FUNCTION public.send_broadcast_notifications FROM anon;
GRANT EXECUTE ON FUNCTION public.send_broadcast_notifications TO authenticated;
GRANT EXECUTE ON FUNCTION public.send_broadcast_notifications TO service_role;
```

- [ ] **Step 2: Apply migration via Supabase MCP `apply_migration`**

- [ ] **Step 3: Verify — query live function definition to confirm admin check present**

- [ ] **Step 4: Commit**

```bash
git add supabase/migrations/20260403_0001_security_broadcast_admin_check.sql
git commit -m "security: add server-side admin check to send_broadcast_notifications

Audit ref: CRIT-2. Live-verified: function had no is_admin check and was
granted to PUBLIC/anon/authenticated. Now enforces is_admin = true and
revokes anon/PUBLIC grants."
```

---

### Task 2: Add Auth Guards to Blocking RPCs

**Audit finding:** CRIT-5 (partial) — `block_user`, `unblock_user`, `get_blocked_users` accept arbitrary user IDs.
**Live confirmed:** All three granted to PUBLIC + anon + authenticated. No auth.uid() check.

**Files:**
- Create: `supabase/migrations/20260403_0002_security_blocking_rpcs_auth_guard.sql`

**Why this is safe:** The app always passes `AuthService.shared.currentUserId` as `p_blocker_id` / `p_user_id`.

- [ ] **Step 1: Write the migration**

```sql
-- Security fix: Add auth.uid() validation to blocking RPCs + tighten grants.
-- Live state: All three granted to PUBLIC/anon/authenticated, no caller validation.
-- Audit ref: CRIT-5.

CREATE OR REPLACE FUNCTION public.block_user(
    p_blocker_id UUID,
    p_blocked_id UUID,
    p_reason TEXT DEFAULT NULL
) RETURNS BOOLEAN AS $$
BEGIN
    IF auth.uid() IS NULL OR auth.uid() != p_blocker_id THEN
        RAISE EXCEPTION 'Blocker ID must match authenticated user';
    END IF;

    IF p_blocker_id = p_blocked_id THEN
        RAISE EXCEPTION 'Cannot block yourself';
    END IF;

    INSERT INTO public.blocked_users (blocker_id, blocked_id, reason)
    VALUES (p_blocker_id, p_blocked_id, p_reason)
    ON CONFLICT (blocker_id, blocked_id) DO NOTHING;

    RETURN TRUE;
END;
$$ LANGUAGE plpgsql SECURITY DEFINER SET search_path TO 'public';

CREATE OR REPLACE FUNCTION public.unblock_user(
    p_blocker_id UUID,
    p_blocked_id UUID
) RETURNS BOOLEAN AS $$
BEGIN
    IF auth.uid() IS NULL OR auth.uid() != p_blocker_id THEN
        RAISE EXCEPTION 'Blocker ID must match authenticated user';
    END IF;

    DELETE FROM public.blocked_users
    WHERE blocker_id = p_blocker_id AND blocked_id = p_blocked_id;

    RETURN TRUE;
END;
$$ LANGUAGE plpgsql SECURITY DEFINER SET search_path TO 'public';

CREATE OR REPLACE FUNCTION public.get_blocked_users(
    p_user_id UUID
) RETURNS TABLE (
    blocked_id UUID,
    blocked_name TEXT,
    blocked_avatar_url TEXT,
    blocked_at TIMESTAMPTZ,
    reason TEXT
) AS $$
BEGIN
    IF auth.uid() IS NULL OR auth.uid() != p_user_id THEN
        RAISE EXCEPTION 'User ID must match authenticated user';
    END IF;

    RETURN QUERY
    SELECT bu.blocked_id, p.name, p.avatar_url, bu.created_at, bu.reason
    FROM public.blocked_users bu
    JOIN public.profiles p ON p.id = bu.blocked_id
    WHERE bu.blocker_id = p_user_id
    ORDER BY bu.created_at DESC;
END;
$$ LANGUAGE plpgsql SECURITY DEFINER SET search_path TO 'public';

-- Tighten grants
REVOKE ALL ON FUNCTION public.block_user FROM PUBLIC;
REVOKE ALL ON FUNCTION public.block_user FROM anon;
GRANT EXECUTE ON FUNCTION public.block_user TO authenticated;
GRANT EXECUTE ON FUNCTION public.block_user TO service_role;

REVOKE ALL ON FUNCTION public.unblock_user FROM PUBLIC;
REVOKE ALL ON FUNCTION public.unblock_user FROM anon;
GRANT EXECUTE ON FUNCTION public.unblock_user TO authenticated;
GRANT EXECUTE ON FUNCTION public.unblock_user TO service_role;

REVOKE ALL ON FUNCTION public.get_blocked_users FROM PUBLIC;
REVOKE ALL ON FUNCTION public.get_blocked_users FROM anon;
GRANT EXECUTE ON FUNCTION public.get_blocked_users TO authenticated;
GRANT EXECUTE ON FUNCTION public.get_blocked_users TO service_role;
```

- [ ] **Step 2: Apply migration**

- [ ] **Step 3: Verify from app — blocking/unblocking should work identically**

- [ ] **Step 4: Commit**

```bash
git add supabase/migrations/20260403_0002_security_blocking_rpcs_auth_guard.sql
git commit -m "security: add auth.uid() guards to blocking RPCs, revoke PUBLIC/anon

Audit ref: CRIT-5. Live-verified: all three functions callable by anon
with no caller validation."
```

---

### Task 3: Add Review Uniqueness Constraints

**Audit finding:** HIGH-6. **Live confirmed:** No unique indexes on reviews beyond PK.

**Files:**
- Create: `supabase/migrations/20260403_0003_security_review_uniqueness.sql`

**Why this is safe:** App UI already hides "Leave a Review" when one exists.

- [ ] **Step 1: Write the migration**

```sql
-- Security fix: Add uniqueness constraints for reviews.
-- Live confirmed: only PK index exists, no unique on reviewer+request.
-- Audit ref: HIGH-6.

-- Remove existing duplicates (keep earliest)
DELETE FROM reviews r1
USING reviews r2
WHERE r1.ride_id IS NOT NULL
  AND r1.ride_id = r2.ride_id
  AND r1.reviewer_id = r2.reviewer_id
  AND r1.created_at > r2.created_at;

DELETE FROM reviews r1
USING reviews r2
WHERE r1.favor_id IS NOT NULL
  AND r1.favor_id = r2.favor_id
  AND r1.reviewer_id = r2.reviewer_id
  AND r1.created_at > r2.created_at;

CREATE UNIQUE INDEX IF NOT EXISTS idx_reviews_unique_ride_reviewer
ON reviews (reviewer_id, ride_id) WHERE ride_id IS NOT NULL;

CREATE UNIQUE INDEX IF NOT EXISTS idx_reviews_unique_favor_reviewer
ON reviews (reviewer_id, favor_id) WHERE favor_id IS NOT NULL;
```

- [ ] **Step 2: Apply migration**
- [ ] **Step 3: Verify indexes exist live**
- [ ] **Step 4: Commit**

```bash
git add supabase/migrations/20260403_0003_security_review_uniqueness.sql
git commit -m "security: add unique constraints — one review per reviewer per request

Audit ref: HIGH-6. Live-verified: no uniqueness indexes existed."
```

---

### Task 4: Change `should_notify_user()` to Deny by Default

**Audit finding:** Tier 3 #18. **Live confirmed via grants:** callable by PUBLIC/anon/authenticated.

**Files:**
- Create: `supabase/migrations/20260403_0004_security_notify_deny_default.sql`

- [ ] **Step 1: Write the migration**

```sql
-- Security fix: Change should_notify_user() ELSE branch from true to false.
-- Audit ref: Tier 3 #18.

CREATE OR REPLACE FUNCTION public.should_notify_user(
    p_user_id UUID,
    p_notification_type TEXT
) RETURNS BOOLEAN
LANGUAGE plpgsql
SECURITY DEFINER
SET search_path TO 'public'
AS $$
DECLARE
    v_profile RECORD;
BEGIN
    SELECT * INTO v_profile FROM profiles WHERE id = p_user_id;
    IF NOT FOUND THEN RETURN false; END IF;

    CASE p_notification_type
        WHEN 'new_ride', 'new_favor' THEN RETURN true;
        WHEN 'announcement', 'admin_announcement', 'broadcast' THEN RETURN true;
        WHEN 'user_approved', 'user_rejected' THEN RETURN true;
        WHEN 'pending_approval' THEN RETURN v_profile.is_admin;
        WHEN 'message', 'added_to_conversation' THEN RETURN v_profile.notify_messages;
        WHEN 'ride_update', 'ride_claimed', 'ride_unclaimed', 'ride_completed',
             'favor_update', 'favor_claimed', 'favor_unclaimed', 'favor_completed'
            THEN RETURN v_profile.notify_ride_updates;
        WHEN 'qa_activity', 'qa_question', 'qa_answer' THEN RETURN v_profile.notify_qa_activity;
        WHEN 'review', 'review_received', 'review_reminder', 'review_request', 'completion_reminder'
            THEN RETURN v_profile.notify_review_reminders;
        WHEN 'town_hall_post', 'town_hall_comment', 'town_hall_reaction'
            THEN RETURN v_profile.notify_town_hall;
        ELSE
            RETURN false;  -- SECURITY FIX: deny-by-default for unknown types
    END CASE;
END;
$$;
```

- [ ] **Step 2: Apply migration**
- [ ] **Step 3: Commit**

```bash
git add supabase/migrations/20260403_0004_security_notify_deny_default.sql
git commit -m "security: should_notify_user() deny-by-default for unknown types

Audit ref: Tier 3 #18. ELSE branch returned true, allowing unknown
notification types to bypass preference checks."
```

---

### Task 5: Tighten Storage Bucket Write/Delete Policies

**Audit finding:** HIGH-2. **Live confirmed:** group-images UPDATE/DELETE and audio-messages DELETE are bucket-wide with no owner check.

**Files:**
- Create: `supabase/migrations/20260403_0005_security_storage_owner_policies.sql`

- [ ] **Step 1: Write the migration**

```sql
-- Security fix: Restrict storage UPDATE/DELETE to object owner.
-- Live confirmed: bucket-wide policies with no owner check.
-- Audit ref: HIGH-2.

DROP POLICY IF EXISTS "Authenticated users can update group images" ON storage.objects;
DROP POLICY IF EXISTS "Authenticated users can delete group images" ON storage.objects;
DROP POLICY IF EXISTS "Authenticated users can delete audio messages" ON storage.objects;

CREATE POLICY "Owner can update group images"
ON storage.objects FOR UPDATE TO authenticated
USING (bucket_id = 'group-images' AND (owner)::uuid = auth.uid())
WITH CHECK (bucket_id = 'group-images' AND (owner)::uuid = auth.uid());

CREATE POLICY "Owner can delete group images"
ON storage.objects FOR DELETE TO authenticated
USING (bucket_id = 'group-images' AND (owner)::uuid = auth.uid());

CREATE POLICY "Owner can delete audio messages"
ON storage.objects FOR DELETE TO authenticated
USING (bucket_id = 'audio-messages' AND (owner)::uuid = auth.uid());
```

- [ ] **Step 2: Apply migration**
- [ ] **Step 3: Verify — upload and delete own image works; attempt cross-user delete fails**
- [ ] **Step 4: Commit**

```bash
git add supabase/migrations/20260403_0005_security_storage_owner_policies.sql
git commit -m "security: restrict storage UPDATE/DELETE to object owner

Audit ref: HIGH-2. Live-verified: group-images and audio-messages
allowed any authenticated user to modify/delete any object."
```

---

### Task 6: Fix Messages SELECT — Add Joined/Left Bounds

**Audit finding:** HIGH-1 (corrected). **Live reality is WORSE than repo:** SELECT checks only participation, no `joined_at` or `left_at` bounds. Former participants see all messages forever.

**Files:**
- Create: `supabase/migrations/20260403_0006_security_messages_select_bounds.sql`

**Why this is safe:** Active participants (`left_at IS NULL`) are unaffected. Only users who have left get their visibility correctly bounded.

- [ ] **Step 1: Write the migration**

```sql
-- Security fix: Add joined_at and left_at bounds to messages SELECT policy.
-- Live state: only checks conversation participation, no time bounds.
-- Former participants can read ALL messages in the conversation forever.
-- Audit ref: HIGH-1 (corrected against live — worse than repo).

DROP POLICY IF EXISTS "Users can view messages in their conversations" ON public.messages;

CREATE POLICY "Users can view messages in their conversations" ON public.messages
  FOR SELECT TO authenticated
  USING (
    -- Conversation creator can always read (they own the conversation)
    EXISTS (
      SELECT 1 FROM public.conversations c
      WHERE c.id = messages.conversation_id
        AND c.created_by = auth.uid()
    )
    OR
    -- Participants: bounded by join/leave window
    EXISTS (
      SELECT 1 FROM public.conversation_participants cp
      WHERE cp.conversation_id = messages.conversation_id
        AND cp.user_id = auth.uid()
        AND messages.created_at >= cp.joined_at
        AND (cp.left_at IS NULL OR messages.created_at <= cp.left_at)
    )
  );
```

- [ ] **Step 2: Apply migration**
- [ ] **Step 3: Verify — active participants see all messages; test with a user who has left**
- [ ] **Step 4: Commit**

```bash
git add supabase/migrations/20260403_0006_security_messages_select_bounds.sql
git commit -m "security: add joined_at/left_at bounds to messages SELECT

Live-verified: policy checked only participation with no time bounds.
Former participants could read all messages forever. Now bounded to
[joined_at, left_at] window."
```

---

### Task 7: Tighten `completion_reminders` Policies + Auth Guard on `handle_completion_response`

**Audit finding:** CRIT-3 + HIGH-4 (corrected for live).

**Live reality (corrected):**
- RLS IS enabled. `completion_reminders_select_own` scopes SELECT to `claimer_user_id = auth.uid()`.
- BUT: INSERT policy is `WITH CHECK (true)` and UPDATE policy is `USING (true) WITH CHECK (true)` — both too broad for authenticated.
- `handle_completion_response` is **NOT SECURITY DEFINER** (`prosecdef = false`). This means internal queries go through RLS, so a non-claimer calling the function gets "Reminder not found" because the SELECT RLS blocks them. The exploit is **narrower than originally stated** — it is not "any user can complete any ride/favor." The real issues are: (1) overly broad INSERT/UPDATE policies, (2) broad EXECUTE grants (PUBLIC + anon), and (3) no explicit caller binding in the function for defense-in-depth.

**Files:**
- Create: `supabase/migrations/20260403_0007_security_completion_reminders_tighten.sql`

**Why this is safe:** App queries filter by `claimer_user_id = userId`. Reminders are created by cron/triggers (service_role), not by app users directly. Tightening INSERT to service_role and UPDATE to own-row won't break the app.

- [ ] **Step 1: Write the migration**

```sql
-- Security fix: Tighten completion_reminders policies and add caller binding
-- to handle_completion_response for defense-in-depth.
--
-- Live state:
--   - RLS enabled, SELECT scoped to claimer_user_id = auth.uid() (good)
--   - INSERT WITH CHECK (true) for authenticated (too broad)
--   - UPDATE USING (true) WITH CHECK (true) for authenticated (too broad)
--   - handle_completion_response is NOT SECURITY DEFINER, so SELECT RLS
--     already blocks non-claimers. But broad policies + grants are still wrong.
-- Audit ref: CRIT-3 (narrowed), HIGH-4 (corrected).

-- Drop overly permissive policies
DROP POLICY IF EXISTS "completion_reminders_insert_service" ON public.completion_reminders;
DROP POLICY IF EXISTS "completion_reminders_update_service" ON public.completion_reminders;

-- INSERT: only service_role (reminders created by cron/triggers, not users)
CREATE POLICY "completion_reminders_insert_service_only"
ON public.completion_reminders FOR INSERT TO service_role
WITH CHECK (true);

-- UPDATE: own reminders only (for snooze via handle_completion_response)
CREATE POLICY "completion_reminders_update_own"
ON public.completion_reminders FOR UPDATE TO authenticated
USING (claimer_user_id = auth.uid())
WITH CHECK (claimer_user_id = auth.uid());

-- UPDATE: service_role can update any (for cron jobs)
CREATE POLICY "completion_reminders_update_service"
ON public.completion_reminders FOR UPDATE TO service_role
USING (true) WITH CHECK (true);

-- Add caller binding to handle_completion_response for defense-in-depth.
-- The function is NOT SECURITY DEFINER, so we make it SECURITY DEFINER
-- to ensure it can update rides/favors (which have their own RLS) while
-- still validating the caller explicitly.
CREATE OR REPLACE FUNCTION public.handle_completion_response(
    p_reminder_id UUID,
    p_completed BOOLEAN
)
RETURNS JSONB
LANGUAGE plpgsql
SECURITY DEFINER
SET search_path TO 'public'
AS $$
DECLARE
    v_reminder RECORD;
    v_request_title TEXT;
    v_requestor_id UUID;
    v_notification_id UUID;
BEGIN
    SELECT * INTO v_reminder FROM completion_reminders WHERE id = p_reminder_id;

    IF NOT FOUND THEN
        RETURN jsonb_build_object('success', false, 'error', 'Reminder not found');
    END IF;

    -- SECURITY FIX: Verify caller is the claimer (defense-in-depth)
    IF auth.uid() IS NULL OR auth.uid() != v_reminder.claimer_user_id THEN
        RAISE EXCEPTION 'Only the claimer can respond to this completion reminder';
    END IF;

    IF p_completed THEN
        IF v_reminder.ride_id IS NOT NULL THEN
            UPDATE rides SET status = 'completed' WHERE id = v_reminder.ride_id;
            SELECT user_id, destination INTO v_requestor_id, v_request_title
            FROM rides WHERE id = v_reminder.ride_id;
        ELSE
            UPDATE favors SET status = 'completed' WHERE id = v_reminder.favor_id;
            SELECT user_id, title INTO v_requestor_id, v_request_title
            FROM favors WHERE id = v_reminder.favor_id;
        END IF;

        UPDATE completion_reminders SET completed = true WHERE id = p_reminder_id;

        v_notification_id := create_notification(
            v_requestor_id, 'review_request', 'How was your experience?',
            'Your request has been completed. Leave a review to thank your helper!',
            v_reminder.ride_id, v_reminder.favor_id, NULL, NULL, NULL, v_reminder.claimer_user_id
        );

        IF v_notification_id IS NOT NULL THEN
            PERFORM queue_push_notification(
                v_requestor_id, 'review_request', 'How was your experience?',
                'Your request has been completed. Leave a review!',
                jsonb_build_object('ride_id', v_reminder.ride_id::text, 'favor_id', v_reminder.favor_id::text, 'action', 'review'),
                NULL, v_notification_id
            );
        END IF;

        RETURN jsonb_build_object('success', true, 'action', 'completed');
    ELSE
        UPDATE completion_reminders
        SET scheduled_for = NOW() + INTERVAL '1 hour',
            reminder_count = reminder_count + 1,
            last_reminded_at = NOW()
        WHERE id = p_reminder_id;

        RETURN jsonb_build_object('success', true, 'action', 'snoozed',
            'next_reminder', NOW() + INTERVAL '1 hour');
    END IF;
END;
$$;

-- Tighten handle_completion_response grants
REVOKE ALL ON FUNCTION public.handle_completion_response FROM PUBLIC;
REVOKE ALL ON FUNCTION public.handle_completion_response FROM anon;
GRANT EXECUTE ON FUNCTION public.handle_completion_response TO authenticated;
GRANT EXECUTE ON FUNCTION public.handle_completion_response TO service_role;
```

- [ ] **Step 2: Apply migration**
- [ ] **Step 3: Verify — test completion reminder response from push notification**
- [ ] **Step 4: Commit**

```bash
git add supabase/migrations/20260403_0007_security_completion_reminders_tighten.sql
git commit -m "security: tighten completion_reminders policies, add auth guard to handle_completion_response

Live-verified: INSERT/UPDATE were WITH CHECK (true) for authenticated.
handle_completion_response was not SECURITY DEFINER and had no caller
binding. Now: INSERT restricted to service_role, UPDATE scoped to
claimer_user_id = auth.uid(), function is SECURITY DEFINER with
explicit claimer validation."
```

---

### Task 8: Bulk Grant Revocations for Dangerous Functions

**Audit finding:** All dangerous functions are callable by PUBLIC + anon.
**Live confirmed:** Every single function in the audit list shows EXECUTE for PUBLIC, anon, and authenticated.

**Files:**
- Create: `supabase/migrations/20260403_0008_security_bulk_grant_revocations.sql`

**Why this is safe:** These functions are only called by authenticated app users or by service_role (triggers/edge functions). Revoking PUBLIC and anon does not affect any legitimate code path.

**Note:** Functions already fixed in Tasks 1-2 and 7 have their grants handled in those migrations. This task covers the remaining functions not yet addressed.

- [ ] **Step 1: Write the migration**

```sql
-- Security fix: Revoke PUBLIC and anon EXECUTE from dangerous functions.
-- Live confirmed: all functions have EXECUTE for PUBLIC/anon/authenticated.
-- Functions already fixed in earlier migrations are included for idempotency.
--
-- Note: create_notification, queue_push_notification, and
-- send_push_notification_direct are also dangerous (CRIT-5) but need
-- a redesign (Batch 2 Task 13) before their authenticated grant can
-- be safely revoked. This migration only revokes PUBLIC and anon from them.

-- Blocking RPCs (already fixed in 0002, included for safety)
REVOKE ALL ON FUNCTION public.block_user FROM PUBLIC;
REVOKE ALL ON FUNCTION public.block_user FROM anon;
REVOKE ALL ON FUNCTION public.unblock_user FROM PUBLIC;
REVOKE ALL ON FUNCTION public.unblock_user FROM anon;
REVOKE ALL ON FUNCTION public.get_blocked_users FROM PUBLIC;
REVOKE ALL ON FUNCTION public.get_blocked_users FROM anon;

-- Notification helper RPCs — revoke PUBLIC/anon only (authenticated needed until redesign)
REVOKE ALL ON FUNCTION public.create_notification FROM PUBLIC;
REVOKE ALL ON FUNCTION public.create_notification FROM anon;
GRANT EXECUTE ON FUNCTION public.create_notification TO authenticated;
GRANT EXECUTE ON FUNCTION public.create_notification TO service_role;

-- queue_push_notification has two overloads
DO $$
DECLARE
    r RECORD;
BEGIN
    FOR r IN
        SELECT oid FROM pg_proc
        WHERE proname = 'queue_push_notification'
        AND pronamespace = 'public'::regnamespace
    LOOP
        EXECUTE format('REVOKE ALL ON FUNCTION %s FROM PUBLIC', r.oid::regprocedure);
        EXECUTE format('REVOKE ALL ON FUNCTION %s FROM anon', r.oid::regprocedure);
        EXECUTE format('GRANT EXECUTE ON FUNCTION %s TO authenticated', r.oid::regprocedure);
        EXECUTE format('GRANT EXECUTE ON FUNCTION %s TO service_role', r.oid::regprocedure);
    END LOOP;
END;
$$;

REVOKE ALL ON FUNCTION public.send_push_notification_direct FROM PUBLIC;
REVOKE ALL ON FUNCTION public.send_push_notification_direct FROM anon;
GRANT EXECUTE ON FUNCTION public.send_push_notification_direct TO authenticated;
GRANT EXECUTE ON FUNCTION public.send_push_notification_direct TO service_role;

-- Broadcast (already fixed in 0001, included for safety)
REVOKE ALL ON FUNCTION public.send_broadcast_notifications FROM PUBLIC;
REVOKE ALL ON FUNCTION public.send_broadcast_notifications FROM anon;

-- Completion (already fixed in 0007, included for safety)
REVOKE ALL ON FUNCTION public.handle_completion_response FROM PUBLIC;
REVOKE ALL ON FUNCTION public.handle_completion_response FROM anon;

-- create_signup_profile: grant revocation deferred to Batch 2 Task 10
-- where it ships alongside the auth.uid() guard + end-to-end signup validation.
-- Revoking PUBLIC/anon here without validating the signup flow is risky
-- because AuthService.signUp() calls this RPC immediately after auth.signUp().

-- mark_invite_code_used: unused by the app (InviteService.markInviteCodeAsUsed
-- uses direct table INSERT/UPDATE, not this RPC). Safe to revoke all access
-- as dead-code cleanup.
REVOKE ALL ON FUNCTION public.mark_invite_code_used FROM PUBLIC;
REVOKE ALL ON FUNCTION public.mark_invite_code_used FROM anon;
REVOKE ALL ON FUNCTION public.mark_invite_code_used FROM authenticated;
GRANT EXECUTE ON FUNCTION public.mark_invite_code_used TO service_role;

-- Utility functions that don't need anon access
REVOKE ALL ON FUNCTION public.is_admin_user FROM anon;
REVOKE ALL ON FUNCTION public.should_notify_user FROM anon;
REVOKE ALL ON FUNCTION public.is_user_blocked FROM anon;
```

- [ ] **Step 2: Apply migration**
- [ ] **Step 3: Verify grants with live query**

```sql
SELECT routine_name, grantee FROM information_schema.routine_privileges
WHERE routine_schema = 'public'
AND routine_name IN ('block_user','create_notification','create_signup_profile',
    'handle_completion_response','mark_invite_code_used','send_broadcast_notifications')
AND grantee IN ('PUBLIC','anon')
ORDER BY routine_name, grantee;
```

Expected: empty result set.

- [ ] **Step 4: Commit**

```bash
git add supabase/migrations/20260403_0008_security_bulk_grant_revocations.sql
git commit -m "security: revoke PUBLIC/anon EXECUTE from all dangerous functions

Live-verified: every audited function had EXECUTE for PUBLIC + anon.
Revokes these grants while preserving authenticated + service_role
access for functions that still need it."
```

---

## Batch 2: Coordinated Backend + Client Fixes

These require paired SQL + Swift changes and should be implemented one at a time with testing after each.

### Task 9: Message Edit/Unsend — DROP Participant-Wide UPDATE + Switch to RPCs

**Audit ref:** CRIT-4. **Live confirmed:** `messages_update_participant` allows any active participant to UPDATE any column on any message (checks `left_at IS NULL` but not `from_id`).

**Why the previous plan didn't close the hole:** Adding a sender-only UPDATE policy alongside the participant-wide policy doesn't help — PostgreSQL evaluates row policies with OR. A non-sender still matches the participant-wide policy and can mutate text, edited_at, and deleted_at via direct REST PATCH.

**The actual fix:** DROP the participant-wide UPDATE policy entirely. All message mutations now go through SECURITY DEFINER RPCs:
- `edit_message` — checks `from_id = auth.uid()` (sender-only)
- `unsend_message` — checks `from_id = auth.uid()` + 15-min window
- `mark_messages_read_batch` — SECURITY DEFINER, handles read receipts

With no UPDATE policy on the messages table, direct REST API `PATCH /rest/v1/messages` is blocked by RLS for all users. The RPCs bypass RLS via SECURITY DEFINER and enforce their own authorization.

**Must ship together:** Migration dropping UPDATE policy + Swift code switching to RPCs + Swift read-receipt fallback fix.

**Files:**
- Create: `supabase/migrations/20260403_0010_security_message_update_lockdown.sql`
- Modify: `NaarsCars/Core/Services/MessageService.swift:688-723` (edit/unsend → RPCs)
- Modify: `NaarsCars/Core/Services/MessageService.swift:760-771` (read receipt fallback → RPC)

- [ ] **Step 1: Write the migration**

```sql
-- Security fix: DROP participant-wide messages UPDATE policy.
-- All message mutations now go through SECURITY DEFINER RPCs only.
-- Live state: messages_update_participant allows any active participant
-- to UPDATE any column on any message — enables cross-user content tampering.
-- Audit ref: CRIT-4.
--
-- After this migration:
--   edit_message RPC (SECURITY DEFINER) → checks from_id = auth.uid()
--   unsend_message RPC (SECURITY DEFINER) → checks from_id = auth.uid() + 15-min window
--   mark_messages_read_batch RPC (SECURITY DEFINER) → handles read receipts
--   Direct REST PATCH on messages → blocked by RLS (no UPDATE policy)

DROP POLICY IF EXISTS "messages_update_participant" ON public.messages;
```

- [ ] **Step 2: Modify MessageService.swift — switch edit/unsend to RPCs**

Replace `updateMessageContent()` (lines 688-703):
```swift
func updateMessageContent(messageId: UUID, newContent: String) async throws {
    let params: [String: AnyCodable] = [
        "p_message_id": AnyCodable(messageId.uuidString),
        "p_new_content": AnyCodable(newContent)
    ]
    try await supabase.rpc("edit_message", params: params).execute()
    AppLogger.database.info("Edited message via RPC: \(messageId)")
}
```

Replace `unsendMessage()` (lines 708-723):
```swift
func unsendMessage(messageId: UUID) async throws {
    let params: [String: AnyCodable] = [
        "p_message_id": AnyCodable(messageId.uuidString)
    ]
    try await supabase.rpc("unsend_message", params: params).execute()
    AppLogger.database.info("Unsent message via RPC: \(messageId)")
}
```

- [ ] **Step 3: Fix read receipt fallback (lines 760-771) — use RPC instead of direct UPDATE**

Replace the fallback loop:
```swift
// Fallback: use RPC per-message instead of direct table UPDATE
for message in unreadMessages {
    var updatedReadBy = message.readBy
    if !updatedReadBy.contains(userId) {
        try? await supabase.rpc(
            "mark_messages_read_batch",
            params: [
                "p_message_ids": AnyCodable([message.id.uuidString]),
                "p_user_id": AnyCodable(userId.uuidString)
            ]
        ).execute()
    }
}
```

- [ ] **Step 4: Build and test**

Run: `xcodebuild -project NaarsCars/NaarsCars.xcodeproj -scheme NaarsCars -sdk iphonesimulator -configuration Debug build`

Test: Edit message → works. Unsend within 15 min → works. Unsend after 15 min → fails with clear error. Read receipts → work. Direct REST PATCH on messages table → blocked.

- [ ] **Step 5: Commit together**

```bash
git add supabase/migrations/20260403_0010_security_message_update_lockdown.sql NaarsCars/Core/Services/MessageService.swift
git commit -m "security: DROP participant-wide messages UPDATE, switch to RPC-only mutations

Audit ref: CRIT-4. Live-verified: messages_update_participant allowed any
active participant to UPDATE any column on any message. Now: no UPDATE
policy on messages table. All mutations go through SECURITY DEFINER RPCs
(edit_message, unsend_message, mark_messages_read_batch) which enforce
their own authorization. Direct REST PATCH is blocked by RLS."
```

---

### Task 10: `create_signup_profile` Auth Guard + Grant Revocation

**Audit ref:** CRIT-1. **Live confirmed:** SECURITY DEFINER, no auth.uid() check, ON CONFLICT resets is_admin/approved/application_complete. Granted to PUBLIC + anon + authenticated.

**Why grant revocation is here (not in Task 8):** `AuthService.signUp()` (line 238) calls `auth.signUp()` then immediately calls this RPC (line 274). The user should be authenticated at that point, but revoking anon/PUBLIC before validating the signup flow is risky. This task bundles the grant revocation WITH the auth guard AND end-to-end signup testing.

**Risk:** If `auth.uid()` is null immediately after `signUp()`, this breaks onboarding. Test carefully.

- [ ] **Step 1: Write migration adding auth.uid() = p_user_id guard + revoking anon/PUBLIC**
- [ ] **Step 2: Test full signup flow end-to-end (critical — this is the highest-risk migration)**
- [ ] **Step 3: Commit**

---

### Task 11: `mark_invite_code_used` — Unused RPC Cleanup

**Audit ref:** CRIT-5 (reframed). **Live confirmed:** SECURITY DEFINER, no auth.uid() check, granted to PUBLIC + anon + authenticated.

**However:** The app does NOT call this RPC. `InviteService.markInviteCodeAsUsed()` (lines 245-315) uses direct table INSERT/UPDATE operations, not the RPC. This function is dead code from the app's perspective.

**Grant revocation already done in Task 8** — all access revoked except service_role. If the function is truly unused, it can also be dropped entirely as follow-up. No auth guard needed since no code calls it.

- [ ] **Step 1: Verify no Swift code calls `mark_invite_code_used` RPC (already confirmed)**
- [ ] **Step 2: Optionally drop the function entirely, or leave with service_role-only grant from Task 8**

---

### Task 12: Notification Helper RPCs — Role-Aware Redesign

**Audit ref:** CRIT-5 (partial). Requires sub-project design — see original plan for details.

- [ ] **Step 1: Audit all Swift call sites for create_notification, queue_push_notification, send_push_notification_direct**
- [ ] **Step 2: Design purpose-specific wrapper RPCs**
- [ ] **Step 3: Implement wrappers + update Swift call sites**
- [ ] **Step 4: Revoke authenticated from base notification functions**

---

### Task 13: Profiles Public/Private Projection Split

**Audit ref:** CRIT-7. **Live confirmed:** `profiles_select_authenticated` gives all authenticated users full-row access. `profiles_select_anon_guest` gives anon full-row access.

- [ ] **Step 1: Create public_profiles security-barrier view**
- [ ] **Step 2: Audit + update Swift queries**
- [ ] **Step 3: Test all profile-dependent screens**

---

### Task 14: Push Edge Function Authentication

**Audit ref:** CRIT-8. Edge function work, not SQL.

- [ ] **Step 1: Design webhook HMAC signing approach**
- [ ] **Step 2: Implement in edge functions**
- [ ] **Step 3: Configure webhook to include signature**
- [ ] **Step 4: Deploy and test**

---

## Findings Removed (Stale Based on Live DB)

These were in the original repo-based plan but are no longer valid:

| Finding | Repo Basis | Live Reality | Status |
|---------|-----------|--------------|--------|
| `conversation_participants` RLS disabled (CRIT-6) | `database/065:24` disables RLS | RLS enabled, participant-scoped SELECT, own-row UPDATE/DELETE | **REMOVED** |
| `message_reactions` SELECT `USING(true)` (HIGH-3) | `database/066:37-39` | Participant-scoped via join through messages + conversation_participants | **REMOVED** |
| `completion_reminders` no RLS (HIGH-4) | No ENABLE RLS in repo | RLS enabled (INSERT/UPDATE too broad — fixed in Task 7) | **REWRITTEN** |

---

## Updated Security Score

With live corrections, revised from 24/100 to **28/100**:
- +2 for conversation_participants having proper RLS live
- +1 for message_reactions being participant-scoped live
- +1 for completion_reminders having RLS (even if policies too broad)

After Batch 1 (Tasks 1-8) is applied: estimated **52/100**
After Batch 2 (Tasks 9-14) is applied: estimated **75/100**
