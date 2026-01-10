# CRITICAL: Manual Fix Required in Xcode

The project files are correctly configured, but Xcode may have cached the old state. 
You MUST follow these steps IN XCODE to fully resolve the issue:

## Required Steps (Do in Xcode)

### 1. Close Xcode Completely
- Press `Cmd+Q` (don't just close the window)
- Verify Xcode is fully quit

### 2. Delete DerivedData
```bash
rm -rf ~/Library/Developer/Xcode/DerivedData/NaarsCars-*
```

### 3. Reopen Xcode and Fix Build Phases

**CRITICAL STEP**: This must be done in Xcode UI:

1. Open the project in Xcode
2. Select **NaarsCars** target (in the left sidebar under TARGETS)
3. Click **Build Phases** tab (at the top)
4. Expand **Copy Bundle Resources** section
5. **Look for `Info.plist`** in the list
6. If you see `Info.plist`, select it and click the **minus (-)** button
7. **Clean Build Folder**: Product → Clean Build Folder (`Shift+Cmd+K`)
8. Close Xcode (`Cmd+Q`)
9. Reopen Xco
10. Try building again

### 4. Verify Build Settings

1. Select **NaarsCars** target
2. Go to **Build Settings** tab
3. Search for "Info.plist"
4. Verify these settings:
   - **Generate Info.plist File** = `NO`
   - **Info.plist File** = `NaarsCars/Resources/Info.plist`

### 5. If Error Persists

Check if Info.plist was recreated in the wrong location:
```bash
find NaarsCars -name "Info.plist" -type f
# Should only show: NaarsCars/Resources/Info.plist
```

If you see `NaarsCars/NaarsCars/Info.plist`, delete it and repeat steps above.

## Why Manual Fix is Needed

`fileSystemSynchronizedGroups` automatically includes files, and Xcode may have cached
that Info.plist should be in Copy Bundle Resources. Removing it from the Build Phases
UI is the only way to clear this cache in some cases.

