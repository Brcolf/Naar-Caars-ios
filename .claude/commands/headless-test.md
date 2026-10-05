---
description: Run unit tests on one headless simulator with Xcode closed (lightest lane on this Mac); optional test class or method filter
argument-hint: [NaarsCarsTests/ClassName[/testMethod]]
---

Run the unit tests in the lightest possible way for this resource-constrained Mac. Xcode does not need to be open; do not open the Simulator app.

1. Build the filter: if `$ARGUMENTS` is non-empty use `-only-testing:$ARGUMENTS`, otherwise use `-skip-testing:NaarsCarsUITests`.
2. Run:
   `xcodebuild test -project NaarsCars/NaarsCars.xcodeproj -scheme NaarsCars -destination 'platform=iOS Simulator,name=iPhone 16' <filter> -parallel-testing-enabled NO -maximum-concurrent-test-simulator-destinations 1 -derivedDataPath build/DerivedData -resultBundlePath build/HeadlessTests.xcresult -quiet 2>&1 | tail -40`
   (delete `build/HeadlessTests.xcresult` first if it exists).
3. Summarize with `xcrun xcresulttool get test-results summary --path build/HeadlessTests.xcresult`; for failures, `xcrun xcresulttool get test-results tests --path build/HeadlessTests.xcresult` and quote the failing assertion.
4. `xcrun simctl shutdown all` so the simulator releases memory.
5. Report passed / failed / skipped, each failing test with its message, and a reminder that 11 unit test files are not attached to the target and were not run (see CLAUDE.md Audit Notes).
