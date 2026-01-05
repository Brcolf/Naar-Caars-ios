# PRD: Localization

## Document Information
- **Feature Name**: Localization (Multi-Language Support)
- **Phase**: 5 (Future Enhancements)
- **Dependencies**: `prd-foundation-architecture.md`
- **Estimated Effort**: 2-3 weeks (depends on number of languages)
- **Last Updated**: January 2025

---

## 1. Introduction/Overview

### What is this?
This document defines localization support for the Naar's Cars iOS app. Localization enables the app to display content in multiple languages based on user preference.

### Why does this matter?
- **Accessibility**: Non-English speakers can use the app
- **Community growth**: Expands potential user base
- **Inclusivity**: Seattle has diverse language communities
- **App Store**: Required for international distribution
- **User experience**: Native language improves comprehension

### What problem does it solve?
- Language barriers for non-English speakers
- Confusion from unfamiliar UI text
- Excludes potential community members
- Limits app's reach

---

## 2. Goals

| Goal | Measurable Outcome |
|------|-------------------|
| Support system language | App uses device language setting |
| Manual language override | Users can choose app language |
| All UI text localized | No hardcoded English strings |
| Date/time localization | Formats match locale |
| RTL support foundation | Arabic, Hebrew ready |
| Initial languages | English + Spanish |

---

## 3. User Stories

| ID | As a... | I want to... | So that... |
|----|---------|--------------|------------|
| LOC-01 | Spanish speaker | Use the app in Spanish | I understand everything |
| LOC-02 | User | Have dates in my format | Jan 5 vs 5 Jan |
| LOC-03 | User | Override app language | I can use different language than system |
| LOC-04 | User | See numbers in my format | 1,000 vs 1.000 |
| LOC-05 | Developer | Add new languages easily | Translation can scale |

---

## 4. Functional Requirements

### 4.1 Project Setup

**Requirement LOC-FR-001**: Configure Xcode for localization:

1. Select project in navigator
2. Info tab â†’ Localizations
3. Click "+" to add languages
4. Export for translation (.xliff or .strings)

**Requirement LOC-FR-002**: Initial supported languages:

| Language | Code | Priority |
|----------|------|----------|
| English | en | P0 (Base) |
| Spanish | es | P1 |
| Chinese (Simplified) | zh-Hans | P2 |
| Vietnamese | vi | P2 |
| Korean | ko | P2 |

### 4.2 String Externalization

**Requirement LOC-FR-003**: All user-facing strings MUST be externalized:

```swift
// BAD - Hardcoded string
Text("Welcome back!")

// GOOD - Localized string
Text("welcome_back", comment: "Greeting on login screen")
```

**Requirement LOC-FR-004**: Use String Catalogs (.xcstrings) for modern localization:

```
Localizable.xcstrings
â”œâ”€â”€ en (English - Base)
â”œâ”€â”€ es (Spanish)
â”œâ”€â”€ zh-Hans (Chinese Simplified)
â”œâ”€â”€ vi (Vietnamese)
â””â”€â”€ ko (Korean)
```

### 4.3 String Keys Convention

**Requirement LOC-FR-005**: Use consistent naming convention:

```
[feature]_[screen]_[element]_[description]

Examples:
auth_login_title                    â†’ "Welcome Back, Carbardian!"
auth_login_email_placeholder        â†’ "Email"
auth_login_button                   â†’ "Log In"
ride_create_pickup_label            â†’ "Pickup Location"
ride_detail_claim_button            â†’ "I Can Help!"
common_cancel                       â†’ "Cancel"
common_save                         â†’ "Save"
common_error_network                â†’ "No internet connection"
```

### 4.4 Localization Manager

**Requirement LOC-FR-006**: Create LocalizationManager for language override:

```swift
// Core/Utilities/LocalizationManager.swift
import Foundation
import SwiftUI

final class LocalizationManager: ObservableObject {
    static let shared = LocalizationManager()
    
    @AppStorage("app_language") var appLanguage: String = "system"
    
    /// Available languages in the app
    static let supportedLanguages: [AppLanguage] = [
        AppLanguage(code: "system", name: "System Default", localizedName: "System Default"),
        AppLanguage(code: "en", name: "English", localizedName: "English"),
        AppLanguage(code: "es", name: "Spanish", localizedName: "EspaÃ±ol"),
        AppLanguage(code: "zh-Hans", name: "Chinese (Simplified)", localizedName: "ç®€ä½“ä¸­æ–‡"),
        AppLanguage(code: "vi", name: "Vietnamese", localizedName: "Tiáº¿ng Viá»‡t"),
        AppLanguage(code: "ko", name: "Korean", localizedName: "í•œêµ­ì–´")
    ]
    
    /// Current locale to use for formatting
    var currentLocale: Locale {
        if appLanguage == "system" {
            return Locale.current
        }
        return Locale(identifier: appLanguage)
    }
    
    /// Current language code
    var currentLanguageCode: String {
        if appLanguage == "system" {
            return Locale.current.language.languageCode?.identifier ?? "en"
        }
        return appLanguage
    }
    
    private init() {}
    
    /// Apply language change (requires app restart for full effect)
    func setLanguage(_ code: String) {
        appLanguage = code
        
        if code == "system" {
            UserDefaults.standard.removeObject(forKey: "AppleLanguages")
        } else {
            UserDefaults.standard.set([code], forKey: "AppleLanguages")
        }
        
        // Post notification for immediate updates where possible
        NotificationCenter.default.post(name: .languageDidChange, object: nil)
    }
}

struct AppLanguage: Identifiable {
    let code: String
    let name: String        // English name
    let localizedName: String  // Native name
    
    var id: String { code }
}

extension Notification.Name {
    static let languageDidChange = Notification.Name("languageDidChange")
}
```

### 4.5 Localized String Extension

**Requirement LOC-FR-007**: Helper extension for localized strings:

```swift
// Core/Extensions/String+Localization.swift
import Foundation

extension String {
    /// Returns localized string using self as key
    var localized: String {
        return NSLocalizedString(self, comment: "")
    }
    
    /// Returns localized string with format arguments
    func localized(with arguments: CVarArg...) -> String {
        return String(format: self.localized, arguments: arguments)
    }
}

// Usage:
// "auth_login_title".localized
// "ride_seats_count".localized(with: 3)  // "3 seats"
```

### 4.6 Strings Catalog Structure

**Requirement LOC-FR-008**: Organize strings by feature:

```
// Localizable.xcstrings structure

// MARK: - Common
"common_cancel" = "Cancel";
"common_save" = "Save";
"common_delete" = "Delete";
"common_edit" = "Edit";
"common_done" = "Done";
"common_ok" = "OK";
"common_error" = "Error";
"common_loading" = "Loading...";
"common_retry" = "Try Again";

// MARK: - Errors
"error_network" = "No internet connection. Please check your network and try again.";
"error_server" = "Something went wrong. Please try again later.";
"error_unknown" = "An unexpected error occurred.";

// MARK: - Authentication
"auth_login_title" = "Welcome Back, Carbardian!";
"auth_login_email_placeholder" = "Email";
"auth_login_password_placeholder" = "Password";
"auth_login_button" = "Log In";
"auth_login_forgot_password" = "Forgot Password?";
"auth_login_signup_prompt" = "Don't have an account? Sign Up";

"auth_signup_title" = "Join the Community";
"auth_signup_invite_prompt" = "Enter your invite code from an existing Carbardian";
"auth_signup_invite_placeholder" = "Invite Code";
"auth_signup_verify_button" = "Verify Code";
"auth_signup_name_placeholder" = "Full Name";
"auth_signup_car_placeholder" = "Car (optional)";
"auth_signup_button" = "Create Account";

"auth_pending_title" = "Pending Approval";
"auth_pending_message" = "Thanks for signing up! An admin needs to approve your account before you can start sharing rides with the community.";

// MARK: - Dashboard
"dashboard_title" = "Requests";
"dashboard_tab_open" = "All Open";
"dashboard_tab_posted" = "My Requests";
"dashboard_tab_helping" = "Helping";
"dashboard_tab_completed" = "Completed";
"dashboard_empty_open" = "No open requests right now";
"dashboard_empty_posted" = "You haven't posted any requests";
"dashboard_empty_helping" = "You're not helping with any requests";

// MARK: - Rides
"ride_type_label" = "Need Ride";
"ride_create_title" = "New Ride Request";
"ride_date_label" = "When do you need a ride?";
"ride_pickup_label" = "Pickup Location";
"ride_destination_label" = "Destination";
"ride_seats_label" = "Number of Seats";
"ride_notes_label" = "Additional Notes";
"ride_notes_placeholder" = "Any special instructions...";
"ride_gift_label" = "Gift/Compensation";
"ride_gift_placeholder" = "e.g., Coffee, $20";
"ride_post_button" = "Post Request";
"ride_claim_button" = "I Can Help!";
"ride_unclaim_button" = "Unclaim";
"ride_complete_button" = "Mark as Complete";

// MARK: - Favors
"favor_type_label" = "Favor";
"favor_create_title" = "New Favor Request";
"favor_title_label" = "What do you need help with?";
"favor_title_placeholder" = "Title";
"favor_description_label" = "Description";
"favor_location_label" = "Where?";
"favor_duration_label" = "How long will it take?";
"favor_duration_under_hour" = "Under an hour";
"favor_duration_couple_hours" = "A couple of hours";
"favor_duration_couple_days" = "A couple of days";
"favor_duration_not_sure" = "Not sure";
"favor_requirements_label" = "Requirements";
"favor_requirements_placeholder" = "e.g., Need a car";

// MARK: - Messages
"messages_title" = "Messages";
"messages_empty" = "No messages yet";
"messages_new_button" = "New Message";
"messages_input_placeholder" = "Message...";
"messages_direct_label" = "Direct Message";

// MARK: - Profile
"profile_title" = "My Profile";
"profile_edit_button" = "Edit Profile";
"profile_stats_rating" = "%@ average";
"profile_stats_reviews" = "%d reviews";
"profile_stats_fulfilled" = "%d requests fulfilled";
"profile_invite_codes" = "Invite Codes";
"profile_generate_code" = "Generate";
"profile_code_available" = "Available";
"profile_code_used" = "Used";
"profile_reviews_title" = "My Reviews";
"profile_logout" = "Log Out";
"profile_logout_confirm" = "Are you sure you want to log out?";

// MARK: - Settings
"settings_title" = "Settings";
"settings_appearance" = "Appearance";
"settings_notifications" = "Notifications";
"settings_language" = "Language";
"settings_security" = "Security";
"settings_about" = "About";

// MARK: - Notifications
"notifications_title" = "Notifications";
"notifications_empty" = "No notifications";
"notifications_mark_all_read" = "Mark All Read";

// MARK: - Status
"status_open" = "Open";
"status_claimed" = "Claimed";
"status_completed" = "Completed";
"status_cancelled" = "Cancelled";
```

### 4.7 Date/Time Formatting

**Requirement LOC-FR-009**: Use locale-aware date formatting:

```swift
// Core/Extensions/Date+Localization.swift
import Foundation

extension Date {
    /// Locale-aware short date (e.g., "Jan 5" or "5 Jan")
    var localizedShortDate: String {
        let formatter = DateFormatter()
        formatter.dateStyle = .medium
        formatter.timeStyle = .none
        formatter.locale = LocalizationManager.shared.currentLocale
        return formatter.string(from: self)
    }
    
    /// Locale-aware time (e.g., "2:30 PM" or "14:30")
    var localizedTime: String {
        let formatter = DateFormatter()
        formatter.dateStyle = .none
        formatter.timeStyle = .short
        formatter.locale = LocalizationManager.shared.currentLocale
        return formatter.string(from: self)
    }
    
    /// Locale-aware relative time
    var localizedRelative: String {
        let formatter = RelativeDateTimeFormatter()
        formatter.locale = LocalizationManager.shared.currentLocale
        formatter.unitsStyle = .full
        return formatter.localizedString(for: self, relativeTo: Date())
    }
    
    /// Full date/time for display
    var localizedFull: String {
        let formatter = DateFormatter()
        formatter.dateStyle = .full
        formatter.timeStyle = .short
        formatter.locale = LocalizationManager.shared.currentLocale
        return formatter.string(from: self)
    }
}
```

### 4.8 Number Formatting

**Requirement LOC-FR-010**: Use locale-aware number formatting:

```swift
// Core/Extensions/Number+Localization.swift
import Foundation

extension Int {
    /// Locale-aware number string (e.g., "1,000" or "1.000")
    var localizedString: String {
        let formatter = NumberFormatter()
        formatter.numberStyle = .decimal
        formatter.locale = LocalizationManager.shared.currentLocale
        return formatter.string(from: NSNumber(value: self)) ?? "\(self)"
    }
}

extension Double {
    /// Locale-aware decimal string
    func localizedString(decimals: Int = 1) -> String {
        let formatter = NumberFormatter()
        formatter.numberStyle = .decimal
        formatter.minimumFractionDigits = decimals
        formatter.maximumFractionDigits = decimals
        formatter.locale = LocalizationManager.shared.currentLocale
        return formatter.string(from: NSNumber(value: self)) ?? "\(self)"
    }
    
    /// Rating display (e.g., "4.8")
    var localizedRating: String {
        return localizedString(decimals: 1)
    }
}
```

### 4.9 Language Settings UI

**Requirement LOC-FR-011**: Language selection interface:

```
â”Œâ”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”
â”‚   â† Language                        â”‚
â”œâ”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”¤
â”‚                                     â”‚
â”‚   â”Œâ”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”   â”‚
â”‚   â”‚ â—‰ System Default            â”‚   â”‚
â”‚   â”‚   Use device language       â”‚   â”‚
â”‚   â”œâ”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”¤   â”‚
â”‚   â”‚ â—‹ English                   â”‚   â”‚
â”‚   â”‚   English                   â”‚   â”‚
â”‚   â”œâ”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”¤   â”‚
â”‚   â”‚ â—‹ EspaÃ±ol                   â”‚   â”‚
â”‚   â”‚   Spanish                   â”‚   â”‚
â”‚   â”œâ”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”¤   â”‚
â”‚   â”‚ â—‹ ç®€ä½“ä¸­æ–‡                   â”‚   â”‚
â”‚   â”‚   Chinese (Simplified)      â”‚   â”‚
â”‚   â”œâ”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”¤   â”‚
â”‚   â”‚ â—‹ Tiáº¿ng Viá»‡t                â”‚   â”‚
â”‚   â”‚   Vietnamese                â”‚   â”‚
â”‚   â”œâ”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”¤   â”‚
â”‚   â”‚ â—‹ í•œêµ­ì–´                     â”‚   â”‚
â”‚   â”‚   Korean                    â”‚   â”‚
â”‚   â””â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”˜   â”‚
â”‚                                     â”‚
â”‚   âš ï¸ Changing language requires     â”‚
â”‚   restarting the app.               â”‚
â”‚                                     â”‚
â””â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”˜
```

```swift
// Features/Profile/Views/LanguageSettingsView.swift
struct LanguageSettingsView: View {
    @ObservedObject private var localizationManager = LocalizationManager.shared
    @State private var showRestartAlert = false
    @State private var pendingLanguage: String?
    
    var body: some View {
        Form {
            Section {
                ForEach(LocalizationManager.supportedLanguages) { language in
                    Button {
                        selectLanguage(language.code)
                    } label: {
                        HStack {
                            VStack(alignment: .leading) {
                                Text(language.localizedName)
                                    .foregroundColor(.primary)
                                if language.code != "system" && language.localizedName != language.name {
                                    Text(language.name)
                                        .font(.caption)
                                        .foregroundColor(.secondary)
                                }
                            }
                            
                            Spacer()
                            
                            if language.code == localizationManager.appLanguage {
                                Image(systemName: "checkmark")
                                    .foregroundColor(.accentColor)
                            }
                        }
                    }
                }
            } footer: {
                Text("Changing language requires restarting the app.")
                    .foregroundColor(.secondary)
            }
        }
        .navigationTitle("Language")
        .alert("Restart Required", isPresented: $showRestartAlert) {
            Button("Restart Now") {
                if let language = pendingLanguage {
                    localizationManager.setLanguage(language)
                    // Force restart
                    exit(0)
                }
            }
            Button("Later", role: .cancel) {
                if let language = pendingLanguage {
                    localizationManager.setLanguage(language)
                }
            }
        } message: {
            Text("The app needs to restart for the language change to take full effect.")
        }
    }
    
    private func selectLanguage(_ code: String) {
        guard code != localizationManager.appLanguage else { return }
        pendingLanguage = code
        showRestartAlert = true
    }
}
```

### 4.10 Pluralization

**Requirement LOC-FR-012**: Handle pluralization correctly:

```swift
// In String Catalog, use stringsdict format:

// Example for "X seats"
"ride_seats_count" = {
    "NSStringLocalizedFormatKey" = "%#@seats@",
    "seats" = {
        "NSStringFormatSpecTypeKey" = "NSStringPluralRuleType",
        "NSStringFormatValueTypeKey" = "d",
        "zero" = "No seats",
        "one" = "1 seat",
        "other" = "%d seats"
    }
}

// Usage:
String(localized: "ride_seats_count", defaultValue: "\(count) seats")
```

### 4.11 RTL Support

**Requirement LOC-FR-013**: Prepare for right-to-left languages:

```swift
// SwiftUI handles most RTL automatically, but verify:
// 1. Use .leading/.trailing instead of .left/.right
// 2. Use layoutDirection environment value if needed

// Example:
@Environment(\.layoutDirection) var layoutDirection

HStack {
    if layoutDirection == .rightToLeft {
        // RTL specific layout if needed
    }
}
```

---

## 5. Translation Workflow

### 5.1 Export for Translation

1. Product â†’ Export Localizations
2. Choose output folder
3. Send .xcloc files to translators

### 5.2 Import Translations

1. Product â†’ Import Localizations
2. Select translated .xcloc file
3. Review changes
4. Build and test

### 5.3 Translation Guidelines for Translators

- Keep strings concise (UI space is limited)
- Preserve placeholders (%@, %d, etc.)
- Maintain tone (friendly, community-focused)
- Test in context when possible

---

## 6. Non-Goals (Out of Scope)

| Item | Reason |
|------|--------|
| User-generated content translation | Beyond scope |
| Server-side localization | Keep on client |
| Dynamic language switching | Requires restart |
| All languages at launch | Start with English + Spanish |

---

## 7. Testing Considerations

### Test Each Language

- All screens render correctly
- Text doesn't overflow
- Date/time formats correct
- Numbers formatted correctly
- Plurals work (0, 1, 2, many)

### Pseudolocalization

Use Xcode's pseudolanguage to catch issues:
1. Edit Scheme â†’ Run â†’ Options
2. Application Language â†’ select pseudo language
3. Test for string truncation, layout issues

---

## 8. Dependencies

### Depends On
- `prd-foundation-architecture.md`

### Affects
- All views
- All user-facing text
- Date/time displays
- Number displays

---

## 9. Success Metrics

| Metric | Target | How to Verify |
|--------|--------|---------------|
| All strings externalized | 0 hardcoded strings | Code review |
| Spanish fully translated | 100% coverage | Export report |
| Date formatting | Locale-correct | Test with different locales |
| Language switch | Works correctly | Change and verify |
| No layout breaks | All text fits | Visual QA |

---

## 10. Open Questions

| Question | Status | Decision |
|----------|--------|----------|
| Which languages first? | **English + Spanish** | Largest Seattle communities |
| Dynamic string reload? | **No** | Restart required |
| User content translation? | **No** | Out of scope |
| Translator source? | **TBD** | Community or professional |

---

*End of PRD: Localization*
