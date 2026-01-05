# PRD: Authentication

## Document Information
- **Feature Name**: Authentication
- **Phase**: 0 (Foundation)
- **Dependencies**: `prd-foundation-architecture.md`
- **Estimated Effort**: 1-2 weeks
- **Last Updated**: January 2025

---

## 1. Introduction/Overview

### What is this?
This document defines the authentication system for the Naar's Cars iOS app. Authentication controls who can access the app and ensures only approved community members can participate.

### Why does this matter?
Naar's Cars is an invite-only community. Unlike public apps where anyone can sign up, this app requires:
1. A valid invite code from an existing member
2. Admin approval before gaining access

This trust-based model is core to the app's identity and safety.

### What problem does it solve?
- Keeps the community private and trusted
- Prevents random strangers from joining
- Gives admins control over who participates
- Creates accountability through the invite chain (who invited whom)

---

## 2. Goals

| Goal | Measurable Outcome |
|------|-------------------|
| Users can sign up with valid invite code | Signup flow completes without errors |
| Users can log in with email/password | Login flow completes without errors |
| Invalid invite codes are rejected | Error message displayed for bad codes |
| Pending users see appropriate screen | Pending approval view shown correctly |
| Session persists across app launches | User stays logged in after closing app |
| Users can log out | Session is cleared, returns to login |
| Password reset works | Reset email is sent and works |

---

## 3. User Stories

| ID | As a... | I want to... | So that... |
|----|---------|--------------|------------|
| AUTH-01 | New user | Sign up with an invite code | I can join the community |
| AUTH-02 | New user | See clear errors if my invite code is invalid | I know what went wrong |
| AUTH-03 | Pending user | See a pending approval screen | I know my account is awaiting admin review |
| AUTH-04 | Approved user | Log in with my email and password | I can access the app |
| AUTH-05 | Logged-in user | Stay logged in when I close and reopen the app | I don't have to log in every time |
| AUTH-06 | Logged-in user | Log out | I can switch accounts or secure my device |
| AUTH-07 | User who forgot password | Reset my password via email | I can regain access to my account |
| AUTH-08 | User | See loading indicators during auth operations | I know the app is working |
| AUTH-09 | User | See friendly error messages | I understand what went wrong |

---

## 4. Functional Requirements

### 4.1 Authentication Service

**Requirement AUTH-FR-001**: The app MUST have an `AuthService` class that handles all authentication operations:

```swift
// Core/Services/AuthService.swift
import Foundation
import Supabase

/// Service responsible for all authentication operations.
/// Use this instead of calling Supabase auth directly.
@MainActor
final class AuthService: ObservableObject {
    private let supabase = SupabaseService.shared.client
    
    /// Currently authenticated user ID (from Supabase Auth)
    @Published private(set) var currentUserId: UUID?
    
    /// Current user's profile (from profiles table)
    @Published private(set) var currentProfile: Profile?
    
    /// Whether auth state is still being determined
    @Published private(set) var isLoading: Bool = true
    
    /// Singleton instance
    static let shared = AuthService()
    
    private init() {}
    
    // MARK: - Public Methods
    
    /// Check if user is already logged in (call on app launch)
    func checkAuthStatus() async throws -> AuthState { ... }
    
    /// Sign up a new user with invite code
    func signUp(
        email: String,
        password: String,
        name: String,
        inviteCode: String,
        car: String?
    ) async throws { ... }
    
    /// Log in existing user
    func logIn(email: String, password: String) async throws { ... }
    
    /// Log out current user
    func logOut() async throws { ... }
    
    /// Send password reset email
    func sendPasswordReset(email: String) async throws { ... }
    
    /// Fetch current user's profile from database
    func fetchCurrentProfile() async throws -> Profile { ... }
}
```

---

### 4.2 Invite Code Validation

**Requirement AUTH-FR-002**: Before allowing signup, the app MUST validate the invite code:

```swift
/// Validates an invite code before signup.
/// - Returns: The invite code record if valid
/// - Throws: AppError.invalidInviteCode if code is invalid or already used
func validateInviteCode(_ code: String) async throws -> InviteCode {
    let normalizedCode = code.uppercased().trimmingCharacters(in: .whitespaces)
    
    let response = try await supabase
        .from("invite_codes")
        .select()
        .eq("code", normalizedCode)
        .is("used_by", value: nil)  // Must not be used
        .single()
        .execute()
    
    guard let inviteCode = try? JSONDecoder().decode(InviteCode.self, from: response.data) else {
        throw AppError.invalidInviteCode
    }
    
    return inviteCode
}
```

**Requirement AUTH-FR-003**: Invite code validation MUST check:
- Code exists in the database
- Code has NOT already been used (`used_by` is null)

**Requirement AUTH-FR-004**: Invite codes MUST be case-insensitive (convert to uppercase before checking).

---

### 4.3 Sign Up Flow

**Requirement AUTH-FR-005**: The signup flow MUST follow these steps in order:

```
1. User enters invite code
       â†“
2. App validates invite code (AUTH-FR-002)
       â†“ (valid)
3. User enters: name, email, password, car (optional)
       â†“
4. App validates all fields (AUTH-FR-006)
       â†“ (valid)
5. App creates Supabase Auth user
       â†“
6. App creates profile record with approved=false
       â†“
7. App marks invite code as used
       â†“
8. App shows "Pending Approval" screen
```

**Requirement AUTH-FR-006**: Signup field validation:

| Field | Required | Validation Rules |
|-------|----------|------------------|
| Invite Code | Yes | Must be valid and unused |
| Name | Yes | Minimum 2 characters, maximum 100 |
| Email | Yes | Valid email format |
| Password | Yes | Minimum 6 characters |
| Car | No | Maximum 100 characters if provided |

**Requirement AUTH-FR-007**: After successful signup, the app MUST:
1. Create a profile record with `approved = false`
2. Set `invited_by` to the user ID who created the invite code
3. Mark the invite code as used by setting `used_by` to the new user's ID

**Requirement AUTH-FR-008**: The signup implementation:

```swift
func signUp(
    email: String,
    password: String,
    name: String,
    inviteCode: String,
    car: String?
) async throws {
    // 1. Validate invite code
    let invite = try await validateInviteCode(inviteCode)
    
    // 2. Create auth user
    let authResponse = try await supabase.auth.signUp(
        email: email,
        password: password,
        data: [
            "name": .string(name),
            "car": car.map { .string($0) } ?? .null,
            "invited_by": .string(invite.createdBy.uuidString)
        ]
    )
    
    guard let userId = authResponse.user?.id else {
        throw AppError.unknown("Failed to create user account")
    }
    
    // 3. Create profile (triggered by Supabase trigger, but let's be explicit)
    try await supabase
        .from("profiles")
        .insert([
            "id": userId.uuidString,
            "name": name,
            "email": email,
            "car": car ?? NSNull(),
            "invited_by": invite.createdBy.uuidString,
            "is_admin": false,
            "approved": false
        ])
        .execute()
    
    // 4. Mark invite code as used
    try await supabase
        .from("invite_codes")
        .update(["used_by": userId.uuidString])
        .eq("id", invite.id.uuidString)
        .execute()
    
    // 5. Update local state
    self.currentUserId = userId
    // Profile won't be fully accessible until approved
}
```

---

### 4.4 Login Flow

**Requirement AUTH-FR-009**: The login flow MUST:

```swift
func logIn(email: String, password: String) async throws {
    // 1. Authenticate with Supabase
    let session = try await supabase.auth.signIn(
        email: email,
        password: password
    )
    
    guard let userId = session.user?.id else {
        throw AppError.invalidCredentials
    }
    
    // 2. Fetch user's profile
    let profile = try await fetchCurrentProfile()
    
    // 3. Update local state
    self.currentUserId = userId
    self.currentProfile = profile
    
    Log.authInfo("User logged in: \(userId)")
}
```

**Requirement AUTH-FR-010**: After successful login, the app MUST check the profile's `approved` status:
- If `approved == true`: Navigate to main app (tab view)
- If `approved == false`: Navigate to Pending Approval screen

---

### 4.5 Session Persistence

**Requirement AUTH-FR-011**: The app MUST persist the auth session so users don't need to log in every time they open the app.

**Requirement AUTH-FR-012**: On app launch, the app MUST:

```swift
func checkAuthStatus() async throws -> AuthState {
    isLoading = true
    defer { isLoading = false }
    
    // 1. Check if there's an existing session
    let session = try await supabase.auth.session
    
    guard let userId = session?.user?.id else {
        Log.authInfo("No existing session found")
        return .unauthenticated
    }
    
    Log.authInfo("Found existing session for user: \(userId)")
    self.currentUserId = userId
    
    // 2. Fetch current profile
    do {
        let profile = try await fetchCurrentProfile()
        self.currentProfile = profile
        
        if profile.approved {
            return .authenticated
        } else {
            return .pendingApproval
        }
    } catch {
        // Profile doesn't exist or error - treat as unauthenticated
        try? await logOut()
        return .unauthenticated
    }
}
```

---

### 4.6 Logout

**Requirement AUTH-FR-013**: The logout function MUST:

```swift
func logOut() async throws {
    try await supabase.auth.signOut()
    
    // Clear local state
    self.currentUserId = nil
    self.currentProfile = nil
    
    Log.authInfo("User logged out")
}
```

**Requirement AUTH-FR-014**: After logout, the app MUST navigate to the login screen.

---

### 4.7 Password Reset

**Requirement AUTH-FR-015**: Password reset MUST send an email to the user:

```swift
func sendPasswordReset(email: String) async throws {
    try await supabase.auth.resetPasswordForEmail(email)
    Log.authInfo("Password reset email sent to: \(email)")
}
```

**Requirement AUTH-FR-016**: The password reset email is handled by Supabase. The app does NOT need to implement the reset form (users click link in email â†’ Supabase hosted page).

---

### 4.8 Auth State Management

**Requirement AUTH-FR-017**: The `AppState` class (from foundation PRD) MUST be updated when auth state changes:

```swift
// In ContentView or App file
.task {
    do {
        let authState = try await AuthService.shared.checkAuthStatus()
        appState.currentUser = AuthService.shared.currentProfile
        appState.isLoading = false
    } catch {
        appState.isLoading = false
        // Handle error
    }
}
```

**Requirement AUTH-FR-018**: The app MUST listen for auth state changes (e.g., session expiry):

```swift
// Set up auth state listener
supabase.auth.onAuthStateChange { event, session in
    switch event {
    case .signedIn:
        Log.authInfo("Auth event: signed in")
    case .signedOut:
        Log.authInfo("Auth event: signed out")
        // Clear app state and navigate to login
    case .tokenRefreshed:
        Log.authInfo("Auth event: token refreshed")
    case .userUpdated:
        Log.authInfo("Auth event: user updated")
    default:
        break
    }
}
```

---

## 5. UI Requirements

### 5.1 Login View

**Requirement AUTH-UI-001**: The Login View MUST contain:

| Element | Type | Behavior |
|---------|------|----------|
| App logo | Image | Naar's Cars logo at top |
| Email field | TextField | Email keyboard, auto-lowercase |
| Password field | SecureField | Hidden characters, no autocorrect |
| "Log In" button | PrimaryButton | Triggers login, shows loading state |
| "Forgot Password?" link | Button | Opens password reset sheet |
| "Don't have an account? Sign Up" | Button | Navigates to signup flow |
| Error message | Text | Shows below form when login fails |

**Requirement AUTH-UI-002**: Login View wireframe:

```
â”Œâ”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”
â”‚                                     â”‚
â”‚         [Naar's Cars Logo]          â”‚
â”‚                                     â”‚
â”‚   Welcome Back, Carbardian!         â”‚
â”‚                                     â”‚
â”‚   â”Œâ”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”   â”‚
â”‚   â”‚  Email                      â”‚   â”‚
â”‚   â””â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”˜   â”‚
â”‚                                     â”‚
â”‚   â”Œâ”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”   â”‚
â”‚   â”‚  Password                   â”‚   â”‚
â”‚   â””â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”˜   â”‚
â”‚                                     â”‚
â”‚   â”Œâ”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”   â”‚
â”‚   â”‚         Log In              â”‚   â”‚
â”‚   â””â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”˜   â”‚
â”‚                                     â”‚
â”‚         Forgot Password?            â”‚
â”‚                                     â”‚
â”‚   â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”‚
â”‚                                     â”‚
â”‚   Don't have an account? Sign Up    â”‚
â”‚                                     â”‚
â””â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”˜
```

---

### 5.2 Signup Flow

**Requirement AUTH-UI-003**: Signup MUST be a multi-step flow:

**Step 1: Invite Code Entry**
```
â”Œâ”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”
â”‚   â†  Back                           â”‚
â”‚                                     â”‚
â”‚         [Naar's Cars Logo]          â”‚
â”‚                                     â”‚
â”‚      Join the Community             â”‚
â”‚                                     â”‚
â”‚   Enter your invite code from       â”‚
â”‚   an existing Carbardian            â”‚
â”‚                                     â”‚
â”‚   â”Œâ”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”   â”‚
â”‚   â”‚  Invite Code (e.g. NC...)   â”‚   â”‚
â”‚   â””â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”˜   â”‚
â”‚                                     â”‚
â”‚   â”Œâ”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”   â”‚
â”‚   â”‚       Verify Code           â”‚   â”‚
â”‚   â””â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”˜   â”‚
â”‚                                     â”‚
â”‚   (Error message if invalid)        â”‚
â”‚                                     â”‚
â””â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”˜
```

**Step 2: Account Details**
```
â”Œâ”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”
â”‚   â†  Back                           â”‚
â”‚                                     â”‚
â”‚      Almost There!                  â”‚
â”‚                                     â”‚
â”‚   â”Œâ”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”   â”‚
â”‚   â”‚  Full Name *                â”‚   â”‚
â”‚   â””â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”˜   â”‚
â”‚                                     â”‚
â”‚   â”Œâ”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”   â”‚
â”‚   â”‚  Email *                    â”‚   â”‚
â”‚   â””â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”˜   â”‚
â”‚                                     â”‚
â”‚   â”Œâ”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”   â”‚
â”‚   â”‚  Password *                 â”‚   â”‚
â”‚   â””â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”˜   â”‚
â”‚                                     â”‚
â”‚   â”Œâ”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”   â”‚
â”‚   â”‚  Car (optional)             â”‚   â”‚
â”‚   â””â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”˜   â”‚
â”‚   e.g., "Blue Honda Civic"          â”‚
â”‚                                     â”‚
â”‚   â”Œâ”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”   â”‚
â”‚   â”‚      Create Account         â”‚   â”‚
â”‚   â””â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”˜   â”‚
â”‚                                     â”‚
â””â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”˜
```

**Requirement AUTH-UI-004**: Signup form field specifications:

| Field | Keyboard | Autocapitalization | Autocorrect | Content Type |
|-------|----------|-------------------|-------------|--------------|
| Invite Code | ASCII | All characters â†’ uppercase | Off | One-time code |
| Name | Default | Words | Off | Name |
| Email | Email | None | Off | Email |
| Password | Default | None | Off | New Password |
| Car | Default | Words | On | - |

---

### 5.3 Pending Approval View

**Requirement AUTH-UI-005**: When a user is logged in but `approved == false`, show:

```
â”Œâ”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”
â”‚                                     â”‚
â”‚         [Clock Icon - Large]        â”‚
â”‚                                     â”‚
â”‚       Pending Approval              â”‚
â”‚                                     â”‚
â”‚   Thanks for signing up!            â”‚
â”‚                                     â”‚
â”‚   An admin needs to approve your    â”‚
â”‚   account before you can start      â”‚
â”‚   sharing rides with the community. â”‚
â”‚                                     â”‚
â”‚   You'll receive a notification     â”‚
â”‚   once you're approved.             â”‚
â”‚                                     â”‚
â”‚   â”Œâ”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”   â”‚
â”‚   â”‚        Sign Out             â”‚   â”‚
â”‚   â””â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”˜   â”‚
â”‚                                     â”‚
â””â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”˜
```

**Requirement AUTH-UI-006**: The Pending Approval view MUST:
- Show a friendly message explaining the wait
- Provide a "Sign Out" button
- NOT show any main app content

**Requirement AUTH-UI-007**: The app SHOULD periodically check if the user has been approved (every 30 seconds) or when the app returns to foreground:

```swift
// In PendingApprovalView
.onReceive(Timer.publish(every: 30, on: .main, in: .common).autoconnect()) { _ in
    Task {
        await checkApprovalStatus()
    }
}
.onReceive(NotificationCenter.default.publisher(for: UIApplication.willEnterForegroundNotification)) { _ in
    Task {
        await checkApprovalStatus()
    }
}

private func checkApprovalStatus() async {
    do {
        let profile = try await AuthService.shared.fetchCurrentProfile()
        if profile.approved {
            appState.currentUser = profile
            // Navigation will automatically update due to authState change
        }
    } catch {
        // Ignore errors during polling
    }
}
```

---

### 5.4 Password Reset Sheet

**Requirement AUTH-UI-008**: Password reset MUST be a sheet presented from the login view:

```
â”Œâ”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”
â”‚   âœ•  Reset Password                 â”‚
â”‚   â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”‚
â”‚                                     â”‚
â”‚   Enter your email and we'll send   â”‚
â”‚   you a link to reset your password â”‚
â”‚                                     â”‚
â”‚   â”Œâ”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”   â”‚
â”‚   â”‚  Email                      â”‚   â”‚
â”‚   â””â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”˜   â”‚
â”‚                                     â”‚
â”‚   â”Œâ”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”   â”‚
â”‚   â”‚     Send Reset Link         â”‚   â”‚
â”‚   â””â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”˜   â”‚
â”‚                                     â”‚
â”‚   (Success/Error message)           â”‚
â”‚                                     â”‚
â””â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”˜
```

**Requirement AUTH-UI-009**: After successfully sending reset email:
- Show success message: "Check your email for a reset link"
- Automatically dismiss sheet after 3 seconds

---

## 6. Error Handling

**Requirement AUTH-FR-019**: The following errors MUST be handled gracefully:

| Scenario | Error | User Message |
|----------|-------|--------------|
| Invalid invite code | `AppError.invalidInviteCode` | "This invite code is invalid or has already been used." |
| Wrong email/password | `AppError.invalidCredentials` | "Invalid email or password." |
| Email already registered | Supabase error | "An account with this email already exists." |
| Network error | `AppError.networkUnavailable` | "No internet connection. Please check your network and try again." |
| Password too short | `AppError.requiredFieldMissing` | "Password must be at least 6 characters." |
| Invalid email format | `AppError.invalidEmail` | "Please enter a valid email address." |
| Session expired | `AppError.sessionExpired` | "Your session has expired. Please log in again." |

**Requirement AUTH-FR-020**: Error messages MUST be displayed:
- Below the form for login/signup errors
- As an alert for unexpected errors
- With red text color

---

## 7. Non-Goals (Out of Scope)

| Item | Reason |
|------|--------|
| Social login (Apple, Google) | Not used in current web app; future enhancement |
| Biometric authentication (Face ID/Touch ID) | Future enhancement |
| Multi-factor authentication (MFA) | Future enhancement |
| Email verification step | Supabase handles this automatically |
| "Remember me" checkbox | iOS persists sessions by default |
| Account deletion | Handled by admin; user can request via profile settings |

---

## 8. Design Considerations

### iOS-Native Patterns

| Pattern | Implementation |
|---------|---------------|
| Keyboard handling | Use `.scrollDismissesKeyboard(.interactively)` on forms |
| Secure field | Use `SecureField` for passwords |
| Focus management | Use `@FocusState` to move between fields |
| Loading states | Disable buttons and show `ProgressView` in button |
| Form validation | Validate on submit, show inline errors |
| Keyboard types | Set `.keyboardType(.emailAddress)` for email |

### Improvements Over Web App

| Web Behavior | iOS Improvement |
|--------------|-----------------|
| Basic text input | Native keyboard types and content types for autofill |
| Manual navigation | SwiftUI navigation with proper back gestures |
| Toast errors | Inline error messages + haptic feedback |
| Session check on load | Background session refresh while showing cached state |

---

## 9. Technical Considerations

### Supabase Auth Configuration

The following Supabase settings should be verified:

1. **Email confirmations**: Decide if email confirmation is required
2. **Password requirements**: Minimum 6 characters
3. **JWT expiry**: Default is 1 hour, refresh tokens handle this

### Security

- Passwords are never stored locally (Supabase handles auth)
- Sessions are stored securely by Supabase Swift SDK
- Invite codes are single-use and tracked

### Testing Considerations

Create test accounts:
1. One approved user for main app testing
2. One pending user for pending approval flow testing
3. Several unused invite codes for signup testing

---

## 10. Dependencies

### Depends On
- `prd-foundation-architecture.md` - Base app structure, SupabaseService, error handling

### Blocks
- All other feature PRDs require authentication to be complete

---

## 11. Success Metrics

| Metric | Target | How to Verify |
|--------|--------|---------------|
| Signup with valid code | Works end-to-end | Create account with test code |
| Signup with invalid code | Shows error | Try fake code |
| Login with valid credentials | Navigates to main app | Log in as approved user |
| Login with wrong password | Shows error | Use wrong password |
| Session persists | Still logged in after app restart | Close and reopen app |
| Pending user sees correct screen | Shows pending view | Log in as pending user |
| Logout clears session | Returns to login | Log out and verify |
| Password reset email sends | Email received | Request reset |

---

## 12. Open Questions

| Question | Status | Decision |
|----------|--------|----------|
| Should we show password strength indicator? | **No** | Keep it simple for MVP |
| Should invite code entry be on same screen as other fields? | **No** | Two-step is clearer UX |
| Should we auto-capitalize invite code as user types? | **Yes** | Less friction |

---

## Appendix A: View Implementation Skeletons

### LoginView

```swift
// Features/Authentication/Views/LoginView.swift
import SwiftUI

struct LoginView: View {
    @StateObject private var viewModel = LoginViewModel()
    @State private var showPasswordReset = false
    
    var body: some View {
        VStack(spacing: 24) {
            // Logo
            Image("AppLogo")
                .resizable()
                .scaledToFit()
                .frame(height: 100)
            
            Text("Welcome Back, Carbardian!")
                .font(.title2)
                .fontWeight(.bold)
            
            // Form
            VStack(spacing: 16) {
                TextField("Email", text: $viewModel.email)
                    .textFieldStyle(.roundedBorder)
                    .keyboardType(.emailAddress)
                    .textInputAutocapitalization(.never)
                    .autocorrectionDisabled()
                
                SecureField("Password", text: $viewModel.password)
                    .textFieldStyle(.roundedBorder)
                
                if let error = viewModel.error {
                    Text(error.errorDescription ?? "An error occurred")
                        .foregroundColor(.red)
                        .font(.caption)
                }
                
                PrimaryButton("Log In", isLoading: viewModel.isLoading) {
                    Task {
                        await viewModel.login()
                    }
                }
            }
            .padding(.horizontal)
            
            Button("Forgot Password?") {
                showPasswordReset = true
            }
            .foregroundColor(.accentColor)
            
            Divider()
                .padding(.vertical)
            
            NavigationLink("Don't have an account? Sign Up") {
                SignupInviteCodeView()
            }
            .foregroundColor(.accentColor)
        }
        .padding()
        .sheet(isPresented: $showPasswordReset) {
            PasswordResetView()
        }
    }
}
```

### LoginViewModel

```swift
// Features/Authentication/ViewModels/LoginViewModel.swift
import Foundation

@MainActor
final class LoginViewModel: ObservableObject {
    @Published var email: String = ""
    @Published var password: String = ""
    @Published var isLoading: Bool = false
    @Published var error: AppError?
    
    func login() async {
        guard !email.isEmpty else {
            error = .requiredFieldMissing("Email")
            return
        }
        
        guard !password.isEmpty else {
            error = .requiredFieldMissing("Password")
            return
        }
        
        isLoading = true
        error = nil
        
        do {
            try await AuthService.shared.logIn(email: email, password: password)
            // Navigation handled by parent view observing auth state
        } catch let appError as AppError {
            error = appError
        } catch {
            error = .unknown(error.localizedDescription)
        }
        
        isLoading = false
    }
}
```

---

*End of PRD: Authentication*

---

## Security & Performance Requirements

**Added**: January 2025 (Senior Developer Review)

The following requirements were identified during security and performance review and are **required for production deployment**.

## REVISE: Section 4.2 - Invite Code Validation

**Replace existing invite code validation with:**

```markdown
### 4.2 Invite Code Validation

**Requirement AUTH-FR-006**: Invite code format (updated):
- Format: `NC` + 8 alphanumeric characters (uppercase)
- Example: `NC7X9K2ABQ`
- Character set: A-Z, 0-9 (excluding confusing: 0/O, 1/I/L)
- Case-insensitive input (normalized to uppercase)

**Requirement AUTH-FR-006a**: Invite code validation implementation:

```swift
func validateInviteCode(_ input: String) async throws -> InviteCode {
    // Rate limit check
    guard await RateLimiter.shared.checkAndRecord(
        action: "validate_invite",
        minimumInterval: 3
    ) else {
        throw AppError.rateLimited
    }
    
    // Normalize input
    let code = input.uppercased().trimmingCharacters(in: .whitespacesAndNewlines)
    
    // Basic format check before hitting database
    guard code.hasPrefix("NC"),
          code.count == 10,
          code.dropFirst(2).allSatisfy({ $0.isLetter || $0.isNumber }) else {
        throw AppError.invalidInviteCode
    }
    
    // Query database
    let response = try await supabase
        .from("invite_codes")
        .select()
        .eq("code", code)
        .single()
        .execute()
    
    let invite = try JSONDecoder().decode(InviteCode.self, from: response.data)
    
    guard invite.usedBy == nil else {
        throw AppError.invalidInviteCode // Same error - don't reveal existence
    }
    
    return invite
}
```

**Requirement AUTH-FR-006b**: Error messages MUST NOT reveal code existence:

| Scenario | Error Message |
|----------|---------------|
| Code doesn't exist | "Invalid or expired invite code" |
| Code already used | "Invalid or expired invite code" |
| Rate limited | "Too many attempts. Please wait a moment." |
| Code valid | (no error) |

**Requirement AUTH-FR-006c**: Support legacy 6-character codes during transition:

```swift
// Accept both 6 and 8 character codes
guard code.hasPrefix("NC"),
      (code.count == 8 || code.count == 10), // NC + 6 or NC + 8
      // ...
```
```

---

## ADD: Section 4.3a - Invite Code Rate Limiting

**Insert after section 4.3**

```markdown
### 4.3a Invite Code Rate Limiting

**Requirement AUTH-FR-007a**: Invite code validation MUST be rate-limited:

| Layer | Limit | Behavior |
|-------|-------|----------|
| Client-side | 3 seconds between attempts | Silent prevention |
| Server-side | 5 attempts per hour per device | Show lockout message |

**Requirement AUTH-FR-007b**: After 5 server-side failures:
- Show: "Too many attempts. Please try again in 1 hour."
- Disable input field for 60 minutes (or until app restart)
- Log attempt for security monitoring

**Requirement AUTH-FR-007c**: Implementation tracking (server-side Edge Function):

```javascript
// Edge Function: validate-invite-code
const attempts = await getAttemptCount(deviceId, 'invite_validation');
if (attempts >= 5) {
    return { error: 'rate_limited', retryAfter: 3600 };
}
await incrementAttemptCount(deviceId, 'invite_validation');
// ... validate code ...
```
```

---

## ADD: Section 4.4a - Login Rate Limiting

**Insert after section 4.4**

```markdown
### 4.4a Login Rate Limiting

**Requirement AUTH-FR-010a**: Login attempts MUST be rate-limited:

| Layer | Limit | Window |
|-------|-------|--------|
| Client-side | 2 seconds between attempts | Per tap |
| Server-side | 5 failed attempts | 15 minutes per email |

**Requirement AUTH-FR-010b**: Client-side implementation:

```swift
func login(email: String, password: String) async throws {
    // Rate limit check
    guard await RateLimiter.shared.checkAndRecord(
        action: "login",
        minimumInterval: 2
    ) else {
        HapticFeedback.warning()
        return
    }
    
    isLoading = true
    defer { isLoading = false }
    
    do {
        try await supabase.auth.signIn(email: email, password: password)
    } catch let error as AuthError {
        // Handle specific errors
        throw mapAuthError(error)
    }
}
```

**Requirement AUTH-FR-010c**: After 5 failed attempts (server-side):
- Show: "Too many failed attempts. Please try again in 15 minutes or reset your password."
- Offer password reset link
- Lock email for 15 minutes on server

**Requirement AUTH-FR-010d**: Supabase Auth configuration:
```
// In Supabase Dashboard → Authentication → Settings
Rate limit: 5 requests per 15 minutes per email for failed logins
```
```

---

## ADD: Section 4.7a - Password Reset Rate Limiting

**Insert after section 4.7**

```markdown
### 4.7a Password Reset Rate Limiting

**Requirement AUTH-FR-015a**: Password reset requests MUST be rate-limited:

| Layer | Limit | Window |
|-------|-------|--------|
| Client-side | 30 seconds between requests | Per tap |
| Server-side | 3 requests per email | 1 hour |

**Requirement AUTH-FR-015b**: ALWAYS show success message (prevent email enumeration):

```swift
func requestPasswordReset(email: String) async {
    // Rate limit check
    guard await RateLimiter.shared.checkAndRecord(
        action: "password_reset",
        minimumInterval: 30
    ) else {
        // Show message anyway to prevent timing attacks
        showSuccessMessage = true
        return
    }
    
    isLoading = true
    
    do {
        try await supabase.auth.resetPasswordForEmail(email)
    } catch {
        // Ignore errors - don't reveal if email exists
        Log.authInfo("Password reset requested for \(email.prefix(3))***")
    }
    
    isLoading = false
    
    // Always show same message
    showSuccessMessage = true
    successMessage = "If an account exists with this email, you'll receive a password reset link."
}
```

**Requirement AUTH-FR-015c**: Success message MUST be identical regardless of:
- Email exists in system
- Email doesn't exist
- Rate limit triggered
- Any error occurred
```

---

## ADD: Section 4.9 - Session Lifecycle Management

**Insert after section 4.8 (or as new final section in Authentication Flow)**

```markdown
### 4.9 Session Lifecycle Management

**Requirement AUTH-FR-021**: Session behavior documentation:

| Parameter | Value | Source |
|-----------|-------|--------|
| JWT expiry | 1 hour | Supabase default |
| Refresh token expiry | 30 days | Supabase default |
| Auto-refresh | Yes | Supabase SDK handles |

**Requirement AUTH-FR-022**: Handle session refresh failures gracefully:

```swift
// In AuthService
func setupAuthStateListener() {
    supabase.auth.onAuthStateChange { [weak self] event, session in
        Task { @MainActor in
            switch event {
            case .signedIn:
                Log.authInfo("Session started")
                
            case .signedOut:
                Log.authInfo("Session ended")
                await self?.handleSignOut()
                
            case .tokenRefreshed:
                Log.authInfo("Session refreshed")
                
            case .userUpdated:
                Log.authInfo("User updated")
                await self?.refreshCurrentProfile()
                
            default:
                break
            }
        }
    }
}

private func handleSignOut() async {
    // Clear all local state
    currentUserId = nil
    currentProfile = nil
    await CacheManager.shared.clearAll()
    await RealtimeManager.shared.unsubscribeAll()
    
    // Notify app to show login screen
    NotificationCenter.default.post(name: .userDidSignOut, object: nil)
}
```

**Requirement AUTH-FR-023**: When session cannot be refreshed:

1. Attempt silent refresh in background
2. If refresh fails with recoverable error (network), retry up to 3 times
3. If refresh fails with auth error (token revoked), sign out user
4. Show friendly message: "Your session has expired. Please log in again."
5. Navigate to login screen
6. Preserve any unsent drafts locally (if applicable)

```swift
func handleAuthError(_ error: Error) {
    if isRecoverableNetworkError(error) {
        Task {
            try? await Task.sleep(nanoseconds: 2_000_000_000)
            try? await supabase.auth.refreshSession()
        }
    } else {
        Task {
            try? await logOut()
            await MainActor.run {
                showSessionExpiredAlert = true
            }
        }
    }
}

private func isRecoverableNetworkError(_ error: Error) -> Bool {
    // Check for network-related errors
    let nsError = error as NSError
    return nsError.domain == NSURLErrorDomain
}
```

**Requirement AUTH-FR-024**: On logout, ensure complete cleanup:

```swift
func logOut() async throws {
    // 1. Unsubscribe from realtime
    await RealtimeManager.shared.unsubscribeAll()
    
    // 2. Clear caches
    await CacheManager.shared.clearAll()
    
    // 3. Remove push token from server
    await PushNotificationService.shared.removeDeviceToken()
    
    // 4. Clear local state
    currentUserId = nil
    currentProfile = nil
    
    // 5. Sign out from Supabase
    try await supabase.auth.signOut()
    
    Log.authInfo("User logged out successfully")
}
```
```

---

## REVISE: Section 7 - Non-Goals

**Update to include future considerations:**

```markdown
## 7. Non-Goals (Out of Scope)

| Item | Reason | Future Consideration |
|------|--------|---------------------|
| Social authentication (Google, Facebook) | Simplify MVP | Phase 5+ if user demand |
| Email verification requirement | Community is invite-only | Consider if expanding |
| Maximum session lifetime | Low risk for community app | Could add 90-day max in Phase 5 |
| View active sessions | Complexity vs value | Could add in settings |
| Remote logout other devices | Complexity vs value | Could add in settings |
| Re-auth for sensitive actions | Covered by biometric PRD | Phase 5 |
```

---

*End of Authentication Addendum*
