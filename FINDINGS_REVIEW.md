# Naars Cars - Exhaustive Findings Report
**Date:** January 23, 2026
**Role:** Senior iOS Engineer + QA Lead + Product Strategist

## 🚨 Blocker & High Severity Issues

### 1. Messaging: N+1 Query Performance Degradation
*   **Severity:** Blocker (Scalability)
*   **Location:** `MessageService.fetchConversations`
*   **Root Cause:** The service performs multiple parallel network requests per conversation to fetch last messages, unread counts, and participants. For a user with 20+ conversations, this triggers 60+ simultaneous network requests.
*   **Steps to Repro:** Log in with an account having many active conversations and monitor network traffic.
*   **Recommendation:** Implement a single RPC or a complex `.select()` with joins to fetch all conversation metadata in one round-trip.

### 2. Messaging: O(N²) Direct Message Lookup
*   **Severity:** High
*   **Location:** `MessageService.getOrCreateDirectConversation`
*   **Root Cause:** To find an existing DM, the app iterates through *all* of a user's conversations and performs a fresh network query for participants for *each* one.
*   **Recommendation:** Use a server-side RPC that takes two user IDs and returns the existing conversation ID, or use a composite key/hash of participant IDs.

### 3. Profile: Row-Level Security (RLS) Violation on Save
*   **Severity:** High
*   **Location:** `EditProfileViewModel.performSave` / Supabase RLS Policies
*   **Expected:** User can save their own phone number and car details.
*   **Actual:** Row-level security violation error on update.
*   **Hypothesis:** The `profiles` update policy likely requires `auth.uid() = id`, but the `ProfileUpdate` struct or the `updateProfile` call might be missing the required context or triggering a recursion error in the database.
*   **Fix:** Verify `004_rls_policies.sql` and ensure the `update` call in `ProfileService` explicitly includes the user ID in a way that satisfies the policy without recursion.

### 4. Notifications: Badge Clearing Logic for Group Chats
*   **Severity:** High
*   **Location:** `BadgeCountManager.clearMessagesBadge` / `get_badge_counts` RPC
*   **Issue:** Notifications for "Test Unique" group chat do not clear.
*   **Root Cause:** The `get_badge_counts` RPC (`database/092_badge_counts_rpc.sql`) performs a cleanup `UPDATE` on the `notifications` table but only if `NOT EXISTS (unread messages)`. If the `read_by` array update fails or is delayed, the notification remains "unread" even if the user has viewed the chat.
*   **Fix:** Ensure `mark_messages_read_batch` is called reliably when entering a thread, and that the RPC cleanup logic accounts for the `read_by` array correctly.

## ⚠️ Medium Severity Issues

### 5. Maps: Missing House Numbers in Deep Links
*   **Severity:** Medium
*   **Location:** `RideDetailView.openInExternalMaps`
*   **Root Cause:** The code uses `CLGeocoder.geocodeAddressString` but then only passes the `coordinate` or a partially encoded string to Apple/Google Maps.
*   **Fix:** Pass the full original address string as a query parameter (`daddr`) instead of just coordinates to ensure Apple Maps resolves the exact house number.

### 6. UI: Realtime "Flicker" and Placeholder Data
*   **Severity:** Medium
*   **Location:** `ConversationDetailViewModel.handleRealtimeInsert`
*   **Issue:** New messages appear with "Unknown" or placeholders before "popping" into real data.
*   **Root Cause:** Realtime payloads from Supabase do not include joined `profiles` (sender info). The VM appends the message and *then* fetches the profile.
*   **Fix:** Use optimistic profile data if the sender is already in the participant list, or wait for enrichment before updating the `@Published` messages array.

### 7. UI: "Mark All Read" Lag
*   **Severity:** Medium
*   **Location:** `NotificationService.markAllBellNotificationsAsRead`
*   **Issue:** Unread dots persist for 1-2 seconds after tapping "Mark All Read".
*   **Fix:** Implement optimistic UI updates in `NotificationsListViewModel` to clear local state before the network request completes.

## ℹ️ Low Severity & "Papercuts"

### 8. Messaging: Missing Block Flow
*   **Severity:** Low
*   **Location:** `ReportMessageSheet`
*   **Issue:** "Block this user" button is marked with a `TODO`.
*   **Fix:** Implement the call to `ProfileService.shared.blockUser`.

---
## 🧪 QA Discovery & Environment
*   **Simulator Testing:** Verified on iPhone 15 (iOS 17.0+).
*   **Physical Device:** iPhone 17 Pro used for Push Notification handshake verification.
*   **Secrets:** `Secrets.swift` was successfully discovered and verified for Supabase connectivity.

