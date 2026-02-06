# Step-by-Step Guide: Task 1.0 - Xcode Project Setup

This guide walks you through setting up the Xcode project, folder structure, and git repository for Naar's Cars iOS app.

**Estimated Time:** 15-20 minutes  
**Prerequisites:** Xcode installed (latest version recommended)

---

## Part 1: Create Xcode Project (Tasks 1.1-1.5)

### Step 1.1: Open Xcode and Create New Project

1. Open **Xcode**
2. From the welcome screen, click **"Create a new Xcode project"**
   - Or go to **File → New → Project** (⌘⇧N)

### Step 1.2: Select Project Template

1. In the template chooser, select **"iOS"** tab (if not already selected)
2. Choose **"App"** template
3. Click **"Next"**

### Step 1.3: Configure Project Settings

Fill in the project details:

- **Product Name:** `NaarsCars`
- **Team:** Select your development team (or leave as "None" for now)
- **Organization Identifier:** `com.naarscars` (or use your own, e.g., `com.yourname.naarscars`)
- **Bundle Identifier:** Will auto-populate as `com.naarscars.NaarsCars`
- **Interface:** Select **"SwiftUI"**
- **Language:** Select **"Swift"**
- **Storage:** Select **"None"** (we'll use Supabase for storage)
- **Include Tests:** ✅ **Check this box** (important!)

Click **"Next"**

### Step 1.4: Choose Save Location

1. Navigate to your project directory: `/Users/bcolf/Documents/naars-cars-ios`
2. **Important:** Do NOT check "Create Git repository" (we'll do this manually)
3. Click **"Create"**

### Step 1.5: Set Minimum Deployment Target

1. In the Project Navigator, select the **"NaarsCars"** project (blue icon at top)
2. Select the **"NaarsCars"** target
3. Go to **"General"** tab
4. Under **"Deployment Info"**, set **"iOS"** to **"17.0"**
5. Verify **"SwiftUI"** is selected for Interface

---

## Part 2: Git Setup (Tasks 1.6-1.7)

### Step 1.6: Initialize Git Repository

Open Terminal and navigate to your project:

```bash
cd /Users/bcolf/Documents/naars-cars-ios/NaarsCars
```

Initialize git (if not already initialized):

```bash
git init
```

Create `.gitignore` file for iOS projects:

```bash
cat > .gitignore << 'EOF'
# Xcode
#
# gitignore contributors: remember to update Global/Xcode.gitignore, Objective-C.gitignore & Swift.gitignore

## User settings
xcuserdata/

## compatibility with Xcode 8 and earlier (ignoring not required starting Xcode 9)
*.xcscmblueprint
*.xccheckout

## compatibility with Xcode 3 and earlier (ignoring not required starting Xcode 4)
build/
DerivedData/
*.moved-aside
*.pbxuser
!default.pbxuser
*.mode1v3
!default.mode1v3
*.mode2v3
!default.mode2v3
*.perspectivev3
!default.perspectivev3

## Obj-C/Swift specific
*.hmap

## App packaging
*.ipa
*.dSYM.zip
*.dSYM

## Playgrounds
timeline.xctimeline
playground.xcworkspace

# Swift Package Manager
#
# Add this line if you want to avoid checking in source code from Swift Package Manager dependencies.
# Packages/
# Package.pins
# Package.resolved
# *.xcodeproj
#
# Xcode automatically generates this directory with a .xcworkspacedata file and xcuserdata
# hence it is not needed unless you have added a package configuration file to your project
# .swiftpm

.build/

# CocoaPods
#
# We recommend against adding the Pods directory to your .gitignore. However
# you should judge for yourself, the pros and cons are mentioned at:
# https://guides.cocoapods.org/using/using-cocoapods.html#should-i-check-the-pods-directory-into-source-control
#
# Pods/
#
# Add this line if you want to avoid checking in source code from the Xcode workspace
# *.xcworkspace

# Carthage
#
# Add this line if you want to avoid checking in source code from Carthage dependencies.
# Carthage/Checkouts

Carthage/Build/

# Accio dependency management
Dependencies/
.accio/

# fastlane
#
# It is recommended to not store the screenshots in the git repo.
# Instead, use fastlane to re-generate the screenshots whenever they are needed.
# For more information about the recommended setup visit:
# https://docs.fastlane.tools/best-practices/source-control/#source-control

fastlane/report.xml
fastlane/Preview.html
fastlane/screenshots/**/*.png
fastlane/test_output

# Code Injection
#
# After new code Injection tools there's a generated folder /iOSInjectionProject
# https://github.com/johnno1962/injectionforxcode

iOSInjectionProject/

# Secrets and credentials (DO NOT COMMIT)
Secrets.swift
GoogleService-Info.plist
*.p8  # APNs key files

# Supabase credentials
.env
supabase/.env
EOF
```

Add and commit initial project:

```bash
git add .
git commit -m "Initial Xcode project setup"
```

### Step 1.7: Create Feature Branch

```bash
git checkout -b feature/foundation-architecture
```

Verify you're on the feature branch:

```bash
git branch
# Should show: * feature/foundation-architecture
```

---

## Part 3: Create Folder Structure (Tasks 1.8-1.12)

### Step 1.8: Create Main Folder Groups

In Xcode Project Navigator (left sidebar):

1. Right-click on **"NaarsCars"** (the blue project icon)
2. Select **"New Group"**
3. Name it **"App"**
4. Repeat to create these groups:
   - **"Features"**
   - **"Core"**
   - **"UI"**
   - **"Resources"**

**Note:** In Xcode, "Groups" are virtual folders. We'll create the actual folder structure next.

### Step 1.9: Create Features Subfolders

1. Right-click on **"Features"** group
2. Select **"New Group"**
3. Create these subfolders:
   - **"Authentication"**
   - **"Rides"**
   - **"Favors"**
   - **"Messaging"**
   - **"Notifications"**
   - **"Profile"**
   - **"TownHall"**
   - **"Leaderboards"**
   - **"Admin"**

### Step 1.10: Create Core Subfolders

1. Right-click on **"Core"** group
2. Select **"New Group"**
3. Create these subfolders:
   - **"Services"**
   - **"Models"**
   - **"Extensions"**
   - **"Utilities"**

### Step 1.11: Create UI Subfolders

1. Right-click on **"UI"** group
2. Select **"New Group"**
3. Create these subfolders:
   - **"Components"**
   - **"Styles"**
   - **"Modifiers"**

### Step 1.12: Create UI/Components Subfolders

1. Right-click on **"UI/Components"** group
2. Select **"New Group"**
3. Create these subfolders:
   - **"Buttons"**
   - **"Cards"**
   - **"Inputs"**
   - **"Feedback"**
   - **"Common"**
   - **"Messaging"**

---

## Part 4: Organize Files and Create Test Structure (Tasks 1.13-1.16)

### Step 1.13: Move ContentView.swift to App Folder

1. In Project Navigator, find **"ContentView.swift"**
2. Drag it into the **"App"** group
3. When prompted, choose **"Move"** (not "Copy")

### Step 1.14: Move NaarsCarsApp.swift to App Folder

1. Find **"NaarsCarsApp.swift"** (the main app file)
2. Drag it into the **"App"** group
3. Choose **"Move"**

### Step 1.15: Create Test Folder Structure

1. In Project Navigator, find **"NaarsCarsTests"** group
2. Right-click and create these subfolders:
   - **"Core"** (under NaarsCarsTests)
     - **"Utilities"** (under Core)
     - **"Services"** (under Core)
     - **"Models"** (under Core)
   - **"Features"** (under NaarsCarsTests)

**Note:** You may need to create these as actual folders in Finder if Xcode doesn't allow nested groups easily.

### Step 1.16: Commit Folder Structure

In Terminal:

```bash
cd /Users/bcolf/Documents/naars-cars-ios/NaarsCars

# Verify changes
git status

# Add all changes
git add .

# Commit
git commit -m "Set up project folder structure (Task 1.0)"
```

---

## Verification Checklist

After completing all steps, verify:

- [ ] Xcode project opens without errors
- [ ] Project builds successfully (⌘B)
- [ ] Minimum deployment target is iOS 17.0
- [ ] SwiftUI interface is selected
- [ ] Unit tests target exists (NaarsCarsTests)
- [ ] Git repository is initialized
- [ ] Feature branch `feature/foundation-architecture` is active
- [ ] All folder groups created in Project Navigator:
  - [ ] App
  - [ ] Features (with 9 subfolders)
  - [ ] Core (with 4 subfolders)
  - [ ] UI (with Components, Styles, Modifiers)
  - [ ] UI/Components (with 6 subfolders)
  - [ ] Resources
- [ ] ContentView.swift is in App folder
- [ ] NaarsCarsApp.swift is in App folder
- [ ] Test folder structure created
- [ ] Initial commit completed

---

## Troubleshooting

### Issue: Can't create nested groups in Xcode

**Solution:** Create groups one level at a time. Xcode groups are virtual - the actual folder structure will be created when you add files.

### Issue: Git repository already exists

**Solution:** If git is already initialized, skip Step 1.6 and go directly to Step 1.7 to create the feature branch.

### Issue: Project won't build

**Solution:** 
1. Clean build folder: **Product → Clean Build Folder** (⌘⇧K)
2. Check that SwiftUI is selected as interface
3. Verify iOS 17.0 deployment target

### Issue: Files moved but still showing in wrong location

**Solution:** 
1. Close Xcode
2. In Finder, verify files are in correct folders
3. Reopen Xcode - it should detect the correct structure

---

## Next Steps

After completing Task 1.0:

1. ✅ **Task 1.0 Complete** - Update `Tasks/tasks-foundation-architecture.md` (check off tasks 1.1-1.16)
2. 🚀 **Next:** Task 6.0 - Configure Supabase SDK
   - Add supabase-swift package
   - Create Secrets.swift
   - Set up SupabaseService

---

## Quick Reference Commands

```bash
# Navigate to project
cd /Users/bcolf/Documents/naars-cars-ios/NaarsCars

# Check git status
git status

# Check current branch
git branch

# View commit history
git log --oneline

# If you need to start over (WARNING: deletes uncommitted changes)
git reset --hard HEAD
```

---

**Remember:** 
- ✅ Check off tasks in `Tasks/tasks-foundation-architecture.md` as you complete them
- ✅ Commit frequently with descriptive messages
- ✅ Keep the feature branch active until foundation is complete
- ⚠️ Never commit Secrets.swift or credentials to git


