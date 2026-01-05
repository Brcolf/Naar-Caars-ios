# Tasks: Apple Sign-In

Based on `prd-apple-sign-in.md`

## Affected Flows

- FLOW_AUTH_002: Login with Email/Password (extension)

See QA/FLOW-CATALOG.md for flow definitions.

## Relevant Files

### Source Files
- `Core/Services/AuthService.swift` - Extend with Apple auth
- `Features/Authentication/Views/LoginView.swift` - Add Apple button
- `Features/Authentication/Views/AppleSignInButton.swift` - Custom button

### Test Files
- `NaarsCarsTests/Core/Services/AuthServiceTests.swift` - Apple auth tests

## Notes

- Uses AuthenticationServices framework
- Requires Apple Developer account configuration
- First-time users still need invite code
- 🧪 items are QA tasks | 🔒 CHECKPOINT items are mandatory gates

## Tasks

- [ ] 0.0 Create feature branch: `git checkout -b feature/apple-sign-in`

- [ ] 1.0 Configure Apple Sign-In capability
  - [ ] 1.1 Add Sign in with Apple capability in Xcode
  - [ ] 1.2 Configure in Apple Developer Portal
  - [ ] 1.3 Enable in Supabase Dashboard

- [ ] 2.0 Extend AuthService
  - [ ] 2.1 Import AuthenticationServices
  - [ ] 2.2 Implement signInWithApple() method
  - [ ] 2.3 Handle ASAuthorizationController delegate
  - [ ] 2.4 Send Apple credential to Supabase
  - [ ] 2.5 Check if profile exists for Apple ID
  - [ ] 2.6 If new user, require invite code flow
  - [ ] 2.7 🧪 Write AuthServiceTests.testAppleSignIn_ExistingUser_Success
  - [ ] 2.8 🧪 Write AuthServiceTests.testAppleSignIn_NewUser_RequiresInvite

### 🔒 CHECKPOINT: QA-APPLE-001
> Run: `./QA/Scripts/checkpoint.sh apple-001`
> Guide: QA/CHECKPOINT-GUIDE.md
> Verify: Apple auth tests pass
> Must pass before continuing

- [ ] 3.0 Build Apple Sign-In Button
  - [ ] 3.1 Create AppleSignInButton.swift
  - [ ] 3.2 Use SignInWithAppleButton from SwiftUI
  - [ ] 3.3 Style to match app theme
  - [ ] 3.4 Handle tap action

- [ ] 4.0 Update Login View
  - [ ] 4.1 Add AppleSignInButton below regular login
  - [ ] 4.2 Add "or continue with" divider
  - [ ] 4.3 Handle loading state for Apple auth

- [ ] 5.0 Handle new Apple users
  - [ ] 5.1 Detect new vs returning Apple user
  - [ ] 5.2 If new, navigate to invite code screen
  - [ ] 5.3 Link Apple identity after valid invite

- [ ] 6.0 Verify Apple Sign-In
  - [ ] 6.1 Test on real device (required)
  - [ ] 6.2 Test existing user flow
  - [ ] 6.3 Test new user with invite code
  - [ ] 6.4 Test account linking
  - [ ] 6.5 Commit: "feat: implement Apple Sign-In"

### 🔒 CHECKPOINT: QA-APPLE-FINAL
> Run: `./QA/Scripts/checkpoint.sh apple-final`
> Guide: QA/CHECKPOINT-GUIDE.md
> Apple Sign-In tests must pass
