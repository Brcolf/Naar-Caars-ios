# NaarsCars iOS — Get-Well Plan (Codex 5.3 Execution Package)

> Produced 2026-02-09, refined 2026-02-10.
> Audience: Codex agents + human reviewers.
> Constraint: incremental, no big-bang rewrites, SwiftUI + SwiftData + Supabase stack unchanged.
> **Every file path, type, and function name below is grounded in the actual repo.**

---

## A) Repo-Grounded Seam Map

### A.1 BadgeCountManager + Badge RPC

| Item | Location |
|------|----------|
| **Singleton** | `NaarsCars/Core/Services/BadgeCountManager.swift` — `BadgeCountManager.shared` |
| **Published counts** | `requestsBadgeCount`, `messagesBadgeCount`, `communityBadgeCount`, `profileBadgeCount`, `adminPanelBadgeCount`, `bellBadgeCount`, `totalUnreadCount` (7 `@Published` properties) |
| **Primary RPC** | `get_badge_counts` — defined in `database/092_badge_counts_rpc.sql`, amended by `database/102_fix_badge_counts_and_conversation_rpc.sql` |
| **RPC call site** | `fetchBadgeCounts(includeDetails:)` → `supabase.rpc("get_badge_counts", params: …)` (lines ~442, ~532) |
| **Fallback computation** | `fetchFallbackBadgeCounts(userId:)` + 5 `calculate*BadgeCount()` helpers, each calling a different service |
| **Backoff** | `badgeRpcFailureCount`, `badgeRpcBackoffUntil`, `registerBadgeRpcFailure(_:)`, `shouldUseBadgeCountsRpc()` |
| **Nested types** | `BadgeTab`, `RequestCountDetail`, `ConversationCountDetail`, `BadgeCountsPayload` (private, `Decodable`) |
| **NSNotification** | Posts `.conversationUnreadCountsUpdated` (defined in `PushNotificationService.swift` line 706) |

**Downstream consumers (15 files):**
- **Views:** `MainTabView` (tab badges + clear on tab change), `BellButton` (bell overlay), `CommunityTabView`, `FavorDetailView`, `RideDetailView`, `DevNotificationTestView`
- **ViewModels:** `NotificationsListViewModel`, `RequestsDashboardViewModel`, `ConversationDetailViewModel`, `ConversationsListViewModel` (via `.conversationUnreadCountsUpdated`), `LeaveReviewViewModel`, `PendingUsersViewModel`
- **Services:** `PushNotificationService`, `ReviewPromptProvider`, `PromptSideEffects`

---

### A.2 RealtimeManager + Subscription Callbacks

| Item | Location |
|------|----------|
| **Singleton** | `NaarsCars/Core/Services/RealtimeManager.swift` — `RealtimeManager.shared` |
| **Callback typealias** | `RealtimeInsertCallback = (Any) -> Void`, `RealtimeUpdateCallback = (Any) -> Void`, `RealtimeDeleteCallback = (Any) -> Void` (lines 16-18) |
| **Actual payload types** | `Realtime.InsertAction`, `Realtime.UpdateAction`, `Realtime.DeleteAction` (Supabase `Realtime` module). Passed as `Any` through the typealias. |
| **Payload inner types** | `InsertAction.record: [String: AnyJSON]`, `UpdateAction.record/.oldRecord: [String: AnyJSON]`, `DeleteAction.oldRecord: [String: AnyJSON]` |
| **Subscribe method** | `subscribe(channelName:table:filter:onInsert:onUpdate:onDelete:) async` — creates `channel.postgresChange(InsertAction.self, …)` async streams, iterates with `for await action in stream`, calls `onInsert(action)` etc. (lines 141-200) |
| **Connection state** | `@Published private(set) var isConnected: Bool` |
| **Lifecycle** | `unsubscribe(channelName:removeConfig:)`, `unsubscribeAll(removeConfigs:)`, `refreshAuth(accessToken:)`, `resubscribeAll()`, background/foreground handlers |

**13 active subscriptions across 8 tables:**

| Channel | Table | Subscriber | File |
|---------|-------|-----------|------|
| `messages:sync` | `messages` | MessagingSyncEngine | `Core/Storage/MessagingSyncEngine.swift` |
| `rides:sync` | `rides` | DashboardSyncEngine | `Core/Storage/DashboardSyncEngine.swift` |
| `favors:sync` | `favors` | DashboardSyncEngine | `Core/Storage/DashboardSyncEngine.swift` |
| `notifications:sync` | `notifications` | DashboardSyncEngine | `Core/Storage/DashboardSyncEngine.swift` |
| `town-hall-posts` | `town_hall_posts` | TownHallSyncEngine | `Core/Storage/TownHallSyncEngine.swift` |
| `town-hall-comments` | `town_hall_comments` | TownHallSyncEngine | `Core/Storage/TownHallSyncEngine.swift` |
| `town-hall-votes` | `town_hall_votes` | TownHallSyncEngine | `Core/Storage/TownHallSyncEngine.swift` |
| `typing:{id}` | `typing_indicators` | TypingIndicatorManager | `Features/Messaging/ViewModels/TypingIndicatorManager.swift` |
| `requests-dashboard-rides` | `rides` | RequestsDashboardViewModel | `Features/Requests/ViewModels/RequestsDashboardViewModel.swift` |
| `requests-dashboard-favors` | `favors` | RequestsDashboardViewModel | `Features/Requests/ViewModels/RequestsDashboardViewModel.swift` |
| `requests-dashboard-notifications` | `notifications` | RequestsDashboardViewModel | `Features/Requests/ViewModels/RequestsDashboardViewModel.swift` |
| `notifications:all` | `notifications` | NotificationsListViewModel | `Features/Notifications/ViewModels/NotificationsListViewModel.swift` |
| `favors-dashboard` | `favors` | FavorsDashboardViewModel | `Features/Favors/ViewModels/FavorsDashboardViewModel.swift` |

---

### A.3 SyncEngines + Payload Parsing

| Engine | File | Payload Handling |
|--------|------|-----------------|
| **MessagingSyncEngine** | `Core/Storage/MessagingSyncEngine.swift` (154 LOC) | **Parses payloads directly** via `MessagingMapper.parseMessageFromPayload(_ payload: Any)`. Casts to `InsertAction`/`UpdateAction`/`DeleteAction`, extracts `.record`/`.oldRecord`. Also uses `shouldIgnoreReadByUpdate(record:oldRecord:)` which takes `[String: AnyJSON]`. |
| **DashboardSyncEngine** | `Core/Storage/DashboardSyncEngine.swift` (~310 LOC) | **Ignores payloads entirely** — `triggerRidesSync()`, `triggerFavorsSync()`, `triggerNotificationsSync()` do debounced full re-fetches from services. No inline parsing. |
| **TownHallSyncEngine** | `Core/Storage/TownHallSyncEngine.swift` | **Parses payloads directly** — `handlePostUpsert(_: Any)`, `handleCommentUpsert(_: Any)`, `handleVoteChange(_: Any)` etc. Casts to Action types, extracts records. |

**MessagingMapper** (`Core/Storage/MessagingMapper.swift`):
- `parseMessageFromPayload(_ payload: Any) -> Message?` — handles `InsertAction`, `UpdateAction`, `DeleteAction`, plus `[String: Any]` fallback (lines 86-170)
- `mapToSDConversation(_:participantIds:) -> SDConversation`
- `mapToSDMessage(_:isPending:) -> SDMessage`
- `mapToMessage(_:) -> Message` (SDMessage → Message)
- `mapToConversation(_:lastMessage:unreadCount:) -> Conversation` (SDConversation → Conversation)
- Private helpers: `normalizeValue(_:)`, `decodeAnyJSON(_:)`, `decodeAnyJSONMirror(_:)` — handle `AnyJSON` → native Swift type conversion via Mirror reflection

**MessagingRepository** (`Core/Storage/MessagingRepository.swift`):
- Consumed by: `ConversationsListViewModel`, `ConversationDetailViewModel`, `MessageSendWorker`, `MessagingSyncEngine`

---

### A.4 NotificationType / AppNotification + Routing

| Item | Location |
|------|----------|
| **NotificationType** | `Core/Models/AppNotification.swift` lines 11-132 — `enum NotificationType: String, Codable` with 30 cases |
| **AppNotification** | `Core/Models/AppNotification.swift` lines 135-202 — `struct AppNotification: Codable, Identifiable, Equatable, Sendable` |
| **DeepLink** | `Core/Utilities/DeepLinkParser.swift` — `enum DeepLink` with 14 cases: `ride(id:)`, `favor(id:)`, `conversation(id:)`, `profile(id:)`, `townHallPostComments(id:)`, `townHallPostHighlight(id:)`, `townHall`, `adminPanel`, `pendingUsers`, `dashboard`, `notifications`, `announcements(notificationId:)`, `enterApp`, `unknown` |
| **DeepLinkParser** | `Core/Utilities/DeepLinkParser.swift` — `struct DeepLinkParser` with `static func parse(userInfo:) -> DeepLink?` |
| **RequestNotificationMapping** | `Core/Utilities/RequestNotificationMapping.swift` (inferred from NotificationsListViewModel reference `RequestNotificationMapping.target(for:rideId:favorId:)`) |

**Push notification tap flow:**
1. `AppDelegate.userNotificationCenter(_:didReceive:)` → `DeepLinkParser.parse(userInfo:)` → `handleDeepLink(_:userInfo:)`
2. `handleDeepLink` posts string-based `NSNotification.Name` (e.g. `"navigateToRide"`, `"navigateToConversation"`)
3. `NavigationCoordinator.setupNotificationListeners()` observes all 11 navigation notification names, sets the matching `@Published` property
4. Views observe `@Published` properties via `.onChange(of:)` or `sheet(isPresented:)`

**In-app notification tap flow:**
1. `NotificationsListViewModel.handleNotificationTap(_:group:)` → marks read → posts `.dismissNotificationsSurface`
2. Sets `NavigationCoordinator.shared.pendingNotificationNavigation` (deferred intent)
3. `MainTabView` sheet `onDismiss` calls `coordinator.applyPendingNotificationNavigation()`
4. `applyPendingNotificationNavigation()` (lines 491-548) switches on `PendingNotificationNavigation`, sets the same `@Published` properties

---

### A.5 NavigationCoordinator + Deferred Navigation

| Item | Location |
|------|----------|
| **File** | `NaarsCars/App/NavigationCoordinator.swift` (~593 LOC) |
| **Singleton** | `NavigationCoordinator.shared` |
| **Published properties** | 20 total: `selectedTab`, `navigateToRide`, `navigateToFavor`, `requestNavigationTarget`, `requestListScrollKey`, `navigateToConversation`, `conversationScrollTarget`, `navigateToProfile`, `townHallNavigationTarget`, `navigateToAdminPanel`, `navigateToPendingUsers`, `navigateToNotifications`, `profileScrollTarget`, `announcementsNavigationTarget`, `showReviewPrompt`, `reviewPromptRideId`, `reviewPromptFavorId`, `pendingDeepLink`, `showDeepLinkConfirmation`, `pendingNotificationNavigation` |
| **Nested types** | `Tab` (4 cases), `ConversationScrollTarget`, `TownHallNavigationTarget`, `AnnouncementsNavigationTarget`, `PendingNotificationNavigation` (15 cases) |
| **Key methods** | `navigate(to:)`, `applyPendingDeepLink()`, `applyPendingNotificationNavigation()`, `consumeRequestNavigationTarget(for:requestId:)`, `resetNavigation()`, `showReviewPromptFor(rideId:favorId:)` |

**Downstream consumers:**
- `MainTabView` (tab selection, sheets, `.onChange` observers)
- `ContentView` (sign-out observation)
- `RequestsDashboardView` (ride/favor navigation targets, scroll keys)
- `ConversationsListView` (conversation navigation)
- `NotificationsListViewModel` (sets `pendingNotificationNavigation`)
- `SettingsView` (admin panel, pending users)

---

### A.6 SwiftData SD Models + Mappers

| Model | File | Fields (summary) |
|-------|------|-----------------|
| `SDConversation` | `Core/Storage/SDModels.swift` lines 14-43 | `id`, `title`, `groupImageUrl`, `createdBy`, `isArchived`, `createdAt`, `updatedAt`, `messages`, `participantIds`, `unreadCount` |
| `SDMessage` | `Core/Storage/SDModels.swift` lines 46-106 | `id`, `conversationId`, `fromId`, `text`, `imageUrl`, `readBy`, `createdAt`, `messageType`, `replyToId`, `audioUrl`, `audioDuration`, `latitude`, `longitude`, `locationName`, `editedAt`, `deletedAt`, `isPending`, `syncError`, `status`, `localAttachmentPath`, `conversation` |
| `SDRide` | `Core/Storage/SDModels.swift` lines 111-167 | `id`, `userId`, `type`, `date`, `time`, `pickup`, `destination`, `seats`, `notes`, `gift`, `status`, `claimedBy`, `reviewed`, `reviewSkipped`, `estimatedCost`, poster/claimer names/avatars, `participantIds`, `qaCount` |
| `SDFavor` | `Core/Storage/SDModels.swift` lines 170-224 | `id`, `userId`, `title`, `favorDescription`, `location`, `duration`, `requirements`, `date`, `time`, `gift`, `status`, `claimedBy`, `reviewed`, `reviewSkipped`, poster/claimer names/avatars, `participantIds`, `qaCount` |
| `SDNotification` | `Core/Storage/SDModels.swift` lines 227-261 | `id`, `userId`, `type`, `title`, `body`, `read`, `pinned`, `createdAt`, `rideId`, `favorId`, `conversationId`, `reviewId`, `townHallPostId`, `sourceUserId` |
| `SDTownHallPost` | `Core/Storage/SDModels.swift` lines 266-314 | `id`, `userId`, `title`, `content`, `imageUrl`, `pinned`, `type`, `reviewId`, `createdAt`, `updatedAt`, `authorName`, `authorAvatarUrl`, `commentCount` |
| `SDTownHallComment` | `Core/Storage/SDModels.swift` lines 317-351 | `id`, `postId`, `userId`, `parentCommentId`, `content`, `createdAt`, `updatedAt`, `authorName`, `authorAvatarUrl` |

---

### A.7 NSNotification.Name Constants (Cross-Module Comms)

| Constant | Defined In | Posted By | Observed By |
|----------|-----------|-----------|-------------|
| `"conversationUpdated"` | (inline string) | MessagingSyncEngine, MessagingRepository, MessageDetailsPopup | ConversationDetailViewModel, InAppToastManager |
| `.conversationUnreadCountsUpdated` | PushNotificationService.swift:706 | BadgeCountManager | ConversationsListViewModel |
| `.showReviewPrompt` | PushNotificationService.swift:703 | AppDelegate.postReviewPrompt | NavigationCoordinator |
| `.showCompletionPrompt` | PushNotificationService.swift:704 | AppDelegate.postCompletionPrompt | (completion prompt handling) |
| `.dismissNotificationsSurface` | PushNotificationService.swift:705 | NotificationsListViewModel | MainTabView (sheet dismiss) |
| `.messageThreadDidAppear` | InAppToastManager.swift:142 | ConversationDetailView | InAppToastManager |
| `.messageThreadDidDisappear` | InAppToastManager.swift:143 | ConversationDetailView | InAppToastManager |
| `.townHallPostVotesDidChange` | TownHallSyncEngine.swift:11 | TownHallSyncEngine | TownHallFeedViewModel |
| `.townHallCommentVotesDidChange` | TownHallSyncEngine.swift:12 | TownHallSyncEngine | PostCommentsView |
| `.languageDidChange` | LocalizationManager.swift:101 | LocalizationManager | (views) |
| `"navigateToRide"` | (inline string) | AppDelegate.handleDeepLink | NavigationCoordinator |
| `"navigateToFavor"` | (inline string) | AppDelegate.handleDeepLink | NavigationCoordinator |
| `"navigateToConversation"` | (inline string) | AppDelegate.handleDeepLink | NavigationCoordinator |
| `"navigateToProfile"` | (inline string) | AppDelegate.handleDeepLink | NavigationCoordinator |
| `"navigateToTownHall"` | (inline string) | AppDelegate.handleDeepLink | NavigationCoordinator |
| `"navigateToAdminPanel"` | (inline string) | AppDelegate.handleDeepLink | NavigationCoordinator |
| `"navigateToPendingUsers"` | (inline string) | AppDelegate.handleDeepLink | NavigationCoordinator |
| `"navigateToNotifications"` | (inline string) | AppDelegate.handleDeepLink | NavigationCoordinator |
| `"navigateToAnnouncements"` | (inline string) | AppDelegate.handleDeepLink | NavigationCoordinator |
| `"navigateToDashboard"` | (inline string) | AppDelegate.handleDeepLink | NavigationCoordinator |
| `"userDidSignOut"` | (inline string) | AuthService | ContentView |
| `"handleInviteCodeDeepLink"` | (inline string) | AppDelegate | InviteService |

---

## B) Phase 0 — Safety Net (Codex-Executable Checklist)

### Goal
Establish regression-catching tests for the most fragile seams *before* touching production code.

### CORRECTION vs. prior plan
The prior plan assumed 4 dictionary-based payload shapes (`{record:…}`, `{new:…}`, `{data:{record:…}}`, `{data:{new:…}}`). **In reality**, `RealtimeManager` passes typed Supabase structs (`InsertAction`, `UpdateAction`, `DeleteAction`) to callbacks. The dictionary shapes exist only as a fallback path in `MessagingMapper`. Phase 0 tests must cover the **real** types.

### Files to Create

```
NaarsCars/NaarsCarsTests/Core/Fixtures/
├── RealtimeFixtures.swift            # Sample InsertAction/UpdateAction/DeleteAction + dict fallbacks
├── WebhookFixtures.swift             # APNs payload shapes from send-message-push + send-notification
└── NotificationFixtures.swift        # All 30 NotificationType raw values + preference mappings

NaarsCars/NaarsCarsTests/Core/Decoding/
├── RealtimePayloadDecodingTests.swift
├── WebhookPayloadDecodingTests.swift
└── NotificationTypeDecodingTests.swift

NaarsCars/NaarsCarsTests/Core/Services/
├── BadgeCountManagerTests.swift
└── NavigationCoordinatorRoutingTests.swift
```

### Files to Modify
- **None.** Phase 0 adds only test files. No production code changes.

### Step-by-Step Tasks

**Step 1: Create `RealtimeFixtures.swift`**
- Define fixture dictionaries (`[String: AnyJSON]`) matching real column schemas for: `messages`, `rides`, `favors`, `notifications`, `town_hall_posts`
- The `AnyJSON` type comes from `import Supabase` — fixtures must use it since `InsertAction.record` is `[String: AnyJSON]`
- If `AnyJSON` cannot be easily constructed in tests (it may lack public initializers), define equivalent `[String: Any]` dictionaries and test the `[String: Any]` fallback path in `parseMessageFromPayload`. Add a note that the `InsertAction`/`UpdateAction`/`DeleteAction` code paths are covered by integration/smoke tests.
- Include at minimum:
  - `messageRecord: [String: Any]` with all fields from `MessagingMapper.parseMessageFromPayload` (id, conversation_id, from_id, text, message_type, read_by, created_at, image_url, reply_to_id, audio_url, audio_duration, latitude, longitude, location_name, edited_at, deleted_at)
  - `rideRecord`, `favorRecord`, `notificationRecord` with matching production column shapes
  - `deletePayload` with `old_record` shape

**Step 2: Create `NotificationFixtures.swift`**
- `static let allRawValues: [String]` containing all 30 raw values from `NotificationType`
- `static let mandatoryTypes: Set<String>` — types where `canBeDisabled == false`
- `static let preferenceMapping: [String: String?]` — expected `preferenceKey` for each type

**Step 3: Create `WebhookFixtures.swift`**
- `static let messagePushPayload: [String: Any]` matching the APNs shape from `send-message-push/index.ts`:
  ```
  { aps: { alert: { title, body }, sound, badge, priority, category: "MESSAGE" },
    type: "message", conversation_id, message_id, sender_id }
  ```
- `static let notificationPushPayload: [String: Any]` matching `send-notification/index.ts`:
  ```
  { aps: { alert: { title, body }, sound, badge, mutable-content, category },
    type: notificationType, ...payload_data }
  ```
- `static let resolveEventTypePayloads: [[String: Any]]` for testing `type`, `eventType`, `event_type`, `data.type` paths (mirrors `_shared/apns.ts` `resolveEventType()`)

**Step 4: Create `RealtimePayloadDecodingTests.swift`**
- Test `MessagingMapper.parseMessageFromPayload()` with dictionary fixture → verify all fields extracted correctly (id, conversationId, fromId, text, messageType, readBy, createdAt, imageUrl, replyToId, etc.)
- Test with minimal required fields only → verify non-nil return
- Test with missing required field (e.g. no `from_id`) → verify nil return
- Test date parsing: ISO8601 with fractional seconds, without fractional seconds, epoch number
- Test `readBy` parsing: empty array, array of UUID strings
- At least 8 test cases

**Step 5: Create `NotificationTypeDecodingTests.swift`**
- Round-trip: `NotificationType(rawValue: type.rawValue) == type` for all 30 cases
- `preferenceKey` returns expected column name for each case (reference `NotificationFixtures.preferenceMapping`)
- `canBeDisabled` returns `false` for mandatory types, `true` for others
- `icon` returns non-empty string for every case
- Unknown raw value → `nil` (not crash)
- At least 30 + 4 test cases

**Step 6: Create `WebhookPayloadDecodingTests.swift`**
- Test `DeepLinkParser.parse(userInfo:)` with message push userInfo → returns `.conversation(id:)`
- Test with ride notification userInfo → returns `.ride(id:)`
- Test with each notification type string → returns correct DeepLink case
- Test `resolveEventType` logic: payload with `type`, `eventType`, `event_type`, `data.type` keys
- At least 6 test cases

**Step 7: Create `BadgeCountManagerTests.swift`**
- Note: `BadgeCountManager` uses Supabase RPC internally. To test without network, test the **parsing** of a `BadgeCountsPayload` JSON string. Since `BadgeCountsPayload` is `private`, either:
  - (a) Extract a `static func parseBadgeCounts(from json: Data) -> BadgeCountsPayload?` helper and make it `internal` for testing, OR
  - (b) Test at the integration boundary: verify that after `refreshAllBadges()` with a mock/stub, published counts are correct.
  - **Recommended for Phase 0**: Option (b) is too invasive. Instead, create a pure helper test: decode a `BadgeCountsPayload`-shaped JSON string using `JSONDecoder`, verify all fields present. This requires making `BadgeCountsPayload` `internal` (one-word change: `private` → `internal`).
  - If even that is too invasive, skip direct parsing test and instead test the **public contract**: `totalUnreadCount == requestsBadgeCount + messagesBadgeCount + communityBadgeCount + bellBadgeCount` after manually setting published values.
- Test backoff logic: `shouldUseBadgeCountsRpc()` returns `true` after `resetBadgeRpcBackoff()`, returns `false` after `registerBadgeRpcFailure()` within backoff window.
  - Same visibility concern: these are `private`. **Recommendation**: Skip internal state tests in Phase 0. Focus on the public observable contract. Add a simple test: verify `totalUnreadCount` published value equals sum of component counts (the reduction logic).

**Step 8: Create `NavigationCoordinatorRoutingTests.swift`**
- Test `PendingNotificationNavigation` → expected tab. Build a mapping table:
  - `.ride(id)` → tab = `.requests`
  - `.favor(id)` → tab = `.requests`
  - `.conversation(id)` → tab = `.messages`
  - `.townHallComments(id)` → tab = `.community`
  - `.pendingUsers` → tab = `.profile`
  - etc.
- Test `resetNavigation()` clears: `navigateToRide == nil`, `navigateToFavor == nil`, `navigateToConversation == nil`, `navigateToProfile == nil`, `navigateToAdminPanel == false`, `navigateToPendingUsers == false`, `navigateToNotifications == false`, `pendingNotificationNavigation == nil`
- Test `DeepLink` → `PendingNotificationNavigation` round-trip where applicable
- At least 15 test cases

### Regression Checklist (Manual Smoke)
After all tests pass, manually verify (on simulator):
- [ ] Send a message → appears in conversation within ~1s
- [ ] Claim a ride → status changes on poster's dashboard
- [ ] Unclaim a ride → status reverts
- [ ] Mark conversation as read → badge count on Messages tab decrements
- [ ] Tap a push notification → navigates to correct tab + detail screen
- [ ] Open bell → tap a ride notification → bell dismisses, ride detail opens

### Done Criteria
- [ ] `xcodebuild test -scheme NaarsCars -destination 'platform=iOS Simulator,name=iPhone 16'` passes with 0 failures
- [ ] All 30 `NotificationType` cases have round-trip decode tests
- [ ] Message payload parsing tested with all required + optional fields
- [ ] Deep link routing tested for all `DeepLink` cases
- [ ] `git diff --stat` shows **only new files** in `NaarsCarsTests/` — zero production code changes
- [ ] **User must add test files to Xcode project manually** (per project rules: do not edit `project.pbxproj`)

### Rollback Plan
`git revert` the Phase 0 commit. No production code was changed, so revert is zero-risk.

---

## C) Phase 1 — Realtime Payload Adapter (Canonical Internal Representation)

### C.1 Real Incoming Payload Types

The **actual** types arriving in callbacks are **not** raw dictionaries. Here is the real flow:

```
RealtimeManager.swift line 141:
  let insertStream = channel.postgresChange(InsertAction.self, schema: "public", table: table, filter: filter)

RealtimeManager.swift line 181:
  for await action in insertStream {
      onInsert(action)   // action is InsertAction, passed as Any via typealias
  }
```

**Types (from Supabase `Realtime` module):**

| Type | `.record` | `.oldRecord` | Used for |
|------|----------|-------------|---------|
| `Realtime.InsertAction` | `[String: AnyJSON]` | — | INSERT events |
| `Realtime.UpdateAction` | `[String: AnyJSON]` | `[String: AnyJSON]` | UPDATE events |
| `Realtime.DeleteAction` | — | `[String: AnyJSON]` | DELETE events |

**Where parsing happens today:**

| File | Function | What it does |
|------|---------|-------------|
| `Core/Storage/MessagingMapper.swift:86` | `parseMessageFromPayload(_ payload: Any)` | Casts to `InsertAction`/`UpdateAction`/`DeleteAction`, extracts `.record`/`.oldRecord`, then field-by-field dictionary parsing with `normalizeValue()` → `decodeAnyJSON()` via Mirror reflection |
| `Core/Storage/MessagingSyncEngine.swift:128` | `shouldIgnoreReadByUpdate(record:oldRecord:)` | Takes `[String: AnyJSON]` directly from `UpdateAction` |
| `Features/Requests/ViewModels/RequestsDashboardViewModel.swift:~667` | `handleRideRealtimePayload(_:event:reason:)` | Casts to `InsertAction`/`UpdateAction`/`DeleteAction`, extracts record |
| `Features/Notifications/ViewModels/NotificationsListViewModel.swift:~581` | `handleRealtimePayload(_:reason:)` | Casts to `InsertAction`, extracts record |
| `Core/Storage/TownHallSyncEngine.swift` | `handlePostUpsert(_:)`, `handleCommentUpsert(_:)`, `handleVoteChange(_:)` | Same casting pattern |

### C.2 Canonical Internal Struct

```swift
/// Canonical representation of a decoded Supabase Realtime event.
/// All subscribers receive this instead of raw `Any` / Action types.
struct RealtimeRecord {
    enum EventType { case insert, update, delete }

    let table: String
    let eventType: EventType
    let record: [String: Any]       // Normalized from [String: AnyJSON]
    let oldRecord: [String: Any]?   // For updates/deletes
}
```

**Key design decision:** `.record` is `[String: Any]` (not `[String: AnyJSON]`), meaning the adapter also normalizes `AnyJSON` → native Swift types using the existing `MessagingMapper.normalizeValue()` / `decodeAnyJSON()` logic. This eliminates Mirror-reflection parsing from every downstream consumer.

### C.3 Adapter API

**File to create:** `NaarsCars/Core/Realtime/RealtimePayloadAdapter.swift`

```swift
//
//  RealtimePayloadAdapter.swift
//  NaarsCars
//
//  Normalizes Supabase Realtime Action types into flat [String: Any] records

import Foundation
import Realtime

/// Decodes Supabase Realtime Action payloads into a canonical `RealtimeRecord`.
///
/// Before Phase 1: each subscriber casts `Any` → `InsertAction`/`UpdateAction`/`DeleteAction`,
/// then manually extracts and normalizes `.record` dictionaries.
///
/// After Phase 1: `RealtimeManager` calls this adapter once; subscribers receive `RealtimeRecord`.
enum RealtimePayloadAdapter {

    /// Decode an insert event payload.
    /// - Parameters:
    ///   - payload: The `Any` from `RealtimeInsertCallback`
    ///   - table: The table name for this subscription
    /// - Returns: A `RealtimeRecord` with `.insert` event type, or nil
    static func decodeInsert(_ payload: Any, table: String) -> RealtimeRecord?

    /// Decode an update event payload.
    static func decodeUpdate(_ payload: Any, table: String) -> RealtimeRecord?

    /// Decode a delete event payload.
    static func decodeDelete(_ payload: Any, table: String) -> RealtimeRecord?

    /// Normalize a `[String: AnyJSON]` dictionary into `[String: Any]`.
    /// Uses the existing `MessagingMapper` decode helpers.
    static func normalizeRecord(_ record: [String: AnyJSON]) -> [String: Any]
}
```

**Where it lives:** `NaarsCars/Core/Realtime/RealtimePayloadAdapter.swift` (new directory `Core/Realtime/`).

### C.4 Call Sites to Update

| # | File | Current | After |
|---|------|---------|-------|
| 1 | `Core/Services/RealtimeManager.swift` | `onInsert(action)` where action is `InsertAction` | `onInsert(RealtimePayloadAdapter.decodeInsert(action, table: table))` — OR change callback type to `((RealtimeRecord) -> Void)?` and decode before calling |
| 2 | `Core/Storage/MessagingSyncEngine.swift` | `handleIncomingMessage(_ payload: Any, event:)` — casts payload to Action types | `handleIncomingMessage(_ record: RealtimeRecord)` — receives pre-decoded record |
| 3 | `Core/Storage/MessagingMapper.swift` | `parseMessageFromPayload(_ payload: Any)` — handles Action types + dict fallback | `parseMessage(from record: [String: Any])` — takes pre-normalized dict, removes Action-type casting logic |
| 4 | `Core/Storage/TownHallSyncEngine.swift` | `handlePostUpsert(_ payload: Any)` etc. — casts to Action types | `handlePostUpsert(_ record: RealtimeRecord)` — receives pre-decoded |
| 5 | `Features/Requests/ViewModels/RequestsDashboardViewModel.swift` | `handleRideRealtimePayload(_ payload: Any, …)` — casts to Action types | `handleRideRealtimeEvent(_ record: RealtimeRecord, …)` — receives pre-decoded |
| 6 | `Features/Notifications/ViewModels/NotificationsListViewModel.swift` | `handleRealtimePayload(_ payload: Any, …)` — casts to InsertAction | `handleRealtimeEvent(_ record: RealtimeRecord, …)` |
| 7 | `Features/Favors/ViewModels/FavorsDashboardViewModel.swift` | `handleFavorInsert(_:)` etc. | Receive `RealtimeRecord` |
| 8 | `Features/Rides/ViewModels/RidesDashboardViewModel.swift` | `handleRideInsert(_:)` etc. | Receive `RealtimeRecord` |

**Two implementation strategies** (choose one):

**Strategy A — Decode in RealtimeManager (recommended):**
Change typealias from `(Any) -> Void` to `(RealtimeRecord) -> Void`. Decode inside the `for await` loop. All subscribers get pre-decoded records. Smaller diff at each subscriber.

**Strategy B — Decode at each call site:**
Keep `(Any) -> Void` typealias. Each subscriber calls `RealtimePayloadAdapter.decodeInsert(payload, table:)`. Smaller change to RealtimeManager, but repeated at every call site.

**Recommendation: Strategy A.** It's a single change in `RealtimeManager` and eliminates the most code across subscribers.

### C.5 Extracting `normalizeValue` / `decodeAnyJSON` from MessagingMapper

Today these are `private static` on `MessagingMapper`. Phase 1 must move them (or copy them) to `RealtimePayloadAdapter.normalizeRecord()`. Preferred approach: move to `RealtimePayloadAdapter` as `internal static`, then have `MessagingMapper` call `RealtimePayloadAdapter.normalizeRecord()` for any remaining uses.

### C.6 Done Criteria
- [ ] `xcodebuild build` succeeds with 0 errors, 0 new warnings
- [ ] All Phase 0 tests still pass
- [ ] New tests for `RealtimePayloadAdapter.decodeInsert/Update/Delete` pass
- [ ] No `InsertAction`/`UpdateAction`/`DeleteAction` casting outside `RealtimePayloadAdapter` — verify with: `grep -rn "InsertAction\|UpdateAction\|DeleteAction" NaarsCars/ --include="*.swift" | grep -v "RealtimePayloadAdapter" | grep -v "RealtimeManager"` → 0 results (except imports)
- [ ] Manual smoke: send message → appears. Create ride → appears on dashboard. Receive notification → appears in bell.

### C.7 Rollback Plan
`git revert` the Phase 1 commit. All subscribers revert to direct Action-type casting. Phase 0 tests still pass against old code (they test dictionary path, not Action types).

---

## D) Critical Follow-ups

### D.1 BadgeCount RPC Reliability

**What telemetry exists today:**
- `AppLogger.error("badges", "Failed to refresh badge counts (…): \(error)")` — logged on every RPC failure (line ~199)
- `AppLogger.warning("badges", "Badge RPC failed (code=…); using fallback counts for …s: …")` — logged in `registerBadgeRpcFailure()` with Postgrest error code (lines ~483-486)
- `badgeRpcFailureCount` tracked internally with exponential backoff
- **No external telemetry** (no analytics event, no crash reporter breadcrumb, no server-side metric)

**Proposed minimal observability step (before removing fallback):**
1. Add an analytics event in `registerBadgeRpcFailure()`:
   ```swift
   PerformanceMonitor.shared.recordEvent("badge_rpc_failure", metadata: [
       "error_code": postgrestCode ?? "unknown",
       "failure_count": "\(badgeRpcFailureCount)",
       "backoff_seconds": "\(backoffSeconds)"
   ])
   ```
   (PerformanceMonitor already exists at `Core/Services/PerformanceMonitor.swift`)

2. Add a similar event on success after a failure streak:
   ```swift
   if badgeRpcFailureCount > 0 {
       PerformanceMonitor.shared.recordEvent("badge_rpc_recovered", metadata: [
           "failures_before_recovery": "\(badgeRpcFailureCount)"
       ])
   }
   ```

**Proposed reversible kill switch:**
Add a `FeatureFlags` case (already exists in `Constants.swift`):
```swift
enum FeatureFlags {
    // Existing flags...
    /// When true, falls back to client-side badge computation on RPC failure.
    /// Set to false after confirming RPC reliability (target: 2026-03-01).
    static let badgeCountClientFallbackEnabled = true
}
```
In `refreshAllBadges()`:
```swift
} catch {
    if FeatureFlags.badgeCountClientFallbackEnabled {
        // existing fallback logic
    } else {
        // new cache-only logic from Phase 4
    }
}
```
This lets us toggle back to fallback via a single constant change if RPC proves unreliable.

### D.2 Supabase Migrations Naming/Numbering

**Confirmed convention:** `database/{NNN}_{snake_case_description}.sql`
**Highest existing number:** `106` (`106_conversation_and_badge_hot_indexes.sql`)
**Next available:** `107`

**Proposed filenames for upcoming phases:**
| Phase | Migration | Filename |
|-------|-----------|----------|
| Phase 4 | Badge counts resilience (COALESCE) | `database/107_badge_counts_resilience.sql` |
| Phase 7 | Notification type CHECK constraint | `database/108_notification_type_check_constraint.sql` |

**Collision avoidance:** If another branch creates `107` before Phase 4 merges, bump to the next available. Always check `ls database/*.sql | tail -5` before creating a migration.

### D.3 NotificationType Registry Approach

**Recommendation: Validation-first** for this repo today.

**Rationale:**
- The `NotificationType` enum already has 30 well-defined cases with computed properties (`icon`, `canBeDisabled`, `preferenceKey`). Generating these from a registry would require a build-plugin or code-gen step that doesn't exist yet.
- The TS edge functions already use string literals; replacing them with a shared const is straightforward.
- A validation script is simpler, lower-risk, and catches drift without requiring build system changes.

**Proposed minimal CI check:**

Create `scripts/validate-notification-types.sh`:
```bash
#!/bin/bash
# Extracts notification type strings from Swift enum, SQL constraint, and TS const.
# Fails if any mismatch.

set -euo pipefail

# Extract from Swift (raw values from NotificationType)
SWIFT_TYPES=$(grep 'case .* = "' NaarsCars/Core/Models/AppNotification.swift \
  | sed 's/.*= "\(.*\)"/\1/' | sort)

# Extract from TS shared module (after Phase 7 creates it)
TS_FILE="supabase/functions/_shared/notificationTypes.ts"
if [ -f "$TS_FILE" ]; then
  TS_TYPES=$(grep "'" "$TS_FILE" | sed "s/.*'\(.*\)'.*/\1/" | sort)
  DIFF=$(diff <(echo "$SWIFT_TYPES") <(echo "$TS_TYPES") || true)
  if [ -n "$DIFF" ]; then
    echo "MISMATCH between Swift and TypeScript notification types:"
    echo "$DIFF"
    exit 1
  fi
fi

echo "Notification types validated: $(echo "$SWIFT_TYPES" | wc -l | tr -d ' ') types in sync."
```

**Where to hook it:**
- As a pre-commit git hook (optional, lightweight)
- As a CI step (recommended — add to existing CI workflow after `xcodebuild build`)
- Can also be called manually: `bash scripts/validate-notification-types.sh`

---

## Phase 2 — NavigationIntent Enum (592 LOC → ~350 LOC)

> **Status:** Not started. Prerequisite: Phases 0+1 complete.

### Goal
Replace 20 ad-hoc `@Published` properties on `NavigationCoordinator` with a single `NavigationIntent` enum. Collapse 11 `NSNotification.Name` observers in `setupNotificationListeners()` and the 15-case `PendingNotificationNavigation` enum into one unified mechanism.

### Current State (post-Phase 1)
- `NavigationCoordinator.swift` (592 LOC) at `NaarsCars/App/NavigationCoordinator.swift`
- 20 `@Published` properties (lines 22-43):
  `selectedTab`, `navigateToRide`, `navigateToFavor`, `requestNavigationTarget`, `requestListScrollKey`, `navigateToConversation`, `conversationScrollTarget`, `navigateToProfile`, `townHallNavigationTarget`, `navigateToAdminPanel`, `navigateToPendingUsers`, `navigateToNotifications`, `profileScrollTarget`, `announcementsNavigationTarget`, `showReviewPrompt`, `reviewPromptRideId`, `reviewPromptFavorId`, `pendingDeepLink`, `showDeepLinkConfirmation`, `pendingNotificationNavigation`
- `setupNotificationListeners()` (lines 278-458) — 11 `NotificationCenter.default.addObserver` calls, each setting different `@Published` properties
- `applyDeepLink(_ deepLink: DeepLink)` (lines 125-186) — switch on 14 `DeepLink` cases, sets individual properties
- `applyPendingNotificationNavigation()` (lines 491-548) — switch on 15 `PendingNotificationNavigation` cases
- `clearConflictingNavigation(for:)` (lines 188-215) — manually nils out conflicting properties
- `hasActiveNavigation` (lines 222-234) — checks 12 properties
- `resetNavigation()` (lines 473-487) — nils out 12 properties

### File to Create

`NaarsCars/App/NavigationIntent.swift`

```swift
enum NavigationIntent: Equatable {
    // Requests tab
    case ride(UUID, anchor: RequestNotificationTarget? = nil)
    case favor(UUID, anchor: RequestNotificationTarget? = nil)
    case requestListScroll(key: String)

    // Messages tab
    case conversation(UUID, scrollTarget: ConversationScrollTarget? = nil)

    // Community tab
    case townHallPost(UUID, mode: TownHallNavigationTarget.Mode = .openComments)
    case announcements(scrollToNotificationId: UUID? = nil)

    // Profile tab
    case profile(UUID)
    case adminPanel
    case pendingUsers

    // Cross-tab surfaces
    case notifications
    case dashboard

    /// The tab that should be selected for this intent.
    var targetTab: NavigationCoordinator.Tab {
        switch self {
        case .ride, .favor, .requestListScroll, .notifications, .dashboard:
            return .requests
        case .conversation:
            return .messages
        case .townHallPost, .announcements:
            return .community
        case .profile, .adminPanel, .pendingUsers:
            return .profile
        }
    }
}
```

### Files to Modify

| # | File | LOC | Change |
|---|------|-----|--------|
| 1 | `App/NavigationCoordinator.swift` | 592 | Replace 15 of 20 `@Published` properties with `@Published var pendingIntent: NavigationIntent?`. Keep: `selectedTab`, `showReviewPrompt`, `reviewPromptRideId`, `reviewPromptFavorId`, `pendingDeepLink`, `showDeepLinkConfirmation`. Rewrite `applyDeepLink()` to produce `NavigationIntent`. Remove `PendingNotificationNavigation` enum entirely — replaced by `NavigationIntent`. Rewrite `setupNotificationListeners()` to set `pendingIntent`. Remove `clearConflictingNavigation`, simplify `hasActiveNavigation` to `pendingIntent != nil`, simplify `resetNavigation()` to `pendingIntent = nil`. |
| 2 | `App/MainTabView.swift` | 240 | Replace `.sheet(isPresented: $navigationCoordinator.navigateToNotifications)` with a single `.onChange(of: coordinator.pendingIntent)` that selects the correct tab. Keep `.sheet` presentation for notifications and announcements but drive from intent. |
| 3 | `Features/Notifications/ViewModels/NotificationsListViewModel.swift` | 599 | `handleNotificationTap` sets `coordinator.pendingIntent` instead of `coordinator.pendingNotificationNavigation`. Remove all `PendingNotificationNavigation` references. |
| 4 | `Features/Requests/ViewModels/RequestsDashboardViewModel.swift` | 942 | Read `coordinator.pendingIntent` for scroll targets instead of `coordinator.requestNavigationTarget` / `requestListScrollKey`. |
| 5 | `Features/Requests/Views/RequestsDashboardView.swift` | — | Consume `.ride(id, anchor:)` / `.favor(id, anchor:)` intents. Nil out `pendingIntent` after consumption. |
| 6 | `Features/Messaging/Views/ConversationsListView.swift` | — | Observe `coordinator.pendingIntent` for `.conversation(id)`. |
| 7 | `Features/Messaging/ViewModels/ConversationsListViewModel.swift` | — | Consume `.conversation` intent. |
| 8 | `Features/Profile/Views/SettingsView.swift` | — | Consume `.adminPanel`, `.pendingUsers` intents. |
| 9 | `App/AppDelegate.swift` | — | `handleDeepLink()` posts same `NSNotification.Name` strings (no change needed here — NavigationCoordinator's listeners are the ones that change). |

### Step-by-Step Tasks

1. Create `NaarsCars/App/NavigationIntent.swift` with the enum definition above.
2. Add `@Published var pendingIntent: NavigationIntent?` to `NavigationCoordinator`.
3. Rewrite `applyDeepLink(_ deepLink: DeepLink)` to map each `DeepLink` case to `NavigationIntent`:
   - `.ride(id)` → `.ride(id)`
   - `.favor(id)` → `.favor(id)`
   - `.conversation(id)` → `.conversation(id)`
   - `.townHallPostComments(id)` → `.townHallPost(id, mode: .openComments)`
   - `.townHallPostHighlight(id)` → `.townHallPost(id, mode: .highlightPost)`
   - `.profile(id)` → `.profile(id)`
   - `.adminPanel` → `.adminPanel`
   - `.pendingUsers` → `.pendingUsers`
   - `.notifications` → `.notifications`
   - `.announcements(id)` → `.announcements(scrollToNotificationId: id)`
   - `.dashboard`, `.enterApp`, `.unknown` → `.dashboard`
   - `.townHall` → set `selectedTab = .community` directly (no detail navigation)
4. Rewrite `setupNotificationListeners()` to set `pendingIntent` instead of individual properties. The 11 observers become intent-setters. Keep the observer mechanism (we're not changing how AppDelegate posts notifications).
5. Delete `PendingNotificationNavigation` enum (lines 75-91). In `NotificationsListViewModel`, set `coordinator.pendingIntent` directly.
6. Rewrite `applyPendingNotificationNavigation()` — can be simplified significantly since `pendingIntent` is consumed by the view layer via `.onChange`.
7. In `MainTabView`, add:
   ```swift
   .onChange(of: navigationCoordinator.pendingIntent) { _, intent in
       guard let intent else { return }
       navigationCoordinator.selectedTab = intent.targetTab
   }
   ```
8. Each tab's view consumes its own intent types and nils out `pendingIntent` after consumption.
9. Remove the 15 replaced `@Published` properties.
10. Update `NavigationCoordinatorRoutingTests.swift` (from Phase 0) to verify intent-based routing.

### Properties to KEEP (5):
- `selectedTab` — drives TabView binding
- `showReviewPrompt` / `reviewPromptRideId` / `reviewPromptFavorId` — modal, not navigation
- `pendingDeepLink` / `showDeepLinkConfirmation` — confirmation dialog flow

### Properties to REMOVE (15):
`navigateToRide`, `navigateToFavor`, `requestNavigationTarget`, `requestListScrollKey`, `navigateToConversation`, `conversationScrollTarget`, `navigateToProfile`, `townHallNavigationTarget`, `navigateToAdminPanel`, `navigateToPendingUsers`, `navigateToNotifications`, `profileScrollTarget`, `announcementsNavigationTarget`, `pendingNotificationNavigation`

(Note: `conversationScrollTarget` is subsumed by `NavigationIntent.conversation(id, scrollTarget:)`, `requestNavigationTarget` by `.ride(id, anchor:)` / `.favor(id, anchor:)`, etc.)

### Done Criteria
- [ ] `xcodebuild build` succeeds with 0 errors
- [ ] All Phase 0 tests pass (update `NavigationCoordinatorRoutingTests` for new API)
- [ ] `NavigationCoordinator` has 6 `@Published` properties (down from 20): `selectedTab`, `pendingIntent`, `showReviewPrompt`, `reviewPromptRideId`, `reviewPromptFavorId`, `pendingDeepLink`, `showDeepLinkConfirmation`
- [ ] `PendingNotificationNavigation` enum deleted — `grep -rn "PendingNotificationNavigation" NaarsCars/` → 0 results (except tests)
- [ ] Deep link from push notification → correct tab + detail screen
- [ ] Notification tap in bell → bell dismisses → navigates to correct screen
- [ ] Manual smoke: all regression checklist items pass

### Rollback
`git revert`. All 20 properties restored. Phase 0 tests revert to old API.

---

## Phase 3 — SyncEngine Protocol + AppState Orchestration

> **Status:** Not started. Prerequisite: Phase 1 complete.

### Goal
Unify the lifecycle of 3 sync engines behind a protocol. `AppState` becomes the single orchestrator. Remove direct sync engine references from `AuthService`.

### Current State (post-Phase 1)
- `AuthService.restartRealtimeSyncEngines()` at `Core/Services/AuthService.swift` line 613 directly calls:
  - `DashboardSyncEngine.shared.startSync()`
  - `MessagingSyncEngine.shared.startSync()`
  - `TownHallSyncEngine.shared.startSync()`
- `AppLaunchManager.startDeferredSyncEnginesIfNeeded(for:)` at `App/AppLaunchManager.swift` line 265 does the same
- `NaarsCarsApp` (line ~112-113) calls `DashboardSyncEngine.shared.setup(modelContext:)` and `MessagingSyncEngine.shared.setup(modelContext:)`
- No `pauseSync()` or `teardown()` methods exist on any engine today
- Each engine has only `startSync()` and `setup(modelContext:)` (implicit, varies by engine)

### Sync Engine Current APIs

| Engine | File | LOC | Has `setup(modelContext:)` | Has `startSync()` | Has pause/teardown |
|--------|------|-----|---------------------------|--------------------|--------------------|
| `MessagingSyncEngine` | `Core/Storage/MessagingSyncEngine.swift` | 144 | Yes | Yes | No |
| `DashboardSyncEngine` | `Core/Storage/DashboardSyncEngine.swift` | 309 | Yes | Yes | No |
| `TownHallSyncEngine` | `Core/Storage/TownHallSyncEngine.swift` | 371 | Yes (implicit) | Yes | No |

### Files to Create

1. `NaarsCars/Core/Storage/SyncEngineProtocol.swift` — protocol definition
2. `NaarsCars/Core/Storage/SyncEngineOrchestrator.swift` — lifecycle manager

### Files to Modify

| # | File | Change |
|---|------|--------|
| 1 | `Core/Storage/MessagingSyncEngine.swift` | Conform to `SyncEngineProtocol`. Add `pauseSync()` (unsubscribe `messages:sync` channel), `resumeSync()` (re-setup subscription), `teardown()` (unsubscribe + nil out state). |
| 2 | `Core/Storage/DashboardSyncEngine.swift` | Conform to `SyncEngineProtocol`. Add `pauseSync()` (unsubscribe `rides:sync`, `favors:sync`, `notifications:sync`), `resumeSync()`, `teardown()`. |
| 3 | `Core/Storage/TownHallSyncEngine.swift` | Conform to `SyncEngineProtocol`. Add `pauseSync()` (unsubscribe `town-hall-posts`, `town-hall-comments`, `town-hall-votes`), `resumeSync()`, `teardown()`. |
| 4 | `Core/Services/AuthService.swift` | Remove `restartRealtimeSyncEngines()` body. Replace with `await SyncEngineOrchestrator.shared.startAll()`. Or: remove method entirely, have callers go through orchestrator. |
| 5 | `App/AppLaunchManager.swift` | `startDeferredSyncEnginesIfNeeded()` calls `SyncEngineOrchestrator.shared.startAll()` instead of 3 direct calls. |
| 6 | `App/AppState.swift` | Add `SyncEngineOrchestrator` wiring. On `userDidSignOut` notification: call `SyncEngineOrchestrator.shared.teardownAll()`. |
| 7 | `App/NaarsCarsApp.swift` | Registration: `SyncEngineOrchestrator.shared.register(MessagingSyncEngine.shared)` etc. Setup: `SyncEngineOrchestrator.shared.setupAll(modelContext:)`. |
| 8 | `App/AppDelegate.swift` | If it calls `DashboardSyncEngine.shared.syncAll()` (line ~94), route through orchestrator. |

### Protocol Definition

```swift
@MainActor
protocol SyncEngineProtocol: AnyObject {
    var engineName: String { get }
    func setup(modelContext: ModelContext)
    func startSync()
    func pauseSync() async
    func resumeSync() async
    func teardown() async
}
```

Note: `startSync()` is not async today (it launches internal `Task`s). Keep it synchronous to match existing call patterns. `pauseSync/resumeSync/teardown` are async because they call `RealtimeManager.unsubscribe()` which is async.

### Done Criteria
- [ ] `xcodebuild build` succeeds
- [ ] `AuthService` no longer directly references any `*SyncEngine.shared` — verify: `grep -rn "MessagingSyncEngine\|DashboardSyncEngine\|TownHallSyncEngine" NaarsCars/Core/Services/AuthService.swift` → 0 results
- [ ] `AppLaunchManager` no longer directly references engines — verify same grep
- [ ] Background → foreground: engines resume (realtime resubscribes)
- [ ] Sign-out: `teardownAll()` called → no orphan subscriptions
- [ ] All existing tests pass
- [ ] Manual smoke: messaging sync, dashboard sync, town hall sync all work normally

### Rollback
`git revert`. AuthService reverts to direct engine calls. Engines lose pause/teardown (harmless — they didn't have them before).

---

## Phase 4 — Badge Count Contract (Kill Client Fallback)

> **Status:** Not started. Prerequisite: Phase 0 badge tests exist.

### Goal
Make `get_badge_counts` RPC the single authority. Remove client-side fallback computation. Add observability and a reversible kill switch.

### Current State (post-Phase 1)
- `BadgeCountManager.swift` (541 LOC) at `Core/Services/BadgeCountManager.swift`
- `refreshAllBadges()` (lines 137-199): tries RPC first via `shouldUseBadgeCountsRpc()`, falls back to `fetchFallbackBadgeCounts(userId:)` on failure
- `fetchFallbackBadgeCounts(userId:)` (lines 489-526): calls `NotificationService.fetchNotifications()`, `NotificationGrouping.unreadRequestKeys()`, `NotificationGrouping.groupBellNotifications()`, `messagingRepository.getConversations()`, `calculateMessagesBadgeCount()`
- 5 `calculate*BadgeCount()` helpers (lines 329-416): each calls a different service
- Service dependencies used ONLY for fallback: `notificationService`, `conversationService`, `adminService`, `townHallService`, `messagingRepository` (line 56-63)
- `profileBadgeCount` is computed separately via `calculateProfileBadgeCount()` (calls `adminService.fetchPendingUsers()`) — this stays (profile/admin badge is not part of the RPC)
- `BadgeCountsPayload` (private struct, line 431): `requestsTotal`, `messagesTotal`, `communityTotal`, `bellTotal`, `requestDetails`, `conversationDetails`
- Backoff: `badgeRpcFailureCount`, `badgeRpcBackoffUntil`, exponential backoff up to 120s, schema errors → 5 min backoff

### Files to Modify

| # | File | Change |
|---|------|--------|
| 1 | `Core/Services/BadgeCountManager.swift` | Add `@Published var isBadgeStale: Bool = false` + `private var lastKnownCounts: BadgeCountsPayload?`. On RPC success: cache + `isBadgeStale = false`. On RPC failure: publish cached counts + `isBadgeStale = true`. Remove `fetchFallbackBadgeCounts()` and all 5 `calculate*BadgeCount()` helpers (except `calculateProfileBadgeCount` which stays). Remove unused service imports. Add `FeatureFlags.badgeCountClientFallbackEnabled` kill switch. Add `PerformanceMonitor` telemetry on failure/recovery. |
| 2 | `Core/Utilities/Constants.swift` | Add `FeatureFlags.badgeCountClientFallbackEnabled` if not already in `FeatureFlags` enum |
| 3 | `database/107_badge_counts_resilience.sql` | Harden `get_badge_counts` RPC with `COALESCE` for all returned keys |

### Step-by-Step Tasks

1. Add to `FeatureFlags` in `Constants.swift`:
   ```swift
   /// When true, falls back to client-side badge computation on RPC failure.
   /// Set to false after confirming RPC reliability (target: 2026-03-01).
   static let badgeCountClientFallbackEnabled = false  // Disabled by default
   ```

2. Add to `BadgeCountManager`:
   ```swift
   @Published private(set) var isBadgeStale: Bool = false
   private var lastKnownCounts: BadgeCountsPayload?
   ```

3. Add telemetry in `registerBadgeRpcFailure()`:
   ```swift
   PerformanceMonitor.shared.recordEvent("badge_rpc_failure", metadata: [
       "error_code": postgrestCode,
       "failure_count": "\(badgeRpcFailureCount)",
       "backoff_seconds": "\(Int(backoffSeconds))"
   ])
   ```

4. Add telemetry on recovery in `refreshAllBadges()`:
   ```swift
   if badgeRpcFailureCount > 0 {
       PerformanceMonitor.shared.recordEvent("badge_rpc_recovered", metadata: [
           "failures_before_recovery": "\(badgeRpcFailureCount)"
       ])
   }
   ```

5. Rewrite `refreshAllBadges()` failure path:
   ```swift
   } catch {
       registerBadgeRpcFailure(error)
       if FeatureFlags.badgeCountClientFallbackEnabled {
           counts = await fetchFallbackBadgeCounts(userId: userId)
       } else if let cached = lastKnownCounts {
           counts = cached
           isBadgeStale = true
       } else {
           counts = BadgeCountsPayload(requestsTotal: 0, messagesTotal: 0,
               communityTotal: 0, bellTotal: 0, requestDetails: [], conversationDetails: [])
           isBadgeStale = true
       }
   }
   ```
   On RPC success: `lastKnownCounts = counts; isBadgeStale = false`

6. Once the kill switch is verified (after monitoring), delete:
   - `fetchFallbackBadgeCounts(userId:)` (lines 489-526)
   - `calculateRequestsBadgeCount(userId:)` (lines 329-341)
   - `calculateMessagesBadgeCount(userId:)` (lines 345-355)
   - `calculateCommunityBadgeCount(userId:)` (lines 359-380)
   - `calculateBellBadgeCount(userId:)` (lines 406-416)
   - Remove `notificationService`, `conversationService`, `townHallService`, `messagingRepository` properties (keep `adminService` for profile badge, keep `authService`, `supabase`, `realtimeManager`)

7. Create `database/107_badge_counts_resilience.sql`:
   ```sql
   -- Harden get_badge_counts to always return complete JSONB with COALESCE defaults
   CREATE OR REPLACE FUNCTION get_badge_counts(...)
   -- Wrap each counter in COALESCE(..., 0)
   -- Wrap detail arrays in COALESCE(..., '[]'::jsonb)
   ```

### Done Criteria
- [ ] `xcodebuild build` succeeds
- [ ] `isBadgeStale` published when RPC fails (verify in `BadgeCountManagerTests`)
- [ ] Kill switch `FeatureFlags.badgeCountClientFallbackEnabled = false` → fallback code unreachable
- [ ] Kill switch `= true` → old fallback behavior restored
- [ ] `PerformanceMonitor` events logged on failure/recovery
- [ ] SQL migration `107` applied: `get_badge_counts` returns all keys with COALESCE defaults
- [ ] Manual smoke: badge counts work normally. Kill network → stale indicator. Restore network → counts refresh.

### Rollback
`git revert` Swift changes. SQL migration is additive (COALESCE is backward-compatible). Set `FeatureFlags.badgeCountClientFallbackEnabled = true` to immediately restore fallback.

---

## Phase 5 — ViewModel Decomposition

> **Status:** Not started. Prerequisite: Phase 1 (so extracted managers receive `RealtimeRecord`, not `Any`).

### Goal
Break the 3 largest ViewModels under 500 lines each via extracted manager objects, following the pattern already proven by `ConversationSearchManager` (`Features/Messaging/ViewModels/ConversationSearchManager.swift`).

### Current LOC

| ViewModel | File | LOC | Target |
|-----------|------|-----|--------|
| `ConversationDetailViewModel` | `Features/Messaging/ViewModels/ConversationDetailViewModel.swift` | 1107 | ≤ 450 |
| `RequestsDashboardViewModel` | `Features/Requests/ViewModels/RequestsDashboardViewModel.swift` | 942 | ≤ 400 |
| `NotificationsListViewModel` | `Features/Notifications/ViewModels/NotificationsListViewModel.swift` | 599 | ≤ 300 |

### Extraction Pattern (from `ConversationSearchManager`)

```swift
@MainActor
final class ExtractedManager: ObservableObject {
    @Published var someState: SomeType = ...
    // Methods that operate on own state
}

// In parent ViewModel:
let searchManager = ConversationSearchManager()
// Wire: searchManager.objectWillChange → self.objectWillChange
private var managerCancellables = Set<AnyCancellable>()
init() {
    searchManager.objectWillChange
        .sink { [weak self] _ in self?.objectWillChange.send() }
        .store(in: &managerCancellables)
}
```

### Files to Create (8 files)

```
NaarsCars/Features/Notifications/ViewModels/
├── NotificationGroupingManager.swift
├── NotificationNavigationRouter.swift
└── NotificationRealtimeHandler.swift

NaarsCars/Features/Requests/ViewModels/
├── RequestFilterManager.swift
├── RequestRealtimeHandler.swift
└── RequestNotificationSummaryManager.swift

NaarsCars/Features/Messaging/ViewModels/
├── MessagePaginationManager.swift
└── MessageSendManager.swift
```

### Decomposition Plan

**1. NotificationsListViewModel (599 → ~300 LOC)**

| Extracted Manager | Responsibilities | Methods to move |
|-------------------|-----------------|-----------------|
| `NotificationGroupingManager` | Filtering + grouping logic. Pure — no side effects. | `getFilteredNotifications(sdNotifications:)`, `getNotificationGroups(sdNotifications:)`, grouping helper logic |
| `NotificationNavigationRouter` | Tap handling → produces `NavigationIntent` (from Phase 2, or sets `pendingNotificationNavigation` if Phase 2 not yet merged). | `handleNotificationTap(_:group:)`, `pendingNavigation(for:)`, `handleNotificationNavigation(for:)`, `handleAnnouncementTap(_:)` |
| `NotificationRealtimeHandler` | Owns realtime subscription. On payload, calls parent's `loadNotifications()` via closure. | `setupRealtimeSubscription()`, `handleRealtimeEvent(_:reason:)` |

**Parent retains:** `@Published` properties, `setup()`, `loadNotifications()`, `markAsRead()`, `markAllAsRead()`, delegates to managers.

**2. RequestsDashboardViewModel (942 → ~400 LOC)**

| Extracted Manager | Responsibilities | Methods to move |
|-------------------|-----------------|-----------------|
| `RequestFilterManager` | Filter application + filtered list computation. | `getFilteredRequests()`, `filterRequests()`, `refreshFilteredRequests()`, filter badge counts |
| `RequestRealtimeHandler` | Owns 3 subscriptions (rides, favors, notifications). Debounced sync scheduling. | `setupRealtime*()`, `handleRideRealtimeEvent(_:reason:)`, `handleFavorRealtimeEvent(_:reason:)`, `handleRequestNotificationEvent(_:reason:)`, debounce logic |
| `RequestNotificationSummaryManager` | Unseen request keys, notification summaries. | `unseenRequestKeys`, `requestNotificationSummaries`, `buildRequestNotificationSummaries()` |

**Parent retains:** `@Published` properties, `setup()`, `loadRequests()`, orchestration.

**3. ConversationDetailViewModel (1107 → ~450 LOC)**

| Extracted Manager | Responsibilities | Methods to move |
|-------------------|-----------------|-----------------|
| `MessagePaginationManager` | Load, loadMore, sort, reply context hydration. | `loadMessages()`, `loadMoreMessages()`, `hasMoreMessages`, reply context methods |
| `MessageSendManager` | Send text/image/audio/location + retry + dismiss. | `sendMessage()`, `sendAudioMessage()`, `sendLocationMessage()`, `editMessage()`, `unsendMessage()`, `retryMessage()`, `dismissFailedMessage()` |

**Parent retains:** `@Published messages`, `searchManager`, `typingManager`, reactions, observation setup, mark-read logic.

### Done Criteria
- [ ] `xcodebuild build` succeeds with 0 errors
- [ ] No ViewModel exceeds 500 lines — verify: `wc -l NaarsCars/Features/*/ViewModels/*.swift | sort -rn | head -5`
- [ ] All existing tests pass
- [ ] Extracted managers are `@MainActor final class: ObservableObject`
- [ ] Parent ViewModels forward `objectWillChange` from all child managers
- [ ] Manual smoke: notifications bell → grouping correct, tap routes correctly. Dashboard → filters work, realtime updates appear. Messaging → pagination, send, edit, unsend all work.
- [ ] **User must add new files to Xcode project manually**

### Rollback
`git revert`. ViewModels restore to monolithic form. All behavior unchanged.

---

## Phase 6 — Service Protocols + Dependency Injection

> **Status:** Not started. Prerequisite: Phase 5 (so extracted managers can also accept protocols).

### Goal
Define protocols for top-10 services. ViewModels accept protocols via initializer. `.shared` singletons remain as defaults.

### Services to Protocol-ize

| Service | File | LOC | Methods used by ViewModels (extract these into protocol) |
|---------|------|-----|--------------------------------------------------------|
| `AuthService` | `Core/Services/AuthService.swift` | ~674 | `currentUserId`, `currentProfile`, `isLoading` |
| `MessageService` | `Core/Services/MessageService.swift` | — | `fetchMessages()`, `sendMessage()`, `markAsRead()`, `editMessage()`, `unsendMessage()` |
| `ConversationService` | `Core/Services/ConversationService.swift` | — | `fetchConversations()`, `createConversation()`, `archiveConversation()` |
| `RideService` | `Core/Services/RideService.swift` | — | `fetchRides()`, `fetchRide()`, `createRide()`, `updateRide()` |
| `FavorService` | `Core/Services/FavorService.swift` | — | `fetchFavors()`, `fetchFavor()`, `createFavor()`, `updateFavor()` |
| `NotificationService` | `Core/Services/NotificationService.swift` | — | `fetchNotifications()`, `markAsRead()`, `markAllAsRead()` |
| `ProfileService` | `Core/Services/ProfileService.swift` | — | `fetchProfile()`, `updateProfile()` |
| `ClaimService` | `Core/Services/ClaimService.swift` | — | `claimRequest()`, `unclaimRequest()` |
| `ReviewService` | `Core/Services/ReviewService.swift` | — | `submitReview()`, `fetchReviews()` |
| `BadgeCountManager` | `Core/Services/BadgeCountManager.swift` | 541 | `refreshAllBadges()`, `clearRequestsBadge()`, `clearMessagesBadge()`, published counts |

### Files to Create (10 protocol files + 1 example mock)

```
NaarsCars/Core/Protocols/
├── AuthServiceProtocol.swift
├── MessageServiceProtocol.swift
├── ConversationServiceProtocol.swift
├── RideServiceProtocol.swift
├── FavorServiceProtocol.swift
├── NotificationServiceProtocol.swift
├── ProfileServiceProtocol.swift
├── ClaimServiceProtocol.swift
├── ReviewServiceProtocol.swift
└── BadgeCountManaging.swift
```

### Pattern

```swift
// Protocol — only methods called by ViewModels:
@MainActor
protocol AuthServiceProtocol: AnyObject {
    var currentUserId: UUID? { get }
    var currentProfile: Profile? { get }
}

// Conformance (zero logic change):
extension AuthService: AuthServiceProtocol {}

// ViewModel injection:
final class SomeViewModel: ObservableObject {
    private let authService: any AuthServiceProtocol
    init(authService: any AuthServiceProtocol = AuthService.shared) {
        self.authService = authService
    }
}
```

### Done Criteria
- [ ] `xcodebuild build` succeeds
- [ ] 10 protocol files exist in `Core/Protocols/`
- [ ] Every ViewModel that previously called `ServiceName.shared` now accepts the protocol via init
- [ ] Default parameter values mean no call-site changes in production View code
- [ ] At least 1 mock implementation exists per protocol (in test target)
- [ ] `grep -rn "AuthService\.shared" NaarsCars/Features/` → 0 results (all moved to injected properties)
- [ ] **User must add new files to Xcode project manually**

### Rollback
`git revert`. Protocols removed, direct `.shared` references restored.

---

## Phase 7 — Notification Type Registry (Single Source of Truth)

> **Status:** Not started.

### Goal
One canonical list of notification types that validates Swift enum, SQL, and TypeScript consistency.

### Current State
- `NotificationType` enum: `Core/Models/AppNotification.swift` lines 11-132, 30 cases
- Edge functions use string literals: `supabase/functions/send-message-push/index.ts`, `supabase/functions/send-notification/index.ts`
- `supabase/functions/_shared/apns.ts` has `resolveEventType()` (lines 148-151) for payload normalization
- No SQL CHECK constraint on `notifications.type` column
- No cross-stack validation

### Files to Create

1. `NaarsCars/Core/Models/NotificationTypeRegistry.swift` — canonical list with compile-time validation
2. `database/108_notification_type_check_constraint.sql` — SQL CHECK on `notifications.type`
3. `supabase/functions/_shared/notificationTypes.ts` — TS const object
4. `scripts/validate-notification-types.sh` — cross-stack validation script

### Files to Modify

| # | File | Change |
|---|------|--------|
| 1 | `Core/Models/AppNotification.swift` | Add `#if DEBUG validateRegistry()` call |
| 2 | `supabase/functions/send-notification/index.ts` | Import from `_shared/notificationTypes.ts` instead of string literals |
| 3 | `supabase/functions/send-message-push/index.ts` | Import from `_shared/notificationTypes.ts` |

### Registry Design (validation-first approach)

```swift
enum NotificationTypeRegistry {
    static let allTypes: Set<String> = [
        "message", "added_to_conversation",
        "new_ride", "ride_update", "ride_claimed", "ride_unclaimed", "ride_completed",
        "new_favor", "favor_update", "favor_claimed", "favor_unclaimed", "favor_completed",
        "completion_reminder",
        "qa_activity", "qa_question", "qa_answer",
        "review", "review_received", "review_reminder", "review_request",
        "town_hall_post", "town_hall_comment", "town_hall_reaction",
        "announcement", "admin_announcement", "broadcast",
        "pending_approval", "user_approved", "user_rejected",
        "other"
    ]

    #if DEBUG
    static func validateRegistry() {
        let enumCases = Set(NotificationType.allCases.map(\.rawValue))
        assert(enumCases == allTypes,
            "NotificationType enum (\(enumCases.count) cases) and registry (\(allTypes.count) types) are out of sync. " +
            "Missing from registry: \(enumCases.subtracting(allTypes)). " +
            "Missing from enum: \(allTypes.subtracting(enumCases))."
        )
    }
    #endif
}
```

Note: `NotificationType` must conform to `CaseIterable` (add `: CaseIterable` if not already present).

### Done Criteria
- [ ] `xcodebuild build` succeeds
- [ ] `NotificationType.allCases.count == NotificationTypeRegistry.allTypes.count` (compile-time via DEBUG assert)
- [ ] SQL constraint applied — inserting invalid type fails
- [ ] Edge functions import from `_shared/notificationTypes.ts` — no string literals for type values
- [ ] `scripts/validate-notification-types.sh` exits 0
- [ ] **User must add new files to Xcode project manually**

### Rollback
`git revert` Swift + TS. SQL constraint can be dropped: `ALTER TABLE notifications DROP CONSTRAINT IF EXISTS valid_notification_type;`

---

## E) Codex 5.3 Handoff Snippets

### E.1 Codex Phase 0 Execution Prompt (COMPLETED)

```
TASK: NaarsCars iOS — Phase 0: Test Safety Net

OBJECTIVE: Create regression tests for the most fragile seams. NO production code changes.

SCOPE BOUNDARY — STRICTLY ENFORCED:
- Create ONLY test files and fixture files under NaarsCarsTests/
- Do NOT modify any file outside NaarsCarsTests/
- Do NOT edit project.pbxproj (user will add files to Xcode manually)
- Do NOT refactor ViewModels, Services, or any production code
- Do NOT add new dependencies

FILES TO CREATE (8 files):
1. NaarsCars/NaarsCarsTests/Core/Fixtures/RealtimeFixtures.swift
   - Sample [String: Any] dictionaries matching message, ride, favor, notification table schemas
   - Include all fields used by MessagingMapper.parseMessageFromPayload() (see Core/Storage/MessagingMapper.swift lines 86-170)
   - Include date format variants: ISO8601 with/without fractional seconds

2. NaarsCars/NaarsCarsTests/Core/Fixtures/NotificationFixtures.swift
   - All 30 NotificationType raw value strings
   - Expected preferenceKey for each type
   - Set of mandatory (canBeDisabled == false) types

3. NaarsCars/NaarsCarsTests/Core/Fixtures/WebhookFixtures.swift
   - APNs payload from send-message-push (type: "message", conversation_id, message_id, sender_id, aps.alert)
   - APNs payload from send-notification (type: notificationType, aps with category, mutable-content)
   - resolveEventType test payloads: {type:}, {eventType:}, {event_type:}, {data:{type:}}

4. NaarsCars/NaarsCarsTests/Core/Decoding/RealtimePayloadDecodingTests.swift
   - Test MessagingMapper.parseMessageFromPayload() with [String: Any] dictionary fixtures
   - Minimum 8 tests: full fields, minimal required, missing required field → nil, date parsing variants, readBy parsing

5. NaarsCars/NaarsCarsTests/Core/Decoding/NotificationTypeDecodingTests.swift
   - Round-trip all 30 cases: NotificationType(rawValue:) == original
   - preferenceKey correctness for all 30
   - canBeDisabled correctness
   - icon non-empty for all cases
   - Unknown string → nil
   - Minimum 34 tests

6. NaarsCars/NaarsCarsTests/Core/Decoding/WebhookPayloadDecodingTests.swift
   - Test DeepLinkParser.parse(userInfo:) with message push shape → .conversation
   - Test with ride notification → .ride
   - Test with each major notification type → correct DeepLink case
   - Minimum 6 tests

7. NaarsCars/NaarsCarsTests/Core/Services/BadgeCountManagerTests.swift
   - Test: totalUnreadCount is computed correctly (if publicly observable)
   - Test: all BadgeTab cases have valid rawValue
   - Keep lightweight — avoid testing private internals
   - Minimum 3 tests

8. NaarsCars/NaarsCarsTests/Core/Services/NavigationCoordinatorRoutingTests.swift
   - Test: resetNavigation() clears all @Published nav properties to defaults
   - Test: PendingNotificationNavigation cases map to expected tabs in applyPendingNotificationNavigation()
   - Test: DeepLink cases from DeepLinkParser map to correct navigation destinations
   - Minimum 15 tests

IMPORTS REQUIRED:
- @testable import NaarsCars
- import XCTest
- For RealtimeFixtures: may need `import Supabase` and `import Realtime` if testing Action types

HEADER FORMAT (required for all new files):
  //
  //  FileName.swift
  //  NaarsCars
  //
  //  Description
  //

COMPILE + TEST COMMAND:
  xcodebuild test -scheme NaarsCars -destination 'platform=iOS Simulator,name=iPhone 16' -only-testing:NaarsCarsTests

DONE CRITERIA:
- All tests pass (0 failures)
- No production files modified
- git diff shows only new files in NaarsCarsTests/

IMPACT SUMMARY (update after completion):
List each file created and the number of test cases in each.

ROLLBACK: git revert the commit. Zero production risk.
```

### E.2 Codex Phase 1 Execution Prompt (COMPLETED)

```
TASK: NaarsCars iOS — Phase 1: Realtime Payload Adapter

OBJECTIVE: Centralize Supabase Realtime payload decoding into a single adapter.
Eliminate duplicated InsertAction/UpdateAction/DeleteAction casting from 6+ files.

SCOPE BOUNDARY — STRICTLY ENFORCED:
- Create adapter in Core/Realtime/
- Update RealtimeManager callback types
- Update each subscriber to receive RealtimeRecord instead of Any
- Update MessagingMapper to accept [String: Any] instead of Any
- Do NOT touch navigation, badge counts, ViewModel decomposition, or SQL migrations
- Do NOT edit project.pbxproj (user will add files to Xcode manually)
- Do NOT change any user-visible behavior

PREREQUISITE: Phase 0 tests must exist and pass before starting.

FILES TO CREATE (1 file, 1 directory):
1. NaarsCars/Core/Realtime/RealtimePayloadAdapter.swift
   - Define RealtimeRecord struct:
     struct RealtimeRecord {
         enum EventType { case insert, update, delete }
         let table: String
         let eventType: EventType
         let record: [String: Any]
         let oldRecord: [String: Any]?
     }
   - Implement decodeInsert/Update/Delete static methods
   - Implement normalizeRecord([String: AnyJSON]) -> [String: Any]
     IMPORTANT: Move/copy normalizeValue() and decodeAnyJSON()/decodeAnyJSONMirror()
     from MessagingMapper (Core/Storage/MessagingMapper.swift lines ~196-291).
     Make them internal static on RealtimePayloadAdapter.
     Update MessagingMapper to call RealtimePayloadAdapter.normalizeRecord() or
     RealtimePayloadAdapter.normalizeValue() instead of its own copies.

FILES TO MODIFY (8 files):

1. Core/Services/RealtimeManager.swift
   - Change typealias lines 16-18:
     FROM: typealias RealtimeInsertCallback = (Any) -> Void
     TO:   typealias RealtimeInsertCallback = (RealtimeRecord) -> Void
     (same for Update and Delete)
   - In subscribe() method, update the for-await loops (lines 178-200):
     FROM: onInsert(action)
     TO:   if let record = RealtimePayloadAdapter.decodeInsert(action, table: table) {
               onInsert(record)
           }
   - Add `import Realtime` if not already present (it is: line 11)
   - The subscribe() method needs access to `table` parameter in the Task closures — it already does.

2. Core/Storage/MessagingSyncEngine.swift
   - handleIncomingMessage(_ payload: Any, event:) →
     handleIncomingMessage(_ record: RealtimeRecord)
   - Remove Action-type casting; use record.record directly
   - For shouldIgnoreReadByUpdate: this currently takes [String: AnyJSON].
     Change to take [String: Any] from record.record and record.oldRecord.
     Or: keep it but call it only for update events.
   - setupMessagesSubscription callbacks now receive RealtimeRecord

3. Core/Storage/MessagingMapper.swift
   - parseMessageFromPayload(_ payload: Any) →
     parseMessage(from record: [String: Any])
   - Remove InsertAction/UpdateAction/DeleteAction casting (lines 89-98)
   - Keep [String: Any] field extraction logic (lines 100-169) — this stays the same
   - Move normalizeValue/decodeAnyJSON helpers to RealtimePayloadAdapter
     (or have MessagingMapper call the adapter's versions)

4. Core/Storage/TownHallSyncEngine.swift
   - handlePostUpsert(_ payload: Any) → handlePostUpsert(_ record: RealtimeRecord)
   - handlePostDelete, handleCommentUpsert, handleCommentDelete, handleVoteChange: same
   - Remove Action-type casting from each

5. Features/Requests/ViewModels/RequestsDashboardViewModel.swift
   - handleRideRealtimePayload(_ payload: Any, event:, reason:) →
     handleRideRealtimeEvent(_ record: RealtimeRecord, reason:)
   - handleFavorRealtimePayload → handleFavorRealtimeEvent
   - handleRequestNotificationPayload → handleRequestNotificationEvent
   - Remove Action-type casting from each
   - event type now comes from record.eventType

6. Features/Notifications/ViewModels/NotificationsListViewModel.swift
   - handleRealtimePayload(_ payload: Any, reason:) →
     handleRealtimeEvent(_ record: RealtimeRecord, reason:)
   - Remove InsertAction casting

7. Features/Favors/ViewModels/FavorsDashboardViewModel.swift
   - handleFavorInsert/Update/Delete: callbacks now receive RealtimeRecord

8. Features/Rides/ViewModels/RidesDashboardViewModel.swift
   - handleRideInsert/Update/Delete: callbacks now receive RealtimeRecord

COMPILE + TEST COMMAND:
  xcodebuild build -scheme NaarsCars -destination 'platform=iOS Simulator,name=iPhone 16'
  xcodebuild test -scheme NaarsCars -destination 'platform=iOS Simulator,name=iPhone 16'

VERIFICATION COMMANDS:
  # No Action-type casting outside adapter and manager:
  grep -rn "InsertAction\|UpdateAction\|DeleteAction" NaarsCars/ --include="*.swift" \
    | grep -v "RealtimePayloadAdapter" | grep -v "RealtimeManager" | grep -v "Tests"
  # Expected: 0 results (or only import statements)

  # No raw "payload as?" casting in sync engines or features:
  grep -rn "payload as\?" NaarsCars/Core/Storage/ NaarsCars/Features/ --include="*.swift"
  # Expected: 0 results

DONE CRITERIA:
- xcodebuild build: 0 errors, 0 new warnings
- All Phase 0 tests still pass
- Verification grep commands return 0 results
- Manual smoke: send message → appears. Create ride → appears. Notification → bell updates.

IMPACT SUMMARY (update after completion):
List each file touched, lines added/removed, and why.

ROLLBACK: git revert the Phase 1 commit. Subscribers revert to direct Action-type casting.
Phase 0 tests still pass against reverted code (they test [String: Any] path).
```

### E.3 Codex Phase 2 Execution Prompt

```
TASK: NaarsCars iOS — Phase 2: NavigationIntent Enum

OBJECTIVE: Replace 15 ad-hoc @Published navigation properties on NavigationCoordinator
with a single NavigationIntent enum. Delete PendingNotificationNavigation.

SCOPE BOUNDARY — STRICTLY ENFORCED:
- Touch ONLY navigation-related files (NavigationCoordinator, MainTabView, views that consume nav properties)
- Do NOT touch RealtimeManager, SyncEngines, BadgeCountManager, or SQL migrations
- Do NOT decompose ViewModels (that's Phase 5)
- Do NOT add service protocols (that's Phase 6)
- Do NOT edit project.pbxproj (user will add files to Xcode manually)
- Do NOT change user-visible behavior — same screens, same routing, same timing

PREREQUISITE: Phases 0+1 complete. RealtimeRecord already in use.

FILE TO CREATE (1 file):
1. NaarsCars/App/NavigationIntent.swift
   - enum NavigationIntent: Equatable with cases:
     ride(UUID, anchor: RequestNotificationTarget? = nil),
     favor(UUID, anchor: RequestNotificationTarget? = nil),
     requestListScroll(key: String),
     conversation(UUID, scrollTarget: ConversationScrollTarget? = nil),
     townHallPost(UUID, mode: TownHallNavigationTarget.Mode = .openComments),
     announcements(scrollToNotificationId: UUID? = nil),
     profile(UUID), adminPanel, pendingUsers, notifications, dashboard
   - Computed property: var targetTab: NavigationCoordinator.Tab

FILES TO MODIFY:
1. App/NavigationCoordinator.swift (592 LOC → ~350)
   - Add @Published var pendingIntent: NavigationIntent?
   - Rewrite applyDeepLink() to set pendingIntent instead of individual properties
   - Rewrite setupNotificationListeners() to set pendingIntent
   - Delete PendingNotificationNavigation enum
   - Rewrite applyPendingNotificationNavigation() to use pendingIntent
   - Simplify resetNavigation() to: pendingIntent = nil
   - Simplify hasActiveNavigation to: pendingIntent != nil
   - Remove 15 properties: navigateToRide, navigateToFavor, requestNavigationTarget,
     requestListScrollKey, navigateToConversation, conversationScrollTarget,
     navigateToProfile, townHallNavigationTarget, navigateToAdminPanel,
     navigateToPendingUsers, navigateToNotifications, profileScrollTarget,
     announcementsNavigationTarget, pendingNotificationNavigation
   - KEEP 6 properties: selectedTab, pendingIntent, showReviewPrompt,
     reviewPromptRideId, reviewPromptFavorId, pendingDeepLink, showDeepLinkConfirmation

2. App/MainTabView.swift (240 LOC)
   - Add .onChange(of: navigationCoordinator.pendingIntent) to select correct tab
   - Update .sheet for notifications to use pendingIntent == .notifications
   - Update .sheet for announcements to use pendingIntent == .announcements

3. Features/Notifications/ViewModels/NotificationsListViewModel.swift
   - handleNotificationTap: set coordinator.pendingIntent instead of pendingNotificationNavigation
   - Remove all PendingNotificationNavigation references

4. Features/Requests/ViewModels/RequestsDashboardViewModel.swift
   - Consume .ride(id, anchor) and .favor(id, anchor) from pendingIntent
   - Replace requestNavigationTarget / requestListScrollKey reads

5. Features/Requests/Views/RequestsDashboardView.swift
   - Consume intents, nil out pendingIntent after consumption

6. Features/Messaging/Views/ConversationsListView.swift
   - Observe pendingIntent for .conversation(id)

7. Features/Messaging/ViewModels/ConversationsListViewModel.swift
   - Consume .conversation intent

8. NaarsCarsTests/Core/Services/NavigationCoordinatorRoutingTests.swift
   - Update tests to verify intent-based routing

CRITICAL: The 11 NSNotification.Name observers in setupNotificationListeners() must continue
to work. AppDelegate still posts "navigateToRide", "navigateToConversation", etc.
The change is: each observer sets pendingIntent instead of individual properties.

COMPILE + TEST COMMAND:
  xcodebuild build -scheme NaarsCars -destination 'platform=iOS Simulator,name=iPhone 16'
  xcodebuild test -scheme NaarsCars -destination 'platform=iOS Simulator,name=iPhone 16'

VERIFICATION:
  grep -rn "PendingNotificationNavigation" NaarsCars/ --include="*.swift" | grep -v Tests
  # Expected: 0 results

  grep -rn "navigateToRide\|navigateToFavor\b\|navigateToConversation\b\|navigateToProfile\b" NaarsCars/ --include="*.swift" | grep -v Tests | grep -v "NSNotification"
  # Expected: 0 results (old properties removed)

DONE CRITERIA:
- xcodebuild build: 0 errors
- All tests pass (NavigationCoordinatorRoutingTests updated)
- NavigationCoordinator has 7 @Published properties (down from 20)
- PendingNotificationNavigation deleted
- Manual smoke: push notification → correct screen. Bell tap → correct screen. Deep link → correct screen.

IMPACT SUMMARY (update after completion):
List each file touched, properties added/removed, and why.

ROLLBACK: git revert. All 20 properties restored.
```

### E.4 Codex Phase 3 Execution Prompt

```
TASK: NaarsCars iOS — Phase 3: SyncEngine Protocol + Orchestrator

OBJECTIVE: Unify 3 sync engines behind a protocol. AppState/AppLaunchManager
orchestrates all engines through one interface. Remove direct engine references
from AuthService.

SCOPE BOUNDARY — STRICTLY ENFORCED:
- Create protocol + orchestrator in Core/Storage/
- Add pauseSync/resumeSync/teardown to each engine
- Update AuthService and AppLaunchManager to use orchestrator
- Do NOT touch NavigationCoordinator, BadgeCountManager, or ViewModels
- Do NOT add SQL migrations
- Do NOT edit project.pbxproj (user will add files to Xcode manually)

FILES TO CREATE (2 files):
1. NaarsCars/Core/Storage/SyncEngineProtocol.swift
   - @MainActor protocol SyncEngineProtocol: AnyObject
   - var engineName: String { get }
   - func setup(modelContext: ModelContext)
   - func startSync()
   - func pauseSync() async    // unsubscribe realtime channels
   - func resumeSync() async   // resubscribe realtime channels
   - func teardown() async     // unsubscribe + clear state

2. NaarsCars/Core/Storage/SyncEngineOrchestrator.swift
   - @MainActor final class SyncEngineOrchestrator
   - static let shared
   - func register(_ engine: SyncEngineProtocol)
   - func setupAll(modelContext: ModelContext)
   - func startAll()
   - func pauseAll() async
   - func resumeAll() async
   - func teardownAll() async
   - Guard against duplicate registration (check identity ===)

FILES TO MODIFY (7 files):
1. Core/Storage/MessagingSyncEngine.swift (144 LOC)
   - Conform to SyncEngineProtocol
   - var engineName = "messaging"
   - Add pauseSync(): await realtimeManager.unsubscribe(channelName: "messages:sync")
   - Add resumeSync(): setupMessagesSubscription()
   - Add teardown(): pauseSync() + nil out repository/model context state

2. Core/Storage/DashboardSyncEngine.swift (309 LOC)
   - Conform to SyncEngineProtocol
   - var engineName = "dashboard"
   - Add pauseSync(): unsubscribe "rides:sync", "favors:sync", "notifications:sync"
   - Add resumeSync(): re-setup subscriptions
   - Add teardown(): pauseSync() + clear cached data

3. Core/Storage/TownHallSyncEngine.swift (371 LOC)
   - Conform to SyncEngineProtocol
   - var engineName = "townHall"
   - Add pauseSync(): unsubscribe "town-hall-posts", "town-hall-comments", "town-hall-votes"
   - Add resumeSync(): re-setup subscriptions
   - Add teardown(): pauseSync() + clear state

4. Core/Services/AuthService.swift
   - restartRealtimeSyncEngines() (line 613): replace body with
     SyncEngineOrchestrator.shared.startAll()
   - signOut cleanup: add await SyncEngineOrchestrator.shared.teardownAll()

5. App/AppLaunchManager.swift
   - startDeferredSyncEnginesIfNeeded() (line 265): replace 3 direct calls with
     SyncEngineOrchestrator.shared.startAll()

6. App/NaarsCarsApp.swift
   - Register engines: SyncEngineOrchestrator.shared.register(MessagingSyncEngine.shared) etc.
   - Setup: SyncEngineOrchestrator.shared.setupAll(modelContext: context)

7. App/AppState.swift (116 LOC)
   - On userDidSignOut: await SyncEngineOrchestrator.shared.teardownAll()

COMPILE + TEST:
  xcodebuild build -scheme NaarsCars -destination 'platform=iOS Simulator,name=iPhone 16'
  xcodebuild test -scheme NaarsCars -destination 'platform=iOS Simulator,name=iPhone 16'

VERIFICATION:
  grep -rn "MessagingSyncEngine\|DashboardSyncEngine\|TownHallSyncEngine" \
    NaarsCars/Core/Services/AuthService.swift NaarsCars/App/AppLaunchManager.swift
  # Expected: 0 results (all routed through orchestrator)

DONE CRITERIA:
- xcodebuild build: 0 errors
- AuthService no longer directly references any *SyncEngine.shared
- AppLaunchManager no longer directly references any *SyncEngine.shared
- Sign-out calls teardownAll()
- All existing tests pass
- Manual smoke: messaging, dashboard, town hall sync all work normally

IMPACT SUMMARY (update after completion):
List each file touched, methods added/changed, and why.

ROLLBACK: git revert. AuthService reverts to direct engine calls. Engines lose
pause/teardown (harmless — they didn't have them before).
```

### E.5 Codex Phase 4 Execution Prompt

```
TASK: NaarsCars iOS — Phase 4: Badge Count Contract (Kill Client Fallback)

OBJECTIVE: Make get_badge_counts RPC the single authority for badge counts.
Add observability telemetry, a reversible kill switch, and a SQL resilience migration.
Remove client-side fallback computation.

SCOPE BOUNDARY — STRICTLY ENFORCED:
- Modify ONLY BadgeCountManager.swift + Constants.swift + new SQL migration
- Do NOT touch NavigationCoordinator, ViewModels, SyncEngines
- Do NOT remove calculateProfileBadgeCount() — profile badge stays client-computed
- Do NOT edit project.pbxproj

FILES TO MODIFY (2 Swift files):
1. Core/Services/BadgeCountManager.swift (541 LOC)
   - Add: @Published private(set) var isBadgeStale: Bool = false
   - Add: private var lastKnownCounts: BadgeCountsPayload?
   - In refreshAllBadges(), on RPC success: lastKnownCounts = counts; isBadgeStale = false
   - In refreshAllBadges(), on RPC failure:
     if FeatureFlags.badgeCountClientFallbackEnabled → use existing fallback
     else if lastKnownCounts exists → publish cached, isBadgeStale = true
     else → publish zeros, isBadgeStale = true
   - Add PerformanceMonitor telemetry in registerBadgeRpcFailure():
     PerformanceMonitor.shared.recordEvent("badge_rpc_failure", metadata: [...])
   - Add recovery telemetry when badgeRpcFailureCount > 0 and RPC succeeds
   - With kill switch disabled (default): DELETE fetchFallbackBadgeCounts() and
     calculateRequestsBadgeCount, calculateMessagesBadgeCount,
     calculateCommunityBadgeCount, calculateBellBadgeCount
   - Remove unused service properties: notificationService, conversationService,
     townHallService, messagingRepository
   - KEEP: adminService (for calculateProfileBadgeCount), authService, supabase, realtimeManager

2. Core/Utilities/Constants.swift
   - Add to FeatureFlags enum:
     static let badgeCountClientFallbackEnabled = false

FILE TO CREATE (1 SQL migration):
1. database/107_badge_counts_resilience.sql
   - CREATE OR REPLACE FUNCTION get_badge_counts(...)
   - Wrap every counter in COALESCE(..., 0)
   - Wrap detail arrays in COALESCE(..., '[]'::jsonb)
   - Do NOT change function signature or parameters

COMPILE + TEST:
  xcodebuild build -scheme NaarsCars -destination 'platform=iOS Simulator,name=iPhone 16'
  xcodebuild test -scheme NaarsCars -destination 'platform=iOS Simulator,name=iPhone 16'

VERIFICATION:
  grep -rn "fetchFallbackBadgeCounts\|calculateRequestsBadgeCount\|calculateMessagesBadgeCount\|calculateCommunityBadgeCount\|calculateBellBadgeCount" NaarsCars/ --include="*.swift"
  # Expected: 0 results (all removed)

  grep -rn "notificationService\|conversationService\|townHallService\|messagingRepository" NaarsCars/Core/Services/BadgeCountManager.swift
  # Expected: 0 results (unused imports removed)

DONE CRITERIA:
- xcodebuild build: 0 errors
- isBadgeStale published on RPC failure
- PerformanceMonitor events logged on failure + recovery
- fetchFallbackBadgeCounts deleted
- Unused service properties removed
- SQL migration 107 creates hardened RPC
- Manual smoke: badges work normally. Kill network → stale state. Restore → refresh.

IMPACT SUMMARY (update after completion):
List lines removed, properties removed, telemetry added.

ROLLBACK: git revert Swift. Set FeatureFlags.badgeCountClientFallbackEnabled = true.
SQL is additive (COALESCE backward-compatible).
```

### E.6 Codex Phase 5 Execution Prompt

```
TASK: NaarsCars iOS — Phase 5: ViewModel Decomposition

OBJECTIVE: Break 3 largest ViewModels under 500 LOC each by extracting manager objects.
Follow the ConversationSearchManager pattern (Features/Messaging/ViewModels/ConversationSearchManager.swift).

SCOPE BOUNDARY — STRICTLY ENFORCED:
- Create extracted manager files ONLY under Features/*/ViewModels/
- Modify ONLY the 3 target ViewModels
- Do NOT change service APIs, navigation, badge counts, or SQL
- Do NOT edit project.pbxproj (user will add files to Xcode manually)
- Do NOT change user-visible behavior — pure structural extraction

PATTERN TO FOLLOW (from ConversationSearchManager.swift):
  @MainActor
  final class ExtractedManager: ObservableObject {
      @Published var state: Type = ...
      func doWork() { ... }
  }
  // In parent:
  let manager = ExtractedManager()
  init() {
      manager.objectWillChange
          .sink { [weak self] _ in self?.objectWillChange.send() }
          .store(in: &managerCancellables)
  }

FILES TO CREATE (8 files):

1. Features/Notifications/ViewModels/NotificationGroupingManager.swift
   - Extract from NotificationsListViewModel (599 LOC)
   - Move: getFilteredNotifications(), getNotificationGroups(), grouping logic
   - Pure logic, no side effects

2. Features/Notifications/ViewModels/NotificationNavigationRouter.swift
   - Move: handleNotificationTap(), pendingNavigation(for:), handleAnnouncementTap()
   - Depends on NavigationCoordinator

3. Features/Notifications/ViewModels/NotificationRealtimeHandler.swift
   - Move: setupRealtimeSubscription(), handleRealtimeEvent()
   - Calls parent via closure for loadNotifications()

4. Features/Requests/ViewModels/RequestFilterManager.swift
   - Extract from RequestsDashboardViewModel (942 LOC)
   - Move: getFilteredRequests(), filterRequests(), filter badge counts

5. Features/Requests/ViewModels/RequestRealtimeHandler.swift
   - Move: 3 subscription setups + handleRideRealtimeEvent/handleFavorRealtimeEvent/handleRequestNotificationEvent + debounce logic

6. Features/Requests/ViewModels/RequestNotificationSummaryManager.swift
   - Move: unseenRequestKeys, requestNotificationSummaries, buildRequestNotificationSummaries()

7. Features/Messaging/ViewModels/MessagePaginationManager.swift
   - Extract from ConversationDetailViewModel (1107 LOC)
   - Move: loadMessages(), loadMoreMessages(), hasMoreMessages, reply context

8. Features/Messaging/ViewModels/MessageSendManager.swift
   - Move: sendMessage(), sendAudioMessage(), sendLocationMessage(), editMessage(), unsendMessage(), retryMessage(), dismissFailedMessage()

FILES TO MODIFY (3 ViewModels):
1. Features/Notifications/ViewModels/NotificationsListViewModel.swift (599 → ≤300)
2. Features/Requests/ViewModels/RequestsDashboardViewModel.swift (942 → ≤400)
3. Features/Messaging/ViewModels/ConversationDetailViewModel.swift (1107 → ≤450)

COMPILE + TEST:
  xcodebuild build -scheme NaarsCars -destination 'platform=iOS Simulator,name=iPhone 16'
  xcodebuild test -scheme NaarsCars -destination 'platform=iOS Simulator,name=iPhone 16'

VERIFICATION:
  wc -l NaarsCars/Features/*/ViewModels/*ViewModel.swift | sort -rn | head -5
  # All must be ≤ 500 LOC

DONE CRITERIA:
- xcodebuild build: 0 errors
- No ViewModel > 500 LOC
- All extracted managers are @MainActor final class: ObservableObject
- All parent ViewModels forward objectWillChange from child managers
- All existing tests pass
- Manual smoke: notifications grouping + tap routing, dashboard filters + realtime,
  messaging pagination + send/edit/unsend all work

IMPACT SUMMARY (update after completion):
List each file created, LOC, and which methods moved from which parent.

ROLLBACK: git revert. ViewModels restore to monolithic form.
```

### E.7 Codex Phase 6 Execution Prompt

```
TASK: NaarsCars iOS — Phase 6: Service Protocols + Dependency Injection

OBJECTIVE: Define protocols for top-10 services. ViewModels accept protocols via
initializer with .shared as default. Enable mock injection for testing.

SCOPE BOUNDARY — STRICTLY ENFORCED:
- Create protocol files in Core/Protocols/
- Add conformance to existing service singletons (no logic changes)
- Update ViewModel initializers to accept protocols (with .shared defaults)
- Replace ServiceName.shared references in ViewModel bodies with injected properties
- Do NOT change service implementations
- Do NOT change any navigation, badge, sync engine, or SQL code
- Do NOT edit project.pbxproj (user will add files to Xcode manually)

FILES TO CREATE (10 protocol files):
1. Core/Protocols/AuthServiceProtocol.swift
2. Core/Protocols/MessageServiceProtocol.swift
3. Core/Protocols/ConversationServiceProtocol.swift
4. Core/Protocols/RideServiceProtocol.swift
5. Core/Protocols/FavorServiceProtocol.swift
6. Core/Protocols/NotificationServiceProtocol.swift
7. Core/Protocols/ProfileServiceProtocol.swift
8. Core/Protocols/ClaimServiceProtocol.swift
9. Core/Protocols/ReviewServiceProtocol.swift
10. Core/Protocols/BadgeCountManaging.swift

PROTOCOL PATTERN:
  @MainActor
  protocol AuthServiceProtocol: AnyObject {
      var currentUserId: UUID? { get }
      var currentProfile: Profile? { get }
      // Only methods actually called by ViewModels
  }
  extension AuthService: AuthServiceProtocol {}  // Zero-change conformance

VIEWMODEL INJECTION PATTERN:
  final class SomeViewModel: ObservableObject {
      private let authService: any AuthServiceProtocol
      init(authService: any AuthServiceProtocol = AuthService.shared) { ... }
  }

FILES TO MODIFY (~30 files):
- 10 service files: add protocol conformance extension
- ~20 ViewModel files: add init parameters + replace .shared references in body

COMPILE + TEST:
  xcodebuild build -scheme NaarsCars -destination 'platform=iOS Simulator,name=iPhone 16'
  xcodebuild test -scheme NaarsCars -destination 'platform=iOS Simulator,name=iPhone 16'

VERIFICATION:
  grep -rn "AuthService\.shared\|MessageService\.shared\|RideService\.shared\|FavorService\.shared\|ConversationService\.shared" NaarsCars/Features/ --include="*.swift"
  # Expected: 0 results (all moved to injected properties)

DONE CRITERIA:
- xcodebuild build: 0 errors
- 10 protocol files in Core/Protocols/
- All ViewModel .shared references replaced with injected properties
- Default parameter values mean zero changes to View call sites
- All tests pass

IMPACT SUMMARY (update after completion):
List each protocol created, methods included, and which ViewModels updated.

ROLLBACK: git revert. Protocols removed, .shared references restored.
```

### E.8 Codex Phase 7 Execution Prompt

```
TASK: NaarsCars iOS — Phase 7: Notification Type Registry

OBJECTIVE: Create a single canonical list of notification types. Add compile-time
validation in Swift, CHECK constraint in SQL, const object in TypeScript,
and a cross-stack validation script.

SCOPE BOUNDARY — STRICTLY ENFORCED:
- Create registry + validation in Swift, SQL, TS
- Do NOT change NotificationType enum cases or raw values
- Do NOT change push notification behavior
- Do NOT edit project.pbxproj (user will add files to Xcode manually)
- Do NOT change existing tests beyond adding registry validation

FILES TO CREATE (4 files):
1. NaarsCars/Core/Models/NotificationTypeRegistry.swift
   - enum NotificationTypeRegistry with:
     static let allTypes: Set<String> (all 30 raw values)
     #if DEBUG static func validateRegistry() — asserts allCases match allTypes
   - NotificationType must conform to CaseIterable (add if not present)

2. database/108_notification_type_check_constraint.sql
   - ALTER TABLE notifications ADD CONSTRAINT valid_notification_type
     CHECK (type IN ('message', 'added_to_conversation', ... all 30 ...));
   - Include all 30 raw values from NotificationType enum

3. supabase/functions/_shared/notificationTypes.ts
   - export const NOTIFICATION_TYPES = { MESSAGE: 'message', ... } as const
   - export type NotificationType = typeof NOTIFICATION_TYPES[keyof typeof NOTIFICATION_TYPES]

4. scripts/validate-notification-types.sh
   - Extract types from Swift enum, compare with TS const
   - Exit 0 if match, exit 1 with diff if mismatch

FILES TO MODIFY (3 files):
1. Core/Models/AppNotification.swift
   - Add CaseIterable conformance to NotificationType if not present
   - Add #if DEBUG call to NotificationTypeRegistry.validateRegistry() in a static initializer or test

2. supabase/functions/send-notification/index.ts
   - Import NOTIFICATION_TYPES from _shared/notificationTypes.ts
   - Replace string literals with NOTIFICATION_TYPES.XXX

3. supabase/functions/send-message-push/index.ts
   - Same: import and use NOTIFICATION_TYPES

COMPILE + TEST:
  xcodebuild build -scheme NaarsCars -destination 'platform=iOS Simulator,name=iPhone 16'
  xcodebuild test -scheme NaarsCars -destination 'platform=iOS Simulator,name=iPhone 16'
  bash scripts/validate-notification-types.sh

VERIFICATION:
  bash scripts/validate-notification-types.sh
  # Expected: exit 0

DONE CRITERIA:
- xcodebuild build: 0 errors
- validateRegistry() passes in DEBUG builds
- SQL constraint applied (invalid type → insert fails)
- Edge functions use NOTIFICATION_TYPES constants (no string literals)
- validate-notification-types.sh exits 0

IMPACT SUMMARY (update after completion):
List files created/modified and validation results.

ROLLBACK: git revert Swift + TS.
SQL: ALTER TABLE notifications DROP CONSTRAINT IF EXISTS valid_notification_type;
```

---

## Appendix: Phase 0 Regression Checklist Template

Copy this into a QA ticket or checklist after each phase merge:

```markdown
## Regression Checklist — Post-Phase {N}

### Messaging
- [ ] Send text message → appears in conversation for both sender and recipient
- [ ] Send image message → thumbnail appears, tap to view full image
- [ ] Send audio message → playback works
- [ ] Message edit → updated text visible to both parties
- [ ] Message unsend → removed from conversation
- [ ] Typing indicator appears when other user is typing
- [ ] Conversation list sorted by most recent message

### Claiming
- [ ] Claim a ride → status changes to "claimed" on both poster's and claimer's view
- [ ] Unclaim a ride → status reverts to "open"
- [ ] Claim a favor → same behavior as ride claim
- [ ] Unclaim a favor → same behavior as ride unclaim

### Badge Counts
- [ ] New message → Messages tab badge increments
- [ ] Open conversation → Messages tab badge decrements (mark as read)
- [ ] New ride posted → Requests tab badge increments
- [ ] App icon badge reflects total unread count

### Notification Tap Routing
- [ ] Tap message push notification → opens conversation
- [ ] Tap ride_claimed notification → opens ride detail with claims section
- [ ] Tap favor_completed notification → opens favor detail
- [ ] Tap town_hall_comment notification → opens post with comments
- [ ] Tap announcement notification → opens announcements
- [ ] Tap notification in bell sheet → bell dismisses → navigates to correct screen

### General
- [ ] Tab switching works (all 4 tabs accessible)
- [ ] Sign out → clears state, no orphan subscriptions
- [ ] App launch < 1 second (no regression)
- [ ] Background → foreground: realtime reconnects, badges refresh
```
