# Production Hardening Design

**Date**: 2026-02-26
**Status**: Approved
**Approach**: Risk-Ordered Phases (A)
**Branch**: `production-hardening` (single branch, logical commits)
**Layers**: Swift + SQL migrations + Edge Functions
**DB target**: Production (review carefully before applying)

---

## Regression Protection Strategy

Every phase MUST:
1. Run the full test suite (`xcodebuild test`) after Swift changes and confirm zero regressions
2. SQL migrations must be additive (CREATE OR REPLACE, ADD IF NOT EXISTS) — never drop columns or tables without replacement
3. Each phase ends with a verification checkpoint before proceeding
4. Existing refactors (granular publishers, debounced sync, optimistic messaging) must not be altered unless directly fixing a bug

Key areas to protect:
- Messaging: optimistic send → server confirm → replace flow
- Sync engines: debounced reconciliation + cooldown guards
- Navigation: deep link routing from push notifications
- Badge counts: RPC-based counting with polling fallback
- Realtime: channel subscription lifecycle (background/foreground)

---

## Phase 1: Security Hardening

### 1a. Restrict `notifications` INSERT policy
- **File**: New `supabase/migrations/20260226_0001_restrict_notification_insert.sql`
- **Change**: Drop `notifications_insert` (WITH CHECK true), replace with service-role-only INSERT
- **Regression risk**: Any client-side code that directly inserts into `notifications` will break. Audit confirms all notification creation goes through RPCs/Edge Functions/triggers that use service role. Verify by grepping for `.from("notifications").insert`.
- **Verification**: Grep codebase for direct notification inserts; confirm all paths use RPCs.

### 1b. Validate caller in `get_badge_counts`
- **File**: New `supabase/migrations/20260226_0002_badge_counts_validate_caller.sql`
- **Change**: Add `auth.uid()` check at top of function body
- **Regression risk**: Low. The iOS app always passes the current user's ID. The check just prevents misuse.
- **Verification**: Badge counts still load correctly after migration.

### 1c. Pre-commit hook for secrets
- **File**: New `scripts/pre-commit-secrets-check.sh`
- **Change**: Shell script that rejects commits containing `.p8`, `GoogleService-Info.plist`, or files matching `Secrets.swift`
- **Regression risk**: None — purely additive developer tooling.
- **Verification**: Try staging a `.p8` file and confirm the hook blocks it.

### 1d. Update audit document
- **File**: `Docs/PRODUCTION-READINESS-AUDIT.md`
- **Change**: Downgrade .p8 finding to resolved, update scorecard.

---

## Phase 2: Membership & Sync Correctness

### 2a. Fix leave/remove announcement RLS conflict
- **File**: `NaarsCars/Core/Services/ConversationParticipantService.swift`
- **Change**: Move `sendSystemMessage` BEFORE `leave_conversation`/`remove_conversation_participant` RPC calls. Replace `try?` with `do/catch` + Crashlytics recording.
- **Regression risk**: Medium. Must ensure the announcement message is visible to all participants. If the RPC fails after the announcement is sent, we have an announcement without an actual leave — mitigate by checking RPC result and noting in the announcement text if needed.
- **Verification**: Unit test: leave group → verify announcement message exists AND user is no longer active. Integration test: verify other participants see the announcement.

### 2b. Fix ConversationService fallback `left_at` filter
- **File**: `NaarsCars/Core/Services/ConversationService.swift`
- **Change**: Add `.is("left_at", value: nil)` to `fetchParticipantsFallback()`
- **Regression risk**: Very low. Only affects the fallback path (when RPC fails). Existing primary path already filters correctly.
- **Verification**: Existing `ConversationParticipantsViewModelTests` should still pass. Add test for fallback path excluding left users.

### 2c. Immediate local participant update after leave/remove
- **Files**: `ConversationParticipantService.swift`, `MessagingRepository.swift`
- **Change**: Add `removeParticipantLocally(conversationId:userId:)` to MessagingRepository. Call it after successful leave/remove RPC.
- **Regression risk**: Low. Only adds a local SwiftData mutation after an already-successful server operation. Must ensure the conversation publisher refreshes.
- **Verification**: Unit test: after removeParticipantLocally, SDConversation.participantIds no longer contains the user. Conversations publisher emits updated list.

### 2d. Dashboard orphan cleanup
- **File**: `NaarsCars/Core/Storage/DashboardSyncEngine.swift`
- **Change**: After upsert loop in `syncRides()`/`syncFavors()`, collect server IDs, fetch local IDs, delete orphans. Only run cleanup when server returned non-empty results.
- **Regression risk**: Medium. If a partial server fetch (e.g., filtered by status) is used, we could incorrectly delete valid local records. Must verify `fetchRides()`/`fetchFavors()` returns ALL records (not a filtered subset) before enabling orphan cleanup.
- **Verification**: Unit test: sync with 3 rides, then sync with 2 rides → verify the missing one is deleted locally. Verify empty server response does NOT trigger cleanup (guards against network errors deleting everything).

---

## Phase 3: Observability & Reliability

### 3a. Replace silent `try?` in network paths
- **Files**: ~15 service files
- **Change**: `try?` → `do { try ... } catch { CrashReportingService.shared.recordNonFatal(...) }` where the catch preserves the original behavior (return nil, continue, etc.)
- **Regression risk**: Very low. Behavior is identical — we just add error recording. The catch blocks must NOT change control flow (no throwing, no early returns that weren't there before).
- **Verification**: Full test suite passes. Spot-check that Crashlytics receives non-fatal events in debug.

### 3b. Sync health metrics
- **Files**: `SyncEngineProtocol.swift`, each sync engine, new `SyncHealthReport.swift`
- **Change**: Add `lastSuccessfulSync: Date?`, `lastSyncError: String?`, `consecutiveFailures: Int` to protocol or a shared base. Log at sync boundaries.
- **Regression risk**: Very low. Purely additive — no existing behavior changed.
- **Verification**: After app launch, verify health metrics are populated. Check logs for sync completion messages.

### 3c. SwiftData indexes via SchemaV2
- **Files**: `SDModelVersions.swift`, `SDMigrationPlan.swift`, `SDModels.swift`
- **Change**: Add SchemaV2 with `#Index` on `SDMessage.conversationId`, `SDNotification.rideId`, `SDNotification.favorId`. Add lightweight migration stage V1→V2.
- **Regression risk**: HIGH if migration fails. SwiftData lightweight migrations for index-only changes should be safe, but must test on a device with existing V1 data. The nuclear recovery path (delete+recreate store) exists as a safety net.
- **Verification**: Test on simulator with V1 data → upgrade → verify data preserved and queries work. Test fresh install. Test the recovery path.

---

## Phase 4: Polish & Infrastructure

### 4a. Server-side rate limiting
- **File**: `supabase/functions/send-message-push/index.ts` or new migration for trigger
- **Change**: Add per-user message rate check (10/minute) before sending push. Could be a simple in-memory counter in the Edge Function or a Postgres trigger.
- **Regression risk**: Low for Edge Function approach (only affects push sending, not message storage). Must ensure legitimate rapid messages (e.g., during active conversation) aren't suppressed.
- **Verification**: Send 11 messages in 1 minute → verify 10 pushes sent, 11th rate-limited. Messages still stored in DB regardless.

### 4b. Final scorecard update
- **File**: `Docs/PRODUCTION-READINESS-AUDIT.md`
- **Change**: Re-score all categories with evidence of fixes.

---

## Test Suite Checkpoints

After each phase:
```bash
xcodebuild test -project NaarsCars/NaarsCars.xcodeproj -scheme NaarsCars -destination 'platform=iOS Simulator,name=iPhone 16'
```

All 64 existing test files must pass with zero regressions.
