# PRD: Face ID / Touch ID (Biometric Authentication)

## Document Information
- **Feature Name**: Face ID / Touch ID
- **Phase**: 5 (Future Enhancements)
- **Dependencies**: `prd-foundation-architecture.md`, `prd-authentication.md`
- **Estimated Effort**: 0.5 weeks
- **Last Updated**: January 2025

---

## 1. Introduction/Overview

### What is this?
This document defines biometric authentication (Face ID and Touch ID) for the Naar's Cars iOS app. Biometrics allow users to quickly re-authenticate without entering their password.

### Why does this matter?
- **Convenience**: Unlock the app instantly with a glance or touch
- **Security**: Biometrics are more secure than passwords for frequent access
- **User expectation**: iOS users expect biometric options in modern apps
- **Session protection**: Re-verify identity for sensitive actions

### What problem does it solve?
- Eliminates repetitive password entry
- Provides quick access when returning to the app
- Secures the app if phone is shared or left unlocked
- Protects sensitive actions (like deleting account)

---

## 2. Goals

| Goal | Measurable Outcome |
|------|-------------------|
| Enable biometric unlock | Users can unlock app with Face ID/Touch ID |
| Graceful fallback | Passcode fallback when biometrics fail |
| Per-device setting | Users can enable/disable per device |
| Secure sensitive actions | Optional re-auth for critical actions |

---

## 3. User Stories

| ID | As a... | I want to... | So that... |
|----|---------|--------------|------------|
| BIO-01 | User | Unlock the app with Face ID | I don't need to enter my password |
| BIO-02 | User | Use Touch ID on older devices | I have the same convenience |
| BIO-03 | User | Fall back to passcode | I can still access if biometrics fail |
| BIO-04 | User | Enable/disable biometrics | I control my security preferences |
| BIO-05 | User | Re-authenticate for sensitive actions | My account is protected |

---

## 4. Functional Requirements

### 4.1 Biometric Service

**Requirement BIO-FR-001**: Create BiometricService using LocalAuthentication:

```swift
// Core/Services/BiometricService.swift
import LocalAuthentication

/// Service for handling biometric authentication (Face ID / Touch ID)
final class BiometricService {
    static let shared = BiometricService()
    private init() {}
    
    // MARK: - Availability
    
    /// Check if biometrics are available on this device
    var isBiometricsAvailable: Bool {
        let context = LAContext()
        var error: NSError?
        return context.canEvaluatePolicy(.deviceOwnerAuthenticationWithBiometrics, error: &error)
    }
    
    /// Check if any authentication (biometrics or passcode) is available
    var isAuthenticationAvailable: Bool {
        let context = LAContext()
        var error: NSError?
        return context.canEvaluatePolicy(.deviceOwnerAuthentication, error: &error)
    }
    
    /// Get the type of biometrics available
    var biometricType: BiometricType {
        let context = LAContext()
        var error: NSError?
        
        guard context.canEvaluatePolicy(.deviceOwnerAuthenticationWithBiometrics, error: &error) else {
            return .none
        }
        
        switch context.biometryType {
        case .faceID:
            return .faceID
        case .touchID:
            return .touchID
        case .opticID:
            return .opticID
        case .none:
            return .none
        @unknown default:
            return .none
        }
    }
    
    // MARK: - Authentication
    
    /// Authenticate using biometrics with passcode fallback
    func authenticate(reason: String) async throws -> Bool {
        let context = LAContext()
        context.localizedFallbackTitle = "Use Passcode"
        context.localizedCancelTitle = "Cancel"
        
        do {
            let success = try await context.evaluatePolicy(
                .deviceOwnerAuthentication,  // Allows passcode fallback
                localizedReason: reason
            )
            return success
        } catch let error as LAError {
            switch error.code {
            case .userCancel, .appCancel:
                throw BiometricError.cancelled
            case .userFallback:
                throw BiometricError.userFallback
            case .biometryNotAvailable:
                throw BiometricError.notAvailable
            case .biometryNotEnrolled:
                throw BiometricError.notEnrolled
            case .biometryLockout:
                throw BiometricError.lockout
            case .authenticationFailed:
                throw BiometricError.failed
            default:
                throw BiometricError.unknown(error.localizedDescription)
            }
        }
    }
    
    /// Authenticate using biometrics only (no passcode fallback)
    func authenticateBiometricsOnly(reason: String) async throws -> Bool {
        let context = LAContext()
        context.localizedFallbackTitle = ""  // Hide fallback button
        
        let success = try await context.evaluatePolicy(
            .deviceOwnerAuthenticationWithBiometrics,
            localizedReason: reason
        )
        return success
    }
}

// MARK: - Types

enum BiometricType {
    case none
    case touchID
    case faceID
    case opticID  // Vision Pro
    
    var displayName: String {
        switch self {
        case .none: return "Passcode"
        case .touchID: return "Touch ID"
        case .faceID: return "Face ID"
        case .opticID: return "Optic ID"
        }
    }
    
    var iconName: String {
        switch self {
        case .none: return "lock.fill"
        case .touchID: return "touchid"
        case .faceID: return "faceid"
        case .opticID: return "opticid"
        }
    }
}

enum BiometricError: LocalizedError {
    case cancelled
    case userFallback
    case notAvailable
    case notEnrolled
    case lockout
    case failed
    case unknown(String)
    
    var errorDescription: String? {
        switch self {
        case .cancelled:
            return "Authentication was cancelled."
        case .userFallback:
            return "User chose to use passcode."
        case .notAvailable:
            return "Biometric authentication is not available on this device."
        case .notEnrolled:
            return "No biometric data is enrolled. Please set up Face ID or Touch ID in Settings."
        case .lockout:
            return "Biometric authentication is locked. Please use your passcode."
        case .failed:
            return "Authentication failed. Please try again."
        case .unknown(let message):
            return message
        }
    }
}
```

### 4.2 User Preferences

**Requirement BIO-FR-002**: Store biometric preference per device:

```swift
// Core/Utilities/BiometricPreferences.swift
import Foundation

/// Manages user preferences for biometric authentication
final class BiometricPreferences {
    private let userDefaults = UserDefaults.standard
    
    private enum Keys {
        static let biometricsEnabled = "biometrics_enabled"
        static let requireBiometricsOnLaunch = "require_biometrics_on_launch"
        static let lastAuthenticatedDate = "last_authenticated_date"
    }
    
    static let shared = BiometricPreferences()
    private init() {}
    
    /// Whether the user has enabled biometric authentication
    var isBiometricsEnabled: Bool {
        get { userDefaults.bool(forKey: Keys.biometricsEnabled) }
        set { userDefaults.set(newValue, forKey: Keys.biometricsEnabled) }
    }
    
    /// Whether to require biometrics when app launches
    var requireBiometricsOnLaunch: Bool {
        get { userDefaults.bool(forKey: Keys.requireBiometricsOnLaunch) }
        set { userDefaults.set(newValue, forKey: Keys.requireBiometricsOnLaunch) }
    }
    
    /// When the user last successfully authenticated
    var lastAuthenticatedDate: Date? {
        get { userDefaults.object(forKey: Keys.lastAuthenticatedDate) as? Date }
        set { userDefaults.set(newValue, forKey: Keys.lastAuthenticatedDate) }
    }
    
    /// Check if re-authentication is needed (e.g., after 5 minutes in background)
    func needsReauthentication(timeout: TimeInterval = 300) -> Bool {
        guard requireBiometricsOnLaunch else { return false }
        guard let lastAuth = lastAuthenticatedDate else { return true }
        return Date().timeIntervalSince(lastAuth) > timeout
    }
    
    /// Record successful authentication
    func recordAuthentication() {
        lastAuthenticatedDate = Date()
    }
}
```

### 4.3 App Lock Screen

**Requirement BIO-FR-003**: Show lock screen when returning to app:

```swift
// Features/Authentication/Views/AppLockView.swift
import SwiftUI

struct AppLockView: View {
    @State private var isAuthenticating = false
    @State private var error: BiometricError?
    @State private var showError = false
    
    let onUnlock: () -> Void
    let onCancel: (() -> Void)?
    
    private let biometricService = BiometricService.shared
    
    var body: some View {
        VStack(spacing: 32) {
            Spacer()
            
            // App logo
            Image("AppLogo")
                .resizable()
                .scaledToFit()
                .frame(width: 100, height: 100)
            
            Text("Naar's Cars")
                .font(.title)
                .fontWeight(.bold)
            
            Text("Unlock to continue")
                .foregroundColor(.secondary)
            
            Spacer()
            
            // Biometric button
            Button {
                Task {
                    await authenticate()
                }
            } label: {
                VStack(spacing: 8) {
                    Image(systemName: biometricService.biometricType.iconName)
                        .font(.system(size: 48))
                    Text("Unlock with \(biometricService.biometricType.displayName)")
                        .font(.headline)
                }
                .foregroundColor(.accentColor)
            }
            .disabled(isAuthenticating)
            
            if let onCancel {
                Button("Cancel") {
                    onCancel()
                }
                .foregroundColor(.secondary)
            }
            
            Spacer()
        }
        .padding()
        .alert("Authentication Failed", isPresented: $showError) {
            Button("Try Again") {
                Task { await authenticate() }
            }
            Button("Cancel", role: .cancel) {}
        } message: {
            Text(error?.errorDescription ?? "Please try again.")
        }
        .task {
            // Automatically prompt on appear
            await authenticate()
        }
    }
    
    private func authenticate() async {
        isAuthenticating = true
        error = nil
        
        do {
            let success = try await biometricService.authenticate(
                reason: "Unlock Naar's Cars"
            )
            
            if success {
                BiometricPreferences.shared.recordAuthentication()
                onUnlock()
            }
        } catch let biometricError as BiometricError {
            if case .cancelled = biometricError {
                // User cancelled - don't show error
            } else {
                self.error = biometricError
                self.showError = true
            }
        } catch {
            self.error = .unknown(error.localizedDescription)
            self.showError = true
        }
        
        isAuthenticating = false
    }
}
```

### 4.4 App Lock Integration

**Requirement BIO-FR-004**: Integrate lock screen into app lifecycle:

```swift
// App/ContentView.swift
struct ContentView: View {
    @EnvironmentObject var appState: AppState
    @Environment(\.scenePhase) var scenePhase
    
    @State private var isLocked = false
    @State private var lastBackgroundDate: Date?
    
    private let lockTimeout: TimeInterval = 300  // 5 minutes
    
    var body: some View {
        ZStack {
            // Main app content
            Group {
                switch appState.authState {
                case .loading:
                    LoadingView()
                case .unauthenticated:
                    AuthenticationFlow()
                case .pendingApproval:
                    PendingApprovalView()
                case .authenticated:
                    MainTabView()
                }
            }
            .blur(radius: isLocked ? 20 : 0)
            
            // Lock screen overlay
            if isLocked {
                AppLockView(onUnlock: {
                    withAnimation {
                        isLocked = false
                    }
                }, onCancel: nil)
                .transition(.opacity)
            }
        }
        .onChange(of: scenePhase) { oldPhase, newPhase in
            handleScenePhaseChange(from: oldPhase, to: newPhase)
        }
    }
    
    private func handleScenePhaseChange(from oldPhase: ScenePhase, to newPhase: ScenePhase) {
        guard BiometricPreferences.shared.isBiometricsEnabled,
              BiometricPreferences.shared.requireBiometricsOnLaunch,
              appState.authState == .authenticated else {
            return
        }
        
        switch newPhase {
        case .background:
            lastBackgroundDate = Date()
            
        case .active:
            if let lastBackground = lastBackgroundDate,
               Date().timeIntervalSince(lastBackground) > lockTimeout {
                isLocked = true
            }
            
        case .inactive:
            break
            
        @unknown default:
            break
        }
    }
}
```

### 4.5 Settings UI

**Requirement BIO-FR-005**: Biometric settings in profile/settings:

```
â”Œâ”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”
â”‚   â† Security Settings               â”‚
â”œâ”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”¤
â”‚                                     â”‚
â”‚   BIOMETRIC AUTHENTICATION          â”‚
â”‚   â”Œâ”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”   â”‚
â”‚   â”‚ Use Face ID          [ON]   â”‚   â”‚
â”‚   â”‚ Quickly unlock the app      â”‚   â”‚
â”‚   â”œâ”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”¤   â”‚
â”‚   â”‚ Require on Launch    [ON]   â”‚   â”‚
â”‚   â”‚ Lock when returning to app  â”‚   â”‚
â”‚   â””â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”˜   â”‚
â”‚                                     â”‚
â”‚   Lock after 5 minutes in           â”‚
â”‚   background                        â”‚
â”‚                                     â”‚
â”œâ”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”¤
â”‚   SENSITIVE ACTIONS                 â”‚
â”‚   â”Œâ”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”   â”‚
â”‚   â”‚ Confirm Claiming     [OFF]  â”‚   â”‚
â”‚   â”‚ Require Face ID to claim    â”‚   â”‚
â”‚   â””â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”˜   â”‚
â”‚                                     â”‚
â””â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”˜
```

**Requirement BIO-FR-006**: Settings view implementation:

```swift
// Features/Profile/Views/SecuritySettingsView.swift
struct SecuritySettingsView: View {
    @State private var biometricsEnabled = BiometricPreferences.shared.isBiometricsEnabled
    @State private var requireOnLaunch = BiometricPreferences.shared.requireBiometricsOnLaunch
    @State private var showEnablePrompt = false
    
    private let biometricService = BiometricService.shared
    
    var body: some View {
        Form {
            Section {
                Toggle(isOn: $biometricsEnabled) {
                    Label {
                        VStack(alignment: .leading) {
                            Text("Use \(biometricService.biometricType.displayName)")
                            Text("Quickly unlock the app")
                                .font(.caption)
                                .foregroundColor(.secondary)
                        }
                    } icon: {
                        Image(systemName: biometricService.biometricType.iconName)
                    }
                }
                .onChange(of: biometricsEnabled) { _, newValue in
                    handleBiometricsToggle(newValue)
                }
                
                if biometricsEnabled {
                    Toggle(isOn: $requireOnLaunch) {
                        VStack(alignment: .leading) {
                            Text("Require on Launch")
                            Text("Lock when returning to app")
                                .font(.caption)
                                .foregroundColor(.secondary)
                        }
                    }
                    .onChange(of: requireOnLaunch) { _, newValue in
                        BiometricPreferences.shared.requireBiometricsOnLaunch = newValue
                    }
                }
            } header: {
                Text("Biometric Authentication")
            } footer: {
                if biometricsEnabled && requireOnLaunch {
                    Text("App will lock after 5 minutes in background")
                }
            }
        }
        .navigationTitle("Security")
        .disabled(!biometricService.isBiometricsAvailable)
        .overlay {
            if !biometricService.isBiometricsAvailable {
                VStack {
                    Text("Biometric authentication is not available on this device")
                        .foregroundColor(.secondary)
                        .multilineTextAlignment(.center)
                        .padding()
                }
            }
        }
    }
    
    private func handleBiometricsToggle(_ enabled: Bool) {
        if enabled {
            // Verify biometrics before enabling
            Task {
                do {
                    let success = try await biometricService.authenticate(
                        reason: "Verify your identity to enable \(biometricService.biometricType.displayName)"
                    )
                    
                    if success {
                        BiometricPreferences.shared.isBiometricsEnabled = true
                        BiometricPreferences.shared.recordAuthentication()
                    } else {
                        biometricsEnabled = false
                    }
                } catch {
                    biometricsEnabled = false
                }
            }
        } else {
            BiometricPreferences.shared.isBiometricsEnabled = false
            BiometricPreferences.shared.requireBiometricsOnLaunch = false
            requireOnLaunch = false
        }
    }
}
```

### 4.6 Info.plist Configuration

**Requirement BIO-FR-007**: Add Face ID usage description:

```xml
<!-- Info.plist -->
<key>NSFaceIDUsageDescription</key>
<string>Naar's Cars uses Face ID to quickly and securely unlock the app.</string>
```

---

## 5. Non-Goals (Out of Scope)

| Item | Reason |
|------|--------|
| Storing credentials in Keychain | Using Supabase session management |
| Biometric for every action | Only app unlock and optional sensitive actions |
| Custom lock timeout | Fixed 5-minute timeout for simplicity |
| Remote biometric settings | Per-device only |

---

## 6. Design Considerations

### iOS Human Interface Guidelines

- Use system biometric icons (`faceid`, `touchid`)
- Don't assume which biometric is available
- Provide graceful fallback to passcode
- Don't require biometrics (make it optional)

### Accessibility

- Passcode fallback is always available
- VoiceOver announces biometric type correctly
- Don't disable authentication for any reason

---

## 7. Technical Considerations

### Required Framework
- `LocalAuthentication`

### Privacy
- Biometric data never leaves the device
- We only receive success/failure result
- No biometric data is stored by our app

### Testing
- Test on devices with Face ID and Touch ID
- Test passcode fallback
- Test biometric lockout scenario
- Test background timeout behavior

---

## 8. Dependencies

### Depends On
- `prd-foundation-architecture.md`
- `prd-authentication.md`

---

## 9. Success Metrics

| Metric | Target | How to Verify |
|--------|--------|---------------|
| Face ID unlock | Works on Face ID devices | Test on iPhone X+ |
| Touch ID unlock | Works on Touch ID devices | Test on SE/older |
| Passcode fallback | Works when biometrics fail | Fail biometrics 5x |
| Background lock | Locks after timeout | Background for 5+ min |
| Settings toggle | Enable/disable works | Toggle and verify |

---

## 10. Open Questions

| Question | Status | Decision |
|----------|--------|----------|
| Configurable timeout? | **No** | Fixed 5 minutes for simplicity |
| Biometric for claiming? | **Optional** | Available but off by default |
| Remember across reinstalls? | **No** | User must re-enable |

---

*End of PRD: Face ID / Touch ID*
