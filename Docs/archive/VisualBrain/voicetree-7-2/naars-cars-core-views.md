---
color: cyan
position:
  x: 370
  y: -1321
isContextNode: false
agent_name: Amy
---

# Core Views & App Structure

The app uses a modern SwiftUI architecture with clear separation of concerns.

## App Entry & Root Views

### NaarsCarsApp.swift
**Main entry point** with sophisticated initialization:
- **SwiftData setup** with migration plan (`SchemaV1`, `NaarsCarsModelMigrationPlan`)
- **Firebase initialization** for crash reporting
- **Sync engine wiring** - Connects SwiftData to Supabase via repositories
- **Error recovery** - Handles SwiftData corruption with user-friendly reset option
- **Performance monitoring** - Tracks app init and sync setup times

### ContentView.swift
**Root navigation controller** managing auth states via `AppLaunchManager`:
- `.initializing` → Loading screen
- `.checkingAuth` → Verifying session
- `.ready(.unauthenticated)` → Login flow
- `.ready(.pendingApproval)` → Waiting for admin approval
- `.ready(.authenticated)` → Main app (MainTabView)
- `.failed(error)` → Error with retry

**Notable features:**
- **Biometric app lock** with 5-minute timeout
- **Background/foreground handling** for re-authentication
- **Performance tracking** for launch phases

### MainTabView.swift
**Tab-based navigation** with 5 main sections:
1. **Requests** - Rides/Favors dashboard
2. **Messaging** - Conversations list
3. **Town Hall** - Community forum
4. **Leaderboards** - User rankings
5. **Profile** - Settings & account

Each tab has badge count support and maintains its own navigation stack.

## Architecture Patterns

### MVVM+C
- **Views**: SwiftUI declarative UI
- **ViewModels**: `@StateObject` with `@Published` properties
- **Services**: Business logic layer (AuthService, MessageService, etc.)
- **NavigationCoordinator**: Centralized deep link handling

### Offline-First with SwiftData
- **SwiftData as UI source of truth** - All `@Query` bindings read from local SQLite
- **Sync engines** populate SwiftData from Supabase Realtime
- **Optimistic updates** - UI updates immediately, then syncs to server

### State Management
- **AppState** (global) - Current user, session, navigation triggers
- **ThemeManager** - Dark mode support
- **AppLaunchManager** - Critical path initialization (FR-051 requirement)

## Key Files

| File | Purpose |
|------|---------|
| `App/NaarsCarsApp.swift` | Main entry, dependency setup |
| `App/ContentView.swift` | Auth state routing, biometric lock |
| `App/MainTabView.swift` | Tab navigation container |
| `App/NavigationCoordinator.swift` | Deep link handling |
| `App/AppState.swift` | Global app state |
| `App/AppLaunchManager.swift` | Launch sequence orchestration |

links to [[/Users/bcolf/Documents/naars-cars-ios/VisualBrain/voicetree-7-2/1770515369146IEM.md]]
