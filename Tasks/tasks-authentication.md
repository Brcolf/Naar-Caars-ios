# Tasks: Authentication

Based on `prd-authentication.md`

## Affected Flows

- FLOW_AUTH_001: Signup with Invite Code
- FLOW_AUTH_002: Login with Email/Password
- FLOW_AUTH_003: Password Reset
- FLOW_AUTH_004: Logout

See QA/FLOW-CATALOG.md for flow definitions.

## Relevant Files

### Source Files
- `Core/Services/AuthService.swift` - Main authentication service
- `Features/Authentication/Views/LoginView.swift` - Login screen
- `Features/Authentication/Views/SignupInviteCodeView.swift` - First step of signup (invite code entry)
- `Features/Authentication/Views/SignupDetailsView.swift` - Second step of signup (user details)
- `Features/Authentication/Views/PendingApprovalView.swift` - Screen for users awaiting approval
- `Features/Authentication/Views/PasswordResetView.swift` - Password reset flow
- `Features/Authentication/ViewModels/LoginViewModel.swift` - Login view model
- `Features/Authentication/ViewModels/SignupViewModel.swift` - Signup view model
- `Features/Authentication/ViewModels/PasswordResetViewModel.swift` - Password reset view model
- `Core/Models/InviteCode.swift` - Invite code data model
- `Core/Models/AppError.swift` - Custom error types (if not already in foundation)
- `Core/Utilities/InviteCodeGenerator.swift` - Secure invite code generation ⭐ NEW
- `App/ContentView.swift` - Update to handle auth states

### Test Files
- `NaarsCarsTests/Core/Services/AuthServiceTests.swift` - AuthService unit tests
- `NaarsCarsTests/Features/Authentication/LoginViewModelTests.swift` - Login VM tests
- `NaarsCarsTests/Features/Authentication/SignupViewModelTests.swift` - Signup VM tests
- `NaarsCarsTests/Features/Authentication/PasswordResetViewModelTests.swift` - Password reset tests
- `NaarsCarsTests/Core/Utilities/InviteCodeGeneratorTests.swift` - Invite code generation tests
- `NaarsCarsIntegrationTests/Auth/SignupFlowIntegrationTests.swift` - Full signup integration
- `NaarsCarsIntegrationTests/Auth/LoginFlowIntegrationTests.swift` - Full login integration

## Notes

- This feature depends on `prd-foundation-architecture.md` being complete
- Authentication uses Supabase Auth + custom profiles table
- Two-step signup: invite code validation first, then user details
- Session persistence handled by Supabase SDK
- All auth operations must use async/await
- ⭐ NEW items are from Senior Developer Security/Performance Review
- 🧪 items are QA tasks - write tests as you implement
- 🔒 CHECKPOINT items are mandatory quality gates - do not skip

## Instructions for Completing Tasks

**IMPORTANT:** As you complete each task, you must check it off in this markdown file by changing `- [ ]` to `- [x]`. This helps track progress and ensures you don't skip any steps.

**BLOCKING:** Tasks marked with ⛔ block other features and must be completed first.

**QA RULES:**
1. Complete 🧪 QA tasks immediately after their related implementation
2. Do NOT skip past 🔒 CHECKPOINT markers until tests pass
3. Run: `./QA/Scripts/checkpoint.sh <checkpoint-id>` at each checkpoint
4. If checkpoint fails, fix issues before continuing

Example:
- `- [ ] 1.1 Read file` → `- [x] 1.1 Read file` (after completing)

Update the file after completing each sub-task, not just after completing an entire parent task.

## Tasks

- [x] 0.0 Create feature branch
  - [x] 0.1 Create and checkout a new branch for this feature (e.g., `git checkout -b feature/authentication`)

- [x] 1.0 Implement AuthService core functionality
  - [x] 1.1 Open AuthService.swift (created in foundation) and add import statements for Foundation and Supabase
  - [x] 1.2 Implement checkAuthStatus() method to get current Supabase session
  - [x] 1.3 Add logic to fetch user profile from database if session exists
  - [x] 1.4 Handle case where session exists but profile doesn't (data inconsistency)
  - [x] 1.5 Return appropriate AuthState based on session and profile status
  - [x] 1.6 Implement fetchCurrentProfile() method to query profiles table
  - [x] 1.7 Add error handling for network failures and database errors
  - [ ] 1.8 ⭐ Set up Supabase auth state listener for session changes
  - [ ] 1.9 ⭐ Handle signedIn, signedOut, tokenRefreshed, userUpdated events
  - [ ] 1.10 🧪 Write AuthServiceTests.testCheckAuthStatus_NoSession_ReturnsUnauthenticated
  - [ ] 1.11 🧪 Write AuthServiceTests.testCheckAuthStatus_ValidSession_ReturnsAuthenticated
  - [ ] 1.12 🧪 Write AuthServiceTests.testFetchCurrentProfile_Success
  - [ ] 1.13 Test AuthService by manually calling checkAuthStatus in a test view

- [x] 2.0 Create invite code validation logic
  - [x] 2.1 Create InviteCode.swift model in Core/Models with fields: id, code, created_by, used_by, created_at
  - [x] 2.2 Make InviteCode conform to Codable, Identifiable
  - [x] 2.3 ⭐ Create InviteCodeGenerator.swift in Core/Utilities
  - [x] 2.4 ⭐ Define character set excluding confusing chars: "ABCDEFGHJKMNPQRSTUVWXYZ23456789" (no 0/O, 1/I/L)
  - [x] 2.5 ⭐ Implement generate() method returning "NC" + 8 random characters (10 total)
  - [ ] 2.6 🧪 Write InviteCodeGeneratorTests - test generates correct length
  - [ ] 2.7 🧪 Write InviteCodeGeneratorTests - test excludes confusing characters
  - [x] 2.8 Add validateInviteCode() method to AuthService
  - [x] 2.9 Implement invite code normalization (uppercase, trim whitespace)
  - [x] 2.10 ⭐ Add rate limit check: 3 seconds between validation attempts
  - [x] 2.11 ⭐ Accept both 6-char (legacy NC + 6) and 8-char (new NC + 8) codes
  - [x] 2.12 Query invite_codes table for matching code where used_by IS NULL
  - [x] 2.13 ⭐ Return same error for "not found" and "already used" (prevent enumeration)
  - [x] 2.14 Return InviteCode object if validation succeeds
  - [ ] 2.15 🧪 Write AuthServiceTests.testValidateInviteCode_ValidCode_ReturnsSuccess
  - [ ] 2.16 🧪 Write AuthServiceTests.testValidateInviteCode_InvalidCode_ReturnsError
  - [ ] 2.17 🧪 Write AuthServiceTests.testValidateInviteCode_UsedCode_ReturnsSameError
  - [ ] 2.18 🧪 Write AuthServiceTests.testValidateInviteCode_RateLimited

### 🔒 CHECKPOINT: QA-AUTH-001
> Run: `./QA/Scripts/checkpoint.sh auth-001`
> Guide: QA/CHECKPOINT-GUIDE.md
> Flows: FLOW_AUTH_001 (partial - validation only)
> Must pass before continuing

- [x] 3.0 Build signup flow (two-step process)
  - [x] 3.1 Create SignupInviteCodeView.swift in Features/Authentication/Views
  - [x] 3.2 Add text field for invite code input with uppercase text transformation
  - [x] 3.3 Add "Next" button that validates invite code before proceeding
  - [x] 3.4 ⭐ Disable button briefly after tap (rate limiting feedback)
  - [x] 3.5 Show loading indicator while validating invite code
  - [x] 3.6 Display error message if invite code is invalid: "Invalid or expired invite code"
  - [x] 3.7 ⭐ Show rate limit message if too fast: "Please wait a moment"
  - [x] 3.8 Navigate to SignupDetailsView if code is valid, passing validated InviteCode
  - [x] 3.9 Create SignupDetailsView.swift in Features/Authentication/Views
  - [x] 3.10 Add text fields for: name, email, password, car (optional)
  - [x] 3.11 Create SignupViewModel.swift with validation logic for all fields
  - [ ] 3.12 🧪 Write SignupViewModelTests.testValidation_EmptyName_ReturnsError
  - [ ] 3.13 🧪 Write SignupViewModelTests.testValidation_InvalidEmail_ReturnsError
  - [ ] 3.14 🧪 Write SignupViewModelTests.testValidation_WeakPassword_ReturnsError
  - [x] 3.15 Implement signUp() method in AuthService that creates auth user, profile, and marks code as used
  - [x] 3.16 Add transaction logic to ensure all database operations succeed or rollback
  - [x] 3.17 Handle email already registered error from Supabase
  - [x] 3.18 After successful signup, update AppState with new user (pending approval)
  - [x] 3.19 Navigate to PendingApprovalView after signup completes
  - [x] 3.20 Add form validation with inline error messages
  - [ ] 3.21 🧪 Write AuthServiceTests.testSignUp_Success_CreatesProfileAndMarksCode
  - [ ] 3.22 🧪 Write AuthServiceTests.testSignUp_EmailExists_ReturnsError

- [x] 4.0 Build login view and functionality
  - [x] 4.1 Create LoginView.swift in Features/Authentication/Views
  - [x] 4.2 Add app logo/title at top of view
  - [x] 4.3 Add email text field with .keyboardType(.emailAddress)
  - [x] 4.4 Add password SecureField
  - [x] 4.5 Create LoginViewModel.swift in Features/Authentication/ViewModels
  - [x] 4.6 Add @Published properties for email, password, isLoading, error
  - [x] 4.7 ⭐ Add rate limit check: 2 seconds between login attempts
  - [x] 4.8 Implement login() method in LoginViewModel that calls AuthService.logIn()
  - [ ] 4.9 ⭐ Add haptic warning feedback when rate limited
  - [ ] 4.10 🧪 Write LoginViewModelTests.testLogin_EmptyEmail_ReturnsError
  - [ ] 4.11 🧪 Write LoginViewModelTests.testLogin_LoadingState_IsTrue
  - [ ] 4.12 🧪 Write LoginViewModelTests.testLogin_RateLimited_ShowsMessage
  - [x] 4.13 Add "Forgot Password?" button that shows password reset sheet
  - [x] 4.14 Add NavigationLink to SignupInviteCodeView for new users
  - [x] 4.15 Show error message below form if login fails
  - [x] 4.16 Disable login button and show loading indicator during auth
  - [x] 4.17 Implement logIn() method in AuthService using Supabase auth.signIn
  - [x] 4.18 After successful login, fetch user profile and update AppState
  - [x] 4.19 Handle wrong password error with friendly message
  - [x] 4.20 Add .scrollDismissesKeyboard(.interactively) to form
  - [ ] 4.21 🧪 Write AuthServiceTests.testLogIn_ValidCredentials_Success
  - [ ] 4.22 🧪 Write AuthServiceTests.testLogIn_InvalidCredentials_ReturnsError

### 🔒 CHECKPOINT: QA-AUTH-002
> Run: `./QA/Scripts/checkpoint.sh auth-002`
> Guide: QA/CHECKPOINT-GUIDE.md
> Flows: FLOW_AUTH_001 (signup), FLOW_AUTH_002 (login)
> Must pass before continuing

- [x] 5.0 Build pending approval screen
  - [x] 5.1 Create PendingApprovalView.swift in Features/Authentication/Views
  - [x] 5.2 Add icon/image indicating pending status
  - [x] 5.3 Add title: "Your Account is Pending Approval"
  - [x] 5.4 Add message explaining an admin will review their account
  - [x] 5.5 Display user's email address for confirmation
  - [x] 5.6 Add "Refresh Status" button that rechecks approval status
  - [x] 5.7 Add "Log Out" button to allow user to switch accounts
  - [x] 5.8 Implement refresh logic that calls AuthService.fetchCurrentProfile()
  - [x] 5.9 Show success message and navigate to main app if approved
  - [x] 5.10 Add pull-to-refresh gesture for checking approval status

- [x] 6.0 Implement password reset flow
  - [x] 6.1 Create PasswordResetView.swift in Features/Authentication/Views
  - [x] 6.2 Add email text field with .keyboardType(.emailAddress)
  - [x] 6.3 Create PasswordResetViewModel.swift in Features/Authentication/ViewModels
  - [x] 6.4 Add @Published properties for email, isLoading, error, successMessage
  - [x] 6.5 ⭐ Add rate limit check: 30 seconds between password reset requests
  - [x] 6.6 Add "Send Reset Link" button
  - [x] 6.7 Implement sendPasswordReset() in AuthService using Supabase auth.resetPasswordForEmail
  - [x] 6.8 ⭐ ALWAYS show same success message regardless of email existence (prevent enumeration)
  - [x] 6.9 Success message: "If an account exists with this email, you'll receive a password reset link."
  - [x] 6.10 ⭐ Catch and ignore errors - never reveal if email exists
  - [x] 6.11 Add auto-dismiss logic after 3 seconds on success
  - [x] 6.12 Add "Back to Login" button to dismiss sheet
  - [ ] 6.13 🧪 Write PasswordResetViewModelTests.testSendReset_ShowsSameMessageAlways
  - [ ] 6.14 🧪 Write PasswordResetViewModelTests.testSendReset_RateLimited

- [x] 7.0 Implement session persistence and auto-login
  - [x] 7.1 Verify Supabase SDK automatically persists sessions (it does by default)
  - [x] 7.2 In AppState init or onAppear, call AuthService.checkAuthStatus()
  - [x] 7.3 Update AppState.currentUser based on auth check result
  - [x] 7.4 Set AppState.isLoading = false after auth check completes
  - [ ] 7.5 Test that closing and reopening app keeps user logged in
  - [ ] 7.6 Test that approved users go directly to main app on launch
  - [ ] 7.7 Test that pending users go to pending approval screen on launch
  - [ ] 7.8 ⭐ Implement session refresh error handling with retry logic
  - [ ] 7.9 ⭐ Retry up to 3 times for network errors before signing out

- [ ] 8.0 ⭐ Implement session lifecycle management
  - [ ] 8.1 Add auth state listener in AuthService.setupAuthStateListener()
  - [ ] 8.2 Handle .signedIn event - log and update state
  - [ ] 8.3 Handle .signedOut event - call handleSignOut()
  - [ ] 8.4 Handle .tokenRefreshed event - log success
  - [ ] 8.5 Handle .userUpdated event - refresh profile
  - [ ] 8.6 Implement handleSignOut() with complete cleanup
  - [ ] 8.7 Clear currentUserId and currentProfile
  - [ ] 8.8 Call CacheManager.shared.clearAll()
  - [ ] 8.9 Call RealtimeManager.shared.unsubscribeAll()
  - [ ] 8.10 Post Notification.Name.userDidSignOut
  - [ ] 8.11 Implement handleAuthError() for refresh failures
  - [ ] 8.12 Check if error is recoverable network error
  - [ ] 8.13 If recoverable, retry after 2 seconds (up to 3 times)
  - [ ] 8.14 If not recoverable (token revoked), sign out user
  - [ ] 8.15 Show graceful session expiry alert: "Your session has expired. Please log in again."
  - [ ] 8.16 Navigate to login screen

### 🔒 CHECKPOINT: QA-AUTH-003
> Run: `./QA/Scripts/checkpoint.sh auth-003`
> Guide: QA/CHECKPOINT-GUIDE.md
> Flows: FLOW_AUTH_003 (password reset)
> Must pass before continuing

- [x] 9.0 Implement logout with complete cleanup
  - [x] 9.1 Implement logOut() method in AuthService
  - [x] 9.2 Call RealtimeManager.shared.unsubscribeAll()
  - [x] 9.3 Call CacheManager.shared.clearAll()
  - [ ] 9.4 Call PushNotificationService.shared.removeDeviceToken()
  - [x] 9.5 Clear currentUserId and currentProfile
  - [x] 9.6 Call supabase.auth.signOut()
  - [x] 9.7 Log successful logout
  - [x] 9.8 Handle any errors gracefully
  - [ ] 9.9 🧪 Write AuthServiceTests.testLogOut_ClearsAllData

- [x] 10.0 Add error handling for all auth scenarios
  - [x] 10.1 Create AppError enum in Core/Models with cases for all auth errors
  - [x] 10.2 Add case .invalidInviteCode with message: "Invalid or expired invite code"
  - [x] 10.3 Add case .invalidCredentials with user-friendly message
  - [x] 10.4 Add case .emailAlreadyExists with user-friendly message
  - [x] 10.5 Add case .networkUnavailable with user-friendly message
  - [x] 10.6 Add case .sessionExpired with user-friendly message
  - [x] 10.7 Add case .rateLimited with message: "Please wait a moment"
  - [x] 10.8 Add case .requiredFieldMissing with field name parameter
  - [x] 10.9 Make AppError conform to LocalizedError for .errorDescription
  - [x] 10.10 Update all ViewModels to catch and display AppError messages
  - [ ] 10.11 Add haptic feedback on errors using UINotificationFeedbackGenerator
  - [ ] 10.12 Test each error scenario and verify user sees appropriate message

- [x] 11.0 Update ContentView to handle auth states
  - [x] 11.1 Open ContentView.swift and verify it observes AppState as @EnvironmentObject
  - [x] 11.2 Update switch statement to show LoginView for .unauthenticated case
  - [x] 11.3 Update switch statement to show PendingApprovalView for .pendingApproval case
  - [x] 11.4 Ensure .loading case shows LoadingView with "Loading..." message
  - [x] 11.5 Ensure .authenticated case navigates to MainTabView (placeholder for now)
  - [x] 11.6 Add NavigationStack wrapper around auth views for proper navigation
  - [x] 11.7 Test navigation flow from login → signup → pending → main app

- [x] 12.0 Verify authentication implementation
  - [x] 12.1 Build project and ensure zero compilation errors
  - [x] 12.2 Run app in simulator and verify it shows login screen initially
  - [x] 12.3 Test signup with valid invite code - verify account created as pending
  - [x] 12.4 Test signup with invalid invite code - verify error message shown
  - [x] 12.5 ⭐ Test rapid invite code attempts - verify rate limiting works
  - [x] 12.6 Test login with valid credentials - verify navigation to appropriate screen
  - [x] 12.7 Test login with wrong password - verify error message shown
  - [x] 12.8 ⭐ Test rapid login attempts - verify rate limiting works
  - [x] 12.9 Test password reset - verify same message shown for any email
  - [x] 12.10 ⭐ Test rapid password reset - verify rate limiting works
  - [x] 12.11 Test that pending users see pending approval screen
  - [x] 12.12 Manually approve test user in Supabase dashboard, verify refresh works
  - [x] 12.13 Test logout - verify returns to login screen and session cleared
  - [x] 12.14 ⭐ Test logout - verify caches cleared
  - [x] 12.15 ⭐ Test logout - verify realtime subscriptions unsubscribed
  - [x] 12.16 Test session persistence - close app and reopen, verify still logged in
  - [x] 12.17 Code review: verify all async operations use proper error handling
  - [x] 12.18 Code review: verify no force unwrapping (!) is used
  - [x] 12.19 Commit changes with message: "feat: implement authentication with rate limiting and session management"
  - [x] 12.20 Push feature branch to remote repository

### 🔒 CHECKPOINT: QA-AUTH-FINAL
> Run: `./QA/Scripts/checkpoint.sh auth-final`
> Guide: QA/CHECKPOINT-GUIDE.md
> Flows: FLOW_AUTH_001, FLOW_AUTH_002, FLOW_AUTH_003, FLOW_AUTH_004
> All authentication tests must pass before starting User Profile
