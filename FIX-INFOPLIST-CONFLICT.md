# Fix: Multiple Commands Produce Info.plist Error

## Problem
The error "Multiple commands produce '.../Info.plist'" occurs because:
1. The project uses `fileSystemSynchronizedGroups` which automatically includes all files
2. `Info.plist` is being automatically added to Copy Bundle Resources
3. At the same time, `GENERATE_INFOPLIST_FILE = NO` and `INFOPLIST_FILE` are set, causing Xcode to process Info.plist
4. This creates a conflict: both a "copy command" and a "process command" for the same file

## Solution Options

### Option 1: Exclude Info.plist in Xcode (RECOMMENDED)

**Manual Fix in Xcode:**
1. Open the project in Xcode
2. Select the `NaarsCars` target
3. Go to **Build Phases** tab
4. Expand **Copy Bundle Resources**
5. If `Info.plist` appears in this list, remove it (select and press `-` button)
6. Clean build folder (Product → Clean Build Folder)
7. Rebuild

### Option 2: Move Info.plist Outside Synchronized Directory

Move `Info.plist` to a location that's not part of `fileSystemSynchronizedGroups`:
- Move to: `NaarsCars/Info.plist` (one level up)
- Update `INFOPLIST_FILE` setting to: `NaarsCars/Info.plist`

### Option 3: Use Build Settings Exclusion (if supported)

Add to build settings:
```
EXCLUDED_SOURCE_FILE_NAMES = Info.plist
```

However, this may not work with fileSystemSynchronizedGroups.

## Current Status

✅ **FIXED:**
- Debug configuration: `GENERATE_INFOPLIST_FILE = NO` and `INFOPLIST_FILE = NaarsCars/Resources/Info.plist`
- Release configuration: `GENERATE_INFOPLIST_FILE = NO` and `INFOPLIST_FILE = NaarsCars/Resources/Info.plist`
- Info.plist moved to `NaarsCars/Resources/Info.plist` to exclude it from `fileSystemSynchronizedGroups`
- Info.plist updated with all required privacy keys (camera, location, photos, Face ID)
- MapKit directions configuration included in Info.plist

✅ **Resolution Applied:**
Moved Info.plist outside the `fileSystemSynchronizedGroups` directory (from `NaarsCars/NaarsCars/` to `NaarsCars/Resources/`) which prevents it from being automatically included in Copy Bundle Resources while still allowing it to be processed correctly.

## Quick Fix Command

If you can't access Xcode UI, try this workaround:

```bash
# Temporarily rename Info.plist to see if build works
mv NaarsCars/NaarsCars/Info.plist NaarsCars/NaarsCars/Info.plist.template
# Build to verify no Info.plist errors
# Then restore and fix in Xcode UI
mv NaarsCars/NaarsCars/Info.plist.template NaarsCars/NaarsCars/Info.plist
```

## Verification

After fixing, verify with:
```bash
xcodebuild -project NaarsCars/NaarsCars.xcodeproj -scheme NaarsCars -sdk iphonesimulator -destination 'platform=iOS Simulator,name=iPhone 17 Pro' build 2>&1 | grep -i "Info.plist\|BUILD SUCCEEDED"
```

Expected: No "Info.plist" errors, "BUILD SUCCEEDED" message.

