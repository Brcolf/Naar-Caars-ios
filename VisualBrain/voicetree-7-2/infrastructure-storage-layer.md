---
color: gray
position:
  x: 260
  y: -857
isContextNode: false
agent_name: Amy
---

# Infrastructure: Storage & Persistence Layer

SwiftData-based offline-first data layer with Supabase sync.

## Core Architecture

### SwiftData Models (`SDModels.swift`)
Local cache models for offline-first UI:
- **SDConversation** - Cached conversations
- **SDMessage** - Cached messages with send status
- **SDRide** - Cached rides
- **SDFavor** - Cached favors
- **SDNotification** - Cached notifications
- **SDTownHallPost** - Cached posts

### Migration System
- **SDModelVersions.swift** - Schema versioning (SchemaV1, SchemaV2, etc.)
- **SDMigrationPlan.swift** - Migration plan for schema evolution
- **NaarsCarsModelMigrationPlan** - Custom migration logic

## Repository Pattern

### MessagingRepository.swift
Abstracts SwiftData operations for messaging:
- `getAllConversations()` - Query cached conversations
- `getMessages(conversationId:)` - Query cached messages
- `upsertMessage()` - Insert or update message
- `deleteMessage()` - Remove message
- Publishers for reactive updates

### NotificationRepository.swift
Abstracts SwiftData operations for notifications:
- `getUnreadNotifications()` - Query unread
- `markAsRead()` - Update read status
- `upsertNotification()` - Sync from server

### TownHallRepository.swift
Abstracts SwiftData operations for Town Hall:
- `getAllPosts()` - Query cached posts
- `upsertPost()` - Sync from server
- `deletePost()` - Remove post

## Sync Engine Pattern

### MessagingSyncEngine.swift
Syncs conversations and messages from Supabase Realtime:
- Subscribes to `postgres_changes` on `conversations` and `messages` tables
- Maps Supabase payloads to SwiftData models via `MessagingMapper`
- Upserts into local cache
- Handles INSERT, UPDATE, DELETE events

### DashboardSyncEngine.swift
Syncs rides and favors:
- Subscribes to `rides` and `favors` tables
- Updates SwiftData cache
- Triggers UI refresh via `@Query`

### TownHallSyncEngine.swift
Syncs Town Hall posts and comments:
- Subscribes to `town_hall_posts` and `town_hall_comments`
- Real-time updates for votes and new posts

## Mapper Pattern

### MessagingMapper.swift
Transforms Supabase payloads to SwiftData models:
- `mapConversation(from: JSON)` → `SDConversation`
- `mapMessage(from: JSON)` → `SDMessage`
- Handles nested JSON (participants, sender profile)
- Error handling for malformed data

## Key Features

### Offline-First
- SwiftData is source of truth for UI
- All `@Query` bindings read from local SQLite
- No network required for browsing cached data

### Optimistic Updates
- UI updates immediately on user action
- Sync engines reconcile with server
- Retry logic for failed operations

### Background Sync
- `MessageSendWorker.swift` - Durable message sending
- Retries failed sends on app launch
- Handles temporary network failures

## File Structure

```
Core/Storage/
├── SDModels.swift              # SwiftData model definitions
├── SDModelVersions.swift       # Schema versioning
├── SDMigrationPlan.swift       # Migration logic
├── MessagingRepository.swift   # Messaging data access
├── MessagingMapper.swift       # JSON → SwiftData mapping
├── MessagingSyncEngine.swift   # Realtime sync for messaging
├── DashboardSyncEngine.swift   # Realtime sync for rides/favors
├── NotificationRepository.swift # Notification data access
├── TownHallRepository.swift    # Town Hall data access
└── TownHallSyncEngine.swift    # Realtime sync for Town Hall
```

## Technical Debt

### 🟡 participantIds Not Synced
**Issue:** `SDRide.participantIds` and `SDFavor.participantIds` never populated from API.

**Impact:** "My Requests" filter may miss requests where user is invited participant (not poster/claimer).

**Fix:** Sync participant data or derive from API response.

links to [[/Users/bcolf/Documents/naars-cars-ios/VisualBrain/voicetree-7-2/1770515369146IEM.md]]
