# iMessage Parity Audit: NaarsCars Messaging Module

**Audit Date:** February 6, 2026
**Auditor:** Principal Engineer / Lead Systems Auditor
**Target Audience:** Claude Opus 4.6 (Principal Architect)

---

## Executive Summary

This audit compares the current NaarsCars messaging implementation against the "Gold Standard" of iOS messaging: **Apple's iMessage**.

**Verdict:** The current implementation is functional but architecturally fundamentally different from iMessage, leading to "jank," "pop-in," and reliability issues. It operates as a **"Network-First, Cache-Later"** system, whereas iMessage is strictly **"Local-First, Sync-Background"**.

To achieve iMessage parity, we must invert the data flow, optimize the rendering pipeline, and harden the optimistic UI logic.

---

## 1. Architecture & Data Flow: The "Local First" Gap

### iMessage Standard
*   **Source of Truth:** Local Database (SQLite/CoreData). The UI *never* waits for the network.
*   **Read Path:** UI <-> NSFetchedResultsController <-> Local DB.
*   **Write Path:** UI -> Local DB (State: Sending) -> Background Daemon -> Network -> Local DB (State: Sent/Delivered).
*   **Sync:** Background process merges cloud changes into Local DB. UI updates reactively.

### NaarsCars Current State
*   **Source of Truth:** Hybrid / Ambiguous.
*   **Read Path:** `ConversationDetailViewModel.loadMessages` fetches from Network, *then* merges with Local.
    *   *Result:* UI flickers/pops as network results arrive and re-sort the list.
*   **Write Path:** UI -> ViewModel (Memory) -> Network -> Local DB.
    *   *Result:* If app crashes during send, message is lost (only exists in `pendingMessages` RAM).
*   **Sync:** `MessagingSyncEngine` listens to Realtime -> Updates SwiftData -> `MessagingRepository` publisher -> ViewModel.

### 🚨 Critical Action Items
1.  **Strict Local-First Read:** `ConversationDetailViewModel` must **ONLY** read from `MessagingRepository` (SwiftData). It should never call `messageService.fetchMessages` directly for the initial render.
2.  **Background Sync:** `MessagingRepository` should trigger the network fetch internally. The ViewModel should not know or care about the network request status for *reading*.
3.  **Persistence for Pending:** Optimistic messages must be written to SwiftData immediately with a `status = .sending` flag. The `pendingMessages` dictionary in the ViewModel must be removed.

---

## 2. Scroll Performance & Layout: The "Jank" Factor

### iMessage Standard
*   **Rendering:** `UICollectionView` (or highly optimized SwiftUI equivalent) with pre-calculated layout attributes.
*   **Pagination:** Bi-directional infinite scroll. Maintains scroll position (content offset) perfectly when inserting items at the top.
*   **Sorting:** Data is stored sorted. Fetch requests are sorted by the DB index. No main-thread sorting.

### NaarsCars Current State
*   **Rendering:** `ScrollView` + `LazyVStack`.
*   **Pagination:** `loadMoreMessages` manually prepends items.
*   **Sorting:** `ConversationDetailViewModel` performs `merged.sort { $0.createdAt < $1.createdAt }` on the `@MainActor`.
    *   *Result:* Frame drops when opening large conversations.
*   **Scroll Management:** Uses `ScrollViewReader` and `onChange` modifiers. This is often "one frame late," causing visual jumps.

### 🚨 Critical Action Items
1.  **Offload Sorting:** The `merged.sort` MUST move to a background actor or be eliminated by relying on the database's sort order (`FetchDescriptor(sortBy: ...)`).
2.  **Scroll Position Stability:** Investigate `scrollPosition(id:)` (iOS 17+) or a custom `UIViewRepresentable` wrapper around `UITableView`/`UICollectionView` if SwiftUI's `ScrollView` cannot handle top-insertion without jumping.
3.  **Reduce View Body Complexity:** `MessageBubble` computes `detectedURLs` and `isSystemMessage` on every render. These should be computed properties on the `Message` model or cached in the ViewModel.

---

## 3. Optimistic UI & Reliability: The "Trust" Factor

### iMessage Standard
*   **Send State:** Message appears instantly. Progress bar at top. "Delivered" status updates asynchronously.
*   **Failure Handling:** Red exclamation mark. Tap to retry. *Persists across app restarts.*
*   **Resilience:** If network drops, message sits in "Sending" state until network returns.

### NaarsCars Current State
*   **Send State:** `pendingMessages` dictionary tracks optimistic messages.
*   **Failure Handling:** `failedMessageIds` set (in memory).
*   **Resilience:** Zero. If the app is killed while `isFailed` is true, the message is gone forever.

### 🚨 Critical Action Items
1.  **Database-Driven State:** Add `status` enum to `SDMessage` (`sending`, `sent`, `delivered`, `failed`, `read`).
2.  **Send Worker:** Create a `MessageSendWorker` (actor) that observes `SDMessage`s with `status == .sending`. It attempts to send them and updates the DB. It survives UI lifecycles.
3.  **Retry Logic:** "Tap to Retry" should simply flip the status back to `.sending` in the DB, waking up the worker.

---

## 4. Media & Rich Content

### iMessage Standard
*   **Loading:** Blurhash / Low-res thumbnail immediately. High-res loads progressively.
*   **Upload:** Image is written to disk immediately. Upload happens in background. UI shows local file path until upload completes.

### NaarsCars Current State
*   **Loading:** `CachedAsyncImage` with a generic placeholder.
*   **Upload:** `mediaService.uploadMessageImage` blocks the send flow.
    *   *Result:* User waits for upload before the message "appears" as sent.

### 🚨 Critical Action Items
1.  **Local Asset Path:** `Message` model needs a `localAttachmentPath` property.
2.  **Immediate Render:** Display the local image immediately from disk. Do not wait for the remote URL.
3.  **Background Upload:** Upload task should run independently. Once complete, update the `SDMessage` with the remote `imageUrl`.

---

## 5. Realtime & Presence

### iMessage Standard
*   **Typing Indicators:** Ephemeral, low-latency.
*   **Read Receipts:** granular (per message) but aggregated for UI ("Read by 3 people").

### NaarsCars Current State
*   **Typing:** `TypingIndicatorManager` polls/subscribes. Good.
*   **Read Receipts:** `Message` model has `readBy: [UUID]`.
*   **Issue:** `MessagingRepository.upsertMessage` triggers a full UI refresh for every read receipt update.
    *   *Result:* If 10 people read a message, the UI re-renders 10 times.

### 🚨 Critical Action Items
1.  **Throttle Updates:** Ensure `MessagingRepository` throttles updates for metadata-only changes (like `readBy` or `lastSeen`).
2.  **Separate Stream:** Consider a separate `Combine` stream for "Message Status Updates" vs "New Messages" to avoid re-calculating the entire list layout for a read receipt.

---

## 6. Implementation Plan for Claude

1.  **Phase 1: Data Layer Hardening (The Foundation)**
    *   Modify `SDMessage` schema to support `status` and `localAttachmentPath`.
    *   Refactor `MessagingRepository` to be the *sole* provider of data to the ViewModel.
    *   Implement `MessageSendWorker` for durable, background sending.

2.  **Phase 2: Performance (The Feel)**
    *   Remove main-thread sorting.
    *   Optimize `MessageBubble` (cache expensive computations).
    *   Implement proper pagination that doesn't rely on `loadMoreMessages` triggering a network call directly (network should backfill DB, DB updates UI).

3.  **Phase 3: Media & Polish (The Look)**
    *   Implement local-first image rendering.
    *   Refine scroll position management.
