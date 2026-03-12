# Group Messaging Enhancement Plan

> **For Claude:** REQUIRED SUB-SKILL: Use superpowers:executing-plans to implement this plan task-by-task.

**Goal:** Enhance the existing messaging system to fully support the Group Messaging PRD — history visibility boundaries, frozen leave state, mute infrastructure, read receipt enhancements, member management constraints, system event completeness, "Delete for Me", admin role removal, and deleted user handling.

**Architecture:** Phased approach starting with Supabase migrations (schema changes), then iOS model updates, then service/UI changes. Each phase builds on the prior. Independent workstreams are called out for parallel execution where possible.

**Tech Stack:** Swift/SwiftUI (iOS 17+), SwiftData, Supabase (PostgreSQL + Realtime + Edge Functions), APNs

**Decisions locked in:**
- Flat permission model — no admin role for messaging. Any participant can add/remove any other participant. Remove `is_admin` from `conversation_participants`.
- Edit and unsend windows both remain at 15 minutes (diverge from iMessage's shorter windows).
- System messages keep actor in `fromId` (option A) — actor name encoded in message text, no null sender_id.
- Read receipts: profile photo thumbnails in groups, checkmarks in 1:1 DMs.
- Read receipt opt-out: global setting on `profiles` table + per-conversation override on `conversation_participants`.
- Muted conversations: badge still increments, but no APNs push and no in-app banners/sounds.
- "Delete for Me" stored in SwiftData locally.
- Frozen left conversations stay in main list sorted normally; user can dismiss them like any other conversation.
- History visibility filter applied retroactively — members added after messages existed will lose visibility of prior messages.
- Deleted user cleanup: soft-delete participant records, show "Deleted User" throughout app.
- Auto-generated 2x2 group avatar: implemented as a standalone subagent task.

---

## Dependency Graph

```
Phase 1: DB Migrations ──> Phase 2: iOS Models ──> Phases 3-10 (parallel workstreams)
                                                    ├── Phase 3: History Visibility (P0)
                                                    ├── Phase 4: Leave/Frozen State (P0)
                                                    ├── Phase 5: Muting Infrastructure (P0)
                                                    ├── Phase 6: Member Management Constraints
                                                    ├── Phase 7: Read Receipts Enhancement
                                                    ├── Phase 8: System Events Completeness
                                                    ├── Phase 9: Delete for Me
                                                    ├── Phase 10: Polish (group name limit, reply fallback, deleted user)
                                                    └── Phase 11: Auto-generated Group Avatar (subagent)
```

---

## Phase 1: Database Migrations

All migrations go in `/supabase/migrations/`. Each task is one migration file.

### Task 1.1: Add `added_by` and mute fields to `conversation_participants`

**Files:**
- Create: `supabase/migrations/20260307_0001_participant_mute_and_added_by.sql`

**Step 1: Write the migration**

```sql
-- Add added_by to track who added each participant
ALTER TABLE public.conversation_participants
  ADD COLUMN IF NOT EXISTS added_by uuid REFERENCES public.profiles(id);

-- Add per-conversation mute fields
ALTER TABLE public.conversation_participants
  ADD COLUMN IF NOT EXISTS notifications_muted boolean NOT NULL DEFAULT false;

ALTER TABLE public.conversation_participants
  ADD COLUMN IF NOT EXISTS muted_until timestamptz;

-- Add per-conversation read receipt override (null = use global setting)
ALTER TABLE public.conversation_participants
  ADD COLUMN IF NOT EXISTS show_read_receipts boolean;
```

**Step 2: Apply migration**

Run: `supabase db push` or apply via Supabase MCP tool
Expected: Migration succeeds, columns added

**Step 3: Commit**

```bash
git add supabase/migrations/20260307_0001_participant_mute_and_added_by.sql
git commit -m "migration: add added_by, mute fields, read receipt override to conversation_participants"
```

---

### Task 1.2: Add `show_read_receipts` to `profiles` table

**Files:**
- Create: `supabase/migrations/20260307_0002_profile_read_receipts.sql`

**Step 1: Write the migration**

```sql
-- Global read receipt preference on profile
ALTER TABLE public.profiles
  ADD COLUMN IF NOT EXISTS show_read_receipts boolean NOT NULL DEFAULT true;
```

**Step 2: Apply migration**

**Step 3: Commit**

```bash
git add supabase/migrations/20260307_0002_profile_read_receipts.sql
git commit -m "migration: add show_read_receipts to profiles"
```

---

### Task 1.3: Remove `is_admin` from `conversation_participants`

**Files:**
- Create: `supabase/migrations/20260307_0003_remove_participant_is_admin.sql`

**Step 1: Write the migration**

First, audit existing RLS policies that reference `is_admin` on `conversation_participants`. Based on codebase exploration, the `is_admin` on conversation_participants is NOT referenced in any RLS policies (the `is_admin_user()` function references `profiles.is_admin` for app-level admin, which is separate). The column is only used in the Swift model. Safe to drop.

```sql
-- Remove is_admin from conversation_participants (flat permission model)
-- Note: profiles.is_admin (app-level admin) is NOT affected
ALTER TABLE public.conversation_participants
  DROP COLUMN IF EXISTS is_admin;
```

**Step 2: Apply migration**

**Step 3: Commit**

```bash
git add supabase/migrations/20260307_0003_remove_participant_is_admin.sql
git commit -m "migration: remove is_admin from conversation_participants (flat permission model)"
```

---

### Task 1.4: Add history visibility RLS policy

**Files:**
- Create: `supabase/migrations/20260307_0004_history_visibility_rls.sql`

**Step 1: Write the migration**

This is the P0 privacy fix. New/re-added members must only see messages created after their `joined_at`. We tighten the existing SELECT policy on `messages`.

```sql
-- Drop existing SELECT policy on messages
DROP POLICY IF EXISTS "messages_select_for_participants" ON public.messages;

-- Recreate with joined_at visibility boundary
-- Users can see messages if:
--   1. They are the conversation creator, OR
--   2. They are an active participant (or were a participant) AND the message was created
--      after their joined_at timestamp
CREATE POLICY "messages_select_for_participants" ON public.messages
  FOR SELECT USING (
    -- Conversation creator can see all messages
    EXISTS (
      SELECT 1 FROM public.conversations c
      WHERE c.id = messages.conversation_id
        AND c.created_by = auth.uid()
    )
    OR
    -- Participant can see messages created after they joined
    EXISTS (
      SELECT 1 FROM public.conversation_participants cp
      WHERE cp.conversation_id = messages.conversation_id
        AND cp.user_id = auth.uid()
        AND messages.created_at >= cp.joined_at
    )
  );
```

**Step 2: Apply migration**

**Step 3: Verify**

Run a test query: a participant added after messages exist should NOT see those older messages.

**Step 4: Commit**

```bash
git add supabase/migrations/20260307_0004_history_visibility_rls.sql
git commit -m "migration: enforce history visibility boundary via RLS (P0 privacy fix)"
```

---

### Task 1.5: Update `leave_conversation` RPC with minimum member check

**Files:**
- Create: `supabase/migrations/20260307_0005_leave_conversation_min_members.sql`

**Step 1: Write the migration**

```sql
-- Replace leave_conversation to enforce minimum 3 remaining active members
CREATE OR REPLACE FUNCTION public.leave_conversation(
    p_conversation_id UUID,
    p_user_id UUID
)
RETURNS BOOLEAN
LANGUAGE plpgsql
SECURITY DEFINER
SET search_path = public
AS $$
DECLARE
    v_participant_exists BOOLEAN;
    v_already_left BOOLEAN;
    v_active_count INT;
BEGIN
    -- Check if user is a participant
    SELECT EXISTS (
        SELECT 1 FROM conversation_participants
        WHERE conversation_id = p_conversation_id
        AND user_id = p_user_id
    ) INTO v_participant_exists;

    IF NOT v_participant_exists THEN
        RAISE EXCEPTION 'User is not a participant in this conversation';
    END IF;

    -- Check if already left
    SELECT EXISTS (
        SELECT 1 FROM conversation_participants
        WHERE conversation_id = p_conversation_id
        AND user_id = p_user_id
        AND left_at IS NOT NULL
    ) INTO v_already_left;

    IF v_already_left THEN
        RETURN FALSE;
    END IF;

    -- Count active members (excluding the user who wants to leave)
    SELECT COUNT(*) INTO v_active_count
    FROM conversation_participants
    WHERE conversation_id = p_conversation_id
      AND left_at IS NULL
      AND user_id != p_user_id;

    -- Must leave at least 3 active members behind (so group has 4+ before leaving)
    IF v_active_count < 3 THEN
        RAISE EXCEPTION 'Cannot leave: group must have at least 3 remaining members';
    END IF;

    -- Update left_at timestamp
    UPDATE conversation_participants
    SET left_at = NOW()
    WHERE conversation_id = p_conversation_id
    AND user_id = p_user_id;

    RETURN TRUE;
END;
$$;

GRANT EXECUTE ON FUNCTION public.leave_conversation(UUID, UUID) TO authenticated;
```

**Step 2: Apply migration**

**Step 3: Commit**

```bash
git add supabase/migrations/20260307_0005_leave_conversation_min_members.sql
git commit -m "migration: enforce minimum 3 remaining members on leave_conversation"
```

---

### Task 1.6: Add `edit_message` 15-minute time window enforcement

**Files:**
- Create: `supabase/migrations/20260307_0006_edit_message_time_window.sql`

**Step 1: Write the migration**

The existing `edit_message` RPC has no time window. Add the 15-minute check.

```sql
CREATE OR REPLACE FUNCTION public.edit_message(
    p_message_id uuid,
    p_new_content text
)
RETURNS void
LANGUAGE plpgsql
SECURITY DEFINER
AS $$
DECLARE
    v_created_at timestamptz;
BEGIN
    -- Get message and verify ownership
    SELECT created_at INTO v_created_at
    FROM public.messages
    WHERE id = p_message_id
      AND from_id = auth.uid()
      AND deleted_at IS NULL;

    IF v_created_at IS NULL THEN
        RAISE EXCEPTION 'Message not found or you are not the sender';
    END IF;

    -- Enforce 15-minute edit window
    IF now() - v_created_at > interval '15 minutes' THEN
        RAISE EXCEPTION 'Messages can only be edited within 15 minutes of sending';
    END IF;

    -- Log old content to audit
    INSERT INTO public.message_audit_log (id, user_id, action, message_id, old_content, created_at)
    SELECT gen_random_uuid(), auth.uid(), 'edit', p_message_id, text, now()
    FROM public.messages WHERE id = p_message_id;

    UPDATE public.messages
    SET text = p_new_content,
        edited_at = now()
    WHERE id = p_message_id
      AND from_id = auth.uid();
END;
$$;

GRANT EXECUTE ON FUNCTION public.edit_message(uuid, text) TO authenticated;
```

**Step 2: Apply migration**

**Step 3: Commit**

```bash
git add supabase/migrations/20260307_0006_edit_message_time_window.sql
git commit -m "migration: add 15-minute time window to edit_message RPC"
```

---

### Task 1.7: Update `delete_user_account` for soft-delete messaging cleanup

**Files:**
- Create: `supabase/migrations/20260307_0007_soft_delete_user_messaging.sql`

**Step 1: Write the migration**

Instead of hard-deleting messages and participant records, soft-delete them so "Deleted User" is visible.

```sql
-- Create a helper function that soft-deletes a user's messaging presence
-- Called during account deletion instead of hard DELETE
CREATE OR REPLACE FUNCTION public.soft_delete_user_messaging(p_user_id UUID)
RETURNS void
LANGUAGE plpgsql
SECURITY DEFINER
SET search_path = public
AS $$
BEGIN
    -- Soft-delete all participant records (set left_at)
    UPDATE conversation_participants
    SET left_at = NOW()
    WHERE user_id = p_user_id
      AND left_at IS NULL;

    -- Soft-delete all messages sent by user (set deleted_at, clear text)
    UPDATE messages
    SET deleted_at = NOW(),
        text = '[Message from deleted user]'
    WHERE from_id = p_user_id
      AND deleted_at IS NULL;
END;
$$;

GRANT EXECUTE ON FUNCTION public.soft_delete_user_messaging(UUID) TO service_role;
```

Note: The existing `delete_user_account` RPC in `database/046_create_delete_account_function.sql` hard-deletes messages and conversation_participants. The caller of account deletion should call `soft_delete_user_messaging` BEFORE the hard delete cascade, or the hard deletes for messaging tables should be replaced with this soft-delete approach. The implementing engineer should update the `delete_user_account` function to call `soft_delete_user_messaging(p_user_id)` and remove the `DELETE FROM messages WHERE from_id = p_user_id` and `DELETE FROM conversation_participants WHERE user_id = p_user_id` lines.

**Step 2: Apply migration**

**Step 3: Commit**

```bash
git add supabase/migrations/20260307_0007_soft_delete_user_messaging.sql
git commit -m "migration: add soft_delete_user_messaging for graceful account deletion"
```

---

## Phase 2: iOS Model Updates

### Task 2.1: Update `ConversationParticipant` struct

**Files:**
- Modify: `NaarsCars/Core/Models/Conversation.swift:127-173`

**Step 1: Update the struct**

Remove `isAdmin`, add `addedBy`, `notificationsMuted`, `mutedUntil`, `showReadReceipts`.

Replace lines 127-173 with:

```swift
struct ConversationParticipant: Codable, Identifiable, Equatable, Sendable {
    let id: UUID
    let conversationId: UUID
    let userId: UUID
    let joinedAt: Date
    var leftAt: Date?
    var lastSeen: Date?
    let addedBy: UUID?
    var notificationsMuted: Bool
    var mutedUntil: Date?
    var showReadReceipts: Bool?

    /// Whether this participant has left the conversation
    var hasLeft: Bool {
        leftAt != nil
    }

    /// Whether this participant is currently active (joined and not left)
    var isActive: Bool {
        leftAt == nil
    }

    /// Whether notifications are effectively muted (permanent or timed)
    var isEffectivelyMuted: Bool {
        if notificationsMuted { return true }
        if let until = mutedUntil, until > Date() { return true }
        return false
    }

    enum CodingKeys: String, CodingKey {
        case id
        case conversationId = "conversation_id"
        case userId = "user_id"
        case joinedAt = "joined_at"
        case leftAt = "left_at"
        case lastSeen = "last_seen"
        case addedBy = "added_by"
        case notificationsMuted = "notifications_muted"
        case mutedUntil = "muted_until"
        case showReadReceipts = "show_read_receipts"
    }

    init(
        id: UUID = UUID(),
        conversationId: UUID,
        userId: UUID,
        joinedAt: Date = Date(),
        leftAt: Date? = nil,
        lastSeen: Date? = nil,
        addedBy: UUID? = nil,
        notificationsMuted: Bool = false,
        mutedUntil: Date? = nil,
        showReadReceipts: Bool? = nil
    ) {
        self.id = id
        self.conversationId = conversationId
        self.userId = userId
        self.joinedAt = joinedAt
        self.leftAt = leftAt
        self.lastSeen = lastSeen
        self.addedBy = addedBy
        self.notificationsMuted = notificationsMuted
        self.mutedUntil = mutedUntil
        self.showReadReceipts = showReadReceipts
    }
}
```

**Step 2: Fix all compile errors from `isAdmin` removal**

Search entire project for references to `isAdmin` on `ConversationParticipant` (NOT `Profile.isAdmin` — that stays):

```
grep -rn "\.isAdmin" --include="*.swift" | grep -i participant
grep -rn "isAdmin:" --include="*.swift" | grep -iv "profile\|admin.*service\|admin.*check"
```

Key locations to fix:
- `ConversationParticipantService.swift` — any participant insert that includes `is_admin` key
- `ConversationService.swift:468-472` — participant insert dicts (remove `is_admin` key if present)
- Any `ConversationParticipant(...)` initializer calls that pass `isAdmin:`

Remove `isAdmin` from all participant insert dictionaries and initializer calls.

**Step 3: Build and verify no compile errors**

Run: `xcodebuild build -scheme NaarsCars -destination 'platform=iOS Simulator,name=iPhone 16'`
Expected: BUILD SUCCEEDED

**Step 4: Commit**

```bash
git add NaarsCars/Core/Models/Conversation.swift
git add -u  # catch all files fixed for isAdmin removal
git commit -m "feat: update ConversationParticipant — remove isAdmin, add mute/addedBy/readReceipts fields"
```

---

### Task 2.2: Update `Profile` struct with `showReadReceipts`

**Files:**
- Modify: `NaarsCars/Core/Models/Profile.swift:22-29` (notification preferences block)

**Step 1: Add field after the existing notification preferences**

Add `showReadReceipts` after line 29 (`notifyTownHall`):

```swift
let showReadReceipts: Bool
```

**Step 2: Add CodingKey**

In the CodingKeys enum, add:

```swift
case showReadReceipts = "show_read_receipts"
```

**Step 3: Build and fix any decode issues**

The Profile struct uses `Codable` auto-synthesis. Adding a non-optional `Bool` field means existing data without this column will fail to decode. Since we added the column with `DEFAULT true`, server responses will include it. But if any local cache or test fixture is missing it, it will fail. If needed, make it `let showReadReceipts: Bool = true` or provide a custom decoder fallback. Safest approach — use `init(from decoder:)` to default to `true` if missing, or simply make it optional with a default:

```swift
let showReadReceipts: Bool?
```

And use a computed property:

```swift
var effectiveShowReadReceipts: Bool {
    showReadReceipts ?? true
}
```

**Step 4: Commit**

```bash
git add NaarsCars/Core/Models/Profile.swift
git commit -m "feat: add showReadReceipts to Profile model"
```

---

### Task 2.3: Add `SDDeletedMessage` SwiftData model for "Delete for Me"

**Files:**
- Modify: `NaarsCars/Core/Storage/SDModels.swift` (add new model after SDMessage, around line 106)

**Step 1: Add the model**

Insert after line 106 (after SDMessage closing brace):

```swift
/// Locally hidden messages ("Delete for Me" — not synced to server)
@Model
final class SDDeletedMessage {
    @Attribute(.unique) var messageId: UUID
    var conversationId: UUID
    var deletedAt: Date

    init(messageId: UUID, conversationId: UUID, deletedAt: Date = Date()) {
        self.messageId = messageId
        self.conversationId = conversationId
        self.deletedAt = deletedAt
    }
}
```

**Step 2: Register in SwiftData ModelContainer**

In `NaarsCars/App/NaarsCarsApp.swift` (around line 42-62 where the container is initialized), add `SDDeletedMessage.self` to the Schema array.

Find the `Schema([...])` call and add `SDDeletedMessage.self` to the array.

**Step 3: Build and verify**

Run build. Expected: BUILD SUCCEEDED.

**Step 4: Commit**

```bash
git add NaarsCars/Core/Storage/SDModels.swift NaarsCars/App/NaarsCarsApp.swift
git commit -m "feat: add SDDeletedMessage SwiftData model for local Delete-for-Me"
```

---

## Phase 3: History Visibility Boundary (P0)

RLS was handled in Task 1.4. This phase adds the client-side defense-in-depth filter.

### Task 3.1: Add `joined_at` filter to `MessageService.fetchMessages`

**Files:**
- Modify: `NaarsCars/Core/Services/MessageService.swift:106-164`

**Step 1: Fetch the current user's `joined_at` timestamp**

After the `ensureConversationMembership` check (line 114), add a query to get the participant's `joined_at`:

```swift
// Defense-in-depth: fetch participant's joined_at for history visibility boundary
let joinedAt: Date? = await {
    let resp = try? await supabase
        .from("conversation_participants")
        .select("joined_at")
        .eq("conversation_id", value: conversationId.uuidString)
        .eq("user_id", value: currentUserId.uuidString)
        .order("joined_at", ascending: false) // Most recent join (for re-added members)
        .limit(1)
        .single()
        .execute()
    guard let data = resp?.data else { return nil }
    struct JoinRow: Codable {
        let joinedAt: Date
        enum CodingKeys: String, CodingKey { case joinedAt = "joined_at" }
    }
    return try? createDateDecoder().decode(JoinRow.self, from: data).joinedAt
}()
```

**Step 2: Apply the filter to the query**

After line 118 (`.eq("conversation_id", ...)`), add:

```swift
// History visibility: only show messages from after participant joined
if let joinedAt = joinedAt {
    let formatter = createISO8601Formatter()
    query = query.gte("created_at", value: formatter.string(from: joinedAt))
}
```

**Step 3: Apply the same filter to `fetchMessagesCreatedAfter`**

In `fetchMessagesCreatedAfter` (around line 168), add the same `joined_at` lookup and filter. The `after` date should be the later of `after` and `joinedAt`:

```swift
let effectiveAfter: Date
if let joinedAt = joinedAt {
    effectiveAfter = max(after, joinedAt)
} else {
    effectiveAfter = after
}
```

Use `effectiveAfter` in the `.gt("created_at", ...)` call.

**Step 4: Build and verify**

**Step 5: Commit**

```bash
git add NaarsCars/Core/Services/MessageService.swift
git commit -m "fix: enforce history visibility boundary in client message fetch (P0 privacy)"
```

---

## Phase 4: Leave / Frozen Conversation State (P0)

### Task 4.1: Add frozen state detection to `ConversationDetailViewModel`

**Files:**
- Modify: `NaarsCars/Features/Messaging/ViewModels/ConversationDetailViewModel.swift`

**Step 1: Add published property for left state**

Near line 52 (after `@Published private(set) var unreadCount`), add:

```swift
@Published private(set) var hasLeftConversation: Bool = false
@Published private(set) var leftAt: Date?
```

**Step 2: Add method to check left status**

Add a method that queries the participant record:

```swift
func checkLeftStatus() async {
    guard let userId = authService.currentUserId else { return }
    let hasLeft = await ConversationParticipantService.shared.hasUserLeftConversation(
        conversationId: conversationId,
        userId: userId
    )
    await MainActor.run {
        self.hasLeftConversation = hasLeft
    }
}
```

**Step 3: Call on load**

In the `loadMessages()` method (around line 264), call `await checkLeftStatus()` before fetching messages.

**Step 4: Commit**

```bash
git add NaarsCars/Features/Messaging/ViewModels/ConversationDetailViewModel.swift
git commit -m "feat: add hasLeftConversation state to ConversationDetailViewModel"
```

---

### Task 4.2: Show frozen UI in `ConversationDetailView`

**Files:**
- Modify: `NaarsCars/Features/Messaging/Views/ConversationDetailView.swift:648-701`

**Step 1: Replace input container with frozen banner when left**

Wrap the `ConversationInputContainer` (lines 652-698) in a conditional:

```swift
if viewModel.hasLeftConversation {
    // Frozen state — user left this conversation
    VStack(spacing: 0) {
        Divider()
        HStack {
            Image(systemName: "rectangle.portrait.and.arrow.right")
                .foregroundColor(.secondary)
            Text("messaging_you_left_conversation".localized)
                .font(.naarsFootnote)
                .foregroundColor(.secondary)
        }
        .frame(maxWidth: .infinity)
        .padding(.vertical, 12)
        .background(Color(.systemGroupedBackground))
    }
} else {
    // existing ConversationInputContainer code unchanged
    ConversationInputContainer(...)
}
```

**Step 2: Disable interaction overlay actions for frozen state**

In the message interaction overlay setup, if `viewModel.hasLeftConversation`, hide Reply/React options. The message bubbles should still be visible and scrollable.

**Step 3: Add localization key**

Add `"messaging_you_left_conversation"` = `"You left this conversation"` to `Localizable.xcstrings`.

**Step 4: Build and verify**

**Step 5: Commit**

```bash
git add NaarsCars/Features/Messaging/Views/ConversationDetailView.swift NaarsCars/Resources/Localizable.xcstrings
git commit -m "feat: show frozen read-only state when user has left conversation"
```

---

### Task 4.3: Update leave button constraints in `MessageDetailsPopup`

**Files:**
- Modify: `NaarsCars/Features/Messaging/Views/MessageDetailsPopup.swift:174-185`

**Step 1: Add active member count state**

Add a `@State private var activeParticipantCount: Int = 0` property.

**Step 2: Fetch count on appear**

In the `.task` or `.onAppear` modifier, query:

```swift
let count = try? await SupabaseService.shared.client
    .from("conversation_participants")
    .select("id", head: true, count: .exact)
    .eq("conversation_id", value: conversationId.uuidString)
    .is("left_at", value: nil)
    .execute()
    .count
activeParticipantCount = count ?? 0
```

**Step 3: Conditionally disable leave button**

Replace the Leave Group Section (lines 175-185):

```swift
Section {
    if activeParticipantCount <= 3 {
        HStack {
            Image(systemName: "rectangle.portrait.and.arrow.right")
            Text("messaging_leave_conversation".localized)
        }
        .foregroundColor(.secondary)
        .help("messaging_leave_disabled_tooltip".localized)
    } else {
        Button(role: .destructive) {
            showLeaveConfirmation = true
        } label: {
            HStack {
                Image(systemName: "rectangle.portrait.and.arrow.right")
                Text("messaging_leave_conversation".localized)
            }
            .foregroundColor(.red)
        }
    }
}
```

**Step 4: Add localization key**

`"messaging_leave_disabled_tooltip"` = `"You cannot leave a group with fewer than 4 members."`

**Step 5: Remove UserDefaults hide-conversation on leave**

Currently in `ConversationParticipantService.leaveConversation` or the calling ViewModel, after leaving, the conversation is hidden via `ConversationService.shared.hideConversationForUser(...)`. Remove that call so the conversation stays visible in frozen state.

**Step 6: Commit**

```bash
git add NaarsCars/Features/Messaging/Views/MessageDetailsPopup.swift NaarsCars/Resources/Localizable.xcstrings
git commit -m "feat: disable leave button when group has 3 or fewer members, keep frozen conversation visible"
```

---

### Task 4.4: Stop hiding conversations on leave — update conversation list

**Files:**
- Modify: `NaarsCars/Features/Messaging/Views/ConversationsListView.swift`

**Step 1: Ensure left conversations still appear in the list**

Currently `fetchConversations` in `ConversationService` may filter out conversations where the user has left. Check the RPC `get_conversations_with_details` — if it filters `left_at IS NULL`, we need to relax that to include conversations where `left_at IS NOT NULL` (so they appear in frozen state).

The `fetchConversations` method and its RPC need to return conversations where the user is EITHER active OR has left (but not hidden). The hide/dismiss functionality stays as-is (UserDefaults-based) — users can dismiss frozen conversations the same way they dismiss any other.

**Step 2: Add visual indicator for left conversations in the row**

In `ConversationsListView.conversationRow` (around line 401), check if the current user has left and show a muted/grayed-out row:

```swift
// After building the ConversationRow, apply opacity if user has left
.opacity(conversationDetail.conversation.currentUserHasLeft ? 0.6 : 1.0)
```

This requires adding a `currentUserHasLeft` property to `ConversationWithDetails` or checking participant records.

**Step 3: Commit**

```bash
git add NaarsCars/Features/Messaging/Views/ConversationsListView.swift NaarsCars/Core/Services/ConversationService.swift
git commit -m "feat: show left conversations in list with frozen visual indicator"
```

---

## Phase 5: Muting Infrastructure (P0)

### Task 5.1: Create `ConversationMuteService`

**Files:**
- Create: `NaarsCars/Core/Services/ConversationMuteService.swift`

**Step 1: Write the service**

```swift
import Foundation
import Supabase

/// Manages per-conversation mute state in the database
final class ConversationMuteService {
    static let shared = ConversationMuteService()
    private let supabase = SupabaseService.shared.client
    private init() {}

    enum MuteDuration {
        case oneHour
        case eightHours
        case twentyFourHours
        case indefinitely

        var interval: TimeInterval? {
            switch self {
            case .oneHour: return 3600
            case .eightHours: return 28800
            case .twentyFourHours: return 86400
            case .indefinitely: return nil
            }
        }
    }

    /// Mute a conversation for the current user
    func muteConversation(conversationId: UUID, userId: UUID, duration: MuteDuration) async throws {
        var updates: [String: AnyEncodable] = [
            "notifications_muted": AnyEncodable(true)
        ]
        if let interval = duration.interval {
            let until = Date().addingTimeInterval(interval)
            let formatter = ISO8601DateFormatter()
            updates["muted_until"] = AnyEncodable(formatter.string(from: until))
        } else {
            updates["muted_until"] = AnyEncodable(Optional<String>.none)
        }

        try await supabase
            .from("conversation_participants")
            .update(updates)
            .eq("conversation_id", value: conversationId.uuidString)
            .eq("user_id", value: userId.uuidString)
            .execute()
    }

    /// Unmute a conversation
    func unmuteConversation(conversationId: UUID, userId: UUID) async throws {
        try await supabase
            .from("conversation_participants")
            .update([
                "notifications_muted": AnyEncodable(false),
                "muted_until": AnyEncodable(Optional<String>.none)
            ])
            .eq("conversation_id", value: conversationId.uuidString)
            .eq("user_id", value: userId.uuidString)
            .execute()
    }

    /// Check if conversation is muted for user
    func isMuted(conversationId: UUID, userId: UUID) async -> Bool {
        guard let resp = try? await supabase
            .from("conversation_participants")
            .select("notifications_muted, muted_until")
            .eq("conversation_id", value: conversationId.uuidString)
            .eq("user_id", value: userId.uuidString)
            .single()
            .execute() else { return false }

        struct MuteRow: Codable {
            let notificationsMuted: Bool
            let mutedUntil: Date?
            enum CodingKeys: String, CodingKey {
                case notificationsMuted = "notifications_muted"
                case mutedUntil = "muted_until"
            }
        }
        guard let row = try? DateDecoderFactory.makeMessagingDecoder().decode(MuteRow.self, from: resp.data) else {
            return false
        }
        if row.notificationsMuted { return true }
        if let until = row.mutedUntil, until > Date() { return true }
        return false
    }
}
```

**Step 2: Commit**

```bash
git add NaarsCars/Core/Services/ConversationMuteService.swift
git commit -m "feat: add ConversationMuteService for per-conversation mute with timed options"
```

---

### Task 5.2: Replace UserDefaults mute with DB-backed mute in `ConversationsListView`

**Files:**
- Modify: `NaarsCars/Features/Messaging/Views/ConversationsListView.swift:23,401-486`

**Step 1: Replace `mutedConversations` state**

Replace `@State private var mutedConversations: Set<UUID> = []` with a DB-backed approach. On load, fetch mute status for all conversations from the participant records. Cache locally for the session.

Change the mute swipe action (lines 445-462) to present a mute duration picker sheet instead of a simple toggle:

```swift
Button {
    if isMuted {
        // Unmute directly
        Task {
            try? await ConversationMuteService.shared.unmuteConversation(
                conversationId: conversationDetail.conversation.id,
                userId: currentUserId
            )
            mutedConversations.remove(conversationDetail.conversation.id)
        }
    } else {
        // Show mute duration picker
        conversationToMute = conversationDetail.conversation.id
        showMutePicker = true
    }
} label: {
    Label(isMuted ? "messaging_unmute".localized : "messaging_mute".localized,
          systemImage: isMuted ? "bell" : "bell.slash")
}
.tint(.gray)
```

**Step 2: Add mute duration picker sheet**

Add a `.sheet(isPresented: $showMutePicker)` with four options:
- For 1 hour
- For 8 hours
- For 24 hours
- Until I turn it back on

Each option calls `ConversationMuteService.shared.muteConversation(...)`.

**Step 3: Remove `saveMutedConversations` and `loadSavedPreferences` mute portion**

The mute data now lives in the database, not UserDefaults. Keep the pinned conversations in UserDefaults.

**Step 4: Commit**

```bash
git add NaarsCars/Features/Messaging/Views/ConversationsListView.swift
git commit -m "feat: replace UserDefaults mute with DB-backed per-conversation mute with duration picker"
```

---

### Task 5.3: Add mute check to edge function `send-message-push`

**Files:**
- Modify: `supabase/functions/send-message-push/index.ts` (around lines 179-203)

**Step 1: Expand participant query to include mute fields**

In the recipient eligibility query (around line 182), change the select to include mute fields:

```typescript
const { data: participants } = await supabase
  .from('conversation_participants')
  .select('user_id, last_seen, notifications_muted, muted_until')
  .eq('conversation_id', conversationId)
  .is('left_at', null)
  .neq('user_id', senderId);
```

**Step 2: Add mute filter**

After the active-viewing filter (around line 198), add:

```typescript
// Skip muted conversations
const now = new Date();
const nonMutedRecipients = activeRecipients.filter(p => {
  if (p.notifications_muted) return false;
  if (p.muted_until && new Date(p.muted_until) > now) return false;
  return true;
});
```

Use `nonMutedRecipients` for the push notification loop instead of `activeRecipients`.

**Step 3: Commit**

```bash
git add supabase/functions/send-message-push/index.ts
git commit -m "feat: suppress push notifications for muted conversations in edge function"
```

---

### Task 5.4: Suppress in-app notification banners for muted conversations

**Files:**
- Modify: `NaarsCars/Core/Services/PushNotificationService.swift:571-601`

**Step 1: Add mute check before showing local notification**

In `showLocalMessageNotification` (line 571), add a check at the top:

```swift
// Check if conversation is muted
let isMuted = await ConversationMuteService.shared.isMuted(
    conversationId: conversationId,
    userId: AuthService.shared.currentUserId ?? UUID()
)
if isMuted { return }
```

This prevents in-app banners/sounds for muted conversations. Badge count still increments because that's handled separately in `updateBadgeCount()`.

**Step 2: Commit**

```bash
git add NaarsCars/Core/Services/PushNotificationService.swift
git commit -m "feat: suppress in-app message banners for muted conversations"
```

---

### Task 5.5: Add mute controls to `MessageDetailsPopup`

**Files:**
- Modify: `NaarsCars/Features/Messaging/Views/MessageDetailsPopup.swift`

**Step 1: Add mute section**

Before the "Leave Group" section (line 174), add a Mute section:

```swift
Section("messaging_notifications_section".localized) {
    if isConversationMuted {
        Button {
            Task {
                try? await ConversationMuteService.shared.unmuteConversation(
                    conversationId: conversationId,
                    userId: AuthService.shared.currentUserId ?? UUID()
                )
                isConversationMuted = false
            }
        } label: {
            HStack {
                Image(systemName: "bell")
                Text("messaging_unmute_notifications".localized)
            }
        }
    } else {
        Menu {
            Button("messaging_mute_1_hour".localized) { muteFor(.oneHour) }
            Button("messaging_mute_8_hours".localized) { muteFor(.eightHours) }
            Button("messaging_mute_24_hours".localized) { muteFor(.twentyFourHours) }
            Button("messaging_mute_indefinitely".localized) { muteFor(.indefinitely) }
        } label: {
            HStack {
                Image(systemName: "bell.slash")
                Text("messaging_mute_notifications".localized)
            }
        }
    }
}
```

Add `@State private var isConversationMuted = false` and load it on appear.

**Step 2: Commit**

```bash
git add NaarsCars/Features/Messaging/Views/MessageDetailsPopup.swift NaarsCars/Resources/Localizable.xcstrings
git commit -m "feat: add mute/unmute controls with duration options to conversation details"
```

---

## Phase 6: Member Management Constraints

### Task 6.1: Enforce minimum 3 participants for group creation

**Files:**
- Modify: `NaarsCars/Core/Services/ConversationService.swift:427-498`

**Step 1: Add validation**

At the top of `createConversationWithUsers` (after line 430), add:

```swift
// Group conversations require at least 3 total participants (creator + 2 others)
// 1:1 DMs are handled by getOrCreateDirectConversation
if userIds.count < 2 {
    throw AppError.invalidInput("Group conversations require at least 3 participants")
}
```

Note: `userIds` should include the creator. If it doesn't, adjust the count check accordingly.

**Step 2: Commit**

```bash
git add NaarsCars/Core/Services/ConversationService.swift
git commit -m "feat: enforce minimum 3 participants for group conversation creation"
```

---

### Task 6.2: Enforce 50-member cap

**Files:**
- Modify: `NaarsCars/Core/Services/ConversationParticipantService.swift:44-161`
- Modify: `NaarsCars/Features/Messaging/Views/MessageDetailsPopup.swift`

**Step 1: Add cap check in `addParticipantsToConversation`**

Near the top of the method (after logging, before the actual insert), add:

```swift
// Check 50-member cap
let countResp = try? await supabase
    .from("conversation_participants")
    .select("id", head: true, count: .exact)
    .eq("conversation_id", value: conversationId.uuidString)
    .is("left_at", value: nil)
    .execute()
let currentCount = countResp?.count ?? 0

if currentCount + userIds.count > 50 {
    throw AppError.invalidInput("This group has reached the maximum of 50 participants.")
}
```

**Step 2: Disable "Add People" in MessageDetailsPopup when at 50**

Use the `activeParticipantCount` from Task 4.3. If >= 50, disable the Add Participants button:

```swift
Button {
    showAddParticipants = true
} label: {
    HStack {
        Image(systemName: "person.badge.plus")
        Text("messaging_add_participants".localized)
    }
}
.disabled(activeParticipantCount >= 50)
```

Show participant count in the section header: `"Participants (\(activeParticipantCount)/50)"`

**Step 3: Commit**

```bash
git add NaarsCars/Core/Services/ConversationParticipantService.swift NaarsCars/Features/Messaging/Views/MessageDetailsPopup.swift
git commit -m "feat: enforce 50-member group cap in service and UI"
```

---

### Task 6.3: Re-add member creates new participant record

**Files:**
- Modify: `NaarsCars/Core/Services/ConversationParticipantService.swift:44-161`

**Step 1: Update `addParticipantsToConversation` to handle re-adds**

Currently the method filters out existing participants. For re-adds (users who left), instead of skipping them, create a new participant record.

In the duplicate-filtering logic, separate users into three groups:
1. Already active — skip with "Already in group" (existing behavior)
2. Previously left — create new record with fresh `joined_at`, insert "added back" system event
3. Never been in conversation — normal add

```swift
// Fetch all participant records for these users (including left ones)
let existingResp = try await supabase
    .from("conversation_participants")
    .select("user_id, left_at")
    .eq("conversation_id", value: conversationId.uuidString)
    .in("user_id", values: userIds.map { $0.uuidString })
    .execute()

struct ExistingRow: Codable {
    let userId: UUID
    let leftAt: Date?
    enum CodingKeys: String, CodingKey {
        case userId = "user_id"
        case leftAt = "left_at"
    }
}
let existing = try DateDecoderFactory.makeMessagingDecoder()
    .decode([ExistingRow].self, from: existingResp.data)

let activeUserIds = Set(existing.filter { $0.leftAt == nil }.map { $0.userId })
let leftUserIds = Set(existing.filter { $0.leftAt != nil }.map { $0.userId })

let newUserIds = userIds.filter { !activeUserIds.contains($0) }
let readdUserIds = newUserIds.filter { leftUserIds.contains($0) }
let freshUserIds = newUserIds.filter { !leftUserIds.contains($0) }
```

Insert records for both `freshUserIds` and `readdUserIds` (new records with fresh `joined_at`). For re-adds, use a distinct system event: `"[Actor] added [Name] back to the conversation."`.

**Step 2: Commit**

```bash
git add NaarsCars/Core/Services/ConversationParticipantService.swift
git commit -m "feat: create new participant record on re-add with fresh joined_at and history boundary"
```

---

### Task 6.4: Pass `added_by` when adding participants

**Files:**
- Modify: `NaarsCars/Core/Services/ConversationParticipantService.swift`
- Modify: `NaarsCars/Core/Services/ConversationService.swift`

**Step 1: Include `added_by` in participant insert dictionaries**

In `addParticipantsToConversation`, when building participant insert rows, add:

```swift
"added_by": AnyCodable(addedBy.uuidString)
```

**Step 2: Include `added_by` in `createConversationWithUsers`**

In `ConversationService.createConversationWithUsers` (line 468), the participant inserts should include `added_by` as `null` for the creator (they added themselves) or the `createdBy` UUID for others. Since this is creation, all are initial members — set `added_by` to `nil`.

**Step 3: Commit**

```bash
git add NaarsCars/Core/Services/ConversationParticipantService.swift NaarsCars/Core/Services/ConversationService.swift
git commit -m "feat: track added_by on participant records"
```

---

## Phase 7: Read Receipts Enhancement

### Task 7.1: Group read receipt profile photo thumbnails in `MessageBubble`

**Files:**
- Modify: `NaarsCars/UI/Components/Messaging/MessageBubble.swift:152-191`

**Step 1: Add group context to MessageBubble**

The bubble needs to know if this is a group conversation and have access to participant profiles. Add properties if not already present:

```swift
let isGroupConversation: Bool
let participantProfiles: [Profile] // all active participants in the conversation
```

**Step 2: Replace checkmark-based read receipt for groups**

In the `readReceiptIndicator` computed property (line 153), add a branch for group conversations:

```swift
private var readReceiptIndicator: some View {
    Group {
        if isGroupConversation && readStatus == .read || readStatus == .delivered {
            // Group read receipts: show profile photo thumbnails
            groupReadReceiptView
        } else {
            // 1:1 DMs: keep existing checkmark style
            // ... existing switch statement ...
        }
    }
}

private var groupReadReceiptView: some View {
    let readers = message.readBy.filter { $0 != message.fromId }
    let readerProfiles = participantProfiles.filter { readers.contains($0.id) }

    return HStack(spacing: -4) {
        ForEach(readerProfiles.prefix(5)) { profile in
            AvatarView(
                imageUrl: profile.avatarUrl,
                name: profile.name,
                size: 14,
                userId: profile.id
            )
            .overlay(
                Circle()
                    .stroke(Color(.systemBackground), lineWidth: 1)
            )
        }
        if readerProfiles.count > 5 {
            Text("+\(readerProfiles.count - 5)")
                .font(.system(size: 9))
                .foregroundColor(.secondary)
        }
    }
}
```

**Step 3: Pass group context from parent views**

Update all call sites of `MessageBubble` to pass `isGroupConversation` and `participantProfiles`.

**Step 4: Commit**

```bash
git add NaarsCars/UI/Components/Messaging/MessageBubble.swift
git commit -m "feat: show profile photo thumbnails for group read receipts"
```

---

### Task 7.2: Per-conversation read receipt toggle

**Files:**
- Modify: `NaarsCars/Features/Messaging/Views/MessageDetailsPopup.swift`

**Step 1: Add read receipt toggle in conversation details**

In the notifications section added in Task 5.5, add:

```swift
Toggle(isOn: $showReadReceiptsForConversation) {
    HStack {
        Image(systemName: "checkmark.message")
        Text("messaging_show_read_receipts".localized)
    }
}
.onChange(of: showReadReceiptsForConversation) { _, newValue in
    Task {
        try? await SupabaseService.shared.client
            .from("conversation_participants")
            .update(["show_read_receipts": newValue])
            .eq("conversation_id", value: conversationId.uuidString)
            .eq("user_id", value: (AuthService.shared.currentUserId ?? UUID()).uuidString)
            .execute()
    }
}
```

**Step 2: Load initial value on appear**

Fetch `show_read_receipts` from the participant record. If `nil`, use the global profile setting.

**Step 3: Wire into read marking logic**

In `MessageService.markAsRead`, before appending to `read_by`, check if the user has read receipts disabled (either globally or for this conversation). If disabled, skip the `read_by` update.

**Step 4: Commit**

```bash
git add NaarsCars/Features/Messaging/Views/MessageDetailsPopup.swift NaarsCars/Core/Services/MessageService.swift
git commit -m "feat: add per-conversation read receipt toggle with global fallback"
```

---

## Phase 8: System Events Completeness

### Task 8.1: Add missing system event types

**Files:**
- Modify: `NaarsCars/Core/Services/ConversationService.swift`
- Modify: `NaarsCars/Core/Services/ConversationParticipantService.swift`
- Modify: `NaarsCars/UI/Components/Messaging/MessageBubble.swift` (system message rendering)

**Step 1: Add "Group Created" system event**

In `createConversationWithUsers` (ConversationService.swift, after line 492 — after participants are added), insert:

```swift
_ = try? await sendSystemMessage(
    conversationId: conversation.id,
    text: "Group conversation created by \(creatorProfile.name)",
    fromId: createdBy
)
```

This requires fetching the creator's profile name. Add a profile fetch or pass the name in.

**Step 2: Add "Name Removed" system event**

In `updateConversationTitle` (ConversationService.swift), when the new title is nil/empty:

```swift
if let title = title, !title.isEmpty {
    // existing: "[Name] changed the group name to [title]"
} else {
    _ = try await sendSystemMessage(
        conversationId: conversationId,
        text: "\(profile.name) removed the group name",
        fromId: userId
    )
}
```

**Step 3: Add "Member Re-Added" system event**

Already handled in Task 6.3 — the re-add path inserts `"[Actor] added [Name] back to the conversation."`.

**Step 4: Update system message icon rendering**

In `MessageBubble.swift` (around line 274, `systemMessageIcon`), add pattern matching for the new event text patterns:

```swift
if message.text.contains("created by") {
    return "sparkles"
} else if message.text.contains("removed the group name") {
    return "pencil.slash"
} else if message.text.contains("back to the conversation") {
    return "person.badge.plus"
}
```

**Step 5: Commit**

```bash
git add NaarsCars/Core/Services/ConversationService.swift NaarsCars/Core/Services/ConversationParticipantService.swift NaarsCars/UI/Components/Messaging/MessageBubble.swift
git commit -m "feat: add missing system events — group created, name removed, member re-added"
```

---

## Phase 9: Delete for Me

### Task 9.1: Add "Delete for Me" to message context menu

**Files:**
- Modify: `NaarsCars/Features/Messaging/Views/ConversationDetailView.swift` (interaction overlay actions)
- Modify: `NaarsCars/UI/Components/Messaging/MessageBubble.swift` (filter hidden messages)

**Step 1: Add "Delete for Me" action to context menu**

In the `MessageInteractionOverlay` action list, after "Undo Send" (which is only shown within 15 min for own messages), add a "Delete for Me" option that is always available:

```swift
// Delete for Me — always available for all messages
Button(role: .destructive) {
    Task {
        await deleteMessageForMe(message)
    }
    dismissOverlay()
} label: {
    Label("messaging_delete_for_me".localized, systemImage: "eye.slash")
}
```

**Step 2: Implement `deleteMessageForMe`**

In `ConversationDetailViewModel`, add:

```swift
func deleteMessageForMe(_ message: Message) async {
    let context = ModelContext(repository.modelContainer)
    let deletedMsg = SDDeletedMessage(
        messageId: message.id,
        conversationId: conversationId
    )
    context.insert(deletedMsg)
    try? context.save()

    // Remove from local messages array
    messages.removeAll { $0.id == message.id }
}
```

**Step 3: Filter deleted messages on load**

In `loadMessages()`, after fetching from network, filter out locally deleted messages:

```swift
let deletedIds = fetchLocallyDeletedMessageIds(for: conversationId)
messages = messages.filter { !deletedIds.contains($0.id) }
```

Implement `fetchLocallyDeletedMessageIds`:

```swift
private func fetchLocallyDeletedMessageIds(for conversationId: UUID) -> Set<UUID> {
    let context = ModelContext(repository.modelContainer)
    let descriptor = FetchDescriptor<SDDeletedMessage>(
        predicate: #Predicate { $0.conversationId == conversationId }
    )
    let deleted = (try? context.fetch(descriptor)) ?? []
    return Set(deleted.map { $0.messageId })
}
```

**Step 4: Commit**

```bash
git add NaarsCars/Features/Messaging/Views/ConversationDetailView.swift NaarsCars/Features/Messaging/ViewModels/ConversationDetailViewModel.swift NaarsCars/Resources/Localizable.xcstrings
git commit -m "feat: add Delete for Me — local-only message hiding via SwiftData"
```

---

## Phase 10: Polish

### Task 10.1: Enforce 50-character group name limit

**Files:**
- Modify: `NaarsCars/Features/Messaging/Views/MessageDetailsPopup.swift:106-109`
- Modify: `NaarsCars/Core/Services/ConversationService.swift` (`updateConversationTitle`)

**Step 1: Add character limit to TextField**

On the group name TextField (line 107), add:

```swift
TextField("messaging_group_name_placeholder".localized, text: $editedTitle)
    .textInputAutocapitalization(.words)
    .onChange(of: editedTitle) { _, newValue in
        if newValue.count > 50 {
            editedTitle = String(newValue.prefix(50))
        }
    }
```

Add a character counter below the field:

```swift
Text("\(editedTitle.count)/50")
    .font(.naarsCaption)
    .foregroundColor(editedTitle.count >= 50 ? .red : .secondary)
```

**Step 2: Add server-side validation**

In `updateConversationTitle`, add:

```swift
if let title = title, title.count > 50 {
    throw AppError.invalidInput("Group name cannot exceed 50 characters")
}
```

**Step 3: Commit**

```bash
git add NaarsCars/Features/Messaging/Views/MessageDetailsPopup.swift NaarsCars/Core/Services/ConversationService.swift
git commit -m "feat: enforce 50-character limit on group conversation names"
```

---

### Task 10.2: Handle deleted reply-to message fallback

**Files:**
- Modify: `NaarsCars/UI/Components/Messaging/MessageBubble.swift` (reply preview rendering)

**Step 1: Check if replied-to message is deleted**

In the reply preview rendering area, when `replyToMessage` is present, check if the original was unsent:

```swift
if let replyContext = message.replyToMessage {
    // Check if original message was unsent/deleted
    if replyContext.text.isEmpty || replyContext.text == "[Message from deleted user]" {
        // Fallback rendering
        HStack(spacing: 4) {
            Rectangle()
                .fill(Color.secondary.opacity(0.3))
                .frame(width: 3)
            Text("messaging_original_message_deleted".localized)
                .font(.naarsCaption)
                .foregroundColor(.secondary)
                .italic()
        }
    } else {
        // Normal reply preview rendering (existing code)
    }
}
```

**Step 2: Add localization key**

`"messaging_original_message_deleted"` = `"Original message deleted"`

**Step 3: Commit**

```bash
git add NaarsCars/UI/Components/Messaging/MessageBubble.swift NaarsCars/Resources/Localizable.xcstrings
git commit -m "feat: show 'Original message deleted' fallback for reply-to unsent messages"
```

---

### Task 10.3: Deleted user display throughout the app

**Files:**
- Modify: `NaarsCars/UI/Components/Messaging/MessageBubble.swift`
- Modify: `NaarsCars/Features/Messaging/Views/MessageDetailsPopup.swift`
- Modify: `NaarsCars/UI/Components/Shared/AvatarView.swift` (if it exists)

**Step 1: Handle null/missing sender profiles**

When `message.sender` is nil (because the profile was deleted), display:

```swift
let senderName = message.sender?.name ?? "Deleted User"
let senderAvatar = message.sender?.avatarUrl // will be nil, showing default avatar
```

**Step 2: Handle deleted participants in conversation details**

In `MessageDetailsPopup`, when fetching participant profiles, if a profile query returns no result for a `user_id`, show a "Deleted User" placeholder row with a generic avatar.

**Step 3: Update `delete_user_account` to call soft-delete helper**

In the `delete_user_account` RPC (or the iOS code that calls it), ensure `soft_delete_user_messaging` is called before the cascade. This was set up in Task 1.7 — verify the integration.

**Step 4: Commit**

```bash
git add NaarsCars/UI/Components/Messaging/MessageBubble.swift NaarsCars/Features/Messaging/Views/MessageDetailsPopup.swift
git commit -m "feat: show 'Deleted User' for messages and participants from deleted accounts"
```

---

### Task 10.4: Update `remove_conversation_participant` RPC for flat permissions

**Files:**
- Modify: `supabase/migrations/` (new migration)
- Modify: `NaarsCars/Core/Services/ConversationParticipantService.swift:252-361`

**Step 1: The existing RPC already checks active participant status**

The `remove_conversation_participant` RPC in `database/083_enhance_group_conversations.sql:195-254` checks if the remover is an active participant OR the conversation creator. Since we're removing admin roles, any active participant can remove anyone — this is already how the RPC works. No RPC changes needed.

**Step 2: Remove admin check from Swift service**

In `ConversationParticipantService.removeParticipantFromConversation` (around line 252), if there's any `isAdmin` check or `canModifyParticipants` check that references admin status, remove it. The only requirement should be: the caller is an active participant.

**Step 3: Update system event text**

Change the removal system message from admin-focused language to neutral: `"[Actor] removed [Name] from the group."` (already matches this pattern).

**Step 4: Commit**

```bash
git add NaarsCars/Core/Services/ConversationParticipantService.swift
git commit -m "feat: flat permissions — any active participant can remove any other participant"
```

---

## Phase 11: Auto-Generated Group Avatar (Subagent)

This phase is fully self-contained and should be dispatched as a standalone subagent task.

### Task 11.1: Implement 2x2 composite group avatar

**Subagent instructions:**

Create a utility that generates a composite group avatar image by arranging up to 4 participant profile photos in a 2x2 grid layout. This is used when a group conversation has no custom `group_image_url`.

**Files to create/modify:**
- Create: `NaarsCars/UI/Components/Shared/GroupAvatarComposite.swift`
- Modify: `NaarsCars/UI/Components/Messaging/ConversationAvatar.swift` (use composite instead of stacked avatars)

**Requirements:**
1. Accept an array of `Profile` objects (the first 4 participants)
2. Download/cache each profile photo using the app's existing `CachedAsyncImage` or `AvatarView` pattern
3. Compose them into a 2x2 grid:
   - 1 participant: single photo fills the circle
   - 2 participants: two photos side-by-side, each taking half
   - 3 participants: top-left, top-right, bottom-center arrangement
   - 4 participants: standard 2x2 grid
4. Clip to a circle
5. Size should match the existing `ConversationAvatar` sizing
6. Fall back to `person.2.fill` system image if no participant photos available

**Integration:**
In `ConversationAvatar.swift`, when the conversation has no `groupImageUrl` and is a group, use `GroupAvatarComposite` instead of the current stacked-overlay approach.

---

## Localization Keys Summary

All new localization keys needed (add to `Localizable.xcstrings`):

| Key | English Value |
|-----|---------------|
| `messaging_you_left_conversation` | You left this conversation |
| `messaging_leave_disabled_tooltip` | You cannot leave a group with fewer than 4 members. |
| `messaging_notifications_section` | Notifications |
| `messaging_mute_notifications` | Mute Notifications |
| `messaging_unmute_notifications` | Unmute Notifications |
| `messaging_mute_1_hour` | For 1 Hour |
| `messaging_mute_8_hours` | For 8 Hours |
| `messaging_mute_24_hours` | For 24 Hours |
| `messaging_mute_indefinitely` | Until I Turn It Back On |
| `messaging_show_read_receipts` | Send Read Receipts |
| `messaging_delete_for_me` | Delete for Me |
| `messaging_original_message_deleted` | Original message deleted |
| `messaging_group_full` | This group has reached the maximum of 50 participants. |

---

## Execution Order (Critical Path)

1. **Phase 1** (Tasks 1.1-1.7) — All DB migrations. Deploy together. ~30 min.
2. **Phase 2** (Tasks 2.1-2.3) — iOS model updates. Must compile clean. ~20 min.
3. **Phase 3** (Task 3.1) — History visibility client fix. P0 privacy. ~15 min.
4. **Phase 4** (Tasks 4.1-4.4) — Leave/frozen state. P0 UX. ~30 min.
5. **Phase 5** (Tasks 5.1-5.5) — Muting infrastructure. P0. ~45 min.
6. **Phases 6-10** — Remaining workstreams. Can be parallelized across subagents. ~60 min total.
7. **Phase 11** — Subagent for group avatar composite. Independent. ~20 min.

---

## Verification Checklist

Before marking complete, verify:

- [ ] New member added to existing group cannot see prior messages
- [ ] Re-added member sees only messages from their new join date forward
- [ ] User cannot leave group with 3 members (button disabled)
- [ ] Left conversation shows frozen read-only state with banner
- [ ] Left conversation stays in list, can be dismissed
- [ ] Muting a conversation with "1 hour" suppresses notifications for 1 hour
- [ ] Muted conversation still shows unread badge
- [ ] Group read receipts show profile photos, DMs show checkmarks
- [ ] "Delete for Me" hides message locally, others still see it
- [ ] 50-member cap prevents adding more participants
- [ ] 50-character group name limit enforced
- [ ] "Group conversation created by [Name]" system event on new groups
- [ ] "[Name] removed the group name" system event when clearing title
- [ ] "[Actor] added [Name] back to the conversation" on re-add
- [ ] Deleted user shows "Deleted User" in messages and participant lists
- [ ] Any active participant can remove any other participant
- [ ] `is_admin` column removed from conversation_participants
- [ ] Per-conversation read receipt toggle works, overrides global setting
- [ ] Reply to unsent message shows "Original message deleted"
- [ ] Auto-generated 2x2 group avatar displays correctly
