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
- **Shared UI**: Reusable components in `NaarsCars/UI/Components/`. Use existing components (e.g. `PrimaryButton`, `EmptyStateView`, `LocationAutocompleteField`) before adding new ones.
- **Constants**: Use `Constants` in `Core/Utilities/Constants.swift` for animation durations, spacing, timeouts, cache TTLs, rate limits, page sizes, and URLs. Do not introduce new magic numbers; add to the appropriate `Constants` enum if needed.

## Backend and database

- **Supabase**: Use the shared client; credentials come from `Secrets` (obfuscated). Never commit `Secrets.swift`, hardcode keys, or share keys externally.
- **Migrations**: legacy SQL lives in `database/` with numeric prefix (e.g. `092_badge_counts_rpc.sql`); do not modify existing files. New migrations go in `supabase/migrations/` as `YYYYMMDD_XXXX_description.sql`, applied through the Supabase MCP.
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

- **Do not hand-edit `project.pbxproj`.** Only two folders are filesystem-synchronized (`PBXFileSystemSynchronizedRootGroup`) and auto-discovered: `NaarsCars/NaarsCars/` (app target) and `NaarsCars/NaarsCarsUITests/`. `NaarsCars/App`, `Core`, `Features`, `UI`, and `NaarsCarsTests` use explicit file references, so a new `.swift` file there is **not compiled** until it is added to the project in Xcode. After adding, confirm it builds.
- When you create a **new file**, state the file path clearly (e.g. `NaarsCars/Features/Favors/Views/MyNewView.swift`) and say that it still needs to be added to the Xcode project.

## Toolchain and verification

- Xcode 26.6 / Swift 6.3 toolchain, Swift 5 language mode (`SWIFT_VERSION = 5.0`), iOS 26.0 deployment target (all three targets). Scheme `NaarsCars`, simulator `iPhone 16`.
- After every change: build, fix all errors and new warnings, run the relevant unit tests, snapshot UI changes in light/dark and at a large accessibility text size, and report what was verified. Never report "done" on an unbuilt change. The development Mac is resource-constrained: prefer `xcodebuild` with a single headless simulator (`-parallel-testing-enabled NO -skip-testing:NaarsCarsUITests`) or the `iOS CI` GitHub Actions workflow over opening Xcode. Full commands and the Xcode MCP tool names are in `CLAUDE.md` → Build and Test Commands.
- Tests are XCTest only. Do not add Swift Testing tests without also setting `SWIFT_TESTING_XCTEST_INTEROP_MODE=limited` in the scheme's test environment.

## Secrets and build

- `Secrets.swift` is gitignored. Use `Secrets.swift.template` and `Scripts/obfuscate.swift` to generate obfuscated credential arrays. Never log or expose `Secrets.supabaseURL` or `Secrets.supabaseAnonKey`.
