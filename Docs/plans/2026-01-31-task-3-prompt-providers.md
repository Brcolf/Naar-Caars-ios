# Task 3 Prompt Providers Implementation Plan

> **For Claude:** REQUIRED SUB-SKILL: Use superpowers:executing-plans to implement this plan task-by-task.

**Goal:** Add Task 3 prompt provider source and test files to the Xcode project, verify build, and commit the change.

**Architecture:** Update `project.pbxproj` by adding file references and build phase entries for the new source and test files, matching existing group structure and target membership.

**Tech Stack:** Xcode project file (`project.pbxproj`), Swift.

---

### Task 1: Add prompt provider source files to app target

**Files:**
- Modify: `NaarsCars/NaarsCars.xcodeproj/project.pbxproj`

**Step 1: Locate the Core/Services group and target build phase**
Run: `rg "Core/Services" "NaarsCars/NaarsCars.xcodeproj/project.pbxproj"`
Expected: Existing group references for Core services files.

**Step 2: Add file references for new source files**
Add file references for:
- `NaarsCars/Core/Services/CompletionPromptProvider.swift`
- `NaarsCars/Core/Services/ReviewPromptProvider.swift`
- `NaarsCars/Core/Services/PromptSideEffects.swift`

**Step 3: Add build phase entries to app target**
Add PBXBuildFile entries and include them in the `PBXSourcesBuildPhase` for the app target.

**Step 4: Verify no duplicate entries**
Run: `rg "CompletionPromptProvider.swift|ReviewPromptProvider.swift|PromptSideEffects.swift" "NaarsCars/NaarsCars.xcodeproj/project.pbxproj"`
Expected: Each file appears once in file references and once in build phase.

### Task 2: Add prompt provider test files to test target

**Files:**
- Modify: `NaarsCars/NaarsCars.xcodeproj/project.pbxproj`

**Step 1: Locate the tests group and test target build phase**
Run: `rg "NaarsCarsTests" "NaarsCars/NaarsCars.xcodeproj/project.pbxproj"`
Expected: Existing test group references and build phase.

**Step 2: Add file references for new test files**
Add file references for:
- `NaarsCars/NaarsCarsTests/Core/Services/CompletionPromptProviderTests.swift`
- `NaarsCars/NaarsCarsTests/Core/Services/ReviewPromptProviderTests.swift`

**Step 3: Add build phase entries to test target**
Add PBXBuildFile entries and include them in the `PBXSourcesBuildPhase` for the test target.

**Step 4: Verify no duplicate entries**
Run: `rg "CompletionPromptProviderTests.swift|ReviewPromptProviderTests.swift" "NaarsCars/NaarsCars.xcodeproj/project.pbxproj"`
Expected: Each file appears once in file references and once in build phase.

### Task 3: Build verification

**Files:**
- None

**Step 1: Run focused build**
Run: `xcodebuild build -scheme "NaarsCars" -project "NaarsCars/NaarsCars.xcodeproj" -destination "platform=iOS Simulator,name=iPhone 15,OS=latest"`
Expected: BUILD SUCCEEDED.

### Task 4: Commit changes

**Files:**
- Modify: `NaarsCars/NaarsCars.xcodeproj/project.pbxproj`

**Step 1: Stage the Xcode project file**
Run: `git add NaarsCars/NaarsCars.xcodeproj/project.pbxproj`
Expected: File staged.

**Step 2: Commit**
Run: `git commit -m "chore: add prompt provider files to project"`
Expected: Commit created.
