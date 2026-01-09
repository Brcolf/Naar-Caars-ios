# Xcode Localization Configuration Guide

## Step-by-Step Instructions for Adding Chinese Localizations

### Step 1: Add Localizable.xcstrings to Xcode Project

1. **Open Xcode** and open the `NaarsCars.xcodeproj` file
2. In the **Project Navigator** (left sidebar), right-click on the `NaarsCars` folder
3. Select **"Add Files to NaarsCars..."**
4. Navigate to: `NaarsCars/Resources/Localizable.xcstrings`
5. **Important settings:**
   - ✅ Uncheck **"Copy items if needed"** (file is already in the correct location)
   - ✅ Select **"Create groups"** (not "Create folder references")
   - ✅ Make sure **"NaarsCars"** target is checked
6. Click **"Add"**

### Step 2: Configure Project Localizations

1. **Select the project** in the Project Navigator (the blue icon at the top)
2. Select the **"NaarsCars"** target (under "TARGETS")
3. Click on the **"Info"** tab at the top
4. Scroll down to the **"Localizations"** section
5. You should see a list of localizations. Click the **"+"** button to add new localizations
6. Add the following languages (if not already present):
   - **Spanish (es)**
   - **Chinese (Simplified) (zh-Hans)**
   - **Chinese (Traditional) (zh-Hant)**
   - **Vietnamese (vi)** (optional, if you want to add translations later)
   - **Korean (ko)** (optional, if you want to add translations later)

### Step 3: Configure Localizable.xcstrings for Each Language

1. **Select `Localizable.xcstrings`** in the Project Navigator
2. In the **File Inspector** (right panel, first tab), you should see a **"Localize..."** button
3. Click **"Localize..."** if prompted
4. In the localization dialog:
   - Check the boxes for all languages you want to support:
     - ✅ English (Base)
     - ✅ Spanish
     - ✅ Chinese (Simplified)
     - ✅ Chinese (Traditional)
   - Click **"Localize"**

### Step 4: Verify Localizations in Localizable.xcstrings

1. **Select `Localizable.xcstrings`** in the Project Navigator
2. Xcode should open it in the **Strings Catalog Editor**
3. You should see:
   - A list of all string keys on the left
   - For each key, columns showing translations for:
     - English (en)
     - Spanish (es)
     - Chinese (Simplified) (zh-Hans)
     - Chinese (Traditional) (zh-Hant)
4. **Verify** that all keys have translations in all four languages

### Step 5: Build and Test

1. **Build the project** (⌘B) to ensure there are no errors
2. **Run the app** on a simulator or device
3. **Test language switching:**
   - Go to Settings → Language
   - Select "简体中文" (Simplified Chinese) or "繁體中文" (Traditional Chinese)
   - Restart the app
   - Verify that all UI text appears in Chinese

## Troubleshooting

### If Localizable.xcstrings doesn't appear in Xcode:

1. Make sure the file is in the correct location: `NaarsCars/Resources/Localizable.xcstrings`
2. Try adding it again using "Add Files to NaarsCars..."
3. Check that the file is included in the "NaarsCars" target (select file → File Inspector → Target Membership)

### If languages don't appear in the Localizations list:

1. Make sure you're looking at the **target** (not the project) in the Info tab
2. Try adding languages one at a time
3. Some languages might need to be added via the "+" button in the Localizations section

### If translations don't appear after restart:

1. Check that `LocalizationManager.shared.initializeLanguagePreference()` is being called in `NaarsCarsApp.init()`
2. Verify that `AppleLanguages` is being set correctly (check logs for "🌐 [LocalizationManager]")
3. Make sure the language code matches exactly: `zh-Hans` or `zh-Hant` (case-sensitive)

### If you see English text instead of Chinese:

1. Verify that the string keys in your Swift code match exactly with the keys in `Localizable.xcstrings`
2. Check that you're using `.localized` extension on strings
3. Ensure the app was restarted after changing language
4. Check Xcode console logs for localization warnings

## Language Codes Reference

| Language | Code | Display Name |
|----------|------|--------------|
| English | `en` | English |
| Spanish | `es` | Español |
| Chinese (Simplified) | `zh-Hans` | 简体中文 |
| Chinese (Traditional) | `zh-Hant` | 繁體中文 |
| Vietnamese | `vi` | Tiếng Việt |
| Korean | `ko` | 한국어 |

## Additional Notes

- **Language codes are case-sensitive**: Use `zh-Hans` and `zh-Hant` exactly as shown
- **App restart required**: Language changes only take full effect after app restart
- **System Default**: If user selects "System Default", the app will use the device's language setting
- **Fallback**: If a translation is missing, the app will fall back to English

## Quick Checklist

- [ ] `Localizable.xcstrings` added to Xcode project
- [ ] Project localizations include: en, es, zh-Hans, zh-Hant
- [ ] `Localizable.xcstrings` is localized for all languages
- [ ] All string keys have translations in all languages
- [ ] Project builds without errors
- [ ] Language switching works in the app
- [ ] Chinese text displays correctly after restart

