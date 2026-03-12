---
color: green
position:
  x: -812
  y: -1577
isContextNode: false
agent_name: Amy
---

# Services Layer Architecture

Clean separation of business logic from UI via service singletons.

## Service Categories

### 🔐 Authentication & Security
- **AuthService** - Sign up/in/out, session management, Apple Sign In
- **BiometricService** - Face ID / Touch ID for app lock
- **InviteService** - Invite code generation and validation
- **AdminService** - Admin approval workflows

### 💬 Messaging & Communication
- **ConversationService** - Create/read/update conversations
- **MessageService** - Send/edit/delete messages
- **MessageMediaService** - Upload images/audio to Supabase Storage
- **MessageReactionService** - Add/remove emoji reactions
- **ConversationParticipantService** - Manage participants, typing presence

### 🚗 Request Management
- **RideService** - CRUD for rides, cost estimation
- **FavorService** - CRUD for favors
- **ClaimService** - Claim/unclaim requests with rate limiting
- **ReviewService** - Post-completion star ratings

### 🔔 Notifications
- **NotificationService** - In-app notification CRUD
- **PushNotificationService** - APNs registration, badge management
- **BadgeCountManager** - Real-time badge count tracking
- **InAppToastManager** - Transient notification toasts

### 🏘️ Community
- **TownHallService** - Community posts CRUD
- **TownHallCommentService** - Threaded comments
- **TownHallVoteService** - Upvote/downvote logic
- **LeaderboardService** - User rankings and reputation

### 🗄️ Infrastructure
- **SupabaseService** - Singleton wrapper for Supabase client
- **ProfileService** - User profile management
- **MapService** - MapKit integration for cost estimation
- **EmailService** - Email sending via Supabase Edge Functions

### 📊 System Services
- **AppLogger** - Structured logging with categories
- **PerformanceMonitor** - Operation timing and metrics
- **CrashReportingService** - Firebase Crashlytics integration
- **RealtimeManager** - Supabase Realtime WebSocket lifecycle
- **JSONDecoderFactory** - Centralized decoder configuration

## Design Patterns

### Singleton Pattern
All services use shared singletons:
```swift
class RideService {
    static let shared = RideService()
    private init() {}
}
```

### Async/Await
Modern Swift concurrency throughout:
```swift
func createRide(...) async throws -> Ride {
    // Supabase interaction
}
```

### Error Handling
Services throw structured errors caught by ViewModels:
```swift
enum RideError: LocalizedError {
    case invalidPickup
    case notFound
    // ...
}
```

## Technical Debt

### 🟡 N+1 Profile Fetching (FIXED)
**Was:** `RideService.enrichRidesWithProfiles` made separate API calls per user
**Now:** Uses batch fetch `fetchProfiles(userIds: [...])`

### 🟡 Badge Count Performance
`get_badge_counts` RPC performs multiple `COUNT(*)` on large tables on every call.

**From STRUCTURAL_HANDOFF_AUDIT.md:**
> This is unoptimized and will degrade as data grows.

**Recommendation:** Use materialized views or counter tables with database triggers.

### 🔴 Cost Estimation Race Condition
`RideService` calculates estimated cost in background Task after ride creation. If user edits immediately, background write may overwrite changes.

**Recommendation:** Use optimistic locking or cancel background Task on user edit.

links to [[/Users/bcolf/Documents/naars-cars-ios/VisualBrain/voicetree-7-2/1770515369146IEM.md]]
