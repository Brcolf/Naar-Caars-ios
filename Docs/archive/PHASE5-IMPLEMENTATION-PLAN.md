# Phase 5 Implementation Plan: Apple Sign-In & Biometric Auth

## Overview

Implementing two Phase 5 features that enhance authentication UX:
1. **Apple Sign-In**: Social login option that still requires invite codes for new users
2. **Biometric Auth**: Face ID/Touch ID for quick app unlock

## Integration Analysis

### Current State
- ✅ Info.plist already has `NSFaceIDUsageDescription` configured
- ✅ Invite code flow is fully implemented
- ✅ AuthService handles email/password authentication
- ✅ Signup flow is two-step: invite code → details entry

### Apple Sign-In Flow Decisions Needed

**Question 1: Apple Sign-In Button Placement**
- Should Apple Sign-In button appear on:
  - LoginView only? 
  - Both LoginView AND SignupInviteCodeView?
  - Or a separate "Choose Sign-In Method" screen after invite code validation?

**Question 2: New User Flow**
- PRD says: "Apple signup still requires invite code"
- Proposed flow:
  1. User enters invite code (existing flow)
  2. After validation, show: "Continue with Apple" OR "Continue with Email"
  3. If Apple: Authenticate with Apple → Create account with invite code
  4. If Email: Show SignupDetailsView (existing flow)
  
  **Is this correct?**

**Question 3: Existing User Flow**
- For users who already have an account:
  - Should they be able to link Apple ID to existing email/password account?
  - Or must they use the same auth method they signed up with?

**Question 4: Hidden Email Handling**
- When user chooses "Hide My Email", Apple provides relay address
- Should we:
  - Always use relay email for profile?
  - Or prompt user to provide real email (optional) for admin contact?

### Biometric Auth Flow Decisions Needed

**Question 5: Biometric Unlock Timing**
- Should biometric unlock work:
  - Only after user has been authenticated at least once? ✅ Recommended
  - Even if user just signed up (pending approval)?
  
**Question 6: Approval Status Handling**
- If user is `pendingApproval` and tries to unlock with biometrics:
  - Should biometric unlock work, but show PendingApprovalView after unlock?
  - Or should biometric unlock be disabled until approved?
  
  **Recommendation**: Allow unlock, show appropriate screen (matches current email/password behavior)

**Question 7: Biometric Settings Location**
- Where should biometric settings live?
  - In ProfileView (Settings section)?
  - Or separate SecuritySettingsView accessible from Profile?

**Question 8: Biometric + Apple Sign-In Interaction**
- If user signs in with Apple and has Face ID enabled:
  - Should Face ID unlock automatically sign them in with Apple (cached credential)?
  - Or just unlock the app (they're already authenticated via session)?

  **Recommendation**: Just unlock app (session-based, not credential-based)

## Implementation Approach

### Phase 5A: Apple Sign-In
1. Configure Apple Sign-In capability in Xcode
2. Configure Supabase Apple provider
3. Extend AuthService with Apple methods
4. Create AppleSignInButton component
5. Update signup flow to support Apple option after invite code
6. Update login view to support Apple Sign-In

### Phase 5B: Biometric Auth
1. Create BiometricService
2. Create BiometricPreferences
3. Create AppLockView
4. Create SecuritySettingsView (or integrate into Profile)
5. Integrate with ContentView lifecycle
6. Handle background/foreground state

## Key Integration Points

### Shared Considerations
- Both features enhance authentication UX
- Biometric unlock should work regardless of auth method (email/password or Apple)
- Apple Sign-In must respect invite code requirement for new users
- Both features should respect approval status (biometric unlocks but shows appropriate screen)

### Code Structure
```
Core/Services/
  ├── AuthService.swift (extend with Apple methods)
  ├── BiometricService.swift (NEW)
  └── BiometricPreferences.swift (NEW)

Features/Authentication/
  ├── Views/
  │   ├── LoginView.swift (add Apple button)
  │   ├── SignupInviteCodeView.swift (add Apple option after validation)
  │   ├── SignupDetailsView.swift (keep existing email/password flow)
  │   └── AppleSignInButton.swift (NEW)
  └── ViewModels/
      └── AppleSignInViewModel.swift (NEW - optional, may handle in AuthService)

Features/Authentication/ or Features/Profile/
  └── Views/
      ├── AppLockView.swift (NEW)
      └── SecuritySettingsView.swift (NEW - or add to ProfileView)
```

## Dependencies

- ✅ LocalAuthentication framework (standard iOS)
- ✅ AuthenticationServices framework (standard iOS)
- ✅ Supabase Apple provider configuration
- ✅ Apple Developer account configuration
- ✅ Info.plist already configured for Face ID

## Testing Requirements

### Apple Sign-In
- [ ] Test new user signup with Apple + invite code
- [ ] Test existing user login with Apple
- [ ] Test hidden email flow
- [ ] Test account linking (if implemented)

### Biometric Auth
- [ ] Test Face ID unlock on Face ID devices
- [ ] Test Touch ID unlock on Touch ID devices
- [ ] Test passcode fallback
- [ ] Test background timeout behavior
- [ ] Test enable/disable toggle
- [ ] Test with pending approval status

## Questions for Product/User

See "Questions" section above. Need clarification before proceeding with implementation.

