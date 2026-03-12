# Timezone Migration Fix & Frame Drop Optimization

**Date:** 2026-03-04
**Status:** Approved

## Problem

### 1. SwiftData Migration Failure (Critical)
Adding `timezone: String` (non-optional) to `SDRide` and `SDFavor` causes CoreData error 134110 on existing stores. The migration fails because:
- Existing rows lack a value for the new mandatory column
- `SDModelVersions.swift` and `SDMigrationPlan.swift` define versioned schemas that don't include `timezone`
- The container in `NaarsCarsApp.swift` uses the unversioned `ModelContainer(for:)` — it never references the migration plan (dead code)
- `BackgroundSyncActor` doesn't map `timezone` during sync (4 missing lines)

### 2. Messaging Frame Drops (Performance)
`messaging.frameDrop.delta` logs show 66-100ms drops (4-6 frames) in conversation view. Root causes:
- `recomputeCellConfigurations()` iterates ALL messages O(n) on every change
- Snapshot applies on every `@Published messages` change without debounce
- Shared `MessageAudioPlayer` causes all audio bubbles to re-render on timer ticks

## Approach

**Pre-release (TestFlight only)** — no production user data at risk.

### Fix 1: Timezone Migration

**A. Delete dead schema files**
- Remove `SDModelVersions.swift` (SchemaV1/V2 are identical, never referenced by container)
- Remove `SDMigrationPlan.swift` (migration plan is never used)

**B. Auto-recover on migration failure (`NaarsCarsApp.swift`)**
- On `createModelContainer()` failure, silently delete store files and retry
- Only show alert if retry also fails
- TestFlight users get seamless upgrade; store rebuilds from network

**C. Add timezone mapping (`BackgroundSyncActor.swift`)**
- `syncRidesInternal`: add `timezone: ride.timezone` to `SDRide(...)` constructor
- `updateSDRide`: add `sd.timezone = ride.timezone`
- `syncFavorsInternal`: add `timezone: favor.timezone` to `SDFavor(...)` constructor
- `updateSDFavor`: add `sd.timezone = favor.timezone`

**D. `SDModels.swift` — no changes needed**
Already correct: `timezone` is non-optional `String` with init defaults.

### Fix 2: Frame Drop Optimization

**A. Incremental cell config recomputation (`ConversationDetailViewModel.swift`)**
- Only recompute configs for new/changed messages and their immediate neighbors
- O(1) for the common case (single new message) instead of O(n)

**B. Debounce snapshot applies (`MessagesCollectionView.swift`)**
- Coalesce rapid-fire updates with ~50ms debounce
- Multiple messages arriving in quick succession produce a single snapshot apply

**C. Isolate audio player re-renders (`MessageBubble.swift`)**
- Only observe playback state for the currently-playing message ID
- Non-playing audio bubbles don't re-render on timer ticks

## Files Changed

| File | Change |
|------|--------|
| `SDModelVersions.swift` | DELETE |
| `SDMigrationPlan.swift` | DELETE |
| `NaarsCarsApp.swift` | Auto-recover container init |
| `BackgroundSyncActor.swift` | 4 timezone mapping lines |
| `ConversationDetailViewModel.swift` | Incremental cell config |
| `MessagesCollectionView.swift` | Debounce snapshot applies |
| `MessageBubble.swift` | Isolate audio re-renders |

## Deferred

- Map snapshot generation profiling
- URL detection caching optimization
- Spring animation simplification
- These need Instruments profiling to validate impact
