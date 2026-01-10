# Critical: Files Need to be Manually Added to Xcode

## Problem
All required files exist on disk, but Xcode's `fileSystemSynchronizedGroups` is not automatically including them in the build. This causes "Cannot find X in scope" compilation errors.

## Solution: Manually Add Files to Xcode Project

Since `fileSystemSynchronizedGroups` isn't working reliably, these files must be **manually added to the Xcode project**.

### Steps:

1. **Open Xcode**

2. **For each missing file, add it to the project:**
   - Right-click on the appropriate folder in Xcode's Project Navigator
   - Select "Add Files to 'NaarsCars'..."
   - Navigate to the file
   - **IMPORTANT:** 
     - ✅ Check "Copy items if needed" = **UNCHECKED**
     - ✅ Check "Add to targets: NaarsCars" = **CHECKED**
     - ✅ Check "Create groups" = **CHECKED**

3. **Files to add (in order):**

   **Core/Utilities/**
   - `BiometricPreferences.swift`*Core/Services/**
   - `InviteService.swift`
   - `LeaderboardService.swift`

   **App/**
   - `NavigationCoordinator.swift`

   **Features/Authentication/ViewModels/**
   - `AppleSignInViewModel.swift`

   **Features/Leaderboards/ViewModels/**
   - `LeaderboardViewModel.swift`

   **Features/Leaderboards/Views/**
   - `LeaderboardRow.swift`

4. **After adding files:**
   - Product → Clean Build Folder (`Shift+Cmd+K`)
   - Build again

## Alternative: Use Python Script to Add Files

If you prefer automation, there's a script at:
- `NaarsCars/Scriptsdd-models-to-xcode.py`

You can modify it to add these specific files.
