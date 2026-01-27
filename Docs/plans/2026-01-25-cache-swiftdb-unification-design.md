# Cache and SwiftData Unification Design

Status: Approved (2026-01-25)

## Goal
- Realtime correctness first.
- UI reads SwiftData immediately and refreshes in background.
- Cache is only a network throttle and never supplies UI data.

## Context
The app added SwiftData (SwiftDB) after a multi-layer in-memory cache was already in place. Realtime updates now write into SwiftData, while service calls can still return cached arrays. This can suppress or delay updates (messaging, notifications, requests, town hall) when cache is warm but SwiftData has newer data.

## Decisions
- SwiftData is the single source of truth for UI state.
- Realtime updates write through to SwiftData and update UI reactively.
- Services write through to SwiftData; cache only avoids redundant network calls.
- Manual refresh always bypasses cache.

## Architecture Overview
- UI renders from SwiftData (@Query or repository-backed queries).
- ViewModels trigger background refresh on entry.
- Services fetch from network, map to models, and write to SwiftData.
- Realtime subscriptions update SwiftData via sync engines.

## Cache Rules
- CacheManager only throttles network requests.
- No service returns CacheManager data to UI callers.
- Cache invalidation can remain for network hygiene, but is not UI-visible.
- Force refresh bypasses cache and writes through to SwiftData.

## Feature Adjustments
Messaging:
- Conversation lists and messages render from SwiftData.
- Background refresh writes to SwiftData via MessageService.
- Realtime inserts/updates are authoritative via MessagingSyncEngine.

Notifications:
- Use a single sync path (ViewModel or DashboardSyncEngine, not both).
- Realtime writes to SwiftData; badge counts derive from SwiftData.
- NotificationService cache only throttles network.

Requests (Rides/Favors):
- Dashboard and detail views render from SwiftData first.
- Background refresh writes to SwiftData via RideService/FavorService.
- Remove duplicate realtime subscriptions that trigger redundant refreshes.

Town Hall:
- Persist posts in SwiftData if not already present.
- Feed renders from SwiftData and refreshes in background.
- Realtime inserts update SwiftData; no cache reads on realtime callbacks.

## Migration and Cleanup Steps
1. Identify UI entry points that consume service arrays and switch to SwiftData reads.
2. Add write-through updates to SwiftData in service fetches.
3. Remove CacheManager return paths from UI-facing methods.
4. Consolidate realtime subscriptions per feature.
5. Ensure badge calculations read from SwiftData.
6. Add logging for "realtime update" vs "network refresh".
7. Remove unused cache helpers and redundant invalidation logic.

## Error Handling and Consistency
- Network failures do not clear SwiftData; show transient error states only.
- Resolve conflicts using updatedAt or server timestamps.
- Keep UI responsive with last-known data until refresh completes.

## Testing
- Unit: service reads are SwiftData-first; cache never returned to UI.
- Integration: realtime inserts update SwiftData and UI with cache warm.
- Regression: messaging receive, notifications appear, requests update, town hall refresh.

## Out of Scope
- Backend schema changes (unless required for conflict resolution).
- Push notification system changes unless needed for delivery guarantees.
