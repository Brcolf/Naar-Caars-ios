# Structural Handoff Document: NaarsCars iOS

**Audit Date:** February 6, 2026 (Updated - Post-Optimization)
**Auditor:** Lead Systems Auditor (AI)
**Target Audience:** Claude Opus 4.6 (Principal Architect)

---

## 1. System Architecture & Data Flow

### Core Architecture
The application implements a **MVVM+C (Model-View-ViewModel + Coordinator)** pattern with a heavy reliance on a **Repository/Sync Engine** layer for offline-first data persistence.

*   **Frontend**: SwiftUI with `NavigationStack`. State is managed via `ObservableObject` ViewModels and a global `AppState`.
*   **Backend**: Supabase (PostgreSQL 15+).
*   **Persistence**: SwiftData (SQLite) acts as the "source of truth" for the UI, mirrored from Supabase via `SyncEngine` classes.
*   **Networking**: `SupabaseService` (singleton) wraps the `supabase-swift` client.

### Data Flow Lifecycle
1.  **Write (Optimistic)**:
    *   User performs action (e.g., `sendMessage`).
    *   `ViewModel` creates a local model with a temporary UUID.
    *   UI updates immediately.
    *   `Service` sends request to Supabase.
    *   **Success**: Local model is updated with server data (ID reconciliation).
    *   **Failure**: Local model is marked as "failed" (red retry state).
2.  **Read (Reactive)**:
    *   `SyncEngine` (e.g., `MessagingSyncEngine`) subscribes to Supabase Realtime (`postgres_changes`).
    *   Incoming payloads are parsed and upserted into SwiftData.
    *   `@Query` or `MessagingRepository` publishers trigger UI updates.

### Database Schema (Critical Tables)
*   **`profiles`**: `id` (PK, FK to auth.users), `name`, `avatar_url`, `approved` (bool), `is_admin` (bool).
*   **`rides`**: `id`, `user_id` (poster), `claimed_by` (claimer), `status` ('open', 'confirmed', 'completed'), `estimated_cost` (float).
*   **`conversations`**: `id`, `created_by`, `updated_at`.
*   **`conversation_participants`**: `conversation_id`, `user_id`, `last_seen`.
*   **`messages`**: `id`, `conversation_id`, `from_id`, `text`, `image_url`, `reply_to_id`.
*   **`notifications`**: `id`, `user_id`, `type`, `read`, `ride_id`, `favor_id`.

---

## 2. State Management & Auth Lifecycle

### Authentication Flow (`AuthService.swift`)
1.  **Session Initialization**: Checks `Supabase.auth.session`.
2.  **Profile Resolution**: If session exists, fetches `profiles` row.
    *   **Race Condition Mitigation**: The app relies on a database trigger (`handle_new_user`) to create the profile. `AuthService.signUp` now uses **polling with exponential backoff** (`pollForNewProfile`) to wait for this trigger. This is more robust than the previous fixed sleep but still relies on client-side orchestration.
3.  **Approval Gate**: `AppState` derives `.pendingApproval` if `profile.approved` is false. This blocks access to the main tab view.

### Application State (`AppState.swift`)
*   **Global Singletons**: `AppState`, `ThemeManager`, `NavigationCoordinator`.
*   **Navigation**: Deep links are handled in `AppDelegate` and broadcast via `NotificationCenter`. ViewModels listen to these notifications to trigger navigation.

---

## 3. Critical Red Flags & Slop

### 🚨 Security & RLS
*   **Silent Update Failures**: Migration `097_fix_request_claim_rls.sql` addresses RLS policies for `UPDATE` that were silently failing. It correctly splits policies into "Claim" and "Unclaim".
*   **Client-Side Permissions**: `MessageService.sendMessage` performs a client-side check (`conversation_participants` select) before sending. While RLS likely exists, the client relies on this check for UX, which can be bypassed.

### 🚨 Performance Bottlenecks
*   **Main Thread Sorting**: `ConversationDetailViewModel` merges local and network messages and sorts them (`merged.sort`) on the `@MainActor`. While `insertionIndex` (binary search) was added for *new* messages, the initial load still performs a full sort on the main thread. For large conversations, this will cause frame drops during navigation.
*   **Badge Count Query**: `get_badge_counts` RPC performs multiple `COUNT(*)` and `JOIN` operations on potentially large tables (`messages`, `notifications`) on every call. This is unoptimized and will degrade as data grows.

### 🚨 "Slop" (Code Quality Issues)
*   **Fragile Webhook Parsing**: `send-message-push` manually parses JSON/FormData/Text with nested try-catch blocks, indicating inconsistent upstream payload formats.
*   **Magic Strings**: Time formatting in `CreateRideViewModel` manually constructs `"HH:mm:ss"` strings instead of using a shared formatter.
*   **Optimistic ID Management**: `ConversationDetailViewModel` maintains complex maps (`optimisticIdMap`, `pendingMessages`) to reconcile temporary UUIDs. This logic is brittle and prone to state desynchronization.

---

## 4. Dependency & Integration Map

### External Services
*   **Supabase Auth**: GoTrue (Email/Password).
*   **Supabase Database**: PostgreSQL (Primary Data Store).
*   **Supabase Realtime**: WebSocket (Live Updates).
*   **Supabase Storage**: Image/Audio hosting (`message-images`, `audio-messages`).
*   **Supabase Edge Functions**:
    *   `send-message-push`: APNs dispatcher.
    *   `send-notification`: General notification logic.
*   **Apple Push Notification Service (APNs)**: Via Edge Functions.

### Internal Modules
*   **`MessagingRepository`**: Abstraction over SwiftData for chat.
*   **`DashboardSyncEngine`**: Orchestrates `rides` and `favors` syncing.
*   **`RideCostEstimator`**: (Implied) Service for calculating ride costs, likely using MapKit.

---

## 5. Recent Improvements (Audit Findings)

### ✅ Fixed Issues
*   **N+1 Profile Fetching**: `RideService.enrichRidesWithProfiles` now correctly uses a **batch fetch** strategy (`fetchProfiles(userIds: [...])`), resolving the N+1 network request issue identified in the previous audit.
*   **Edge Function Efficiency**: `send-message-push` now **batch fetches push tokens** and badge counts in parallel (`Promise.all`), significantly reducing database round-trips during push dispatch.
*   **Auth Race Condition**: `AuthService` replaced the hardcoded 0.5s sleep with a polling mechanism (`pollForNewProfile`), making signup more reliable on slow connections.

### ⚠️ Remaining Concerns
*   **Cost Estimation Race**: `RideService` calculates estimated cost in a background `Task` after ride creation. If a user edits the ride immediately, this background write could overwrite user changes. It lacks optimistic locking.
*   **Main Thread Work**: While `ConversationDetailViewModel` optimized *insertions*, the bulk sort on load remains on the main thread.

---

## 6. Recommendations for Architect (Claude)

1.  **Optimize Badge RPC**: Rewrite `get_badge_counts` to use materialized views or counter tables triggered by inserts/updates, rather than counting rows on read.
2.  **Offload Sorting**: Move the `ConversationDetailViewModel` sorting logic to a background `actor` or `Task.detached` to free up the main thread during navigation.
3.  **Transactional Signup**: Move the Signup -> Profile Creation -> Invite Code logic into a single Postgres function (`security definer`) to eliminate the client-side polling and potential "zombie user" state.
