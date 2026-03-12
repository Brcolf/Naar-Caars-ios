---
color: indigo
position:
  x: -808
  y: -1781
isContextNode: false
agent_name: Amy
---

# Feature: Authentication

User authentication and onboarding flows.

## Views
- **LoginView.swift** - Email/password login with Apple Sign In
- **SignUpView.swift** - New user registration with invite code
- **AppleSignInButton.swift** - Native Apple Sign In button wrapper
- **PendingApprovalView.swift** - Waiting screen for admin approval
- **AppLockView.swift** - Biometric authentication lock screen

## ViewModels
- **LoginViewModel.swift** - Login form validation and auth state
- **SignUpViewModel.swift** - Registration flow with invite code verification

## Services
- **AuthService.swift** - Core authentication (session, sign up/in/out)
- **AuthService+AppleSignIn.swift** - Apple Sign In integration
- **BiometricService.swift** - Face ID / Touch ID support

## Key Flows

### Sign Up Flow
1. User enters email, password, invite code
2. `AuthService.signUp()` creates Supabase auth user
3. Polls for profile creation (database trigger)
4. Profile created with `approved = false`
5. Shows `PendingApprovalView` until admin approves

### Login Flow
1. User enters credentials or uses Apple Sign In
2. `AuthService.signIn()` validates with Supabase
3. Fetches user profile
4. Routes to main app if approved, else pending approval

### App Lock
- Biometric authentication required after 5 minutes in background
- Configurable in settings via `BiometricPreferences`
- Blurs app content when locked

## Technical Debt

### 🟡 Client-Side Profile Polling
**Issue:** After signup, client polls for profile creation instead of transactional approach.

**From STRUCTURAL_HANDOFF_AUDIT.md:**
> Move the Signup → Profile Creation → Invite Code logic into a single Postgres function (security definer) to eliminate the client-side polling and potential "zombie user" state.

**Current:** `AuthService.signUp()` → `pollForNewProfile()` with exponential backoff
**Better:** Database function that atomically creates user + profile + validates invite

links to [[/Users/bcolf/Documents/naars-cars-ios/VisualBrain/voicetree-7-2/1770515369146IEM.md]]
