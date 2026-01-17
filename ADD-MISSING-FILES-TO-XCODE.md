# Add Missing Files to Xcode Project

## Problem
These files exist on disk but are NOT being compiled by Xcode:
- `LeaderboardViewModel.swift`
- `NavigationCoordinator.swift`
- `AppleSignInViewModel.swift`
- `BiometricPreferences.swift`
- `InviteService.swift`
- `LeaderboardService.swift`
- `LeaderboardRow.swift`

## Root Cause
Even though the project uses `fileSystemSynchronizedGroups`, Xcode is not automatically including these files in the build. They need to be **manually added to the Xcode project**.

## Solution: Manual Addition in Xcode

**CRITICAL**: You must add these files manually in Xcode UI. The `fileSystemSynchronizedGroups` feature is not working reliably for these files.

### Steps:

1. **Open Xcode**
2. **For each file below, follow these steps:**
   - Right-click on the **correct folder** in Project Navigator
   - Select **"Add Files to 'NaarsCars'..."**
   - Navigate to the file location
   - **IMPORTANT Settings:**
     - ✅ **Copy items if needed**: **UNCHECKED** (files already exist)
     - ✅ **Add to targets: NaarsCars**: **CHECKED** (this is critical!)
     - ✅ **Create groups**: **CHECKED**
   - Click **"Add"**

### Files to Add (In Order):

1. **Core/Utilities/BiometricPreferences.swift**
   - Right-click on `Core` → `Utilities` folder
   - Add `BiometricPreferences.swift`

2. **Core/Services/InviteService.swift**
   - Right-click on `Core` → `Services` folder
   - Add `InviteService.swift`

3. **Core/Services/LeaderboardService.swift**
   - Right-click on `Core` → `Services` folder  
   - Add `LeaderboardService.swift`

4. **App/NavigationCoordinator.swift**
   - Right-click on `App` folder
   - Add `NavigationCoordinator.swift`

5. **Features/Authentication/ViewModels/AppleSignInViewModel.swift**
   - Right-click on `Features` → `Authentication` → `ViewModels` folder
   - Add `AppleSignInViewModel.swift`

6. **Features/Leaderboards/ViewModels/LeaderboardViewModel.swift**
   - Right-click on `Features` → `Leaderboards` → `ViewModels` folder
   - Add `LeaderboardViewModel.swift`

7. **Features/Leaderboards/Views/LeaderboardRow.swift**
   - Right-click on `Features` → `Leaderboards` → `Views` folder
   - Add `LeaderboardRow.swift`

### After Adding All Files:

1. **Product → Clean Build Folder** (`Shift+Cmd+K`)
2. **Close Xcode completely** (`Cmd+Q`)
3. **Reopen Xcode**
4. **Build again** (`Cmd+B`)

## Verification

After adding files, verify they're in the project:
1. Select a file in Project Navigator
2. Open **File Inspector** (right panel)
3. Under **Target Membership**, ensure **NaarsCars** is checked

If any file shows "NaarsCars" unchecked, check it manually.

## Expected Result

After adding all files, the build should succeed without "Cannot find X in scope" errors.


