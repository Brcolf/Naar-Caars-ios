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

- **New Swift files must be referenced in `project.pbxproj`.** All Swift sources (`NaarsCars/App`, `Core`, `Features`, `UI` and `NaarsCars/NaarsCarsTests`) use classic Xcode groups, so a file dropped on disk is silently ignored by the build until it is added to the project (add it in Xcode, or convert the group with Xcode 16's "Convert to Folder"). The only filesystem-synced roots (`PBXFileSystemSynchronizedRootGroup`) are `NaarsCars/NaarsCars/` (asset catalog and entitlements only — no Swift sources) and `NaarsCars/NaarsCarsUITests/`. `scripts/verify-xcode-file-sync.sh` (a Claude Code `PostToolUse` hook wired in `.claude/settings.json`) warns when a written `.swift` file has no `project.pbxproj` reference.
- When you create a **new file**, state the file path clearly (e.g. `NaarsCars/Features/Favors/Views/MyNewView.swift`).

## Secrets and build

- `Secrets.swift` is gitignored. Use `Secrets.swift.template` and `Scripts/obfuscate.swift` to generate obfuscated credential arrays. Never log or expose `Secrets.supabaseURL` or `Secrets.supabaseAnonKey`.
- Install the git pre-commit hook with `scripts/install-hooks.sh`; it installs a thin wrapper that runs `scripts/pre-commit-secrets-check.sh` from the repo (secrets, signing files, localization-key check).
