## Product Requirements: Persistent “Bell” Notifications Surface (Non-Message Inbox)

### 1) Overview
NaarsCars needs a native, always-available entry point for non-message notifications that:
- is accessible from anywhere in the “main app” experience
- shows a unified list of non-message notifications
- deep links to the exact destination where the user should act/observe
- supports predictable read/clear behavior

This PRD defines the “bell” surface as **separate from Messages**:
- Message notifications and unread behavior are handled exclusively by the Messages tab + conversation list + thread view (see Messaging PRD).
- The bell surface is for **everything else** (requests lifecycle events, Town Hall/community, admin/system).

---

### 2) Problem statement (what’s broken/unclear today)
- A previous notification page surfaced under Profile, but the product requirement is for a **native in-app notifications surface** that is discoverable and consistent (not “hidden” under Profile).
- Current navigation coordinator supports `.notifications` deep link, but it routes notifications under the Profile tab, which is not aligned with a global bell icon accessible from all main pages.

---

### 3) Goals
- **G1: Persistent entry point**
  - Bell icon exists on all main pages (Requests, Messages, Community, Profile) in a consistent location.
- **G2: Unified non-message feed**
  - Users can see all non-message notifications in one list, ordered by recency (and optionally pinned/priority).
- **G3: Deep link to “exact spot”**
  - Tapping an item takes the user directly to the content that is the subject of the notification (request detail, town hall post, admin panel, profile, etc.).
- **G4: Clear and consistent read semantics**
  - Notifications can be cleared by viewing the destination and/or explicit “mark read” affordances.
- **G5: No duplication/confusion with messages**
  - Messages are excluded from the bell feed.

---

### 4) Non-goals
- **NG1**: Building a full push notification preferences UI.
- **NG2**: Supporting message notifications inside the bell feed.
- **NG3**: Designing complex notification grouping (e.g., collapsing 100 likes into one) unless required later.

---

### 5) Definitions
- **Bell feed**: A list view that shows non-message notifications for the current user.
- **Bell badge**: The count displayed on/near the bell icon indicating unseen bell feed items.
- **Destination**: The screen and specific content that a notification should take the user to.

---

### 6) Current codebase reality (for engineering context)
- `NavigationCoordinator` has a `.notifications` destination that currently routes to the Profile tab (`selectedTab = .profile; navigateToNotifications = true`).
- `NotificationService.fetchNotifications(...)` fetches from `notifications` table, caches results, and provides `markAsRead(...)` and `markAllAsRead(...)`.
- `BadgeCountManager` currently computes:
  - Requests badge from unread request-related notification types
  - Community badge from unread town hall notification types
  - No dedicated “bell” badge exists yet (it will need to be defined as “non-message unread count” excluding message/request/community if those remain separate tab badges, or including them if bell becomes the unified surface).

This PRD defines the product-level desired behavior; later technical docs will decide whether the bell badge is:
- a separate badge independent from tab badges, or
- the canonical non-message badge while tabs may still show their own scoped badges.

---

### 7) Product requirements (UX)
#### 7.1 Placement and access
- **R-BELL-1**: A bell icon is visible in the upper-right of all main pages:
  - Requests dashboard
  - Messages
  - Community
  - Profile
- **R-BELL-2**: Bell icon opens the bell feed (`NotificationsListView` or equivalent).
- **R-BELL-3**: Bell icon can display a badge count (bell badge), defined below.

#### 7.2 Notification inclusion/exclusion
- **R-FEED-1**: The bell feed includes all non-message notifications.
- **R-FEED-2**: The bell feed excludes message events (new message, added to conversation, message read, typing, etc.).
- **R-FEED-3**: Each notification item displays:
  - type (icon + label)
  - primary text (who/what)
  - timestamp (relative)
  - read/unread styling

#### 7.3 Deep linking behavior (“exact spot”)
- **R-DEEPLINK-1**: Each notification type maps to one destination:
  - Request-based notifications → request detail (ride or favor)
  - Town Hall notifications → specific post/comment thread
  - Admin/pending approvals → admin panel
  - Profile-related notifications → profile screen
- **R-DEEPLINK-2**: Tapping a notification navigates the user to the destination with minimal intermediate steps.

#### 7.4 Read/clear behavior
- **R-READ-1**: A bell notification becomes read when the user successfully navigates to (and sees) the destination content.
- **R-READ-2**: The bell feed supports explicit clearing (e.g., “mark as read” via swipe action) for users who want to clear without navigating.
- **R-READ-3**: The bell feed supports “mark all read” as an optional affordance (product decision).
- **R-READ-4 (cross-surface clearing)**: If a bell notification is “cleared” because the user navigated to the destination via some other path (e.g., opening a request detail from Requests tab, or opening a Town Hall post directly), the bell feed item must update to read as well. The bell feed is a view over the underlying notification read state, not a separate state.
- **R-READ-5 (type-specific exception: review prompts)**: For review request/reminder notifications, navigating to the Review UI does **not** mark the notification read. It becomes read only when the user submits a review or explicitly skips/dismisses the review prompt.

---

### 8) Bell badge semantics (explicit)
This PRD defines the bell badge as:
- **bell badge = count of unread bell-feed notifications (non-message)**.

Important clarification:
- If Requests and Community continue to have their own tab badges, bell badge can still exist independently as “all non-message notifications”. Alternatively, bell could become the unified surface and those tab badges could be reduced/removed later. This PRD does not force that consolidation but ensures semantics are well-defined.

**Locked decision**: Keep existing tab badges and also have bell as a unified non-message surface (potentially overlapping counts), rather than consolidating into a single badge source.

---

### 8.1 Bell feed includes these categories (locked)
- **Requests**: include
- **Community/Town Hall**: include
- **Admin/System**: include

---

### 8.2 UI Anchor Registry (canonical, code-backed)
These anchors are the authoritative names we will use in PRDs and later task lists.

#### Global chrome anchors (to be implemented)
- **`app.chrome.bellIcon`**: Bell icon in the upper-right of main pages (Requests/Messages/Community/Profile).
- **`app.chrome.bellBadge`**: Badge displayed on/near the bell icon.

#### Dedicated notifications sub-surfaces (to be implemented)
- **`bell.announcements`**: Dedicated Announcements screen (a focused list of `announcement` / `adminAnnouncement` / `broadcast` items).
- **`bell.announcements.row(notificationId)`**: A specific announcement item row.

#### Current “notifications list” anchors (existing implementation)
Note: today, `NotificationsListView` is reachable via Profile. The bell PRD will eventually make it reachable globally, but these existing anchors still matter for migration.
- **`profile.myProfile.notificationsLink`**: My Profile → “Notifications” NavigationLink (`notificationsSection()`).
- **`profile.myProfile.adminPanelLink`**: My Profile → “Admin Panel” NavigationLink (`adminPanelLink()`).
- **`profile.myProfile.reviewsSection`**: My Profile → Reviews section (the “Reviews” block in `reviewsSection()`).
- **`bell.notificationsList`**: `NotificationsListView` screen (currently presented via Profile navigation).
- **`bell.notificationsList.markAllRead`**: “Mark All Read” toolbar button.
- **`bell.notificationsList.row(notificationId)`**: A notification row (tap invokes `NotificationsListViewModel.handleNotificationTap(...)`).

#### Community anchors (Town Hall)
- **`community.townHall.feed`**: `TownHallFeedView` feed surface.
- **`community.townHall.postCard(postId)`**: A post card in the feed (`TownHallPostCard`).
- **`community.townHall.postCommentsSheet(postId)`**: The comments sheet (`PostCommentsView(postId:)`) presented from a post card.
- **`community.townHall.postCommentsSheet.commentInput`**: Comment input field area (bottom composer).

#### Admin anchors
- **`profile.adminPanel`**: `AdminPanelView` root.
- **`profile.adminPanel.pendingApprovalsLink`**: “Pending Approvals” link within AdminPanel management section.
- **`profile.admin.pendingUsersList`**: `PendingUsersView` list screen.

#### Entry anchors
- **`app.entry.enterApp`**: Post-approval entry path that routes the approved user into the authenticated experience (dashboard).

---

### 8.3 Notification type → destination → anchor mapping (explicit)
This table defines how bell feed items deep link into the app.

| NotificationType | Destination | Anchor |
|---|---|---|
| request-based (see Requests PRD mapping) | `RideDetailView` / `FavorDetailView` | request anchors per Requests PRD |
| `townHallPost` | Community → Town Hall | open feed → auto-open `community.townHall.postCommentsSheet(postId)` (and highlight post context) |
| `townHallComment` / `townHallReaction` | Community → Town Hall | `community.townHall.postCard(postId)` (scroll into view; no auto-open comments; no auto-focus composer; **highlight post card ~10s**) |
| `pendingApproval` | Profile → Admin | `profile.admin.pendingUsersList` |
| `announcement` / `adminAnnouncement` / `broadcast` | Announcements screen | `bell.announcements.row(notificationId)` |
| `reviewReceived` | Profile → My Profile | `profile.myProfile.reviewsSection` |
| `userApproved` | Enter app | `app.entry.enterApp` |
| `userRejected` | No user-facing notification | `none` (account is deleted as part of rejection flow) |

---

### 8.4 Announcements pipeline (locked)
This app currently has `NotificationType` values for announcements (`announcement`, `adminAnnouncement`, `broadcast`) and push categories for “new request / completion reminder / message”, but there is **not yet** a complete product-specified announcements UX. This section defines it.

#### 8.4.1 Surfaces
- **R-ANN-1**: Announcements appear in the bell system and are accessible from:
  - the unified bell feed (as grouped/filtered items), and
  - a dedicated Announcements screen (`bell.announcements`) that shows announcements only.
- **R-ANN-2**: Announcements are grouped by **announcement id** (one announcement = one subject), not collapsed into a single “Announcements” bucket.

#### 8.4.2 Read semantics
- **R-ANN-READ-1**: An announcement is marked read **only** when the user taps that specific announcement row (read-on-tap).
- **R-ANN-READ-2**: Simply opening the bell feed or the Announcements screen does not mark announcements read.

#### 8.4.3 Deep linking
- **R-ANN-DL-1**: Tapping an announcement notification routes to `bell.announcements.row(notificationId)` (showing the specific announcement item in context).

---

### 9) Example flows (explicit)
#### Flow B1: User receives a request-related notification
- **Given**: User is in any tab.
- **When**: A request notification arrives (e.g., claim/unclaim/Q&A/completion).
- **Then**:
  - Bell badge increments by 1.
  - Bell feed shows a new item at the top.
  - Tapping the item navigates directly to that request’s detail view.
  - After viewing, that bell item becomes read and bell badge decrements.

#### Flow B2: User receives a Town Hall comment notification
- **When**: Someone comments on the user’s Town Hall post.
- **Then**:
  - Bell feed item appears with type “Town Hall Comment”.
  - Tap → navigates to the exact post/comment thread.
  - Read state updates on successful navigation.

#### Flow B3: User clears without navigating
- **When**: User opens bell feed and swipes to mark an item read.
- **Then**:
  - Item styling becomes read.
  - Bell badge decrements accordingly.

---

### 10) Acceptance criteria
- **AC-BELL-1**: Bell icon is visible on all main pages.
- **AC-BELL-2**: Bell feed never shows message events.
- **AC-BELL-3**: Tapping any bell feed item navigates to the correct destination (“exact spot”).
- **AC-BELL-4**: Bell badge count matches the number of unread bell-feed items.
- **AC-BELL-5**: Read/clear actions update UI and badge predictably.

---

### 11) Dependencies and cross-cutting concerns
- Deep-link routing must support all destinations (ride, favor, town hall post, admin, profile).
- Badge correctness must follow the reconciliation model in the Realtime/Caching PRD to prevent trust erosion.
- The notifications table/schema must carry enough information (subject IDs) to deep link unambiguously.

---

### 13) Grouping behavior (locked)
- **R-GROUP-1**: Bell feed groups notifications by subject (e.g., multiple events on the same request collapse into one feed entry, with a count and “latest activity” timestamp).
- **R-GROUP-2**: Tapping a grouped entry navigates to the subject destination; the grouping UI must still allow the user to understand “something happened multiple times” (count + latest summary).

#### 13.1 Grouping key rules (explicit)
- Requests: group by `ride_id` or `favor_id`
- Town Hall: group by `town_hall_post_id`
- Admin pending approval: group by “pending approvals” subject
- Announcements: group by **announcement notification id** (do not collapse all announcements together)

---

### 12) External references (design guidance)
- Apple guidance on using notifications to provide timely, relevant updates: [Human Interface Guidelines: Notifications](https://developer.apple.com/design/human-interface-guidelines/notifications/)
- Apple notification APIs (foreground presentation + handling user responses): [UserNotifications](https://developer.apple.com/documentation/usernotifications)

