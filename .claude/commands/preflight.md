---
description: Full build, unit test run, warnings summary, and a diff check for signing, entitlements, privacy, and Supabase migration changes
---

Run the pre-push preflight for the current branch. Report only; do not fix anything inside this command.

1. **Changed files:** `git fetch origin main --quiet; git diff --name-only origin/main...HEAD; git status --porcelain`.
2. **Build + warnings.** If the `xcode` MCP tools are available: `XcodeListWindows` → `BuildProject` (`scheme: "NaarsCars"`) → `GetBuildLog` with `severity: "error"`, then `"warning"`. Otherwise (Xcode closed, preferred on this machine):
   `xcodebuild -project NaarsCars/NaarsCars.xcodeproj -scheme NaarsCars -sdk iphonesimulator -configuration Debug -derivedDataPath build/DerivedData build 2>&1 | grep -E 'error:|warning:' | sort | uniq -c | sort -rn`
   Record error count, total warning count, and the warnings located in files changed on this branch.
3. **Unit tests** (UI tests only if the user asked):
   `xcodebuild test -project NaarsCars/NaarsCars.xcodeproj -scheme NaarsCars -destination 'platform=iOS Simulator,name=iPhone 16' -skip-testing:NaarsCarsUITests -parallel-testing-enabled NO -maximum-concurrent-test-simulator-destinations 1 -derivedDataPath build/DerivedData -resultBundlePath build/Preflight.xcresult -quiet`
   then `xcrun xcresulttool get test-results summary --path build/Preflight.xcresult`. Record passed / failed / skipped and name each failing test. Note that 11 unit test files are not attached to the target (CLAUDE.md Audit Notes) and did not run. Finish with `xcrun simctl shutdown all`.
4. **Sensitive-area scan** of the changed-file list. Flag any match:
   - signing / entitlements: `*.entitlements`, `*.mobileprovision`, `*.p8`, `*.p12`, `*.cer`, `ExportOptions*.plist`; and in `project.pbxproj` any changed line containing `CODE_SIGN`, `DEVELOPMENT_TEAM`, `PROVISIONING_PROFILE`, `PRODUCT_BUNDLE_IDENTIFIER`, `IPHONEOS_DEPLOYMENT_TARGET`, `SWIFT_VERSION` (`git diff origin/main...HEAD -- NaarsCars/NaarsCars.xcodeproj/project.pbxproj`)
   - Info.plist and privacy: `Info.plist`, `PrivacyInfo.xcprivacy`, `GoogleService-Info.plist`
   - Supabase: `supabase/migrations/**`, `database/**`, `supabase/functions/**`
   - secrets: `Secrets.swift`, `.env*`
   If `supabase/functions/**` or the Swift notification type enum changed, run `scripts/validate-notification-types.sh` and include its result.
5. **Report:**
   - Build: pass / fail, errors, total warnings, new warnings in changed files (list)
   - Tests: passed / failed / skipped, failing test names
   - Sensitive paths touched: list, or "none"
   - Verdict: READY / NOT READY with the single most important reason
