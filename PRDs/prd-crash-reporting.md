# PRD: Crash Reporting

## Document Information
- **Feature Name**: Crash Reporting
- **Phase**: 5 (Future Enhancements - but recommended for launch)
- **Dependencies**: `prd-foundation-architecture.md`
- **Estimated Effort**: 0.5 weeks
- **Last Updated**: January 2025

---

## 1. Introduction/Overview

### What is this?
This document defines crash reporting functionality for the Naar's Cars iOS app using Firebase Crashlytics. Crash reporting automatically captures and reports app crashes and errors to help developers identify and fix issues.

### Why does this matter?
- **Visibility**: Know when and why the app crashes
- **Prioritization**: See which crashes affect the most users
- **Context**: Get stack traces, device info, and user state
- **Proactive fixes**: Fix crashes before users complain
- **Quality**: Maintain high app store ratings

### What problem does it solve?
- Crashes happen silently without reports
- Users don't always report issues
- Hard to reproduce crashes without context
- No insight into crash frequency or patterns
- Can't prioritize fixes without impact data

---

## 2. Goals

| Goal | Measurable Outcome |
|------|-------------------|
| Automatic crash capture | All crashes reported |
| Crash-free rate tracking | Dashboard shows percentage |
| Non-fatal error logging | Log important errors |
| User context | Know which user experienced crash |
| Breadcrumbs | See events leading to crash |

---

## 3. User Stories

| ID | As a... | I want to... | So that... |
|----|---------|--------------|------------|
| CRASH-01 | Developer | See crash reports | I know what's breaking |
| CRASH-02 | Developer | See stack traces | I can locate the bug |
| CRASH-03 | Developer | See device info | I can reproduce the issue |
| CRASH-04 | Developer | See user count per crash | I prioritize high-impact fixes |
| CRASH-05 | Developer | Log non-fatal errors | I catch issues before they crash |
| CRASH-06 | Developer | See crash trends | I know if releases improve stability |

---

## 4. Functional Requirements

### 4.1 Firebase Setup

**Requirement CRASH-FR-001**: Add Firebase SDK via Swift Package Manager:

```swift
// Package URL: https://github.com/firebase/firebase-ios-sdk
// Add FirebaseCrashlytics product
```

**Requirement CRASH-FR-002**: Configure Firebase in the app:

1. Create Firebase project at console.firebase.google.com
2. Add iOS app with bundle identifier
3. Download `GoogleService-Info.plist`
4. Add to Xcode project (ensure target membership)

**Requirement CRASH-FR-003**: Initialize Firebase on launch:

```swift
// App/NaarsCarsApp.swift
import Firebase

@main
struct NaarsCarsApp: App {
    init() {
        FirebaseApp.configure()
    }
    
    var body: some Scene {
        WindowGroup {
            ContentView()
        }
    }
}
```

### 4.2 Crash Service

**Requirement CRASH-FR-004**: Create CrashService wrapper:

```swift
// Core/Services/CrashService.swift
import Foundation
import FirebaseCrashlytics

/// Service for crash reporting and error logging
final class CrashService {
    static let shared = CrashService()
    private let crashlytics = Crashlytics.crashlytics()
    
    private init() {}
    
    // MARK: - User Identification
    
    /// Set the current user ID for crash reports
    func setUserId(_ userId: String?) {
        if let userId = userId {
            crashlytics.setUserID(userId)
            Log.networkInfo("Crashlytics user ID set: \(userId.prefix(8))...")
        } else {
            crashlytics.setUserID("")
        }
    }
    
    /// Set custom key-value pairs for crash context
    func setCustomValue(_ value: Any, forKey key: String) {
        crashlytics.setCustomValue(value, forKey: key)
    }
    
    // MARK: - Breadcrumbs
    
    /// Log a breadcrumb event (visible in crash reports)
    func log(_ message: String) {
        crashlytics.log(message)
    }
    
    /// Log screen view for navigation context
    func logScreenView(_ screenName: String) {
        crashlytics.log("Screen: \(screenName)")
    }
    
    /// Log user action for interaction context
    func logAction(_ action: String, parameters: [String: Any]? = nil) {
        var message = "Action: \(action)"
        if let params = parameters {
            message += " - \(params)"
        }
        crashlytics.log(message)
    }
    
    // MARK: - Non-Fatal Errors
    
    /// Record a non-fatal error (app didn't crash but something went wrong)
    func recordError(_ error: Error, userInfo: [String: Any]? = nil) {
        let nsError = error as NSError
        
        var info = userInfo ?? [:]
        info["errorDescription"] = error.localizedDescription
        
        crashlytics.record(error: nsError, userInfo: info)
        
        Log.networkError("Non-fatal error recorded: \(error.localizedDescription)")
    }
    
    /// Record an error with custom domain and code
    func recordError(
        domain: String,
        code: Int,
        message: String,
        userInfo: [String: Any]? = nil
    ) {
        var info = userInfo ?? [:]
        info[NSLocalizedDescriptionKey] = message
        
        let error = NSError(domain: domain, code: code, userInfo: info)
        crashlytics.record(error: error)
    }
    
    // MARK: - Crash Testing
    
    /// Force a test crash (DEBUG only)
    func forceCrash() {
        #if DEBUG
        fatalError("Test crash triggered")
        #endif
    }
    
    // MARK: - Opt-out (if needed)
    
    /// Enable or disable crash collection
    func setCrashlyticsCollectionEnabled(_ enabled: Bool) {
        crashlytics.setCrashlyticsCollectionEnabled(enabled)
    }
}
```

### 4.3 Integration Points

**Requirement CRASH-FR-005**: Set user ID on authentication:

```swift
// In AuthService after successful login
func handleSuccessfulLogin(userId: UUID) {
    // ... existing code ...
    
    // Set crash reporting user ID
    CrashService.shared.setUserId(userId.uuidString)
}

// On logout
func handleLogout() {
    // ... existing code ...
    
    // Clear crash reporting user ID
    CrashService.shared.setUserId(nil)
}
```

**Requirement CRASH-FR-006**: Log screen views:

```swift
// Add to each major view's onAppear
.onAppear {
    CrashService.shared.logScreenView("RideDetail")
}

// Or use a ViewModifier
struct ScreenTrackingModifier: ViewModifier {
    let screenName: String
    
    func body(content: Content) -> some View {
        content.onAppear {
            CrashService.shared.logScreenView(screenName)
        }
    }
}

extension View {
    func trackScreen(_ name: String) -> some View {
        modifier(ScreenTrackingModifier(screenName: name))
    }
}

// Usage
RideDetailView(ride: ride)
    .trackScreen("RideDetail")
```

**Requirement CRASH-FR-007**: Log important actions:

```swift
// Claiming a request
CrashService.shared.logAction("claim_ride", parameters: [
    "ride_id": rideId.uuidString,
    "status": ride.status.rawValue
])

// Sending a message
CrashService.shared.logAction("send_message", parameters: [
    "conversation_id": conversationId.uuidString
])

// Creating a request
CrashService.shared.logAction("create_ride", parameters: [
    "has_gift": gift != nil
])
```

**Requirement CRASH-FR-008**: Record non-fatal errors:

```swift
// In network calls
func fetchRides() async {
    do {
        let rides = try await RideService.shared.fetchRides()
        // success
    } catch {
        // Record non-fatal error
        CrashService.shared.recordError(error, userInfo: [
            "operation": "fetchRides",
            "filter": "open"
        ])
        
        // Still show error to user
        self.error = error
    }
}

// For specific error types
catch let error as DecodingError {
    CrashService.shared.recordError(
        domain: "com.naarscars.decoding",
        code: 1001,
        message: "Failed to decode rides response",
        userInfo: ["error": String(describing: error)]
    )
}
```

### 4.4 Custom Keys for Context

**Requirement CRASH-FR-009**: Set custom context values:

```swift
// Set app state context
CrashService.shared.setCustomValue(appState.authState.rawValue, forKey: "auth_state")
CrashService.shared.setCustomValue(appState.currentUser?.isAdmin ?? false, forKey: "is_admin")

// Set feature flags
CrashService.shared.setCustomValue(true, forKey: "feature_map_view")

// Set connection state
CrashService.shared.setCustomValue(networkMonitor.isConnected, forKey: "has_network")
```

### 4.5 Build Configuration

**Requirement CRASH-FR-010**: Upload dSYM files for symbolication:

Add to Build Phases in Xcode:
```bash
# Run Script Phase (after "Embed Frameworks")
"${BUILD_DIR%/Build/*}/SourcePackages/checkouts/firebase-ios-sdk/Crashlytics/run"
```

Or use Fastlane:
```ruby
# Fastfile
lane :upload_symbols do
  upload_symbols_to_crashlytics(
    gsp_path: "./GoogleService-Info.plist"
  )
end
```

### 4.6 Privacy Considerations

**Requirement CRASH-FR-011**: Respect user privacy:

```swift
// Optional: Allow users to opt out
struct PrivacySettingsView: View {
    @AppStorage("crash_reporting_enabled") var crashReportingEnabled = true
    
    var body: some View {
        Toggle("Share Crash Reports", isOn: $crashReportingEnabled)
            .onChange(of: crashReportingEnabled) { _, newValue in
                CrashService.shared.setCrashlyticsCollectionEnabled(newValue)
            }
    }
}
```

**Requirement CRASH-FR-012**: Don't log sensitive data:

```swift
// NEVER log:
// - Passwords
// - Full email addresses
// - Phone numbers
// - Addresses
// - Personal messages

// OK to log:
// - User IDs (anonymized)
// - Screen names
// - Action types
// - Error codes
// - Device info
```

### 4.7 Dashboard Usage

**Requirement CRASH-FR-013**: Monitor these metrics in Firebase Console:

| Metric | Description | Target |
|--------|-------------|--------|
| Crash-free users | % of users without crashes | >99.5% |
| Crash-free sessions | % of sessions without crashes | >99.9% |
| Top crashes | Most impactful crashes | Fix top 3 weekly |
| Trends | Crash rate over time | Decreasing |
| Velocity alerts | Sudden spike detection | No alerts |

---

## 5. Error Categories

### 5.1 Error Domains

Define consistent error domains:

```swift
enum CrashDomain {
    static let network = "com.naarscars.network"
    static let auth = "com.naarscars.auth"
    static let database = "com.naarscars.database"
    static let parsing = "com.naarscars.parsing"
    static let storage = "com.naarscars.storage"
    static let ui = "com.naarscars.ui"
}
```

### 5.2 Error Codes

```swift
enum CrashErrorCode {
    // Network: 1000-1999
    static let networkTimeout = 1001
    static let networkUnreachable = 1002
    static let networkUnauthorized = 1003
    
    // Auth: 2000-2999
    static let authInvalidToken = 2001
    static let authExpiredSession = 2002
    static let authInvalidCredentials = 2003
    
    // Database: 3000-3999
    static let dbQueryFailed = 3001
    static let dbInsertFailed = 3002
    static let dbNotFound = 3003
    
    // Parsing: 4000-4999
    static let parseDecodingFailed = 4001
    static let parseInvalidFormat = 4002
    
    // Storage: 5000-5999
    static let storageUploadFailed = 5001
    static let storageDownloadFailed = 5002
}
```

---

## 6. Non-Goals (Out of Scope)

| Item | Reason |
|------|--------|
| Analytics | Separate feature (Firebase Analytics) |
| Performance monitoring | Separate feature (Firebase Performance) |
| Remote config | Separate feature |
| A/B testing | Separate feature |
| User feedback | Separate in-app feature |

---

## 7. Testing

### 7.1 Test Crash Reporting

```swift
#if DEBUG
// Add to debug menu or shake gesture
Button("Test Crash") {
    CrashService.shared.forceCrash()
}

Button("Test Non-Fatal") {
    CrashService.shared.recordError(
        domain: CrashDomain.ui,
        code: 9999,
        message: "Test non-fatal error"
    )
}
#endif
```

### 7.2 Verify Setup

1. Archive and distribute app (crashes aren't reported in debug)
2. Trigger a crash
3. Relaunch app (crash is uploaded on next launch)
4. Check Firebase Console for crash report
5. Verify dSYM symbols resolve stack trace

---

## 8. Dependencies

### Depends On
- `prd-foundation-architecture.md`

### External Dependencies
- Firebase SDK (FirebaseCrashlytics)
- GoogleService-Info.plist
- Firebase Console account

### Costs
- **Free tier**: Unlimited crash reporting
- No per-event charges

---

## 9. Implementation Checklist

- [ ] Create Firebase project
- [ ] Add iOS app to Firebase
- [ ] Download GoogleService-Info.plist
- [ ] Add Firebase SDK via SPM
- [ ] Initialize Firebase in app
- [ ] Create CrashService wrapper
- [ ] Add dSYM upload script
- [ ] Set user ID on login/logout
- [ ] Add screen tracking
- [ ] Add action logging
- [ ] Record non-fatal errors in catch blocks
- [ ] Test crash in release build
- [ ] Verify crash appears in console
- [ ] Set up velocity alerts

---

## 10. Success Metrics

| Metric | Target | How to Verify |
|--------|--------|---------------|
| Crashes captured | 100% of crashes | Test crash â†’ see in console |
| Symbolication | Stack traces readable | Check crash details |
| User context | User ID visible | Check crash user ID |
| Breadcrumbs | Events visible | Check crash logs |
| Non-fatals | Logged correctly | Trigger error â†’ see in console |

---

## 11. Open Questions

| Question | Status | Decision |
|----------|--------|----------|
| User opt-out option? | **Yes** | Add to privacy settings |
| Include with launch? | **Recommended** | Critical for quality |
| Analytics too? | **Future** | Separate PRD if needed |

---

*End of PRD: Crash Reporting*
