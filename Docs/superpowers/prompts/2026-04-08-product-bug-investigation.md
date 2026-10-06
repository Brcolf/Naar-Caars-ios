# Product Bug Investigation Prompt

Paste this into a new Claude Code session.

---

You are investigating 5 product bugs in a production iOS + Supabase app (Naar's Cars). These bugs were discovered during manual QA testing and are believed to be pre-existing — not caused by recent security hardening work.

**Critical constraint:** Do NOT modify any security-related database policies, function grants, or RLS rules. Security hardening is happening in a separate session. Your job is to diagnose and fix product bugs only.

**Your tools:** You have access to the Supabase MCP for live database queries (execute_sql, get_logs, list_edge_functions, get_edge_function). Use it — live DB is the source of truth, not repo SQL files. Authenticate with the MCP before starting.

**Read CLAUDE.md first** — it contains critical architectural rules, fragile system invariants, and the priority order for tradeoffs in this codebase.

---

## Bug A: Direct Notification INSERT Fails with RLS Violation (CONFIRMED)

**Symptoms:** Console logs show:
```
Failed to create notification for claimer: PostgrestError(detail: nil, hint: nil, code: Optional("42501"), message: "new row violates row-level security policy for table \"notifications\"")
```

**Root cause (confirmed):** `RideService.swift:376-390` and `FavorService.swift:272-285` do direct table INSERT into `notifications` with `user_id` set to the claimer's UUID. But the INSERT runs as the request owner (who is editing the ride/favor). The live `notifications_insert_service_only` policy requires `auth.uid() = user_id`, so the owner's auth.uid() != claimer's user_id → RLS blocks.

**Fix approach:** Switch these two code paths from direct table INSERT to calling the `create_notification` RPC, which is SECURITY DEFINER and handles cross-user notification creation. The RPC already exists and is used by all trigger-based notification paths. Verify the RPC signature and parameters match what these code paths need before changing.

**Files:**
- `NaarsCars/Core/Services/RideService.swift:370-395` (the `detailsChanged` notification block)
- `NaarsCars/Core/Services/FavorService.swift:269-290` (same pattern)

**Verification:** After fix, edit a ride/favor that has a claimer → claimer should receive an in-app notification about the update. Console should not show the 42501 error.

---

## Bug B: Blocked User Messages Visible in Group Conversations (LIKELY BUG)

**Symptoms:** User blocks "CTO" user. In the conversations list, a group thread with CTO shows "Message unavailable" as the preview. But when opening the group thread, CTO's actual message text is visible (e.g., "Does this still work?", "Hev Testing").

**What the code intends:** The app has blocked-user message filtering:
- `MessageService.swift:45-49` — `filterBlocked()` method filters messages from blocked users
- `MessageService.swift:211-213` — applies `filterBlocked` during message fetching
- `ConversationDetailViewModel.swift:831` — checks blocked status

The conversation list preview correctly shows "Message unavailable" for the blocked sender, suggesting the preview path respects blocks. But the actual message thread rendering does NOT filter/redact blocked user messages in group conversations.

**Investigation approach:**
1. Trace the message rendering path in the UIKit `MessagesCollectionView` — does it apply the blocked-user filter when building the data source?
2. Check if `filterBlocked()` is called during the hydration path (`MessagingSyncEngine` → `MessagingRepository` → ViewModel) or only during the initial fetch
3. Check if realtime-delivered messages bypass the block filter
4. Determine whether the fix should be: (a) filter blocked messages out of the data source entirely, or (b) render a redacted "Message from blocked user" cell in group threads

**Key files:**
- `NaarsCars/Core/Services/MessageService.swift` — `filterBlocked()` method
- `NaarsCars/Core/Storage/MessagingSyncEngine.swift` — message hydration and realtime handling
- `NaarsCars/Core/Storage/MessagingRepository.swift` — message data access
- `NaarsCars/Features/Messaging/ViewModels/ConversationDetailViewModel.swift` — message list data source
- `NaarsCars/Features/Messaging/Views/MessageThreadViewController.swift` — UIKit rendering

**Verification:** After fix, open a group conversation containing a blocked user → their messages should be redacted or hidden. The conversation list preview should continue showing "Message unavailable."

---

## Bug C: Duplicate Push Notifications for New Ride Requests (UNDIAGNOSED)

**Symptoms:** When a new ride is created, other users receive 2-3 push notifications for the same ride, plus a summary notification ("You have X new notifications from Naar's Cars"). Expected: 1 push notification per new ride.

**Investigation approach — gather evidence first, don't guess:**
1. Query live DB: check `notification_queue` for duplicate entries from a recent ride creation. Look for rows with the same `ride_id` but different queue IDs.
2. Query live DB: check the `notify_new_ride()` trigger function definition. Does it call both `create_notification()` AND `queue_push_notification()`? Are there multiple triggers on the `rides` table that could fire for the same INSERT?
3. Check edge function logs (`get_logs`) for `send-notification` — are there duplicate invocations for the same notification?
4. Check if the database webhook for `notification_queue` fires for both INSERT and UPDATE, which could cause the edge function to process the same notification twice.

**Key files (DB side):**
- `notify_new_ride()` function (live DB — use `pg_get_functiondef`)
- Triggers on `rides` table (live DB — query `pg_trigger`)
- Webhooks configuration (Supabase dashboard or `supabase_functions.hooks`)
- `supabase/functions/send-notification/index.ts` — queue processing logic

**Key files (Swift side):**
- Check if the app also calls notification creation after ride creation (search for `create_notification` or `queue_push_notification` calls in `RideService.swift` or `CreateRideViewModel.swift`)

**Verification:** Create a new ride → exactly 1 push notification should arrive for each recipient.

---

## Bug D: No Push Notification for New Messages (UNDIAGNOSED)

**Symptoms:** When a message is sent, the recipient does not receive a push notification. The message appears when the recipient navigates to the Messages tab (unread badge shows), but no push wakes the device or shows in the notification center. The sender's console shows `messaging.send.serverAccepted` confirming the message reached Supabase.

**Investigation approach — gather evidence first:**
1. Query live DB: after sending a test message, check `notification_queue` for a corresponding push entry. Is a row being created?
2. Check if there's a trigger on the `messages` table that fires `notify_message_push()` or similar. Get the trigger definition from live DB.
3. Check if the trigger calls `queue_push_notification()` or if it relies on a webhook to invoke `send-message-push` edge function.
4. Check edge function logs for `send-message-push` — is it being invoked at all?
5. If the edge function IS being invoked, check:
   - Is the recipient's push token in the `push_tokens` table?
   - Is the recipient muted for this conversation?
   - Is the recipient being filtered out as "recently active" (the function skips push for users active in the last few minutes)?
   - Is the APNs call succeeding or failing?
6. Check if the message webhook configuration is correct in Supabase dashboard.

**Key files:**
- `supabase/functions/send-message-push/index.ts` — the edge function that sends message pushes
- `supabase/functions/_shared/apns.ts` — APNs sending logic
- `NaarsCars/Core/Services/PushNotificationService.swift` — token registration
- Live DB: triggers on `messages` table, `push_tokens` table, webhook configuration

**Verification:** Send a message to a user who is NOT in the conversation → they should receive a push notification within a few seconds.

---

## Bug E: No Completion Reminder Notification (UNDIAGNOSED)

**Symptoms:** User creates a ride/favor, another user claims it, the scheduled time passes, but no completion reminder notification arrives to prompt the claimer to mark it as complete.

**Investigation approach — gather evidence first:**
1. Query live DB: check `completion_reminders` table for rows matching the test ride/favor. Are reminders being created at all? What is `scheduled_for`, `completed`, `reminder_count`?
2. If reminders exist: check `process_completion_reminders()` function definition from live DB. This is the cron job that processes due reminders. Is it scheduled? When did it last run?
3. Check if pg_cron is enabled and the job is active: `SELECT * FROM cron.job WHERE jobname LIKE '%completion%'`
4. If the cron job is running: check whether `should_notify_user()` is blocking the notification (the `completion_reminder` type maps to `v_profile.notify_review_reminders` — is that preference enabled for the test user?)
5. Check `notification_queue` for any queued completion reminder entries
6. Check if the reminder is being created with the correct `scheduled_for` time (should be shortly after the ride/favor's scheduled time)

**Key files:**
- `process_completion_reminders()` function (live DB)
- `completion_reminders` table (live DB)
- `cron.job` table (live DB)
- `NaarsCars/Core/Services/CompletionPromptProvider.swift` — reads reminders
- `NaarsCars/Core/Services/PromptSideEffects.swift` — calls `handle_completion_response` RPC
- `NaarsCars/Core/Services/PushNotificationService.swift:654-663` — push action handler

**Verification:** Claim a ride/favor, wait past the scheduled time, cron job runs → claimer should receive a completion reminder push notification.

---

## General Investigation Rules

1. **Evidence before diagnosis.** Query live DB and read logs before proposing a fix. Do not guess root causes.
2. **One bug at a time.** Investigate, diagnose, fix, and verify each bug before moving to the next.
3. **Do not touch security policies or grants.** If you discover a security-related issue during investigation, document it but do not fix it — that's handled in the security hardening session.
4. **Preserve existing behavior.** Follow CLAUDE.md rules — minimal changes, no scope creep, no refactoring.
5. **Start with Bug A** — it has a confirmed root cause and a clear fix. Then move to B (likely bug with good leads). Then C, D, E (need investigation).
