# Naars Cars Messaging Module — Full Review & Improvement Plan

> **Date:** February 5, 2026
> **Scope:** Complete messaging module review from User, UX/UI Designer, and Developer perspectives
> **Benchmark:** Apple iMessage (iOS 17+)

---

## Table of Contents

1. [Executive Summary](#executive-summary)
2. [User Perspective — Feature Gap Analysis](#user-perspective)
3. [UX/UI Designer Perspective — Interaction & Visual Review](#uxui-perspective)
4. [Developer Perspective — Architecture & Infrastructure Review](#developer-perspective)
5. [Database & Backend Review](#database-review)
6. [Prioritized Improvement Plan](#improvement-plan)

---

## 1. Executive Summary <a name="executive-summary"></a>

The Naars Cars messaging module is **feature-rich** — it includes reactions, message editing, unsend, inline replies, audio messages, location sharing, typing indicators, and read receipts. In many ways it exceeds iMessage's feature set. However, the **core chat experience** — scrolling, keyboard interaction, message rendering performance, and real-time reliability — has significant gaps that make it feel noticeably less polished than iMessage.

### Top-Level Findings

| Category | Grade | Summary |
|----------|-------|---------|
| Feature Completeness | **B+** | Most iMessage features present; exceeds in reactions, editing, search |
| Scroll & Keyboard UX | **D** | Pagination jumps, keyboard handling broken, unreliable bottom detection |
| Visual Polish | **B** | Good design system, but missing animations and micro-interactions |
| Real-time Reliability | **C-** | Unfiltered global subscription, no guaranteed delivery, missing retry |
| Data Architecture | **C** | Optimistic UI exists but incomplete; offline support has gaps |
| Database Design | **B-** | Functional schema; missing critical indexes and conflicting RLS |
| Push Notifications | **B** | Working with quick reply; missing rich previews and thread grouping |

---

## 2. User Perspective — Feature Gap Analysis <a name="user-perspective"></a>

### What Works Well (User Would Notice)
- Warm, distinctive brand color (terracotta) differentiates from iMessage blue
- Reactions (6 emoji options) with detail sheet showing who reacted
- Message editing and unsend with 15-minute window
- Inline reply threading with visual spine connector
- Audio messages with waveform visualization
- Location sharing with map snapshot preview
- In-conversation and global message search
- Media gallery per conversation (Photos / Audio / Links tabs)
- Swipe-to-reply on message bubbles
- Quick reply from push notification banner
- Failed message indicator with tap-to-retry
- Skeleton loading states for initial load

### What Feels Worse Than iMessage (User Would Notice)

#### Critical UX Gaps

| Issue | iMessage Behavior | Naars Cars Behavior | Impact |
|-------|------------------|---------------------|--------|
| **Loading older messages** | Scroll position preserved; messages appear above seamlessly | Scroll jumps when older messages are inserted at top | **Jarring** — user loses their place in conversation |
| **Keyboard opens** | Content adjusts upward; user stays at same position in conversation | `@FocusState` never connected to TextField — keyboard-aware scrolling is **completely broken** | **Frustrating** — messages may be hidden behind keyboard |
| **Keyboard closes** | Content adjusts back down smoothly | No handling for keyboard dismissal scroll adjustment | Disorienting |
| **Return key in message** | Inserts newline | Sends the message | **Wrong behavior** — users can't compose multi-line messages via keyboard |
| **"Am I at the bottom?"** | Always accurate; new messages auto-scroll to bottom | Uses 1pt spacer with onAppear/onDisappear — unreliable; can miss new messages | Messages arrive but user doesn't see them |
| **Swipe-to-reply** | Smooth, doesn't conflict with scrolling | Conflicts with ScrollView vertical gesture; diagonal swipes can trigger accidentally | Frustrating false triggers |

#### Missing Features Users Would Expect

| Feature | iMessage | Naars Cars | Notes |
|---------|----------|-----------|-------|
| **Delivery timestamps** | "Delivered 2:34 PM" / "Read 2:36 PM" | Checkmark icons only, no timestamps | Users can't tell *when* message was read |
| **Send animation** | Bubble "shoots up" from input bar | Instant appearance, no animation | Feels static |
| **Long-press preview** | Blurred background + elevated message + reaction bar | Straight to context menu | Less visually polished |
| **Message effects** | Slam, Loud, Gentle, Invisible Ink, etc. | Not supported | Fun feature gap |
| **Link previews** | Rich OG previews with image/title/description | Basic URL detection; `LPMetadataProvider` used but no metadata stored server-side | Previews re-fetch every time |
| **Contact sharing** | vCard attachment | Not supported | |
| **File attachments** | Documents, PDFs, etc. | Only images and audio | |
| **Search highlighting** | Persistent highlight on search result | Temporary 1.5s pulse, then fades | Hard to find the result |
| **Notification grouping** | Grouped by conversation thread | Individual notifications | Clutters notification center |

---

## 3. UX/UI Designer Perspective — Interaction & Visual Review <a name="uxui-perspective"></a>

### 3.1 Scrolling & Pagination

**Current Implementation:**
```
ScrollView → LazyVStack → ForEach(Array(messages.enumerated()))
```

**Problems:**

1. **Scroll position loss on pagination** — When `loadMoreMessages()` inserts messages at `index 0`, SwiftUI's LazyVStack recalculates layout and jumps. The user's visual position is not preserved. This is the **single biggest UX issue**.

2. **Bottom detection is unreliable** — A 1pt spacer with `onAppear`/`onDisappear` is used to detect if user is at bottom. LazyVStack may delay `onDisappear` callbacks, causing false positives. The scroll-to-bottom FAB and auto-scroll on new messages depend on this being accurate.

3. **`ForEach(Array(viewModel.messages.enumerated()))`** — Creates a new enumerated array on every render. For 500+ messages, this is O(n) allocation per frame.

**iMessage Approach:**
- Uses UIKit's `UICollectionView` with `UICollectionViewCompositionalLayout` in a reversed/inverted configuration
- Content inset adjustments maintain scroll position during pagination
- `prefetchDataSource` for efficient pagination triggering
- Precise scroll position tracking via `contentOffset`

**Recommended Fix:**
- Use a **reversed ScrollView** pattern (`.rotationEffect(.degrees(180))` on both ScrollView and each row) OR
- Use a `UIViewRepresentable` wrapping `UICollectionView` for production-grade scroll behavior
- Replace `onAppear`/`onDisappear` bottom detection with `ScrollView` position tracking (iOS 17+ `ScrollPosition` API or `GeometryReader` + `PreferenceKey`)

### 3.2 Keyboard Interaction

**Current Implementation:**
- `@FocusState private var isInputFocused: Bool` is declared but **never bound** to the MessageInputBar's TextField
- When focus changes to `true` (which never happens), it scrolls to bottom after 100ms delay
- `.scrollDismissesKeyboard(.interactively)` is correctly applied

**Problems:**
1. `isInputFocused` is never set to `true` because `MessageInputBar` doesn't accept a `FocusState` binding — **keyboard-aware scrolling is completely non-functional**
2. The 100ms delay is a race condition with the keyboard animation (~250-300ms)
3. Force-scrolling to bottom when keyboard opens is wrong behavior — if user is reading older messages and taps the input, they should stay in position
4. No adjustment when keyboard closes

**iMessage Approach:**
- Uses `UIScrollView.keyboardDismissMode = .interactive`
- Adjusts `contentInset.bottom` to match keyboard height
- Maintains scroll position relative to content, not to bottom
- Smooth animated transitions coordinated with keyboard

**Recommended Fix:**
- Pass `@FocusState` binding through to `MessageInputBar`'s TextField
- Use `KeyboardReadable` publisher or `UIResponder.keyboardWillShowNotification` to get keyboard height
- Adjust ScrollView bottom padding to match keyboard height (not force-scroll to bottom)
- Animate padding change in sync with keyboard animation curve

### 3.3 Message Bubble Design

**What's Good:**
- `BubbleShape` with quadratic bezier tail is clean and iMessage-like
- Series grouping (same sender within 5 min) controls tail visibility, avatar, and name display
- Terracotta brand color is distinctive and warm
- Dark mode fully supported via dynamic color providers

**What Needs Work:**

| Aspect | Current | Recommended |
|--------|---------|-------------|
| Max bubble width | 70% of screen | 75-80% (matches iMessage) |
| Screen width calculation | `UIScreen.main.bounds.width` (deprecated iOS 16+) | `GeometryReader` |
| Series time threshold | 5 minutes | 1 minute (matches iMessage) |
| Bubble tail shape | Quadratic bezier | SuperEllipse for smoother curve |
| Entrance animation | Scale + slide on ALL new messages (including paginated) | Only animate truly new messages (sent/received in real-time) |
| Link detection | `NSDataDetector` on every render | Cache detection results on `Message` model |

### 3.4 Input Bar

**What's Good:**
- Multi-line expansion (1-5 lines)
- Attachment menu (Photo, Location)
- Audio recording with duration display
- Reply/Edit context banners
- Send button color matches brand

**What Needs Work:**

| Issue | Impact | Fix |
|-------|--------|-----|
| Return key sends message | Users can't write multi-paragraph messages | Remove `.onSubmit` handler; send only via button |
| No maximum audio recording duration | Users could accidentally record huge files | Cap at 2-3 minutes like iMessage |
| Audio timer uses `Timer.scheduledTimer` | Can leak if view dismissed while recording | Use Combine `Timer.publish` |
| No send button animation | Feels static compared to iMessage's scale pulse | Add `.scaleEffect` animation on tap |
| No "Edit message..." placeholder | User doesn't know they're in edit mode from text field alone | Change placeholder text when `editingMessage != nil` |
| Missing FocusState binding | Keyboard handling doesn't work | Add `FocusState<Bool>` parameter |

### 3.5 Reaction Picker

**Current:** Centered on screen with `padding(.bottom, 100)` hardcoded.

**iMessage:** Positioned directly above/below the long-pressed message bubble with a blurred backdrop.

**Recommended:**
- Anchor reaction picker to the message bubble's frame using `GeometryReader`
- Add blurred/dimmed overlay behind the picker
- Remove the competing `onLongPressGesture` (context menu already handles long press)

### 3.6 Conversations List

**What's Good:**
- Pinned conversations section
- Search with debounce
- Swipe actions (delete, pin, mute)
- Pull-to-refresh
- Skeleton loading

**What Needs Work:**

| Issue | Impact |
|-------|--------|
| Pinned/muted state stored in UserDefaults without user ID | Wrong user inherits another user's pins/mutes |
| `findExistingGroupConversation` makes O(n) network requests | Sluggish new-conversation flow |
| No real-time inbox updates | New messages don't update last-message preview until refresh |
| Fade gradient uses hardcoded background color | Breaks in dark mode or themed backgrounds |

### 3.7 Accessibility

**What's Good:**
- `accessibilityIdentifier` on interactive elements
- `accessibilityLabel` on avatars, reactions, images
- `accessibilityHint` on input field, failed messages
- Dynamic Type support via system fonts
- 44pt minimum touch targets on reaction buttons

**What's Missing:**
- No VoiceOver announcements for incoming messages
- No `AccessibilityFocusState` management
- Swipe-to-reply has no VoiceOver alternative (context menu compensates)
- Audio waveform has no accessibility representation

---

## 4. Developer Perspective — Architecture & Infrastructure Review <a name="developer-perspective"></a>

### 4.1 Real-Time Message Pipeline

**Current Flow:**
```
Supabase Postgres → Realtime WebSocket → RealtimeManager → MessagingSyncEngine
→ MessagingMapper.parseMessageFromPayload → MessagingRepository.upsertMessage
→ SwiftData → NotificationCenter → ViewModel → View
```

**Critical Issues:**

1. **SECURITY/PERFORMANCE: Unfiltered global subscription** — `MessagingSyncEngine` subscribes to `public:messages` which receives **ALL messages for ALL users**. Every insert, update, and delete in the entire messages table triggers processing on every connected client.
   - **Impact:** Massive bandwidth waste, battery drain, CPU usage, privacy concerns
   - **Fix:** Use Supabase RLS-aware subscriptions or filter by user's conversation IDs

2. **No guaranteed delivery** — If WebSocket disconnects momentarily, messages are lost until next `syncMessages` call. No message acknowledgment or catch-up mechanism.
   - **Fix:** Track last-received message timestamp; on reconnect, fetch all messages since that timestamp

3. **Delete events handled incorrectly** — Delete events use the same `handleIncomingMessage` path as inserts/updates, but delete payloads typically contain only the primary key. `parseMessageFromPayload` will fail or produce incomplete data.
   - **Fix:** Separate handler for delete events that removes the local message by ID

### 4.2 Offline Support & Message Sync

**Current State:** Partially implemented with significant gaps.

| Component | Status | Issue |
|-----------|--------|-------|
| Optimistic message sending | Implemented | Failed messages never retried; `retryPendingMessages()` is a **stub** |
| SwiftData persistence | Implemented | `editedAt`/`deletedAt` not mapped; sender profile not persisted |
| Incremental sync | Not implemented | `latestTimestamp` is calculated but **never used**; always fetches last 25 |
| Offline reading | Partial | Reactions and reply contexts not persisted |
| Conversation pruning | Dangerous | Deletes any local conversation not in current remote page |

### 4.3 Message Service Issues

| Issue | Location | Description |
|-------|----------|-------------|
| Dead retry logic | `MessageService.swift:370-381` | Catch block retries same decode on same data — always re-throws |
| Duplicate participant check | `MessageService.swift:48-76, 317-338` | Same verification logic duplicated across `fetchMessages` and `sendMessage` |
| N+1 pagination query | `MessageService.swift:83-106` | Extra round-trip to look up cursor timestamp |
| Search without escaping | `MessageService.swift:730` | `ilike "%\(query)%"` doesn't escape `%` and `_` in user input |
| Typing indicator clock skew | `MessageService.swift:818` | Compares server `started_at` against client `Date()` |

### 4.4 View Model Issues

| Issue | Location | Description |
|-------|----------|-------------|
| `messageText` cleared twice | `ConversationDetailView:139` + `VM:236` | Harmless but indicates unclear state ownership |
| Fragile optimistic matching | `VM:300-308` | Falls back to text + sender + 5s window — same text sent twice = wrong match |
| `unreadCount` computed on every access | `VM:64-68` | Iterates entire messages array; should be `@Published` |
| `currentOffset` not reset on refresh | `ConversationsListVM:270` | Pagination breaks after pull-to-refresh |
| Sequential profile hydration | `ConversationsListVM:196-228` | 30+ sequential network requests; should use `TaskGroup` |
| Wasteful conversation lookup | `ConversationDetailView:850` | Fetches 100 conversations to find one by ID |

### 4.5 Component Issues

| Issue | Location | Description |
|-------|----------|-------------|
| Gesture conflict | `MessageBubble:504-577` | `contextMenu` + `onLongPressGesture` on same view — context menu wins |
| Swipe conflicts with scroll | `MessageBubble:462-496` | `DragGesture` with 20pt minimum interferes with vertical scrolling |
| `UIScreen.main` deprecated | `MessageBubble:69` | Use `GeometryReader` instead |
| System message English-only | `MessageBubble:92-101` | String matching for system messages won't work in other languages |
| `NSDataDetector` per render | `MessageBubble:80-87` | Expensive URL detection runs on every SwiftUI body evaluation |
| Hardcoded waveform | `MessageBubble:68` | All audio messages show identical waveform |
| Entrance animation on pagination | `MessageBubble:183-196` | Scale+slide plays for paginated messages, not just new ones |

### 4.6 Badge Count & Push Notifications

**Dual badge computation paths:**
1. `BadgeCountManager` uses server RPC `get_badge_counts`
2. `PushNotificationService.updateBadgeCount()` manually queries conversations + notifications

These can produce **different results**. One should be canonical.

**Other push issues:**
- Token registration uses SELECT + INSERT/UPDATE (race condition) — should use UPSERT
- 10-second polling when realtime is connected is too aggressive — should be 60-120s
- No notification service extension for rich previews
- No thread identifier for conversation-grouped notifications
- No silent push for background sync

### 4.7 Network & Retry Layer

| Issue | Description |
|-------|-------------|
| No jitter in backoff | Pure exponential (1s, 2s, 4s...) causes thundering herd |
| Error detection is locale-dependent | `localizedDescription.contains("timeout")` fails in non-English locales |
| HTTP error domain mismatch | Checks `"HTTPError"` domain which Supabase SDK may not use |
| `RequestDeduplicator` type mismatch | Same key used for different return types silently bypasses dedup |
| No in-flight TTL | Hung request blocks all subsequent requests for same key forever |

---

## 5. Database & Backend Review <a name="database-review"></a>

### 5.1 Schema Summary

| Table | Purpose | Status |
|-------|---------|--------|
| `conversations` | Conversation metadata (title, image, archive) | Good |
| `conversation_participants` | Membership (user_id, last_seen, left_at) | **RLS DISABLED** |
| `messages` | Message content, read receipts, media URLs | Good, but `read_by` array doesn't scale |
| `message_reactions` | Emoji reactions (6 types, 1 per user) | Good, but not in realtime publication |
| `typing_indicators` | Real-time typing state (auto-cleanup >10s) | Good |
| `blocked_users` | Bidirectional blocking | Good |
| `reports` | Message/user reporting | Good |

### 5.2 Critical Database Issues

#### 5.2.1 Missing GIN Index on `read_by`

The `read_by UUID[]` column is queried with the `@>` (array contains) operator for:
- Badge count computation (`get_badge_counts` RPC)
- Unread message filtering
- Push notification badge calculation

**Without a GIN index, every one of these queries does a sequential scan on the entire messages table.**

```sql
-- MUST ADD:
CREATE INDEX idx_messages_read_by ON messages USING GIN(read_by);
```

#### 5.2.2 Conflicting RLS Policies on `messages` UPDATE

Multiple migrations create overlapping UPDATE policies:
- `081/20260126_0007`: `messages_update_for_participants` — any participant can update any field
- `20260205_0001`: `messages_update_own` — only sender can update (for edit/unsend)

The active policy depends on **migration execution order**. If `messages_update_own` is the last to run, non-senders **cannot mark messages as read** via direct UPDATE (must use the `SECURITY DEFINER` RPC instead). These need to be consolidated into clear, non-conflicting policies:

```sql
-- Policy for read receipts (any participant can update read_by):
CREATE POLICY "messages_update_read_by" ON messages FOR UPDATE
  USING (EXISTS (SELECT 1 FROM conversation_participants WHERE conversation_id = messages.conversation_id AND user_id = auth.uid() AND left_at IS NULL))
  WITH CHECK (true);  -- Consider column-level restriction

-- Policy for edit/unsend (only sender):
CREATE POLICY "messages_update_own_content" ON messages FOR UPDATE
  USING (from_id = auth.uid())
  WITH CHECK (from_id = auth.uid());
```

#### 5.2.3 `conversation_participants` RLS Disabled

Security is enforced only at the iOS application level. Any authenticated user with direct Supabase access could:
- Add themselves to any conversation
- Read all conversation memberships
- Remove other users from conversations

**Recommendation:** Re-enable RLS with policies that avoid the recursion problem, or add a security-definer function layer.

#### 5.2.4 `REPLICA IDENTITY FULL` on Messages

Every `read_by` update (which happens for every message read by every user) broadcasts the **entire message row** — including text content — over realtime to all subscribers. This is expensive and unnecessary.

**Recommendation:** Use a separate `message_reads` table for read receipt tracking, with `REPLICA IDENTITY DEFAULT` on messages.

### 5.3 Missing Database Features

| Feature | iMessage Equivalent | Recommendation |
|---------|-------------------|----------------|
| **Delivery status tracking** | `delivered_at` per recipient | Add `message_delivery_status` table or `delivered_at` column |
| **Read timestamps** | "Read 2:34 PM" per recipient | Replace `read_by UUID[]` with `message_reads(message_id, user_id, read_at)` table |
| **Full-text search** | Spotlight integration | Add `tsvector` column with GIN index on `messages.text` |
| **Multiple reactions per user** | Tapback (one per user) | Consider relaxing UNIQUE constraint to UNIQUE(message_id, user_id, reaction) |
| **Link preview metadata** | OG title/description/image cached | Add `link_title`, `link_description`, `link_image_url` columns |
| **Mute per conversation** | Mute/unmute conversation | Add `is_muted` to `conversation_participants` (currently UserDefaults only!) |
| **Conversation notification settings** | Focus filters, mention-only | Add notification preference columns |
| **Realtime reactions** | Instant tapback appearance | Add `message_reactions` to realtime publication |

### 5.4 Index Optimization

**Duplicate indexes to clean up:**
- `idx_messages_conv_created` (ASC) overlaps with `idx_messages_conversation_created` (DESC) and `idx_messages_conversation_id_created_at` (DESC) — keep only the DESC variant

**Missing indexes to add:**
```sql
-- Critical for badge counts:
CREATE INDEX idx_messages_read_by ON messages USING GIN(read_by);

-- For participant lookups with active filter:
CREATE INDEX idx_conv_participants_user_active ON conversation_participants(user_id, conversation_id) WHERE left_at IS NULL;

-- For full-text search (if implemented):
ALTER TABLE messages ADD COLUMN text_search tsvector GENERATED ALWAYS AS (to_tsvector('english', COALESCE(text, ''))) STORED;
CREATE INDEX idx_messages_text_search ON messages USING GIN(text_search);
```

### 5.5 Edge Function Issues

| Issue | Location | Impact |
|-------|----------|--------|
| `send-message-push` doesn't clean stale APNs tokens | Lines 455-458 | Dead tokens accumulate; wasted push attempts |
| APNs JWT created per push | `createAPNsJWT()` | ~100ms overhead per push; should cache for 50 min |
| Badge count query scans all messages | Lines 361-374 | Slow at scale without GIN index on `read_by` |
| No push debouncing | Entire function | Rapid messages = rapid pushes; should batch |
| `priority: 10` inside `aps` payload | Line 30 | Harmless but incorrect; priority is HTTP header only |
| Duplicate "active viewing" check | Trigger + edge function | Extra latency; 60s threshold too generous |

---

## 6. Prioritized Improvement Plan <a name="improvement-plan"></a>

### Phase 1: Critical UX Fixes (Week 1-2)
*Fix the core chat experience to match iMessage's baseline quality.*

| # | Task | Priority | Effort | Impact |
|---|------|----------|--------|--------|
| 1.1 | **Fix scroll position on pagination** — Implement reversed scroll pattern or UICollectionView wrapper | P0 | High | Eliminates the most jarring UX issue |
| 1.2 | **Connect `@FocusState` to MessageInputBar** — Pass binding through, adjust scroll for keyboard height (not force-to-bottom) | P0 | Medium | Fixes completely broken keyboard handling |
| 1.3 | **Fix Return key behavior** — Remove `.onSubmit` handler; Return inserts newline, Send button sends | P0 | Low | Fixes incorrect multi-line input |
| 1.4 | **Fix bottom detection** — Replace 1pt spacer with `ScrollPosition` API (iOS 17+) or `GeometryReader` + `PreferenceKey` | P0 | Medium | Reliable auto-scroll on new messages |
| 1.5 | **Fix swipe-to-reply gesture conflict** — Add `simultaneousGesture` coordination or switch to UIKit gesture recognizer delegation | P1 | Medium | Prevents accidental swipe triggers |
| 1.6 | **Remove `onLongPressGesture` on bubbles** — Context menu already provides "React" option; long press should trigger context menu only | P1 | Low | Eliminates gesture conflict |

### Phase 2: Real-Time Reliability (Week 2-3)
*Ensure messages are delivered reliably in real-time.*

| # | Task | Priority | Effort | Impact |
|---|------|----------|--------|--------|
| 2.1 | **Filter realtime subscription** — Subscribe only to user's conversation IDs, not `public:messages` | P0 | Medium | Security fix; reduces bandwidth 99%+ |
| 2.2 | **Implement reconnection catch-up** — On WebSocket reconnect, fetch messages since last-received timestamp | P0 | Medium | Prevents message loss during brief disconnects |
| 2.3 | **Implement `retryPendingMessages()`** — Replace stub with exponential backoff retry queue | P0 | Medium | Failed messages actually get sent |
| 2.4 | **Fix delete event handling** — Separate handler that removes local message by ID | P1 | Low | Correct handling of unsent/deleted messages |
| 2.5 | **Add realtime inbox updates** — Subscribe to conversations table changes for live last-message preview | P1 | Medium | Inbox stays current without manual refresh |

### Phase 3: Data Layer Fixes (Week 3-4)
*Fix the persistence and sync layer for offline reliability.*

| # | Task | Priority | Effort | Impact |
|---|------|----------|--------|--------|
| 3.1 | **Add GIN index on `messages.read_by`** — Single migration | P0 | Low | Massive query performance improvement |
| 3.2 | **Consolidate RLS policies on `messages`** — Single coherent policy set | P0 | Medium | Eliminates security ambiguity |
| 3.3 | **Map `editedAt`/`deletedAt` in MessagingMapper** — Add to both `mapToSDMessage` and `mapToMessage` | P1 | Low | Edited/unsent state preserved offline |
| 3.4 | **Implement incremental sync** — Use `latestTimestamp` (already calculated) as cursor | P1 | Medium | Efficient sync, catches missed messages |
| 3.5 | **Fix conversation pruning** — Don't delete local conversations missing from paginated remote response | P1 | Low | Prevents data loss |
| 3.6 | **Reset `currentOffset` on refresh** — In `ConversationsListViewModel.refreshConversations()` | P1 | Low | Fixes pagination after pull-to-refresh |
| 3.7 | **Add `message_reactions` to realtime publication** — Database migration | P2 | Low | Reactions appear in real-time |

### Phase 4: Visual Polish (Week 4-5)
*Close the micro-interaction gap with iMessage.*

| # | Task | Priority | Effort | Impact |
|---|------|----------|--------|--------|
| 4.1 | **Add send animation** — Bubble scale + slide-up from input bar | P2 | Medium | Feels more alive and responsive |
| 4.2 | **Anchor reaction picker to message** — Use `GeometryReader` to position above/below tapped bubble | P2 | Medium | Matches iMessage UX pattern |
| 4.3 | **Add delivery/read timestamps** — "Delivered 2:34 PM" / "Read 2:36 PM" on last message | P2 | Medium | Users know when messages were read |
| 4.4 | **Fix entrance animation** — Only animate truly new messages (sent/received), not paginated ones | P2 | Low | Prevents animation spam during scroll-up |
| 4.5 | **Cache `NSDataDetector` results** — Compute URL detection once and store on `Message` model | P2 | Low | Performance improvement on re-renders |
| 4.6 | **Replace `UIScreen.main`** — Use `GeometryReader` for bubble max width | P2 | Low | Future-proofs for multi-window |
| 4.7 | **Increase bubble max width to 75-80%** — Match iMessage proportions | P3 | Low | Slightly better text layout |
| 4.8 | **Reduce series threshold to 1 minute** — Match iMessage grouping | P3 | Low | More frequent timestamp visibility |

### Phase 5: Backend & Push Optimization (Week 5-6)
*Optimize server-side performance and push notifications.*

| # | Task | Priority | Effort | Impact |
|---|------|----------|--------|--------|
| 5.1 | **Add stale APNs token cleanup to `send-message-push`** — Handle HTTP 410 like `send-notification` does | P1 | Low | Reduces wasted push attempts |
| 5.2 | **Cache APNs JWT** — Cache for 50 minutes instead of recreating per push | P1 | Low | Reduces push latency ~100ms |
| 5.3 | **Reduce badge polling to 60s** — When realtime is connected, 10s is too aggressive | P1 | Low | Reduces server load significantly |
| 5.4 | **Remove duplicate `updateBadgeCount` from PushNotificationService** — Use `BadgeCountManager` as single source | P2 | Low | Consistent badge numbers |
| 5.5 | **Add push debouncing** — Batch rapid-fire messages into single notification | P2 | Medium | Better notification UX |
| 5.6 | **Add thread identifier to push payloads** — Group notifications by conversation | P2 | Low | Cleaner notification center |
| 5.7 | **Fix token registration race condition** — Use PostgreSQL UPSERT | P2 | Low | Prevents duplicate token entries |

### Phase 6: Advanced Features (Week 6-8)
*Enhance beyond iMessage baseline.*

| # | Task | Priority | Effort | Impact |
|---|------|----------|--------|--------|
| 6.1 | **Move pin/mute to server** — Add `is_muted`/`is_pinned` columns to `conversation_participants` | P2 | Medium | Persists across devices, per-user |
| 6.2 | **Full-text search** — Add `tsvector` column + GIN index on `messages.text` | P2 | Medium | Fast search at scale |
| 6.3 | **Link preview metadata storage** — Add columns for OG title/description/image | P2 | Medium | Previews don't re-fetch |
| 6.4 | **Read receipt timestamps** — Migrate from `read_by UUID[]` to `message_reads` table | P3 | High | Scalable; enables "Read at..." |
| 6.5 | **Separate read tracking from REPLICA IDENTITY** — New `message_reads` table with DEFAULT identity | P3 | High | Reduces realtime bandwidth |
| 6.6 | **Add group admin/permissions** — Only creator can remove members | P3 | Medium | Prevents unauthorized removals |
| 6.7 | **Parallel profile hydration** — Replace sequential loops with `TaskGroup` | P2 | Medium | Faster list loading |
| 6.8 | **Add jitter to NetworkRetryHelper** — `delay * Double.random(in: 0.5...1.5)` | P3 | Low | Prevents thundering herd |
| 6.9 | **System message localization** — Use localization keys instead of English string matching | P2 | Medium | Correct behavior in all languages |
| 6.10 | **Real audio waveform generation** — Generate from audio data instead of hardcoded array | P3 | Medium | Each audio message looks unique |

### Phase 7: Nice-to-Have (Future)

| # | Task | Notes |
|---|------|-------|
| 7.1 | Notification service extension for rich previews | Shows sender avatar + message preview in notification |
| 7.2 | Communication notifications framework integration | Shows contact photos, integrates with Focus modes |
| 7.3 | File/document attachment support | PDF, document sharing |
| 7.4 | Contact card (vCard) messages | Share contacts inline |
| 7.5 | Message effects (slam, gentle, etc.) | Fun feature for engagement |
| 7.6 | Silent push for background sync | Keeps data fresh without user interaction |
| 7.7 | End-to-end encryption | Privacy/security feature |
| 7.8 | Pinned messages within conversation | Pin important messages to top |

---

## Appendix: Quick Reference — Files Changed Per Phase

### Phase 1 (Critical UX)
- `NaarsCars/Features/Messaging/Views/ConversationDetailView.swift`
- `NaarsCars/UI/Components/Messaging/MessageInputBar.swift`
- `NaarsCars/UI/Components/Messaging/MessageBubble.swift`

### Phase 2 (Real-Time)
- `NaarsCars/Core/Storage/MessagingSyncEngine.swift`
- `NaarsCars/Core/Services/RealtimeManager.swift`
- `NaarsCars/Core/Storage/MessagingRepository.swift`
- `NaarsCars/Features/Messaging/ViewModels/ConversationsListViewModel.swift`

### Phase 3 (Data Layer)
- New SQL migration for GIN index + RLS consolidation
- `NaarsCars/Core/Storage/MessagingMapper.swift`
- `NaarsCars/Core/Storage/MessagingRepository.swift`
- `NaarsCars/Features/Messaging/ViewModels/ConversationsListViewModel.swift`

### Phase 4 (Visual Polish)
- `NaarsCars/UI/Components/Messaging/MessageBubble.swift`
- `NaarsCars/Features/Messaging/Views/ConversationDetailView.swift`
- `NaarsCars/Core/Models/Message.swift`

### Phase 5 (Backend)
- `supabase/functions/send-message-push/index.ts`
- `NaarsCars/Core/Services/BadgeCountManager.swift`
- `NaarsCars/Core/Services/PushNotificationService.swift`

### Phase 6 (Advanced)
- New SQL migration for `message_reads` table, full-text search, link metadata
- `NaarsCars/Core/Services/MessageService.swift`
- `NaarsCars/Core/Services/NetworkRetryHelper.swift`
- `NaarsCars/Features/Messaging/Views/MessageDetailsPopup.swift`
- Multiple ViewModels for `TaskGroup` parallelization
