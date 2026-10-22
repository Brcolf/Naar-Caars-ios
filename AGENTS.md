# Naars Cars iOS — Project Instructions (Codex)

These instructions apply to all work in this repository. Follow them unless the user explicitly overrides.

---

## Naming (follow existing conventions)

- **ViewModels**: Type name `*ViewModel` (e.g. `CreateFavorViewModel`), file `*ViewModel.swift`. Use `final class … : ObservableObject`.
- **Views**: Type name matches screen/component — `*View`, `*Sheet`, `*Card`, `*Row`, etc. File name matches (e.g. `ClaimSheet.swift`, `FavorDetailView.swift`).
- **Services**: Type `*Service` or `*Manager` (e.g. `RideService`, `BadgeCountManager`). File `*Service.swift` / `*Manager.swift`. Live under `NaarsCars/Core/Services/`.
- **Models**: Under `NaarsCars/Core/Models/`. Struct/enum name and file name match.
- **Swift file header**: Use the project header format:
  - Line 1: `//`
  - Line 2: `//  FileName.swift`
  - Line 3: `//  NaarsCars`
  - Line 4: `//`
  - Optional short description (e.g. `//  View for creating a new favor request`), then blank line. Add a doc comment above the main type (e.g. `/// View for creating a new favor request`).

## Architecture

- **MVVM**: Views in `Features/<FeatureName>/Views/`, ViewModels in `Features/<FeatureName>/ViewModels/`. One primary ViewModel per screen; Views call ViewModels, ViewModels call services in `Core/Services/`.
- **Push-notify, pull-hydrate**: Realtime WebSockets are scoped to the active conversation only (messages + reactions + typing). All other domains (dashboard, town hall, notifications, conversations) use pull-on-appear with 30s staleness and push-triggered refresh. A centralized `RefreshCoordinator` owns all refresh decisions, staleness tracking, and in-flight dedup. Engines are pure fetch-and-store. ViewModels do not call refresh methods directly — `MainTabView.onChange(of: selectedTab)` is the sole staleness trigger. See `Docs/superpowers/specs/2026-03-30-push-notify-pull-hydrate-design.md` for the full spec.
- **Message sending**: `MessageSendManager` (`sendMessage`, `sendAudioMessage`, `sendLocationMessage`, `retryMessage`) is the only entry point. It saves the optimistic row in SwiftData with status `sending`, uploads any media, and makes one inline call to `MessageService`; success replaces the row with the server's, an error marks it `failed` for the user to retry. `MessageSendWorker` is a recovery drain, not a stage of every send: it resends rows still `sending` at session start and when the network returns. Never send from `MessagingRepository`, Views, ViewModels or untracked `Task {}` blocks, and do not add another caller of `MessageService.send*` or another drain trigger. Inserts are not idempotent, so a repeated attempt can duplicate a message; see `CLAUDE.md` → Fragile Systems §2 and Audit Notes ("Send path re-read, 2026-10-08").
- **Shared UI**: Reusable components in `NaarsCars/UI/Components/`. Use existing components (e.g. `PrimaryButton`, `EmptyStateView`, `LocationAutocompleteField`) before adding new ones.
- **Constants**: Use `Constants` in `Core/Utilities/Constants.swift` for animation durations, spacing, timeouts, cache TTLs, rate limits, page sizes, and URLs. Do not introduce new magic numbers; add to the appropriate `Constants` enum if needed.

## Backend and database

- **Supabase**: Use the shared client; credentials come from `Secrets` (obfuscated). Never commit `Secrets.swift`, hardcode keys, or share keys externally.
- **Migrations**: New migrations go in `supabase/migrations/` (Supabase-managed, `YYYYMMDD_XXXX_description.sql`, or the 14-digit timestamp form the Supabase MCP `apply_migration` tool creates). `database/` holds the legacy numeric-prefix migrations (e.g. `092_badge_counts_rpc.sql`) and is frozen — do not add to it or modify existing files. Any migration applied through the Supabase MCP or dashboard MUST be committed to `supabase/migrations/` in the same change (the live database had 102 migrations the repo lacked until an export on 2026-10-05).
- **RLS**: New tables or endpoints must consider RLS; see `SECURITY.md` and existing policies.

## UI and accessibility (App Store)

- **Localization**: User-facing strings use localized keys (e.g. `"key_name".localized`) and keys in `Resources/Localizable.xcstrings`. No hardcoded user-facing text.
- **Accessibility**: Every interactive element must have:
  - `accessibilityLabel` (concise, what the element is).
  - `accessibilityHint` where it helps (what happens on action).
  - `accessibilityIdentifier` for important controls (e.g. `"createFavor.title"`, `"claim.confirm"`) for automation and consistency.
- Support Dynamic Type and avoid fixed font sizes where text should scale.

## Tests

- **Do not add tests unless the user explicitly asks for them.** No new test files or test targets without a direct request.

## Xcode and new files

- **Do not hand-edit `project.pbxproj`.** Only two folders are filesystem-synchronized (`PBXFileSystemSynchronizedRootGroup`) and auto-discovered: `NaarsCars/NaarsCars/` (app target) and `NaarsCars/NaarsCarsUITests/`. `NaarsCars/App`, `Core`, `Features`, `UI`, and `NaarsCarsTests` use explicit file references, so a new `.swift` file there is **not compiled** until it is added to the project in Xcode. After adding, confirm it builds. `scripts/verify-xcode-file-sync.sh` (a Claude Code `PostToolUse` hook wired in `.claude/settings.json`) warns when a written `.swift` file has no `project.pbxproj` reference.
- When you create a **new file**, state the file path clearly (e.g. `NaarsCars/Features/Favors/Views/MyNewView.swift`) and say that it still needs to be added to the Xcode project.

## Toolchain and verification

- Xcode 26.6 / Swift 6.3 toolchain, Swift 5 language mode (`SWIFT_VERSION = 5.0`), iOS 26.0 deployment target (all three targets). Scheme `NaarsCars`, simulator `iPhone 16`.
- After every change: build, fix all errors and new warnings, run the relevant unit tests, snapshot UI changes in light/dark and at a large accessibility text size, and report what was verified. Never report "done" on an unbuilt change. The development Mac is resource-constrained: prefer `xcodebuild` with a single headless simulator (`-parallel-testing-enabled NO -skip-testing:NaarsCarsUITests`) or the `iOS CI` GitHub Actions workflow over opening Xcode. Full commands and the Xcode MCP tool names are in `CLAUDE.md` → Build and Test Commands.
- Tests are XCTest only. Do not add Swift Testing tests without also setting `SWIFT_TESTING_XCTEST_INTEROP_MODE=limited` in the scheme's test environment.

## Secrets and build

- `Secrets.swift` is gitignored. Use `Secrets.swift.template` and `Scripts/obfuscate.swift` to generate obfuscated credential arrays. Never log or expose `Secrets.supabaseURL` or `Secrets.supabaseAnonKey`.
- Install the git pre-commit hook with `scripts/install-hooks.sh`; it installs a thin wrapper that runs `scripts/pre-commit-secrets-check.sh` from the repo (secrets, signing files, localization-key check).

## Communities (Release 1: Explore and the community page)

- Tabs: Requests, Messages, Town Hall, Profile, and Explore as the search-role tab (`MainTabView`, SwiftUI `Tab` API). `MainTabView.onChange(of: selectedTab)` is the only caller of `setVisibleDomain`: Requests → `.dashboard`, Messages → `.conversations`, Town Hall → `.townHall`, Profile and Explore → nil (`NavigationCoordinator.Tab.refreshDomain`). Leaving Messages still unsubscribes the conversation.
- Explore code: `ExploreView` (root) with `MyCommunitiesView` as its content and its intent consumer (`MyCommunitiesView.exploreRoute(for:)`); `CommunityPageView(communityId:)` / `CommunityPageViewModel` (`ObservableObject`) for a community's page; `UI/Components/Common/CommunityBadges.swift` (`CommunityPolicyChip`, `CommunityMonogram`). Push every destination item-driven, never with a value-based `NavigationLink` in a pushed screen.
- Routes: community-admin routes (`.pendingMembers`, `.communityReports`, `.communityMembers`), `.myCommunities`, `.joinCommunity` and `.enterApp` (authenticated) open on Explore; platform-admin routes (`.pendingUsers`, `.adminReports`, `.adminPanel`) stay on Profile.
- A visitor reads a community only through `CommunityService.fetchCommunityPreview(communityId:)` → `get_community_preview` (listed and unarchived only; refusal `not_listed`; no address columns), never through a table read.
- Requests filter: `CommunityContext.requestsScope` (`.all`, `.community`, `.excluding`), changed through `toggleRequestsInclusion(_:)` or the title menu.
- The Explore badge (`BadgeCounts.explore`) reads `pending_members_total`.

## Communities (Phase 2)

- Community screens: `Features/Community/{Views,ViewModels}`; Admin → Communities in `Features/Admin`; onboarding in `Features/Authentication` (`CommunityOnboardingView` is the `.needsApplication` root).
- `pending_approval` with `community_id` routes to `.pendingMembers(communityId)` (Explore); without it, `.pendingUsers` opens the default community's Requests to join (Profile); `.enterApp` while authenticated opens Explore.
- Never aggregate pending counts on the client. `clearCommunityBadge(visibleCommunityId:)` clears only the visible community's Town Hall rows.
- Community RPC refusals (`{success:false, error, code}`) throw `CommunityRPCError`. Shared community sheets record a result and the presenter acts on it in `onDismiss`. `PreviewCommunityService` is the only app-target preview stand-in.

## Communities (Phase 1)

- `CommunityContext` (`@Observable`, `App/`) holds the person's memberships and the selected scopes. Switch the Community tab's community only by setting `communityTabId`; the feed refreshes through `forceFullRefreshAndWait(.townHall, …)`. `TownHallSyncEngine` reads the context at fetch start and `.townHallPostsDidSync` carries the synced scope.
- Town Hall pushes use `town_hall_post_id` (`NotificationType.entityIdKey`) and may carry `community_id`; they do a targeted single-post refresh.
- `recheckAccountStatus` acts only on a successful read; the waiting screen runs `performCriticalLaunch()`; sign-out calls `CommunityContext.resetForSignOut(userId:)`.
- Title menus use the shared `communityTitleMenu` modifier; since Release 1 they show for any member, also of one community (About this community and Find communities live there), and never for a guest. `get_badge_counts` keys `pending_members_total`, `community_details`, `total` come from the server.

## Communities (Phase 3)

- Admin and moderation code: `Features/Community/{Views,ViewModels}` (members, settings, reports) and `Features/Admin` (panel per community, announcements). Fronts: `AdminServiceProtocol` (figures, `sendBroadcast(communityId:…)`, community reports) and `CommunityAdminServiceProtocol` (remove, readmit, roles, ownership, settings, archive). `PreviewAdminService` is the app-target preview stand-in; any `#Preview` using a DEBUG-only preview service sits inside `#if DEBUG`.
- `CommunityReport` has no reporter field (INV-P2). Community screens never call `admin_get_reports` or `admin_moderate_content`; they use `AdminService.fetchCommunityReports` and `moderateCommunityContent`.
- `content_reported` with `community_id` routes to `.communityReports(communityId)` (Explore) for a non-platform admin; without it, `.adminReports` (Profile). `account_restricted` routes to `.myCommunities` (Explore).
- Coordinator triggers added: `forceFullRefreshAndWait(.dashboard, "removedMember")` and `(.dashboard, "archivedCommunity")`, from ViewModels after an explicit action only. One RPC per tap: a write method returns early while one is in flight.

## Phase 5a (multi-community) facts

- **Signed image URLs**: images of `message-images`, `group-images`, `town-hall-images`, `review-images` and voice notes (`audio-messages`) are read through `StorageURLSigner` (via `PersistentImageService.getImage(for:)`, `CachedAsyncImage`, `MessageAudioPlayer`). Never persist or log a signed URL, never download these with `URLSession.shared`, and store only the URL the upload returned.
- **Ride-cost geocoding**: `GeocodingCacheService` uses only `get_geocoding_multiplier` / `put_geocoding_multiplier`; it never reads or writes `geocoding_cache` and sends no placemark data. The client no longer touches `invite_codes`.
- Phase 5b server files (`20261019_0060`-`0063`) are applied (2026-10-20); see `CLAUDE.md`.

## Phase 4 (multi-community) facts

- **Notification types**: 34. `membership_update` is the newest; add or change a type in the Swift enum, `NotificationTypeRegistry`, `supabase/functions/_shared/notificationTypes.ts` and the SQL `valid_notification_type` CHECK together; `scripts/validate-notification-types.sh` reads all four. Its server producers and the announcement push (`20261019_0002`, `20261019_0003`) are live since 2026-10-20.
- **Incoming URLs**: `onOpenURL` → `IncomingLinkHandler.handle(_:)` (in `Core/Utilities/PendingInviteStore.swift`) saves the code in `PendingInviteStore` first, then `DeepLinkParser.parse(url:)` → `DeepLink.joinCommunity` → `NavigationCoordinator.applyExternalDeepLink`. The code is read from the fragment only and never logged. Do not add `UIApplicationDelegate` URL methods (`AppDelegate` has none).
- **Entitlement**: Associated Domains `applinks:naarscars.com`; the owner adds the capability to the App ID and hosts `Docs/universal-links/apple-app-site-association` before an archive.
- **Navigation**: new intents `communityMembers` and `joinCommunity`; the routing table test covers them.
- **Do not create new `.swift` files** in a headless run; the project file is not edited by hand.
