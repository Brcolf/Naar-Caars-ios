# How to Add Files to Xcode Project

The files `SupabaseService.swift` and `Secrets.swift` exist on disk but need to be added to the Xcode project.

## Method 1: Drag and Drop (Easiest)

1. **Open Xcode** with `NaarsCars.xcodeproj`
2. **Open Finder** and navigate to:
   - `/Users/bcolf/Documents/naars-cars-ios/NaarsCars/Core/Services/SupabaseService.swift`
   - `/Users/bcolf/Documents/naars-cars-ios/NaarsCars/Core/Utilities/Secrets.swift`
3. **Drag both files** from Finder into Xcode's Project Navigator:
   - Drag `SupabaseService.swift` into the **"Core/Services"** group
   - Drag `Secrets.swift` into the **"Core/Utilities"** group
4. When prompted, make sure:
   - ✅ **"Copy items if needed"** is UNCHECKED (files are already in the right place)
   - ✅ **"Add to targets: NaarsCars"** is CHECKED
5. Click **"Finish"**

## Method 2: Add Files via Xcode Menu

1. **In Xcode**, right-click on the **"Core/Services"** group in Project Navigator
2. Select **"Add Files to 'NaarsCars'..."**
3. Navigate to `Core/Services/SupabaseService.swift`
4. Make sure:
   - ✅ **"Copy items if needed"** is UNCHECKED
   - ✅ **"Add to targets: NaarsCars"** is CHECKED
5. Click **"Add"**
6. Repeat for `Secrets.swift` in the **"Core/Utilities"** group

## Method 3: Verify Files Are Added

After adding, verify in Xcode:

1. **Project Navigator** should show:
   - `Core/Services/SupabaseService.swift`
   - `Core/Utilities/Secrets.swift`
2. **Select each file** and check the **File Inspector** (right panel):
   - Under **"Target Membership"**, make sure **"NaarsCars"** is checked
3. **Build the project** (⌘B) - should now compile successfully

## Troubleshooting

### If files still don't appear:
1. Close Xcode
2. Reopen the project
3. The files should appear if they're in the correct folder structure

### If build still fails:
1. Clean build folder: **Product → Clean Build Folder** (⌘⇧K)
2. Build again: **Product → Build** (⌘B)


