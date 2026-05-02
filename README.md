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
| Minimum iOS | 17.0 |
| Tooling | Xcode 16+ |

**Dependencies (SPM, Xcode-managed):** `supabase-swift` v2.5.1+, `firebase-ios-sdk` v12.8.0+, `PhoneNumberKit` v4.0.0+.

---

## 📁 Repository Layout

```
naars-cars-ios/
├── NaarsCars/                # Xcode project root
│   ├── App/                  # AppDelegate, NaarsCarsApp, MainTabView, NavigationCoordinator
│   ├── Core/                 # Services, Storage, Models, Protocols, Utilities
│   ├── Features/             # Feature modules (Messaging, Rides, Favors, TownHall, ...)
│   ├── UI/                   # Reusable components (Buttons, Cards, Map, Messaging, ...)
│   ├── Resources/            # Assets, Localizable.xcstrings, Info.plist
│   ├── NaarsCarsTests/       # Unit tests
│   └── NaarsCarsUITests/     # UI automation
│
├── database/                 # Legacy numeric SQL migrations (do not modify in place)
├── supabase/                 # Supabase-managed migrations + edge functions
├── PRDs/                     # Product Requirements Documents (per feature)
├── Tasks/                    # Historical task breakdowns (some predate the current architecture)
├── QA/                       # QA framework, checkpoint scripts, flow catalog
├── Docs/                     # Audit reports, debug runbooks, plans, superpowers specs
├── Legal/                    # Privacy Policy, Terms of Service, FAQ
└── scripts/                  # Pre-commit hooks and validation helpers
```

---

## 🚀 Building Locally

### Prerequisites
- macOS Sonoma 14.0+
- Xcode 16+
- Supabase project credentials (URL + anon key)
- Apple Developer account (for signing real devices / TestFlight)

### Secrets Setup (required — the build will fail without it)

1. Copy `NaarsCars/Core/Utilities/Secrets.swift.template` → `NaarsCars/Core/Utilities/Secrets.swift`.
2. Run `swift NaarsCars/Scripts/obfuscate.swift` to generate obfuscated byte arrays for the Supabase URL and anon key.
3. Paste the generated arrays into `Secrets.swift`.

`Secrets.swift` is gitignored, and `scripts/pre-commit-secrets-check.sh` blocks commits that contain it (or `GoogleService-Info.plist`, or any `*.p8`/`*.p12`/`*.key`).

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

There is **no CI** — checks are pre-commit hooks (`scripts/pre-commit-*`) plus a Claude Code `PostToolUse` hook (`scripts/verify-xcode-file-sync.sh`). Build and test verification is manual.

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

Root-level `*-PLAN.md`, `*-SUMMARY.md`, `*-CHECKLIST.md`, and similar files are historical planning artifacts from earlier development phases — do not treat as authoritative.

---

## 🔒 Security & Privacy

- **RLS is the security boundary.** All data access goes through Supabase Row Level Security policies. Client-side filtering is not security. See `SECURITY.md`.
- **Secrets never leave local machines.** `Secrets.swift`, `GoogleService-Info.plist`, `*.p8`, `*.p12`, and `*.key` are gitignored and blocked by the pre-commit hook.
- **Privacy manifest coverage is mandatory.** Firebase SDKs require required-reason API declarations in the compiled IPA; Apple will reject builds that omit them. See `NaarsCars/PrivacyInfo.xcprivacy` and `Legal/PRIVACY-DISCLOSURES.md`.
- **Account deletion, Sign in with Apple, and moderation/blocking/reporting** must remain functional on every release — they are App Store non-negotiables (see CLAUDE.md → App Store Compliance Rules).

---

## 📜 License

Private — all rights reserved.
