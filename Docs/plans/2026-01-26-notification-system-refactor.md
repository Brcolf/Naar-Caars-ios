# Notification System Refactor Implementation Plan

> **For Claude:** REQUIRED SUB-SKILL: Use superpowers:executing-plans to implement this plan task-by-task.

**Goal:** Restore reliable push + in-app notifications, badge counts, and deep-link behavior across Requests, Messages, Town Hall, and Admin approvals, using server-scheduled delivery and scoped clearing.

**Architecture:** Database triggers create in-app notifications and enqueue push payloads. Edge functions deliver APNs pushes. iOS consumes pushes, deep-links to content, and clears relevant notification state on view. Badges are server-authoritative via RPC.

**Tech Stack:** SwiftUI (iOS), Supabase Postgres (RLS, triggers, functions), Supabase Edge Functions (Deno/TypeScript), APNs.

---

## Assumptions (documented, proceed unless contradicted)
- Q&A ends after claim; Q&A input hidden when claimed and replaced with "Message participants".
- Completion reminders must be server-scheduled pushes (local scheduling removed or demoted to fallback).
- Foreground alerting is via in-app toasts (no OS banner requirements for foreground).
- Message push suppression only when thread is open (not just Messages tab).
- Admin badge is derived from pending user count.
- Pending approval push permission prompt (current flow) is acceptable.

---

### Task 1: Add DB verification script (tests-first for infra)

**Files:**
- Create: `QA/notification_infra_checks.sql`

**Step 1: Write the failing verification script**

```sql
-- Notification infra checks (run in Supabase SQL editor)
-- These should FAIL before migrations are applied.
select 'push_tokens' as table_name, to_regclass('public.push_tokens') is not null as exists;
select 'get_badge_counts' as fn_name, exists (
  select 1 from pg_proc where proname = 'get_badge_counts'
) as exists;
select 'mark_request_notifications_read' as fn_name, exists (
  select 1 from pg_proc where proname = 'mark_request_notifications_read'
) as exists;
```

**Step 2: Run the script (verify FAIL)**
Run in Supabase SQL editor.  
Expected: `exists = false` for missing items.

**Step 3: Commit**
```bash
git add QA/notification_infra_checks.sql
git commit -m "docs: add notification infra check script"
```

---

### Task 2: Create `push_tokens` table migration

**Files:**
- Create: `supabase/migrations/20260126_0001_push_tokens.sql`

**Step 1: Add failing check (already in Task 1)**

**Step 2: Write minimal migration**
```sql
create table if not exists public.push_tokens (
  id uuid primary key default gen_random_uuid(),
  user_id uuid not null references profiles(id) on delete cascade,
  device_id text not null,
  token text not null,
  platform text not null default 'ios',
  environment text not null default 'production',
  created_at timestamptz not null default now(),
  updated_at timestamptz not null default now(),
  last_used_at timestamptz
);

create unique index if not exists push_tokens_user_device_idx
  on public.push_tokens (user_id, device_id);

alter table public.push_tokens enable row level security;

create policy "push_tokens_select_own"
  on public.push_tokens for select
  using (auth.uid() = user_id);

create policy "push_tokens_insert_own"
  on public.push_tokens for insert
  with check (auth.uid() = user_id);

create policy "push_tokens_update_own"
  on public.push_tokens for update
  using (auth.uid() = user_id)
  with check (auth.uid() = user_id);
```

**Step 3: Re-run verification (expect PASS)**
Run `QA/notification_infra_checks.sql` in Supabase SQL editor.  
Expected: `push_tokens exists = true`.

**Step 4: Commit**
```bash
git add supabase/migrations/20260126_0001_push_tokens.sql
git commit -m "db: add push_tokens table and RLS"
```

---

### Task 3: Port `get_badge_counts` RPC

**Files:**
- Create: `supabase/migrations/20260126_0002_get_badge_counts.sql`

**Step 1: Add failing check (already in Task 1)**

**Step 2: Write minimal migration**
Copy contents from `database/092_badge_counts_rpc.sql` with function name and grants.

**Step 3: Re-run verification (expect PASS)**
Run `QA/notification_infra_checks.sql`.  
Expected: `get_badge_counts exists = true`.

**Step 4: Commit**
```bash
git add supabase/migrations/20260126_0002_get_badge_counts.sql
git commit -m "db: add get_badge_counts RPC"
```

---

### Task 4: Port `mark_request_notifications_read` RPC

**Files:**
- Create: `supabase/migrations/20260126_0003_mark_request_notifications_read.sql`

**Step 1: Add failing check (already in Task 1)**

**Step 2: Write minimal migration**
Copy contents from `database/091_request_notification_read_scoped.sql`.

**Step 3: Re-run verification (expect PASS)**
Run `QA/notification_infra_checks.sql`.  
Expected: `mark_request_notifications_read exists = true`.

**Step 4: Commit**
```bash
git add supabase/migrations/20260126_0003_mark_request_notifications_read.sql
git commit -m "db: add mark_request_notifications_read RPC"
```

---

### Task 5: Port core notification triggers + critical fixes

**Files:**
- Create: `supabase/migrations/20260126_0004_notification_triggers.sql`

**Step 1: Write a failing verification query**
Add to `QA/notification_infra_checks.sql`:
```sql
select 'notify_new_ride' as fn_name, exists (
  select 1 from pg_proc where proname = 'notify_new_ride'
) as exists;
```

**Step 2: Run verification (expect FAIL)**

**Step 3: Write migration**
Consolidate `database/077_notification_triggers.sql` + fixes from `database/080_fix_notification_triggers_critical.sql`.  
Ensure:
- Q&A stops after claim (keep claimed short-circuit).
- Queue payload uses `queue_push_notification` with `notification_id` when available.

**Step 4: Re-run verification (expect PASS)**

**Step 5: Commit**
```bash
git add supabase/migrations/20260126_0004_notification_triggers.sql QA/notification_infra_checks.sql
git commit -m "db: add notification triggers with fixes"
```

---

### Task 6: Port notification queue processing + RLS

**Files:**
- Create: `supabase/migrations/20260126_0005_notification_queue_processing.sql`

**Step 1: Add failing verification query**
Add to `QA/notification_infra_checks.sql`:
```sql
select 'process_immediate_notification' as fn_name, exists (
  select 1 from pg_proc where proname = 'process_immediate_notification'
) as exists;
```

**Step 2: Run verification (expect FAIL)**

**Step 3: Write migration**
Copy from `database/082_fix_notification_queue_processing.sql`.  
Ensure RLS policies and immediate processing trigger exist.

**Step 4: Re-run verification (expect PASS)**

**Step 5: Commit**
```bash
git add supabase/migrations/20260126_0005_notification_queue_processing.sql QA/notification_infra_checks.sql
git commit -m "db: add notification_queue processing and RLS"
```

---

### Task 7: Port review_id column + realtime publication

**Files:**
- Create: `supabase/migrations/20260126_0006_notifications_review_id.sql`
- Create: `supabase/migrations/20260126_0007_realtime_publication.sql`

**Step 1: Add failing verification query**
Add to `QA/notification_infra_checks.sql`:
```sql
select 'notifications.review_id' as column_name,
  exists (
    select 1 from information_schema.columns
    where table_name = 'notifications' and column_name = 'review_id'
  ) as exists;
```

**Step 2: Run verification (expect FAIL)**

**Step 3: Write migrations**
Copy from `database/079_fix_notifications_review_id_column.sql` and `database/081_fix_realtime_messaging.sql`.

**Step 4: Re-run verification (expect PASS)**

**Step 5: Commit**
```bash
git add supabase/migrations/20260126_0006_notifications_review_id.sql supabase/migrations/20260126_0007_realtime_publication.sql QA/notification_infra_checks.sql
git commit -m "db: add review_id column and realtime publication"
```

---

### Task 8: Server-scheduled completion reminders

**Files:**
- Create: `supabase/migrations/20260126_0008_completion_reminders.sql`
- Modify: `NOTIFICATION-DEPLOYMENT-GUIDE.md`

**Step 1: Write failing verification query**
Add to `QA/notification_infra_checks.sql`:
```sql
select 'process_completion_reminders' as fn_name, exists (
  select 1 from pg_proc where proname = 'process_completion_reminders'
) as exists;
```

**Step 2: Run verification (expect FAIL)**

**Step 3: Write migration**
Copy `process_completion_reminders` and `handle_completion_response` from `database/078_pg_cron_notification_jobs.sql` if missing.

**Step 4: Update deployment guide**
Add explicit pg_cron or external scheduler setup for:
- `process_completion_reminders`
- `process_batched_notifications`

**Step 5: Re-run verification (expect PASS)**

**Step 6: Commit**
```bash
git add supabase/migrations/20260126_0008_completion_reminders.sql NOTIFICATION-DEPLOYMENT-GUIDE.md QA/notification_infra_checks.sql
git commit -m "db: add completion reminder scheduler and docs"
```

---

### Task 9: Global in-app toast for messages

**Files:**
- Modify: `NaarsCars/App/MainTabView.swift`
- Modify: `NaarsCars/Features/Messaging/Views/ConversationsListView.swift`
- Modify: `NaarsCars/Features/Messaging/ViewModels/ConversationsListViewModel.swift`

**Step 1: Write failing test**
Create or update `NaarsCarsTests/Features/Messaging/InAppMessageToastTests.swift` to assert toast state is exposed from a shared manager when a message arrives while not in thread.

**Step 2: Run test (expect FAIL)**
Run: `xcodebuild test -scheme NaarsCars -only-testing:NaarsCarsTests/Features/Messaging/InAppMessageToastTests`

**Step 3: Implement**
Move toast overlay to `MainTabView` using a shared `InAppToastManager` or environment object.  
Suppress toast only when the active thread is open.

**Step 4: Run test (expect PASS)**

**Step 5: Commit**
```bash
git add NaarsCars/App/MainTabView.swift NaarsCars/Features/Messaging/Views/ConversationsListView.swift NaarsCars/Features/Messaging/ViewModels/ConversationsListViewModel.swift NaarsCarsTests/Features/Messaging/InAppMessageToastTests.swift
git commit -m "ios: globalize in-app message toasts"
```

---

### Task 10: Remove Q&A input after claim and show message participants

**Files:**
- Modify: `NaarsCars/Features/Rides/Views/RideDetailView.swift`
- Modify: `NaarsCars/Features/Favors/Views/FavorDetailView.swift`

**Step 1: Write failing test**
Add UI tests or unit tests asserting Q&A input is hidden when `claimedBy != nil`.

**Step 2: Run test (expect FAIL)**

**Step 3: Implement**
Hide/disable Q&A composer after claim.  
Show "Message participants" button that collects poster + claimer + participants and navigates to conversation.

**Step 4: Run test (expect PASS)**

**Step 5: Commit**
```bash
git add NaarsCars/Features/Rides/Views/RideDetailView.swift NaarsCars/Features/Favors/Views/FavorDetailView.swift
git commit -m "ios: replace Q&A after claim with message participants"
```

---

### Task 11: Remove local completion reminder scheduling

**Files:**
- Modify: `NaarsCars/Core/Services/ClaimService.swift`
- Modify: `NaarsCars/Core/Services/PushNotificationService.swift`

**Step 1: Write failing test**
Add unit test ensuring `scheduleCompletionReminderIfNeeded` does not schedule local notifications when server scheduling is enabled.

**Step 2: Run test (expect FAIL)**

**Step 3: Implement**
Disable local scheduling or gate it behind a feature flag.  
Ensure server-scheduled push is the primary path.

**Step 4: Run test (expect PASS)**

**Step 5: Commit**
```bash
git add NaarsCars/Core/Services/ClaimService.swift NaarsCars/Core/Services/PushNotificationService.swift
git commit -m "ios: rely on server-scheduled completion reminders"
```

---

### Task 12: Delivery wiring documentation for webhooks and cron

**Files:**
- Modify: `NOTIFICATION-DEPLOYMENT-GUIDE.md`
- Modify: `supabase/functions/send-message-push/WEBHOOK_SETUP.md` (if needed)

**Step 1: Write failing verification checklist**
Add a checklist section that fails if webhook/cron is not configured.

**Step 2: Implement**
Document explicit steps to configure:
- `send-notification` on `notification_queue` inserts
- `send-message-push` on `messages` inserts
- cron schedules for completion reminders and batched notifications

**Step 3: Commit**
```bash
git add NOTIFICATION-DEPLOYMENT-GUIDE.md supabase/functions/send-message-push/WEBHOOK_SETUP.md
git commit -m "docs: document notification delivery wiring"
```

---

## Execution Handoff

When executing this plan, use **superpowers:executing-plans** and follow TDD strictly for Swift changes. For DB migrations, use the SQL verification script to simulate test-first behavior. Commit after each task.

