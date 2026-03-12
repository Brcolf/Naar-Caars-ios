# App Store Submission Fix Plan

**Date:** 2026-03-12 (updated after pre-merge)
**Branch:** `main` (UIKit refactor merged, thread view wired in)
**Audit Score:** 79/100 → Target: 95+/100

This plan addresses every issue found in the combined Claude Opus + Codex audit. Fixes are grouped into phases with strict ordering. Each step includes exact file paths, before/after code, and verification commands.

**Pre-merge completed:** The `feat/uikit-message-cells` branch was merged to `main` with `MessageThreadRepresentable` wired in, dead SwiftUI `MessageThreadView` deleted, and `MessageThreadViewModel.swift` added to the Xcode project. Build verified passing on `main`.

---

## How to Use This Plan

**LLM Assignments:**
- **Opus** — Complex architectural work: database migrations, blocked-user filtering
- **Sonnet** — Straightforward code changes: 1-line fixes, string replacements, accessibility labels, localization

**Execution Rules:**
1. Complete all steps in a phase before moving to the next phase
2. Within a phase, steps marked `[parallel]` can be done simultaneously
3. After each phase, run the verification command at the end of the phase
4. Do NOT skip steps. Do NOT refactor beyond what is specified
5. Commit after each phase completes successfully

**Testing:** After all phases, run a clean build:
```bash
xcrun simctl shutdown all && killall -9 Simulator 2>/dev/null; sleep 2
xcodebuild -project NaarsCars/NaarsCars.xcodeproj -scheme NaarsCars -destination 'platform=iOS Simulator,name=iPhone 17 Pro' build 2>&1 | tail -20
```

---

## Phase 0: Database Migration Drift (5 migration files)

**LLM: Opus**
**Risk: HIGH — Source/live divergence means any DB rebuild loses security fixes**
**Context:** The live Supabase database has fixes applied manually that were never captured in migration files. Write new migration files to capture them. The next available migration number is `128`.

### Step 0.1: Auth guard on delete_user_account

**File to create:** `database/128_fix_delete_user_account_auth_guard.sql`

**What to write:**
```sql
-- Fix: Add auth.uid() verification to delete_user_account
-- The live DB already has this guard, but it was never captured in a migration.
-- Without this, any authenticated user could delete another user's account.

CREATE OR REPLACE FUNCTION public.delete_user_account(p_user_id UUID)
RETURNS void
LANGUAGE plpgsql
SECURITY DEFINER
SET search_path = public
AS $$
BEGIN
    -- CRITICAL: Verify the caller is deleting their own account
    IF auth.uid() IS NULL OR auth.uid() != p_user_id THEN
        RAISE EXCEPTION 'Not authorized to delete this account';
    END IF;

    -- (Rest of the function body is unchanged from migration 125)
    -- Re-open any active requests the user has claimed
    UPDATE requests
    SET status = 'open', claimed_by = NULL, claimed_at = NULL
    WHERE claimed_by = p_user_id AND status IN ('claimed', 'confirmed');

    -- Notify requesters that their claimed requests are re-opened
    INSERT INTO notifications (user_id, type, title, body, data)
    SELECT r.user_id, 'request_update',
           'Request Re-opened',
           'A Carbardian who claimed your request has left. It''s now open for others.',
           jsonb_build_object('request_id', r.id)
    FROM requests r
    WHERE r.claimed_by IS NULL
      AND r.status = 'open'
      AND r.user_id != p_user_id;

    -- Clean up review-related notifications
    DELETE FROM notifications
    WHERE user_id = p_user_id
      AND type IN ('review_received', 'review_reminder');

    -- Clean up completion reminders
    DELETE FROM notifications
    WHERE user_id = p_user_id
      AND type = 'completion_reminder';

    -- Delete from all user-related tables
    DELETE FROM messages WHERE from_id = p_user_id;
    DELETE FROM conversation_participants WHERE user_id = p_user_id;
    DELETE FROM notifications WHERE user_id = p_user_id;
    DELETE FROM reviews WHERE reviewer_id = p_user_id;
    DELETE FROM reviews WHERE reviewee_id = p_user_id;
    DELETE FROM requests WHERE user_id = p_user_id;
    DELETE FROM town_hall_comments WHERE author_id = p_user_id;
    DELETE FROM town_hall_posts WHERE author_id = p_user_id;
    DELETE FROM profiles WHERE id = p_user_id;
    DELETE FROM auth.users WHERE id = p_user_id;
END;
$$;
```

**IMPORTANT:** Before writing this migration, read the FULL current function body from `database/125_graceful_user_departure_request_handling.sql` and preserve every statement exactly. The code above is an approximation — the real function may have additional statements. The ONLY change is adding the `IF auth.uid()` guard at the top and the `SET search_path = public`.

**Verification:** After applying, run against Supabase:
```sql
SELECT prosrc FROM pg_proc WHERE proname = 'delete_user_account';
-- Confirm the first executable line is the auth.uid() check
```

### Step 0.2: Reports table post/comment columns

**File to create:** `database/128_fix_reports_add_post_comment_columns.sql`

**What to write:**
```sql
-- Fix: Add reported_post_id and reported_comment_id to reports table
-- The live DB already has these columns, but they were never captured in a migration.

-- Add columns (IF NOT EXISTS prevents errors if already applied)
ALTER TABLE reports ADD COLUMN IF NOT EXISTS reported_post_id UUID REFERENCES town_hall_posts(id);
ALTER TABLE reports ADD COLUMN IF NOT EXISTS reported_comment_id UUID REFERENCES town_hall_comments(id);

-- Update the check constraint to include new columns
ALTER TABLE reports DROP CONSTRAINT IF EXISTS reports_target_check;
ALTER TABLE reports ADD CONSTRAINT reports_target_check CHECK (
    reported_user_id IS NOT NULL OR
    reported_message_id IS NOT NULL OR
    reported_post_id IS NOT NULL OR
    reported_comment_id IS NOT NULL
);
```

### Step 0.3: Update submit_report RPC to accept post/comment IDs

**File to create:** `database/128_fix_submit_report_post_comment.sql`

**What to write:** Read the live `submit_report` function via Supabase MCP (`SELECT prosrc FROM pg_proc WHERE proname = 'submit_report';`) and write a `CREATE OR REPLACE` migration that matches. The function must:
- Accept `p_reported_post_id UUID DEFAULT NULL` and `p_reported_comment_id UUID DEFAULT NULL` parameters
- Include them in the INSERT statement
- Add duplicate-prevention for posts and comments (same pattern as existing user/message dedup)
- Use `auth.uid()` instead of trusting `p_reporter_id` for the authorization check
- Include `SET search_path = public`

### Step 0.4: Tighten notifications INSERT policy

**File to create:** `database/128_fix_notifications_insert_policy.sql`

**What to write:**
```sql
-- Fix: Tighten notifications INSERT policy from WITH CHECK (true) to auth.uid() scoped
-- The live DB has this fix, but source SQL in 081 still has WITH CHECK (true).

DROP POLICY IF EXISTS notifications_insert_authenticated ON notifications;
DROP POLICY IF EXISTS notifications_insert_service_only ON notifications;

CREATE POLICY notifications_insert_service_only ON notifications
    FOR INSERT TO authenticated
    WITH CHECK (auth.uid() = user_id);
```

### Step 0.5: Restrict notification_queue to service_role

**File to create:** `database/128_fix_notification_queue_service_role.sql`

**What to write:**
```sql
-- Fix: Restrict notification_queue access to service_role only
-- The live DB has proper restrictions, but source SQL in 082 has permissive policies.

DROP POLICY IF EXISTS notification_queue_insert_authenticated ON notification_queue;
DROP POLICY IF EXISTS notification_queue_select_service ON notification_queue;
DROP POLICY IF EXISTS notification_queue_update_service ON notification_queue;

-- Only service_role (via SECURITY DEFINER functions) should access this table
CREATE POLICY notification_queue_insert_service_role ON notification_queue
    FOR INSERT TO service_role
    WITH CHECK (true);

CREATE POLICY notification_queue_select_service_role ON notification_queue
    FOR SELECT TO service_role
    USING (true);

CREATE POLICY notification_queue_update_service_role ON notification_queue
    FOR UPDATE TO service_role
    USING (true)
    WITH CHECK (true);
```

**Phase 0 Verification:**
```bash
# Confirm all 5 migration files exist
ls -la database/128_fix_*.sql
# Each file should parse cleanly (no syntax errors visible on read)
```

---

## Phase 1: Critical App Fixes

### Step 1.1: Fix reactions subscription leak [Sonnet]

**Issue:** `ConversationDetailView.onDisappear` never calls `viewModel.stop()`, leaking a Supabase Realtime channel on every conversation visit.

**File:** `NaarsCars/Features/Messaging/Views/ConversationDetailView.swift`

**Find this code (around line 209):**
```swift
        .onDisappear {
            NotificationCenter.default.post(
                name: .messageThreadDidDisappear,
                object: nil,
                userInfo: ["conversationId": conversationId]
            )
            // Stop observing typing indicators
            viewModel.stopTypingObservation()
#if DEBUG
            debugFrameDropMonitor.stop()
#endif
        }
```

**Replace with:**
```swift
        .onDisappear {
            NotificationCenter.default.post(
                name: .messageThreadDidDisappear,
                object: nil,
                userInfo: ["conversationId": conversationId]
            )
            // Tear down all subscriptions: typing, search, reactions, observers
            viewModel.stop()
#if DEBUG
            debugFrameDropMonitor.stop()
#endif
        }
```

**What changed:** Replaced `viewModel.stopTypingObservation()` with `viewModel.stop()`. The `stop()` method (defined at `ConversationDetailViewModel.swift:198`) already calls `stopTypingObservation()` plus also tears down the reactions subscription and search manager. This is strictly a superset.

**Verification:** Search for `stopTypingObservation` — it should only appear in `ConversationDetailViewModel.swift` (inside `stop()`), NOT in `ConversationDetailView.swift`.

### Step 1.2: Fix privacy manifest — add precise location [Sonnet]

**Issue:** The app sends exact lat/lng coordinates but the privacy manifest only declares coarse location.

**File:** `NaarsCars/PrivacyInfo.xcprivacy`

**Find this block (around line 59-70):**
```xml
		<dict>
			<key>NSPrivacyCollectedDataType</key>
			<string>NSPrivacyCollectedDataTypeCoarseLocation</string>
			<key>NSPrivacyCollectedDataTypeLinked</key>
			<true/>
			<key>NSPrivacyCollectedDataTypeTracking</key>
			<false/>
			<key>NSPrivacyCollectedDataTypePurposes</key>
			<array>
				<string>NSPrivacyCollectedDataTypePurposeAppFunctionality</string>
			</array>
		</dict>
```

**Replace with:**
```xml
		<dict>
			<key>NSPrivacyCollectedDataType</key>
			<string>NSPrivacyCollectedDataTypeCoarseLocation</string>
			<key>NSPrivacyCollectedDataTypeLinked</key>
			<true/>
			<key>NSPrivacyCollectedDataTypeTracking</key>
			<false/>
			<key>NSPrivacyCollectedDataTypePurposes</key>
			<array>
				<string>NSPrivacyCollectedDataTypePurposeAppFunctionality</string>
			</array>
		</dict>
		<dict>
			<key>NSPrivacyCollectedDataType</key>
			<string>NSPrivacyCollectedDataTypePreciseLocation</string>
			<key>NSPrivacyCollectedDataTypeLinked</key>
			<true/>
			<key>NSPrivacyCollectedDataTypeTracking</key>
			<false/>
			<key>NSPrivacyCollectedDataTypePurposes</key>
			<array>
				<string>NSPrivacyCollectedDataTypePurposeAppFunctionality</string>
			</array>
		</dict>
```

**What changed:** Added a second location entry for `PreciseLocation` alongside the existing `CoarseLocation`. Both are used — coarse for the map view, precise for location sharing in messages.

**Also:** Update the App Store Connect privacy answers to include precise location when submitting.

### Step 1.3: Add blocked-user content filtering [Opus]

**Issue:** The block infrastructure (DB functions, service methods, UI for managing blocks) exists but NO code filters blocked users' content from display. The database even has a `messages_filtered` view (created in migration 087) that is never used.

**This is the most complex fix. Three services need filtering added.**

#### Step 1.3a: Add a cached blocked-user-IDs set to MessageService

**File:** `NaarsCars/Core/Services/MessageService.swift`

Find the class declaration and add a cached property. Look for existing properties near the top of the class and add:

```swift
    /// Cached set of blocked user IDs, refreshed on fetch
    private var cachedBlockedUserIds: Set<UUID> = []

    /// Refresh the blocked user IDs cache
    func refreshBlockedUsers() async {
        guard let userId = AuthService.shared.currentUserId else { return }
        do {
            let blocked = try await getBlockedUsers(userId: userId)
            cachedBlockedUserIds = Set(blocked.map { $0.blockedId })
        } catch {
            AppLogger.error("messaging", "Failed to refresh blocked users: \(error)")
        }
    }

    /// Check if a user ID is in the blocked set
    func isBlocked(_ userId: UUID) -> Bool {
        cachedBlockedUserIds.contains(userId)
    }
```

#### Step 1.3b: Filter messages after fetch

**File:** `NaarsCars/Core/Services/MessageService.swift`

In the `fetchMessages` method (around line 135-189), find the return statement at the end:

```swift
        AppLogger.network.info("Fetched \(messages.count) messages from network.")
        return messages
```

Replace with:
```swift
        // Filter out messages from blocked users
        if !cachedBlockedUserIds.isEmpty {
            messages = messages.filter { !cachedBlockedUserIds.contains($0.fromId) }
        }

        AppLogger.network.info("Fetched \(messages.count) messages from network.")
        return messages
```

#### Step 1.3c: Filter Town Hall posts after fetch

**File:** `NaarsCars/Core/Services/TownHallService.swift`

In the `fetchPosts` method (around line 36-61), find the return at the end:

```swift
        AppLogger.info("townhall", "Fetched \(posts.count) posts from network")
        return posts
```

Replace with:
```swift
        // Filter out posts from blocked users
        let blockedIds = MessageService.shared.cachedBlockedUserIds
        if !blockedIds.isEmpty {
            posts = posts.filter { !blockedIds.contains($0.authorId) }
        }

        AppLogger.info("townhall", "Fetched \(posts.count) posts from network")
        return posts
```

**Note:** This requires making `cachedBlockedUserIds` internal (not private). Change the declaration in MessageService from `private var cachedBlockedUserIds` to `private(set) var cachedBlockedUserIds`.

#### Step 1.3d: Filter Town Hall comments after fetch

**File:** `NaarsCars/Core/Services/TownHallCommentService.swift`

In the `fetchComments` method (around line 34-63), find the line before building nested structure:

```swift
        // Build nested structure
        let nestedComments = buildNestedStructure(allComments)
```

Add filtering before it:
```swift
        // Filter out comments from blocked users
        let blockedIds = MessageService.shared.cachedBlockedUserIds
        if !blockedIds.isEmpty {
            allComments = allComments.filter { !blockedIds.contains($0.authorId) }
        }

        // Build nested structure
        let nestedComments = buildNestedStructure(allComments)
```

#### Step 1.3e: Refresh blocked users on app launch and after block/unblock

**File:** `NaarsCars/Core/Services/MessageService.swift`

In the `blockUser` method (around line 813), add a cache refresh after the RPC call succeeds:
```swift
        // After the existing RPC call succeeds, refresh cache
        await refreshBlockedUsers()
```

Do the same in `unblockUser` (around line 827).

**File:** `NaarsCars/App/AppDelegate.swift` (or wherever the app initializes after login)

Find the post-login initialization path and add:
```swift
        await MessageService.shared.refreshBlockedUsers()
```

**Verification:**
```bash
# Confirm filtering code exists in all three services
grep -n "cachedBlockedUserIds\|blockedIds" NaarsCars/Core/Services/MessageService.swift NaarsCars/Core/Services/TownHallService.swift NaarsCars/Core/Services/TownHallCommentService.swift
```

### Step 1.4: Fix main-thread image load in thread view [Sonnet]

**Issue:** `Data(contentsOf: url)` runs on main thread, blocking UI for large images.

**File:** `NaarsCars/Features/Messaging/Views/MessageThreadViewController.swift`

**Find this code (around line 549-553):**
```swift
        Task {
            if let data = try? Data(contentsOf: url), let img = UIImage(data: data) {
                iv.image = img
            }
        }
```

**Replace with:**
```swift
        Task.detached(priority: .userInitiated) {
            guard let data = try? Data(contentsOf: url), let img = UIImage(data: data) else { return }
            await MainActor.run {
                iv.image = img
            }
        }
```

**What changed:** `Task { }` inherits main actor context. `Task.detached` runs on a background thread, then dispatches the UI update back to main via `MainActor.run`. This matches the pattern already used in `ImageBubbleView.configure(localPath:)`.

### Step 1.5: Fix NSCameraUsageDescription text [Sonnet]

**Issue:** Description says "messages, reviews, and posts" but camera is not available in messaging.

**File:** `NaarsCars/Info.plist`

**Find (line 58-59):**
```xml
	<key>NSCameraUsageDescription</key>
	<string>Naar's Cars uses your camera to take photos for messages, reviews, and posts.</string>
```

**Replace with:**
```xml
	<key>NSCameraUsageDescription</key>
	<string>Naar's Cars uses your camera to take photos for reviews and posts.</string>
```

**Phase 1 Verification:**
```bash
# 1.1: stop() called in onDisappear
grep -n "viewModel.stop()" NaarsCars/Features/Messaging/Views/ConversationDetailView.swift
# 1.2: PreciseLocation in privacy manifest
grep -c "PreciseLocation" NaarsCars/PrivacyInfo.xcprivacy
# 1.3: blocked filtering in services
grep -n "cachedBlockedUserIds\|blockedIds" NaarsCars/Core/Services/MessageService.swift NaarsCars/Core/Services/TownHallService.swift NaarsCars/Core/Services/TownHallCommentService.swift
# 1.4: Task.detached in thread VC
grep -n "Task.detached" NaarsCars/Features/Messaging/Views/MessageThreadViewController.swift
# 1.5: camera description updated
grep "NSCameraUsageDescription" -A1 NaarsCars/Info.plist
```

---

## Phase 2: Medium-Priority Fixes

### Step 2.1: Fix ImageBubbleView remote retry [Sonnet]

**Issue:** `configure(remoteUrl:)` never sets `lastRemoteUrl`, so the retry button does nothing for failed remote images.

**File:** `NaarsCars/UI/Components/Messaging/Cells/ImageBubbleView.swift`

**Find this code (around line 69-71):**
```swift
    func configure(remoteUrl: String, onTap: ((URL) -> Void)? = nil) {
        self.onTap = onTap
        self.imageURL = URL(string: remoteUrl)
```

**Replace with:**
```swift
    func configure(remoteUrl: String, onTap: ((URL) -> Void)? = nil) {
        self.onTap = onTap
        self.imageURL = URL(string: remoteUrl)
        self.lastRemoteUrl = remoteUrl
        self.lastLocalPath = nil
```

**What changed:** Added `self.lastRemoteUrl = remoteUrl` and `self.lastLocalPath = nil` to mirror the pattern in `configure(localPath:)` (which sets `self.lastLocalPath = localPath` and `self.lastRemoteUrl = nil` at lines 94-95).

### Step 2.2: Fix Dark Mode Color.white on MessageInputBar [Sonnet]

**Issue:** Hardcoded `Color.white` background on image-preview dismiss button appears as a white dot in Dark Mode.

**File:** `NaarsCars/UI/Components/Messaging/MessageInputBar.swift`

**Find (around line 88):**
```swift
                            .background(Color.white.clipShape(Circle()))
```

**Replace with:**
```swift
                            .background(Color(.systemBackground).clipShape(Circle()))
```

**What changed:** `Color(.systemBackground)` is white in Light Mode and dark in Dark Mode, matching the system appearance.

### Step 2.3: Add deinit to MessageThreadViewController [Sonnet]

**Issue:** `mergeRepliesTask` is never cancelled when the view controller is dismissed.

**File:** `NaarsCars/Features/Messaging/Views/MessageThreadViewController.swift`

**Find the `// MARK: - State` section (around line 148-153):**
```swift
    // MARK: - State

    private var cancellables = Set<AnyCancellable>()
    private var mergeRepliesTask: Task<Void, Never>?
    private var messageText = ""
    private var imageToSend: UIImage?
```

**Add immediately after `imageToSend` (before the next `// MARK:`):**
```swift

    deinit {
        mergeRepliesTask?.cancel()
    }
```

### Step 2.4: Add explanatory text to disabled notification toggles [Sonnet]

**Issue:** "Announcements" and "New Requests" toggles are disabled but no text explains why.

**File:** `NaarsCars/Features/Profile/Views/NotificationSettingsSection.swift`

Find each disabled toggle (around lines 74-80). Below each `Toggle(...)` that has `.disabled(true)`, add a caption. The exact approach depends on the current layout — look for the toggle, then add a `.safeAreaInset` or a `VStack` wrapping. The simplest approach: wrap each disabled toggle label in a `VStack(alignment: .leading)` and add caption text:

For the "Announcements" toggle, change:
```swift
Toggle("settings_announcements".localized, isOn: .constant(true))
    .disabled(true)
```
to:
```swift
Toggle(isOn: .constant(true)) {
    VStack(alignment: .leading, spacing: 2) {
        Text("settings_announcements".localized)
        Text("settings_always_enabled".localized)
            .font(.caption)
            .foregroundColor(.secondary)
    }
}
.disabled(true)
```

Do the same for "New Requests".

**Also:** Add the localization key `"settings_always_enabled"` to `Localizable.xcstrings` with value `"Always enabled"`.

### Step 2.5: Update stale deletion-warning translations [Sonnet]

**Issue:** Non-English translations of `profile_confirm_deletion_message` are generic and don't list specific data types.

**File:** `NaarsCars/Resources/Localizable.xcstrings`

Find the key `profile_confirm_deletion_message` (around line 25289). For each translation (Spanish, Korean, Vietnamese, Chinese Simplified, Chinese Traditional), update the value to be a proper translation of the English string:

> "This will permanently delete your account including all rides, favors, messages, reviews, and Town Hall posts. Active requests you've claimed will be reopened for others. This cannot be undone."

Provide translated strings for each language. Also change the `extractionState` from `"stale"` to `"manual"` for each translation you update.

**Note:** If you are not confident in translation quality, mark this step as needing human review and provide the English string to be translated professionally.

*Step 2.6 (thread view wiring) was completed during pre-merge and is no longer needed.*

**Phase 2 Verification:**
```bash
# 2.1: lastRemoteUrl set in configure(remoteUrl:)
grep -A3 "func configure(remoteUrl:" NaarsCars/UI/Components/Messaging/Cells/ImageBubbleView.swift | grep lastRemoteUrl
# 2.2: no Color.white in MessageInputBar (except acceptable uses)
grep -n "Color.white" NaarsCars/UI/Components/Messaging/MessageInputBar.swift
# 2.3: deinit in MessageThreadViewController
grep -n "deinit" NaarsCars/Features/Messaging/Views/MessageThreadViewController.swift
# 2.4: caption on disabled toggles
grep -n "settings_always_enabled" NaarsCars/Features/Profile/Views/NotificationSettingsSection.swift
# 2.5: translations updated
grep -c "stale" NaarsCars/Resources/Localizable.xcstrings | head -1
```

---

## Phase 3: Localization & Accessibility

### Step 3.1: Localize hardcoded English in ConversationDetailView [Sonnet]

**File:** `NaarsCars/Features/Messaging/Views/ConversationDetailView.swift`

Make these replacements:

| Line | Current | Replacement |
|------|---------|-------------|
| ~90 | `"Chat"` (fallback name) | `"messaging_chat_fallback".localized` |
| ~93 | `"Chat"` (second fallback) | `"messaging_chat_fallback".localized` |
| ~260 | `"Unsend Message"` (alert title) | `"messaging_unsend_title".localized` |
| ~261 | `"Cancel"` (button) | `"common_cancel".localized` |
| ~264 | `"Unsend"` (destructive button) | `"messaging_unsend_action".localized` |

**Also add these keys to `NaarsCars/Resources/Localizable.xcstrings`:**
- `"messaging_chat_fallback"` → `"Chat"`
- `"messaging_unsend_title"` → `"Unsend Message"`
- `"common_cancel"` → `"Cancel"` (check if this key already exists first — if so, use the existing key)
- `"messaging_unsend_action"` → `"Unsend"`

### Step 3.2: Localize hardcoded "Reported" text [Sonnet]

**File:** `NaarsCars/Features/TownHall/Views/TownHallPostCard.swift`

Find (around line 251):
```swift
"Reported"
```

Replace with:
```swift
"townhall_reported".localized
```

**File:** `NaarsCars/Features/TownHall/Views/PostCommentsView.swift`

Same change at the equivalent line (~251).

**Add to Localizable.xcstrings:** `"townhall_reported"` → `"Reported"`

### Step 3.3: Add accessibility to MessageInputBar [Sonnet]

**File:** `NaarsCars/UI/Components/Messaging/MessageInputBar.swift`

**3.3a — Add menu (around line 119-123):**

Find:
```swift
            } label: {
                Image(systemName: "plus.circle.fill")
                    .font(.title2)
                    .foregroundColor(.naarsPrimary)
            }
```

Replace with:
```swift
            } label: {
                Image(systemName: "plus.circle.fill")
                    .font(.title2)
                    .foregroundColor(.naarsPrimary)
            }
            .accessibilityLabel("messaging_menu_add".localized)
            .accessibilityHint("messaging_menu_add_hint".localized)
```

**3.3b — Send button (around line 151-154):**

Find:
```swift
            .disabled(isDisabled)
            .accessibilityIdentifier("message.send")
```

Replace with:
```swift
            .disabled(isDisabled)
            .accessibilityIdentifier("message.send")
            .accessibilityLabel("messaging_send".localized)
            .accessibilityHint("messaging_send_hint".localized)
```

**3.3c — Localize text field accessibility (around line 133-135):**

Find:
```swift
                .accessibilityIdentifier("message.input")
                .accessibilityLabel("Message")
                .accessibilityHint("Type your message here")
```

Replace with:
```swift
                .accessibilityIdentifier("message.input")
                .accessibilityLabel("messaging_input_label".localized)
                .accessibilityHint("messaging_input_hint".localized)
```

**Add to Localizable.xcstrings:**
- `"messaging_menu_add"` → `"Attachments"`
- `"messaging_menu_add_hint"` → `"Open menu to attach photo, voice note, or location"`
- `"messaging_send"` → `"Send message"`
- `"messaging_send_hint"` → `"Send your message"`
- `"messaging_input_label"` → `"Message"`
- `"messaging_input_hint"` → `"Type your message here"`

**Phase 3 Verification:**
```bash
# No hardcoded English strings in target areas
grep -n '"Chat"\|"Unsend Message"\|"Unsend"\|"Reported"' NaarsCars/Features/Messaging/Views/ConversationDetailView.swift NaarsCars/Features/TownHall/Views/TownHallPostCard.swift NaarsCars/Features/TownHall/Views/PostCommentsView.swift
# Accessibility on input bar
grep -n "accessibilityLabel\|accessibilityHint" NaarsCars/UI/Components/Messaging/MessageInputBar.swift
```

---

## Phase 4: Low-Risk Cleanup

### Step 4.1: Use https for maps URLs consistently [Sonnet] [parallel]

**File:** `NaarsCars/UI/Components/Map/AddressText.swift`

Find the line using `maps://` scheme (around line 96):
```swift
"maps://?q=\(encodedAddress)"
```

Replace with:
```swift
"https://maps.apple.com/?address=\(encodedAddress)"
```

This matches the pattern in `NaarsCars/UI/Components/AddressText.swift` (line 97).

**Also check:** `NaarsCars/UI/Components/Messaging/Cells/LocationBubbleView.swift` around line 152 for any `maps://` usage and update to `https://maps.apple.com/` if found.

### Step 4.2: Replace deprecated UIScreen.main [Sonnet] [parallel]

**File:** `NaarsCars/Core/Services/MapSnapshotCache.swift` (around line 34)

Replace:
```swift
UIScreen.main.scale
```
with:
```swift
UITraitCollection.current.displayScale
```

**File:** `NaarsCars/UI/Components/Messaging/Overlay/OverlayActionListView.swift` (around line 164)

Same replacement.

**File:** `NaarsCars/UI/Components/Messaging/Cells/MessageBubble.swift` (around lines 82-83)

Same replacement.

### Step 4.3: Fix Info.plist formatting [Sonnet] [parallel]

**File:** `NaarsCars/Info.plist`

Find (line 64):
```xml
<key>NSFaceIDUsageDescription</key>
```

Replace with (add leading tab):
```xml
	<key>NSFaceIDUsageDescription</key>
```

### Step 4.4: Guard force unwraps on FileManager [Sonnet] [parallel]

**File:** `NaarsCars/Core/Services/PersistentImageService.swift` (around line 21)

Replace:
```swift
fileManager.urls(for: .cachesDirectory, in: .userDomainMask).first!
```
with:
```swift
fileManager.urls(for: .cachesDirectory, in: .userDomainMask).first ?? FileManager.default.temporaryDirectory
```

**File:** `NaarsCars/Core/Utilities/LocalAttachmentStorage.swift` (around line 16)

Same replacement pattern.

### Step 4.5: Prune dateSeparatorDates dictionary [Sonnet] [parallel]

**File:** `NaarsCars/UI/Components/Messaging/MessagesCollectionView.swift`

In the `updateUIView` method, find where `dateSeparatorDates` is populated (around line 152-159). Before building a new snapshot, clear stale entries:

Add before the snapshot-building loop:
```swift
// Prune stale date separator entries not in current snapshot
let currentSeparatorIds = Set(snapshot.itemIdentifiers.filter { $0.hasPrefix("date-") })
dateSeparatorDates = dateSeparatorDates.filter { currentSeparatorIds.contains($0.key) }
```

**Phase 4 Verification:**
```bash
# 4.1: no maps:// in production code
grep -rn "maps://" NaarsCars/ --include="*.swift" | grep -v Test | grep -v Preview
# 4.2: no UIScreen.main
grep -rn "UIScreen.main" NaarsCars/ --include="*.swift" | grep -v Test | grep -v Preview
# 4.3: plist formatting
python3 -c "import plistlib; plistlib.load(open('NaarsCars/Info.plist','rb')); print('Valid plist')"
# 4.4: no force unwraps on FileManager
grep -n "\.first!" NaarsCars/Core/Services/PersistentImageService.swift NaarsCars/Core/Utilities/LocalAttachmentStorage.swift
```

---

## Phase 5: Final Verification

### Step 5.1: Clean build [any LLM]

```bash
xcrun simctl shutdown all && killall -9 Simulator 2>/dev/null; sleep 2
timeout 180 xcodebuild -project NaarsCars/NaarsCars.xcodeproj \
    -scheme NaarsCars \
    -destination 'platform=iOS Simulator,name=iPhone 16' \
    build 2>&1 | tail -30
```

If the build fails, fix compiler errors before proceeding.

### Step 5.2: Run regression grep checks [any LLM]

```bash
echo "=== Force unwraps ==="
grep -rn '\.first!\|\.last!\|\.data!' NaarsCars/ --include="*.swift" | grep -v Test | grep -v Preview | grep -v node_modules

echo "=== Empty catch blocks ==="
grep -rn "catch {" NaarsCars/ --include="*.swift" -A1 | grep -B1 "^[^a-zA-Z]*}" | grep -v Test

echo "=== Debug code outside guards ==="
grep -rn "print(" NaarsCars/ --include="*.swift" | grep -v Test | grep -v Preview | grep -v "#if DEBUG" | grep -v AppLogger | head -10

echo "=== Hardcoded localhost/staging ==="
grep -rn "localhost\|127\.0\.0\.1\|staging" NaarsCars/ --include="*.swift" --include="*.plist" | grep -v Test | grep -v Preview | grep -v "#if DEBUG"

echo "=== Color.white/Color.black ==="
grep -rn "Color\.white\|Color\.black" NaarsCars/ --include="*.swift" | grep -v Test | grep -v Preview | grep -v overlay | grep -v shadow | grep -v stroke | grep -v mask
```

Review each finding. Any new issues introduced by the fixes should be addressed before committing.

### Step 5.3: Deploy database migrations [Opus]

Apply the Phase 0 migration files to the Supabase project:

```bash
# Use Supabase MCP or CLI to apply each migration
# Verify each one succeeds before applying the next
```

After applying, run these verification queries:
```sql
-- Auth guard on delete_user_account
SELECT prosrc FROM pg_proc WHERE proname = 'delete_user_account' LIMIT 1;

-- Reports table has post/comment columns
SELECT column_name FROM information_schema.columns WHERE table_name = 'reports' AND column_name IN ('reported_post_id', 'reported_comment_id');

-- submit_report accepts post/comment params
SELECT proargtypes FROM pg_proc WHERE proname = 'submit_report';

-- notifications INSERT policy scoped
SELECT polname, pg_get_expr(polwithcheck, polrelid) FROM pg_policy WHERE polrelid = 'notifications'::regclass AND polcmd = 'a';

-- notification_queue restricted
SELECT polname FROM pg_policy WHERE polrelid = 'notification_queue'::regclass;
```

### Step 5.4: Commit and prepare for review

Create a single commit (or one per phase if preferred):

```bash
git add -A
git commit -m "fix: App Store submission fixes from combined audit

- Fix reactions subscription leak in ConversationDetailView
- Add precise location to privacy manifest
- Add blocked-user content filtering to messages, posts, comments
- Fix main-thread image load in thread view
- Update NSCameraUsageDescription to match actual usage
- Fix ImageBubbleView remote retry dead code
- Fix Dark Mode Color.white on MessageInputBar
- Add deinit to MessageThreadViewController
- Add explanatory text to disabled notification toggles
- Update stale deletion-warning translations
- Localize hardcoded English strings
- Add accessibility to MessageInputBar
- Standardize maps URLs to https
- Replace deprecated UIScreen.main
- Guard force unwraps on FileManager
- Add 5 database migrations capturing live DB fixes"
```

---

## Summary Table

| ID | Phase | Step | LLM | Files Changed |
|----|-------|------|-----|---------------|
| P0.1 | 0 | Auth guard migration | Opus | `database/128_fix_delete_user_account_auth_guard.sql` |
| P0.2 | 0 | Reports columns migration | Opus | `database/128_fix_reports_add_post_comment_columns.sql` |
| P0.3 | 0 | submit_report migration | Opus | `database/128_fix_submit_report_post_comment.sql` |
| P0.4 | 0 | Notifications policy migration | Opus | `database/128_fix_notifications_insert_policy.sql` |
| P0.5 | 0 | notification_queue migration | Opus | `database/128_fix_notification_queue_service_role.sql` |
| P1.1 | 1 | Reactions subscription leak | Sonnet | `ConversationDetailView.swift` |
| P1.2 | 1 | Privacy manifest location | Sonnet | `PrivacyInfo.xcprivacy` |
| P1.3 | 1 | Blocked-user filtering | Opus | `MessageService.swift`, `TownHallService.swift`, `TownHallCommentService.swift`, `AppDelegate.swift` |
| P1.4 | 1 | Main-thread image load | Sonnet | `MessageThreadViewController.swift` |
| P1.5 | 1 | Camera description | Sonnet | `Info.plist` |
| P2.1 | 2 | Image retry fix | Sonnet | `ImageBubbleView.swift` |
| P2.2 | 2 | Dark Mode fix | Sonnet | `MessageInputBar.swift` |
| P2.3 | 2 | Thread VC deinit | Sonnet | `MessageThreadViewController.swift` |
| P2.4 | 2 | Toggle explanatory text | Sonnet | `NotificationSettingsSection.swift`, `Localizable.xcstrings` |
| P2.5 | 2 | Stale translations | Sonnet | `Localizable.xcstrings` |
| P2.6 | 2 | ~~Dead thread-view code~~ | ~~Opus~~ | *Completed during pre-merge* |
| P3.1 | 3 | Localize ConversationDetail | Sonnet | `ConversationDetailView.swift`, `Localizable.xcstrings` |
| P3.2 | 3 | Localize "Reported" | Sonnet | `TownHallPostCard.swift`, `PostCommentsView.swift`, `Localizable.xcstrings` |
| P3.3 | 3 | Input bar accessibility | Sonnet | `MessageInputBar.swift`, `Localizable.xcstrings` |
| P4.1 | 4 | maps:// → https | Sonnet | `AddressText.swift`, `LocationBubbleView.swift` |
| P4.2 | 4 | UIScreen.main deprecated | Sonnet | `MapSnapshotCache.swift`, `OverlayActionListView.swift`, `MessageBubble.swift` |
| P4.3 | 4 | Plist formatting | Sonnet | `Info.plist` |
| P4.4 | 4 | Force unwrap guards | Sonnet | `PersistentImageService.swift`, `LocalAttachmentStorage.swift` |
| P4.5 | 4 | Dictionary pruning | Sonnet | `MessagesCollectionView.swift` |

**Total: 23 active steps across 5 phases + final verification (Step 2.6 completed pre-merge)**
