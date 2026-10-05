---
color: blue
position:
  x: -302
  y: -763
isContextNode: false
agent_name: Amy
---

# Project Mapping Complete

Comprehensive mapping of NaarsCars iOS project structure completed.

## Mapping Summary

Created 19 child nodes organizing the entire codebase into logical areas:

### Core Architecture (5 nodes)
1. **Core Views & App Structure** - App entry, navigation, state management
2. **Core Data Models** - 20+ models with clean Codable conformance
3. **Services Layer** - 40+ service singletons
4. **Storage & Persistence Layer** - SwiftData + Sync Engines
5. **Utilities & Helpers** - 30+ utility classes

### Feature Modules (8 nodes)
1. **Rides & Favors Module** - ⚠️ **BROKEN** (RLS bug)
2. **Messaging Module** - iMessage-like chat
3. **Authentication** - Login/signup flows
4. **Profile** - User settings
5. **Admin** - User management
6. **Notifications** - Push + in-app
7. **Town Hall** - Community forum
8. **Leaderboards** - Gamification
9. **Reviews** - Star ratings

### Infrastructure (4 nodes)
1. **UI Components Library** - 50+ reusable components
2. **Database Schema & Migrations** - 99 SQL migrations
3. **Backend Edge Functions** - Push notification handlers
4. **Testing & QA** - Unit/UI tests

### Documentation (2 nodes)
1. **Documentation & Specifications** - PRDs, audits, plans
2. **Architecture Overview Diagrams** - Mermaid visualizations

## Project Statistics

- **Total Swift Files:** 342
- **Feature Modules:** 15
- **Service Classes:** 40+
- **Database Migrations:** 99
- **Edge Functions:** 2
- **UI Components:** 50+
- **Test Files:** ~50

## Key Findings

### ✅ Strengths Identified
- Modern Swift architecture (async/await, Sendable, SwiftUI)
- Offline-first design with SwiftData
- Comprehensive feature set rivaling major apps
- Clean separation of concerns (MVVM+C)
- Active maintenance (Feb 2026 comprehensive fix pass)

### 🔴 Critical Issues Found
1. **Claim/Unclaim Broken** - RLS policy bug blocks core feature
2. **Main Thread Blocking** - Message sorting causes lag
3. **Badge Count Performance** - Unoptimized COUNT queries
4. **Cost Estimation Race** - Background task conflicts

### 🟡 Technical Debt
- Client-side profile polling (should be transactional)
- Fragile webhook parsing in Edge Functions
- Optimistic ID reconciliation complexity
- participantIds not synced to SwiftData

## Visualization

Created comprehensive Mermaid diagrams showing:
- **System Architecture** - Component relationships
- **Data Flow** - Optimistic updates + sync
- **Feature Module Structure** - Standard patterns
- **Authentication Flow** - State machine
- **Messaging Architecture** - Real-time sync
- **Request Lifecycle** - Ride/favor states
- **RLS Bug Visualization** - Why claims fail

## Next Steps

Ready to dive into claims bug debugging with full project context:
1. Examine current RLS policies in detail
2. Trace claim flow from UI → Service → Database
3. Design correct RLS policies
4. Plan implementation and testing strategy

## Complexity Assessment

**Overall Complexity: 7/10**

**Most Complex Areas:**
- Messaging (8/10) - Real-time sync, optimistic updates, rich features
- Rides/Favors (7/10) - Multi-step claiming, RLS interactions
- Storage Layer (7/10) - SwiftData + Supabase sync orchestration

**Simplest Areas:**
- Models (3/10) - Clean, straightforward Codable structs
- UI Components (4/10) - Reusable, well-structured views
- Leaderboards (4/10) - Straightforward ranking display

completes [[/Users/bcolf/Documents/naars-cars-ios/VisualBrain/voicetree-7-2/1770515369146IEM.md]]
