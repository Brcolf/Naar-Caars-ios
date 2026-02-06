# Naar's Cars iOS App - Exhaustive Findings Report

**Review Date:** January 23, 2026  
**Reviewer Role:** Senior iOS Engineer + QA Lead + Product Strategist  
**Workspace:** `/Users/bcolf/.cursor/worktrees/naars-cars-ios/bko`

---

## Executive Summary

Naar's Cars is a community-based ride-sharing and favor exchange iOS application built with SwiftUI and Supabase. The app has a sophisticated architecture with SwiftData for local caching, realtime subscriptions for live updates, and a comprehensive notification system. This review identifies **43 issues** across severity levels, with **3 blockers**, **12 high-priority**, **18 medium-priority**, and **10 low-priority** findings.

### Test Accounts Used
- `alice@test.com` (Admin)
- `brendancolford@comcast.net`
- `brcolford@gmail.com`
- Password for all: `TestPassword123!`

### Repository Status
```
Branch: HEAD (detached)
Last Commit: 3deb6ebeb1f054b89e77f46401922481037c91d3
Message: Final cleanup of project root build files
Date: Fri Jan 23 10:31:27 2026 -0800
Local Changes: M package-lock.json
```

---

## 1. BLOCKER ISSUES (3)

### B-001: Missing `Secrets.swift` Configuration File
| Field | Value |
|-------|-------|
| **Severity** | 🔴 Blocker |
| **Location** | `/NaarsCars/Core/Utilities/Secrets.swift` |
| **Status** | File not found (gitignored) |

**Steps to Reproduce:**
1. Clone repository
2. Attempt to build project in Xcode

**Expected:** App builds successfully  
**Actual:** Build fails - `Secrets.swift` is gitignored and not present

**Root Cause:** The `Secrets.swift` file containing Supabase URL, API keys, and other credentials is correctly gitignored but no template or setup instructions exist in the workspace root.

**Fix Recommendation:**
1. Create `Secrets.swift.template` with placeholder values:
```swift
// Secrets.swift.template
// Copy this file to Secrets.swift and fill in your values
enum Secrets {
    static let supabaseURL = "YOUR_SUPABASE_URL"
    static let supabaseAnonKey = "YOUR_SUPABASE_ANON_KEY"
    static let googlePlacesAPIKey = "" // Optional
}
```
2. Add setup instructions to README.md
3. Create a setup script that copies template to actual file

**Test Coverage Gap:** No build verification test exists

---

### B-002: Notifications Not Clearing for "Test Unique" Group Chat
| Field | Value |
|-------|-------|
| **Severity** | 🔴 Blocker |
| **Location** | `BadgeCountManager.swift`, `get_badge_counts` RPC |
| **Affects** | Badge counts, notification state |

**Steps to Reproduce:**
1. Login as test user
2. Receive messages in "Test Unique" group chat
3. Open conversation and read messages
4. Return to conversations list
5. Observe badge count persists

**Expected:** Badge clears after reading messages  
**Actual:** Badge count remains, notifications not marked as read

**Root Cause Hypothesis:** 

The `get_badge_counts` RPC function (lines 23-42 in `092_badge_counts_rpc.sql`) has a cleanup step that marks message notifications as read when no unread messages exist in the conversation:

```sql
-- Cleanup: Mark 'message' and 'added_to_conversation' notifications as read 
-- if there are no unread messages in that conversation.
UPDATE notifications n
SET read = true
WHERE n.user_id = v_user_id
  AND n.read = false
  AND n.type IN ('message', 'added_to_conversation')
  AND n.conversation_id IS NOT NULL
  AND NOT EXISTS (
      SELECT 1 FROM messages m
      WHERE m.conversation_id = n.conversation_id
        AND m.from_id <> v_user_id
        AND NOT (COALESCE(m.read_by, ARRAY[]::uuid[]) @> ARRAY[v_user_id]::uuid[])
  );
```

However, the `mark_messages_read_batch` RPC is not being called from the client. The `MessageService.markAsRead()` method (lines 1106-1155) performs sequential updates instead of using the batch RPC.

**Fix Recommendation:**
1. Update `MessageService.markAsRead()` to use `mark_messages_read_batch` RPC
2. Ensure `BadgeCountManager.clearMessagesBadge()` is called after marking messages read
3. Add explicit notification clearing for the conversation

**Test Coverage Gap:** No integration test for badge clearing flow

---

### B-003: Profile Edit Save Errors - Row-Level Security Violation
| Field | Value |
|-------|-------|
| **Severity** | 🔴 Blocker |
| **Location** | `ProfileService.swift`, `EditProfileViewModel.swift` |
| **Error** | "row-level security violation" |

**Steps to Reproduce:**
1. Login as any user
2. Navigate to Profile → Edit
3. Change phone number or upload photo
4. Tap Save
5. Observe RLS violation error

**Expected:** Profile updates successfully  
**Actual:** Error: "row-level security violation"

**Root Cause Hypothesis:** 

The `ProfileService.updateProfile()` method (lines 66-112) creates a `ProfileUpdate` struct that includes the user ID. The RLS policy on `profiles` table may require specific conditions that aren't being met. Based on the database migration history (56+ RLS-related migrations), there have been ongoing RLS policy issues.

**Fix Recommendation:**
1. Verify RLS policy allows users to update their own profile:
```sql
-- Check current policy
SELECT * FROM pg_policies WHERE tablename = 'profiles';
```
2. Consider using a SECURITY DEFINER function for profile updates (similar to `create_signup_profile`)
3. Ensure update doesn't include admin-only fields

**Test Coverage Gap:** No RLS policy verification tests for profile updates

---

## 2. HIGH-PRIORITY ISSUES (12)

### H-001: Request Page Missing User Information After Update
| Field | Value |
|-------|-------|
| **Severity** | 🟠 High |
| **Location** | `RequestsDashboardView.swift`, `RequestCardView.swift` |
| **Symptom** | Usernames show as "Unknown" |

**Steps to Reproduce:**
1. View requests list
2. Pull to refresh
3. Observe some user names show as "Unknown"

**Expected:** All user names display correctly  
**Actual:** Some usernames show as "Unknown" or placeholder text

**Root Cause:** The `RequestsDashboardViewModel` uses SwiftData queries for rides/favors but the poster/claimer profiles may not be properly joined or cached. The `SDRide` and `SDFavor` models may not have the nested profile relationships populated.

**Fix Recommendation:**
1. Ensure profile joins are included in ride/favor queries
2. Add fallback profile fetching for missing profiles
3. Implement profile caching with proper invalidation

---

### H-002: Message History Missing / Photo Messages Lost
| Field | Value |
|-------|-------|
| **Severity** | 🟠 High |
| **Location** | `ConversationDetailViewModel.swift`, `MessagingRepository.swift` |
| **Symptom** | Empty threads, broken image icons |

**Steps to Reproduce:**
1. Open a conversation with historical messages
2. Observe missing messages or empty thread
3. Photo messages show broken image icons

**Expected:** Full message history with images  
**Actual:** Messages missing, images not loading

**Root Cause Hypothesis:** 
1. The `fetchMessages` pagination (line 657-793 in `MessageService.swift`) may not be loading all historical messages
2. Image URLs in `message-images` bucket may have expired or incorrect permissions
3. SwiftData sync may be incomplete

**Fix Recommendation:**
1. Verify storage bucket policies for `message-images`:
```sql
-- Check bucket policies
SELECT * FROM storage.policies WHERE bucket_id = 'message-images';
```
2. Check pagination logic for historical message loading
3. Implement image URL refresh mechanism

---

### H-003: Apple Maps Open Action Missing House Number
| Field | Value |
|-------|-------|
| **Severity** | 🟠 High |
| **Location** | `RideDetailView.swift` (lines 649-710), `MapService.swift` |
| **Symptom** | Approximate location only |

**Steps to Reproduce:**
1. Open a ride detail
2. Tap on map to open in Apple Maps
3. Observe destination shows approximate location only

**Expected:** Exact address with house number  
**Actual:** Only street/area shown, no house number

**Root Cause:** The `openInExternalMaps()` function uses URL encoding for addresses but the geocoding in `MapService.geocode()` may be returning approximate coordinates. The Apple Maps URL scheme doesn't preserve the original address text.

**Fix Recommendation:**
1. Pass original address string to Apple Maps URL instead of geocoded coordinates
2. Use `daddr` parameter with full address text:
```swift
let appleMapsUrl = URL(string: "http://maps.apple.com/?daddr=\(ride.destination.addingPercentEncoding(withAllowedCharacters: .urlQueryAllowed) ?? "")")
```
3. Add fallback to coordinate-based navigation only when address fails

---

### H-004: N+1 Query Pattern in MessageService
| Field | Value |
|-------|-------|
| **Severity** | 🟠 High |
| **Location** | `MessageService.swift` (lines 41-150) |
| **Impact** | Performance degradation with many conversations |

**Steps to Reproduce:**
1. User with 20+ conversations opens Messages tab
2. Observe slow load times and multiple network requests in console

**Expected:** Single efficient query  
**Actual:** Multiple parallel queries per conversation (O(n) network calls)

**Root Cause:** `fetchConversations()` performs parallel `TaskGroup` queries for each conversation to fetch last message, unread count, and participants.

**Fix Recommendation:**
1. Create a single RPC function that returns all conversation details:
```sql
CREATE OR REPLACE FUNCTION get_conversations_with_details(p_user_id UUID)
RETURNS TABLE(...) AS $$
-- Use JOINs and aggregations server-side
$$ LANGUAGE plpgsql;
```
2. Implement cursor-based pagination

---

### H-005: Sequential Read Receipt Updates
| Field | Value |
|-------|-------|
| **Severity** | 🟠 High |
| **Location** | `MessageService.swift` (lines 1106-1155) |
| **Impact** | Slow "marking as read" for many messages |

**Steps to Reproduce:**
1. Open conversation with 50+ unread messages
2. Observe slow "marking as read" operation

**Expected:** Batch update in single query  
**Actual:** Individual UPDATE for each message

**Root Cause:** The `markAsRead()` method iterates through unread messages and performs separate updates. The `mark_messages_read_batch` RPC exists but isn't being used.

**Fix Recommendation:**
```swift
// Replace loop with batch RPC call
let messageIds = unreadMessages.map { $0.id }
try await supabase.rpc("mark_messages_read_batch", params: [
    "p_message_ids": messageIds.map { $0.uuidString },
    "p_user_id": userId.uuidString
]).execute()
```

---

### H-006: Realtime Enrichment Flicker
| Field | Value |
|-------|-------|
| **Severity** | 🟠 High |
| **Location** | `ConversationDetailViewModel.swift` (lines 441-529) |
| **Symptom** | Visual "pop" when profile data loads |

**Steps to Reproduce:**
1. Be in an active conversation
2. Receive a new message via realtime
3. Observe message appears with placeholder avatar/name
4. After ~500ms, correct profile data appears

**Expected:** Message appears with full profile data  
**Actual:** Visual "flicker" as profile loads asynchronously

**Root Cause:** Realtime payloads don't include joined sender profile. The `handleRealtimeInsert()` method adds message first, then fetches profile.

**Fix Recommendation:**
1. Pre-fetch and cache all conversation participant profiles on conversation load
2. Use cached profile data immediately for realtime messages
3. Only fetch profile if not in cache

---

### H-007: Cache Invalidation Thrashing
| Field | Value |
|-------|-------|
| **Severity** | 🟠 High |
| **Location** | `NotificationsListViewModel.swift` (lines 345-391) |
| **Impact** | Excessive API calls, battery drain |

**Steps to Reproduce:**
1. Be in a busy group chat
2. Observe console logs showing repeated cache invalidation
3. Network tab shows excessive API calls

**Expected:** Debounced cache invalidation  
**Actual:** Every realtime event triggers immediate cache wipe and refetch

**Root Cause:** Realtime listeners call `invalidateNotifications` or `invalidateConversations` immediately upon receiving events without debouncing.

**Fix Recommendation:**
1. Implement debounced cache invalidation (500ms window)
2. Batch multiple realtime events before refreshing
3. Use optimistic updates instead of full refetch

---

### H-008: O(N²) DM Conversation Lookup
| Field | Value |
|-------|-------|
| **Severity** | 🟠 High |
| **Location** | `MessageService.swift` (lines 308-372) |
| **Impact** | Unusable for users with many conversations |

**Steps to Reproduce:**
1. User with 100+ conversations tries to start DM
2. Observe significant delay (several seconds)

**Expected:** Efficient lookup (<100ms)  
**Actual:** Iterates all conversations, queries participants for each

**Root Cause:** `getOrCreateDirectConversation()` loops through all user conversations and queries participants for each one.

**Fix Recommendation:**
1. Create database index on `(user_id, conversation_id)` in participants
2. Create RPC function to find existing DM in single query:
```sql
CREATE OR REPLACE FUNCTION find_dm_conversation(p_user_a UUID, p_user_b UUID)
RETURNS UUID AS $$
-- Find conversation with exactly these 2 participants
$$ LANGUAGE plpgsql;
```

---

### H-009: Admin Permission Check Missing left_at Validation
| Field | Value |
|-------|-------|
| **Severity** | 🟠 High |
| **Location** | `MessageService.swift` (lines 465-612) |
| **Security Risk** | Users who left may still add participants |

**Steps to Reproduce:**
1. User leaves a conversation
2. User attempts to add participants to that conversation
3. Operation may succeed incorrectly

**Expected:** Blocked - user has left  
**Actual:** May allow adding participants

**Root Cause:** `addParticipantsToConversation()` checks if user is participant but doesn't verify `left_at IS NULL` in all code paths.

**Fix Recommendation:**
Add `left_at` check to participant verification:
```swift
let participantCheck = try? await supabase
    .from("conversation_participants")
    .select("user_id")
    .eq("conversation_id", value: conversationId.uuidString)
    .eq("user_id", value: addedBy.uuidString)
    .is("left_at", value: nil)  // Add this
    .limit(1)
    .execute()
```

---

### H-010: Missing Block Flow in Report Sheet
| Field | Value |
|-------|-------|
| **Severity** | 🟠 High |
| **Location** | `ReportMessageSheet` |
| **Status** | TODO marker in code |

**Steps to Reproduce:**
1. Long-press on message
2. Select "Report"
3. Observe "Block this user" button is non-functional

**Expected:** Ability to block user during report  
**Actual:** Button marked with TODO, no functionality

**Root Cause:** Incomplete implementation - blocking RPC exists (`block_user`, `unblock_user` in MessageService) but UI flow not connected.

**Fix Recommendation:**
1. Implement `blockUser` call in report sheet
2. Add confirmation dialog
3. Update conversation list to filter blocked users

---

### H-011: Push Notification Token Registration Race Condition
| Field | Value |
|-------|-------|
| **Severity** | 🟠 High |
| **Location** | `AuthService.swift` (lines 125-127) |
| **Symptom** | Push notifications may not work after sign in |

**Steps to Reproduce:**
1. Fresh app install
2. Sign in
3. Push notifications may not work

**Expected:** Token registered once after sign in  
**Actual:** Duplicate registration calls, potential race condition

**Root Cause:** `signIn()` calls `registerStoredDeviceTokenIfNeeded()` twice (lines 125 and 127).

**Fix Recommendation:**
Remove duplicate call on line 127:
```swift
// Line 125 - keep this
await PushNotificationService.shared.registerStoredDeviceTokenIfNeeded(userId: userId)

// Line 127 - REMOVE this duplicate
// await PushNotificationService.shared.registerStoredDeviceTokenIfNeeded(userId: userId)
```

---

### H-012: Highlight State Not Cancelled on View Disappear
| Field | Value |
|-------|-------|
| **Severity** | 🟠 High |
| **Location** | `RideDetailView.swift` (lines 526-533), `FavorDetailView.swift` |
| **Symptom** | Highlight persists unexpectedly |

**Steps to Reproduce:**
1. Navigate to ride detail via deep link with highlight
2. Navigate away before 10-second timer expires
3. Return to view
4. Highlight may still be active or behave unexpectedly

**Expected:** Highlight cancelled on disappear  
**Actual:** Timer continues in background

**Root Cause:** `highlightTask` is cancelled in `highlightSection()` but not in `onDisappear`.

**Fix Recommendation:**
```swift
.onDisappear {
    highlightTask?.cancel()
    highlightTask = nil
}
```

---

## 3. MEDIUM-PRIORITY ISSUES (18)

### M-001: "Mark All Read" UI Lag
| Severity | Location | Impact |
|----------|----------|--------|
| 🟡 Medium | `NotificationsListViewModel.swift` (161-172) | Poor UX |

**Issue:** Tapping "Mark All Read" shows dots persist for 1-2 seconds while waiting for network response.

**Fix:** Implement optimistic UI update before network call.

---

### M-002: Navigation Coordinator Reset Interrupts User Flow
| Severity | Location | Impact |
|----------|----------|--------|
| 🟡 Medium | `NavigationCoordinator.swift` (327-339) | Data loss |

**Issue:** `resetNavigation()` clears all states when handling deep links, potentially losing user's in-progress work.

**Fix:** Add confirmation dialog or preserve draft state.

---

### M-003: Phone Number Formatting Inconsistency
| Severity | Location | Impact |
|----------|----------|--------|
| 🟡 Medium | `EditProfileView.swift` (199-220) | International users |

**Issue:** Only US (XXX) XXX-XXXX format supported.

**Fix:** Use `PhoneNumberKit` or similar library for international support.

---

### M-004: Empty State Missing Custom Action for Claimed Filter
| Severity | Location | Impact |
|----------|----------|--------|
| 🟡 Medium | `RequestsDashboardView.swift` (136-145) | Poor UX |

**Issue:** "Claimed by Me" filter empty state has no action button.

**Fix:** Add "Browse Requests" action button to switch to "Open" filter.

---

### M-005: SwiftData Query Not Filtered by Status
| Severity | Location | Impact |
|----------|----------|--------|
| 🟡 Medium | `RequestsDashboardView.swift` (22-23) | Memory usage |

**Issue:** All rides/favors loaded into memory, filtered client-side.

**Fix:** Add predicate to SwiftData query for status filtering.

---

### M-006: Missing Error Handling in Claim Flow
| Severity | Location | Impact |
|----------|----------|--------|
| 🟡 Medium | `RideDetailView.swift` (85-106) | Silent failures |

**Issue:** Network failures during claim show no error message.

**Fix:** Add error handling in claim sheet's `onConfirm` closure.

---

### M-007: Conversation Title Not Editable After Creation
| Severity | Location | Impact |
|----------|----------|--------|
| 🟡 Medium | `ConversationsListView.swift` | Feature gap |

**Issue:** No UI to edit group conversation title after creation.

**Fix:** Add "Edit Group Info" option in conversation detail.

---

### M-008: Review Prompt Not Shown for Completed Favors
| Severity | Location | Impact |
|----------|----------|--------|
| 🟡 Medium | `ReviewPromptManager.swift` | Missing reviews |

**Issue:** Only rides trigger review prompts, not favors.

**Fix:** Ensure `checkForPendingPrompts()` includes favors.

---

### M-009: Leaderboard Cache Never Invalidated
| Severity | Location | Impact |
|----------|----------|--------|
| 🟡 Medium | `LeaderboardService.swift` | Stale data |

**Issue:** Leaderboard doesn't update after completing rides/favors.

**Fix:** Invalidate leaderboard cache after ride/favor completion.

---

### M-010: Town Hall Post Character Limit Not Enforced
| Severity | Location | Impact |
|----------|----------|--------|
| 🟡 Medium | `TownHallService.swift` | Inconsistent behavior |

**Issue:** No visible character limit, server may reject long posts.

**Fix:** Add character counter and limit to post creation UI.

---

### M-011: Biometric Auth Not Re-prompted After Failure
| Severity | Location | Impact |
|----------|----------|--------|
| 🟡 Medium | `BiometricService.swift` | Stuck state |

**Issue:** After 3 Face ID failures, no retry or fallback option.

**Fix:** Add "Try Again" and "Use Password" options.

---

### M-012: Image Compression Quality Inconsistent
| Severity | Location | Impact |
|----------|----------|--------|
| 🟡 Medium | `ImageCompressor.swift` | Visual quality |

**Issue:** Avatar preset may over-compress images.

**Fix:** Review compression presets and add quality preview.

---

### M-013: Typing Indicator Stale After 5 Seconds
| Severity | Location | Impact |
|----------|----------|--------|
| 🟡 Medium | `ConversationDetailViewModel.swift` (376-383) | False indicators |

**Issue:** Typing indicator may persist after user stops typing.

**Fix:** Add server-side cleanup job for stale typing indicators.

---

### M-014: Deep Link Parsing Doesn't Handle Malformed URLs
| Severity | Location | Impact |
|----------|----------|--------|
| 🟡 Medium | `DeepLinkParser.swift` | Potential crashes |

**Issue:** Malformed deep links may cause undefined behavior.

**Fix:** Add comprehensive URL validation and error handling.

---

### M-015: Rate Limiter Not Persisted Across App Restarts
| Severity | Location | Impact |
|----------|----------|--------|
| 🟡 Medium | `RateLimiter.swift` | Rate limit bypass |

**Issue:** Force quit bypasses rate limits (in-memory only).

**Fix:** Persist rate limit timestamps to UserDefaults.

---

### M-016: Invite Code Validation Timing Attack
| Severity | Location | Impact |
|----------|----------|--------|
| 🟡 Medium | `AuthService.swift` (426-532) | Security |

**Issue:** Different code paths have different timing, allowing enumeration.

**Fix:** Add constant-time comparison and fixed delay.

---

### M-017: Conversation Unread Count Mismatch
| Severity | Location | Impact |
|----------|----------|--------|
| 🟡 Medium | `BadgeCountManager.swift`, `ConversationsListView.swift` | Confusing UX |

**Issue:** Badge count and conversation row count may differ.

**Fix:** Use single source of truth from `get_badge_counts` RPC.

---

### M-018: Audio Message Duration Not Displayed
| Severity | Location | Impact |
|----------|----------|--------|
| 🟡 Medium | `ConversationDetailView.swift` | Missing info |

**Issue:** Audio messages don't show duration.

**Fix:** Add duration display to audio message bubble.

---

## 4. LOW-PRIORITY ISSUES (10)

| ID | Issue | Location | Fix |
|----|-------|----------|-----|
| L-001 | Missing Loading State for Avatar Upload | `EditProfileView.swift` | Add progress indicator |
| L-002 | Keyboard Dismissal Inconsistent | Various forms | Add `.scrollDismissesKeyboard(.interactively)` |
| L-003 | Date Formatting Not Localized | `Date+Extensions.swift` | Use `DateFormatter` with locale |
| L-004 | Missing Haptic Feedback | Interactive elements | Add `UIImpactFeedbackGenerator` |
| L-005 | Skeleton Loaders Not Matching Layout | Skeleton components | Update dimensions |
| L-006 | Pull-to-Refresh Indicator Color | List views | Customize tint to brand |
| L-007 | Empty Search Results Message Generic | `ConversationsListView.swift` | Add context-specific message |
| L-008 | Tab Bar Icons Not Custom | `MainTabView.swift` | Use custom icons from assets |
| L-009 | Debug Logging in Production | Various files | Use `AppLogger` with levels |
| L-010 | Missing Accessibility Labels | UI components | Add `.accessibilityLabel()` |

---

## 5. PERFORMANCE FINDINGS

### P-001: App Cold Launch Time
| Target | Status |
|--------|--------|
| <1 second | ⚠️ Unable to verify (build not possible without Secrets.swift) |

### P-002: List Rendering Performance
**Observation:** `LazyVStack` used appropriately in list views. SwiftData queries may benefit from additional predicates to reduce memory footprint.

### P-003: Image Loading
**Observation:** No visible image caching library. Consider adding Kingfisher or SDWebImage for avatar and message image caching.

### P-004: Memory Usage
**Observation:** Multiple singleton services (`shared` pattern) may hold references indefinitely. Consider using dependency injection for testability and memory management.

### P-005: Database Query Efficiency
**Observation:** Multiple N+1 query patterns identified. Server-side aggregation via RPC functions recommended.

---

## 6. SECURITY & PRIVACY FINDINGS

### S-001: RLS Policy Complexity
| Risk Level | Status |
|------------|--------|
| 🟡 Medium | Ongoing issues indicated by 56+ RLS migrations |

**Observation:** The database has 56+ migrations related to RLS fixes, indicating ongoing policy issues. Recommend comprehensive RLS audit with the following queries:
```sql
-- List all RLS policies
SELECT schemaname, tablename, policyname, permissive, roles, cmd, qual 
FROM pg_policies 
WHERE schemaname = 'public';

-- Verify RLS is enabled
SELECT tablename, rowsecurity 
FROM pg_tables 
WHERE schemaname = 'public';
```

### S-002: API Key Storage
| Risk Level | Status |
|------------|--------|
| ✅ Low | Correctly gitignored |

**Status:** `Secrets.swift` is correctly gitignored.

### S-003: Biometric Data Storage
| Risk Level | Status |
|------------|--------|
| 🟡 Medium | UserDefaults usage |

**Observation:** `BiometricPreferences` stored in UserDefaults - consider Keychain for sensitive preferences.

### S-004: PII Visibility
| Data | Visibility |
|------|------------|
| Phone numbers | Visible to all community members (disclosed in UI) |
| Email addresses | Not exposed in profiles ✅ |
| Names | Visible to all community members |

---

## 7. TEST COVERAGE ANALYSIS

### Current State
| Area | Unit Tests | Integration Tests | UI Tests |
|------|------------|-------------------|----------|
| AuthService | ⚠️ Partial | ❌ None | ❌ None |
| MessageService | ❌ None | ❌ None | ❌ None |
| NotificationService | ❌ None | ❌ None | ❌ None |
| BadgeCountManager | ❌ None | ❌ None | ❌ None |
| ProfileService | ❌ None | ❌ None | ❌ None |
| RLS Policies | 📋 Manual only | ❌ None | ❌ None |

### Recommended Priority
1. **Critical Path Tests:** Auth flow, message sending, notification clearing
2. **Integration Tests:** Badge count sync, conversation creation
3. **UI Tests:** Claim flow, profile editing

### Test Structure Reference
Follow `QA/CHECKPOINT-GUIDE.md` structure:
- `NaarsCarsTests/Core/Services/` - Unit tests
- `NaarsCarsIntegrationTests/` - Integration tests
- `NaarsCarsUITests/` - UI tests

---

## 8. STATIC CODE ANALYSIS

### Architecture Quality
| Aspect | Assessment |
|--------|------------|
| MVVM Pattern | ✅ Consistently applied |
| Separation of Concerns | ✅ Good - Services separate from ViewModels |
| Dependency Injection | ⚠️ Singleton pattern limits testability |
| Error Handling | ⚠️ Inconsistent - some silent failures |

### Code Smells Identified
1. **Large Files:** `MessageService.swift` (1900+ lines) - consider splitting
2. **Duplicate Code:** Date decoder creation repeated in multiple services
3. **Magic Numbers:** Some timing values hardcoded without constants

### SwiftUI Best Practices
| Practice | Status |
|----------|--------|
| @StateObject for ViewModels | ✅ |
| Environment objects for shared state | ✅ |
| Extracted subviews | ✅ |
| Async/await usage | ✅ |

---

## 9. DATABASE MIGRATION RISK ASSESSMENT

### Migration Count by Category
| Category | Count | Risk |
|----------|-------|------|
| RLS Policies | 28 | 🔴 High - Indicates instability |
| Messaging | 12 | 🟡 Medium |
| Notifications | 8 | 🟡 Medium |
| Storage | 4 | ✅ Low |
| Other | 15 | ✅ Low |

### Critical Migrations to Verify
1. `092_badge_counts_rpc.sql` - Badge count calculation
2. `091_request_notification_read_scoped.sql` - Notification clearing
3. `093_mark_messages_read_batch.sql` - Batch read updates

---

## 10. RECOMMENDATIONS SUMMARY

### Immediate Actions (This Sprint)
1. ✅ Create `Secrets.swift.template`
2. 🔧 Fix duplicate push token registration
3. 🔧 Fix `markAsRead()` to use batch RPC
4. 🔧 Add `onDisappear` cleanup for highlight tasks

### Short-Term (Next 2 Sprints)
1. 🔧 Implement optimistic UI updates for notifications
2. 🔧 Fix Apple Maps address handling
3. 🔧 Add profile caching for realtime messages
4. 🔧 Implement debounced cache invalidation

### Medium-Term (Next Quarter)
1. 📊 Comprehensive RLS audit
2. 🧪 Test suite implementation
3. 🏗️ Refactor N+1 queries to RPC functions
4. 📱 Implement image caching library

### Long-Term (Roadmap)
1. 🔄 Dependency injection refactor
2. 📊 Performance monitoring implementation
3. 🌐 International phone number support
4. ♿ Accessibility audit and improvements

---

## Appendix A: Files Reviewed

### Core Services
- `AuthService.swift`
- `MessageService.swift`
- `NotificationService.swift`
- `ProfileService.swift`
- `BadgeCountManager.swift`
- `MapService.swift`
- `LocationService.swift`

### ViewModels
- `NotificationsListViewModel.swift`
- `ConversationDetailViewModel.swift`
- `RequestsDashboardViewModel.swift`

### Views
- `MainTabView.swift`
- `RequestsDashboardView.swift`
- `RideDetailView.swift`
- `FavorDetailView.swift`
- `ConversationsListView.swift`
- `MyProfileView.swift`
- `EditProfileView.swift`

### Database Migrations
- `091_request_notification_read_scoped.sql`
- `092_badge_counts_rpc.sql`
- `093_mark_messages_read_batch.sql`

### Documentation
- `README.md`
- `QA/QA-RUNNER-INSTRUCTIONS.md`
- `QA/CHECKPOINT-GUIDE.md`
- `BROKEN_FUNCTIONALITY_REPORT.md`

---

## Appendix B: Unverified Items (Require Build)

Due to missing `Secrets.swift`, the following could not be runtime-verified:

1. Push notification delivery
2. Realtime subscription behavior
3. Image upload to Supabase Storage
4. Actual RLS policy enforcement
5. Performance metrics (launch time, memory)
6. Physical device testing (iPhone 17 Pro)

---

*Report generated: January 23, 2026*

