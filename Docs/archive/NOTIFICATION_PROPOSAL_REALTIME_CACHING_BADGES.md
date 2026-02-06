## Product Requirements: Realtime + Caching Strategy for Trustworthy Badges (Social-App Style)

### 1) Overview
Badges are a trust contract: if users can’t rely on them, they stop paying attention (or they keep reopening the app “just to clear the red dot”).

This PRD defines a “social-app style” model (Instagram/Facebook-like in spirit) for badge correctness:
- **Server is the source of truth** for unread counts.
- **Realtime provides speed**, but is not trusted alone.
- **Foreground reconciliation** (and occasional lightweight refresh) prevents drift from missed realtime events, caching, multi-device reads, or intermittent connectivity.

This PRD applies to:
- Messages tab badge (sum of unread across conversations)
- Requests tab badge (request-scoped unseen activity)
- Bell badge (non-message notification unseen activity; see Notifications Surface PRD)

---

### 2) Problem statement (why we need this)
The current codebase contains multiple “drift vectors”:
- **Caching can return stale state**:
  - `NotificationService.fetchNotifications(...)` returns cached notifications unless `forceRefresh` is true.
  - `MessageService.fetchConversations(...)` returns cached conversations if present, regardless of pagination parameters (limit/offset).
- **Badge refresh is lifecycle-driven, not event-driven**:
  - `BadgeCountManager` refreshes on app active and on explicit refresh calls.
  - Realtime message inserts refresh badge counts, but there is no equivalent realtime mechanism for request-based notifications or bell feed updates.
- **Multi-device reads can drift**:
  - If messages are read on Device A, Device B only updates when it refreshes counts (foreground, manual refresh), and caches can still mask the truth.

---

### 3) Goals
- **G1: Badge correctness**
  - Badge counts are accurate across lifecycle events (launch, background/foreground, tab switches).
  - Badge counts converge after connectivity loss.
  - Badge counts converge across multiple devices.
- **G2: Low-latency UX**
  - When realtime is connected, UI updates within ~1–2s for new events.
- **G3: Predictable sources of truth**
  - Engineering can answer “where does this badge number come from?” in one sentence.
- **G4: Minimal network overhead**
  - Reconciliation calls are lightweight and rate-limited.

---

### 4) Non-goals
- **NG1**: Building a full-blown analytics or experimentation platform.
- **NG2**: Guaranteeing <200ms delivery for non-message notifications (messages have separate constraints).

---

### 5) Definitions
- **Server-authoritative count**: A number computed by the backend that represents current unread/unseen items for a user/category.
- **Realtime event**: An event delivered to the client via Supabase Realtime (or similar) indicating a change occurred (new message, notification inserted, read state updated).
- **Reconciliation**: A lightweight “ask the server for the truth” refresh used to correct drift.
- **Drift**: Client UI badge count differs from server truth due to missed events, caching, or delayed updates.

---

### 6) Current codebase reality (for engineering context)
What we already have:
- Messages list is already updated via realtime (`ConversationsListViewModel` subscribes to `messages` inserts).
- Thread view marks read on entry (`ConversationDetailViewModel.loadMessages()` calls `updateLastSeen` then `markAsRead`).
- `BadgeCountManager.refreshAllBadges()` recomputes counts by:
  - Requests: fetch notifications (force refresh) and count unread request-related types
  - Messages: fetch conversations and sum unreadCount
  - Community: fetch notifications (force refresh) and count unread community types

What we do not have:
- A server-authoritative “counts endpoint” that returns all badge counts in one call (or a stable set of calls).
- A unified “counts state” that is independent from cached lists and pagination.

---

### 7) Product requirements: Badge correctness model
#### 7.1 Single-source counts (server truth)
- **R-COUNTS-1**: The app must be able to fetch server-authoritative counts for:
  - total unread messages (sum across conversations)
  - request-based unseen activity (per chosen model in Requests PRD)
  - non-message notification unseen count (bell)
- **R-COUNTS-2**: These counts are the “truth” used to render badges, regardless of cached lists.
- **R-COUNTS-3**: Conversation-level unread counts displayed in the conversation list must either:
  - come from server-authoritative per-conversation counts, or
  - be reconciled against server totals in a way that cannot diverge for long.

#### 7.2 Realtime updates as fast-path (not truth)
- **R-RT-1**: When a new message arrives and realtime is connected:
  - Update the relevant conversation row immediately (preview + ordering).
  - Optimistically increment the unread count for that conversation (if recipient).
  - Optimistically increment the messages badge.
- **R-RT-2**: When the user reads messages (thread view), optimistically decrement counts after the “mark read” action is executed.
- **R-RT-3**: All optimistic updates must be reconciled against server truth at defined times.

#### 7.3 Foreground reconciliation (“catch up”)
- **R-RECON-1**: On app foreground (or didBecomeActive), fetch server-authoritative counts and overwrite badge state.
- **R-RECON-2**: On tab switches into Messages/Requests/Bell, the app may optionally reconcile counts if last sync is older than a threshold (e.g., 15–30 seconds).
- **R-RECON-3**: After any “mark read/seen” action, reconcile counts to confirm convergence and prevent phantom badges.

#### 7.3.1 Periodic reconciliation while app is active (locked)
- **R-RECON-4**: While the app is active (foreground), perform periodic reconciliation (polling) to converge badge counts even if realtime events are missed.
- **R-RECON-5**: The polling interval **P seconds** must be explicitly defined (see “Open product constants” below) to remove ambiguity for implementation.

#### 7.4 Cache policy (what is safe to cache)
- **R-CACHE-1**: Conversation metadata (names, avatars, last message preview) may be cached.
- **R-CACHE-2**: Badge counts must not be computed from cached lists unless there is a reconciliation mechanism that ensures convergence quickly.
- **R-CACHE-3**: Cached lists must not “win” over server-authoritative counts. If cached data implies a different unread count than the server truth, the server truth wins.

---

### 8) Example flows (explicit)
#### Flow C1: New message arrives while app is foregrounded
- **Given**: User is on Requests tab; realtime is connected.
- **When**: New message arrives for Conversation X.
- **Then**:
  - Messages badge increments quickly (realtime fast-path).
  - On next reconciliation (foreground or tab switch), messages badge is overwritten with server truth.

#### Flow C2: Device B reads messages; Device A catches up
- **Given**: User has two devices.
- **When**: User reads Conversation X on Device B.
- **Then**:
  - Device A might remain stale temporarily.
  - On next foreground (or periodic reconcile), Device A fetches counts and badge updates to match.

#### Flow C3: Realtime disconnect; later reconnect
- **Given**: Realtime subscription drops for 2 minutes.
- **When**: New events occur during the outage.
- **Then**:
  - UI may be temporarily stale.
  - On reconnect or next foreground reconcile, badges correct to match server truth.

---

### 9) Acceptance criteria
- **AC-CNT-1**: After app foreground, badge counts match server truth within 1 network round trip.
- **AC-CNT-2**: If realtime is connected, new message causes conversation list + badge update within ~1–2 seconds.
- **AC-CNT-3**: If realtime is disconnected, counts still correct after next foreground reconcile.
- **AC-CNT-4**: Multi-device: reading on one device is reflected on another after reconciliation.
- **AC-CNT-5**: Cached lists never cause badges to remain incorrect after reconciliation.

---

### 10) Dependencies and cross-cutting concerns
- Server needs a stable way to provide counts efficiently (RPC/view/endpoint).
- Client needs a central “counts state” that badges render from, rather than deriving counts ad hoc from different list fetches.
- Rate limiting is required to avoid over-fetching on frequent foreground/tab events.

---

### 12) Explicit product decisions (locked)
- **D-CNT-1 (counts endpoint)**: Use a single server endpoint/RPC to return all counts in one call.
- **D-CNT-2 (reconciliation mode)**: Periodic polling while app is active is required (in addition to foreground + post-action reconciliation).

---

### 13) Open product constants (must be decided before implementation)
- **CONST-POLL-INTERVAL (locked)**:
  - When realtime is connected: poll every **10 seconds** while app is foreground.
  - When realtime is disconnected: poll every **90 seconds** while app is foreground.

#### 13.1 Operational rule (explicit)
- “Realtime disconnected” means the app’s realtime layer is not currently subscribed/connected for the relevant channels (counts may drift).
- If realtime reconnects, immediately resume the 10-second cadence.

---

### 11) External references (design guidance)
- Apple guidance on ensuring notifications are timely and relevant: [Human Interface Guidelines: Notifications](https://developer.apple.com/design/human-interface-guidelines/notifications/)
- General iOS notification APIs: [UserNotifications](https://developer.apple.com/documentation/usernotifications)

