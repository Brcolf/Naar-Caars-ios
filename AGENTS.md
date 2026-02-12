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
- **Shared UI**: Reusable components in `NaarsCars/UI/Components/`. Use existing components (e.g. `PrimaryButton`, `EmptyStateView`, `LocationAutocompleteField`) before adding new ones.
- **Constants**: Use `Constants` in `Core/Utilities/Constants.swift` for animation durations, spacing, timeouts, cache TTLs, rate limits, page sizes, and URLs. Do not introduce new magic numbers; add to the appropriate `Constants` enum if needed.

## Backend and database

- **Supabase**: Use the shared client; credentials come from `Secrets` (obfuscated). Never commit `Secrets.swift`, hardcode keys, or share keys externally.
- **Migrations**: SQL lives in `database/` with numeric prefix and description (e.g. `092_badge_counts_rpc.sql`). Do not modify existing migration files.
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

- **Do not edit `project.pbxproj`** to add new Swift (or other) files.
- When you create a **new file** that must be part of the app target, **tell the user** clearly: state the file path (e.g. `NaarsCars/Features/Favors/Views/MyNewView.swift`) and ask them to add it to the Xcode project manually (File → Add Files to "NaarsCars"… or drag into the correct group).

## Secrets and build

- `Secrets.swift` is gitignored. Use `Secrets.swift.template` and `Scripts/obfuscate.swift` to generate obfuscated credential arrays. Never log or expose `Secrets.supabaseURL` or `Secrets.supabaseAnonKey`.
