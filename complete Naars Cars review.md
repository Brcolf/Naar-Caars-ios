# Product Requirements Document: Complete Naars Cars iOS Review & Remediation Plan

**Date:** January 23, 2026  
**Status:** Comprehensive Audit (Agnostic PRD)  
**Target Audience:** Engineering (Opus 4.5, Codex 5.2, Gemini Flash 3), QA, Product Management

---

## 1. Executive Summary

Naars Cars is a community-driven ride-sharing and favor exchange application built with SwiftUI, Supabase, and SwiftData. This document merges findings from three independent model reviews to provide a single source of truth for the current state of the application.

The application architecture is robust but suffers from significant performance bottlenecks in the messaging layer, critical configuration gaps for new developers, and UI/UX inconsistencies. A total of **43+ issues** have been identified, categorized by severity to guide remediation.

### Key Metrics & Environment
- **Workspace:** `/Users/bcolf/Documents/naars-cars-ios`
- **Last Commit:** `3deb6ebeb1f054b89e77f46401922481037c91d3` (Final cleanup of project root build files)
- **Primary Tech Stack:** SwiftUI, Supabase (PostgreSQL/RLS/Realtime), SwiftData, Apple Maps.

---

## 2. Blocker Issues (Critical Path / Build Failures)

### B-001: Missing `Secrets.swift` Configuration
- **Issue:** The `NaarsCars/Core/Utilities/Secrets.swift` file is gitignored and missing from the repo, preventing clean builds without manual intervention.
- **Requirement:** Provide a `Secrets.swift.template` and setup instructions in `README.md`.
- **Impact:** Immediate build failure for new developers.

### B-002: Messaging Cache API Mismatch
- **Issue:** `MessageService.swift` references conversation/message cache APIs in `CacheManager` that do not exist (only profiles/rides/favors/notifications/town hall are defined).
- **Requirement:** Align `CacheManager` with `MessageService` requirements or migrate fully to SwiftData for messaging persistence.
- **Impact:** Likely build failure or runtime crash in messaging features.

### B-003: N+1 Query Performance in Messaging
- **Issue:** `MessageService.fetchConversations` triggers parallel network requests per conversation for metadata (last message, unread count, participants). 20 conversations = 60+ requests.
- **Requirement:** Implement a single RPC (`get_conversations_with_details`) to fetch all metadata in one round-trip.
- **Impact:** App becomes unusable for active users; severe latency and battery drain.

### B-004: Notification Persistence in Group Chats
- **Issue:** Badge counts and notifications for "Test Unique" group chat do not clear even after reading.
- **Requirement:** Fix the `get_badge_counts` RPC and ensure `mark_messages_read_batch` is called reliably.
- **Impact:** User confusion and "ghost" notifications.

---

## 3. High-Priority Issues (Functional & Security)

### H-001: Profile Edit RLS Violation
- **Issue:** Saving profile changes (phone, car details) results in "row-level security violation".
- **Requirement:** Audit `004_rls_policies.sql` and `ProfileService.updateProfile`. Ensure `auth.uid()` context is correctly passed and policies aren't recursive.
- **Impact:** Users cannot update their own profiles.

### H-002: Requests Dashboard "Unknown User" Bug
- **Issue:** After pull-to-refresh, request cards show "Unknown User" for poster/claimer.
- **Requirement:** Ensure SwiftData models (`SDRide`, `SDFavor`) persist profile data or hydrate them immediately upon fetch.
- **Impact:** Core app functionality (requesting/claiming) is visually broken.

### H-003: O(N²) Direct Message Lookup
- **Issue:** `getOrCreateDirectConversation` iterates all conversations and performs fresh queries for participants for each.
- **Requirement:** Implement a server-side RPC `find_dm_conversation(user_a, user_b)` to return the ID in one query.
- **Impact:** Significant UI hang when starting new chats.

### H-004: Message History Pagination Blocked
- **Issue:** Scrolling up in long threads fails to load older messages beyond the initial 25.
- **Requirement:** Update `fetchMessages` to bypass cache when `beforeMessageId` is provided and ensure repository sync handles historical data.
- **Impact:** Loss of conversation context for users.

### H-005: Avatar Deletion on Profile Edit
- **Issue:** Saving profile without selecting a new image may clear the existing `avatar_url`.
- **Requirement:** Modify `EditProfileViewModel` to only include `avatarUrl` in the update payload if a new image was actually selected.
- **Impact:** Data loss (user avatars).

### H-006: Realtime Enrichment Flicker
- **Issue:** New messages via Realtime show "Unknown" sender for ~500ms before profile data loads.
- **Requirement:** Pre-fetch/cache participant profiles or include sender info in the Realtime payload (if possible).
- **Impact:** Poor UX; "popping" UI elements.

### H-007: Push Notification Token Race Condition
- **Issue:** `AuthService.signIn()` calls `registerStoredDeviceTokenIfNeeded` twice, causing duplicate registration.
- **Requirement:** Remove the redundant call on line 127 of `AuthService.swift`.
- **Impact:** Unreliable push notification delivery.

### H-008: Admin Permission Check Logic
- **Issue:** `addParticipantsToConversation` doesn't consistently verify if the adding user has `left_at IS NULL`.
- **Requirement:** Add explicit `is("left_at", value: nil)` check to participant verification.
- **Impact:** Security risk; users who left could potentially still manipulate group membership.

---

## 4. Medium-Priority Issues (UX & Polish)

### M-001: Apple Maps Address Precision
- **Issue:** Opening Apple Maps from a ride/favor shows approximate location only, missing house numbers.
- **Requirement:** Pass the full original address string to the `daddr` parameter in the Apple Maps URL scheme.

### M-002: "Mark All Read" UI Lag
- **Issue:** Unread dots persist for 1-2 seconds after tapping "Mark All Read".
- **Requirement:** Implement optimistic UI updates in `NotificationsListViewModel`.

### M-003: Cache Invalidation Thrashing
- **Issue:** Every Realtime event triggers an immediate full cache wipe and refetch.
- **Requirement:** Implement debounced cache invalidation (e.g., 500ms window) and use optimistic upserts.

### M-004: Navigation Coordinator Reset
- **Issue:** Deep link handling clears all navigation state, potentially losing user's unsaved work.
- **Requirement:** Add confirmation dialogs or preserve draft states during coordinator resets.

### M-005: Phone Number Formatting
- **Issue:** Hardcoded US format `(XXX) XXX-XXXX`.
- **Requirement:** Integrate `PhoneNumberKit` for international support.

### M-006: SwiftData Query Filtering
- **Issue:** All rides/favors are loaded into memory and filtered client-side.
- **Requirement:** Add `Predicate` to SwiftData queries to filter by status at the storage level.

---

## 5. Low-Priority & "Papercuts"

- **L-001: Missing Block Flow:** "Block this user" in `ReportMessageSheet` is a `TODO`.
- **L-002: Audio Message Duration:** Missing duration display in chat bubbles.
- **L-003: Haptic Feedback:** Missing from interactive elements (buttons, pull-to-refresh).
- **L-004: Keyboard Dismissal:** Inconsistent behavior in forms; needs `.scrollDismissesKeyboard(.interactively)`.
- **L-005: Accessibility:** Missing labels for custom UI components.

---

## 6. Performance & Security Audit

### Performance
- **Cold Launch:** Verification pending (blocked by `Secrets.swift`).
- **Memory Management:** Singleton services (`shared` pattern) may cause memory pressure; consider Dependency Injection.
- **Image Loading:** No dedicated caching library (Kingfisher/SDWebImage) identified for avatars/messages.

### Security & Privacy
- **RLS Stability:** 56+ migrations related to RLS indicate high instability; a full audit is required.
- **PII Visibility:** Phone numbers are visible to all community members; verify if this aligns with privacy policy.
- **Biometric Data:** `BiometricPreferences` stored in `UserDefaults`; consider `Keychain` for sensitive flags.

---

## 7. Test Coverage Analysis

| Area | Status | Recommendation |
| :--- | :--- | :--- |
| **Auth Flow** | ⚠️ Partial | Add integration tests for token refresh. |
| **Messaging** | ❌ None | Critical: Test `markAsRead` and Realtime inserts. |
| **RLS Policies** | 📋 Manual | Implement database-level unit tests for policies. |
| **UI/UX** | ❌ None | Add UI tests for the Claim/Request flow. |

---

## 8. Remediation Roadmap

### Phase 1: Stability (Immediate)
1. Fix `Secrets.swift` and `CacheManager` build blockers.
2. Implement `get_conversations_with_details` RPC to resolve N+1 performance.
3. Fix RLS Profile Save violation.

### Phase 2: Core UX (Short-Term)
1. Fix "Unknown User" in Requests Dashboard.
2. Implement Batch Read Receipts for messaging.
3. Fix Apple Maps address precision.

### Phase 3: Optimization (Medium-Term)
1. Implement debounced cache invalidation.
2. Integrate image caching library.
3. Complete "Block User" and "Report" flows.

---
*End of Document*


