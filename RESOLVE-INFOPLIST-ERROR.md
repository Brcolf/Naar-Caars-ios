# How to Resolve "Multiple commands produce Info.plist" Error

## The Problem
Xcode is trying to copy `Info.plist` from `NaarsCars/NaarsCars/Info.plist` even though:
- ✅ The file has been moved to `NaarsCars/Resources/Info.plist`
- ✅ Build settings are correctly configured
- ✅ Only one Info.plist file exists

This is a **Xcode cache issue**. The build system has cached that Info.plist should be copied from the old location.

## Solution: Clear Xcode Cache and Remove from Build Phases

### Option 1: Quick Fix (Recommended)

**In Xcode:**
1. **Close Xcode completely** (`Cmd+Q`)
2. Run this command in Terminal:
   ```bash
   rm -rf ~/Library/Developer/Xcode/DerivedData/NaarsCars-*
   ```
3. **Reopen Xcode**
4. **Select NaarsCars target** → **Build Phases** tab
5. Expand **Copy Bundle Resources**
6. **If `Info.plist` appears in the list**, select it and click **minus (-)** to remove it
7. **Product** → **d Folder** (`Shift+Cmd+K`)
8. Build again

### Option 2: If Option 1 Doesn't Work

The fileSystemSynchronizedGroups may be causing issues. Try this:

1. Close Xcode
2. Delete DerivedData: `rm -rf ~/Library/Developer/Xcode/DerivedData/NaarsCars-*`
3. Reopen Xcode
4. Select project → NaarsCars target → **Build Phases**
5. Check **Copy Bundle Resources** - remove Info.plist if present
6. Also check if there's a **fileSystemSynchronizedGroups** section showing Info.plist
7. **Build Settings** → Search "Info.plist" → Verify:
erate Info.plist File: `NO`
   - Info.plist File: `NaarsCars/Resources/Info.plist`
8. Clean Build Folder
9. Close Xcode, reopen, build

### Option 3: Nuclear Option (If All Else Fails)

If the error persists, you may need to disable fileSystemSynchronizedGroups temporarily:

1. Open project.pbxproj in a text editor
2. Find: `fileSystemSynchronizedGroups = ( ACDCBDCA2F0B74F400956D1C /* NaarsCars */, );`
3. Comment it out or remove the NaarsCars entry
4. Manually add files to Xcode project (this is more work but guarantees no auto-inclusion issues)
5. Rebuild

## Current Configuration (Verified ✅)

- **Info.plist location**: `NaarsCars/Resources/Info.plist` (outside fileSystemSynchronizedGroups)
- **Build Settings**:
  - `GENERATE_INFOPLIST_FILE = NO`
  - `INFOPLIST_FILE = NaarsCars/Resources/Info.plist`
- **Only one Info.plist file exists** in the project

## Why This Happens

`fileSystemSynchronizedGroups` automatically syncs files from the directory into the build. 
Even after moving/deleting files, Xcods build cache may still reference the old location.
The Copy Bundle Resources phase may have been automatically populated and cached.

Removing it from Copy Bundle Resources in Xcode UI clears this cache.
