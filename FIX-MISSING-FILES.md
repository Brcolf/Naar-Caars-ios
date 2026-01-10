# Fix: Cannot Find Files in Scope

## Problem
The compiler cannot find these files even though they exist on disk:
- `LeaderboardViewModel.swift`
- `NavigationCoordinator.swift`
- `AppleSignInViewModel.swift`
- `BiometricPreferences.swift`
- `InviteService.swift` (and its types: `InviteCodeWithInvitee`, `InviteStats`)

## Root Cause
These files exist but aren't being compiled by Xcode. Even though the project uses `fileSystemSynchronizedGroups`, Xcode may not have refreshed its file list.

## Solution

### Option 1: Refresh Xcode File List (Recommended)

1. **Close Xcode completely** (`Cmd+Q`)

2. **Clean DerivedData:**
   ```bash
   rm -rf ~/Library/Developer/Xcode/DerivedData/NaarsCars-*
   ```

3. **Reopen Xcode**

4. **Product → Clean Build Folder** (`Shift+Cmd+K`)

5. **Close and reopen Xcode again**

6. **Try building**

### Option 2: Verify Files Are in Correct Location

All files should be under `NaarsCars/` directory:
- ✅ `NaarsCars/Features/Leaderboards/ViewModels/LeaderboardViewModel.swift`
- ✅ `NaarsCars/App/NavigationCoordinator.swift`
- ✅ `NaarsCars/Features/Authentication/ViewModels/AppleSignInViewModel.swift`
- ✅ `NaarsCars/Core/Utilities/BiometricPreferences.swift`
- ✅ `NaarsCars/Core/Services/InviteService.swift`

### Option 3: Manual File Addition (If Above Doesn't Work)

If `fileSystemSynchronizedGroups` isn't working:

1. In Xcode, right-click on the appropriate group folder
2. Select "Add Files to 'NaarsCars'..."
3. Navigate to each file and add it
4. Ensure "Copy items if needed" is **UNCHECKED**
5. Ensure "Add to targets: NaarsCars" is **CHECKED**

## Verification

After applying the fix, verify by building:
```bash
xcodebuild -project NaarsCars/NaarsCars.xcodeproj -scheme NaarsCars -sdk iphonesimulator build
```

All "Cannot find X in scope" errors should be resolved.

## Files That Exist and Should Work

All these files exist and have correct structure:
- ✅ `LeaderboardViewModel.swift` - Has `@MainActor` and `ObservableObject`
- ✅ `NavigationCoordinator.swift` - Has `@MainActor` and `ObservableObject`
- ✅ `AppleSignInViewModel.swift` - Has `@MainActor` and `ObservableObject`
- ✅ `BiometricPreferences.swift` - Has `final class` with `static let shared`
- ✅ `InviteService.swift` - Has types `InviteCodeWithInvitee` and `InviteStats` defined at bottom

These should all compile once Xcode recognizes them.

