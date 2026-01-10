# Fix Info.plist Conflict in Xcode

## Quick Fix Steps

The project files are already correctly configured. If you're still seeing the error in Xcode, follow these steps:

### Step 1: Close Xcode Completely
- Press `Cmd+Q` to quit Xcode (don't just close the window)
- Wait a few seconds

### Step 2: Clear Build Cache
Run this in Terminal:
```bash
cd /Users/bcolf/.cursor/worktrees/naars-cars-ios/vcs
./CLEAR-XCODE-CACHE.sh
```

Or manually:
```bash
rm -rf ~/Library/Developer/Xcode/DerivedData/NaarsCars-*
```

### Step 3: Reopen Xcode and Clean
1. Open the project in Xcode
2. Go to **Product** → **Clean Build Folder** (or press `Shift+Cmd+K`)
3. Close Xcode again (`Cmd+Q`)
4. Reopen Xcode

### Step 4: Verify Build Settings (if error persists)
1. Select the project in Project Navigator
2. Select **NaarsCars** target
3. Go to **Build Settings** tab
4. Search for "Info.plist"
5. Verify:
   - **Info.plist File**: Should be `arsCars/Resources/Info.plist`
   - **Generate Info.plist File**: Should be `NO`

### Step 5: Remove from Copy Bundle Resources (CRITICAL)
1. Select **NaarsCars** target
2. Go to **Build Phases** tab
3. Expand **Copy Bundle Resources**
4. **Look for `Info.plist`** in the list
5. If found, select it and click the **minus (-)** button to remove it
6. Clean Build Folder again (`Shift+Cmd+K`)
7. Build again

### Step 6: If Still Failing - Check File System
Verify Info.plist only exists in one location:
```bash
find NaarsCars -name "Info.plist" -type f
# Should only show: NaarsCars/Resources/Info.plist
```

If you see `NaarsCars/NaarsCars/Info.plist`, delete it:
```bash
rm NaarsCars/NaarsCars/Info.plist
```

## Expected Configuration

✅ **Info.plist location**: `NaarsCars/Resources/Info.plist`  
✅ **Build Settings**: `GENERATE_INFOPLIST_FILE = NO`  
✅ **Build Settings**: `INFOPLIST_FILE = NaarsCars/Resources/Info.plist`  
✅ **Copy Bundle Resources**: Should NOT include Info.plist  
✅ **Only one Info.plist file**: In Resources/ directory only

## Why This Happens

When using `fileSystemSynchronizedGroups`, Xcode automatically includes files from the synchronized directory. Info.plist should NOT be copied as a resource - it should only be processed. Moving it to Resources/ (which is NOT synchronized) prevents the automatic inclusion.

