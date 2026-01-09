# Tasks: Crash Reporting

Based on `prd-crash-reporting.md`

## Relevant Files

### Source Files
- `Core/Services/CrashReportingService.swift` - Crash and analytics
- `App/AppDelegate.swift` - Crash reporting setup

### Test Files
- `NaarsCarsTests/Core/Services/CrashReportingServiceTests.swift`

## Notes

- Uses Firebase Crashlytics
- Requires Firebase project setup
- Non-fatal errors also tracked
- 🧪 items are QA tasks | 🔒 CHECKPOINT items are mandatory gates

## Instructions for Completing Tasks

**IMPORTANT:** As you complete each task, you must check it off in this markdown file by changing `- [ ]` to `- [x]`. This helps track progress and ensures you don't skip any steps.

**BLOCKING:** Tasks marked with ⛔ block other features and must be completed first.

**QA RULES:**
1. Complete 🧪 QA tasks immediately after their related implementation
2. Do NOT skip past 🔒 CHECKPOINT markers until tests pass
3. Run: `./QA/Scripts/checkpoint.sh <checkpoint-id>` at each checkpoint
4. If checkpoint fails, fix issues before continuing

Example:
- `- [ ] 1.1 Read file` → `- [x] 1.1 Read file` (after completing)

Update the file after completing each sub-task, not just after completing an entire parent task.

## Tasks

- [ ] 0.0 Create feature branch: `git checkout -b feature/crash-reporting`

- [ ] 1.0 Set up Firebase project
  - [ ] 1.1 Create Firebase project at console.firebase.google.com
  - [ ] 1.2 Add iOS app with bundle ID
  - [ ] 1.3 Download GoogleService-Info.plist
  - [ ] 1.4 Add to Xcode project (do NOT commit to git)
  - [ ] 1.5 Add GoogleService-Info.plist to .gitignore

- [ ] 2.0 Add Firebase SDK
  - [ ] 2.1 Add Firebase Crashlytics via SPM
  - [ ] 2.2 URL: https://github.com/firebase/firebase-ios-sdk
  - [ ] 2.3 Select FirebaseCrashlytics package
  - [ ] 2.4 Add dSYM upload script to build phases

- [ ] 3.0 Implement CrashReportingService
  - [ ] 3.1 Create CrashReportingService.swift
  - [ ] 3.2 Implement configure() to initialize Firebase
  - [ ] 3.3 Call FirebaseApp.configure() in AppDelegate
  - [ ] 3.4 Implement setUser(userId:) for user identification
  - [ ] 3.5 Implement logError(error:, context:) for non-fatal errors
  - [ ] 3.6 Implement log(message:) for breadcrumbs
  - [ ] 3.7 🧪 Write CrashReportingServiceTests.testLogError

### 🔒 CHECKPOINT: QA-CRASH-001
> Run: `./QA/Scripts/checkpoint.sh crash-001`
> Guide: QA/CHECKPOINT-GUIDE.md
> Verify: Firebase configured, service tests pass
> Must pass before continuing

- [ ] 4.0 Integrate throughout app
  - [ ] 4.1 Set user ID on login
  - [ ] 4.2 Clear user ID on logout
  - [ ] 4.3 Log non-fatal errors from services
  - [ ] 4.4 Add breadcrumbs for key actions

- [ ] 5.0 Test crash reporting
  - [ ] 5.1 Force a test crash
  - [ ] 5.2 Verify crash appears in Firebase Console
  - [ ] 5.3 Verify stack trace is symbolicated
  - [ ] 5.4 Test non-fatal error logging
  - [ ] 5.5 Commit: "feat: implement crash reporting"

### 🔒 CHECKPOINT: QA-CRASH-FINAL
> Run: `./QA/Scripts/checkpoint.sh crash-final`
> Guide: QA/CHECKPOINT-GUIDE.md
> Crash reporting tests must pass
