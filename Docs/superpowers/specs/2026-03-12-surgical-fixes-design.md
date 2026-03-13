# Surgical Fixes: Reports, Auth, and Blocking Enforcement

**Date:** 2026-03-12
**Status:** Approved
**Scope:** 4 fixes addressing GPT 5.4 review findings — validated against live Supabase

---

## Context

A GPT 5.4 review identified critical/high issues in the app. We validated each finding against the live Supabase database and the source code. Several findings were not live issues (the DB already had correct FK behavior) but the source SQL doesn't match reality. The real remaining issues are:

1. Source SQL drift from live DB (FK behavior, duplicate constraint)
2. `submit_report` trusts caller-supplied `p_reporter_id` in a SECURITY DEFINER function
3. Blocked-user content leaks through 9 of 10 messaging code paths and multiple UI surfaces
4. `delete_user_account` source doesn't document its FK cascade dependencies

### Live Supabase vs Source SQL (Key Differences)

| Item | Source SQL | Live DB |
|------|-----------|---------|
| `reported_post_id` FK | No cascade (RESTRICT) | `ON DELETE SET NULL` |
| `reported_comment_id` FK | No cascade (RESTRICT) | `ON DELETE SET NULL` |
| Check constraint name | Drops `reports_target_check` | Both `report_target_check` AND `reports_target_check` exist (duplicate) |
| `messages_filtered` view | Defined in 087 | Does not exist |
| `is_user_blocked()` function | Defined in 087 | Exists and works |
| `submit_report` auth | Trusts `p_reporter_id` | Trusts `p_reporter_id` (confirmed vulnerable) |

---

## Fix 1: Reports Migration — Source Accuracy + Duplicate Constraint

### Problem

`database/128_fix_reports_add_post_comment_columns.sql` has two issues:

1. **FK behavior mismatch:** Lines 5-6 use bare `REFERENCES` (defaults to RESTRICT), but live DB has `ON DELETE SET NULL`. If the DB were recreated from source, `delete_user_account` would hit FK violations when deleting posts/comments that have been reported.

2. **Constraint name mismatch:** Line 9 drops `reports_target_check` (plural), but the original constraint from `087_reports_and_blocking.sql:28` is named `report_target_check` (singular). The DROP silently does nothing, so the migration creates a second constraint. Live DB now has both.

### Changes

**File:** `database/128_fix_reports_add_post_comment_columns.sql`

Rewrite to match live reality:

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

**Live DB action:** Execute the following to clean up the duplicate constraint:

```sql
ALTER TABLE reports DROP CONSTRAINT IF EXISTS reports_target_check;
```

The remaining `report_target_check` already has the correct 4-column definition live.

### Risk

Near-zero. FKs already exist live with SET NULL. Source file is brought into alignment. Dropping the duplicate constraint has no functional impact.

---

## Fix 2: submit_report Auth Guard

### Problem

`submit_report` is a `SECURITY DEFINER` function that accepts `p_reporter_id` as a caller-supplied parameter and uses it directly for INSERT and duplicate checks. Any authenticated user can attribute reports to another user. This is a real security vulnerability confirmed live.

### Approach

**Guard + override (Approach B):** Add `auth.uid()` validation at the top. Replace all internal uses of `p_reporter_id` with `auth.uid()`. Keep the parameter in the function signature for API backward compatibility — no Swift client changes needed.

### Changes

**File:** `database/128_fix_submit_report_post_comment.sql`

```sql
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

**Live DB action:** Execute `CREATE OR REPLACE FUNCTION` with the above to redeploy.

### Risk

Low. The client already passes `auth.uid()` as `reporterId` in all 4 Swift call sites (`reportUser`, `reportMessage`, `reportPost`, `reportComment` in MessageService.swift:773-835). No legitimate calls will break. The guard + override is belt-and-suspenders.

---

## Fix 3: Blocking Enforcement — Backend Through Frontend

### Problem

Blocked-user content leaks through 9 of 10 messaging code paths. Only `fetchMessages` (the initial conversation load) filters blocked users. Incremental sync, search, media galleries, replies, realtime inserts, typing indicators, and reply context previews all expose blocked user content.

### Design Principles

- **Content from blocked users** (messages, reply text, typing indicators) → MUST hide
- **Membership/presence of blocked users** (group titles, participant lists, read receipts) → Do NOT hide. Hiding group membership is misleading. iMessage, WhatsApp, and Signal all show blocked group members by name.

### 3a. MessageService.swift — filterBlocked helper

**Add after `isBlocked` (line 43):**

```swift
/// Filter an array of messages, removing any from blocked users
private func filterBlocked(_ messages: [Message]) -> [Message] {
    guard !cachedBlockedUserIds.isEmpty else { return messages }
    return messages.filter { !cachedBlockedUserIds.contains($0.fromId) }
}
```

**Apply to these methods (replace return with `return filterBlocked(...)`):**

| Method | Location | Current return | New return |
|--------|----------|---------------|------------|
| `fetchMessages` | line 208-210 | 3-line inline filter | `return filterBlocked(messages)` |
| `fetchMessagesCreatedAfter` | line 270 | `return messages` | `return filterBlocked(messages)` |
| `fetchMediaMessages` | line 299 | `return messages` | `return filterBlocked(messages)` |
| `fetchLinkMessages` | line 326 | `return messages.filter { urlCheck }` | `return filterBlocked(messages.filter { urlCheck })` |
| `fetchReplies` | line 342 | `return messages` | `return filterBlocked(messages)` |
| `searchMessages` | line 948 | `return messages` | `return filterBlocked(messages)` |
| `searchMessagesInConversation` | line 992 | `return messages` | `return filterBlocked(messages)` |

### 3b. MessageService.swift — Reply context sanitization

**In `fetchReplyContexts` (line 444), replace the loop body:**

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

When a non-blocked user's message replies to a blocked user's message, the reply preview shows "Blocked user" / "Message unavailable" instead of the actual name and content.

### 3c. MessageService.swift — Typing indicator filtering

**In `fetchTypingUsers` (line 1060), wrap the return:**

```swift
let users = rows.map { TypingUser(id: $0.userId, name: $0.userName, avatarUrl: $0.avatarUrl) }
if !cachedBlockedUserIds.isEmpty {
    return users.filter { !cachedBlockedUserIds.contains($0.id) }
}
return users
```

**In `fetchTypingUsersFallback` (line 1111), same pattern:**

```swift
var users = profiles.map { TypingUser(id: $0.id, name: $0.name, avatarUrl: $0.avatarUrl) }
if !cachedBlockedUserIds.isEmpty {
    users = users.filter { !cachedBlockedUserIds.contains($0.id) }
}
return users
```

### 3d. MessagingSyncEngine.swift — Gate realtime upserts

**In `handleIncomingMessage` (after line 102, before the Task):**

```swift
// Block realtime messages from blocked users
if MessageService.shared.isBlocked(message.fromId) { return }
```

Prevents blocked messages from entering SwiftData or posting `.conversationUpdated` notifications.

### 3e. ConversationDetailViewModel.swift — Guard handleNewMessage

**In `handleNewMessage` (line 558, after existing guards):**

```swift
// Skip messages from blocked users
if MessageService.shared.isBlocked(newMessage.fromId) { return }
```

Defense-in-depth for any blocked message that bypasses the sync engine gate.

### 3f. ConversationRow.swift — Last message preview

**In `messagePreviewText` (line 113), add blocked check at the top:**

```swift
private func messagePreviewText(_ message: Message) -> String {
    if MessageService.shared.isBlocked(message.fromId) {
        return "messaging_blocked_user_message".localized
    }
    // ... existing logic unchanged
}
```

### 3g. Localizable.xcstrings — New keys

Add two English-language entries:

- `messaging_blocked_user` → `"Blocked user"`
- `messaging_blocked_user_message` → `"Message unavailable"`

### What is NOT changed (membership vs content)

| UI Surface | Action | Reasoning |
|-----------|--------|-----------|
| Group conversation titles | No change | Hiding membership is misleading |
| Participant lists / "View Members" | No change | Users need to know who's in the group |
| Read receipt avatars | No change | Metadata about your own message delivery |
| `fetchMessageById` | No change | Guarded by reply context sanitization and realtime gate |
| Conversation list sort order | No change | A blocked user's message may push a conversation to the top of the list. iMessage behaves the same way — blocking hides content, not activity. |

### Known Limitations

**SwiftData historical messages:** If User A's messages are already in SwiftData when User B blocks them, those messages remain in the local store until the next full network sync replaces them. The realtime gate (3d) prevents *new* blocked messages from entering SwiftData, and the fetch filters (3a) prevent blocked messages from being returned by API calls. The gap is messages written to SwiftData before the block was created. These are flushed on the next sync cycle, which is acceptable for this round.

**Thread safety of `cachedBlockedUserIds`:** `MessageService` is a plain `final class` with no actor isolation. The `cachedBlockedUserIds` property is mutated in `refreshBlockedUsers()` (an async method) and read from `@MainActor` contexts. This is a pre-existing architectural concern — the property and `isBlocked()` method already exist at lines 27-43. This spec adds more call sites for the existing pattern but does not introduce new unsafety. A follow-up should either mark `MessageService` as `@MainActor` or protect `cachedBlockedUserIds` with a lock.

### Risk

Low. All changes are additive filters or content replacements. If `cachedBlockedUserIds` is empty (not yet loaded), every filter is a no-op — existing behavior preserved. No data mutations, no API signature changes, no layout changes.

---

## Fix 4: delete_user_account Source Documentation

### Problem

The function works correctly due to FK cascades, but the source SQL doesn't document these dependencies. Future developers (or AI reviewers) flag missing explicit deletes for `town_hall_comments`, `reports`, and `blocked_users` as bugs.

### Changes

**File:** `database/128_fix_delete_user_account_auth_guard.sql`

Add comments before line 124 (town_hall_posts delete):

```sql
-- town_hall_comments: CASCADE-deleted via town_hall_comments_post_id_fkey
-- reports.reported_post_id: SET NULL via reports_reported_post_id_fkey
-- reports.reported_comment_id: SET NULL via reports_reported_comment_id_fkey
DELETE FROM town_hall_posts WHERE user_id = p_user_id;
```

Add comments before line 132 (profiles delete):

```sql
-- reports.reporter_id: CASCADE-deleted via reports_reporter_id_fkey
-- reports.reported_user_id: CASCADE-deleted via reports_reported_user_id_fkey
-- blocked_users: CASCADE-deleted via both blocker_id and blocked_id FKs
DELETE FROM profiles WHERE id = p_user_id;
```

### Risk

Zero. Comments only. No behavioral change.

---

## Complete Change Manifest

| Fix | Files Modified | Live DB Action | Risk |
|-----|---------------|----------------|------|
| 1. Reports migration accuracy | `128_fix_reports_add_post_comment_columns.sql` | Drop duplicate `reports_target_check` | Near-zero |
| 2. submit_report auth | `128_fix_submit_report_post_comment.sql` | Redeploy function | Low |
| 3. Blocking enforcement | `MessageService.swift`, `MessagingSyncEngine.swift`, `ConversationDetailViewModel.swift`, `ConversationRow.swift`, `Localizable.xcstrings` | None | Low |
| 4. delete_user_account docs | `128_fix_delete_user_account_auth_guard.sql` | None | Zero |

## Execution Order

All four fixes are independent and can be developed in parallel. No ordering dependencies between them.

For live DB actions (Fixes 1-2): Apply via Supabase MCP after source files are updated and committed.

## Testing Plan

- **Fix 1:** Verify only one `report_target_check` constraint exists after applying
- **Fix 2:** Test `submit_report` with mismatched `p_reporter_id` — should raise exception. Test with correct ID — should succeed.
- **Fix 3:**
  - Block a user, verify their messages don't appear in: initial load, incremental sync, search, media gallery, link gallery, replies, realtime
  - Verify reply previews to blocked user messages show "Blocked user" / "Message unavailable"
  - Verify blocked users don't appear in typing indicators
  - Verify conversation list preview shows "Message unavailable" for blocked user's last message
  - Verify group titles and participant lists still show blocked user names
- **Fix 4:** Read-only verification — review comments match live FK behavior
