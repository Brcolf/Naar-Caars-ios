# Naar's Cars iOS — Deep Codebase Audit Report

**Date:** 2026-03-16
**Scope:** Full codebase analysis for permanent development guardrail generation
**Files analyzed:** ~435 Swift files, 34 migrations, 3 edge functions, project configuration

---

## 1 — Architecture Overview

### Pattern: MVVM + Local-First with Realtime Sync

The app uses **Model-View-ViewModel (MVVM)** with a **local-first, server-authoritative** data architecture backed by Supabase.

### Layer Map

| Layer | Location | Technology |
|-------|----------|------------|
| **View** | `Features/*/Views/`, `UI/Components/` | SwiftUI (~90%), UIKit for messaging collection view |
| **ViewModel** | `Features/*/ViewModels/` | `@MainActor ObservableObject` with `@Published` properties |
| **Service** | `Core/Services/` | Singleton services with protocol abstractions |
| **Protocol** | `Core/Protocols/` | 10 service protocols (AuthServiceProtocol, etc.) |
| **Model** | `Core/Models/` | Codable structs (22 model files) |
| **Storage** | `Core/Storage/` | SwiftData `@Model` classes + Repositories + Sync Engines |
| **Realtime** | `Core/Services/RealtimeManager.swift` | Supabase Realtime websocket subscriptions |
| **Networking** | `Core/Services/SupabaseService.swift` | Direct Supabase client calls (no REST abstraction) |
| **Utilities** | `Core/Utilities/` | 30+ utilities (caching, rate limiting, date handling, etc.) |

### Data Flow

```
Supabase (PostgreSQL + RLS) ← Source of truth
    ↕ Realtime websocket events
RealtimeManager → Sync Engines (3)
    ↕ Parse + upsert
SwiftData (local @Model cache)
    ↕ Combine publishers
Repositories → ViewModels (@Published)
    ↕ SwiftUI bindings
Views (@State, @StateObject, @EnvironmentObject)
```

### Entry Point & Launch

- `NaarsCarsApp.swift` (`@main`): Initializes Firebase, SwiftData ModelContainer, 3 sync engines, theme
- `AppLaunchManager`: Critical-path launch (<1s) — check session, show UI, defer loading
- `AppDelegate`: Push registration, background refresh (15-min), MetricKit, notification actions
- Launch state: `.initializing` → `.checkingAuth` → `.ready(authState)`

### Tab Structure (4 tabs)

| Tab | Content | Badge Source |
|-----|---------|-------------|
| Requests | Rides + Favors dashboard | Request count |
| Messages | Conversations list | Unread message count |
| Community | Town Hall + Leaderboards | Community notification count |
| Profile | Settings + Admin panel | Profile notification count |

### Navigation

- **NavigationCoordinator** (singleton): Manages `NavigationIntent` enum (15 cases) for deep linking
- Deferred navigation: Push tap → store intent → dismiss sheet → apply navigation
- Tab selection, scroll targets, and confirmation dialogs all centralized

### Dependency Injection

- **Strategy**: Singleton services + Environment Objects
- **Singletons**: 45+ services via `static let shared` with `private init()`
- **Environment**: `AppState`, `ThemeManager`, `ModelContainer` injected at root
- **ViewModel DI**: Constructor injection with `.shared` defaults (enables testing)
- **No DI container**: Services self-initialize and access each other via `.shared`

### Dependencies (SPM)

| Package | Version | Purpose |
|---------|---------|---------|
| supabase-swift | ≥2.5.1 | Backend (DB, auth, realtime, storage) |
| firebase-ios-sdk | ≥12.8.0 | Push notifications (APNs) + Crashlytics |
| PhoneNumberKit | ≥4.0.0 | Phone number parsing |

### Build Configuration

| Setting | Value |
|---------|-------|
| Deployment Target | iOS 17.0 |
| Swift Version | 5.9+ |
| Orientation | Portrait only |
| Architecture | arm64 |
| Marketing Version | 1.7 |

### Entitlements

- `aps-environment`: production (push notifications)
- `com.apple.developer.applesignin`: Sign in with Apple
- Background modes: `remote-notification`, `fetch`

### Info.plist Privacy Strings

| Permission | Description |
|-----------|-------------|
| NSCameraUsageDescription | Photos for reviews and posts |
| NSFaceIDUsageDescription | Quick and secure app unlock |
| NSLocationWhenInUseUsageDescription | Show location on map for nearby requests |
| NSMicrophoneUsageDescription | Record audio messages in conversations |
| NSPhotoLibraryUsageDescription | Profile picture and message images |
| NSCalendarsFullAccessUsageDescription | Add confirmed requests to calendar |

---

## 2 — Messaging + Realtime Systems

### Message Storage

**Dual-layer architecture:**

| Layer | Technology | Role |
|-------|-----------|------|
| Remote | Supabase `messages` table | Source of truth |
| Local | SwiftData `SDMessage` | Read-through cache + pending send queue |

**SDMessage fields**: id, conversationId, fromId, text, imageUrl, readBy[], createdAt, messageType, replyToId, audioUrl, audioDuration, latitude, longitude, locationName, editedAt, deletedAt, status (sending/sent/delivered/failed/read), isPending, localAttachmentPath, syncError

### Message Types

Text, image, audio, location, link preview, emoji-only (large render), system messages (user left, etc.)

### Reaction System (iMessage-style Tapbacks)

- **Model**: `MessageReaction` (id, messageId, userId, reaction emoji, createdAt)
- **Standard reactions**: heart, thumbsUp, thumbsDown, laughing, exclamation, question
- **Storage**: `message_reactions` table (Supabase) + local SwiftData
- **Data invariant**: `Message.setIndividualReactions(_:)` is the ONLY way to update — maintains `individualReactions` (source of truth) → derives `reactions` (aggregated view)
- **Per-person badges**: UI renders who reacted with what (iMessage parity)
- **Position**: Badges render at TOP of message bubble (not bottom)

### Realtime Subscriptions

| Channel | Table | Events | Scope |
|---------|-------|--------|-------|
| `messages:sync` | messages | INSERT, UPDATE, DELETE | Global |
| `reactions:{convId}` | message_reactions | INSERT, DELETE | Per-conversation |
| `typing:{convId}` | N/A (ephemeral) | Broadcast | Per-conversation |
| `rides:sync` | rides | INSERT, UPDATE, DELETE | Global |
| `favors:sync` | favors | INSERT, UPDATE, DELETE | Global |
| `notifications:sync` | notifications | INSERT, UPDATE, DELETE | Filtered by user_id |
| `town-hall-posts` | town_hall_posts | INSERT, UPDATE, DELETE | Global |
| `town-hall-comments` | town_hall_comments | INSERT, UPDATE, DELETE | Global |
| `town-hall-votes` | town_hall_votes | INSERT, UPDATE, DELETE | Global |

### Realtime Event Pipeline

1. `RealtimeManager.subscribe()` → creates Supabase Realtime channel
2. `RealtimePayloadAdapter.decode*()` → normalizes `[String: Any]` to `RealtimeRecord`
3. Sync engine handler → parse + filter (blocked users, read-only changes)
4. `MessagingRepository.upsertMessageDetailed()` → returns change type
5. Repository refreshes Combine publishers → ViewModel updates

### Message Sending (Optimistic + Durable)

1. **Optimistic insert**: Create local `SDMessage` with `status="sending"`, `isPending=true`
2. **Immediate UI update**: Repository emits via `messageSubjects[conversationId]`
3. **Background send**: `MessageSendWorker` actor watches for pending messages
4. **On success**: Swap local UUID with server UUID, set `status="sent"`
5. **On failure**: Set `status="failed"`, store `syncError`

**MessageSendWorker details:**
- Monitors NWPathMonitor for network availability
- Exponential backoff: 1s initial → 30s max, 5 retries max
- Media upload: images → `message-images` bucket, audio → `message-audio` bucket
- Cleanup: removes local attachment files after successful send

### Read Receipts

- `Message.readBy`: UUID array of readers
- `ConversationParticipant.lastSeen`: Timestamp of last view
- `ConversationParticipant.showReadReceipts`: User opt-in preference
- Throttled updates (Constants.RateLimits.throttleLastSeen)
- Metadata-only updates via separate PassthroughSubject (no full list re-render)

### Typing Indicators

- Ephemeral Supabase Realtime broadcast (not database-backed)
- Debounced ~500ms on send
- Auto-clears after ~3s timeout

### Thread/Reply System

- `Message.replyToId`: UUID of parent message
- `ReplyContext`: Lightweight struct (id, text, senderName, senderId, imageUrl) — NOT stored in DB
- Hydrated on-demand via `MessageService.fetchMessageContext()`
- Reply counts tracked per message in `ConversationDetailViewModel.replyCountMap`

### Race Condition Risks

| Risk | Scenario | Mitigation |
|------|----------|-----------|
| Duplicate messages | Optimistic insert + realtime insert from same user | Deduplication by ID on upsert |
| Lost read receipts | Rapid mark-read → send reply | Throttling + realtime sync |
| Message ordering | Out-of-order realtime arrivals | Sort by `createdAt` after each batch |
| Reaction race | User adds reaction while being fetched | Upsert semantics; optimistic apply ignores duplicates |
| Conversation stale | Pagination skips newly-created conversations | Sync from `updated_at` DESC |
| Pending send + crash | Message stuck in "sending" | MessageSendWorker resumes from SwiftData on restart |
| Reply context missing | Parent message deleted or never synced | Graceful nil handling |

### Authoritative State

- **Before server ACK**: Local SwiftData (optimistic)
- **After server ACK**: Server becomes source, SwiftData syncs via realtime
- **Conflict resolution**: Server always wins; local state rolls back on failure

---

## 3 — State Management

### Root-Level State

| Object | Type | Injected Via | Purpose |
|--------|------|-------------|---------|
| `AppState` | `@MainActor ObservableObject` | `@EnvironmentObject` | User profile mirror, auth state, admin/approved flags |
| `ThemeManager` | `@StateObject` | `@EnvironmentObject` | Dark mode preference |
| `ModelContainer` | SwiftData | `.modelContainer()` modifier | Local database access |

### Singleton Services (ObservableObject / @Observable)

All use `static let shared` + `private init()`:

- `AuthService`: `@Published currentUserId`, `currentProfile`, `isLoading`
- `BadgeCountManager`: `@Published counts: BadgeCounts`, `isBadgeStale`
- `AppLockManager`: `@Observable` with state enum (unlocked/locked/authenticating)
- `NavigationCoordinator`: `selectedTab`, `pendingIntent`, `navigationPath`
- `NetworkMonitor`: `@Published isConnected`, `connectionType`
- `PushNotificationService`: `@Published isAuthorized`, `pendingDeepLink`
- `CrashReportingService`: `@Published isEnabled`
- `InAppToastManager`: `@Published latestToast`
- `SupabaseService`: `@Published isConnected`, `lastError`
- `LocationService`: `@Published recentLocations`

### ViewModel Patterns

All ViewModels follow:
```swift
@MainActor
final class SomeViewModel: ObservableObject {
    @Published var data: [Model] = []
    @Published var isLoading = false
    @Published var error: AppError?

    private let service: any ServiceProtocol  // DI with .shared default
    private var cancellables = Set<AnyCancellable>()
    private var loadTask: Task<Void, Never>?  // Cancellation safety
}
```

### State Flow: Services → ViewModels → Views

1. **Services** fetch from Supabase, return Codable models
2. **Sync engines** upsert to SwiftData, notify via Combine subjects
3. **Repositories** expose `CurrentValueSubject` publishers
4. **ViewModels** subscribe via `.sink()`, update `@Published` properties
5. **Views** bind to `@Published` via SwiftUI's observation

### @MainActor Usage

- All ViewModels: `@MainActor`
- All repositories: `@MainActor`
- All singleton managers: `@MainActor`
- Background work: `BackgroundSyncActor` (`@ModelActor actor`)

### Architectural Risks

1. **State duplication**: AppState mirrors AuthService.currentProfile via Combine — can desync if subscription breaks
2. **125+ `.shared` usages**: Heavy singleton coupling across Features/ — no dependency graph validation
3. **Circular dependency potential**: BadgeCountManager → AdminService → AuthService
4. **SwiftData versioning**: Relies on automatic migration (additive only) — breaking changes require `.deleteStoreFiles()` (loses all local data)
5. **Incomplete repository pattern**: Only 3 repositories (Messaging, Notification, TownHall) — Dashboard syncs directly via engine
6. **LeaderboardEntry.isCurrentUser**: Computed property calls `AuthService.shared` — timing risk during init

---

## 4 — Networking Layer

### Backend: Supabase (PostgreSQL + Auth + Realtime + Storage)

**Project ref**: `easlpsksbylyceqiqecq`

### API Call Patterns

All networking uses direct Supabase client calls (no REST abstraction layer):

```swift
// SELECT
try await supabase.from("table").select(...).eq("field", value:).execute()

// INSERT
try await supabase.from("table").insert(data).select().single().execute()

// UPDATE
try await supabase.from("table").update(updates).eq("id", value:).execute()

// DELETE
try await supabase.from("table").delete().eq("id", value:).execute()

// RPC (stored procedures)
try await supabase.rpc("function_name", params: [...]).execute()
```

### RPC Functions (14+)

| Function | Purpose |
|----------|---------|
| `get_badge_counts` | Tab bar badge counts |
| `get_conversations_with_details` | Conversation list with unread counts |
| `find_dm_conversation` | Find existing DM between two users |
| `mark_messages_read_batch` | Batch mark messages as read |
| `get_user_badges` | Earned badges |
| `create_xp_leaderboard` | XP leaderboard with rankings |
| `create_leaderboard_spotlights` | Featured spotlights |
| `handle_completion_response` | Mark completion reminder done |
| `cleanup_orphaned_auth_user` | Delete auth user if profile creation fails |
| `delete_user_account` | Cascading user data deletion |
| `admin_reject_pending_user` | Admin rejection |
| `admin_get_reports` | Fetch admin reports |
| `admin_moderate_content` | Moderate reported content |
| `create_signup_profile` | SECURITY DEFINER — create profile on signup |

### Error Handling

**AppError enum** with user-friendly descriptions:
- `networkUnavailable`, `serverError`, `invalidCredentials`, `sessionExpired`
- `unauthorized`, `rateLimited`, `notFound`, `invalidInviteCode`, `conversationFrozen`

**Pattern:**
1. Service methods throw `AppError`
2. ViewModel catches and stores in `@Published var error: AppError?`
3. View displays user-friendly message
4. Non-fatal errors recorded to Crashlytics

**Lenient decoding**: Per-item try/catch (one bad notification doesn't kill the list)

### Retry Logic

**RetryableOperation utility:**
- `maxAttempts: 3`, `initialDelay: 1.0s`, `backoffMultiplier: 2.0`, `maxDelay: 10.0s`
- Custom `shouldRetry` predicate

**RequestDeduplicator actor:**
- Prevents concurrent duplicate requests (cache stampede protection)
- In-flight tracking by key
- Concurrent calls wait for first result

### Rate Limiting

| Operation | Interval |
|-----------|----------|
| Login attempts | 2 seconds |
| Invite code validation | 3 seconds |
| Message sends | 1 second |
| Town Hall posts | 30 seconds |
| Town Hall comments | 10 seconds |
| Claim requests | 10 seconds |
| Mark read messages | 0.5 seconds |

### Authentication Tokens

- Supabase JWT-based authentication
- Session stored in Keychain (`com.naarscars.supabase.auth`)
- `startAutoRefresh()` keeps token fresh
- Auth state listener updates realtime channel auth on changes
- APNs token also stored in Keychain (not UserDefaults)

### Secrets

- `Secrets.swift`: XOR-obfuscated with "NaarsCars" key (NOT encryption)
- `.gitignore`d — not committed to source control
- Validated via `Secrets.isConfigured` property
- Actual security relies on RLS policies, not client-side obfuscation

### Network Monitoring

- `NetworkMonitor.shared`: Uses `NWPathMonitor`
- `@Published isConnected`, `connectionType`
- `OfflineBannerModifier`: Red banner shown when offline
- No automatic retry in base services — callers must handle

---

## 5 — Data Storage

### Persistence Systems

| System | Technology | Scope | TTL/Lifecycle |
|--------|-----------|-------|---------------|
| **Server DB** | Supabase PostgreSQL | All authoritative data | Permanent |
| **Local DB** | SwiftData | Entity cache (7 @Model classes) | App session; cleared on corruption |
| **Memory Cache** | CacheManager actor | Profiles, rides, favors, messages | TTL-based (30s–5min) |
| **Badge Cache** | BadgeCache + BadgeCountManager | Leaderboard badges, tab counts | 1 hour / 30-90s polling |
| **Disk (temp)** | LocalAttachmentStorage | Pending message attachments | Until uploaded |
| **Disk (persistent)** | UserDefaults | Conversation names, timestamps, settings | Persists across sessions |
| **Image Cache** | PersistentImageService | Cached profile/message images | Disk-backed |
| **Map Cache** | MapSnapshotCache (NSCache) | Map snapshots | 50 items / 20MB |
| **URL Cache** | URLDetectionCache (NSLock) | NSDataDetector regex results | Unbounded (risk) |
| **Geocoding Cache** | GeocodingCacheService | Supabase `geocoding_cache` table | 72 hours |

### SwiftData Models

| Model | Purpose | Unique Key |
|-------|---------|-----------|
| `SDConversation` | Conversations with unread count | `@Attribute(.unique) id` |
| `SDMessage` | Messages with send status tracking | `@Attribute(.unique) id` |
| `SDDeletedMessage` | "Delete for Me" tracking (local only) | `@Attribute(.unique) messageId` |
| `SDRide` | Ride request cache with profile snapshots | `@Attribute(.unique) id` |
| `SDFavor` | Favor request cache with profile snapshots | `@Attribute(.unique) id` |
| `SDNotification` | Notification cache with deep link IDs | `@Attribute(.unique) id` |
| `SDTownHallPost` | Forum posts with author snapshots | `@Attribute(.unique) id` |
| `SDTownHallComment` | Nested comments | `@Attribute(.unique) id` |

**Relationships**: `SDConversation` → `SDMessage` with `.cascade` delete rule

### Sync Engines

| Engine | Scope | Realtime Channels | Debounce |
|--------|-------|------------------|----------|
| `DashboardSyncEngine` | Rides, favors, notifications | 3 channels | 2 seconds |
| `MessagingSyncEngine` | Conversations, messages, reactions | 2+ channels (dynamic) | Immediate (event-driven) |
| `TownHallSyncEngine` | Posts, comments, votes | 3 channels | 600ms |

**Orchestrator**: `SyncEngineOrchestrator` coordinates lifecycle (setup → start → pause → resume → teardown)

**BackgroundSyncActor**: `@ModelActor actor` for off-MainActor SwiftData writes — batch upserts with single `modelContext.save()` call

### Source of Truth

- **Server (Supabase)**: Authoritative for all entity data
- **Local (SwiftData)**: Read-through cache for UI + pending send queue
- **Conflict resolution**: Server wins; realtime events patch local storage incrementally
- **Fallback**: If payload parsing fails, trigger full sync (conservative approach)

### UserDefaults Usage

- Conversation display name cache (LRU, max 1000)
- Badge manager last-viewed timestamps
- Theme preference
- Hidden conversations per user
- Biometric preferences
- Push permission request tracking
- Last push payload (diagnostic)

### Cache TTLs (from Constants)

| Cache | TTL |
|-------|-----|
| Profiles | 5 minutes |
| Rides/Favors | 2 minutes |
| Notifications/Conversations | 1 minute |
| Messages | 30 seconds |
| Town Hall Posts | 2 minutes |
| Leaderboard | 15 minutes |
| Badges | 1 hour |

---

## 6 — Notifications

### Push Notification Flow

1. App launch → `registerForRemoteNotifications()` (APNs)
2. APNs token → stored in Keychain + registered with Supabase `push_tokens` table
3. Backend creates `notification_queue` row
4. Webhook triggers `send-notification` edge function
5. Function fetches tokens + badge count → sends APNs payload
6. User taps → `AppDelegate` handles action → `DeepLinkParser` → `NavigationCoordinator`

### Notification Categories & Actions

| Category | Actions |
|----------|---------|
| COMPLETION_REMINDER | Yes / No |
| MESSAGE | Quick Reply (text input) + Mark as Read |
| NEW_REQUEST | View Details |
| REQUEST_CLAIMED | Add to Calendar + View Details |

### Deep Link Routing

| Notification Type | Routes To |
|-------------------|-----------|
| message, added_to_conversation | Conversation detail |
| new_ride, ride_*, review_*, qa_* | Ride or Favor detail |
| review_received | User profile |
| town_hall_post/comment/reaction | Town Hall post |
| pending_approval | Admin pending users |
| announcement, broadcast | Announcements view |

### In-App Toast System

- `InAppToastManager`: Shows toast when message arrives while app active
- Suppressed if: conversation muted, user actively viewing conversation (60s window), app not active
- Auto-dismiss after 4 seconds
- Tap navigates to conversation

### Badge Count Management

- `BadgeCountManager`: Polls `get_badge_counts` RPC (30s connected, 90s disconnected)
- Debounce: minimum 2.5s between refreshes
- Exponential backoff on RPC failure (5s → 120s)
- Schema failure: 5-minute backoff
- Falls back to cached counts with `isBadgeStale` flag
- App icon badge: `UIApplication.shared.applicationIconBadgeNumber`

### Notification Grouping

- Groups by: announcement ID, town hall postId, ride/favor ID
- 24-hour stale threshold: read notifications older than 24h removed from feed
- Bell feed excludes message types (those go to Messages tab)
- Pinned announcements kept for 7 days

### Background Notifications

- `UIBackgroundModes`: `remote-notification`, `fetch`
- Background app refresh: 15-minute intervals → `DashboardSyncEngine.syncAll()`
- `content-available: 1` for silent updates

### Edge Functions (Server-Side Push)

| Function | Trigger | Purpose |
|----------|---------|---------|
| `send-notification` | Webhook on `notification_queue` INSERT | General push delivery |
| `send-message-push` | Webhook on `messages` INSERT | Message-specific push with smart filtering |

**Smart filtering in `send-message-push`:**
- Skips users who viewed conversation <60s ago
- Respects per-conversation mute settings
- Rate limits: >10 messages/minute from sender → skip
- Batch sends (max 10 concurrent)

### NSNotification (Internal Events)

Key internal notification names used:
- `.conversationUpdated`, `.conversationUnreadCountsUpdated`
- `.notificationsDidSync`, `.ridesDidSync`, `.favorsDidSync`
- `.messageThreadDidAppear/Disappear` (toast suppression)
- `.showCompletionPrompt`, `.dismissNotificationsSurface`
- `.languageDidChange`, `.userDidSignOut`

---

## 7 — Authentication + Account Systems

### Authentication Methods

1. **Email/Password**: Supabase Auth with invite code validation
2. **Apple Sign-In**: Nonce-based security (SHA256), handled via ASAuthorizationController

### Sign-Up Flow (Email/Password)

1. Validate invite code (rate limited, 3s between attempts)
2. Create auth user via `Supabase.auth.signUp()`
3. Poll for profile creation (exponential backoff: 100ms → 1600ms)
4. RPC: `create_signup_profile` (SECURITY DEFINER, bypasses RLS)
5. RPC: `mark_invite_code_used` (handles bulk vs single-use differently)
6. Cleanup orphaned auth user if signup fails partway
7. Register device token for push

### Session Handling

- JWT stored in Keychain (`com.naarscars.supabase.auth`)
- `startAutoRefresh()` keeps token fresh automatically
- Auth state listener updates realtime channel auth on changes
- Session check on every app launch → determines auth state

### Account Deletion

- `delete_user_account()` RPC with cascading delete:
  - push_tokens, notifications, reviews, town_hall_posts
  - invite_codes, messages, conversation_participants, conversations
  - rides, favors, request_qa, profiles
  - **Also deletes `auth.users` record** (allows email re-use)
- Apple Sign-In token revocation via `revoke-apple-token` edge function

### Sign-Out Cleanup

- `Supabase.auth.signOut()`
- Clear local state (currentUserId, currentProfile)
- Post `.userDidSignOut` notification
- Remove device token from database
- Clear all caches via `CacheManager.clearAll()`
- Unsubscribe from realtime channels
- Tear down sync engines
- Clear crash reporting context

### Biometric Lock

- Optional FaceID/TouchID unlock via `AppLockManager`
- 5-minute inactivity timeout before re-lock
- Locks on app background (if enabled)
- State machine: `.unlocked` → `.locked` → `.authenticating` → `.unlocked`

### Invite Code System

- **Single-use codes**: 8 chars, base32 alphanum, never expire
- **Bulk codes**: Admin-only, expire 48 hours
- Uniqueness check with 3 retry attempts
- Format: uppercase, trimmed
- Same error for all failures (prevent enumeration)

---

## 8 — Apple App Store Compliance Review

### Privacy Strings: PASS

All required `NS*UsageDescription` strings present for: Camera, FaceID, Location (WhenInUse only), Microphone, Photo Library, Calendar.

### Background Location: PASS

Only `NSLocationWhenInUseUsageDescription` used — no background location or always-on tracking.

### User-Generated Content Moderation: PASS

- **Message reporting**: ReportMessageSheet with type selection + description
- **Post reporting**: ReportContentSheet for Town Hall
- **User blocking**: BlockedUsersView with unblock capability
- **Admin panel**: AdminReportsView for content moderation with action/notes
- **Admin moderation RPC**: `admin_moderate_content` with SECURITY DEFINER

### Reporting/Blocking: PASS

- Users can report messages and posts
- Users can block other users
- Blocked user content filtered from feed
- Admin can moderate flagged content

### Account Deletion: PASS

- `delete_user_account()` RPC with full cascading delete
- Apple Sign-In token revocation via edge function
- Compliant with Apple's account deletion requirement

### Tracking: LOW RISK

- Firebase Crashlytics (opt-out via UserDefaults `crash_reporting_enabled`)
- No advertising SDK
- No tracking SDK (no ATT framework usage detected)
- MetricKit for performance (first-party)

### Third-Party SDK Privacy: LOW RISK

| SDK | Data Collected | Privacy Impact |
|-----|---------------|----------------|
| Supabase | Auth tokens, user data | Backend provider — controlled |
| Firebase Crashlytics | Crash reports, device info | Google — privacy manifest needed |
| PhoneNumberKit | Phone number format | Local processing only |

### Potential Concerns

1. **Firebase privacy manifest**: Ensure `PrivacyInfo.xcprivacy` includes Firebase SDK data collection disclosures
2. **conversation_participants RLS disabled**: Technically a security concern — enforced at app level, but unusual
3. **Secrets obfuscation**: XOR is not encryption — App Store review unlikely to flag, but security-conscious reviewers might note
4. **Edge function JWT verification disabled**: Both push functions have `verify_jwt = false` — controlled via webhook trust, but documents an unusual pattern
5. **Town Hall misinformation**: Voting system without fact-checking or misinformation flags

---

## 9 — Performance Risks

### UI Performance

1. **MessagesCollectionView**: UIKit `UICollectionView` wrapped in SwiftUI — good for large message lists
   - Uses native `MessageContentCell` (not UIHostingConfiguration) — avoids SwiftUI overhead
   - Flip transform (`scaleY: -1`) for bottom-up rendering
   - Incremental cell config recomputation (only changed messages)
   - **Risk**: Falls back to full recompute for >3 message changes — could be slow for batch operations

2. **ConversationDetailViewModel**: Largest ViewModel (~817 lines) with complex composition
   - `messages` didSet triggers `recomputeCellConfigurations()` + `recomputeUnreadCount()` on every change
   - Metadata-only changes use separate publisher to avoid full list diffs
   - **Risk**: Rapid message arrival could trigger excessive recomputation

3. **CachedAsyncImage**: Custom replacement for AsyncImage with disk caching
   - Checks `PersistentImageService` before network
   - **Risk**: No memory pressure handling — could accumulate stale entries

### Data Fetching

4. **N+1 Query Prevention**: Batch profile fetches throughout (single query for IDs)
   - But some ViewModels still do individual fetches for edge cases

5. **Pagination**: Offset-based for conversations (10/page), cursor-based for messages
   - Town Hall: 20 posts per page
   - **Risk**: Offset-based pagination can skip/duplicate items during concurrent inserts

6. **Realtime Event Debouncing**:
   - Dashboard: 2s coalesce window
   - Town Hall: 600ms
   - **Risk**: Rapid-fire events within debounce window trigger full sync on expiry

### Memory

7. **URLDetectionCache**: No size limit — grows unbounded with unique message texts
8. **CacheManager profiles**: No explicit memory limit — TTL-based cleanup only on access (lazy)
9. **FlightInfo.displayInfoCache**: Static dictionary — never cleared
10. **MapSnapshotCache**: NSCache with 50 item / 20MB limit — properly bounded

### Concurrency

11. **BackgroundSyncActor**: Proper `@ModelActor` isolation for off-MainActor writes
12. **Task cancellation**: ViewModels track `loadTask` and cancel in `stop()` — good pattern
13. **Realtime subscription cleanup**: Proper in sync engine `teardown()` methods
14. **Risk**: BadgeCountManager NotificationCenter observers added in init without explicit removal (singleton never deallocates, so acceptable but fragile)

---

## 10 — Code Quality Risks

### Duplicate Logic

1. **Date parsing**: Multiple services implement their own ISO8601 decoder instead of using shared `DateDecoderFactory`
2. **Profile enrichment**: Both `RideService` and `FavorService` independently implement batch profile fetch + merge logic
3. **Notification filtering**: Filter logic duplicated between `NotificationGrouping` (client) and edge functions (server)

### Weak Architecture Boundaries

4. **Service-to-service coupling**: Services directly access other singletons (e.g., `TownHallService` → `MessageService.isBlocked()`)
5. **View → Service shortcuts**: Some views bypass ViewModel and call services directly
6. **Repository inconsistency**: Messaging/TownHall use repository pattern; Dashboard syncs directly via engine

### Tight Coupling

7. **125+ `.shared` usages**: No dependency graph — refactoring one service requires checking all consumers
8. **LeaderboardEntry.isCurrentUser**: Computed property reaches into `AuthService.shared` singleton
9. **NotificationType enum**: 31 cases with properties in 3+ locations (enum, registry, preferenceKey, canBeDisabled, icon)

### Threading Issues

10. **conversation_participants RLS disabled**: Security enforced at Swift layer only — bypassed by direct DB access
11. **Sendable conformance gaps**: Models with optional joined `Profile?` fields — Profile is Sendable but pattern is fragile
12. **Mutable AppNotification fields**: `read` and `pinned` are mutable on otherwise immutable struct — no state transition validation

### Race Conditions

13. **Optimistic message send + realtime insert**: Both can exist briefly — mitigated by ID deduplication but window exists
14. **Badge count RPC + local count**: Can disagree during network latency
15. **SwiftData concurrent access**: BackgroundSyncActor creates separate ModelContext — changes propagate via save notification (slight delay)

---

## 11 — Refactor Safety Rules

### CRITICAL: Do Not Break These Systems

#### 1. Realtime Messaging Pipeline
**Files**: `MessagingSyncEngine.swift`, `RealtimeManager.swift`, `MessagingRepository.swift`, `MessageSendWorker.swift`

- The realtime → sync engine → repository → publisher → ViewModel chain is the backbone of messaging
- Breaking any link causes silent message loss or duplicate rendering
- `RealtimePayloadAdapter` normalizes quirky Supabase realtime payloads — changes here cascade everywhere
- Message deduplication logic prevents double-rendering — removing it causes visual bugs

#### 2. Optimistic Message Sending
**Files**: `MessageSendWorker.swift`, `MessagingRepository.swift`, `SDModels.swift`

- The `status` field state machine (sending → sent → delivered → failed) must be preserved
- `isPending` and `localAttachmentPath` track in-flight sends — clearing them prematurely loses messages
- Media upload → URL replacement → message send is a strict sequence

#### 3. Reaction State Invariant
**Files**: `Message.swift`, `MessageReaction.swift`, `MessageReactionService.swift`

- `Message.setIndividualReactions(_:)` is the ONLY valid mutation path
- Never modify `reactions` directly — it's derived from `individualReactions`
- iMessage reaction badges render at TOP of bubble (not bottom) — memory note exists for this

#### 4. Notification Routing
**Files**: `DeepLinkParser.swift`, `NavigationCoordinator.swift`, `AppDelegate.swift`, `PushNotificationService.swift`

- Deep link chain: push payload → `DeepLinkParser` → `NavigationIntent` → `NavigationCoordinator` → tab switch + navigation
- Deferred navigation (dismiss sheet → then navigate) prevents UI corruption
- Breaking this chain causes push taps to silently fail

#### 5. Auth State Machine
**Files**: `AuthService.swift`, `AppState.swift`, `AppLaunchManager.swift`, `ContentView.swift`

- Launch state progression: `.initializing` → `.checkingAuth` → `.ready(authState)`
- AuthState routes to: LoginView / PendingApprovalView / MainTabView
- `AppState` mirrors `AuthService` via Combine — both must stay in sync
- Sign-out notification triggers full teardown (sync engines, caches, tokens)

#### 6. Sync Engine Lifecycle
**Files**: `SyncEngineOrchestrator.swift`, all 3 sync engines

- Strict lifecycle: `setup(modelContext:)` → `startSync()` → `pauseSync()` → `resumeSync()` → `teardown()`
- Orchestrator coordinates all 3 engines — calling individual engines out of order causes state corruption
- Teardown on sign-out is essential — skipping leaves zombie subscriptions

#### 7. Badge Count System
**Files**: `BadgeCountManager.swift`, `BadgeCache.swift`, `BadgeCountManaging.swift`

- RPC-based with exponential backoff on failure
- Tab bar badges, app icon badge, and individual conversation unread counts all derive from this
- Breaking the refresh debounce causes API spam; breaking the fallback causes badge flicker

#### 8. SwiftData Migration
**Files**: `SDModels.swift`, `NaarsCarsApp.swift`

- Auto-recovery deletes corrupt SwiftData store (loses all local data)
- Only additive (optional property) changes are safe without migration plans
- Removing or renaming fields requires manual `VersionedSchema` + `SchemaMigrationPlan`

---

## 12 — Required Development Guardrails

### Architecture Rules

1. **Never bypass the ViewModel layer** — Views must not call services directly. All data flows through ViewModels.
2. **Maintain the repository pattern** — SwiftData reads go through repositories, not raw `FetchDescriptor` in ViewModels.
3. **Singleton lifecycle** — Never create a second instance of any `static let shared` service. Never make `init()` public.
4. **Protocol compliance** — All new services must have a corresponding protocol in `Core/Protocols/`. ViewModels must accept services via constructor injection with `.shared` defaults.
5. **Feature isolation** — Features must not import other features. Cross-feature communication goes through services or notifications.

### State Management Rules

6. **@MainActor for all UI state** — Every ViewModel, repository, and manager that publishes to UI must be `@MainActor`.
7. **Task cancellation** — Every ViewModel with async work must track `loadTask: Task<Void, Never>?` and cancel in `stop()`/`deinit`.
8. **Never mutate `reactions` directly** — Always use `Message.setIndividualReactions(_:)`. The aggregated `reactions` dictionary is derived.
9. **iMessage reaction badges render at the TOP of the bubble** — not the bottom.
10. **Published properties must not have side effects** — Use `didSet` sparingly and only for derived state (cell configs, unread counts).

### Networking Rules

11. **All Supabase calls must handle errors** — Wrap in do/catch, surface `AppError` to UI, record non-fatals to Crashlytics.
12. **Respect rate limits** — Use `RateLimiter.shared.checkAndRecord()` before any rate-limited operation. Check `Constants.RateLimits` for values.
13. **Batch profile fetches** — Never fetch profiles one-by-one. Always collect IDs and batch via `ProfileService.fetchProfiles(userIds:)`.
14. **Use existing decoders** — Date parsing must use `DateDecoderFactory` or the established ISO8601 pattern with fractional seconds. Do not create new date formatters.
15. **Request deduplication** — For cacheable reads, use `RequestDeduplicator` to prevent concurrent duplicate network calls.

### Realtime Rules

16. **Never modify realtime subscription logic without testing the full pipeline** — Realtime → sync engine → repository → publisher → ViewModel → View.
17. **Payload parsing must be defensive** — Use optional extraction with fallbacks. If parsing fails, trigger full sync instead of crashing.
18. **Respect channel limits** — Max 30 subscriptions. Protected prefixes (messages, typing) are not evicted first.
19. **Reactions use per-conversation subscriptions** — Subscribe on conversation open, unsubscribe on close. Do not subscribe globally.
20. **Read-by changes are metadata-only** — Filter out `read_by`-only updates in sync engines to avoid unnecessary UI re-renders.

### UI Rules

21. **Messaging list uses UIKit** — `MessagesCollectionView` is a UICollectionView wrapper. Do not replace with SwiftUI List.
22. **Use the design system** — Colors from `ColorTheme`, typography from `Typography`, buttons from `UI/Components/Buttons/`.
23. **Skeleton views for loading** — Use existing skeleton components (SkeletonRideCard, SkeletonConversationRow, etc.) — do not show spinner for list loading.
24. **Image compression** — Use `ImageCompressor` presets (avatar, messageImage, townHall) — do not upload raw images.
25. **Localization** — All user-facing strings must use localization keys. Check `Localizable.xcstrings`.

### Concurrency Rules

26. **SwiftData writes on BackgroundSyncActor** — Never write to SwiftData from the main thread during sync. Use `BackgroundSyncActor` for batch operations.
27. **Combine subscriptions** — Store in `Set<AnyCancellable>`. Never use `.sink()` without storing the cancellable.
28. **Actor isolation** — `MessageSendWorker` is an actor. Do not access its state from outside without `await`.
29. **Structured concurrency** — Prefer `async let` for parallel fetches. Check `Task.isCancelled` in long-running loops.
30. **No blocking the main thread** — Profile fetches, network calls, and SwiftData batch operations must be async or on background actors.

### Database Rules

31. **RLS is the security boundary** — Never assume client-side filtering is sufficient. All security-critical operations must have RLS policies.
32. **SECURITY DEFINER for cross-table operations** — RPC functions that need to bypass RLS (e.g., signup, admin) must use SECURITY DEFINER.
33. **SwiftData changes must be additive** — New optional properties only. Removing or renaming fields requires a `VersionedSchema` migration plan.
34. **Cascading deletes** — The `delete_user_account()` RPC must be updated when new tables referencing `profiles.id` are created.

### Testing Rules

35. **Service protocols enable testing** — Mock services by conforming to protocols. Never mock Supabase client directly.
36. **Test realtime payloads** — Use `RealtimeFixtures` for consistent test data. Test both structured and unstructured payload formats.
37. **Test notification routing** — Deep link parsing must be tested for every `NotificationType` case.

---

## Appendix: Key File Reference

### App Layer
- `NaarsCars/App/NaarsCarsApp.swift` — Entry point, SwiftData container, sync engine setup
- `NaarsCars/App/AppDelegate.swift` — Push, background refresh, notification actions
- `NaarsCars/App/ContentView.swift` — Auth state routing
- `NaarsCars/App/MainTabView.swift` — Tab bar with badge counts
- `NaarsCars/App/NavigationCoordinator.swift` — Deep link navigation

### Core Services
- `Core/Services/SupabaseService.swift` — Supabase client singleton
- `Core/Services/AuthService.swift` — Authentication + session management
- `Core/Services/RealtimeManager.swift` — Realtime subscription coordinator
- `Core/Services/MessageService.swift` — Message CRUD
- `Core/Services/MessageSendWorker.swift` — Durable message send queue
- `Core/Services/ConversationService.swift` — Conversation management
- `Core/Services/MessageReactionService.swift` — Reaction CRUD
- `Core/Services/BadgeCountManager.swift` — Badge count aggregation
- `Core/Services/PushNotificationService.swift` — APNs management
- `Core/Services/NotificationService.swift` — In-app notification CRUD

### Storage Layer
- `Core/Storage/SDModels.swift` — SwiftData model definitions
- `Core/Storage/MessagingSyncEngine.swift` — Realtime message sync
- `Core/Storage/DashboardSyncEngine.swift` — Realtime dashboard sync
- `Core/Storage/TownHallSyncEngine.swift` — Realtime town hall sync
- `Core/Storage/SyncEngineOrchestrator.swift` — Sync lifecycle coordinator
- `Core/Storage/BackgroundSyncActor.swift` — Off-MainActor SwiftData writes
- `Core/Storage/MessagingRepository.swift` — Message/conversation local storage

### Models
- `Core/Models/Message.swift` — Message + reaction data invariant
- `Core/Models/Conversation.swift` — Conversation model
- `Core/Models/AppNotification.swift` — 31 notification types
- `Core/Models/NotificationGrouping.swift` — Grouping + archival logic

### Edge Functions
- `supabase/functions/send-notification/` — General push delivery
- `supabase/functions/send-message-push/` — Message-specific push
- `supabase/functions/revoke-apple-token/` — Apple Sign-In token revocation
