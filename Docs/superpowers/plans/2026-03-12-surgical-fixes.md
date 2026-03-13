# Surgical Fixes Implementation Plan

> **For agentic workers:** REQUIRED: Use superpowers:subagent-driven-development (if subagents available) or superpowers:executing-plans to implement this plan. Steps use checkbox (`- [ ]`) syntax for tracking.

**Goal:** Fix source SQL drift, submit_report auth spoofing, and blocked-user content leaks across all messaging paths and UI surfaces.

**Architecture:** Four independent fixes: two SQL migration file rewrites with live DB application, one multi-file Swift blocking enforcement pass, and one SQL comment addition. No new files created. No API signature changes.

**Tech Stack:** PostgreSQL (Supabase), Swift/SwiftUI, Localizable.xcstrings

**Spec:** `docs/superpowers/specs/2026-03-12-surgical-fixes-design.md`

---

## File Map

| File | Action | Responsibility |
|------|--------|---------------|
| `database/128_fix_reports_add_post_comment_columns.sql` | Rewrite | FK behavior + constraint name accuracy |
| `database/128_fix_submit_report_post_comment.sql` | Rewrite | auth.uid() guard + override |
| `database/128_fix_delete_user_account_auth_guard.sql` | Edit | FK cascade documentation comments |
| `NaarsCars/Core/Services/MessageService.swift` | Edit | filterBlocked helper, apply to 7 methods, reply context sanitization, typing indicator filtering |
| `NaarsCars/Core/Storage/MessagingSyncEngine.swift` | Edit | Gate realtime upserts from blocked users |
| `NaarsCars/Features/Messaging/ViewModels/ConversationDetailViewModel.swift` | Edit | Guard handleNewMessage from blocked users |
| `NaarsCars/Features/Messaging/Views/ConversationRow.swift` | Edit | Last message preview placeholder for blocked users |
| `NaarsCars/Resources/Localizable.xcstrings` | Edit | 2 new localization keys |

---

## Chunk 1: Database Fixes (Tasks 1-3)

### Task 1: Fix reports migration — source accuracy + duplicate constraint

**Files:**
- Rewrite: `database/128_fix_reports_add_post_comment_columns.sql`

- [ ] **Step 1: Rewrite the migration file**

Replace the entire contents of `database/128_fix_reports_add_post_comment_columns.sql` with:

```sql
-- Fix: Add reported_post_id and reported_comment_id to reports table
-- The live DB already has these columns, but they were never captured in a migration.

-- Add columns with ON DELETE SET NULL (reports survive when content is deleted)
ALTER TABLE reports ADD COLUMN IF NOT EXISTS reported_post_id UUID
  REFERENCES town_hall_posts(id) ON DELETE SET NULL;
ALTER TABLE reports ADD COLUMN IF NOT EXISTS reported_comment_id UUID
  REFERENCES town_hall_comments(id) ON DELETE SET NULL;

-- Update the check constraint to include new columns.
-- Drop BOTH possible names to handle any DB state:
--   report_target_check  (original name from 087_reports_and_blocking.sql)
--   reports_target_check (erroneously created by earlier version of this migration)
ALTER TABLE reports DROP CONSTRAINT IF EXISTS report_target_check;
ALTER TABLE reports DROP CONSTRAINT IF EXISTS reports_target_check;
ALTER TABLE reports ADD CONSTRAINT report_target_check CHECK (
    reported_user_id IS NOT NULL OR
    reported_message_id IS NOT NULL OR
    reported_post_id IS NOT NULL OR
    reported_comment_id IS NOT NULL
);
```

- [ ] **Step 2: Drop duplicate constraint from live DB**

Execute via Supabase MCP:

```sql
ALTER TABLE reports DROP CONSTRAINT IF EXISTS reports_target_check;
```

- [ ] **Step 3: Verify live DB has exactly one constraint**

Execute via Supabase MCP:

```sql
SELECT conname, pg_get_constraintdef(oid)
FROM pg_constraint
WHERE conrelid = 'public.reports'::regclass
AND contype = 'c'
AND conname LIKE '%target_check%';
```

Expected: exactly one row — `report_target_check` with the 4-column definition.

- [ ] **Step 4: Verify FK behavior matches source**

Execute via Supabase MCP:

```sql
SELECT conname, pg_get_constraintdef(oid)
FROM pg_constraint
WHERE conrelid = 'public.reports'::regclass
AND contype = 'f'
AND conname IN ('reports_reported_post_id_fkey', 'reports_reported_comment_id_fkey');
```

Expected: both show `ON DELETE SET NULL`.

- [ ] **Step 5: Commit**

```bash
git add database/128_fix_reports_add_post_comment_columns.sql
git commit -m "fix: align reports migration with live DB — ON DELETE SET NULL FKs, correct constraint name"
```

---

### Task 2: Fix submit_report auth guard

**Files:**
- Rewrite: `database/128_fix_submit_report_post_comment.sql`

- [ ] **Step 1: Rewrite the migration file**

Replace the entire contents of `database/128_fix_submit_report_post_comment.sql` with:

```sql
-- Fix: Update submit_report RPC to accept post/comment IDs
-- The live DB already has this version, but it was never captured in a migration.
-- Changes from original: adds p_reported_post_id and p_reported_comment_id params,
-- duplicate-prevention for posts/comments, SET search_path = public.
-- SECURITY FIX: validates auth.uid() matches p_reporter_id, uses auth.uid() for
-- all internal operations to prevent reporter spoofing.

CREATE OR REPLACE FUNCTION public.submit_report(
    p_reporter_id uuid,
    p_reported_user_id uuid DEFAULT NULL::uuid,
    p_reported_message_id uuid DEFAULT NULL::uuid,
    p_reported_post_id uuid DEFAULT NULL::uuid,
    p_reported_comment_id uuid DEFAULT NULL::uuid,
    p_report_type text DEFAULT 'other'::text,
    p_description text DEFAULT NULL::text
)
RETURNS uuid
LANGUAGE plpgsql
SECURITY DEFINER
SET search_path TO 'public'
AS $function$
DECLARE
    v_report_id UUID;
BEGIN
    -- Target validation
    IF p_reported_user_id IS NULL AND p_reported_message_id IS NULL
       AND p_reported_post_id IS NULL AND p_reported_comment_id IS NULL THEN
        RAISE EXCEPTION 'Must report a user, message, post, or comment';
    END IF;

    -- SECURITY: Verify the caller is the reporter (prevent spoofing)
    IF auth.uid() IS NULL OR auth.uid() != p_reporter_id THEN
        RAISE EXCEPTION 'Reporter ID must match authenticated user';
    END IF;

    -- Prevent duplicate reports (use auth.uid() not p_reporter_id)
    IF p_reported_post_id IS NOT NULL THEN
        IF EXISTS (SELECT 1 FROM reports
                   WHERE reporter_id = auth.uid()
                   AND reported_post_id = p_reported_post_id) THEN
            RETURN NULL;
        END IF;
    END IF;
    IF p_reported_comment_id IS NOT NULL THEN
        IF EXISTS (SELECT 1 FROM reports
                   WHERE reporter_id = auth.uid()
                   AND reported_comment_id = p_reported_comment_id) THEN
            RETURN NULL;
        END IF;
    END IF;

    -- Insert using auth.uid() as the trusted reporter identity
    INSERT INTO reports (
        reporter_id, reported_user_id, reported_message_id,
        reported_post_id, reported_comment_id,
        report_type, description
    ) VALUES (
        auth.uid(), p_reported_user_id, p_reported_message_id,
        p_reported_post_id, p_reported_comment_id,
        p_report_type, p_description
    )
    RETURNING id INTO v_report_id;

    RETURN v_report_id;
END;
$function$;
```

- [ ] **Step 2: Deploy the function to live DB**

Execute the full `CREATE OR REPLACE FUNCTION` statement above via Supabase MCP.

- [ ] **Step 3: Verify the function is deployed correctly**

Execute via Supabase MCP:

```sql
SELECT prosrc FROM pg_proc WHERE proname = 'submit_report';
```

Verify the output contains:
- `IF auth.uid() IS NULL OR auth.uid() != p_reporter_id THEN`
- `WHERE reporter_id = auth.uid()` (in duplicate checks)
- `auth.uid()` in the INSERT VALUES (not `p_reporter_id`)

- [ ] **Step 4: Commit**

```bash
git add database/128_fix_submit_report_post_comment.sql
git commit -m "fix: add auth.uid() guard to submit_report — prevent reporter spoofing"
```

---

### Task 3: Add FK cascade documentation to delete_user_account

**Files:**
- Edit: `database/128_fix_delete_user_account_auth_guard.sql:124,132`

- [ ] **Step 1: Add cascade documentation comment before town_hall_posts delete**

In `database/128_fix_delete_user_account_auth_guard.sql`, before line 124 (`DELETE FROM town_hall_posts`), add:

```sql
    -- town_hall_comments: CASCADE-deleted via town_hall_comments_post_id_fkey
    -- reports.reported_post_id: SET NULL via reports_reported_post_id_fkey
    -- reports.reported_comment_id: SET NULL via reports_reported_comment_id_fkey
```

- [ ] **Step 2: Add cascade documentation comment before profiles delete**

Before line 132 (`DELETE FROM profiles`), add:

```sql
    -- reports.reporter_id: CASCADE-deleted via reports_reporter_id_fkey
    -- reports.reported_user_id: CASCADE-deleted via reports_reported_user_id_fkey
    -- blocked_users: CASCADE-deleted via both blocker_id and blocked_id FKs
```

- [ ] **Step 3: Commit**

```bash
git add database/128_fix_delete_user_account_auth_guard.sql
git commit -m "docs: add FK cascade documentation to delete_user_account"
```

---

## Chunk 2: Blocking Enforcement — MessageService + Localization (Tasks 4-7)

### Task 4: Add filterBlocked helper and apply to fetch methods

**Files:**
- Edit: `NaarsCars/Core/Services/MessageService.swift:43,208-210,270,299,326,342,948,992`

- [ ] **Step 1: Add the filterBlocked helper method**

In `MessageService.swift`, after the `isBlocked` method (after line 43), add:

```swift
    /// Filter an array of messages, removing any from blocked users
    private func filterBlocked(_ messages: [Message]) -> [Message] {
        guard !cachedBlockedUserIds.isEmpty else { return messages }
        return messages.filter { !cachedBlockedUserIds.contains($0.fromId) }
    }
```

- [ ] **Step 2: Refactor fetchMessages to use filterBlocked**

Replace lines 206-210 (the stale comment and inline filter block):

```swift
        // Cache results (only cache if this is the initial load, not pagination)
        // Filter out messages from blocked users
        if !cachedBlockedUserIds.isEmpty {
            messages = messages.filter { !cachedBlockedUserIds.contains($0.fromId) }
        }
```

With:

```swift
        messages = filterBlocked(messages)
```

- [ ] **Step 3: Add filterBlocked to fetchMessagesCreatedAfter**

At line 270, change:

```swift
        return messages
```

To:

```swift
        return filterBlocked(messages)
```

- [ ] **Step 4: Add filterBlocked to fetchMediaMessages**

At line 299, change:

```swift
        return messages
```

To:

```swift
        return filterBlocked(messages)
```

Note: `fetchMediaMessages` has two code paths (image vs other types). The return at line 299 is after decoding. Verify you are editing the final return statement of the method.

- [ ] **Step 5: Add filterBlocked to fetchLinkMessages**

At line ~322-326, the method filters messages for URLs then returns. Wrap the existing filter:

Change:

```swift
        return messages.filter { message in
            guard !message.text.isEmpty else { return false }
            let range = NSRange(message.text.startIndex..., in: message.text)
            return (detector?.numberOfMatches(in: message.text, range: range) ?? 0) > 0
        }
```

To:

```swift
        return filterBlocked(messages.filter { message in
            guard !message.text.isEmpty else { return false }
            let range = NSRange(message.text.startIndex..., in: message.text)
            return (detector?.numberOfMatches(in: message.text, range: range) ?? 0) > 0
        })
```

- [ ] **Step 6: Add filterBlocked to fetchReplies**

At line 342, change:

```swift
        return messages
```

To:

```swift
        return filterBlocked(messages)
```

- [ ] **Step 7: Add filterBlocked to searchMessages**

At line 948, change:

```swift
        return messages
```

To:

```swift
        return filterBlocked(messages)
```

- [ ] **Step 8: Add filterBlocked to searchMessagesInConversation**

At line 992, change:

```swift
        return messages
```

To:

```swift
        return filterBlocked(messages)
```

- [ ] **Step 9: Commit**

```bash
git add NaarsCars/Core/Services/MessageService.swift
git commit -m "fix: add filterBlocked helper and apply to all message fetch methods"
```

---

### Task 5: Add localization keys for blocked user placeholders

**Files:**
- Edit: `NaarsCars/Resources/Localizable.xcstrings`

> **Why this comes before reply context and UI changes:** Tasks 6 and 11 use `"messaging_blocked_user".localized` and `"messaging_blocked_user_message".localized`. These keys must exist first, otherwise the app displays raw key strings at runtime.

- [ ] **Step 1: Add messaging_blocked_user key**

In `Localizable.xcstrings`, insert after the closing `},` of the `messaging_block_user_footer` entry (around line 17937) and before `messaging_cancel`:

```json
    "messaging_blocked_user" : {
      "localizations" : {
        "en" : {
          "stringUnit" : {
            "state" : "translated",
            "value" : "Blocked user"
          }
        }
      }
    },
```

- [ ] **Step 2: Add messaging_blocked_user_message key**

Add immediately after `messaging_blocked_user`:

```json
    "messaging_blocked_user_message" : {
      "localizations" : {
        "en" : {
          "stringUnit" : {
            "state" : "translated",
            "value" : "Message unavailable"
          }
        }
      }
    },
```

- [ ] **Step 3: Commit**

```bash
git add NaarsCars/Resources/Localizable.xcstrings
git commit -m "feat: add localization keys for blocked user placeholder text"
```

---

### Task 6: Sanitize reply contexts from blocked users

**Files:**
- Edit: `NaarsCars/Core/Services/MessageService.swift:444-454`

> Depends on Task 5 (localization keys) for correct runtime behavior.

- [ ] **Step 1: Replace the reply context loop body**

In `fetchReplyContexts`, replace the loop body at lines 444-454:

```swift
        for row in replyRows {
            contexts[row.id] = ReplyContext(
                id: row.id,
                text: row.text,
                senderName: row.sender?.name ?? "Unknown",
                senderId: row.fromId,
                imageUrl: row.imageUrl
            )
        }
```

With:

```swift
        for row in replyRows {
            if cachedBlockedUserIds.contains(row.fromId) {
                contexts[row.id] = ReplyContext(
                    id: row.id,
                    text: "messaging_blocked_user_message".localized,
                    senderName: "messaging_blocked_user".localized,
                    senderId: row.fromId,
                    imageUrl: nil
                )
            } else {
                contexts[row.id] = ReplyContext(
                    id: row.id,
                    text: row.text,
                    senderName: row.sender?.name ?? "Unknown",
                    senderId: row.fromId,
                    imageUrl: row.imageUrl
                )
            }
        }
```

- [ ] **Step 2: Commit**

```bash
git add NaarsCars/Core/Services/MessageService.swift
git commit -m "fix: sanitize reply contexts from blocked users with placeholder text"
```

---

### Task 7: Filter blocked users from typing indicators

**Files:**
- Edit: `NaarsCars/Core/Services/MessageService.swift:1060,1111`

- [ ] **Step 1: Filter fetchTypingUsers return value**

At line 1060, replace:

```swift
            return rows.map { TypingUser(id: $0.userId, name: $0.userName, avatarUrl: $0.avatarUrl) }
```

With:

```swift
            let users = rows.map { TypingUser(id: $0.userId, name: $0.userName, avatarUrl: $0.avatarUrl) }
            if !cachedBlockedUserIds.isEmpty {
                return users.filter { !cachedBlockedUserIds.contains($0.id) }
            }
            return users
```

- [ ] **Step 2: Filter fetchTypingUsersFallback return value**

At line 1111, replace:

```swift
            return profiles.map { TypingUser(id: $0.id, name: $0.name, avatarUrl: $0.avatarUrl) }
```

With:

```swift
            var users = profiles.map { TypingUser(id: $0.id, name: $0.name, avatarUrl: $0.avatarUrl) }
            if !cachedBlockedUserIds.isEmpty {
                users = users.filter { !cachedBlockedUserIds.contains($0.id) }
            }
            return users
```

- [ ] **Step 3: Commit**

```bash
git add NaarsCars/Core/Services/MessageService.swift
git commit -m "fix: filter blocked users from typing indicators"
```

---

## Chunk 3: Blocking Enforcement — Sync Engine, ViewModel, UI (Tasks 8-10)

### Task 8: Gate realtime upserts from blocked users

**Files:**
- Edit: `NaarsCars/Core/Storage/MessagingSyncEngine.swift:102`

- [ ] **Step 1: Add blocked user check in handleIncomingMessage**

In `MessagingSyncEngine.swift`, in the `handleIncomingMessage` method, after the message parsing guard (line 99-101) and before the `Task {` block (line 104), add:

```swift
        // Block realtime messages from blocked users
        if MessageService.shared.isBlocked(message.fromId) { return }
```

The result should read:

```swift
        guard let message = MessagingMapper.parseMessage(from: event.record) else {
            AppLogger.warning("messaging", "Failed to parse realtime message payload")
            return
        }

        // Block realtime messages from blocked users
        if MessageService.shared.isBlocked(message.fromId) { return }

        Task {
```

- [ ] **Step 2: Commit**

```bash
git add NaarsCars/Core/Storage/MessagingSyncEngine.swift
git commit -m "fix: gate realtime message upserts from blocked users"
```

---

### Task 9: Guard handleNewMessage from blocked users

**Files:**
- Edit: `NaarsCars/Features/Messaging/ViewModels/ConversationDetailViewModel.swift:558`

- [ ] **Step 1: Add blocked user check in handleNewMessage**

In `ConversationDetailViewModel.swift`, in the `handleNewMessage` method, after the existing guards (lines 555-562) and before the `messages = paginationManager.insertNewMessage(...)` call (line 564), add:

```swift
        // Skip messages from blocked users
        if MessageService.shared.isBlocked(newMessage.fromId) { return }
```

The result should read:

```swift
        // Skip messages the user has locally deleted ("Delete for Me")
        let deletedIds = repository.fetchLocallyDeletedMessageIds(for: conversationId)
        guard !deletedIds.contains(newMessage.id) else { return }

        // Skip messages from blocked users
        if MessageService.shared.isBlocked(newMessage.fromId) { return }

        messages = paginationManager.insertNewMessage(newMessage, into: messages)
```

- [ ] **Step 2: Commit**

```bash
git add NaarsCars/Features/Messaging/ViewModels/ConversationDetailViewModel.swift
git commit -m "fix: guard handleNewMessage from blocked users (defense-in-depth)"
```

---

### Task 10: Blocked user placeholder in conversation list preview

**Files:**
- Edit: `NaarsCars/Features/Messaging/Views/ConversationRow.swift:113`

- [ ] **Step 1: Add blocked check to messagePreviewText**

In `ConversationRow.swift`, in the `messagePreviewText` method (line 113), add a blocked user check at the very top of the function body:

Change:

```swift
    private func messagePreviewText(_ message: Message) -> String {
        if message.isAudioMessage {
```

To:

```swift
    private func messagePreviewText(_ message: Message) -> String {
        if MessageService.shared.isBlocked(message.fromId) {
            return "messaging_blocked_user_message".localized
        }
        if message.isAudioMessage {
```

- [ ] **Step 2: Commit**

```bash
git add NaarsCars/Features/Messaging/Views/ConversationRow.swift
git commit -m "fix: show placeholder text for blocked user messages in conversation list"
```

---

## Chunk 4: Verification (Task 11)

### Task 11: End-to-end verification

- [ ] **Step 1: Verify Fix 1 — reports constraint is clean**

Execute via Supabase MCP:

```sql
SELECT conname, pg_get_constraintdef(oid)
FROM pg_constraint
WHERE conrelid = 'public.reports'::regclass
AND contype = 'c'
AND conname LIKE '%target_check%';
```

Expected: exactly 1 row — `report_target_check`.

- [ ] **Step 2: Verify Fix 2 — submit_report rejects spoofed reporter**

Execute via Supabase MCP:

```sql
SELECT prosrc FROM pg_proc WHERE proname = 'submit_report';
```

Verify the function body contains `auth.uid() != p_reporter_id` guard and uses `auth.uid()` in the INSERT.

- [ ] **Step 3: Verify Fix 3 — review all modified Swift files compile**

Run a build check:

```bash
cd /Users/bcolf/Documents/naars-cars-ios
xcodebuild -scheme NaarsCars -destination 'platform=iOS Simulator,name=iPhone 16' build 2>&1 | tail -20
```

Expected: `BUILD SUCCEEDED` (or at minimum, no errors in the files we modified).

- [ ] **Step 4: Verify Fix 4 — comments are present in source**

Read `database/128_fix_delete_user_account_auth_guard.sql` and confirm the FK cascade comments are present before the `town_hall_posts` and `profiles` DELETE statements.

- [ ] **Step 5: Final commit — stage remaining 128_*.sql files**

The five `128_*.sql` files capture fixes already applied live but never committed to source. Tasks 1-3 updated three of them. The remaining two are:

- `128_fix_notification_queue_service_role.sql` — Restricts `notification_queue` RLS to service_role only (INSERT/SELECT/UPDATE). Already live.
- `128_fix_notifications_insert_policy.sql` — Tightens `notifications` INSERT policy to `auth.uid() = user_id`. Already live.

Commit them as source-of-truth records:

```bash
git add database/128_fix_delete_user_account_auth_guard.sql
git add database/128_fix_notification_queue_service_role.sql
git add database/128_fix_notifications_insert_policy.sql
git status
git commit -m "chore: commit remaining 128_* migration source-of-truth files"
```
