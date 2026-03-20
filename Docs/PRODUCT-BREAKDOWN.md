# Naar's Cars iOS App — Exhaustive Product & Technical Breakdown

> Generated: 2026-03-19
> Source: Full codebase analysis of `naars-cars-ios` repository
> Purpose: App Store reviewer evaluation, new engineer onboarding, product strategy reference

---

## 1. App Overview (Plain-English)

### What the app is

Naar's Cars is a native iOS 17+ app for an invite-only neighborhood community where members help each other with rides and favors. It is not a commercial ride-hailing service — there are no payments, no driver accounts, no fares. It is a mutual-aid platform where neighbors post requests ("I need a ride to the airport Thursday at 6am" or "Can someone help me move a couch?") and other community members voluntarily claim and fulfill those requests.

### Core value proposition

Eliminates the friction of asking neighbors for help. Instead of texting around or posting on Nextdoor, users post structured requests with dates, times, locations, and seat counts. The app handles matching (claiming), coordination (group messaging), follow-up (completion reminders, reviews), and community health (leaderboards, town hall).

### Target users

- Suburban or semi-urban neighbors in a defined geographic community
- Adults who drive and/or need rides (airport runs, errands, appointments)
- People who want to exchange small favors (moving help, pet sitting, tool lending)
- The invite-only model targets existing social networks — neighbors who already know each other or are vouched for by someone who does

### Real-world use cases

1. **Airport ride**: A user posts a ride request for Thursday at 5:30am, pickup at home, destination SFO, 2 seats. A neighbor claims it. The app creates a conversation between them, sends a push notification, and prompts the poster to leave a review after completion.

2. **Moving help**: A user posts a favor: "Help moving boxes from garage to storage unit, couple of hours, Saturday morning." Another member claims it. Coordination happens via in-app messaging.

3. **Recurring errands**: A user regularly posts grocery-run rides. Over time their profile accumulates reviews and XP, visible on the leaderboard. Other members can see their track record before claiming.

4. **Community engagement**: Members post in the Town Hall about neighborhood events, vote on posts, comment with threaded replies.

---

## 2. Core Feature Breakdown (Deep Dive)

### 2.1 Authentication (Apple + Email)

**What it does**: Two authentication methods — Sign in with Apple (SIWA) and email/password. Both flow through Supabase Auth.

**Where it exists in the UI**: Welcome screen with "Sign in with Apple" button and "Sign up with Email" / "Log in" options.

**User flow — Email signup**:
1. User enters email, password (min 8 chars, strength-validated), confirm password, name (min 2 chars), optional car description
2. System validates invite code (if provided) or proceeds with public signup
3. Supabase auth user created via `signUp(email:password:)`
4. Profile created either by database trigger (`handle_new_user` for invite-based) or by `create_signup_profile` RPC (for public signup)
5. Invite code marked as used if applicable
6. User redirected to application form

**User flow — Apple Sign In**:
1. User taps "Sign in with Apple" — system presents Apple auth sheet
2. Apple provides identity token (JWT), optional name, optional email (may be private relay)
3. Token exchanged with Supabase via `signInWithIdToken()` with nonce
4. Apple user identifier stored in Keychain (`com.naarscars.apple`, `kSecAttrAccessibleAfterFirstUnlock`)
5. Profile created/updated with Apple-provided name (or "Apple User" fallback)
6. If no existing account found: `.noAccountFound` returned, auth user cleaned up

**Backend interactions**:
- Supabase Auth: user creation, session management, token refresh
- Supabase RPC: `create_signup_profile` (SECURITY DEFINER), `link_apple_identity`, `unlink_apple_identity`
- Edge Function: `revoke-apple-token` (for account deletion/unlinking)
- Keychain: Apple user identifier storage

**Data models**: `Profile` (all user fields), `AuthState` enum (`.loading`, `.unauthenticated`, `.needsApplication`, `.pendingApproval`, `.authenticated`)

**Edge cases / failure states**:
- Apple private relay email: displayed as "Private Email (via Apple)" — not used for login recovery
- Orphaned auth user: if profile creation fails after auth user creation, `cleanupOrphanedAuthUser()` RPC called (best-effort)
- Rate limiting: 2s minimum between login attempts, 3s between invite code validations
- Email enumeration prevention: password reset always shows success regardless of whether email exists
- SIWA login with no account: server auth user created then cleaned up, returns `.noAccountFound`

---

### 2.2 Invite / Approval System

**What it does**: Gate-keeps community membership. New users need either an invite code from an existing member or go through a public application that requires admin approval.

**Where it exists in the UI**: Signup flow (invite code entry), `InvitationWorkflowView` (code generation), `PendingApprovalView` (waiting screen), Admin panel (approval queue).

**User flow — Invite-based signup**:
1. Existing member generates invite code via `InvitationWorkflowView`
2. Member provides an "invite statement" explaining who they're inviting and why (max 500 chars)
3. System generates code: `"NC" + 8 random alphanumeric chars` (charset excludes confusable characters: 0/O, 1/I/L)
4. Code shared via clipboard or iOS share sheet
5. New user enters code during signup — validated against `invite_codes` table
6. Code marked as used (`used_by`, `used_at` set)

**Invite code types**:
- **Single-use**: Generated by any member. Never expires. One use only. Limited to one active code per user.
- **Bulk (admin-only)**: Multiple uses. Expires in 48 hours. When used, creates a tracking record referencing the original code.

**Approval flow**:
1. After signup, user state is `needsApplication` (`applicationComplete = false`)
2. User completes mandatory application: "How did you hear about Naar's Cars?" + "Why would you like to join?"
3. State transitions to `pendingApproval` (`applicationComplete = true`, `approved = false`)
4. `PendingApprovalView` shown — polls every 30 seconds for approval, offers manual refresh and sign-out
5. Admin reviews application in admin panel, sets `approved = true`
6. Next poll detects approval, transitions to `.authenticated`

**Backend interactions**:
- `invite_codes` table: code storage, validation, usage tracking
- `InviteService`: code generation (3 collision retries), validation, marking used
- `AdminService.approveUser()` / `AdminService.rejectUser()`: admin approval

**Data models**: `InviteCode` (code, createdBy, usedBy, usedAt, inviteStatement, isBulk, expiresAt, bulkCodeId)

**Edge cases**:
- Deep link support: `https://naarscars.com/signup?code=CODE` pre-fills invite code
- Expired bulk codes: checked on validation, same error as "not found" (prevents enumeration)
- User with no invite code: goes through public signup, still requires admin approval
- Concurrent code generation: collision check with 3 retries

---

### 2.3 Profiles (Public + Private Fields)

**What it does**: User identity, preferences, and community reputation.

**Where it exists in the UI**: `MyProfileView` (own profile), `PublicProfileView` (others), `EditProfileView` (editing), `SettingsView` (preferences).

**Public fields** (visible to other approved members):
- `name` (required, real name)
- `avatarUrl` (profile picture)
- `car` (optional vehicle description)
- Reviews received (rating, comment, image)
- Leaderboard stats (XP, badges, streak)

**Private/restricted fields**:
- `email` — visible on own profile only; Apple private relay shows "Private Email (via Apple)"
- `phoneNumber` — masked by default (`(***) ***-4321`); auto-revealed to conversation partners and same-request participants
- `heardAbout`, `joinReason` — visible to admins during approval only
- `isAdmin` — system field
- Notification preferences — personal settings

**Profile editing**: Name, phone (with visibility disclosure + confirmation), car description, avatar (via PhotosUI picker, compressed before upload).

**Data model**: `Profile` struct — 25+ fields including identity, approval state, notification preferences, community engagement, timestamps.

---

### 2.4 Rides

**What it does**: Structured ride requests with location, date/time, seats, and optional flight code detection.

**Where it exists in the UI**: Rides tab (dashboard with list/map toggle), `CreateRideView`, `RideDetailView`, `EditRideView`.

**User flow — Creating a ride**:
1. Tap "+" FAB on rides dashboard
2. Fill form: date (DatePicker), time (custom 12-hour picker), timezone, pickup location (autocomplete), destination (autocomplete), seats (1-7 stepper), notes (free text), gift/thank-you (free text)
3. Optionally add up to 5 co-requestors via `UserSearchView` modal
4. Submit — ride created with status `open`
5. **Async enrichment** (non-blocking, after creation):
   - MapKit route calculation → `estimatedCost` saved
   - Regex flight code parsing from notes → `flightNormalized` saved (e.g., "DL123")

**User flow — Claiming a ride**:
1. Browse rides dashboard (filters: All, Mine, Claimed)
2. Tap ride card → `RideDetailView`
3. Tap "Claim" → `ClaimSheet` confirmation
4. **Prerequisite**: User must have phone number on profile (prompted via `PhoneRequiredSheet` if missing)
5. Rate limited: 10s minimum between claim operations
6. Status transitions: `open` → `confirmed`, `claimedBy` set
7. Push notification + in-app notification sent to poster
8. Calendar offer prompt shown to claimer

**Status lifecycle**: `open` → (claim) → `confirmed` → (complete by poster) → `completed` → (optional review prompt). Unclaim: `confirmed` → `open`.

**Backend interactions**:
- `RideService`: CRUD, Q&A, participants, batch profile fetching
- `ClaimService`: claim/unclaim/complete with notifications
- `rides` table, `ride_participants` table, `request_qa` table

**Data model**: `Ride` — 20+ fields including route, timing, status, claim state, review tracking, enrichment data (cost, flight code).

**Edge cases**:
- Past dates rejected in creation/editing
- Q&A disabled once ride is claimed (questions only while `open`)
- Cost estimation retries up to 3x with exponential backoff
- Participants capped at 5

---

### 2.5 Favors

**What it does**: Structured favor requests with flexible timing and duration categories.

**Where it exists in the UI**: Favors tab (dashboard with list/map toggle), `CreateFavorView`, `FavorDetailView`.

**User flow — Creating a favor**:
1. Tap "+" FAB on favors dashboard
2. Fill form: title (required), description, location (autocomplete, required), duration (enum picker), date (required), time (optional toggle), timezone, requirements, gift
3. Optionally add up to 5 participants
4. Submit — favor created with status `open`

**Key differences from rides**:
- Single location (not route-based pickup/destination)
- Duration is categorical: "Under an hour", "A couple of hours", "A couple of days", "Not sure"
- Time is truly optional (toggle-controlled)
- No cost estimation or flight code parsing
- Has `title` field (rides infer context from route)

**Data model**: `Favor` — similar structure to Ride with `title`, `description`, `requirements`, `duration` (enum) instead of route fields.

**Backend interactions**: Mirror of ride services — `FavorService` for CRUD, shared `ClaimService` for claiming, shared `request_qa` table for Q&A.

---

### 2.6 Messaging (1:1 + Group)

**What it does**: Real-time messaging with text, images, audio, location sharing, reactions, read receipts, typing indicators, message editing, and unsend.

**Where it exists in the UI**: Messages tab (conversation list), `ConversationDetailView` (thread view, backed by UIKit `MessagesCollectionView` for performance).

**Supported content types**:
- Text (max 5000 chars)
- Images (compressed to 1920px max, 0.7 JPEG quality, stored in `message-images` bucket)
- Audio (M4A format from in-app recorder, stored in `audio-messages` bucket)
- Location (lat/lon + optional name, shared in real-time)
- System messages (member added/removed/left, group created/renamed)
- Links (detected client-side via `NSDataDetector`)

**Optimistic send pipeline**:
1. Validate text length
2. Compress image off-main-thread (if present), capture dimensions
3. Save compressed file to `LocalAttachmentStorage` temp cache
4. Create optimistic `Message` with `sendStatus = .sending`, insert into SwiftData
5. UI shows message immediately (pending indicator)
6. Upload media to Supabase Storage (if present)
7. Send message to Supabase via `MessageService.sendMessage()`
8. On success: replace optimistic message with server-confirmed version (`sendStatus = .sent`)
9. On failure: mark `sendStatus = .failed`, `syncError = error text`, retain local attachment for retry

**Durable send worker** (`MessageSendWorker`):
- Actor that monitors SwiftData for `status = "sending"` messages
- Exponential backoff retry: 1s initial, 30s max, 5 attempts
- Watches network reachability, resumes on reconnect
- Re-uploads local attachments if needed
- Started by `MessagingSyncEngine.startSync()`

**Message editing**: Optimistic text update → `MessageService.updateMessageContent()` sets `edited_at` → rollback on failure.

**Message unsend**: Soft delete — clears text, sets `deleted_at`. 15-minute time window (`canUnsend` check). Rollback on failure.

**Read receipts**: `readBy: [UUID]` array on messages. Batch-marked via `mark_messages_read_batch` RPC. Throttled `last_seen` updates. User can disable per-conversation via `showReadReceipts` preference.

**Typing indicators**: Debounced (150ms initial delay), throttled signaling, auto-clear after 5s idle, manual clear on send. Server-side `typing_indicators` table with realtime subscription.

**Realtime delivery**: `MessagingSyncEngine` subscribes to `messages` table. Payload parsed via `RealtimePayloadAdapter`. All callbacks marshalled to `@MainActor`. Blocked users' messages silently dropped. Distinguishes metadata-only changes (readBy) from content changes to minimize UI rebuilds.

**Search**: ILIKE-based full-text search within conversations (50 results) and globally across all user's conversations (30 results). Special character escaping for `\`, `%`, `_`.

**Pagination**: Initial load 25 messages, load-older via `beforeMessageId` cursor (by `created_at` timestamp). History boundary at participant's `joinedAt`.

**Data models**: `Message` (30+ fields), `Conversation` (metadata + participants), `ConversationParticipant` (join/leave, mute, read receipts), `MessageReaction`, `ReplyContext`.

**Edge cases**:
- Media uploads must complete before send is committed
- Failed sends remain recoverable (user can retry)
- Blocked user reply contexts replaced with localized placeholder
- Group conversations hidden only if ALL other participants are blocked
- Conversation unhidden automatically when new message arrives from non-blocked sender

---

### 2.7 Reactions / Emojis

**What it does**: iMessage-style tapback reactions on messages.

**Where it exists in the UI**: Long-press on message bubble → reaction picker. Reaction badges rendered at the **top** of the message bubble.

**Standard tapbacks**: `["heart", "thumbsup", "thumbsdown", "laughing", "exclamation", "question"]` — rendered as `["❤️", "👍", "👎", "😂", "‼️", "❓"]`.

**Invariant**: `individualReactions: [MessageReaction]` is the single source of truth. `reactions: MessageReactions` (aggregated map of emoji → user IDs) is always derived. The ONLY valid mutation path is `Message.setIndividualReactions(_:)`.

**Add reaction flow**:
1. Optimistic: update local `individualReactions` (remove old reaction if any, add new)
2. UI updates immediately
3. Server: `MessageReactionService.addReaction()` upserts `message_reactions` table
4. On failure: rollback via `setIndividualReactions(previousIndividual)`

**Remove reaction**: Same pattern — optimistic local removal → server delete → rollback on failure.

**Data model**: `MessageReaction` (id, messageId, userId, reaction string, createdAt). `MessageReactions` (aggregated: `reactions: [String: [UUID]]` with sort/count helpers).

---

### 2.8 Reviews / Ratings

**What it does**: Post-completion reviews between request posters and fulfillers.

**Where it exists in the UI**: `ReviewPromptSheet` (shown after marking request complete), `LeaveReviewView` (review form), `ReviewsSheet` (list on profile), `ReviewRowView` / `ReviewCard` (display components).

**User flow**:
1. Poster marks ride/favor as "Complete" via `CompleteSheet`
2. `ReviewPromptSheet` appears (non-dismissible initial prompt)
3. Options: "Leave Review" or "Skip"
4. If reviewing: 1-5 star rating (required), optional text comment, optional image (compressed)
5. Submit: creates `Review` record, marks request `reviewed = true`
6. **Side effect**: Database trigger `handle_new_review` auto-creates Town Hall post of type `.review`
7. Review notifications cleared

**Skip flow**: Sets `review_skipped = true` and `review_skipped_at` timestamp. No time limit on going back to review later.

**Data model**: `Review` (id, reviewerId, fulfillerId, rideId/favorId, rating 1-5, comment, imageUrl, createdAt, joined names).

**Backend**: `ReviewService.createReview()` — image compressed (1200px max, 500KB), uploaded to `review-images` bucket.

---

### 2.9 Notifications

**What it does**: Integrated push notifications, in-app notification list, badge counts, deep link routing.

**Where it exists in the UI**: Bell icon (notification list), tab badges, app icon badge, push banners/alerts, in-app toasts.

**Notification types** (18 distinct types across 6 categories):
- **Messages**: `message`, `addedToConversation`
- **Rides**: `newRide`, `rideUpdate`, `rideClaimed`, `rideUnclaimed`, `rideCompleted`
- **Favors**: `newFavor`, `favorUpdate`, `favorClaimed`, `favorUnclaimed`, `favorCompleted`
- **Completion**: `completionReminder` (1-hour post-claim)
- **Q&A**: `qaActivity`, `qaQuestion`, `qaAnswer`
- **Reviews**: `review`, `reviewReceived`, `reviewReminder`, `reviewRequest`
- **Town Hall**: `townHallPost`, `townHallComment`, `townHallReaction`
- **Admin**: `contentReported`, `pendingApproval`, `userApproved`, `userRejected`
- **Announcements**: `announcement`, `adminAnnouncement`, `broadcast`

**Push categories with actions**:
- `COMPLETION_REMINDER`: "Yes, Completed" / "No, Not Yet"
- `MESSAGE`: Quick-reply (text input) / Mark as Read
- `NEW_REQUEST`: View Details
- `REQUEST_CLAIMED`: Add to Calendar / View Details

**Badge count system** (`BadgeCountManager`):
- Authoritative: `get_badge_counts` RPC returns per-category counts
- Polling: 30s when Realtime connected, 90s when disconnected
- Debounced: 0.5s minimum refresh interval
- Tab badges: requests, messages, community, profile (admin: pending approvals)
- App icon badge: `totalUnread` via `UIApplication.shared.applicationIconBadgeNumber`
- Fallback: cached/zero values with staleness indicator on RPC failure

**Smart suppression**:
- Message push: skipped if recipient viewed conversation <60s ago, or conversation is muted, or sender sent >10 messages/minute
- Foreground push: message notifications suppressed when user is on Messages tab
- In-app: muted conversations suppress banners

**Deep link routing**: Push tap → `AppDelegate` → `DeepLinkParser` → `NavigationIntent` → `NavigationCoordinator.pendingIntent` → deferred navigation after overlay dismisses.

**User controls**: 5 toggleable preference categories (ride updates, messages, Q&A, review reminders, town hall). New requests and announcements are always on.

**Edge functions**:
- `send-notification`: Webhook-triggered, processes `notification_queue`, rate-limited (30/min/user), batch processing (100 at a time, 10 concurrent), APNs payload with badge + category
- `send-message-push`: `messages` table INSERT webhook, smart suppression, parallel recipient processing

---

### 2.10 Admin Functionality

**What it does**: User approval, report review, broadcast announcements, community analytics.

**Where it exists in the UI**: Admin panel (accessible to users where `isAdmin = true` on their profile). Defense-in-depth: client checks admin status, but RLS is the real security boundary.

**Capabilities**:
- **User management**: View pending users, approve/reject applications, view all members, promote/demote admin (with self-demotion prevention)
- **Report review**: View reports filtered by status (pending/resolved/dismissed), see report type badges (color-coded: red=harassment/scam, orange=spam, purple=inappropriate), view report count (multiple reporters), hide/restore/dismiss content
- **Broadcasts**: Send announcements to all approved users via `send_broadcast_notifications` RPC
- **Dashboard stats**: Fulfilled request count, total community savings, active rides/favors, breakdown by time period

**Security**: Non-admin users attempting admin operations are logged. `verifyAdminStatus()` makes fresh server check before each operation.

---

### 2.11 Blocking / Reporting

**What it does**: User-to-user blocking and content reporting with admin review workflow.

**Where it exists in the UI**: `PublicProfileView` menu (Block User), `ReportMessageSheet` (report + optional block from messages), `ReportContentSheet` (report posts, comments, rides, favors).

**Blocking behavior**:
- Messages from blocked users completely hidden (filtered at fetch and realtime layers)
- Conversations with all-blocked participants hidden from list
- Town Hall posts/comments from blocked users filtered out
- Typing indicators from blocked users filtered
- Reply contexts to blocked users' messages show localized placeholder
- Blocking is **unidirectional** — the blocked user is not notified and can still see the blocker's content (unless they also block)

**Reporting**:
- **Report types**: spam, harassment, inappropriate_content, scam, other
- **Reportable content**: messages, users, town hall posts, town hall comments, rides, favors
- **Flow**: Select reason → optional description → optional block → submit to `submit_report` RPC → status `pending` for admin review
- **Admin actions**: hide content (`content_hidden = true`), restore, dismiss

**Data model**: `blocked_users` table (blocker_id, blocked_id, reason, created_at). `reports` table (reporter_id, reported_*_id fields, report_type, description, status, admin_notes, content_hidden, report_count).

---

### 2.12 Settings

**Where it exists in the UI**: `SettingsView`, accessible from `MyProfileView`.

**Sections**:
- **Biometric Authentication**: Toggle Face ID/Touch ID, "Require on Launch" sub-toggle
- **Notification Settings**: Master push toggle + per-category toggles (see 2.9)
- **Account Linking**: Link/unlink Apple ID
- **Messaging Settings**: Send read receipts, show typing indicators, show link previews, auto-download media
- **Language**: System language selector
- **Appearance**: Theme mode (system/light/dark)
- **Privacy**: Blocked users management, crash reporting toggle
- **Debug** (DEBUG builds only): Notification diagnostics, test crash, performance instrumentation
- **About**: App name/version, community guidelines link, privacy policy link, terms of service link, contact support (mailto)

---

### 2.13 Account Deletion

**Where it exists in the UI**: Settings → Delete Account → confirmation dialog.

**Flow**:
1. User taps "Delete Account"
2. Confirmation dialog with warning
3. If Apple Sign-In linked: `revokeAppleAuthorization()` — presents Apple auth sheet for fresh authorization code → calls `revoke-apple-token` edge function → clears Keychain
4. Calls `delete_user_account(p_user_id)` RPC — cascade deletes all user data: profile, messages, conversations, rides, favors, reviews, blocks, reports, auth.users entry
5. Local cache invalidated
6. Session terminated

**Completeness**: Full cascade delete. Apple token revoked. Keychain cleared. This satisfies Apple's account deletion requirement.

---

### 2.14 Town Hall (Community Forum)

**What it does**: Community bulletin board with posts, threaded comments, and voting.

**Where it exists in the UI**: Community tab, `TownHallFeedView`, `TownHallPostCard`, `PostCommentsView`.

**Post types**: `user_post` (regular), `review` (auto-generated from reviews), `completion` (completion posts), `announcement` (admin broadcasts).

**User flow — Creating a post**:
1. Tap "+" on Town Hall feed
2. Enter content (max 500 chars), optional image
3. Rate limited: 30s between posts
4. Auto-generated title from first line of content

**Voting**: Upvote/downvote on posts and comments. Toggle: same vote again removes it. Different vote switches. UI: orange (upvoted), blue (downvoted).

**Comments**: Threaded/nested via `parentCommentId`. Top-level comments + replies. Comments also have voting.

**Filtering**: Posts/comments from blocked users hidden client-side.

**Data models**: `TownHallPost` (content, type, pinned, imageUrl, votes, commentCount), `TownHallComment` (content, nested replies, votes), `TownHallVote` (upvote/downvote on post or comment).

---

### 2.15 Leaderboard / Gamification

**What it does**: XP-based ranking with badges and streaks.

**Where it exists in the UI**: Leaderboard tab, `LeaderboardView`.

**Badge types** (6):
- Road Warrior (rides), Good Neighbor (favors), Streak Champion (consistency), Five Star (reviews), Big Saver (cost savings), Frequent Carbardian (general activity)

**Data model**: `LeaderboardEntry` (userId, name, xp, badges, streakWeeks, requestsFulfilled, requestsMade, rank).

**Periods**: This Month, This Quarter, This Year, All Time. 15-minute cache per period.

---

## 3. User Generated Content (UGC) Surfaces

### 3.1 Messages

| Aspect | Detail |
|--------|--------|
| **What users can input** | Text (5000 chars max), images, audio recordings, location pins |
| **What other users can see** | Full message content within conversation (only participants) |
| **Moderation** | Reportable via `ReportMessageSheet`. Admin can hide via report review. No automated content filtering. |
| **Reporting/blocking** | Yes — report with 5 categories + optional block. Blocked users' messages hidden. |
| **Risks** | Harassment via DM, unsolicited images/audio, spam. Mitigated by invite-only community + blocking + reporting. |

### 3.2 Ride Posts

| Aspect | Detail |
|--------|--------|
| **What users can input** | Pickup, destination, date, time, seats, notes (free text), gift (free text) |
| **What other users can see** | All fields visible to all approved members |
| **Moderation** | Reportable via `ReportContentSheet`. Admin can hide. No automated filtering. |
| **Reporting/blocking** | Yes — report rides with 5 categories. Blocked users' rides still visible (blocking filters messages/posts, not rides). |
| **Risks** | Inappropriate content in notes/gift fields. Location-based stalking risk (addresses visible). Mitigated by invite-only + approval. |

### 3.3 Favor Posts

| Aspect | Detail |
|--------|--------|
| **What users can input** | Title, description, location, duration, requirements, date, time, gift |
| **What other users can see** | All fields visible to all approved members |
| **Moderation** | Reportable. Admin can hide. No automated filtering. |
| **Risks** | Similar to rides. Title and description are fully free-text. |

### 3.4 Profiles

| Aspect | Detail |
|--------|--------|
| **What users can input** | Name, car description, phone number, avatar photo |
| **What other users can see** | Name, car, avatar. Phone masked until context reveals it. |
| **Moderation** | Users can be reported. No automated profile content filtering. |
| **Risks** | Offensive names or avatar images. Phone number exposure to conversation/request partners. |

### 3.5 Reviews

| Aspect | Detail |
|--------|--------|
| **What users can input** | 1-5 star rating, optional text comment, optional image |
| **What other users can see** | Rating, comment, image, reviewer name — visible on fulfiller's public profile |
| **Moderation** | Not directly reportable as standalone content (reportable via the associated request or user). Auto-posted to Town Hall where it IS reportable. |
| **Risks** | Vindictive reviews. No dispute/appeal mechanism for review recipients. |

### 3.6 Town Hall Posts & Comments

| Aspect | Detail |
|--------|--------|
| **What users can input** | Posts: content (500 chars), optional image. Comments: content. |
| **What other users can see** | Full content visible to all approved members |
| **Moderation** | Posts and comments individually reportable. Admin can hide. Blocked users' content filtered client-side. |
| **Risks** | Inflammatory posts, spam, pile-on via downvoting. |

### 3.7 Reactions

| Aspect | Detail |
|--------|--------|
| **What users can input** | One of 6 standard emoji reactions per message |
| **What other users can see** | Aggregated reaction counts + who reacted (in conversation) |
| **Moderation** | Not individually reportable. Removing reaction is self-service. |
| **Risks** | Minimal — limited to 6 predefined emojis. No custom text. |

### 3.8 Q&A on Requests

| Aspect | Detail |
|--------|--------|
| **What users can input** | Questions (any user) and answers (poster) on open rides/favors |
| **What other users can see** | All Q&A visible on request detail view |
| **Moderation** | Not directly reportable. Report the parent ride/favor instead. |
| **Risks** | Inappropriate questions. Limited by invite-only community. |

---

## 4. Full User Journey Maps

### 4.1 New User Onboarding (Cold Start to Full Access)

```
1. Receive invite code from existing member (or find signup link)
2. Open app → Welcome screen
3. Choose "Sign up with Email" or "Sign in with Apple"
4. [Email path] Enter: name, email, password, confirm password, optional car
   [Apple path] Tap Apple button → Apple auth sheet → name/email provided
5. If invite code: enter code → validated → profile created
   If no code: public signup → profile created via RPC
6. → Application screen (mandatory):
   "How did you hear about Naar's Cars?"
   "Why would you like to join?"
   Submit application
7. → Pending Approval screen:
   "We're reviewing your application"
   Polls every 30 seconds + manual refresh button
   Option to enable push notifications
   Sign out available
8. Admin approves application
9. → Community Guidelines acceptance (non-dismissible sheet):
   Must scroll to bottom to enable "Accept" button
   6 guidelines about respectful community behavior
10. → Full app access: Rides, Favors, Messages, Town Hall, Leaderboard tabs
```

### 4.2 Posting a Ride

```
1. Navigate to Rides tab
2. Tap "+" floating action button
3. Fill form:
   - Select date (DatePicker)
   - Select time (custom 12-hour picker)
   - Select timezone (TimeZonePicker)
   - Enter pickup location (LocationAutocompleteField)
   - Enter destination (LocationAutocompleteField)
   - Set seat count (1-7 stepper)
   - Enter notes (optional free text)
   - Enter gift/thank-you (optional free text)
   - Add participants (optional, max 5, via UserSearchView modal)
4. Tap Create
5. Validation: pickup and destination required, date not in past
6. Ride created with status "open"
7. Background: MapKit cost estimation + flight code parsing
8. Ride appears in dashboard for all members
9. Wait for someone to claim
```

### 4.3 Requesting a Favor

```
1. Navigate to Favors tab
2. Tap "+" floating action button
3. Fill form:
   - Enter title (required)
   - Enter description (optional)
   - Enter location (required, autocomplete)
   - Select duration: Under an hour / Couple hours / Couple days / Not sure
   - Select date (required)
   - Toggle time on/off → select time if on
   - Select timezone
   - Enter requirements (optional)
   - Enter gift (optional)
   - Add participants (optional, max 5)
4. Tap Create
5. Validation: title and location required, date not in past
6. Favor created with status "open"
7. Favor appears in dashboard for all members
```

### 4.4 Sending a Message

```
1. Navigate to Messages tab → conversation list
2. Tap existing conversation (or create new from ride/favor context)
3. Message input bar at bottom:
   - Type text → Send button appears when text or attachment ready
   - Tap camera icon → camera or photo picker
   - Tap mic icon → audio recorder
   - Tap location icon → share current location
4. Tap send:
   - Message appears immediately (optimistic, pending indicator)
   - Media uploaded in background
   - Server confirmation replaces optimistic message
   - If failure: message shows failed state, retry available
5. Other participants see message via realtime subscription
6. Read receipts update as recipients view the message
7. Typing indicators show while composing (debounced, auto-clear 5s)
```

### 4.5 Leaving a Review

```
1. Poster marks ride/favor as "Complete" via Complete button
2. ReviewPromptSheet appears immediately (non-dismissible initial)
3. Choose "Leave Review":
   - Select 1-5 star rating (required)
   - Enter comment (optional)
   - Attach image (optional, compressed)
4. Submit review
5. Review saved, request marked as "reviewed"
6. Auto-created Town Hall post of type "review"
7. Review visible on fulfiller's public profile

Alternative: "Skip" → marks review_skipped, can return later (no time limit)
```

### 4.6 Reporting or Blocking

**Reporting a message**:
```
1. Long-press or tap menu on message in conversation
2. Select "Report"
3. ReportMessageSheet appears:
   - Select reason: Spam / Harassment / Inappropriate Content / Scam / Other
   - Enter optional description
   - Toggle "Block this user" (optional)
4. Submit → report created with status "pending"
5. Admin reviews in admin panel
6. Admin can: hide content, restore, or dismiss report
```

**Blocking a user**:
```
1. Navigate to user's public profile (via avatar tap in conversation, ride, etc.)
2. Tap menu (ellipsis) → "Block User"
3. Confirmation dialog
4. Block created server-side → cached locally
5. All content from blocked user immediately filtered:
   - Messages hidden
   - Conversations hidden (if all other participants blocked)
   - Town Hall posts/comments filtered
   - Typing indicators filtered
   - Reply contexts show placeholder
```

---

## 5. Permissions & Data Usage

### 5.1 iOS Permissions Requested

| Permission | Info.plist Key | When Prompted | What For |
|-----------|---------------|---------------|----------|
| Camera | `NSCameraUsageDescription` | User taps camera in message/profile/post/review | Photos for messages, profile avatar, post images, review images |
| Photo Library | `NSPhotoLibraryUsageDescription` | User taps photo picker | Same surfaces as camera |
| Location (When In Use) | `NSLocationWhenInUseUsageDescription` | User taps location share in messaging | Real-time location sharing in messages |
| Microphone | `NSMicrophoneUsageDescription` | User taps audio record in messaging | Audio message recording |
| Calendar (Full Access) | `NSCalendarsFullAccessUsageDescription` | User accepts calendar offer after claiming ride/favor | Add confirmed requests to calendar with reminders |
| Face ID | `NSFaceIDUsageDescription` | User enables biometric lock in settings | App unlock (declared but implementation is partial) |
| Push Notifications | (system prompt) | After first claim or during onboarding | Push notifications for messages, requests, reminders |

### 5.2 Data Collected

| Data Category | Specific Data | Purpose | Stored Where | Linked to Identity |
|--------------|---------------|---------|--------------|-------------------|
| Contact Info | Name, email, phone | Account, coordination | Supabase (server) | Yes |
| User Content | Messages, posts, comments, reviews, Q&A | App functionality | Supabase + SwiftData (cache) | Yes |
| Photos/Videos | Profile avatar, message images, post images, review images | App functionality | Supabase Storage | Yes |
| Audio | Audio messages | App functionality | Supabase Storage | Yes |
| Location | Lat/lon (message shares only) | Location sharing | Supabase (in message record) | Yes |
| Identifiers | Device ID (UUID), push token | Push delivery, deduplication | Keychain (local) + Supabase | Yes |
| Diagnostics | Crash data, non-fatal errors | Crash reporting | Firebase Crashlytics | Yes (user ID set) |
| Usage Data | Screen views (Crashlytics breadcrumbs only) | Crash context | Firebase Crashlytics | No (crash context only) |

### 5.3 Data NOT Collected

- No IDFA / advertising identifier
- No cross-app tracking
- No analytics events (no Google Analytics, Amplitude, Mixpanel, etc.)
- No browsing history
- No contacts access
- No health data
- No financial data
- No precise location tracking (only point-in-time shares in messages)

### 5.4 Third-Party Data Sharing

| Third Party | What's Shared | Why |
|------------|---------------|-----|
| Supabase (backend) | All app data | Database, auth, storage, realtime |
| Apple (APNs) | Push tokens | Push notification delivery |
| Firebase (Crashlytics) | Crash reports, sanitized context | Crash diagnostics |

No data is sold. No data is used for advertising. No data is shared for tracking purposes.

### 5.5 App Store Privacy Label Mapping

| Privacy Label Category | Collected | Linked | Tracking |
|-----------------------|-----------|--------|----------|
| Contact Info (Name, Email, Phone) | Yes | Yes | No |
| User Content (Messages, Posts, Reviews) | Yes | Yes | No |
| Photos or Videos | Yes | Yes | No |
| Audio Data | Yes | Yes | No |
| Precise Location | Yes | Yes | No |
| Identifiers (Device ID) | Yes | Yes | No |
| Diagnostics (Crash Data) | Yes | Yes | No |

`NSPrivacyTracking = false`. No tracking domains declared.

---

## 6. Safety & Moderation Analysis

### 6.1 What Safeguards Exist

| Safeguard | Implementation | Effectiveness |
|-----------|---------------|---------------|
| **Invite-only access** | Invite codes + admin approval | Strong gatekeeper — limits community to vouched individuals |
| **User blocking** | Unidirectional, immediate content filtering across messages/posts/comments | Effective for individual user protection |
| **Content reporting** | 5 categories, optional description, admin review queue | Functional workflow, but depends on active admin |
| **Admin content hiding** | `content_hidden` flag on reported content | Effective once admin acts |
| **Phone number masking** | Default masked, revealed only in active request/conversation context | Good privacy protection |
| **Rate limiting** | Client-side: login (2s), invite validation (3s), claims (10s), messages (1s), posts (30s) | Prevents basic spam, but client-side only |
| **RLS (Row Level Security)** | Database-level access control on all tables | Strong — real security boundary |
| **Community guidelines** | Required acceptance before first use | Establishes behavioral expectations |
| **Real identity** | Real names required, no pseudonyms | Accountability through identity |

### 6.2 What is Missing

| Gap | Risk Level | Detail |
|-----|-----------|--------|
| **No automated content moderation** | Medium | No profanity filter, no image scanning (CSAM, nudity), no ML-based detection. All moderation is manual. |
| **No account suspension/banning** | Medium | Admin can reject pending users but cannot suspend approved accounts. A toxic approved user can only be managed through blocking (by individual users). |
| **No appeal mechanism** | Low-Medium | Users cannot appeal blocks, content hiding, or (theoretical) account actions. |
| **No server-side rate limiting** | Medium | All rate limiting is client-side. A modified client could bypass limits. |
| **No message content filtering** | Medium | No profanity or slur filtering on messages, posts, or any UGC surface. |
| **Unidirectional blocking gap** | Low | Blocked user can still see blocker's content (unless mutual block). This is standard behavior in most apps. |
| **Rides/favors not filtered by blocking** | Low | Blocking filters messages and Town Hall content, but rides and favors from blocked users may still appear on the dashboard. |
| **No automated escalation** | Low | Multiple reports on same content increment `report_count` but don't auto-hide. Requires admin action. |
| **Reviews not directly reportable** | Low | Must report via parent request or user profile. Auto-posted Town Hall version is reportable. |

### 6.3 Apple Guideline Risk Areas

**Guideline 1.2 (User Generated Content)**:
- The app has UGC on multiple surfaces (messages, rides, favors, posts, comments, reviews, Q&A)
- Blocking and reporting exist for most surfaces
- Missing: automated content moderation, user suspension mechanism
- Risk: Apple may ask about automated moderation capabilities

**Guideline 5.6.1 (User Safety)**:
- The app facilitates real-world meetings between users (rides, favors)
- Mitigated by: invite-only + admin approval + real names + reviews + community guidelines
- Missing: no in-app safety features for meetups (no location sharing for safety, no check-in system)

### 6.4 Abuse Scenarios

1. **Harassment via messaging**: User sends offensive messages to another. Mitigation: block + report. Gap: no automated detection.

2. **Fake ride requests for stalking**: User posts rides to learn another user's address/schedule. Mitigation: invite-only community limits reach. Gap: addresses are visible to all members.

3. **Review bombing**: User leaves vindictive 1-star reviews after disputes. Mitigation: reviews are tied to completed requests (must actually be the fulfiller). Gap: no dispute mechanism.

4. **Spam posts in Town Hall**: User floods community with posts. Mitigation: 30-second rate limit (client-side). Gap: server-side enforcement missing.

5. **Account takeover**: Compromised credentials used to impersonate user. Mitigation: Supabase session management, optional SIWA. Gap: no 2FA beyond SIWA, no session activity view.

---

## 7. Authentication & Identity Model

### 7.1 User Identification

- **Primary identifier**: UUID assigned by Supabase Auth at account creation
- **Display identity**: Real name (required), profile photo (optional)
- **Auth methods**: Email/password and/or Sign in with Apple (can link both)
- **Session**: Supabase JWT with automatic refresh

### 7.2 Identity Type: Real Identity

This is a **real-identity** platform. Users must provide their real name (validated only by minimum 2-character length). The invite-only + admin approval model creates social accountability — your inviter is associated with your account.

No pseudonym or anonymous mode exists. No username system. All UGC (messages, posts, reviews) is attributed to the user's real name and avatar.

### 7.3 Trust Model

- **Invite chain**: Every user is traceable to the member who invited them (`invitedBy` field)
- **Admin vetting**: Application reviewed before approval (heard_about, join_reason)
- **Reputation**: Reviews (1-5 stars), XP, badges, streak weeks
- **Phone verification**: Phone number required to claim requests (creates accountability for real-world meetups)

### 7.4 Impersonation / Fraud Risks

| Risk | Mitigation | Gap |
|------|-----------|-----|
| Fake identity at signup | Admin approval review | No ID verification beyond name/email |
| Compromised invite codes | Single-use codes, bulk codes expire in 48h | No code request-approval flow |
| Account sharing | No mitigation | No device limits or session monitoring |
| Impersonating another member | Real names + admin review | No name uniqueness enforcement |

---

## 8. Backend Architecture Overview

### 8.1 Services Used

| Service | Purpose | Critical? |
|---------|---------|-----------|
| **Supabase Auth** | User authentication, sessions, token management | Yes |
| **Supabase Database** (PostgreSQL) | All application data, RLS enforcement | Yes |
| **Supabase Storage** | Image/audio file storage (buckets: message-images, audio-messages, avatars, review-images, town-hall-images) | Yes |
| **Supabase Realtime** | Live message delivery, notification updates, typing indicators | Yes |
| **Supabase Edge Functions** | `send-notification` (push delivery), `send-message-push` (message push), `revoke-apple-token` (SIWA compliance) | Yes |
| **Supabase RPCs** | Complex operations: `delete_user_account`, `get_badge_counts`, `mark_messages_read_batch`, `create_signup_profile`, `link_apple_identity`, `block_user`, `submit_report`, etc. | Yes |
| **Apple APNs** | Push notification delivery | Yes |
| **Firebase Crashlytics** | Crash reporting (no analytics) | No (diagnostic only) |
| **MapKit** (Apple) | Route calculation for ride cost estimation | No (enrichment only) |

### 8.2 Realtime Systems

- **Message delivery**: Subscription on `messages` table → `RealtimePayloadAdapter` → `MessagingSyncEngine` → `MessagingRepository` → SwiftData → ViewModel → UI
- **Notification updates**: Subscription on `notifications` table → `NotificationPayloadMapper` → SwiftData
- **Typing indicators**: Subscription on `typing_indicators` table → `TypingIndicatorManager`
- **Dashboard sync**: `DashboardSyncEngine` for rides/favors, `TownHallSyncEngine` for posts

### 8.3 Data Flow (Client <-> Backend)

```
UI Layer (SwiftUI / UIKit)
    ↕
ViewModels (@MainActor, @Observable or ObservableObject)
    ↕
Services (protocol-abstracted singletons)
    ↕
Supabase SDK (supabase-swift)
    ↕ REST / Realtime WebSocket / Storage API
Supabase Backend (PostgreSQL + RLS + Edge Functions)
    ↕ Webhooks
Edge Functions (Deno/TypeScript)
    ↕ APNs
Apple Push Notification Service
```

### 8.4 Critical Dependencies

1. **Supabase availability**: Single point of failure for all server operations. No offline-first mode for reads (SwiftData cache provides stale data only).
2. **Realtime WebSocket**: If connection drops, message delivery falls back to polling-based sync. Badge counts fall back to 90s polling.
3. **APNs**: Push delivery depends on Apple infrastructure. Token cleanup handles stale tokens.
4. **Edge Functions**: Push notification delivery depends on edge function availability. Queue-based (retry on failure).

### 8.5 Failure Points

| Failure | Impact | Recovery |
|---------|--------|----------|
| Supabase down | App functional with cached data, no writes | SwiftData cache, retry on reconnect |
| Realtime disconnect | Messages delayed | Polling fallback, reconnect with backfill |
| Edge function failure | Push not delivered | Notification queue retries, badge count polling |
| Media upload failure | Message shows failed state | Retry with local attachment preserved |
| RPC failure | Operation fails | User sees error, can retry |
| Badge count RPC failure | Stale badges | Cached values with staleness indicator, exponential backoff retry |

---

## 9. Known Bugs, Race Conditions, or Risk Areas

### 9.1 Concurrency Issues

- **`TownHallSyncEngine` writes on MainActor**: Violates the project's own BackgroundSyncActor rule. May cause UI jank during sync of large post sets.
- **`@Observable` ViewModel init/deinit storms**: Partially mitigated by removing `@Observable` VMs from `.environment()` in sheets and tab views. Still a risk if new ViewModels are added with `@Observable` + environment injection.
- **Realtime callback threading**: All callbacks must be marshalled to `@MainActor`. The compiler does NOT automatically hop for plain closure callbacks. Files `RealtimeManager.swift`, `MessagingSyncEngine.swift`, `DashboardSyncEngine.swift`, `TownHallSyncEngine.swift` require explicit `MainActor.run {}` wrapping.

### 9.2 Realtime Sync Risks

- **Payload format variability**: Supabase Realtime payloads are not guaranteed to have consistent structure (`record`/`new` vs `data.record`/`data.new`). The `RealtimePayloadAdapter` handles known variants, but new payload shapes could cause silent parsing failures.
- **Optimistic + realtime deduplication**: When a user sends a message, both the optimistic local insert and the realtime server event arrive. Deduplication logic must handle this correctly to avoid duplicates.
- **Message ordering**: Messages are ordered by `created_at`. Clock skew between client and server could theoretically cause ordering issues.

### 9.3 Data Consistency Risks

- **AppState / AuthService desync**: `AppState` mirrors `AuthService` state via Combine publishers. If publishers fail or timing is wrong, the UI can show stale auth state.
- **Badge count divergence**: App icon badge, tab badges, and in-app unread counts are computed from the same RPC but applied at different times. Transient divergence is possible.
- **Reaction dual-write potential**: The invariant that `individualReactions` is the sole source of truth is enforced by convention (only mutate via `setIndividualReactions()`), not by access control. A code change that directly mutates `reactions` would create phantom reactions.
- **Invite code race condition**: Two users validating the same single-use code concurrently could both succeed at validation, but only one can mark it used (database constraint). The second user's signup would fail at the "mark as used" step after auth user creation, requiring orphan cleanup.

### 9.4 Security Concerns

- **Client-side rate limiting only**: All rate limits (login, claims, posts, messages) are enforced client-side. A modified client could bypass them. Server-side rate limiting is recommended for production.
- **XOR obfuscation for secrets**: `Secrets.swift` uses XOR obfuscation for Supabase URL and anon key. This is not encryption — a motivated attacker can extract the key from the binary. Supabase RLS is the real security boundary, so the anon key exposure risk is limited to the scope of RLS policies.
- **JWT decoding without verification**: Apple token payload is decoded without signature verification during account linking (justified: token already verified by `ASAuthorizationController`, but unusual).

---

## 10. App Store Compliance Risk Assessment

### Guideline 1.2 — User Generated Content

**Assessment**: **⚠️ Risk**

The app has extensive UGC surfaces (messages, rides, favors, posts, comments, reviews, Q&A). It provides:
- ✅ Blocking (user-to-user, immediate content filtering)
- ✅ Reporting (5 categories, all major content types, admin review)
- ✅ Admin moderation (hide/restore/dismiss workflow)
- ⚠️ No automated content filtering (no profanity filter, no image scanning)
- ⚠️ No user suspension mechanism for approved accounts

**Likely outcome**: Apple may accept given the invite-only + admin approval model provides a gatekeeping layer that most UGC apps lack. However, Apple could request evidence of a "mechanism to filter objectionable material." The manual admin moderation workflow may satisfy this, but automated content moderation would strengthen the case.

---

### Guideline 5.1 — Privacy

**Assessment**: **✅ Compliant**

- Privacy manifest (`PrivacyInfo.xcprivacy`) properly configured with all data types, no tracking declared
- All Info.plist usage description strings present and accurate
- No third-party tracking SDKs
- Firebase Crashlytics only (no analytics)
- Privacy policy required before submission (documents exist in `Legal/`)
- User data deletion fully functional
- Phone number masking by default

---

### Guideline 5.6.1 — User Safety (Apps facilitating real-world contact)

**Assessment**: **⚠️ Risk**

This app facilitates real-world meetings between users (rides to/from locations, in-person favors). Apple's guideline states apps that facilitate meetings must include "safety tips, mechanisms for contacting authorities, etc."

Current mitigations:
- ✅ Invite-only community (social vetting)
- ✅ Admin approval of all new members
- ✅ Real-name identity
- ✅ Blocking and reporting
- ✅ Review system creates accountability
- ⚠️ No explicit safety tips for meetups
- ⚠️ No emergency contact or authority-contact mechanism
- ⚠️ No location-based safety features (no check-in, no live tracking during ride)

**Recommendation**: Consider adding a safety tips section or help article accessible from ride/favor detail views.

---

### Sign in with Apple Requirements

**Assessment**: **✅ Compliant**

- SIWA fully implemented as a primary auth method
- Token revocation implemented via `revoke-apple-token` edge function (called during account deletion and unlinking)
- Apple user identifier stored in Keychain (not UserDefaults)
- Nonce-based security for token exchange
- Account linking/unlinking supported with guard against unlinking sole auth method
- Private relay email handled gracefully

---

### Account Deletion Requirements

**Assessment**: **✅ Compliant**

- Account deletion accessible from Settings (discoverable)
- Confirmation dialog before deletion
- Apple token revocation performed before data deletion
- Full cascade delete via `delete_user_account` RPC — profile, messages, conversations, rides, favors, reviews, blocks, reports, auth user all removed
- Local cache invalidated
- Session terminated

---

### Summary Table

| Guideline | Status | Notes |
|-----------|--------|-------|
| 1.2 UGC | ⚠️ Risk | Blocking + reporting exist. No automated moderation. Invite-only model may satisfy. |
| 5.1 Privacy | ✅ Compliant | Privacy manifest complete. No tracking. Data deletion works. |
| 5.6.1 Safety | ⚠️ Risk | Facilitates real-world meetings. No safety tips or emergency mechanisms. |
| SIWA | ✅ Compliant | Full implementation including token revocation. |
| Account Deletion | ✅ Compliant | Full cascade delete with Apple token revocation. |
| 2.1 App Completeness | ✅ Compliant | All features functional, no placeholder screens. |
| 3.1.1 In-App Purchase | N/A | No IAP, subscriptions, or payments. |
| 4.0 Design | ✅ Compliant | Standard iOS design patterns, accessibility support, Dynamic Type. |

---

## 11. Competitive Positioning

### App Store Category

**Social Networking** (primary) or **Lifestyle** (secondary)

### Comparable Apps

| App | Similarity | Key Difference |
|-----|-----------|----------------|
| **Nextdoor** | Neighborhood community, real identity | Naar's Cars is invite-only, focused on rides/favors (not general neighborhood discussion) |
| **HeyNeighbor** | Neighbor help exchange | Naar's Cars has structured requests, claiming, reviews |
| **TaskRabbit** | Favor/task marketplace | TaskRabbit is commercial (paid); Naar's Cars is mutual aid (no payments) |
| **Uber/Lyft** | Ride requests | Commercial ride-hailing; Naar's Cars is neighbor-to-neighbor, no fare |
| **Waze Carpool** | Community-based rides | Naar's Cars is broader (favors too) and invite-only |

### What Makes It Unique

1. **Invite-only + admin approval**: Strongest community trust model compared to any competitor
2. **Combined rides + favors**: Not just rides OR tasks — both in one community platform
3. **No payments**: Pure mutual aid — removes commercial friction and regulatory burden
4. **Gamification**: XP, badges, streaks, leaderboard create engagement loop
5. **Structured claiming**: Not just "who wants to help?" — formal claim/complete/review workflow
6. **Real-time messaging built-in**: Not relying on external messaging (unlike Nextdoor which uses basic DMs)

---

## 12. One-Paragraph "What This App Actually Does"

Naar's Cars is an invite-only iOS app where vetted neighbors post structured ride requests (airport runs, errands) and favor requests (moving help, pet sitting), and other community members voluntarily claim and fulfill them — no money changes hands. Every new user needs either an invite code from an existing member or must pass admin approval after submitting an application explaining who they are and why they want to join. Once inside, users coordinate through built-in real-time messaging (text, images, audio, location sharing), rate each other through post-completion reviews (1-5 stars), and participate in a community forum (Town Hall) with threaded comments and voting. The app runs entirely on Supabase (database, auth, realtime, storage, edge functions) with Firebase Crashlytics for diagnostics, uses no analytics or tracking, supports full account deletion with Apple token revocation, and handles push notifications with smart suppression, deep link routing, and actionable categories. The main App Store compliance risks are (1) lack of automated content moderation on UGC surfaces (mitigated by invite-only model) and (2) facilitating real-world meetups without explicit safety tips or emergency mechanisms.
