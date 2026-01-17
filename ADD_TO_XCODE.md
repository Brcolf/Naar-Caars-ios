# Add NavigationCoordinator.swift to Xcode Project

## Issue

The file `NavigationCoordinator.swift` exists but Xcode can't find it, causing compilation errors:
- "Cannot find 'NavigationCoordinator' in scope"

## Solution: Add File to Xcode Project

The file needs to be added to the Xcode project target.

### Method 1: Add via Xcode (Recommended)

1. **Open Xcode**
2. **Right-click** on the `App` folder in the Project Navigator (left sidebar)
3. Select **"Add Files to NaarsCars..."**
4. Navigate to: `NaarsCars/App/NavigationCoordinator.swift`
5. Make sure **"NaarsCars"** target is checked
6. Click **"Add"**

### Method 2: Drag & Drop

1. **Open Finder** and navigate to: `/Users/bcolf/.cursor/worktrees/naars-cars-ios/vcs/NaarsCars/App/`
2. **Drag** `NavigationCoordinator.swift` into Xcode's Project Navigator
3. Drop it in the `App` folder
4. In the dialog, make sure:
   - **"Copy items if needed"** is **UNCHECKED** (file already exists)
   - **"Add to targets: NaarsCars"** is **CHECKED**
5. Click **"Finish"**

### Method 3: Verify File is in Target

If the file is already in the project but still not compiling:

1. Select `NavigationCoordinator.swift` in the Project Navigator
2. Open **File Inspector** (right sidebar, first tab)
3. Under **"Target Membership"**, make sure **"NaarsCars"** is **CHECKED**
4. If unchecked, check it

### Method 4: Clean Build Folder

Sometimes Xcode needs a clean build:

1. In Xcode menu: **Product** → **Clean Build Folder** (Shift+Cmd+K)
2. Try building again (Cmd+B)

---

## Verify It Works

After adding the file:

1. Build the project (Cmd+B)
2. All compilation errors should disappear
3. `NavigationCoordinator` should be accessible in all files

---

## File Location

**File Path**: `NaarsCars/App/NavigationCoordinator.swift`

**Absolute Path**: `/Users/bcolf/.cursor/worktrees/naars-cars-ios/vcs/NaarsCars/App/NavigationCoordinator.swift`

---

## Quick Check

Run this to verify the file exists:
```bash
ls -la /Users/bcolf/.cursor/worktrees/naars-cars-ios/vcs/NaarsCars/App/NavigationCoordinator.swift
```

If this shows the file, it exists and just needs to be added to the Xcode project.


