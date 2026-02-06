## Product Requirements: Request-Based Notifications + Badge Clearing (Per-Request, Universal Types)

### 1) Overview
Requests (rides + favors) generate multiple notification types over their lifecycle (new request, Q&A activity, claim/unclaim, completion, review prompts). Users need:
- A trustworthy Requests badge that reflects “things I should look at”
- Per-request cues (so the user can find which request is “hot”)
- A universal clearing rule: viewing the request detail clears request-related notifications for that specific request

This PRD defines read/seen semantics for request-based notifications and how those semantics map into:
- Requests tab badge count
- Per-card indicators in the Requests dashboard/list
- Clearing behavior on navigating to request detail

---

### 2) Problem statement (what’s broken today)
Consistent with the current code:
- `BadgeCountManager.clearRequestsBadge()` stores a `lastViewedRequests` timestamp, but Requests badge computation does not reference that timestamp.
- Requests badge count is currently computed by fetching notifications and counting unread rows for request-related notification types. Therefore, simply navigating to the Requests tab does not clear anything, and the badge persists unless those notification rows are explicitly marked read.

---

### 3) Goals
- **G1: Universal per-request clearing**
  - Viewing request detail for Request X clears request-based notifications scoped to Request X (across all request types: new, Q&A, claim/unclaim, completion, review).
- **G2: Badge reflects actionable unseen request activity**
  - Requests badge represents unseen request activity, scoped correctly.
- **G3: Per-card cues**
  - Requests list clearly highlights which specific requests have unseen activity.
- **G4: Consistency across types**
  - The clearing rule is the same regardless of whether the notification was “new request” vs “Q&A” vs “claim/unclaim”.

---

### 4) Non-goals
- **NG1**: Redefining what a “request” is or changing request lifecycle business logic.
- **NG2**: Redesigning Messages semantics (handled in messaging PRD).
- **NG3**: Building a full notification preferences UI (may exist separately).

---

### 5) Definitions
- **Request**: Either a ride request or favor request (identified by `ride_id` or `favor_id`).
- **Request-based notification**: Any notification whose subject is a particular request (e.g., new ride, QA, claim/unclaim, completion, review).
- **Seen (request)**: User has navigated into the request detail view and the content has loaded sufficiently to be considered “viewed”.
- **Clearing**: Marking the scoped request-based notifications as read/seen such that they no longer count toward badge totals.

---

### 6) Current codebase reality (for engineering context)
Important behaviors that this PRD must align with:
- Requests badge is computed by `BadgeCountManager.calculateRequestsBadgeCount(...)` by fetching notifications and counting unread request-related notification types.
- Requests “clear” on tab switch currently calls `BadgeCountManager.clearRequestsBadge()`, which does not mark any notification rows read; it only stores `lastViewedRequests`.
- `NotificationService` supports `markAsRead(notificationId:)`, `markAllAsRead(userId:)`, and has a special-case `markReviewRequestAsRead(requestType:requestId:)` for `review_request`, indicating partial request-scoped clearing exists but is not generalized.

---

### 7) Product requirements (UX + semantics)
#### 7.1 Badge meaning (Requests tab badge)
Pick one of the two models below and treat it as a product decision. This PRD assumes **Model A** because it best matches “count of un-viewed request-based notifications” as you described; Model B remains as an explicit alternative.

- **Model A (recommended): badge = number of requests with unseen activity**
  - If one request has 5 unseen notifications, the badge increments by 1 (not 5).
  - Rationale: users think in terms of “which requests need attention,” not “how many events happened.”

- **Model B (alternative): badge = total count of unseen request-based notifications**
  - Badge increments per event row.
  - Rationale: more precise, but can inflate quickly and feel noisy.

This PRD requires whichever model is chosen to be consistent everywhere (badge, per-card counts).

**Locked decision**: Requests badge uses **Model A** (badge = number of requests with unseen activity).

#### 7.2 Per-card cues in Requests list/dashboard
- **R-CARD-1**: Each request card must indicate unseen activity using a **dot indicator only** (binary seen/unseen).
- **R-CARD-2**: The indicator must be derived from the same underlying seen/read state used for Requests tab badge (no “two sources of truth”).
- **R-CARD-3**: The indicator must be scoped to that request only (never cleared by viewing a different request).

#### 7.3 Universal clearing on request detail view
- **R-CLEAR-REQ-1**: When the user views request detail for Request X (ride or favor):
  - Mark as read/seen all request-based notifications for Request X, across these classes:
    - new request (new ride/new favor)
    - Q&A activity (question/answer/activity)
    - claim/unclaim
    - completion + completion reminders
    - review prompts/reminders
  - This must apply universally to “relevant parties” (the notification recipient) regardless of role (requester/fulfiller/etc.).
- **R-CLEAR-REQ-2**: Clearing is triggered by viewing the request detail (not just by opening Requests tab).
- **R-CLEAR-REQ-3**: Clearing is idempotent and safe to repeat.

#### 7.4 “Seen” definition (remove ambiguity)
- **R-SEEN-REQ-1 (section-specific)**: A request-based notification is considered “seen/read” only when the user views the **relevant section** in the request detail experience (not merely opening the request shell).
- **R-SEEN-REQ-2 (Q&A deep link)**: For Q&A notifications, the destination must navigate to request detail and auto-scroll to the **Q&A section**.
- **R-SEEN-REQ-3 (clearing scope in time)**: Viewing a request clears only the notifications that exist **up to the time of viewing**; new notifications created after viewing remain unread/unseen.

#### 7.5 Section mapping per notification type (locked)
This mapping defines what “relevant section” means for each request-based notification type.

- **New Request** (`newRide`, `newFavor`) → request detail **main section (top)**.
- **Claimed** (`rideClaimed`, `favorClaimed`) → request detail **main section (top)**.
- **Unclaimed** (`rideUnclaimed`, `favorUnclaimed`) → request detail navigates to the **claim/fulfillment status** portion of the detail UI (the part that explains/reflects unclaiming for the relevant party).
- **Completion flow** (`completionReminder`) → request detail navigates to the **completion action** and opens the **CompleteSheet** modal for the claimer (see Section 7.6).
- **Q&A** (`qaActivity`, `qaQuestion`, `qaAnswer`) → request detail **Q&A section** (auto-scroll).
- **Review Request / Review Reminder** (`reviewRequest`, `reviewReminder`) → navigate to **Review UI**, but **do not clear** the notification upon navigation; clear only when the user:
  - submits a review, or
  - explicitly skips/dismisses the review prompt (product “skip” action).

#### 7.6 Completion workflow (locked, replaces “completed notifications”)
- **R-COMPLETE-1**: “Mark Complete” is an action performed by the **claimer/fulfiller** via a popup modal (`CompleteSheet`), similar to the review flow.
- **R-COMPLETE-2**: Completing a request triggers the **review workflow** for relevant parties (review prompt / review request notification).
- **R-COMPLETE-3**: There is **no separate request-based notification type** that exists solely to inform users “ride/favor completed” (`rideCompleted` / `favorCompleted`) because the review workflow covers this inform/next-action moment.
  - If legacy `rideCompleted` / `favorCompleted` notifications exist historically, they should be treated as request updates landing at `mainTop` and can be ignored for new generation.

#### 7.7 Deep-link landing highlight (locked)
- **R-HIGHLIGHT-1**: When a notification deep-links into a request detail view, the target anchor section is visually highlighted to orient the user.
- **R-HIGHLIGHT-2**: Highlight lasts ~**10 seconds** or until the page is dismissed, whichever comes first.
- **R-HIGHLIGHT-3**: This highlight rule applies to all request update notifications (e.g., Q&A, unclaim, completion reminder, ride/favor update).

---

### 9.1 UI Anchor Registry (canonical, code-backed)
These anchors must be treated as stable identifiers for deep linking and “seen” logic. They map to existing SwiftUI sections/components in `RideDetailView` and `FavorDetailView`.

#### Ride detail anchors (`RideDetailView`)
- **`requests.rideDetail.mainTop`**: Top of `RideDetailView` scroll content (poster/participants/status).
- **`requests.rideDetail.statusBadge`**: The status badge `Text(ride.status.displayText)` section.
- **`requests.rideDetail.claimerCard`**: The “Claimed by” card (only present when `ride.claimer != nil`).
- **`requests.rideDetail.qaSection`**: The `RequestQAView` block (header “Questions & Answers”).
- **`requests.rideDetail.claimAction`**: The `claimButtonSection(ride:)` area (`ClaimButton`).
- **`requests.rideDetail.completeAction`**: The “Mark Complete” entry point (should be claimer-facing per PRD; opens `CompleteSheet`).
- **`requests.rideDetail.completeSheet`**: The `CompleteSheet` modal.
- **`requests.rideDetail.reviewSheet`**: The `LeaveReviewView` sheet (shown via `showReviewSheet`).
- **`requests.rideDetail.claimSheet`**: The `ClaimSheet` modal.
- **`requests.rideDetail.unclaimSheet`**: The `UnclaimSheet` modal.

#### Favor detail anchors (`FavorDetailView`)
- **`requests.favorDetail.mainTop`**
- **`requests.favorDetail.statusBadge`**
- **`requests.favorDetail.claimerCard`**
- **`requests.favorDetail.qaSection`**
- **`requests.favorDetail.claimAction`**
- **`requests.favorDetail.completeAction`**
- **`requests.favorDetail.completeSheet`**
- **`requests.favorDetail.reviewSheet`** (note: review sheet may be present depending on flow)
- **`requests.favorDetail.claimSheet`**
- **`requests.favorDetail.unclaimSheet`**

---

### 9.2 Notification → destination → anchor mapping (explicit)
This table defines the required deep link landing point for request-based notification types.

| NotificationType | Destination screen | Anchor |
|---|---|---|
| `newRide` | `RideDetailView(rideId)` | `requests.rideDetail.mainTop` |
| `rideClaimed` | `RideDetailView(rideId)` | `requests.rideDetail.mainTop` |
| `rideUnclaimed` | `RideDetailView(rideId)` | `requests.rideDetail.statusBadge` → auto-scroll to `requests.rideDetail.claimAction` |
| `completionReminder` (ride) | `RideDetailView(rideId)` | `requests.rideDetail.completeSheet` (open modal) |
| `qaActivity`/`qaQuestion`/`qaAnswer` (ride) | `RideDetailView(rideId)` | `requests.rideDetail.qaSection` |
| `reviewRequest`/`reviewReminder` (ride) | `LeaveReviewView` (via Review UI entry) | `requests.rideDetail.reviewSheet` (do not mark read on navigation) |
| `rideUpdate` (ride) | `RideDetailView(rideId)` | `requests.rideDetail.mainTop` (with highlight if specific section is identified later) |
| `newFavor` | `FavorDetailView(favorId)` | `requests.favorDetail.mainTop` |
| `favorClaimed` | `FavorDetailView(favorId)` | `requests.favorDetail.mainTop` |
| `favorUnclaimed` | `FavorDetailView(favorId)` | `requests.favorDetail.statusBadge` → auto-scroll to `requests.favorDetail.claimAction` |
| `completionReminder` (favor) | `FavorDetailView(favorId)` | `requests.favorDetail.completeSheet` (open modal) |
| `qaActivity`/`qaQuestion`/`qaAnswer` (favor) | `FavorDetailView(favorId)` | `requests.favorDetail.qaSection` |
| `reviewRequest`/`reviewReminder` (favor) | `LeaveReviewView` (via Review UI entry) | `requests.favorDetail.reviewSheet` (do not mark read on navigation) |
| `favorUpdate` (favor) | `FavorDetailView(favorId)` | `requests.favorDetail.mainTop` (with highlight if specific section is identified later) |

---

### 8) Example flows (explicit)
#### Flow R1: Two requests; view clears one
- **Given**: User has unseen activity on Request A and Request B.
- **Then**: Requests tab badge shows 2 (Model A) and both cards show “unseen”.
- **When**: User opens Request A detail.
- **Then**:
  - Request A’s request-based notifications are marked read/seen.
  - Requests tab badge becomes 1.
  - Request A’s card indicator clears; Request B remains highlighted.

#### Flow R2: Multiple notification types for a single request; single view clears all
- **Given**: Request A generated:
  - new request
  - 2 Q&A notifications
  - claim notification
- **When**: User opens Request A detail and content loads.
- **Then**:
  - All Request A notifications become read/seen (not just the most recent type).
  - Request A no longer contributes to Requests badge and no longer shows per-card “unseen”.

#### Flow R3: Viewing Requests tab does not clear
- **Given**: User has unseen activity on Request A.
- **When**: User taps Requests tab and sees the dashboard/list.
- **Then**: Badge remains until Request A detail is viewed (per R-CLEAR-REQ-2).

---

### 9) Data requirements (minimal, unambiguous)
To support per-request scoping, every request-based notification must be linkable to exactly one request:
- Ride notifications carry `ride_id`
- Favor notifications carry `favor_id`

If a notification cannot be scoped to a request, it must not count toward Requests badge nor show per-card cues.

---

### 10) Acceptance criteria (QA-ready)
- **AC-REQ-1**: Requests tab badge decreases when viewing a specific request detail, and only for that request.
- **AC-REQ-2**: Clearing is universal across all request-based notification types (new/Q&A/claim/unclaim/completion/review) for that request.
- **AC-REQ-3**: Viewing Requests tab alone never clears request-based notifications.
- **AC-REQ-4**: Per-card “unseen” indicators exactly match the underlying state driving the badge count.
- **AC-REQ-5**: Unrelated notification types (messages/community/admin/system) do not affect Requests badge or request card cues.
- **AC-REQ-6**: Q&A notification tap deep links to the request detail and lands in the Q&A section; the notification is marked read only after the Q&A section is reached/visible.
- **AC-REQ-7**: Unclaim/completion notification tap deep links to the relevant portion of the request detail UI (claim/status or completion/status respectively); the notification is marked read only after that section is reached/visible.
- **AC-REQ-8**: Review request/reminder notifications do not clear on navigation; they clear only on “review submitted” or “review skipped.”

---

### 11) Dependencies and implementation notes (not implementation)
- `NotificationService` will need a generalized “mark request-scoped notifications read” operation (ride + favor) rather than only `review_request`.
- Badge computation in `BadgeCountManager` must align to the chosen badge model (A vs B).
- The Requests dashboard/list and each request detail view must have the necessary identifiers (request type + id) to trigger scoped clearing on detail view.

---

### 12) External references (design guidance)
- Apple guidance on using notifications to provide timely, relevant updates: [Human Interface Guidelines: Notifications](https://developer.apple.com/design/human-interface-guidelines/notifications/)

