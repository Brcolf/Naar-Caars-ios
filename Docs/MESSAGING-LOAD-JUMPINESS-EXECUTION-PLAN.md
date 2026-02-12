# Message View Load Jumpiness — Execution Plan

**Goal:** Eliminate jumpiness when opening a conversation by aligning with how iMessage/WhatsApp load and display: **one or two coherent UI updates** instead of several rapid updates (local → network merge → repository publisher → reply hydration).

**Scope:** ViewModel and thread ViewModel only. No new files, no UI redesign. Minimal, targeted changes.

**Date:** February 6, 2026

---

## 1. How iMessage/WhatsApp Behave

- **Single coherent frame:** They show either a loading state or the final list. They do not flash: local list → merged list → sync list → list with reply previews.
- **Cached data as final until refresh:** When cache is shown, it is treated as the single source of truth until a deliberate refresh completes (one visible update).
- **No late layout shifts:** Reply previews / rich data are either (a) loaded with the message, or (b) applied before the first paint so the first frame already has correct heights. They avoid a second layout pass that adds reply previews after the list is already on screen.

---

## 2. Root Causes of Our Jumpiness

| # | Cause | Effect |
|---|--------|--------|
| 1 | **Multiple `messages` publishes in one load** | `loadMessages()` does: (1) `messages = local`, (2) `messages = merged` (network). View re-renders twice. |
| 2 | **Reply context hydration runs async** | `scheduleReplyContextHydration()` runs in a throttled `Task` and later does `messages = enriched`. Third publish; reply previews appear and **cell heights change** → visible jump. |
| 3 | **Repository publisher fires after our own sync** | `loadMessages()` starts `Task { refreshMessagesInBackground() }`. When `syncMessages()` does `modelContext.save()`, `NSManagedObjectContextDidSave` fires → `getMessagesPublisher` emits → VM sets `messages` again. Fourth publish (or third, racing with hydration). |
| 4 | **Thread: seed then replace** | `MessageThreadView` sets `replies` from seed, then replaces with network fetch. Two list updates; if order/count differ, list jumps. |
| 5 | **Thread: mergeReplies on every parent update** | `onReceive(conversationViewModel.$messages)` calls `mergeReplies(from:)`. Parent VM publishes 2–4 times on load → thread gets 2–4 mergeReplies calls → thread list can jump repeatedly. |

---

## 3. Execution Plan (Minimal, No Bloat)

### 3.1 ConversationDetailViewModel — One “final” update after network + hydration

**File:** `NaarsCars/Features/Messaging/ViewModels/ConversationDetailViewModel.swift`

**Change:**

1. **Inline reply hydration after network merge (initial load only)**  
   After building `merged` from the network in `loadMessages()`:
   - If any message in `merged` has `replyToId != nil` and `replyToMessage == nil`, **await** reply context building and assign once:
     - `let hydrated = await Self.buildReplyContexts(from: merged)` (reuse existing static helper; no throttler for this path).
     - `self.messages = hydrated`.
   - Else: `self.messages = merged`.
   - **Do not** call `scheduleReplyContextHydration()` at the end of `loadMessages()` when we just performed this inline hydration (we still need `scheduleReplyContextHydration()` for other code paths: send, realtime, loadMore, and for when we don’t hydrate inline).

2. **When to call inline vs scheduled**  
   - In `loadMessages()`: after network merge, if there are messages needing reply context, call a small sync path that awaits `buildReplyContexts(from: merged)` and assigns; then skip calling `scheduleReplyContextHydration()` for this load.
   - Keep `scheduleReplyContextHydration()` calls everywhere else (after local assign, after loadMore, after send/realtime updates) so later-arriving messages still get hydrated.

**Result:** Initial load does at most **two** publishes: (1) local, (2) merged+hydrated. No third update from async hydration.

**Implementation detail:** Reuse `buildReplyContexts(from:)`; it is `nonisolated` and async. From `loadMessages()` (MainActor), use `let hydrated = await Self.buildReplyContexts(from: merged)` then `self.messages = hydrated`. No new public API; optionally add a private helper `hydrateReplyContextsIfNeeded(_ messages: [Message]) async -> [Message]` that returns `messages` unchanged if no reply-to messages need hydration, otherwise returns `await Self.buildReplyContexts(from: messages)`, to keep `loadMessages()` readable.

---

### 3.2 ConversationDetailViewModel — Defer background sync

**File:** `NaarsCars/Features/Messaging/ViewModels/ConversationDetailViewModel.swift`

**Change:** In `loadMessages()`, do **not** start `refreshMessagesInBackground()` immediately. Defer it so the initial UI is stable before the repository is written and the publisher fires.

- Replace:
  - `Task { [weak self] in await self?.refreshMessagesInBackground() }`
- With:
  - `Task { [weak self] in try? await Task.sleep(nanoseconds: 2_000_000_000); await self?.refreshMessagesInBackground() }`  
  (2 second delay; use a named constant if the project prefers.)

**Result:** The publisher does not fire right after load, avoiding an extra `messages` update and list re-render during the first 2 seconds.

**Trade-off:** SwiftData is updated 2 seconds later; acceptable for initial load. Realtime and send paths still write immediately.

---

### 3.3 MessageThreadViewModel — Single update for replies

**File:** `NaarsCars/Features/Messaging/Views/ConversationDetailView.swift` (MessageThreadViewModel and MessageThreadView)

**Change:**

1. **loadThread**  
   - Set `parentMessage` from seed (if available) for instant header.
   - Do **not** set `replies` from seed.
   - Set `replies = []` initially (or leave as-is if already empty).
   - After network fetch: set `parentMessage` (from fetch) and `replies = fetchedReplies` **once**.

   So the thread has at most two updates: (1) parent from seed + replies empty, (2) parent + replies from network. Replies list does not go seed → network (no mid-load list swap).

2. **mergeReplies debounce**  
   - `onReceive(conversationViewModel.$messages)` currently calls `mergeReplies(from: messages)` on every parent update. When the parent loads, that can be 2–4 rapid emissions.
   - Debounce: e.g. only apply merge after 150–200 ms of no new emission (simple timer or Combine `debounce`). So when the parent conversation loads and publishes multiple times, the thread applies one merged state after things settle.

**Result:** Thread list updates at most once (or twice: empty → network) and doesn’t jump on every parent publish.

**Implementation detail:** For debounce, use a `@State` or ViewModel-held task/timer: on each `onReceive`, cancel the previous “apply merge” task and schedule a new one for 150 ms later; when it fires, call `mergeReplies(from: currentMessages)`. Keep the API of `mergeReplies(from:)` unchanged.

---

### 3.4 Optional: Ignore repository publisher during initial load

**File:** `NaarsCars/Features/Messaging/ViewModels/ConversationDetailViewModel.swift`

**Change (optional, if 3.1 + 3.2 are not enough):** In the `getMessagesPublisher` sink, ignore emissions that occur within 1–2 seconds of the last time we set `messages` ourselves (e.g. track `lastMessagesAssignTime` and skip apply when `Date().timeIntervalSince(lastMessagesAssignTime) < 1.5`). This avoids the publisher overwriting our merged+hydrated list if `syncMessages` runs earlier than the 2s delay or from another path.

**Result:** Prevents one more possible source of duplicate update. Only add if testing still shows a late jump after 3.1 and 3.2.

---

## 4. What We Are Not Doing (No Bloat)

- No new types or managers for “load phases.”
- No UI changes: no skeleton screens, no new loading states.
- No changes to repository API or SwiftData model.
- No changes to ConversationDetailView layout or scroll (safeAreaInset / defaultScrollAnchor stay as-is).
- No refactor of realtime/send paths; only initial load and thread load are tuned.

---

## 5. Files to Touch

| File | Changes |
|------|--------|
| `ConversationDetailViewModel.swift` | Inline reply hydration after network merge in `loadMessages()`; defer `refreshMessagesInBackground()` by 2s; optional: ignore publisher for 1–2s after own assign. |
| `ConversationDetailView.swift` (MessageThreadView + MessageThreadViewModel) | `loadThread`: no seed replies, set replies once from network; debounce `mergeReplies` in `onReceive`. |

---

## 6. Testing Checklist

- [ ] Open conversation (with replies): list appears with reply previews, no second “pop” when previews appear.
- [ ] Open conversation (no replies): list appears once, no jump.
- [ ] Open thread from conversation: thread list appears without multiple jumps; at most one update from empty to loaded.
- [ ] Send message / receive realtime: reply context still hydrates (scheduleReplyContextHydration still used elsewhere).
- [ ] Load older messages (pagination): scroll position preserved; no new jumpiness.
- [ ] After 2+ seconds, background sync still runs (repository updated).

---

## 7. Order of Implementation

1. **3.2** Defer `refreshMessagesInBackground()` — quick win, no risk.
2. **3.1** Inline reply hydration in `loadMessages()` — main fix for main list jumpiness.
3. **3.3** Thread: single reply update + debounce mergeReplies — fixes thread jumpiness.
4. **3.4** Optional publisher guard — only if needed after testing.

This order keeps each step small and verifiable without bloating the messaging module.
