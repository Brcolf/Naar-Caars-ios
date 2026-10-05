# CLAUDE.md

This file provides guidance to Claude Code (claude.ai/code) when working with code in this repository.

# Naar's Cars iOS

## Table of Contents

- [Read This First](#-read-this-first--before-any-code-change)
- [Current State of the Codebase](#current-state-of-the-codebase-active-context)
- [What This App Is](#what-this-app-is)
- [Build and Test Commands](#build-and-test-commands)
- [Verification Loop](#verification-loop--mandatory-after-every-change)
- [File and Naming Conventions](#file-and-naming-conventions)
- [Priority Order for Tradeoffs](#priority-order-for-tradeoffs)
- [Fragile Systems](#fragile-systems--mandatory-conservative-handling) — realtime pipeline, optimistic send, reactions, notifications, auth, sync engines, badges, SwiftData
- [Architecture Rules](#architecture-rules)
- [State Management Rules](#state-management-rules)
- [Concurrency Rules](#concurrency-rules)
- [Networking Rules](#networking-rules)
- [Realtime Rules](#realtime-rules)
- [Messaging-Specific Rules](#messaging-specific-rules)
- [Notification Rules](#notification-rules)
- [Cross-Layer Synchronization Rules](#cross-layer-synchronization-rules)
- [SwiftData and Local Storage Rules](#swiftdata-and-local-storage-rules)
- [Security and Privacy Rules](#security-and-privacy-rules)
- [App Store Compliance Rules](#app-store-compliance-rules)
- [UI and UX Rules](#ui-and-ux-rules)
- [Performance Rules](#performance-rules)
- [Refactor Rules](#refactor-rules)
- [Testing Expectations](#testing-expectations)
- [How to Respond to Code Tasks](#how-to-respond-to-code-tasks)
- [When to Slow Down](#when-to-slow-down)
- [Quick Reference — Critical Invariants](#quick-reference--critical-invariants)
- [Audit Notes — Known Deviations](#audit-notes--known-deviations)

---

## ⚠️ Read This First — Before Any Code Change

You are working in a production iOS app that is shipped on the App Store with live users.
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

**The app is live on the App Store.** All updates must be App Store-safe by default — a rejected update blocks fix delivery to live users. If a change has any submission risk, say so explicitly before proceeding.

**October 2026 cleanup branch (`claude/quirky-gates-4bkmv4`) — large, and not yet compiled.** The branch was produced in a cloud session without Xcode. It landed: push delivery restored (database webhooks authenticate with a Vault shared secret sent as `x-webhook-secret`; see `SECURITY.md` §7.4), SECURITY DEFINER function lockdown, cross-user profile reads moved to the `public_profiles` view (own-row and admin reads stay on `profiles`), `RefreshCoordinator` conformance (pull-to-refresh via `forceFullRefreshAndWait`, no launch double-sync, `*DidSync` observers reload locally only, the push-off conversations poll owned by `ConversationsListViewModel` and routed through the coordinator), push navigation only via `pendingIntent`, quick reply via `MessageSendManager`, realtime callbacks typed `@MainActor @Sendable`, most View-level mutations moved into new ViewModels, the `Log` enum replaced by `AppLogger`, hardcoded strings localized, and a performance pass. **None of it has been built or tested.** Build and run the unit suites locally before any release; `Docs/handoff/2026-10-05-cleanup-handoff.md` lists the build order, the manual Supabase dashboard actions, and the deliberately deferred items.

**The messaging view layer is mid-UIKit refactor.** The original SwiftUI messaging components are not the reference implementation. The UIKit `MessagesCollectionView`-based implementation is the current canonical path. Do not treat SwiftUI messaging components as authoritative when they conflict with UIKit ones.

**MessageInputBar.swift** has been refactored into a thin rendering shell that reads state from `InputBarController` and delegates all mutations to it. The refactor is settled — treat `InputBarController` as the authoritative input state owner.

**Swift Observation migration is partially complete.** Several ViewModels have been migrated from `ObservableObject` to `@Observable`, but this has surfaced init/deinit storms and navigation hangs (see recent commits). When touching ViewModels, check whether they use `ObservableObject` or `@Observable` and follow the existing pattern for that file. Do not opportunistically migrate additional ViewModels without explicit approval.

**Guest mode is implemented.** Anonymous users can browse rides, favors, and town hall without an account. Auth-required actions (create, claim, vote, comment, report, message) are gated in the UI and guarded by RLS policies (`20260320_0001_guest_mode_anon_read_policies.sql`). Deep link intents that require auth prompt the guest to sign up. `exitGuestMode()` must be called before any auth flow begins.

**The app uses a push-notify, pull-hydrate architecture.** The previous design used 7-8 WebSocket subscriptions per client, which hit Supabase connection limits at ~17 concurrent users. Realtime WebSockets are now scoped to the active conversation only (messages + reactions + typing). All other domains (dashboard, town hall, notifications, conversations) use pull-on-appear with 30s staleness and push-triggered refresh. Do not widen WebSocket scope — this was the root cause of the scaling issue. A centralized `RefreshCoordinator` is the single source of truth for refresh decisions, staleness tracking, and in-flight dedup. Badge counts are push-triggered with a 5-minute safety poll. See `Docs/superpowers/specs/2026-03-30-push-notify-pull-hydrate-design.md` for the full architecture spec.

**Agent tooling is aligned with Xcode 26.6 (2026-10-05).** Build, test, and preview verification run through the Xcode MCP server (`xcrun mcpbridge`), not through ad hoc `xcodebuild` output parsing. Every change follows the [Verification Loop](#verification-loop--mandatory-after-every-change) below: build via MCP, fix errors and new warnings, run the relevant tests, snapshot any UI change in light and dark appearance and at a large accessibility text size, and report what was verified. The project-wiring gaps found during this alignment were repaired on the Mac on 2026-10-05 (ten orphaned unit test files attached, absolute symlinks removed, `PerformanceImprovementsTests` moved into the test tree); what remains is listed under [Audit Notes](#audit-notes--known-deviations). The development Mac is resource-constrained: Xcode, a simulator, and Claude together exhaust it, so default to the headless lane (Lane B) or CI (Lane C) described in Build and Test Commands, and open Xcode only when `RenderPreview` is needed.

**Deployment target is iOS 26.0 (raised from 17.0 on 2026-10-05).** App Store Connect analytics showed negligible iOS 17 and iOS 18 shares, so the minimum was raised straight to iOS 26 on all three targets; this drops iPhone XS, XS Max, and XR (the iOS 17/18-only devices). Users on an older iOS keep the installed app; they only stop receiving updates. Consequences for code: `#available(iOS 18/26)` guards are now redundant and can be removed when touched, iOS 26 APIs (Liquid Glass, new SwiftUI/SwiftData features) are available unconditionally, and the simulator runtime must be iOS 26.x. The raise surfaced 34 new `deprecated in iOS 26.0` warning occurrences in the build log; because most repeat an existing message, the count of unique build warnings rose by only one (112 to 113). The deprecated APIs: `CLGeocoder`/`MKPlacemark`/`geocodeAddressString`/`reverseGeocodeLocation` in `LocationService` and `MapService` (replace with `MKGeocodingRequest` / `MKReverseGeocodingRequest`), `UIScreen.main`, `Text + Text` concatenation, and the `AppDelegate` `application(_:open:options:)` / `OpenURLOptionsKey` URL path (replace with the UIScene URL-context path; this is deep-link routing, so treat it as a fragile-system change). They are queued as follow-ups and were deliberately not fixed in the deployment-target change. Do not lower the target again without checking analytics.

**Critical active risks:**
- WebSocket callbacks (active conversation only) arrive on background threads and must be marshalled to the main actor before reaching UIKit views
- `@Observable` ViewModels passed through `.environment()` can cause init/deinit storms — recent fixes removed these patterns from sheets and tab views
- Any regression of previously-fixed App Store issues (account deletion, moderation, SIWA) is a blocker
- Guest mode gating must remain consistent — if a new auth-required action is added, it must be gated in both the UI and RLS
- `RefreshCoordinator` state machine must not be bypassed — ViewModels never call engines or `refreshIfNeeded`; the only coordinator call a ViewModel may make is `forceFullRefreshAndWait` for an explicit user-initiated reload. `MainTabView.onChange(of: selectedTab)` and app-foreground (`ContentView` → `handleAppForegrounded()`) remain the staleness triggers. The push-off conversations poll (`Constants.Timing.conversationsPushOffPollInterval`, owned by `ConversationsListViewModel`, each tick staleness-gated through the coordinator) is the one sanctioned timer besides the 5-minute safety poll

---

## What This App Is

iOS 26+ community app (deployment target 26.0; built with the Xcode 26.6 / Swift 6.3 toolchain, compiled in Swift 5 language mode) for neighbor rides/favors with messaging, town hall, notifications, open signup with admin approval, and moderation/blocking/reporting. See `README.md` for the product overview; this section covers only what's load-bearing for code work.

| Layer | Technology |
|---|---|
| Toolchain | Xcode 26.6, Swift 6.3 compiler, iOS 26 SDK (exact SDK version: confirm with `xcodebuild -showsdks`); `IPHONEOS_DEPLOYMENT_TARGET = 26.0` on all three targets; `SWIFT_VERSION = 5.0` (Swift 5 language mode), `SWIFT_APPROACHABLE_CONCURRENCY = YES`, `SWIFT_DEFAULT_ACTOR_ISOLATION = nonisolated` (app target). Do not change language mode or these flags without approval. |
| UI | SwiftUI (most surfaces) + UIKit (messaging) |
| Architecture | MVVM, singleton service layer, protocol abstractions |
| Backend | Supabase (auth, database, storage, RPC, realtime) |
| Local storage | SwiftData (cache + durable pending-send queue) |
| Crash / push | Firebase |

**SPM dependencies (Xcode-managed):** supabase-swift v2.5.1+, firebase-ios-sdk v12.8.0+, PhoneNumberKit v4.0.0+.

**Feature modules** live in `Features/<Name>/Views/` and `Features/<Name>/ViewModels/`.

---

## Build and Test Commands

> **First-time setup:** the build will fail until you create `Secrets.swift` — see [Secrets Setup](#secrets-setup-required-for-build) below before running any of the commands here.

The Xcode project is at `NaarsCars/NaarsCars.xcodeproj`. Scheme: `NaarsCars` (the only shared scheme; it builds the app and runs both `NaarsCarsTests` and `NaarsCarsUITests`, parallelized). Destination: iOS Simulator, `iPhone 16` on an iOS 26.x runtime (create one with `xcrun simctl create 'iPhone 16' com.apple.CoreSimulator.SimDeviceType.iPhone-16 <iOS-26 runtime id>` if the device list has only iPhone 17 models); deployment target iOS 26.0.

### Preferred path: Xcode MCP tools

Claude Code connects to Xcode with `claude mcp add --transport stdio xcode -- xcrun mcpbridge` (Xcode → Settings → Intelligence → Model Context Protocol → Xcode Tools must be ON, and the project must be open in Xcode). Use these tools, by their real names, instead of parsing `xcodebuild` output:

| Need | Tool | Notes |
|---|---|---|
| Find the project window | `XcodeListWindows` | Call first; every other tool needs the returned `tabIdentifier`. |
| Build | `BuildProject` (`scheme: "NaarsCars"`) | Then `GetBuildLog` with `severity: "error"`, and again with `"warning"`. Fix all errors and every warning your change introduced. |
| Live diagnostics | `XcodeListNavigatorIssues`, `XcodeRefreshCodeIssuesInFile` | Faster than a full build for a single file. |
| Run tests | `RunAllTests`, `RunSomeTests` (`tests: [...]`), `GetTestList` | Prefer `RunSomeTests` with the affected test classes; run everything before declaring a seam change safe. |
| Render a SwiftUI preview | `RenderPreview` (`sourceFilePath` = project-navigator path such as `NaarsCars/UI/Components/Common/NotificationBadge.swift`, optional `previewDefinitionIndexInFile`, `timeout`) | Writes a PNG to `previewSnapshotPath`. Its result lists `supportedPreviewVariantOverrides`; call again with `previewVariantOverrides` using these exact group and value names (verified on Xcode 26.6, 2026-10-05): `"Color Scheme"`: `Light Appearance`, `Dark Appearance`; `"Dynamic Type"`: `X Small`, `Small`, `Medium`, `Large`, `X Large`, `XX Large`, `XXX Large`, `AX 1`, `AX 2`, `AX 3`, `AX 4`, `AX 5`; `"Orientation"`: `Portrait`, `Landscape Left`, `Landscape Right`. Example: `{"Color Scheme": "Dark Appearance", "Dynamic Type": "AX 5"}`. The first render after Xcode opens can time out on this Mac ("Updating took more than 5 seconds"); retry once before falling back to Lane B. Xcode 26.6+ only. |
| Try an expression | `ExecuteSnippet` | Swift REPL; useful for decoding fixtures. |
| Look up an API | `DocumentationSearch` | Apple docs and WWDC transcripts. |

### Three verification lanes (pick the lightest that answers the question)

| Lane | When | Cost on the Mac |
|---|---|---|
| **A. Xcode MCP** (tools above) | A UI change needs `RenderPreview`, or you want live diagnostics | Xcode open; heaviest. Close the Simulator app; `RenderPreview` does not need it. |
| **B. Headless** (`xcodebuild` + `xcrun simctl`, Xcode closed) | Builds and unit tests; screenshots of the running app in light/dark and at accessibility text sizes | One headless simulator, no clones. Default lane on this machine. |
| **C. CI** (`.github/workflows/ios-ci.yml`, GitHub-hosted `macos-26` runner with Xcode 26.6) | Every pull request and manual dispatch: build + unit tests with a placeholder `Secrets.swift` | Zero. Cloud sessions read the result through PR events. Uses paid macOS minutes. |

Lane B commands. All of them keep the simulator count at one and skip UI tests unless asked:

```bash
# Build (debug, simulator) into a predictable DerivedData path
xcodebuild -project NaarsCars/NaarsCars.xcodeproj -scheme NaarsCars -sdk iphonesimulator -configuration Debug -derivedDataPath build/DerivedData -quiet build

# Unit tests only, one simulator, no parallel clones (the scheme marks both targets parallelizable; these flags override it)
xcodebuild test -project NaarsCars/NaarsCars.xcodeproj -scheme NaarsCars -destination 'platform=iOS Simulator,name=iPhone 16' -skip-testing:NaarsCarsUITests -parallel-testing-enabled NO -maximum-concurrent-test-simulator-destinations 1 -test-timeouts-enabled YES -default-test-execution-time-allowance 60 -maximum-test-execution-time-allowance 120 -derivedDataPath build/DerivedData -resultBundlePath build/TestResults.xcresult -quiet

# Single test class / method
xcodebuild test -project NaarsCars/NaarsCars.xcodeproj -scheme NaarsCars -destination 'platform=iOS Simulator,name=iPhone 16' -only-testing:NaarsCarsTests/ProfileTests -parallel-testing-enabled NO -derivedDataPath build/DerivedData -quiet
xcodebuild test -project NaarsCars/NaarsCars.xcodeproj -scheme NaarsCars -destination 'platform=iOS Simulator,name=iPhone 16' -only-testing:NaarsCarsTests/ProfileTests/testSomething -parallel-testing-enabled NO -derivedDataPath build/DerivedData -quiet

# Read failures out of the result bundle without opening Xcode
xcrun xcresulttool get test-results summary --path build/TestResults.xcresult

# Headless simulator (no Simulator.app window): boot, install the built app, launch, screenshot
xcrun simctl boot 'iPhone 16' 2>/dev/null || true
xcrun simctl install booted build/DerivedData/Build/Products/Debug-iphonesimulator/NaarsCars.app
xcrun simctl launch booted com.NaarsCars
xcrun simctl io booted screenshot build/shot-light.png

# Appearance and Dynamic Type overrides for the headless screenshots
xcrun simctl ui booted appearance dark
xcrun simctl ui booted content_size accessibility-extra-extra-extra-large   # sizes: extra-small … extra-extra-extra-large, accessibility-medium … accessibility-extra-extra-extra-large
xcrun simctl io booted screenshot build/shot-dark-ax5.png
xcrun simctl ui booted appearance light; xcrun simctl ui booted content_size large   # reset

# Shut the simulator down when finished; it is the biggest memory consumer
xcrun simctl shutdown booted

# Clean build artifacts
scripts/CLEAR-XCODE-CACHE.sh
```

`build/` is gitignored. Run UI tests only on request: `-only-testing:NaarsCarsUITests` with the same single-simulator flags.

Test targets: `NaarsCarsTests` (unit, XCTest; 72 files on disk, every one attached to the target as of this branch — `ThrottlerTests` compiles again, and `PushNotificationServiceTests` runs without timing out or reaching the live project — its permission case is stubbed through `NotificationAuthorizationRequesting` and its token cases skip without a session) and `NaarsCarsUITests` (UI automation, XCTest). Tests are parallelizable. There is no `.xctestplan`; the scheme's Test action runs both targets directly. There are no Swift Testing files (`NaarsCarsTests/NaarsCarsTests.swift` is an XCTest file); because XCTest/Swift Testing interop is off by default since Xcode 26.4, `SWIFT_TESTING_XCTEST_INTEROP_MODE=limited` would have to be set in a test plan or the scheme's test environment if Swift Testing tests are ever mixed into this target.

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

Install it with `scripts/install-hooks.sh`, which writes a thin wrapper that delegates to the versioned `scripts/pre-commit-secrets-check.sh` (that script chains `pre-commit-localization-check.sh`).

### MCP Servers

Supabase and GitHub MCP tools are provided by the Claude Code environment — there is no `.mcp.json` in the repository. Use the Supabase MCP for database queries, migrations, and edge function management; its `apply_migration` / `execute_sql` hold `DROP` and `CREATE OR REPLACE` statements for interactive confirmation, so see the migration rules under [File and Naming Conventions](#file-and-naming-conventions) before relying on it from a headless session. Use the GitHub MCP for PR and issue operations.

### Validation Scripts

`scripts/` contains validation helpers beyond the pre-commit hook:
- `VERIFY-ALL-FILES.sh` — full-project file integrity check
- `verify-apple-signin-config.sh` — validates SIWA entitlements and Info.plist
- `validate-notification-types.sh` — checks notification type registry consistency across Swift and TypeScript layers
- `verify-xcode-file-sync.sh` — runs after every Write/Edit as a Claude Code PostToolUse hook (configured in the tracked `.claude/settings.json`). For a `.swift` file outside the two synchronized folders, it checks whether `project.pbxproj` references the file and warns when it does not, since such a file will not compile until it is added to the project.
- `install-hooks.sh` — installs the git pre-commit hook (see above)
- `pre-commit-localization-check.sh` — validates localization key consistency (called by the pre-commit hook)
- `pre-commit-secrets-check.sh` — blocks commits containing secrets or signing files (called by the pre-commit hook)

**CI:** `.github/workflows/ios-ci.yml` (Lane C) builds the app and runs the unit tests on a GitHub-hosted `macos-26` runner with Xcode 26.6 on every pull request and on manual dispatch. It uses a placeholder `Secrets.swift` and a placeholder `GoogleService-Info.plist` unless the repository secrets `SUPABASE_URL`, `SUPABASE_ANON_KEY`, and `GOOGLE_SERVICE_INFO_PLIST_B64` are set. UI tests do not run in CI. There is no deploy pipeline; TestFlight and App Store submission remain manual.

**Project slash commands** (`.claude/commands/`): `/verify-ui <ViewName>` (build, then light/dark/large-text captures via `RenderPreview` or headless `simctl`), `/preflight` (build, unit tests, warnings summary, sensitive-path scan of the diff), `/headless-test [Class[/method]]` (unit tests on one headless simulator with Xcode closed).

### Cursor Rules

`.cursor/rules/` contains 9 rule files that reinforce the patterns in this document with file-glob scoping. Key rules: impact seam analysis (`01`), notification type registry consistency (`02`), centralized realtime payload parsing (`03`), badge count server contract (`04`), navigation intent pattern (`05`), SwiftData mapper mirroring (`06`), service DI via protocols (`07`), fixture test requirements for seam changes (`08`), and a master project rule (`naars-cars-project.mdc`, `alwaysApply: true`). These rules use glob-based `Applies to:` patterns to scope enforcement to relevant files.

### Agent Instructions

`AGENTS.md` contains condensed project conventions for Codex and other AI agents. It mirrors the naming, architecture, and Xcode project-membership rules from this file in a shorter format.

### Key Reference Documents

- `SECURITY.md` — RLS policies, security requirements, compliance details, webhook authentication (§7.4), credential rotation (§3.2)
- `MESSAGING-REVIEW-AND-PLAN.md` — deep architectural review of the messaging/realtime system; read before touching messaging internals
- `Docs/superpowers/specs/2026-03-30-push-notify-pull-hydrate-design.md` — authoritative spec for the push-notify, pull-hydrate architecture and `RefreshCoordinator`
- `Docs/handoff/2026-10-05-cleanup-handoff.md` — what the October 2026 cleanup branch changed, what must be done on a Mac and in the Supabase dashboard, and what was deliberately deferred

**Historical artifacts — do not treat as authoritative.** Root-level `*-PLAN.md`, `*-SUMMARY.md`, `*-CHECKLIST.md`, `CHECKPOINT-RESULTS.md`, and similar files (e.g., `BUILD-PLAN.md`, `EXECUTION-SUMMARY.md`, `FOUNDATION-COMPLETION-SUMMARY.md`, `REMAINING-TASKS-SUMMARY.md`, `NaarsCars/CLEANUP_SUMMARY*.md`, `NaarsCars/ADD-FILES-TO-XCODE.md`, `NaarsCars/FIX-*.md`, `NaarsCars/MISSING-FILES-REPORT.txt`) are stale planning/migration notes left over from earlier phases. Do not cite them in code review or rely on them for current behavior unless they are explicitly cross-referenced from this file or `SECURITY.md`.

---

## Verification Loop — Mandatory After Every Change

Compilation is not correctness, and an unbuilt change is not done. After every code change, in this order:

1. **Build through the Xcode MCP.** `BuildProject` on scheme `NaarsCars`, then `GetBuildLog` for errors and for warnings. Fix every error and every warning your diff introduced. Do not suppress warnings to get green.
2. **Run the relevant tests.** `RunSomeTests` for the affected classes (see the Testing Expectations table for which areas need which coverage), then `RunAllTests` before finishing a change to any fragile system or high-blast-radius seam. All 72 test files are attached, but several classes `XCTSkip` their live-backend cases when no session is signed in on the simulator (see Audit Notes); a green headless run does not exercise those paths.
3. **Snapshot every UI change.** For each touched SwiftUI view with a `#Preview` (101 files have one), call `RenderPreview` and inspect the image, then render again with `previewVariantOverrides` for dark appearance and for a large accessibility type size. Render landscape only for screens that support it (the iPhone orientation mask allows landscape, but the messaging thread and input bar are the screens most likely to break; verify them when touched). Look at every image: clipped text, overlapping badges, truncated Dynamic Type, unreadable dark-mode contrast, reaction badges not at the top of the bubble. Fix before reporting. UIKit messaging surfaces (`MessagesCollectionView`, `MessageThreadViewController`) have no SwiftUI preview; verify them with Lane B screenshots (`simctl ui … appearance dark`, `content_size accessibility-…`). When Xcode cannot be opened, Lane B screenshots of the running app are the accepted substitute for `RenderPreview` for any view.
4. **Report what was verified and how.** Name the build result, which tests ran and their outcome, and which snapshots were inspected. Say explicitly what could not be verified (no simulator, no Xcode MCP, test not wired). Never say "done" for a change that was not built.

---

## File and Naming Conventions

- **ViewModels**: `*ViewModel.swift`, `final class … : ObservableObject`
- **Views**: `*View.swift`, `*Sheet.swift`, `*Card.swift`, `*Row.swift`
- **Services**: `*Service.swift` or `*Manager.swift` in `Core/Services/`
- **Models**: `Core/Models/`, struct/enum name matches filename
- **Protocols**: `Core/Protocols/` — the core domain services have one (`AuthServiceProtocol`, `RideServiceProtocol`, etc.; `BadgeCountManaging` for `BadgeCountManager`). Many services still do not — see Architecture rule 4.
- **Feature layout**: `Features/<Name>/Views/` and `Features/<Name>/ViewModels/`
- **Shared UI**: Reusable components in `UI/Components/` (subdirs: Buttons, Cards, Common, Feedback, Inputs, Map, Messaging). Check existing components (e.g., `PrimaryButton`, `EmptyStateView`, `SkeletonView`, `LocationAutocompleteField`) before creating new ones.
- **Swift file header**: `//` / `//  FileName.swift` / `//  NaarsCars` / `//`
- **Constants**: Use the `Constants` enum in `Core/Utilities/Constants.swift` for animation durations, spacing, timeouts, cache TTLs, rate limits, page sizes, and URLs. Do not introduce new magic numbers.

**Xcode synchronized folders are only partially used.** The project (object version 77) has exactly two `PBXFileSystemSynchronizedRootGroup`s: `NaarsCars/NaarsCars/` (app target; it holds only `Assets.xcassets`, `GoogleService-Info.plist` and the entitlements — no Swift sources) and `NaarsCars/NaarsCarsUITests/`. Everything else is a classic group with explicit file references: `NaarsCars/App/`, `NaarsCars/Core/`, `NaarsCars/Features/`, `NaarsCars/UI/` (384 app files) and `NaarsCars/NaarsCarsTests/` (72 unit test files). Consequences:
- A new `.swift` file under `NaarsCars/App/`, `Core/`, `Features/`, `UI/`, or `NaarsCarsTests/` is **not** compiled until it is added to the project. Add it through Xcode (or the Xcode MCP file tools; confirm that files created this way land in the right target) and check it compiles via `BuildProject` and, for tests, shows up in `GetTestList`. Do not hand-edit `project.pbxproj`. Xcode 16+ "Convert to Folder" on a group is the sanctioned way to make a directory filesystem-synced.
- A new file under `NaarsCars/NaarsCars/` is auto-discovered, but Swift sources do not belong there; do not start a parallel source tree in that root without approval.
- A PostToolUse hook (`scripts/verify-xcode-file-sync.sh`, wired in `.claude/settings.json`) warns when a written `.swift` file name is missing from `project.pbxproj`.

**Secrets**: `Secrets.swift` is gitignored. Use `Secrets.swift.template` and `NaarsCars/Scripts/obfuscate.swift` for credential obfuscation.

**Localization**: All user-facing strings use `"key".localized` with keys in `Resources/Localizable.xcstrings` (Xcode string catalog format). A pre-commit hook validates localization changes.

**Database migrations**: Two locations; only one is live:
- `database/` — frozen legacy SQL files with numeric prefix (e.g., `092_badge_counts_rpc.sql`; latest is `132`). Do not add to or modify them.
- `supabase/migrations/` — the schema source of truth. Both naming forms exist and are fine: `YYYYMMDD_XXXX_description.sql` (hand-written) and the Supabase MCP's 14-digit timestamp form (`YYYYMMDDHHMMSS_description.sql`). All new SQL goes here. A migration applied through the Supabase MCP or dashboard must be committed in the same change. The MCP's `apply_migration` / `execute_sql` hold `DROP` and `CREATE OR REPLACE` statements for interactive confirmation, so from a headless session prefer additive statements and leave destructive ones for the SQL editor. `20261005_0004_function_caller_guards.sql` is committed but pending manual application for exactly this reason.

**Supabase edge functions**: `supabase/functions/` — `revoke-apple-token`, `send-message-push`, `send-notification`. Shared utilities in `supabase/functions/_shared/` (`apns.ts`, `badges.ts`, `notificationTypes.ts`, `webhookAuth.ts`). The `notificationTypes.ts` registry must stay in sync with the Swift `AppNotification` enum — use `scripts/validate-notification-types.sh` to verify. Deploy edge functions using the Supabase MCP `deploy_edge_function` tool. Database webhooks are created by `public.invoke_edge_webhook()` and never embed API keys: they send the Vault shared secret as `x-webhook-secret`, which `_shared/webhookAuth.ts` verifies (`SECURITY.md` §7.4).

**Test fixtures**: `NaarsCarsTests/Core/Fixtures/` contains `RealtimeFixtures.swift`, `WebhookFixtures.swift`, and `NotificationFixtures.swift`. When adding payload handling, add corresponding fixtures and decoding tests here.

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
- `Core/Services/RefreshCoordinator.swift` (result contract: `Core/Models/RefreshMetrics.swift`)
- `Core/Storage/MessagingSyncEngine.swift`
- `Core/Services/RealtimeManager.swift`
- `Core/Storage/MessagingRepository.swift`
- `Core/Services/MessageSendWorker.swift`
- `Core/Services/MessageService.swift`
- `Core/Services/MessageReactionService.swift`

**Realtime WebSockets apply ONLY to the active conversation** (messages + reactions + typing). All other domains use push-triggered refresh through the coordinator.

**Active conversation data flow — do not break or bypass any step:**
```
WebSocket event
  → payload adapter
  → sync engine
  → repository (MainActor upsert with change detection)
  → publisher
  → view model
  → UI
```

**All other domains (dashboard, town hall, notifications, conversations):**
```
push notification / staleness expiry / pull-to-refresh
  → RefreshCoordinator
  → sync engine (performFullSync / performTargetedSync)
  → BackgroundSyncActor (compare-before-write, conditional save)
  → SwiftData
  → @Query / publisher
  → UI
```

**Why this matters:** Bypassing the repository layer or the coordinator causes message loss, duplication, stale data, or silent corruption that is very hard to reproduce in testing but will affect users reliably.

**Do not:**
- Bypass the repository layer for any reason
- Remove deduplication logic
- Assume payloads are well-formed — they aren't always
- Call sync engine methods directly from ViewModels — go through `RefreshCoordinator`
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

Engines are pure fetch-and-store. The `RefreshCoordinator` owns all refresh decisions, staleness tracking, and in-flight dedup.

**Required engine lifecycle:**
```
setup / setupBackgroundActor (once per container)
  → startSync (session setup only — must not fetch)
  → performFullSync / performTargetedSync (coordinator-driven)
  → teardown (cancels session work only)
```

Engines keep their container-scoped `modelContext` / `backgroundActor` across sign-out — `teardown()` only cancels session work (realtime channels, the send worker) — because nothing re-runs `setup` / `setupBackgroundActor` on the next sign-in. `SyncEngineProtocol` has no `pauseSync` / `resumeSync`.

**Coordinator per-domain state machine** (domains: `dashboard`, `townHall`, `conversations`, `badges`):
```
unhydrated → hydrated → invalidated → refreshing → hydrated
                                    ↘ failed → invalidated (on retry)
```
- `unhydrated`: initial state, no data fetched yet
- `hydrated`: data is fresh (within staleness window)
- `invalidated`: push or staleness expired, needs refresh
- `refreshing`: fetch in progress (join, don't duplicate)
- `failed`: fetch errored, retryable

**Coordinator methods (not engine methods):** `refreshIfNeeded`, `performTargetedRefresh`, `forceFullRefresh`, `forceFullRefreshAndWait`, `invalidate`, `setVisibleDomain`, `handleAppForegrounded`, `reset`. ViewModels never call engines or `refreshIfNeeded`; the only coordinator call a ViewModel may make is `forceFullRefreshAndWait` for an explicit user-initiated reload (pull-to-refresh, mark-read, approve). `MainTabView.onChange(of: selectedTab)` and app-foreground remain the staleness triggers; the push-off conversations poll in `ConversationsListViewModel` (`Constants.Timing.conversationsPushOffPollInterval`, ticks staleness-gated through the coordinator) is the one sanctioned timer besides the 5-minute safety poll.

**MessagingSyncEngine has additional conversation-scoped methods** outside the protocol: `subscribeToConversation(_ conversationId:)`, `beginGracePeriod()`, `cancelGracePeriodAndUnsubscribe()`, `refreshConversationList()`.

**Do not:**
- Call engine `performFullSync`/`performTargetedSync` from ViewModels — go through the coordinator
- Bypass the coordinator's in-flight dedup (at most one task per domain)
- Tear down partially
- Leave subscriptions alive after sign-out

### 7. Badge Count System

Push badges, tab badges, in-app toast counts, and unread counts are one connected system. Changes to any one affect all others. Badge counts are **push-triggered** (every push refreshes badges) with a **5-minute safety poll** managed by `RefreshCoordinator`. There are no 30s/90s polling timers.

**If `get_badge_counts` RPC fails:** prefer cached/stale values with a staleness indicator rather than introducing a second client-side aggregation logic path.

**Badge refresh entry points:** after a user action (mark read, approve, review) call `RefreshCoordinator.forceFullRefreshAndWait(.badges, trigger:)`; after a push, `PushNotificationService` / `AppDelegate` call `RefreshCoordinator.performTargetedRefresh(.badges, …)`. Only the coordinator calls `BadgeCountManager.refreshAllBadges`.

**Do not:**
- Remove the 5s debounce (prevents push bursts) or backoff logic
- Reintroduce frequent polling timers — the safety poll interval is 5 minutes
- Let app icon, tab badges, and unread counts diverge without deliberate reason
- Bypass the coordinator for badge refresh scheduling

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
4. Services must remain behind protocols in `Core/Protocols/`. **Known deviation:** roughly two dozen services still have none — `TownHallService`, `LeaderboardService`, `AdminService`, `PushNotificationService`, `RealtimeManager`, `RefreshCoordinator`, `MessageReactionService`, `MessageMediaService`, `ConversationParticipantService`, among others. Only the core domain services (`Auth`, `Ride`, `Favor`, `Claim`, `Conversation`, `Message`, `Notification`, `Profile`, `Review`) and `BadgeCountManager` (`BadgeCountManaging`) have one today.
5. New services require a protocol and must be injected into consumers. `.shared` defaults are acceptable in constructors, but logic must depend on protocols, not concrete types. Add a protocol to an existing protocol-less service only when you are already editing that service for another reason — do not run a protocol sweep as its own change.
6. No new cross-domain service dependencies without an explicit reason. If Messaging needs Claiming, route through a narrow interface — not direct service fan-in.
7. Repositories are the preferred local data access layer. ViewModels should not perform raw SwiftData fetches when an established repository exists.
8. Do not import one feature module directly into another to share internals. Use services, repositories, or established notifications for cross-feature communication.
9. Do not introduce a second architectural style into the same feature unless explicitly asked.
10. Do not combine architectural changes with behavioral changes in the same diff.

---

## State Management Rules

1. All UI-facing state holders must be `@MainActor`.
2. The observation split is mixed and settled: 33 screen ViewModels (31 once the two dead dashboard ViewModels are deleted) are `ObservableObject`; the four messaging/notifications screen ViewModels (`ConversationDetailViewModel`, `MessageThreadViewModel`, `ConversationsListViewModel`, `NotificationsListViewModel`), the ~11 helper managers under `Features/*/ViewModels/` (`MessageSendManager`, `TypingIndicatorManager`, `NotificationGroupingManager`, …), a few Core/UI state holders (`BadgeCountManager`, `InAppToastManager`, `InputBarController`, `AppTheme`), `AppState`, and `NavigationCoordinator` are `@Observable`. **New ViewModels must be `ObservableObject` + `@MainActor`.** Do not migrate existing ones in either direction without explicit approval.
3. Use `@Published` for state the UI binds to in `ObservableObject` types.
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
9. **Realtime callbacks must be marshalled to `@MainActor`.** Supabase Realtime delivers channel events on its own socket queue. `MessagingSyncEngine` is `@MainActor`, `MessagingRepository` upserts on the main actor, and the UIKit messaging views are main-thread-only, so any handler that reaches them from the socket queue produces intermittent `UICollectionView` inconsistency crashes and SwiftData context violations that do not reproduce in tests. See "Realtime Callback Threading" in the Audit Notes section for required patterns and affected files.

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

**Realtime WebSockets are conversation-scoped only.** At most ~3 channels are active at any time (messages, reactions, typing for one conversation). All other domains use push-triggered refresh and pull-on-appear through the `RefreshCoordinator`.

1. Realtime payload parsing must always be defensive — payloads are not guaranteed to be well-formed.
2. If payload parsing fails or is unreliable, prefer a safe fallback sync over silent corruption.
3. Do not widen subscription scope beyond the active conversation. Dashboard, town hall, and notifications must not use WebSocket subscriptions.
4. At most one conversation has active WebSocket channels at any time.
5. Preserve deduplication between optimistic local inserts and server-originated events.
6. Preserve message ordering guarantees.
7. Treat metadata-only changes carefully — they should not trigger unnecessary full UI recomputation.
8. Any realtime refactor must be validated end-to-end, not just at compile time. Compilation is not correctness.
9. All realtime subscription callbacks must be dispatched on `@MainActor`. See "Realtime Callback Threading" in the Audit Notes section for required patterns.
10. Conversation WebSocket lifecycle follows subscribe-then-fetch: subscribe to channels, wait for confirmation, REST fetch recent messages, upsert to SwiftData, then process buffered events. This closes the race window between REST and WebSocket.
11. A 5-second grace period applies when navigating back to conversation list. Leaving the messaging tab or backgrounding the app triggers immediate unsubscribe. (**Known deviation:** backgrounding currently unsubscribes after `Constants.Timing.realtimeBackgroundUnsubscribeDelay` — 30 s — see Audit Notes.)

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
11. **UIKit memory hygiene in the messaging path.** `MessagesViewController`, `MessageThreadViewController`, `MessageOverlayController`, and `MessagesCollectionView` are long-lived UIKit objects hosted from SwiftUI through `UIViewControllerRepresentable`/`UIViewRepresentable` coordinators. Capture `self` weakly in every closure they store or hand to Combine, `Task`, `NotificationCenter`, gesture, or diffable-data-source APIs; keep delegates `weak`; cancel stored `Task`s and `cancellables` and remove observers in `deinit`/teardown; and never let a Representable coordinator and its ViewModel retain each other. **Why:** a leaked thread controller keeps its realtime handlers alive after the user leaves the conversation, which silently violates the "at most one conversation has active channels" invariant, double-applies incoming messages, and reintroduces the connection-limit problem that forced the push-notify, pull-hydrate redesign.

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
8. When adding or changing deep link routing, validate the mapping between notification types and navigation intents with a test or debug harness. The full routing table must be documented and verifiable.

---

## Cross-Layer Synchronization Rules

Several systems span Swift client code, SQL (database RPCs/triggers), and Supabase Edge Functions. Changes to any layer must be reflected in all others.

**High-blast-radius seams** — before changing any of these, list upstream/downstream dependencies and update ALL consumers in the same change set:
- `RefreshCoordinator` — centralized refresh orchestration, staleness tracking, in-flight dedup, domain state machine. All refresh decisions flow through here. ViewModels must not bypass it.
- `PushNotificationService.handlePushReceived()` — push type to domain mapping. `NotificationType.affectedDomains` and `entityIdKey` must stay in sync with edge function payload construction.
- `BadgeCountManager` — if a `get_badge_counts` RPC exists, treat it as authoritative; do not expand client-side fallback aggregation
- `RealtimeManager` — conversation-scoped subscription only (~3 channels max), cleanup
- `NavigationCoordinator` — routing table mapping notification types to intents
- `NotificationType` — registry must match across Swift enum, SQL, and Edge Functions. `affectedDomains` and `entityIdKey` extensions must cover all cases.
- Sync engines — `MessagingSyncEngine`, `DashboardSyncEngine`, `TownHallSyncEngine`
- SwiftData ↔ Domain mappers — if you change a domain model (`Message`, `Ride`, `Favor`, `Conversation`, `Notification`, `TownHall`), you MUST atomically update all three: the SwiftData model, mapper(s), and sync engine insert/update logic. These are a mandatory trio — updating one without the others will cause silent data loss or crashes.
- Supabase RPC call sites — signature changes must propagate to all callers
- `NSNotification.Name` constants and `Constants.swift` values

**Payload parsing must be centralized.** ViewModels and sync engines must NOT hand-parse raw `Any`/JSON. All payloads go through a single adapter/decoder layer that normalizes known shapes (`record`/`new`, `data.record`/`data.new`, `oldRecord`/`old`, insert/update/delete variants).

**Fixture test gate for seam changes.** When modifying high-blast-radius seams (badge, notifications, realtime, mappers, RPCs, edge functions), at minimum one fixture test covering the changed payload or contract is required. See `NaarsCarsTests/Core/Fixtures/` for existing patterns.

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

`NaarsCarsTests` compiles 72 test files. `BackgroundSyncActorConversationSyncTests` is the fixture test for the conversation-prune rule in `BackgroundSyncActor.syncConversations` (absent-within-window conversations deleted, older ones kept, an unchanged page writes nothing) — extend it rather than adding a parallel harness.

**Frameworks:** the suite is XCTest; there are no Swift Testing files. If a change adds Swift Testing tests to `NaarsCarsTests`, set `SWIFT_TESTING_XCTEST_INTEROP_MODE=limited` in the scheme's test environment (or a new test plan) so both frameworks run under one invocation; since Xcode 26.4 this interop is off by default. For UI-related tests, attach the rendered image to the test (`XCTAttachment` in XCTest; `Attachment` with `UIImage`/`CGImage` in Swift Testing, available since Xcode 26.4) so failures are inspectable.

**Required mindset:** Do not declare realtime, notifications, or auth "safe" based on compilation alone. Behavioral verification matters. The bugs in these systems do not show up at compile time.

---

## How to Respond to Code Tasks

For any non-trivial change, structure your response as:

1. **Scope** — exactly what is being changed, nothing more
2. **Risk level** — low / medium / high, with a one-sentence justification
3. **Plan** — short step-by-step before writing any code
4. **Code changes** — targeted implementation
5. **Why this is safe** — which invariants are preserved and how
6. **What was verified, and what to test** — the build result, tests run, and snapshots inspected (per the Verification Loop), followed by any remaining manual verification steps
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
- RefreshCoordinator or sync engines
- SwiftData schema
- Account deletion
- Reporting, blocking, or moderation

In these areas: smaller diff, preserved logic, explicit reasoning, and verification notes are not optional — they are the output format.

---

## Quick Reference — Critical Invariants

| System | Invariant |
|---|---|
| RefreshCoordinator | At most ONE refresh task per domain. Join in-flight, never cancel (except sign-out). |
| Push-triggered refresh | push → PushNotificationService → RefreshCoordinator → engine → BackgroundSyncActor → SwiftData |
| Active conversation | Subscribe-then-fetch: subscribe → confirmation → REST fetch → upsert → process buffered events |
| Realtime pipeline (active conversation) | WebSocket → adapter → sync engine → repository (MainActor) → publisher → view model → UI |
| Non-realtime domains | coordinator → engine → BackgroundSyncActor (compare-before-write) → SwiftData → @Query/publisher → UI |
| SwiftData writes | Change detection mandatory: no save without mutation. NSNotifications posted only after save. |
| Optimistic send | pending appears immediately; failed stays recoverable; server ack reconciles |
| Reactions | `individualReactions` is source of truth; only `setIndividualReactions(_:)` mutates it |
| Reaction badges | render at the TOP of the bubble |
| Notifications | push → AppDelegate → DeepLinkParser → NavigationIntent → NavigationCoordinator → destination |
| Auth state | initializing → checkingAuth → ready(authState) |
| Launch hydration | `AppLaunchManager` → `RefreshCoordinator.refreshIfNeeded(.dashboard / .conversations / .townHall, trigger: "launch")`. Engine `startSync()` is session setup only and never fetches. |
| Sign-out | teardown (session work only — engines keep their container-scoped `modelContext` / `backgroundActor`) → wipe SwiftData → clear sync timestamps → reset coordinator. All domains nil, badges zero, @Query returns []. |
| SwiftData schema | additive-only changes without a formal migration |
| UIKit messaging | MessagesCollectionView is not replaceable with SwiftUI List |

### Canonical Entry Points

When you need to do one of these things, this is the *only* path. Do not duplicate — extend the existing API.

| If you need to… | Call this | Do not |
|---|---|---|
| Send a chat message | `MessageSendManager.sendMessage(...)` (or `sendAudioMessage` / `sendLocationMessage` / `retryMessage`) | Send from `MessagingRepository`, Views, ViewModels, or untracked `Task {}` blocks |
| Refresh a domain after push or staleness | `RefreshCoordinator.refreshIfNeeded(_ domain:, trigger:)` | Call sync engine `performFullSync` / `performTargetedSync` from a ViewModel |
| Pull-to-refresh / manual reload from a ViewModel | `RefreshCoordinator.forceFullRefreshAndWait(_:trigger:)` (awaitable; joins in-flight; never cancels) | Bypass the coordinator's in-flight dedup, or call an engine |
| Refresh badges after a user action (mark read, approve, review) | `RefreshCoordinator.forceFullRefreshAndWait(.badges, trigger:)` | Call `BadgeCountManager.refreshAllBadges` directly — only the coordinator calls it |
| Refresh badges after a push | `RefreshCoordinator.performTargetedRefresh(.badges, entityId:, trigger:)` from `PushNotificationService` / `AppDelegate` | Add a second badge-refresh path |
| Send a quick reply from a push action | `MessageSendManager.sendMessage(...)` via `PushNotificationService` | Call `MessageService.sendMessage` directly from the push handler |
| Mark a domain dirty after a push | `RefreshCoordinator.invalidate(_:reason:)` | Mutate engine state directly |
| Track which tab/screen is visible | `RefreshCoordinator.setVisibleDomain(_:)` from `MainTabView.onChange(of: selectedTab)` | Call this from individual ViewModels |
| Mutate reaction state on a `Message` | `Message.setIndividualReactions(_:)` | Mutate `reactions` (aggregated) directly |
| Route a deep link / push intent | `NavigationCoordinator.navigate(to: DeepLink)` (sets `pendingIntent`) | Set `@Published navigateToX` flags or navigate from `AppDelegate` / `PushNotificationService` |
| Subscribe to a conversation's realtime channels | `MessagingSyncEngine.subscribeToConversation(_:)` (subscribe-then-fetch) | Open WebSocket channels from anywhere else, or fetch before subscribing |
| Persist sync writes from a sync engine | `BackgroundSyncActor` (compare-before-write, conditional `save()`) | Call `modelContext.save()` from the main actor or a ViewModel for sync data |

---

## Audit Notes — Known Deviations

These document where the code currently deviates from the rules above. Check these before touching the affected areas.

### Known Violations

**Last audited: 2026-10-05 against the merge of `claude/quirky-gates-4bkmv4` and `claude/eloquent-hypatia-rar9pm` (built and unit-tested on the Mac, Xcode 26.6, headless Lane B).**

Two fragile-system deviations are confirmed and **unfixed** (found by the 2026-10-05 test-hardening pass; the fix needs owner approval and on-device verification because both are in the active-conversation receive path):

- **`ConversationDetailViewModel.setupConversationUpdatedObserver` drops the notification's `object`** (around line 593): the `.conversationUpdated` notification is rebuilt on the main actor with `Notification(name:userInfo:)`, so `handleConversationUpdatedImmediate` → `notificationConversationId` always sees `nil` and every event is ignored. The user-visible impact is small: new messages, edits, unsends and moderation hides still update live through `repository.save(changedConversationIds:)` → `refreshMessagesPublishers` → the view model's messages publisher. What the bug loses is the view model's own `handleMessageUpdate` / `handleMessageDelete` handling and the throttled background resync after a delete. The `read_by` bullet below is the user-visible messaging bug. Fix: carry `notification.object as? UUID` into the rebuilt notification. `ConversationDetailViewModelRealtimeTests.testRealtimeMessageInsertUpdatesViewModel` encodes the intended behavior inside a strict `XCTExpectFailure`, so it reports an expected failure until the fix lands and turns red once it does (remove the wrapper then).
- **`MessagingSyncEngine.shouldIgnoreReadByUpdate` ignores every `read_by`-only realtime update** (around line 447, called from `handleIncomingMessage`): the per-user check (ignore only the current user's own read echoing back) was removed in `72eebf3`, so another member's read receipt never reaches `repository.upsertMessageDetailed` and the `.metadataOnly` publisher path is unreachable for live read receipts. Fix: restore the `currentUserId` condition with a defensive `read_by` decoder and a fixture test. This is the user-visible one: other members' read receipts do not update live in the open conversation. `MessagingSyncEngineTests.testShouldIgnoreReadByUpdate_ReturnsFalseForOtherUserRead` encodes the intended behavior inside a strict `XCTExpectFailure`, so it reports an expected failure until the fix lands and turns red once it does (remove the wrapper then).

The previous `TownHallSyncEngine` MainActor write deviation has been resolved — TownHall writes now use `BackgroundSyncActor`. Beyond that:

1. **Realtime rule 11 — background teardown is delayed, not immediate.** `RealtimeManager` unsubscribes after `Constants.Timing.realtimeBackgroundUnsubscribeDelay` (30 s) instead of immediately on backgrounding. Immediate teardown plus foreground resubscribe is a documented follow-up that needs on-device verification.
2. **Message inserts are not idempotent.** There is no client id / idempotency key on the send path, so a network flap mid-send can duplicate a message. Follow-up "E5b" (idempotent insert using the client id as the server id) is deferred until the SwiftData reconciliation can be verified on a simulator.
3. **`TownHallFeedViewModel.loadMore` writes SwiftData on the main actor** through `TownHallRepository.upsertPosts` (the repository is `@MainActor`). Coordinator-driven Town Hall refreshes use `BackgroundSyncActor`; only the paging path is still main-actor.
4. **`SDTownHallPost` stores no vote/review columns**, so the feed keeps a network enrichment fetch beside the coordinator refresh. That fetch must never write to SwiftData.
5. **Dead files awaiting manual deletion in Xcode** (remove the project references too): `Core/Services/MessagingDebugView.swift` (DEBUG-only, unreferenced), `Core/Utilities/Logger.swift` (legacy `Log` enum, no callers), `Features/Rides/Views/RidesDashboardView.swift` + `RidesDashboardViewModel.swift` + its test, `Features/Favors/Views/FavorsDashboardView.swift` + `FavorsDashboardViewModel.swift` + its test (only referenced by previews/tests). `DirectMessageContainerView.swift` and the eight machine-specific `NaarsCars/*.swift` symlinks are already deleted.
6. **A production `service_role` key is in git history** and must be rotated (`SECURITY.md` §3.2). The local `Secrets.swift` has moved to the `sb_publishable_…` key (REST verified); legacy JWT keys stay enabled until a build with the new key has shipped.
7. **`supabase/migrations/20261005_0004_function_caller_guards.sql` is committed but not applied** — the Supabase MCP declines its `CREATE OR REPLACE` statements; run it from the SQL editor (see Database migrations).
8. **Deliberately deferred:** an aggregate vote/comment-count RPC for Town Hall, message-window pagination in `MessagingRepository.getMessages`, incremental hydration gating in `MessagingSyncEngine`, and pruning of `SDNotification` rows.
9. **Architecture rule 2:** `SettingsView` still writes notification preferences through `ProfileService.shared.updateNotificationPreferences` directly rather than via a ViewModel.
10. **Architecture rule 4:** roughly two dozen services still have no protocol (see that rule for the policy).

**Project wiring and test suite (state after the merge, full headless unit run from a clean DerivedData on 2026-10-05):**
- All 72 unit test files on disk are attached to `NaarsCarsTests`, including the previously orphaned `ThrottlerTests` (its `TimeTracker.values` is now `private(set)`) and `PushNotificationServiceTests`. The eight absolute symlinks and the "Recovered References" entries that pointed at them are gone, so the 14 always-failing mis-bundled UI test cases no longer appear in unit runs. No test file appears twice in the Sources phase.
- Suite result after the 2026-10-05 test-hardening pass (full headless run from a clean DerivedData): 349 cases, 314 passed, 0 failed, 2 expected failures, 33 skipped (`xcodebuild` exit 0). The two expected failures are the tests for the unfixed messaging deviations above, wrapped in strict `XCTExpectFailure` so they turn red again the moment the bug is fixed without updating the test. The 33 skips are session-gated live-backend cases (`LeaderboardServiceTests`, `NotificationServiceTests`, `NotificationsListViewModelTests`, `PushNotificationServiceTests` token cases, `TownHallServiceTests`, `TownHallFeedViewModelTests`, `MyProfileViewModelTests`, `ReviewPromptProviderTests`, `CompletionPromptProviderTests`) plus the pre-existing cache-test skips; they run their real assertions only when a user is signed in on the simulator. Two test-isolation bugs that had masqueraded as "live backend HTTP 500" failures for months were fixed: `InAppToastManagerTests` leaked a fake `AuthService.shared.currentUserId` to every later class, and `ClaimServiceTests` / `ConversationParticipantsViewModelTests` left a URLProtocol stub registered process-wide that answered every later network call with a local 500. All Lane B and CI test commands pass `-test-timeouts-enabled YES` with a 60 s default / 120 s maximum allowance so a hanging test fails instead of stalling the run.
- Still open: the "Recovered References" group still exists in `project.pbxproj` and carries the only `PBXBuildFile` for some app sources, so it is load-bearing and must not be deleted wholesale. Consolidating it into the proper groups is a separate, build-verified cleanup.
- Still open: `project.pbxproj` says `LastUpgradeCheck = 2620` and the shared scheme `LastUpgradeVersion = 2630`. With the project open in Xcode 26.6 the Issue Navigator (`XcodeListNavigatorIssues`) reported no "update to recommended settings" item, so nothing was accepted; let Xcode perform the upgrade check if it ever appears rather than editing by hand.

If you make a fragile-system change, re-verify this section and bump the audit date and commit.

### Realtime Callback Threading — Required Patterns

Realtime callbacks that touch SwiftData, NotificationCenter, UIKit, ViewModels, or repositories must be marshalled to `@MainActor`:

```swift
await MainActor.run { handler(record) }
// or (as in RealtimeManager.swift)
typealias RealtimeInsertCallback = @MainActor @Sendable (RealtimeRecord) -> Void
```

Files where this invariant is critical: `RealtimeManager.swift`, `MessagingSyncEngine.swift`. Realtime is now conversation-scoped only, so `DashboardSyncEngine` and `TownHallSyncEngine` no longer have realtime callbacks. Any future realtime subscription must follow this pattern.

### High-Risk Files

Extra care required when editing — verify concurrency safety, messaging invariants, notification routing, and SwiftData schema stability:

`RefreshCoordinator.swift`, `RealtimeManager.swift`, `MessagingSyncEngine.swift`, `MessageSendManager.swift`, `MessageSendWorker.swift`, `MessagingRepository.swift`, `NavigationCoordinator.swift`, `AuthService.swift`, `BadgeCountManager.swift`, `BackgroundSyncActor.swift`, `PushNotificationService.swift`, `SDModels.swift`

---

## If Unsure

If a change risks breaking realtime, notifications, auth, moderation, or App Store compliance:

- Say so explicitly
- Reduce scope
- Preserve existing behavior
- Propose a safer patch

**Never guess when a fragile system invariant is at stake.**

> If a requested change conflicts with the invariants in this file, Claude must warn the user before implementing the change.
