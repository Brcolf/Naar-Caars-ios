# String Catalog Setup for Localization

## Overview

The Naar's Cars app uses Apple's modern String Catalog (`.xcstrings`) format for localization. This provides better tooling and integration with Xcode compared to traditional `.strings` files.

## Setup Steps

### 1. Create String Catalog in Xcode

1. **Open Xcode** and navigate to your project
2. **Right-click** on the `NaarsCars` folder in the Project Navigator
3. Select **New File...**
4. Choose **Resource** → **String Catalog**
5. Name it: `Localizable.xcstrings`
6. Make sure **NaarsCars** target is selected
7. Click **Create**

### 2. Add Languages

1. **Select** `Localizable.xcstrings` in the Project Navigator
2. In the **Inspector panel** (right side), you'll see a **Languages** section
3. Click the **+** button to add languages:
   - **English** (Base) - Already included
   - **Spanish** (es)
   - **Chinese (Simplified)** (zh-Hans)
   - **Vietnamese** (vi)
   - **Korean** (ko)

### 3. Extract Hardcoded Strings

Currently, the app uses hardcoded English strings. You'll need to:

1. **Search for hardcoded strings** in the codebase:
   ```bash
   # Find common patterns
   grep -r "Text(\"" NaarsCars/Features/
   grep -r "title:" NaarsCars/Features/
   grep -r "message:" NaarsCars/Features/
   ```

2. **Replace with localized strings**:
   ```swift
   // Before:
   Text("Sign In")
   
   // After:
   Text("sign_in", bundle: .main)
   // Or use the extension:
   "sign_in".localized
   ```

3. **Add to String Catalog**:
   - Open `Localizable.xcstrings`
   - Click **+** to add a new entry
   - Key: `sign_in`
   - English: `Sign In`
   - Spanish: `Iniciar sesión`
   - (Add translations for other languages)

### 4. Use Localization Extensions

The app already has localization extensions in place:

```swift
// String extension
"sign_in".localized  // Uses NSLocalizedString

// Date extension
date.localizedShortDate  // Uses LocalizationManager.currentLocale

// Number extension
count.localizedString  // Uses LocalizationManager.currentLocale
```

### 5. Common String Keys

Here are some common strings you'll need to extract:

**Authentication**:
- `sign_in` → "Sign In"
- `sign_up` → "Sign Up"
- `email` → "Email"
- `password` → "Password"
- `forgot_password` → "Forgot Password?"

**Navigation**:
- `requests` → "Requests"
- `messages` → "Messages"
- `notifications` → "Notifications"
- `town_hall` → "Town Hall"
- `leaderboard` → "Leaderboard"
- `profile` → "Profile"

**Rides**:
- `create_ride` → "Create Ride Request"
- `pickup_location` → "Pickup Location"
- `destination` → "Destination"
- `seats` → "Seats"
- `notes` → "Notes"

**Favors**:
- `create_favor` → "Create Favor Request"
- `location` → "Location"
- `duration` → "Duration"
- `requirements` → "Requirements"

**Settings**:
- `settings` → "Settings"
- `language` → "Language"
- `biometric_auth` → "Biometric Authentication"
- `push_notifications` → "Push Notifications"

### 6. Testing Localization

1. **Change app language**:
   - Go to Settings → Language
   - Select a different language
   - Restart the app (or use the restart prompt)

2. **Test in Simulator**:
   - Device → Language & Region
   - Change system language
   - App will use system language if "System Default" is selected

3. **Verify translations**:
   - Check all screens display translated text
   - Verify date/number formatting matches locale
   - Test with different languages

### 7. Translation Workflow

**Option A: Manual Translation**
1. Export String Catalog to CSV (if needed)
2. Send to translators
3. Import translations back

**Option B: Use Translation Services**
1. Use Xcode's built-in translation tools
2. Or use third-party services that support `.xcstrings` format

**Option C: AI Translation (Quick Start)**
1. Use ChatGPT/Claude to translate strings
2. Manually add to String Catalog
3. Have native speakers review

### 8. Best Practices

1. **Use descriptive keys**: `sign_in_button` not `btn1`
2. **Group related strings**: `ride_pickup`, `ride_destination`, `ride_seats`
3. **Include context**: Add comments in String Catalog for translators
4. **Test edge cases**: Long strings, pluralization, special characters
5. **Keep base language updated**: English should always be complete

### 9. Pluralization

For plural strings, use `.stringsdict` format or handle in code:

```swift
// In code:
let count = 5
Text("\(count) \(count == 1 ? "request" : "requests")")

// Or use String Catalog's plural support:
Text("request_count \(count)", bundle: .main)
// In String Catalog, add plural rule for "request_count"
```

### 10. Date/Number Formatting

The app already handles locale-aware formatting:

```swift
// Dates
date.localizedShortDate  // "Jan 5" or "5 Jan" depending on locale
date.localizedTime       // "2:30 PM" or "14:30" depending on locale

// Numbers
count.localizedString    // "1,000" or "1.000" depending on locale
rating.localizedRating   // "4.8" formatted for locale
```

## Current Status

✅ **Infrastructure Complete**:
- `LocalizationManager` created
- Extensions for String/Date/Number created
- `LanguageSettingsView` created
- Settings integration complete

⏳ **Manual Steps Required**:
- Create String Catalog in Xcode
- Extract hardcoded strings
- Add translations (start with Spanish)
- Test with different languages

## Next Steps

1. **Create String Catalog** (5 minutes)
2. **Extract 10-20 most common strings** (30 minutes)
3. **Add Spanish translations** (1 hour)
4. **Test in app** (15 minutes)
5. **Continue extracting strings incrementally** (ongoing)

## Resources

- [Apple: Localizing Your App](https://developer.apple.com/documentation/xcode/localizing-your-app)
- [String Catalog Format](https://developer.apple.com/documentation/xcode/localizing-strings-in-your-app)
- [NSLocalizedString Documentation](https://developer.apple.com/documentation/foundation/nslocalizedstring)

