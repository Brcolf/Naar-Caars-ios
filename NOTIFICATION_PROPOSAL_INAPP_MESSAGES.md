## Product Requirements: Messaging Notifications + Unread State (iMessage-Style)

### 1) Overview
NaarsCars messaging should feel like texting:
- A new message is **always visible immediately** where the user expects to see it.
- The app **does not “notify you about what you are already looking at.”**
- Badges represent **work you haven’t done yet** (messages you haven’t viewed), and they clear **only** by viewing the relevant thread.

This document defines message-specific notification behavior and read/unread semantics. It intentionally treats “Messages” as its own product surface, separate from the “bell” (non-message) notifications surface.

---

### 2) Problem statement (what’s broken today)
These issues are consistent with the current codebase:
- **In-app notifications for messages don’t exist server-side**: the DB trigger `notify_message_push()` sends push via `send_push_notification_direct(...)` and does **not** create any `notifications` rows for message events, so the in-app notifications list/feed cannot show message entries even if we wanted it to.
- **Foreground “message notifications” are currently implemented as a local notification**: `ConversationsListViewModel.handleMessageInsertForList(...)` calls `PushNotificationService.shared.showLocalMessageNotification(...)` when `UIApplication.shared.applicationState == .active`. This is the opposite of iMessage-style UX (it interrupts while the app is in use, and can be redundant with the list update itself).
- **Read suppression exists, but only at a coarse level**: the DB trigger suppresses push if `conversation_participants.last_seen` is within 60 seconds, and `ConversationDetailViewModel.loadMessages()` sets `last_seen` then marks messages read. This is close to the desired behavior, but needs clear product-level rules so it behaves predictably (and doesn’t miss cases like “user is in Messages tab but not in that thread”).

---

### 3) Goals
- **G1: Thread-first experience**
  - If the user is viewing a message thread, new messages for that thread appear inline (no banners, no “notification rows”).
- **G2: Conversation list awareness**
  - If the user is viewing the conversations list, that list updates immediately (preview + ordering + per-conversation unread).
  - A lightweight in-app cue is allowed, but must not feel like a push notification clone.
- **G3: Cross-app awareness**
  - If the user is outside Messages (other tab, background, locked), a message should alert them and deep link directly into the thread.
- **G4: Unread correctness**
  - Per-conversation unread counts are correct.
  - Messages tab badge is the sum of unread messages across all conversations (as requested).
  - Unread clears only by viewing the thread (incrementally, based on which messages were seen).
- **G5: No ambiguity for implementation**
  - The required inputs and “state rules” are explicit (what counts as “viewing a thread”, what counts as “seen”, etc.).

---

### 4) Non-goals (for this PRD)
- **NG1**: Redesigning the entire notifications system / bell feed.
- **NG2**: Implementing OS-level push registration, APNS token lifecycle, or push delivery reliability work.
- **NG3**: Introducing message reactions, mentions, or advanced chat features (typing indicators already exist separately).

---

### 5) Definitions (shared vocabulary)
- **Thread / Conversation**: A single chat conversation (`conversation_id`).
- **Conversation list**: The messages inbox screen listing all conversations (`ConversationsListView`).
- **Thread view**: The chat detail screen for one conversation (`ConversationDetailView` / `ConversationDetailViewModel`).
- **Unread message**: A message whose `read_by` does not contain the current user (current model behavior).
- **Seen / viewed (thread)**: The user has navigated into the thread view and the app has had an opportunity to mark messages read (incremental).
- **In-app message awareness**: Updating UI in real time (list row + badge + previews) without using a separate “bell” feed entry.
- **UI Anchor**: A stable identifier for a destination within the UI (screen + section + optional item) used for deep linking and “seen” logic.

---

### 6) Current codebase reality (for engineering context)
This PRD intentionally aligns with the current architecture:
- **Realtime list updates already exist**:
  - `ConversationsListViewModel` subscribes to `messages` inserts (`messages:list-updates`) and updates the conversation row + local unread count.
- **Thread read flow already exists**:
  - `ConversationDetailViewModel.loadMessages()` updates `conversation_participants.last_seen` and calls `MessageService.markAsRead(...)`, then refreshes `BadgeCountManager`.
- **Badges are computed as follows**:
  - Messages badge is computed as the sum of `ConversationWithDetails.unreadCount` across all conversations fetched by `MessageService.fetchConversations(...)`.
- **DB push for messages**:
  - DB function `notify_message_push()` sends push directly and suppresses push if `last_seen` is within 60 seconds.

Product requirements below define how we should leverage/adjust these behaviors, but do not ask for implementation yet.

---

### 7) User stories
- **US1**: As a user who is actively chatting in a thread, I want new replies to appear immediately without interruptions.
- **US2**: As a user scanning my conversation list, I want the correct conversation to jump to the top and show an unread count as soon as a message arrives.
- **US3**: As a user elsewhere in the app, I want to be routed to the correct thread when a message arrives.
- **US4**: As a user, I want badges to be trustworthy and only clear when I actually read the thread.

---

### 8) Primary UX requirements (what the user sees)
#### 8.1 Thread view (ConversationDetailView) behavior
- **R-THREAD-1**: If a message arrives for the thread the user is currently viewing:
  - The message **renders inline** immediately.
  - The app **must not** display any “new message” in-app banner/toast/notification for that message.
  - The message is considered eligible for “seen” only if it becomes **visible** on screen (exact incremental rules below).
- **R-THREAD-2 (auto-scroll expectation)**: When the user is at/near the bottom of the thread (i.e., actively reading the newest messages), the UI should keep the newest message in view when new messages arrive (auto-scroll to bottom as needed). If the user has scrolled up (not at bottom), the UI must not force-scroll; instead it should show a subtle “new messages” affordance so the user can jump to bottom intentionally.

#### 8.2 Conversation list behavior
- **R-LIST-1**: If a message arrives for a conversation while the user is on the conversation list:
  - That conversation row updates (preview, timestamp, ordering).
  - That conversation’s unread count increments (if the message is from someone else).
  - Messages tab badge updates (sum of all conversation unread counts).
- **R-LIST-2 (required)**: While on the conversation list, show a **lightweight in-app banner/toast** for incoming messages (tap-to-open the thread), but:
  - It must never show while the user is inside the relevant thread.
  - It must not be implemented as an OS-style local notification (avoid Notification Center clutter and “double notification” feel).

#### 8.3 Outside Messages (other tabs / background)
- **R-OUTSIDE-1**: If the user is not in the Messages tab (or the app is backgrounded), the user should receive an alert (push when OS allows).
- **R-OUTSIDE-2**: Tapping that alert routes the user:
  - to Messages tab
  - then directly into the correct thread (deep link to conversation).
- **R-OUTSIDE-3 (foreground push rule)**: If the app is in the foreground, do **not** rely on APNS push delivery to alert the user. Use in-app UI (banner/toast + list update + badges) only.

---

### 9) Read/unread + clearing semantics (incremental)
This is the “rules engine” that prevents phantom badges and ensures incremental clearing.

#### 9.1 What clears a message notification?
- **R-CLEAR-1**: A message is cleared (becomes read for the recipient) only by viewing the thread that contains it.
- **R-CLEAR-2**: Navigating to the Messages tab or to the conversation list **does not** clear message unread state.

#### 9.2 Incremental clearing (seen messages only)
- **R-INCR-1**: When the user enters a thread view:
  - The app marks as read only the messages that are **actually visible** on screen (product intent: “messages the user had a chance to see”).
- **R-INCR-2**: If there are 50 unread messages and only the latest 25 are loaded initially, the badge should decrement only for the subset that becomes visible (not necessarily all 25). The remainder stays unread until it becomes visible (e.g., user scrolls).
- **R-INCR-3 (thread-open but scrolled up)**: If the user is in a thread but scrolled up such that new incoming messages are not visible, those messages remain unread and can contribute to unread counts/badges until the user jumps to bottom (or otherwise makes them visible).

#### 9.3 Marking unread again
- **R-UNREAD-1**: If a user explicitly marks a message/thread as unread in the future (not currently in scope), it should create a **new** unread state rather than “resurrecting” old cleared notification rows.

---

### 10) Example flows (explicit, end-to-end)
#### Flow M1: User is inside Thread A; message arrives in Thread A
- **Given**: User is viewing Thread A.
- **When**: Another participant sends a message to Thread A.
- **Then**:
  - Message appears inline in Thread A immediately.
  - No banner/toast/local-notification is shown.
  - If the user is at bottom and the message is visible immediately, the Messages tab badge does not increment due to this message (it is immediately eligible to be seen).
  - If the user is scrolled up and the message is not visible, it remains unread and can increment unread counts until the user views it.

#### Flow M2: User is on conversation list; message arrives for Thread A
- **Given**: User is on conversation list.
- **When**: Message arrives for Thread A.
- **Then**:
  - Thread A row moves to top, shows preview and timestamp.
  - Thread A unread count increments by 1.
  - Messages tab badge increments by 1 (or by the appropriate amount for multi-message bursts).

#### Flow M3: User is on Requests tab; message arrives for Thread A
- **Given**: User is not in Messages tab.
- **When**: Message arrives for Thread A.
- **Then**:
  - Messages tab badge increments.
  - Push notification is delivered (subject to OS + user settings).
  - Tapping the push takes user to Messages tab and directly into Thread A.

#### Flow M4: Burst messages while user is away; incremental clearing
- **Given**: User has Thread A with 10 unread messages.
- **When**: User opens Thread A and the app loads the latest 6 unread messages.
- **Then**:
  - Those 6 become read; unread count for Thread A becomes 4.
  - Messages tab badge decrements by 6, leaving the remaining 4 until loaded/seen.

---

### 11) Data requirements (inputs needed to meet UX)
To enable deep links and correct reconciliation, every delivered “new message” event (realtime or push) must include:
- **conversation_id**
- **message_id**
- **sender_id**
- **message_preview** (optional; used for UI preview only)

Note: current DB push payload already includes `conversation_id`, `message_id`, `sender_id`.

---

### 12) Acceptance criteria (what QA can verify)
- **AC-1**: When viewing a thread, incoming messages never create a banner/toast/local notification for that thread.
- **AC-2**: Conversation list updates within ~1–2 seconds of message insert (given realtime subscription is connected).
- **AC-3**: Messages tab badge equals the sum of per-conversation unread counts.
- **AC-4**: Unread state clears only by entering the relevant thread, and clears incrementally (not globally) based on what is loaded/marked read.
- **AC-5**: Tapping a message push navigates directly to the relevant thread.
- **AC-6**: In thread view, if user is at bottom, new messages stay visible (auto-scroll). If user is scrolled up, the UI does not force-scroll and unread state remains until the user jumps to bottom.

---

### 13) Dependencies and cross-cutting considerations
- **DB**: `conversation_participants.last_seen` is currently used to infer “actively viewing”; product requirements rely on a reliable definition of “actively viewing thread” (may evolve beyond a 60s threshold).
- **Realtime**: Conversation list relies on realtime `messages` inserts to update without polling.
- **Caching**: `MessageService.fetchConversations(...)` uses cache; badge correctness must not be undermined by stale cached unread counts (see the Realtime/Caching PRD).

---

### 15) Explicit product decisions (locked)
- **D-MSG-1 (Messages badge)**: Messages tab badge = **total unread messages across all conversations**.
- **D-MSG-2 (Viewing thread definition)**: A user is considered “viewing Thread X” only when `ConversationDetailView` for X is the top-most view **and** the app is foregrounded.
- **D-MSG-3 (Conversation list cue)**: Use an **in-app banner/toast** (not OS local notifications) while on the conversation list.
- **D-MSG-4 (Foreground push)**: In foreground, do not rely on push; use in-app UI only.
- **D-MSG-5 (Deep link)**: Push tap always routes: open app → Messages tab → thread.
- **D-MSG-6 (Message notification rows)**: Message events may still create `notifications` rows for audit/debug/reconciliation, but they must be excluded from the bell feed and bell badge calculations.

---

### 16) UI Anchor Registry (canonical, code-backed)
These anchors are grounded in existing SwiftUI structure in `ConversationsListView` and `ConversationDetailView`. They should be treated as stable IDs for deep linking and “seen” semantics.

#### Conversations list anchors (`ConversationsListView`)
- **`messages.conversationsList`**: The Messages inbox list screen.
- **`messages.conversationsList.row(conversationId)`**: A specific conversation row (tap navigates to thread).
- **`messages.conversationsList.newMessageComposer`**: The “New Message” entry point (`square.and.pencil` toolbar button + `UserSearchView` sheet).
- **`messages.conversationsList.inAppToast`**: The lightweight in-app toast/banner shown when a new message arrives while on the list (required by PRD; not currently implemented).

#### Thread view anchors (`ConversationDetailView`)
- **`messages.thread(conversationId)`**: The thread screen.
- **`messages.thread.message(messageId)`**: A specific message bubble (message rows already use `.id(message.id)`).
- **`messages.thread.bottom`**: The bottom-of-thread anchor (already present as `.id("bottom")`).
- **`messages.thread.scrollToBottomButton`**: The “scroll to bottom” affordance (`ScrollToBottomButton`).

---

### 17) Message deep link landing rules (explicit)
- **Push tap**: `messages.conversationsList` → `messages.thread(conversationId)` → scroll to `messages.thread.bottom`.
- **In-app toast tap (list)**: `messages.conversationsList` → `messages.thread(conversationId)` → scroll to `messages.thread.bottom`.

---

### 14) External references (design guidance)
- Apple’s notification design guidance (interruption level and relevance): [Human Interface Guidelines: Notifications](https://developer.apple.com/design/human-interface-guidelines/notifications/)
- Apple’s notification handling APIs (deep linking on tap): [UserNotifications](https://developer.apple.com/documentation/usernotifications)

