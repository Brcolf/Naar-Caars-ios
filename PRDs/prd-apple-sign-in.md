# PRD: Apple Sign-In

## Document Information
- **Feature Name**: Apple Sign-In (Social Login)
- **Phase**: 5 (Future Enhancements)
- **Dependencies**: `prd-foundation-architecture.md`, `prd-authentication.md`
- **Estimated Effort**: 1 week
- **Last Updated**: January 2025

---

## 1. Introduction/Overview

### What is this?
This document defines Apple Sign-In integration for the Naar's Cars iOS app. Apple Sign-In provides a fast, secure, and privacy-focused way for users to authenticate.

### Why does this matter?
- **Required by Apple**: Apps that offer third-party login MUST offer Apple Sign-In
- **User convenience**: One-tap authentication without remembering passwords
- **Privacy**: Users can hide their real email with Apple's relay service
- **Trust**: Apple's authentication is highly secure with biometric verification

### What problem does it solve?
- Reduces friction during signup/login
- Eliminates forgotten password issues
- Provides a trusted, familiar authentication method
- Increases signup conversion rates

---

## 2. Goals

| Goal | Measurable Outcome |
|------|-------------------|
| Users can sign up with Apple | Account created via Apple ID |
| Users can log in with Apple | Session established |
| Handle email hiding | Relay emails work correctly |
| Link to existing accounts | Optional account linking |
| Maintain invite code requirement | Apple users still need invite |

---

## 3. User Stories

| ID | As a... | I want to... | So that... |
|----|---------|--------------|------------|
| APPLE-01 | New user | Sign up using my Apple ID | I don't need to create a password |
| APPLE-02 | New user | Choose to hide my email | My privacy is protected |
| APPLE-03 | Existing user | Link Apple ID to my account | I can use Apple Sign-In for login |
| APPLE-04 | User | Log in with Face ID/Touch ID | Authentication is instant |
| APPLE-05 | User | See my Apple-linked status | I know how I'm authenticated |

---

## 4. Functional Requirements

### 4.1 Apple Sign-In Configuration

**Requirement APPLE-FR-001**: Enable Sign in with Apple capability in Xcode:
1. Select project in navigator
2. Select target â†’ Signing & Capabilities
3. Click "+ Capability"
4. Add "Sign in with Apple"

**Requirement APPLE-FR-002**: Configure Supabase for Apple OAuth:
1. In Supabase dashboard â†’ Authentication â†’ Providers
2. Enable Apple provider
3. Add Service ID, Key ID, Team ID, and private key

### 4.2 Sign-In Flow

**Requirement APPLE-FR-003**: Apple Sign-In button placement:

```
â”Œâ”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”
â”‚         [Naar's Cars Logo]          â”‚
â”‚                                     â”‚
â”‚   Welcome Back, Carbardian!         â”‚
â”‚                                     â”‚
â”‚   â”Œâ”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”   â”‚
â”‚   â”‚  Email                      â”‚   â”‚
â”‚   â””â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”˜   â”‚
â”‚   â”Œâ”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”   â”‚
â”‚   â”‚  Password                   â”‚   â”‚
â”‚   â””â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”˜   â”‚
â”‚                                     â”‚
â”‚   â”Œâ”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”   â”‚
â”‚   â”‚         Log In              â”‚   â”‚
â”‚   â””â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”˜   â”‚
â”‚                                     â”‚
â”‚   â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€ or â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€   â”‚
â”‚                                     â”‚
â”‚   â”Œâ”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”   â”‚
â”‚   â”‚  Sign in with Apple       â”‚   â”‚
â”‚   â””â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”˜   â”‚
â”‚                                     â”‚
â”‚   Don't have an account? Sign Up    â”‚
â”‚                                     â”‚
â””â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”˜
```

**Requirement APPLE-FR-004**: Use Apple's official `SignInWithAppleButton`:

```swift
// Features/Authentication/Views/LoginView.swift
import AuthenticationServices

struct AppleSignInButton: View {
    @Environment(\.colorScheme) var colorScheme
    let onRequest: (ASAuthorizationAppleIDRequest) -> Void
    let onCompletion: (Result<ASAuthorization, Error>) -> Void
    
    var body: some View {
        SignInWithAppleButton(
            onRequest: onRequest,
            onCompletion: onCompletion
        )
        .signInWithAppleButtonStyle(
            colorScheme == .dark ? .white : .black
        )
        .frame(height: 50)
        .cornerRadius(12)
    }
}
```

### 4.3 Authentication Service Extension

**Requirement APPLE-FR-005**: Extend AuthService for Apple Sign-In:

```swift
// Core/Services/AuthService.swift
import AuthenticationServices

extension AuthService {
    
    /// Handle Apple Sign-In for new users (signup flow)
    func signUpWithApple(
        credential: ASAuthorizationAppleIDCredential,
        inviteCode: String
    ) async throws {
        // 1. Validate invite code first
        let invite = try await validateInviteCode(inviteCode)
        
        // 2. Get identity token
        guard let identityTokenData = credential.identityToken,
              let identityToken = String(data: identityTokenData, encoding: .utf8) else {
            throw AppError.unknown("Failed to get Apple identity token")
        }
        
        // 3. Get user info
        let email = credential.email ?? ""  // May be nil on subsequent logins
        let fullName = [
            credential.fullName?.givenName,
            credential.fullName?.familyName
        ].compactMap { $0 }.joined(separator: " ")
        
        // 4. Sign in with Supabase using Apple token
        let session = try await supabase.auth.signInWithIdToken(
            credentials: .init(
                provider: .apple,
                idToken: identityToken
            )
        )
        
        guard let userId = session.user?.id else {
            throw AppError.unknown("Failed to create user account")
        }
        
        // 5. Create or update profile
        try await createOrUpdateAppleProfile(
            userId: userId,
            email: email,
            name: fullName,
            invitedBy: invite.createdBy
        )
        
        // 6. Mark invite code as used
        try await supabase
            .from("invite_codes")
            .update(["used_by": userId.uuidString])
            .eq("id", invite.id.uuidString)
            .execute()
        
        // 7. Update local state
        self.currentUserId = userId
        
        Log.authInfo("User signed up with Apple: \(userId)")
    }
    
    /// Handle Apple Sign-In for existing users (login flow)
    func logInWithApple(credential: ASAuthorizationAppleIDCredential) async throws {
        guard let identityTokenData = credential.identityToken,
              let identityToken = String(data: identityTokenData, encoding: .utf8) else {
            throw AppError.unknown("Failed to get Apple identity token")
        }
        
        let session = try await supabase.auth.signInWithIdToken(
            credentials: .init(
                provider: .apple,
                idToken: identityToken
            )
        )
        
        guard let userId = session.user?.id else {
            throw AppError.invalidCredentials
        }
        
        // Fetch profile
        let profile = try await fetchCurrentProfile()
        
        self.currentUserId = userId
        self.currentProfile = profile
        
        Log.authInfo("User logged in with Apple: \(userId)")
    }
    
    /// Create or update profile for Apple user
    private func createOrUpdateAppleProfile(
        userId: UUID,
        email: String,
        name: String,
        invitedBy: UUID
    ) async throws {
        // Check if profile exists
        let existing = try? await supabase
            .from("profiles")
            .select()
            .eq("id", userId.uuidString)
            .single()
            .execute()
        
        if existing != nil {
            // Update existing profile if name was provided
            if !name.isEmpty {
                try await supabase
                    .from("profiles")
                    .update(["name": name])
                    .eq("id", userId.uuidString)
                    .execute()
            }
        } else {
            // Create new profile
            let profileName = name.isEmpty ? "Apple User" : name
            let profileEmail = email.isEmpty ? "\(userId.uuidString)@privaterelay.appleid.com" : email
            
            try await supabase
                .from("profiles")
                .insert([
                    "id": userId.uuidString,
                    "name": profileName,
                    "email": profileEmail,
                    "invited_by": invitedBy.uuidString,
                    "is_admin": false,
                    "approved": false
                ])
                .execute()
        }
    }
}
```

### 4.4 Signup Flow with Apple

**Requirement APPLE-FR-006**: Apple signup still requires invite code:

```
Step 1: Enter Invite Code (same as email signup)
â”Œâ”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”
â”‚   Enter your invite code            â”‚
â”‚   â”Œâ”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”   â”‚
â”‚   â”‚  Invite Code                â”‚   â”‚
â”‚   â””â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”˜   â”‚
â”‚   [Verify Code]                     â”‚
â””â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”˜

Step 2: Choose signup method
â”Œâ”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”
â”‚   How would you like to sign up?    â”‚
â”‚                                     â”‚
â”‚   â”Œâ”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”   â”‚
â”‚   â”‚  Sign in with Apple       â”‚   â”‚
â”‚   â””â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”˜   â”‚
â”‚                                     â”‚
â”‚   â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€ or â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€   â”‚
â”‚                                     â”‚
â”‚   â”Œâ”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”   â”‚
â”‚   â”‚  Continue with Email        â”‚   â”‚
â”‚   â””â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”˜   â”‚
â””â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”˜
```

### 4.5 Handle Hidden Email

**Requirement APPLE-FR-007**: Handle Apple's private relay email:
- Users can choose "Hide My Email" during Apple Sign-In
- Apple provides a relay address like `xyz123@privaterelay.appleid.com`
- Store this relay email in the profile
- Emails sent to relay will forward to user's real email

**Requirement APPLE-FR-008**: Display handling for relay emails:

```swift
extension Profile {
    var isApplePrivateRelay: Bool {
        email.contains("privaterelay.appleid.com")
    }
    
    var displayEmail: String {
        if isApplePrivateRelay {
            return "Private Email (via Apple)"
        }
        return email
    }
}
```

### 4.6 Credential State Checking

**Requirement APPLE-FR-009**: Check Apple credential state on app launch:

```swift
// Check if Apple credential is still valid
func checkAppleCredentialState() async {
    guard let userId = UserDefaults.standard.string(forKey: "appleUserIdentifier") else {
        return
    }
    
    let provider = ASAuthorizationAppleIDProvider()
    
    do {
        let state = try await provider.credentialState(forUserID: userId)
        
        switch state {
        case .authorized:
            Log.authInfo("Apple credential still authorized")
        case .revoked:
            Log.authInfo("Apple credential revoked - logging out")
            try? await logOut()
        case .notFound:
            Log.authInfo("Apple credential not found")
        case .transferred:
            Log.authInfo("Apple credential transferred")
        @unknown default:
            break
        }
    } catch {
        Log.authError("Failed to check Apple credential state: \(error)")
    }
}
```

### 4.7 Link Existing Account

**Requirement APPLE-FR-010**: Allow existing email users to link Apple ID:

```swift
func linkAppleAccount(credential: ASAuthorizationAppleIDCredential) async throws {
    guard let identityTokenData = credential.identityToken,
          let identityToken = String(data: identityTokenData, encoding: .utf8) else {
        throw AppError.unknown("Failed to get Apple identity token")
    }
    
    // Link identity to existing user
    try await supabase.auth.linkIdentity(
        credentials: .init(
            provider: .apple,
            idToken: identityToken
        )
    )
    
    // Store Apple user identifier for credential checking
    UserDefaults.standard.set(
        credential.user,
        forKey: "appleUserIdentifier"
    )
    
    Log.authInfo("Apple account linked successfully")
}
```

---

## 5. UI Components

### 5.1 Apple Sign-In View Model

```swift
// Features/Authentication/ViewModels/AppleSignInViewModel.swift
import AuthenticationServices

@MainActor
final class AppleSignInViewModel: ObservableObject {
    @Published var isLoading = false
    @Published var error: AppError?
    
    private var currentNonce: String?
    
    func handleSignInRequest(_ request: ASAuthorizationAppleIDRequest) {
        request.requestedScopes = [.fullName, .email]
        
        // Generate nonce for security
        let nonce = randomNonceString()
        currentNonce = nonce
        request.nonce = sha256(nonce)
    }
    
    func handleSignInCompletion(
        result: Result<ASAuthorization, Error>,
        inviteCode: String?,
        isNewUser: Bool
    ) async {
        isLoading = true
        error = nil
        
        switch result {
        case .success(let authorization):
            guard let credential = authorization.credential as? ASAuthorizationAppleIDCredential else {
                error = .unknown("Invalid credential type")
                isLoading = false
                return
            }
            
            do {
                if isNewUser, let code = inviteCode {
                    try await AuthService.shared.signUpWithApple(
                        credential: credential,
                        inviteCode: code
                    )
                } else {
                    try await AuthService.shared.logInWithApple(credential: credential)
                }
                
                // Store user identifier for credential checking
                UserDefaults.standard.set(
                    credential.user,
                    forKey: "appleUserIdentifier"
                )
            } catch {
                self.error = error as? AppError ?? .unknown(error.localizedDescription)
            }
            
        case .failure(let error):
            if let authError = error as? ASAuthorizationError,
               authError.code == .canceled {
                // User canceled - not an error
            } else {
                self.error = .unknown(error.localizedDescription)
            }
        }
        
        isLoading = false
    }
    
    // MARK: - Nonce Generation
    
    private func randomNonceString(length: Int = 32) -> String {
        precondition(length > 0)
        var randomBytes = [UInt8](repeating: 0, count: length)
        let errorCode = SecRandomCopyBytes(kSecRandomDefault, randomBytes.count, &randomBytes)
        if errorCode != errSecSuccess {
            fatalError("Unable to generate nonce")
        }
        let charset: [Character] = Array("0123456789ABCDEFGHIJKLMNOPQRSTUVXYZabcdefghijklmnopqrstuvwxyz-._")
        return String(randomBytes.map { charset[Int($0) % charset.count] })
    }
    
    private func sha256(_ input: String) -> String {
        import CryptoKit
        let inputData = Data(input.utf8)
        let hashedData = SHA256.hash(data: inputData)
        return hashedData.compactMap { String(format: "%02x", $0) }.joined()
    }
}
```

---

## 6. Non-Goals (Out of Scope)

| Item | Reason |
|------|--------|
| Google Sign-In | Apple-only for initial release |
| Facebook Login | Not common for community apps |
| Account merging | Complex edge cases |
| Apple Sign-In on web | iOS app only |

---

## 7. Design Considerations

### Apple Human Interface Guidelines

- Use official `SignInWithAppleButton` - don't create custom buttons
- Button must be at least 140pt wide and 30pt tall
- Use appropriate style for light/dark mode
- Place Apple button prominently (same size as other login options)

### Button Styles

| Color Scheme | Button Style |
|--------------|--------------|
| Light mode | `.black` |
| Dark mode | `.white` |

---

## 8. Technical Considerations

### Required Capabilities

1. **Sign in with Apple** capability in Xcode
2. **App ID** configured in Apple Developer portal
3. **Service ID** for Supabase (if using web OAuth flow)
4. **Private key** for server-to-server communication

### Supabase Configuration

```
Provider: Apple
Enabled: Yes
Client ID: [Your Service ID]
Secret: [Your private key content]
```

### Testing

- Use Simulator or real device (Apple Sign-In works on both)
- Create test Apple IDs for QA
- Test both "Share Email" and "Hide Email" flows
- Test credential revocation handling

---

## 9. Dependencies

### Depends On
- `prd-foundation-architecture.md`
- `prd-authentication.md`

### Frameworks Required
- `AuthenticationServices`
- `CryptoKit` (for nonce generation)

---

## 10. Success Metrics

| Metric | Target | How to Verify |
|--------|--------|---------------|
| Sign up with Apple | Creates account | Complete signup flow |
| Log in with Apple | Establishes session | Log in as existing user |
| Hidden email works | Relay email stored | Choose "Hide Email" |
| Credential check | Handles revocation | Revoke in Apple ID settings |
| Invite code enforced | Cannot skip | Try signup without code |

---

## 11. Open Questions

| Question | Status | Decision |
|----------|--------|----------|
| Prompt for name if Apple doesn't provide? | **Yes** | Show name entry after Apple auth |
| Allow unlinking Apple account? | **No** | Keep it simple |
| Show Apple badge on profile? | **Optional** | Nice to have |

---

*End of PRD: Apple Sign-In*
