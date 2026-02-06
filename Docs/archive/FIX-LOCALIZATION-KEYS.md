# Fix Localization Keys Showing as Placeholders

## Problem
Several screens are showing localization keys (like `auth_login_title`, `settings_done`, etc.) instead of translated text. This indicates that `NSLocalizedString` is not finding the `Localizable.xcstrings` file.

## Root Cause
The `Localizable.xcstrings` file exists at `NaarsCars/Resources/Localizable.xcstrings` and contains all translations, but:
1. The file might not be properly included in the Xcode project build phase
2. `NSLocalizedString` needs an explicit bundle reference to find the .xcstrings file

## Solution Applied

### 1. Updated String Extension
Modified `String+Localization.swift` to explicitly specify the bundle and table name:
```swift
var localized: String {
    let localizedString = NSLocalizedString(self, tableName: "Localizable", bundle: .main, value: self, comment: "")
    return localizedString
}
```

This ensures `NSLocalizedString` looks for `Localizable.xcstrings` in the main bundle.

### 2. Verify Xcode Project Configuration

**CRITICAL**: The `Localizable.xcstrings` file MUST be added to the Xcode project:

1. **Open Xcode**
2. **Right-click on `NaarsCars/Resources` folder** in the Project Navigator
3. **Select "Add Files to NaarsCars..."**
4. **Navigate to and select `Localizable.xcstrings`**
5. **Ensure "Copy items if needed" is UNCHECKED** (file is already in the correct location)
6. **Ensure "Add to targets: NaarsCars" is CHECKED**
7. **Click "Add"**

### 3. Verify Build Settings

Ensure these build settings are correct:
- `LOCALIZATION_PREFERS_STRING_CATALOGS = YES` ✅ (Already set)
- The file should appear in "Copy Bundle Resources" build phase

### 4. Clean and Rebuild

After adding the file to Xcode:
1. **Product → Clean Build Folder** (`Shift+Cmd+K`)
2. **Close Xcode completely** (`Cmd+Q`)
3. **Delete DerivedData**: `rm -rf ~/Library/Developer/Xcode/DerivedData/NaarsCars-*`
4. **Reopen Xcode**
5. **Build and Run**

## Verification

After the fix, strings should display as:
- ✅ "Sign in to continue" instead of "auth_login_title"
- ✅ "Done" instead of "settings_done"
- ✅ "Email" instead of "auth_email_placeholder"

If keys still show, verify:
1. The file is in the "Copy Bundle Resources" build phase
2. The file is not duplicated in the project
3. The target membership includes "NaarsCars"

## Alternative: Check Bundle Location

If issues persist, you can verify the bundle is finding the file:
```swift
// Add this temporarily to debug
if let path = Bundle.main.path(forResource: "Localizable", ofType: "xcstrings") {
    print("✅ Found Localizable.xcstrings at: \(path)")
} else {
    print("❌ Localizable.xcstrings not found in bundle")
}
```


