# Localization Setup Guide

## What Has Been Implemented

### ✅ Completed

1. **LocalizationManager** - Manages language preferences and initializes on app launch
2. **Localizable.xcstrings** - Created with English and Spanish translations for:
   - Authentication screens (login, signup)
   - Settings screen (biometric, notifications, account linking)
   - Language settings screen
   - Common UI elements (buttons, errors, loading)
3. **String Externalization** - Updated key views to use `.localized`:
   - `LoginView.swift`
   - `SettingsView.swift`
   - `LanguageSettingsView.swift`
   - `ContentView.swift`

## Required Xcode Configuration

### Step 1: Add Localizable.xcstrings to Xcode Project

1. Open Xcode
2. Right-click on the `NaarsCars` folder in the Project Navigator
3. Select "Add Files to NaarsCars..."
4. Navigate to `NaarsCars/Resources/Localizable.xcstrings`
5. Make sure "Copy items if needed" is **unchecked** (file is already in the right place)
6. Make sure "Create groups" is selected
7. Click "Add"

### Step 2: Configure Project Localizations

1. Select the project in the Project Navigator (top-level "NaarsCars")
2. Select the "NaarsCars" target
3. Go to the "Info" tab
4. Under "Localizations", click the "+" button
5. Add the following languages:
   - Spanish (es)
   - Chinese (Simplified) (zh-Hans)
   - Chinese (Traditional) (zh-Hant)
   - Vietnamese (vi)
   - Korean (ko)

### Step 3: Verify Localizable.xcstrings is Configured

1. Select `Localizable.xcstrings` in the Project Navigator
2. In the File Inspector (right panel), verify:
   - "Localize..." button shows all languages
   - The file is included in the target

## How It Works

1. **Language Selection**: User selects language in Settings → Language
2. **Preference Storage**: `LocalizationManager` stores preference in `UserDefaults` with key `app_language`
3. **AppleLanguages Override**: On app launch, `LocalizationManager.initializeLanguagePreference()` sets `AppleLanguages` in `UserDefaults`
4. **String Loading**: `NSLocalizedString` (via `.localized` extension) reads from `Localizable.xcstrings` based on `AppleLanguages`
5. **App Restart**: Language change requires app restart to take full effect

## Testing

1. Build and run the app
2. Go to Settings → Language
3. Select "Español" (Spanish)
4. Restart the app (or use "Restart Now" button)
5. Verify that:
   - Login screen shows Spanish text
   - Settings screen shows Spanish text
   - Language settings shows Spanish text

## Adding More Translations

To add translations for other languages (Chinese, Vietnamese, Korean):

1. Open `Localizable.xcstrings` in Xcode
2. For each string key, add a new localization:
   - Click the "+" next to the language code
   - Enter the translated text
3. Or use Xcode's "Export for Localization" feature to generate `.xliff` files for translators

## Current Translation Coverage

- ✅ English (en) - Complete
- ✅ Spanish (es) - Complete for implemented screens
- ⏳ Chinese Simplified (zh-Hans) - Keys exist, translations needed
- ⏳ Chinese Traditional (zh-Hant) - Keys exist, translations needed
- ⏳ Vietnamese (vi) - Keys exist, translations needed
- ⏳ Korean (ko) - Keys exist, translations needed

## Next Steps

1. Add `Localizable.xcstrings` to Xcode project (see Step 1 above)
2. Configure project localizations (see Step 2 above)
3. Test language switching
4. Add more string externalizations to other views as needed
5. Add translations for remaining languages

## Notes

- Language changes require app restart for full effect
- The `AppleLanguages` UserDefaults key is set on app launch
- `NSLocalizedString` automatically respects `AppleLanguages`
- Date/time/number formatting uses `LocalizationManager.currentLocale`

