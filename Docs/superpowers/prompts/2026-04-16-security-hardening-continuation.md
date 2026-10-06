# Security Hardening Continuation Prompt

Paste this into a new Claude Code session.

---

You are continuing a security hardening project on a production iOS + Supabase app (Naar's Cars). Four prior batches of security fixes have been applied and verified. Two remaining items need design + implementation.

**Read CLAUDE.md first** — it contains critical architectural rules, fragile system invariants, and priority order for tradeoffs.

**Read the hardening plan** at `Docs/superpowers/plans/2026-04-02-security-hardening.md` for full context on the audit findings and what's been done.

---

## What Has Already Been Done (DO NOT REDO)

All of the following are applied to the live Supabase database and deployed edge functions. Do not revert or re-apply them.

### Batch 1: Safe Backend-Only
- `send_broadcast_notifications` — added `is_admin = true` guard, revoked PUBLIC/anon grants
- `block_user`, `unblock_user`, `get_blocked_users` — added `auth.uid()` validation, revoked PUBLIC/anon grants
- Review uniqueness — partial unique indexes on `(reviewer_id, ride_id)` and `(reviewer_id, favor_id)`
- `should_notify_user()` — ELSE branch changed to `RETURN false` (deny-by-default), `content_reported` added as `v_profile.is_admin`
- Storage policies — `group-images` UPDATE/DELETE and `audio-messages` DELETE now require `owner = auth.uid()`

### Batch 2: Messages + Grant Revocations
- Messages SELECT policy — added `joined_at` and `left_at` bounds, preserved `hidden_at` clause
- Bulk grant revocations — revoked PUBLIC/anon from: `create_notification`, `queue_push_notification`, `send_push_notification_direct`, `handle_completion_response`, `mark_invite_code_used` (reduced to service_role only), `is_user_blocked`, `is_admin_user`

### Batch 3: Completion Reminders + Message Mutations
- `completion_reminders` — INSERT restricted to service_role, UPDATE scoped to `claimer_user_id = auth.uid()` for authenticated
- `handle_completion_response` — added `auth.uid() = claimer_user_id` guard (kept NOT SECURITY DEFINER)
- Messages UPDATE — **DROPPED `messages_update_participant` policy entirely**. No UPDATE policies remain on messages table. All mutations go through SECURITY DEFINER RPCs:
  - `edit_message` — checks `from_id = auth.uid()`
  - `unsend_message` — checks `from_id = auth.uid()` + 15-min window
  - `mark_messages_read_batch` — handles read receipts
- Swift changes in `MessageService.swift`:
  - `updateMessageContent()` → calls `edit_message` RPC
  - `unsendMessage()` → calls `unsend_message` RPC
  - `markAsRead()` fallback → calls `mark_messages_read_batch` with PostgreSQL uuid[] literal format `"{uuid1,uuid2}"`

### Batch 4: Signup Profile
- `create_signup_profile` — added `auth.uid() = p_user_id` guard, revoked PUBLIC/anon grants

### Batch 5: Edge Function Auth
- `send-message-push` (v29) and `send-notification` (v20) — added in-function service_role authorization check:
  ```typescript
  const authHeader = req.headers.get('authorization') ?? ''
  if (authHeader !== `Bearer ${supabaseServiceKey}`) {
    return new Response(JSON.stringify({ error: 'Unauthorized' }), { status: 401, ... })
  }
  ```
- Gateway `verify_jwt` stays `false` (enabling it previously broke edge function flows)
- Auth check is after CORS preflight, before body parsing

### Also Fixed During Hardening
- `send-message-push` redeployed to fix stale code referencing removed `notifications_muted` column
- `mark_messages_read_batch` Swift caller fixed to use PostgreSQL uuid[] literal format instead of JSON array

---

## What Remains: Two Items

### Item 1: Notification RPCs Redesign (CRIT-5 remaining)

**The problem:** `create_notification`, `queue_push_notification`, and `send_push_notification_direct` are callable by any authenticated user with arbitrary recipient IDs. An attacker can forge in-app notifications and push notifications to any user.

**What's already been done to reduce blast radius:**
- PUBLIC/anon grants revoked (Batch 2) — only `authenticated` remains
- Edge function auth gates (Batch 5) — external callers blocked
- So the remaining risk is authenticated-user-to-authenticated-user notification forgery

**Why this is hard:** These functions are called by 16+ database trigger/functions:
- `notify_ride_status_change`, `notify_favor_status_change`
- `notify_new_ride`, `notify_new_favor`
- `notify_added_to_conversation`
- `notify_pending_user`, `notify_user_approved`
- `notify_qa_activity`, `notify_qa_answer`
- `notify_town_hall_comment`, `notify_town_hall_post`, `notify_town_hall_vote`
- `handle_new_report`, `handle_completion_response`
- `process_completion_reminders`
- `send_broadcast_notifications`
- `delete_user_account`

All of these are SECURITY DEFINER trigger functions that legitimately create cross-user notifications. A simple `auth.uid() = p_user_id` guard would break all of them.

**Design approach (needs validation):**
1. Revoke `authenticated` grant from the three base notification functions
2. Keep only `service_role` (triggers are SECURITY DEFINER owned by postgres → bypass grants)
3. Verify that every trigger/function caller still works after the revocation
4. For any Swift code that calls these functions directly (check `ClaimService.swift` which calls `queue_push_notification`), create a purpose-specific wrapper RPC that validates the caller's relationship to the action

**Critical verification before implementation:**
- Query live DB for ALL callers: `SELECT proname FROM pg_proc WHERE pg_get_functiondef(oid) LIKE '%create_notification(%' OR pg_get_functiondef(oid) LIKE '%queue_push_notification(%'`
- Check all Swift call sites: `grep -rn 'create_notification\|queue_push_notification\|send_push_notification_direct' NaarsCars/`
- For each Swift caller, determine: what relationship does auth.uid() have to the recipient?

**Key constraint:** SECURITY DEFINER functions owned by postgres bypass both RLS AND grant restrictions. So revoking `authenticated` should not break trigger-called paths. But this MUST be verified against the live DB, not assumed.

### Item 2: Profiles Projection Split (CRIT-7)

**The problem:** All authenticated users get full-row SELECT on all profiles, including email, phone_number, is_admin, is_banned, ban_reason, banned_by, notification preferences, application data. Anonymous users also get full-row access via guest mode policy.

**Live policies (verified via MCP):**
- `profiles_select_authenticated`: `USING (auth.role() = 'authenticated')` — full-row to all authenticated
- `profiles_select_anon_guest`: `USING (true)` — full-row to anon
- `profiles_select_admin`: `USING (is_admin_user(auth.uid()))` — redundant with above
- `Users can view approved profiles`: `USING ((auth.uid() = id) OR (is_user_approved(auth.uid()) = true))` — also full-row

**Profile fields that should NOT be publicly visible:**
From `NaarsCars/Core/Models/Profile.swift`:
- `email`, `phoneNumber` — PII
- `isAdmin`, `isBanned`, `banReason`, `bannedAt`, `bannedBy` — security metadata
- `heardAbout`, `joinReason`, `applicationComplete`, `applicationSubmittedAt` — application data
- `notifyRideUpdates`, `notifyMessages`, `notifyAnnouncements`, etc. — notification preferences

**Fields that ARE needed publicly:**
- `id`, `name`, `avatarUrl`, `car` — displayed in ride/favor cards, messaging, community
- `approved` — needed for some UI gating

**Design approach:**
1. Create a `public_profiles` security-barrier view projecting only safe columns
2. Replace `profiles_select_authenticated` and `profiles_select_anon_guest` with policies that restrict to self + admin for full row
3. Update Swift queries that fetch profiles for display purposes (messaging participant lists, ride/favor cards, community) to use the restricted view or select only needed columns
4. Keep full-row access for `auth.uid() = id` (own profile) and admin

**This is the highest-touch change** because many Swift files query profiles:
- `ConversationService.swift` — participant profiles
- `MessageService.swift` — sender profiles
- `RideService.swift`, `FavorService.swift` — creator/claimer profiles
- `ReviewService.swift` — reviewer/fulfiller profiles
- `AdminService.swift` — admin operations (needs full row)
- `ProfileService.swift` — own profile (needs full row)
- `TownHallCommentService.swift` — commenter profiles

**Critical constraint:** The Supabase client's `.select("*")` pattern is used extensively. Switching to a view means either:
- (a) All queries that currently hit `profiles` switch to `public_profiles` (many file changes)
- (b) Replace the base table policies so that `SELECT * FROM profiles` only returns safe columns for non-self/non-admin queries (not possible with RLS alone — RLS is row-level, not column-level)
- (c) Use a security-barrier view as the primary query target and restrict direct table access

Approach (a) is the most work but the cleanest. Approach (c) is a middle ground.

---

## Hard Requirements for This Session

1. **Live Supabase MCP is the source of truth.** Before proposing or applying any DB fix, verify live state with `execute_sql`. Do not rely on repo SQL files.

2. **Preserve behavior first.** If a secure mechanism already exists, prefer switching the app to that path. Do not refactor unrelated code.

3. **Batch and verify.** Do not implement both items in one sweep. Do one, verify, then the other.

4. **Before revoking any grant, enumerate all live callers.** Check pg_proc, Swift code, edge functions, and triggers. Do not revoke until you know what replaces the current path.

5. **Do not touch anything already fixed.** The batches listed above are done. Do not re-apply, modify, or revert them.

6. **Authenticate with Supabase MCP first.** You'll need it for all DB verification.

7. **For each proposed fix, explicitly answer:**
   - What vulnerability does this close?
   - What current app flow depends on this path?
   - Why won't this break that flow?
   - What is the verification step after the change?

---

## Recommended Sequence

**Start with Item 1 (Notification RPCs)** because:
- The design approach (revoke `authenticated`, keep `service_role`) may be simpler than it looks — most callers are SECURITY DEFINER triggers that bypass grants
- The main risk is Swift call sites that call these RPCs directly — there may be very few
- Closing this eliminates the last CRIT-5 finding

**Then Item 2 (Profiles)** because:
- It's the highest-touch change (many Swift files)
- It benefits from having the notification RPCs locked down first
- It's the last remaining CRIT finding

**After both items are done, the security hardening is complete.** All remaining items (AppState staleness, sign-out lifecycle, Apple identity linking) are Tier 3 hardening, not launch-blocking.
