# CLAUDE.md

This file provides guidance to Claude Code (claude.ai/code) when working with code in this repository.

# Naar's Cars iOS

## ⚠️ Read This First — Before Any Code Change

You are working in a production iOS app actively preparing for App Store submission.
Several subsystems are fragile. This document tells you where, why, and how to proceed safely.

**Your default posture is: minimal, targeted, conservative.**

When in doubt between two approaches:
- Prefer the smaller diff
- Prefer preserving proven behavior
- Prefer explaining a risk over silently working around it
- Prefer asking for clarification over broadening scope

This isn't excessive caution — it's the correct engineering posture for a system with live users, realtime infrastructure, and an active App Store review in progress.

---

## Current State of the Codebase (Active Context)

> Update this section as the project state changes.

**App Store submission is in progress.** All changes must be App Store-safe by default. If a change has any submission risk, say so explicitly before proceeding.

**The messaging view layer is mid-UIKit refactor.** The original SwiftUI messaging components are not the reference implementation. The UIKit `MessagesCollectionView`-based implementation is the current canonical path. Do not treat SwiftUI messaging components as authoritative when they conflict with UIKit ones.

**MessageInputBar.swift** has been refactored into a thin rendering shell that reads state from `InputBarController` and delegates all mutations to it. The refactor is settled — treat `InputBarController` as the authoritative input state owner.

**Swift Observation migration is partially complete.** Several ViewModels have been migrated from `ObservableObject` to `@Observable`, but this has surfaced init/deinit storms and navigation hangs (see recent commits). When touching ViewModels, check whether they use `ObservableObject` or `@Observable` and follow the existing pattern for that file. Do not opportunistically migrate additional ViewModels without explicit approval.

**Critical active risks:**
- Supabase Realtime callbacks arrive on background threads and must be marshalled to the main actor before reaching UIKit views
- `@Observable` ViewModels passed through `.environment()` can cause init/deinit storms — recent fixes removed these patterns from sheets and tab views
- Any regression of previously-fixed App Store issues (account deletion, moderation, SIWA) is a blocker

---

## What This App Is

**Naar's Cars** is an invite-only community platform for neighbors to help each other with rides and favors. It's an iOS 17+ Swift app with:

| Layer | Technology |
|---|---|
| UI | SwiftUI (most surfaces) + UIKit (messaging) |
| Architecture | MVVM, singleton service layer, protocol abstractions |
| Backend | Supabase (auth, database, storage, RPC, realtime) |
| Local storage | SwiftData (cache + durable pending-send queue) |
| Crash / push | Firebase |

**SPM dependencies (Xcode-managed):** supabase-swift v2.5.1+, firebase-ios-sdk v12.8.0+, PhoneNumberKit v4.0.0+.

**Core product areas:** ride and favor requests, group messaging and reactions, town hall/community content, notifications and deep linking, invite-based auth and approval flows, moderation/blocking/reporting.

---

## Build and Test Commands

The Xcode project is at `NaarsCars/NaarsCars.xcodeproj`. Scheme: `NaarsCars`. Simulator target: iPhone, iOS 17+.

```bash
# Build (debug, simulator)
xcodebuild -project NaarsCars/NaarsCars.xcodeproj -scheme NaarsCars -sdk iphonesimulator -configuration Debug build

# Run all unit tests
xcodebuild -project NaarsCars/NaarsCars.xcodeproj -scheme NaarsCars -sdk iphonesimulator -destination 'platform=iOS Simulator,name=iPhone 16' test

# Run a single test class
xcodebuild test -project NaarsCars/NaarsCars.xcodeproj -scheme NaarsCars -sdk iphonesimulator -destination 'platform=iOS Simulator,name=iPhone 16' -only-testing:NaarsCarsTests/ProfileTests

# Run a single test method
xcodebuild test -project NaarsCars/NaarsCars.xcodeproj -scheme NaarsCars -sdk iphonesimulator -destination 'platform=iOS Simulator,name=iPhone 16' -only-testing:NaarsCarsTests/ProfileTests/testSomething

# Clean build artifacts
scripts/CLEAR-XCODE-CACHE.sh
```

Test targets: `NaarsCarsTests` (unit, ~66 files), `NaarsCarsUITests` (UI automation). Tests are parallelizable.

**Do not launch multiple simulators.** If one is running when launching a new simulator, ensure others are shut down first.

**Do not add tests unless explicitly asked.** When tests are requested, follow existing patterns in `NaarsCarsTests/`.

**No SwiftLint or SwiftFormat** — no linter config exists. No `Package.swift` or `Podfile` — dependencies are managed via Xcode (SPM integrated in the project).

### Secrets Setup (Required for Build)

1. Copy `NaarsCars/Core/Utilities/Secrets.swift.template` to `NaarsCars/Core/Utilities/Secrets.swift`
2. Run `NaarsCars/Scripts/obfuscate.swift` to generate obfuscated byte arrays for the Supabase URL and anon key
3. Paste the generated arrays into `Secrets.swift`

`Secrets.swift` is gitignored and must be created locally. Never log or expose `Secrets.supabaseURL` or `Secrets.supabaseAnonKey`.

### Pre-Commit Hook

The `.git/hooks/pre-commit` hook blocks commits containing:
- Secrets files (`Secrets.swift`, `GoogleService-Info.plist`, `.env`)
- Apple signing files (`*.p8`, `*.p12`, `*.key`)
- It also validates that localization keys are not accidentally removed

### MCP Servers

Supabase and GitHub MCP tools are configured in `.mcp.json`. Use the Supabase MCP for database queries, migrations, and edge function management. Use the GitHub MCP for PR and issue operations.

### Validation Scripts

`scripts/` contains validation helpers beyond the pre-commit hook:
- `VERIFY-ALL-FILES.sh` — full-project file integrity check
- `verify-apple-signin-config.sh` — validates SIWA entitlements and Info.plist
- `validate-notification-types.sh` — checks notification type registry consistency across layers
- `verify-xcode-file-sync.sh` — PostToolUse hook that warns if `.swift` files are outside synced roots

### Cursor Rules

`.cursor/rules/` contains 9 rule files that reinforce the patterns in this document with file-glob scoping. Key rules: impact seam analysis (`01`), notification type registry consistency (`02`), centralized realtime payload parsing (`03`), badge count server contract (`04`), navigation intent pattern (`05`), SwiftData mapper mirroring (`06`), service DI via protocols (`07`), and fixture test requirements for seam changes (`08`).

### Agent Instructions

`AGENTS.md` contains condensed project conventions for Codex and other AI agents. It mirrors the naming, architecture, and Xcode filesystem-sync rules from this file in a shorter format.

---

## File and Naming Conventions

- **ViewModels**: `*ViewModel.swift`, `final class … : ObservableObject`
- **Views**: `*View.swift`, `*Sheet.swift`, `*Card.swift`, `*Row.swift`
- **Services**: `*Service.swift` or `*Manager.swift` in `Core/Services/`
- **Models**: `Core/Models/`, struct/enum name matches filename
- **Protocols**: `Core/Protocols/` — every service has a protocol (`AuthServiceProtocol`, `RideServiceProtocol`, etc.)
- **Feature layout**: `Features/<Name>/Views/` and `Features/<Name>/ViewModels/`
- **Shared UI**: Reusable components in `UI/Components/` (subdirs: Buttons, Cards, Common, Feedback, Inputs, Map, Messaging). Check existing components (e.g., `PrimaryButton`, `EmptyStateView`, `SkeletonView`, `LocationAutocompleteField`) before creating new ones.
- **Swift file header**: `//` / `//  FileName.swift` / `//  NaarsCars` / `//`
- **Constants**: Use the `Constants` enum in `Core/Utilities/Constants.swift` for animation durations, spacing, timeouts, cache TTLs, rate limits, page sizes, and URLs. Do not introduce new magic numbers.

**Xcode uses filesystem-synced groups** (`PBXFileSystemSynchronizedRootGroup`). New `.swift` files placed under `NaarsCars/NaarsCars/`, `NaarsCars/NaarsCarsTests/`, or `NaarsCars/NaarsCarsUITests/` are auto-discovered by Xcode — no `project.pbxproj` edits needed. A PostToolUse hook (`scripts/verify-xcode-file-sync.sh`) warns if a `.swift` file is written outside these synced roots.

**Secrets**: `Secrets.swift` is gitignored. Use `Secrets.swift.template` and `NaarsCars/Scripts/obfuscate.swift` for credential obfuscation.

**Localization**: All user-facing strings use `"key".localized` with keys in `Resources/Localizable.xcstrings` (Xcode string catalog format). A pre-commit hook validates localization changes.

**Database migrations**: SQL files in `database/` with numeric prefix (e.g., `092_badge_counts_rpc.sql`). Latest is `132`. Do not modify existing migration files.

**Supabase edge functions**: `supabase/functions/` — `revoke-apple-token`, `send-message-push`, `send-notification`.

---

## Priority Order for Tradeoffs

When you face a tradeoff, resolve it in this order:

1. **App Store compliance** — nothing ships if review fails
2. **Correctness** — realtime, messaging, and auth must be right, not just fast
3. **Stability** — prefer the proven path over a clever new one
4. **Minimal change** — the smallest safe diff is almost always the right diff
5. **Performance** — important, but not at the cost of correctness
6. **Cleanliness** — last. Do not mix aesthetic cleanup with behavioral changes.

---

## Fragile Systems — Mandatory Conservative Handling

These systems require extra care. Before changing any of them: read the relevant files end-to-end, state the invariant you are preserving, and describe what could go wrong.

### 1. Realtime Messaging Pipeline

**Files:**
- `Core/Storage/MessagingSyncEngine.swift`
- `Core/Services/RealtimeManager.swift`
- `Core/Storage/MessagingRepository.swift`
- `Core/Services/MessageSendWorker.swift`
- `Core/Services/MessageService.swift`
- `Core/Services/MessageReactionService.swift`

**Required data flow — do not break or bypass any step:**
```
realtime payload
  → payload adapter
  → sync engine
  → repository
  → publisher
  → view model
  → UI
```

**Why this matters:** Bypassing any layer in this chain causes message loss, duplication, or silent corruption that is very hard to reproduce in testing but will affect users reliably.

**Do not:**
- Bypass the repository layer for any reason
- Remove deduplication logic
- Assume payloads are well-formed — they aren't always
- Collapse structured and unstructured realtime handling without preserving fallbacks
- Change message ordering behavior without explicit approval

### 2. Optimistic Message Sending

**The only valid send path is:**
```
MessageSendManager → MessageSendWorker → MessageService → Supabase
```

Never send messages from `MessagingRepository`, Views, or ViewModels directly. The repository must never contain fire-and-forget send logic.

**Required invariants:**
- Pending local messages appear in the UI immediately
- Failed sends remain recoverable — the user can retry
- Successful sends correctly reconcile local and server records
- Media uploads complete before the final send payload is committed

**Why this matters:** Breaking optimistic send makes the app feel broken to users even when the network is fine. Breaking recovery means users lose messages silently.

**Do not:**
- Remove or collapse `status` state transitions
- Clear `isPending` or `localAttachmentPath` before server acknowledgment
- Replace the durable queue with fire-and-forget async tasks
- Use untracked `Task {}` blocks to send messages

### 3. Reaction State

**Required invariants:**
- `individualReactions` is the single source of truth
- `reactions` (aggregated) is always derived, never directly mutated
- `Message.setIndividualReactions(_:)` is the **only** valid mutation path for reaction state
- Reaction badges render at the **top** of the message bubble

**Why this matters:** Dual-write bugs in reaction state produce phantom reactions and incorrect counts that are invisible in unit tests but immediately visible to users.

**Do not:**
- Mutate `reactions` directly
- Add alternative reaction mutation paths
- Move badge rendering position unless explicitly asked

### 4. Notification Routing

**Required flow:**
```
push payload
  → AppDelegate / push service
  → DeepLinkParser
  → NavigationIntent
  → NavigationCoordinator
  → correct tab / destination
```

All navigation from push handlers must go through **`pendingIntent` / `deferNotificationIntent()`**. Do not call navigation methods directly from `AppDelegate`, `PushNotificationService`, or completion handlers.

**Do not:**
- Bypass deferred navigation handling
- Add ad hoc direct navigation from push handlers (e.g., `coordinator.showReviewPromptFor()` or `coordinator.navigate(to:)` directly)
- Add new `@Published` navigation flags (e.g., `navigateToX`) — prefer the `NavigationIntent` enum pattern
- Change notification type mapping without verifying every route

### 5. Auth and Launch State

**Required state machine:**
```
initializing → checkingAuth → ready(authState)
```

**Do not:**
- Change launch routing logic without tracing the full state machine
- Allow `AppState` and `AuthService` to drift out of sync
- Skip sign-out teardown — it must clean up: subscriptions, caches, sync engines, tokens

### 6. Sync Engine Lifecycle

**Required lifecycle:**
```
setup → startSync → pauseSync → resumeSync → teardown
```

**Do not:**
- Call engine methods out of this order
- Start an engine without setup
- Tear down partially
- Leave subscriptions alive after sign-out

### 7. Badge Count System

Push badges, tab badges, in-app toast counts, and unread counts are one connected system. Changes to any one affect all others.

**If `get_badge_counts` RPC fails:** prefer cached/stale values with a staleness indicator rather than introducing a second client-side aggregation logic path.

**Do not:**
- Remove debounce or backoff logic
- Introduce badge refresh calls that could spam the system
- Let app icon, tab badges, and unread counts diverge without deliberate reason

### 8. SwiftData Schema

**Do not:**
- Rename or remove fields without a migration plan
- Make non-additive schema changes casually
- Assume it's acceptable for local cache to be silently lost

---

## Architecture Rules

These exist to keep the codebase navigable as it grows with AI assistance. Violating them doesn't just create tech debt — it makes subsequent AI-assisted changes more error-prone.

1. **MVVM is the architecture.** Preserve it.
2. Views must not call services directly for business logic or network mutations — that belongs in ViewModels.
3. ViewModels are the UI mutation boundary.
4. Services must remain behind protocols in `Core/Protocols/`.
5. New services require a protocol and must be injected into consumers. `.shared` defaults are acceptable in constructors, but logic must depend on protocols, not concrete types.
6. No new cross-domain service dependencies without an explicit reason. If Messaging needs Claiming, route through a narrow interface — not direct service fan-in.
7. Repositories are the preferred local data access layer. ViewModels should not perform raw SwiftData fetches when an established repository exists.
8. Do not import one feature module directly into another to share internals. Use services, repositories, or established notifications for cross-feature communication.
9. Do not introduce a second architectural style into the same feature unless explicitly asked.
10. Do not combine architectural changes with behavioral changes in the same diff.

---

## State Management Rules

1. All UI-facing state holders must be `@MainActor`.
2. All ViewModels remain `ObservableObject` unless an explicit codebase-wide migration is in progress.
3. Use `@Published` for state the UI binds to.
4. Published state should not trigger heavy side effects unless the pattern is already established and proven safe.
5. Track cancellable async work with stored `Task` references.
6. Cancel work in `stop()` / `deinit` / teardown wherever the existing feature pattern expects it.
7. Do not duplicate authoritative state across multiple managers without a sync mechanism — this is a common source of subtle bugs.
8. Be cautious when mirroring `AuthService` state into `AppState` — desync between them is a difficult class of bug.

---

## Concurrency Rules

1. Do not block the main thread.
2. Use structured concurrency where practical.
3. Respect actor isolation — particularly the boundary between background Supabase Realtime callbacks and UIKit views.
4. Store all Combine cancellables.
5. Check `Task.isCancelled` in long-running async flows.
6. Prefer explicit cancellation over orphaned tasks.
7. Do not perform SwiftData batch sync writes on the main actor.
8. Be careful with mixed Combine + async/await flows — preserve existing delivery guarantees when refactoring.
9. **Realtime callbacks must be marshalled to `@MainActor` before touching SwiftData, NotificationCenter, UIKit, ViewModels, or repositories.** See "Realtime Callback Threading" in the audit notes below for required patterns.

---

## Networking Rules

1. All Supabase calls must have explicit error handling.
2. Surface domain-friendly `AppError` values to the UI — raw Supabase errors are not user-friendly.
3. Non-fatal operational failures should be recorded through the existing crash/error reporting path.
4. Use existing date decoding patterns. Do not invent new date parsing logic.
5. Use shared utilities for retry, deduplication, and rate limiting.
6. Batch-fetch related data like profiles wherever possible.
7. Do not embed raw secrets in source.
8. Do not claim XOR obfuscation is secure encryption.
9. Respect auth token lifecycle and session refresh behavior.

---

## Realtime Rules

1. Realtime payload parsing must always be defensive — payloads are not guaranteed to be well-formed.
2. If payload parsing fails or is unreliable, prefer a safe fallback sync over silent corruption.
3. Do not widen subscription scope without checking channel count and cleanup behavior.
4. Reactions remain per-conversation subscriptions, not global subscriptions.
5. Preserve deduplication between optimistic local inserts and server-originated events.
6. Preserve message ordering guarantees.
7. Treat metadata-only changes carefully — they should not trigger unnecessary full UI recomputation.
8. Any realtime refactor must be validated end-to-end, not just at compile time. Compilation is not correctness.
9. All realtime subscription callbacks must be dispatched on `@MainActor`. Plain `(RealtimeRecord) -> Void` closures invoked from background `Task` contexts are not actor-isolated — the compiler does not hop automatically. See "Realtime Callback Threading" in the audit notes.

---

## Messaging-Specific Rules

1. Do not replace `MessagesCollectionView` with a SwiftUI `List`. The UIKit implementation exists because SwiftUI List cannot meet the performance requirements.
2. Preserve incremental update behavior wherever possible.
3. Keep metadata-only updates lightweight — they should not trigger full-list redraws.
4. Preserve send failure recoverability.
5. Preserve reply context hydration behavior.
6. Preserve read receipt throttling semantics.
7. Preserve typing indicator debounce and timeout behavior unless UX change is explicitly requested.
8. Do not introduce message duplication through optimistic + realtime overlap.
9. After any messaging change, mentally verify both app-open and app-background receive paths.
10. Do not break push delivery, in-app toasts, or badge updates when touching messaging.

---

## Notification Rules

Push notifications, in-app toasts, and badge counts are one connected system. A change to any one part can break the others in non-obvious ways.

1. Preserve smart suppression — when a user is actively viewing a conversation, suppress the notification for that conversation.
2. Preserve mute behavior.
3. Preserve deep link routing for all notification types.
4. Keep action categories working: quick reply, mark read, yes/no, add to calendar, etc.
5. Do not silently change notification grouping or archival rules.
6. Do not remove background refresh or silent push behavior without explicit approval.
7. **Cross-layer sync required:** Adding, removing, or changing a notification type requires updating ALL of: the Swift enum/model, SQL triggers/RPCs/functions, Edge Function handlers, preferences mapping, badge logic, and routing logic. Do not introduce new notification type strings inline — use the single registry.

---

## Cross-Layer Synchronization Rules

Several systems span Swift client code, SQL (database RPCs/triggers), and Supabase Edge Functions. Changes to any layer must be reflected in all others.

**High-blast-radius seams** — before changing any of these, list upstream/downstream dependencies and update ALL consumers in the same change set:
- `BadgeCountManager` — if a `get_badge_counts` RPC exists, treat it as authoritative; do not expand client-side fallback aggregation
- `RealtimeManager` — subscription scope, channel count, cleanup
- `NavigationCoordinator` — routing table mapping notification types to intents
- `NotificationType` — registry must match across Swift enum, SQL, and Edge Functions
- Sync engines — `MessagingSyncEngine`, `DashboardSyncEngine`, `TownHallSyncEngine`
- SwiftData ↔ Domain mappers — if you change a domain model (`Message`, `Ride`, `Favor`, `Conversation`, `Notification`, `TownHall`), update the SwiftData model, mapper(s), and sync engine insert/update logic
- Supabase RPC call sites — signature changes must propagate to all callers
- `NSNotification.Name` constants and `Constants.swift` values

**Payload parsing must be centralized.** ViewModels and sync engines must NOT hand-parse raw `Any`/JSON. All payloads go through a single adapter/decoder layer that normalizes known shapes (`record`/`new`, `data.record`/`data.new`, `oldRecord`/`old`, insert/update/delete variants).

---

## SwiftData and Local Storage Rules

1. Supabase is server-authoritative. SwiftData is the local cache and durable pending-send layer.
2. Local state may be authoritative only before server acknowledgment (optimistic flows). After ack, server wins.
3. Background sync writes must use the existing `BackgroundSyncActor` (`@ModelActor`) pattern: `BackgroundSyncActor → batch upsert → modelContext.save()`. This applies to all sync engines and bulk data operations.
4. Do not move large sync writes onto the main thread. Do not call `context.save()` from ViewModels for sync operations — delegate to repository methods that use `BackgroundSyncActor`.
5. Do not write directly to persistence from view code.
6. Avoid unbounded caches. Any new cache must have documented TTL, max size, and invalidation behavior.

---

## Security and Privacy Rules

1. RLS is the true security boundary. Client-side filtering is not security.
2. Any new sensitive table or operation requires corresponding RLS review.
3. Cross-table privileged operations should use carefully scoped RPCs or equivalent server-side logic.
4. Do not weaken auth checks to simplify development.
5. Preserve keychain usage for session and auth-sensitive tokens.
6. Keep secrets out of git.

---

## App Store Compliance Rules

**This app is in active App Store submission preparation. Every change must be App Store-safe.**

### Non-Negotiables

1. **Account deletion** must remain fully functional and accessible.
2. **Sign in with Apple** behavior must be preserved everywhere it is required.
3. **Moderation, reporting, and blocking** must remain intact for all UGC surfaces.
4. Any new permission usage requires: a valid product reason, a correct Info.plist usage description string, and UI that matches the disclosed purpose.
5. Do not add tracking SDKs or ATT-relevant behavior without explicit approval.
6. Keep privacy disclosures aligned with actual SDK usage.
7. Firebase privacy manifest coverage is required, not optional. Firebase SDKs require **required-reason API declarations** in the final privacy manifest — Apple will reject the build if these entries are missing. When updating dependencies, ensure Firebase privacy manifest entries are merged and the compiled IPA contains all required-reason declarations.
8. Do not introduce misleading claims about data handling or security.
9. If touching community or messaging features, preserve abuse-reporting pathways.

### Checklist for Any Substantial Change

Before finalizing, verify:

- [ ] Does it use a new system permission?
- [ ] Does it collect or store user data differently?
- [ ] Does it affect account deletion?
- [ ] Does it affect reporting, blocking, or moderation?
- [ ] Does it alter notification behavior?
- [ ] Does it add a third-party SDK?
- [ ] Does it require a privacy manifest update?
- [ ] Does it introduce subscription, payment, or account management changes?

If any box is checked, flag it explicitly in your response.

---

## UI and UX Rules

1. Use the existing design system. Do not introduce new visual patterns without reason.
2. Reuse existing shared components before creating new ones.
3. Prefer skeleton loading states over generic spinners for list surfaces.
4. All user-facing strings must be localizable — do not hardcode visible English strings in features that already use localization.
5. Preserve current interaction patterns unless a UX change is explicitly requested.
6. Avoid unnecessary UI churn during technical refactors.
7. Compress images with existing presets. Do not upload raw originals.
8. Keep UI changes production-polished, not placeholder quality.
9. **Accessibility**: Every interactive element must have an `accessibilityLabel` (concise, what the element is). Add `accessibilityHint` where it helps (what happens on action). Add `accessibilityIdentifier` for important controls (e.g., `"createFavor.title"`, `"claim.confirm"`). Support Dynamic Type — avoid fixed font sizes where text should scale.

---

## Performance Rules

1. Avoid full-list recomputation when a narrower incremental update is possible.
2. Avoid unbounded memory caches.
3. Be cautious with debounce window changes — they affect freshness and load in ways that aren't obvious.
4. Do not regress large-message-list scrolling performance.
5. Preserve the UIKit messaging list performance characteristics. This is why UIKit was chosen over SwiftUI here.
6. Any new caching layer must have explicit bounds and invalidation strategy.

---

## Refactor Rules

1. Refactors must preserve behavior unless behavioral change is explicitly requested.
2. Separate refactor work from feature work whenever possible. Do not combine them in one diff.
3. Do not combine architecture rewrites with bug fixes unless it is truly unavoidable — and if it is, say so.
4. Document the invariant you are preserving before changing any fragile system.
5. Preserve public APIs where practical when touching shared services.
6. When replacing duplicate logic, verify edge-case parity before deleting old paths.
7. Prefer extraction and consolidation over wholesale rewrites.
8. Do not perform large decomposition of giant ViewModels unless the current task explicitly calls for it.

---

## Testing Expectations

For any meaningful code change, include or propose concrete tests for the affected path.

**By area:**

| Area | Minimum coverage |
|---|---|
| Messaging | Optimistic send, realtime receive, dedupe, ordering, read state, reactions |
| Notifications | Deep links, category actions, toast suppression, badge updates |
| Auth | Launch routing, sign in, sign out teardown, pending approval, account deletion |
| Storage | Migration safety, cache invalidation, sync engine behavior |
| Realtime | Structured and unstructured payload cases |

**Required mindset:** Do not declare realtime, notifications, or auth "safe" based on compilation alone. Behavioral verification matters. The bugs in these systems do not show up at compile time.

---

## How to Respond to Code Tasks

For any non-trivial change, structure your response as:

1. **Scope** — exactly what is being changed, nothing more
2. **Risk level** — low / medium / high, with a one-sentence justification
3. **Plan** — short step-by-step before writing any code
4. **Code changes** — targeted implementation
5. **Why this is safe** — which invariants are preserved and how
6. **What to test** — concrete manual or programmatic verification steps
7. **Known risks / follow-ups** — anything that remains uncertain or needs future attention

If the risk level is medium or high, state the risks **before** writing code, not after.

**When touching high-blast-radius seams** (BadgeCountManager, RealtimeManager, NavigationCoordinator, NotificationType, sync engines, mappers, RPCs, Constants), end your response with an **Impact Summary**: what changed, what files were updated, and what would have broken if a consumer was missed.

---

## When to Slow Down

Be maximally conservative when changes touch any of these:

- Auth or launch routing
- Message send or receive paths
- Reactions
- Deep links
- Push notifications
- Sync engines
- SwiftData schema
- Account deletion
- Reporting, blocking, or moderation

In these areas: smaller diff, preserved logic, explicit reasoning, and verification notes are not optional — they are the output format.

---

## Quick Reference — Critical Invariants

| System | Invariant |
|---|---|
| Realtime pipeline | payload → adapter → sync engine → repository → publisher → view model → UI |
| Optimistic send | pending appears immediately; failed stays recoverable; server ack reconciles |
| Reactions | `individualReactions` is source of truth; only `setIndividualReactions(_:)` mutates it |
| Reaction badges | render at the TOP of the bubble |
| Notifications | push → AppDelegate → DeepLinkParser → NavigationIntent → NavigationCoordinator → destination |
| Auth state | initializing → checkingAuth → ready(authState) |
| Sign-out | must teardown: subscriptions, caches, sync engines, tokens |
| SwiftData | additive-only changes without a formal migration |
| UIKit messaging | MessagesCollectionView is not replaceable with SwiftUI List |

---

## Audit Notes — Known Deviations (2026-03-16)

These document where the code currently deviates from the rules above. Check these before touching the affected areas.

### Known Violations

- **`TownHallSyncEngine`** currently writes on the MainActor — this violates the SwiftData background-write rule. Do not extend this pattern; when touching this file, prefer migrating writes to `BackgroundSyncActor`.

### Realtime Callback Threading — Required Patterns

Realtime callbacks that touch SwiftData, NotificationCenter, UIKit, ViewModels, or repositories must be marshalled to `@MainActor`:

```swift
await MainActor.run { handler(record) }
// or
@MainActor @Sendable typealias RealtimeInsertCallback = (RealtimeRecord) -> Void
```

Files where this invariant is critical: `RealtimeManager.swift`, `MessagingSyncEngine.swift`, `DashboardSyncEngine.swift`, `TownHallSyncEngine.swift`. Any future realtime subscription must follow this pattern.

### High-Risk Files

Extra care required when editing — verify concurrency safety, messaging invariants, notification routing, and SwiftData schema stability:

`RealtimeManager.swift`, `MessagingSyncEngine.swift`, `MessageSendManager.swift`, `MessagingRepository.swift`, `NavigationCoordinator.swift`, `AuthService.swift`, `BadgeCountManager.swift`, `BackgroundSyncActor.swift`, `SDModels.swift`

---

## If Unsure

If a change risks breaking realtime, notifications, auth, moderation, or App Store compliance:

- Say so explicitly
- Reduce scope
- Preserve existing behavior
- Propose a safer patch

**Never guess when a fragile system invariant is at stake.**

> If a requested change conflicts with the invariants in this file, Claude must warn the user before implementing the change.
