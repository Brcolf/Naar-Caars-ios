# Naar's Cars iOS

Native iOS app for Naar's Cars — a community platform where neighbors help each other with rides and favors. **Live on the iOS App Store** (bundle ID `com.NaarsCars`, App Store category: Social Networking). The codebase is in active development for new features and stability work.

> The canonical operating manual for any code change is **[`CLAUDE.md`](./CLAUDE.md)** — read it before touching `Core/Services/`, `Core/Storage/`, messaging, notifications, auth, or anything else flagged as fragile.

---

## 🏗️ Technology Stack

| Layer | Technology |
|---|---|
| Language | Swift 5.9+ |
| UI | SwiftUI (most surfaces) + UIKit (messaging) |
| Architecture | MVVM, singleton service layer, protocol abstractions |
| Backend | Supabase (Postgres, Auth, Storage, RPC, Realtime) + Firebase (push, crash) |
| Local storage | SwiftData (cache + durable pending-send queue) |
| Minimum iOS | 26.0 (raised from 17.0 on 2026-10-05; drops iPhone XS, XS Max, XR) |
| Tooling | Xcode 26.6 (Swift 6.3 toolchain, Swift 5 language mode) |

**Dependencies (SPM, Xcode-managed):** `supabase-swift` v2.5.1+ (pinned 2.41.1), `firebase-ios-sdk` v12.8.0+ (pinned 12.10.0), `PhoneNumberKit` v4.0.0+ (pinned 4.2.7). Pinned versions are recorded in `Package.resolved`.

---

## 📁 Repository Layout

```
naars-cars-ios/
├── NaarsCars/                # Xcode project root
│   ├── App/                  # AppDelegate, NaarsCarsApp, MainTabView, NavigationCoordinator
│   ├── Core/                 # Services, Storage, Models, Protocols, Utilities
│   ├── Features/             # Feature modules (Messaging, Rides, Favors, TownHall, ...)
│   ├── UI/                   # Reusable components (Buttons, Cards, Map, Messaging, ...)
│   ├── Resources/            # Localizable.xcstrings (+ .backup), FlightData/
│   ├── NaarsCars/            # Assets.xcassets + entitlements only (filesystem-synced; no Swift sources)
│   ├── Info.plist            # App Info.plist
│   ├── PrivacyInfo.xcprivacy # Privacy manifest
│   ├── NaarsCarsTests/       # Unit tests (classic Xcode group)
│   └── NaarsCarsUITests/     # UI automation (filesystem-synced)
│
├── database/                 # Legacy numeric SQL migrations — frozen; do not add to or modify
├── supabase/                 # Supabase-managed migrations (supabase/migrations/) + edge functions (supabase/functions/)
├── PRDs/                     # Product Requirements Documents (per feature)
├── Tasks/                    # Historical task breakdowns (some predate the current architecture)
├── QA/                       # QA framework, checkpoint scripts, flow catalog
├── Docs/                     # Audit reports, debug runbooks, plans, superpowers specs; Docs/archive/ = retired notes
├── Legal/                    # Privacy Policy, Terms of Service, FAQ
└── scripts/                  # Pre-commit hooks and validation helpers
```

**Database migrations:** new migrations go in `supabase/migrations/` (Supabase-managed; `YYYYMMDD_XXXX_description.sql`, or the 14-digit timestamp form the Supabase MCP `apply_migration` tool creates). `database/` is legacy and frozen. Any migration applied through the Supabase MCP or dashboard **must be committed to `supabase/migrations/` in the same change** — the live database had 102 migrations the repo lacked until they were exported on 2026-10-05.

---

## 🚀 Building Locally

### Prerequisites
- macOS 15.6+ (required by Xcode 26)
- Xcode 26.6
- Supabase project credentials (URL + publishable key)
- Apple Developer account (for signing real devices / TestFlight)

### Secrets Setup (required — the build will fail without it)

1. Copy `NaarsCars/Core/Utilities/Secrets.swift.template` → `NaarsCars/Core/Utilities/Secrets.swift`.
2. Run `swift NaarsCars/Scripts/obfuscate.swift` to generate obfuscated byte arrays for the Supabase URL and the publishable key. The value to obfuscate is the publishable key (`sb_publishable_...`) from Supabase → Project Settings → API keys. The property is still named `supabaseAnonKey` for source compatibility.
3. Paste the generated arrays into `Secrets.swift`.

Legacy JWT keys (anon and service_role) stay enabled until a build using the publishable key has shipped; the live App Store build still uses the legacy anon key.

`Secrets.swift` is gitignored, and `scripts/pre-commit-secrets-check.sh` blocks commits that contain it (or `GoogleService-Info.plist`, or any `*.p8`/`*.p12`/`*.key`). Install the hook with `scripts/install-hooks.sh`, which writes a thin `.git/hooks/pre-commit` wrapper that runs the script from the repo.

### Build & Test

The Xcode project is at `NaarsCars/NaarsCars.xcodeproj`, scheme `NaarsCars`. The full set of build/test invocations lives in [`CLAUDE.md`](./CLAUDE.md#build-and-test-commands); the common ones:

```bash
# Build (Debug, simulator)
xcodebuild -project NaarsCars/NaarsCars.xcodeproj -scheme NaarsCars \
  -sdk iphonesimulator -configuration Debug build

# Run all unit tests
xcodebuild test -project NaarsCars/NaarsCars.xcodeproj -scheme NaarsCars \
  -sdk iphonesimulator -destination 'platform=iOS Simulator,name=iPhone 16'

# Clear Xcode caches
scripts/CLEAR-XCODE-CACHE.sh
```

CI runs in `.github/workflows/ios-ci.yml` on a GitHub-hosted `macos-26` runner: it builds the app and runs the unit tests on every pull request (and on manual dispatch), using placeholder secrets unless the repository secrets are set. UI tests do not run in CI. Local checks are the git pre-commit hook (`scripts/pre-commit-*`, installed by `scripts/install-hooks.sh`) plus a Claude Code `PostToolUse` hook (`scripts/verify-xcode-file-sync.sh`, wired in `.claude/settings.json`) that warns when a newly written `.swift` file is not referenced in `project.pbxproj`.

### Adding Swift Files

All Swift sources (`NaarsCars/App`, `Core`, `Features`, `UI`, and `NaarsCars/NaarsCarsTests`) live in classic Xcode groups, so a new `.swift` file must be referenced in `NaarsCars/NaarsCars.xcodeproj/project.pbxproj` — add it through Xcode, or convert the group with Xcode 16+'s "Convert to Folder" — or the build silently ignores it. Only two filesystem-synced roots (`PBXFileSystemSynchronizedRootGroup`) exist: `NaarsCars/NaarsCars/` (asset catalog and entitlements only — do not put Swift there) and `NaarsCars/NaarsCarsUITests/`.

---

## 📖 Authoritative Documentation

Read these before making non-trivial changes:

| Document | Purpose |
|---|---|
| [`CLAUDE.md`](./CLAUDE.md) | **Operating manual.** Architecture rules, fragile-system invariants, App Store gates, canonical entry points. |
| [`AGENTS.md`](./AGENTS.md) | Condensed agent-facing version of CLAUDE.md (for Codex and similar tools). |
| [`SECURITY.md`](./SECURITY.md) | RLS policies, security requirements, compliance details. |
| [`MESSAGING-REVIEW-AND-PLAN.md`](./MESSAGING-REVIEW-AND-PLAN.md) | Deep architectural review of the messaging/realtime system. |
| [`Docs/superpowers/specs/2026-03-30-push-notify-pull-hydrate-design.md`](./Docs/superpowers/specs/2026-03-30-push-notify-pull-hydrate-design.md) | Push-notify, pull-hydrate architecture spec — the design behind `RefreshCoordinator`. |
| [`PRDs/`](./PRDs/) | Feature-level product requirements (one per feature). |
| [`Legal/`](./Legal/) | Privacy Policy, Terms of Service, FAQ. |
| [`Legal/PRIVACY-DISCLOSURES.md`](./Legal/PRIVACY-DISCLOSURES.md) | Data-collection disclosures for App Store privacy labels. |

Historical planning artifacts from earlier development phases (`*-PLAN.md`, `*-SUMMARY.md`, `*-CHECKLIST.md`, and similar) have been moved out of the repo root into `Docs/archive/root-planning/`; edge-function setup notes are in `Docs/archive/edge-function-setup/` and the VisualBrain experiment in `Docs/archive/VisualBrain/`. Nothing under `Docs/archive/` is authoritative.

---

## 🔒 Security & Privacy

- **RLS is the security boundary.** All data access goes through Supabase Row Level Security policies. Client-side filtering is not security. See `SECURITY.md`.
- **Secrets never leave local machines.** `Secrets.swift`, `GoogleService-Info.plist`, `*.p8`, `*.p12`, and `*.key` are gitignored and blocked by the pre-commit hook (`scripts/pre-commit-secrets-check.sh`). Supabase CLI scratch state (`supabase/.temp/`) is gitignored too.
- **Privacy manifest coverage is mandatory.** Firebase SDKs require required-reason API declarations in the compiled IPA; Apple will reject builds that omit them. See `NaarsCars/PrivacyInfo.xcprivacy` and `Legal/PRIVACY-DISCLOSURES.md`.
- **Account deletion, Sign in with Apple, and moderation/blocking/reporting** must remain functional on every release — they are App Store non-negotiables (see CLAUDE.md → App Store Compliance Rules).

---

## 📜 License

Private — all rights reserved.
