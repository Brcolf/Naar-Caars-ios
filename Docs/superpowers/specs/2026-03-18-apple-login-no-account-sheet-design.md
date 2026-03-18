# Auth Flow: Apple Login No-Account Sheet

**Date:** 2026-03-18
**Status:** Draft
**Approach:** Minimal Patch (Approach A)

---

## Problem

When a user taps "Sign in with Apple" on the login screen and no linked account exists, the app throws a technical `.processingError` with language about "Hide My Email" and "private relay." App Review interpreted this as broken Sign in with Apple.

## Goal

Replace the technical error with a friendly sheet that explains no account exists and offers clear next steps. No other auth behavior changes.

## Scope

| File | Change |
|---|---|
| `Core/Protocols/AuthServiceProtocol.swift` | Add `AppleLoginResult` enum; update `logInWithApple` return type to `AppleLoginResult` |
| `Core/Services/AuthService+AppleSignIn.swift` | `logInWithApple` returns `.noAccountFound` for missing profile, re-throws real errors; add `isProfileNotFoundError` helper |
| `Features/Authentication/ViewModels/AppleSignInViewModel.swift` | New `@Published var showNoAccountSheet` flag, reset on each attempt, set on `.noAccountFound` |
| `Features/Authentication/Views/LoginView.swift` | Bind sheet to ViewModel's `showNoAccountSheet`; add `onDismiss` nav trigger; add `.navigationDestination` for signup |
| **New:** `Features/Authentication/Views/NoAccountFoundSheet.swift` | Friendly sheet with two action buttons |
| `Resources/Localizable.xcstrings` | 5 new localization keys |

**Not touched:** `AuthService.swift`, `AppState.swift`, `AppLaunchManager.swift`, signup flow, invite code validation, pending approval screen, launch state machine, any fragile system.

---

## Design

### 1. New Result Type

```swift
enum AppleLoginResult: Sendable {
    case success
    case noAccountFound
}
```

Defined in `Core/Protocols/AuthServiceProtocol.swift` alongside the protocol (since the protocol's `logInWithApple` method returns this type, it must be visible there). Simple enum with no associated values — implicitly `Sendable`.

### 2. AuthService+AppleSignIn.swift — `logInWithApple`

**Current behavior:** When profile fetch fails after successful Apple auth, the method cleans up the orphaned auth user and throws:

```swift
throw AppError.processingError(
    "No account found for this Apple ID. If you chose \"Hide My Email\"..."
)
```

**New behavior:** Same cleanup, but returns `.noAccountFound` instead of throwing — only for the "no profile" case. Real errors (network, decoding, Supabase 500) are re-thrown so the error alert still fires:

```swift
func logInWithApple(
    credential: ASAuthorizationAppleIDCredential,
    rawNonce: String? = nil
) async throws -> AppleLoginResult {
    isLoading = true
    defer { isLoading = false }

    // ... existing token extraction and signInWithIdToken (unchanged) ...

    do {
        let profile = try await ProfileService.shared.fetchProfile(userId: userId)
        currentUserId = userId
        currentProfile = profile
        AppleUserKeychain.save(credential.user)
        AppLogger.auth.info("User logged in with Apple: \(userId), approved: \(profile.approved)")
        return .success
    } catch {
        // Distinguish "no profile exists" from transient failures.
        // ProfileService.fetchProfile uses .single() which throws a
        // PostgREST error with code "PGRST116" (0 rows) when no
        // profile exists. Any other error is a real failure.
        if isProfileNotFoundError(error) {
            AppLogger.auth.warning("Apple login succeeded but no profile found for user \(userId). Cleaning up.")
            await cleanupOrphanedAuthUser(userIdString: userIdString)
            return .noAccountFound
        } else {
            // Real failure (network, decoding, server error) — re-throw
            // so the existing error alert fires in the UI.
            throw error
        }
    }
}
```

The `isProfileNotFoundError(_:)` helper checks whether the error is a PostgREST "0 rows" response from `.single()`. This is a small private helper on `AuthService` — the exact check depends on the error type returned by the Supabase SDK (typically checking for `PostgrestError` with code `PGRST116` or HTTP 406). If the SDK error type is opaque, a fallback approach is to check the error's `localizedDescription` for "0 rows" — but the typed check is preferred.

Everything else in the method is unchanged: token extraction, `signInWithIdToken`, keychain save on success, orphaned user cleanup on no-profile. The existing `defer { isLoading = false }` remains.

**Protocol update:** `AuthServiceProtocol.logInWithApple` return type changes from `Void` to `AppleLoginResult`:

```swift
// In AuthServiceProtocol.swift:
func logInWithApple(credential: ASAuthorizationAppleIDCredential, rawNonce: String?) async throws -> AppleLoginResult
```

`AppleSignInViewModel` is the **only** consumer of `logInWithApple` (confirmed by grep). No other callers need updating.

### 3. AppleSignInViewModel.swift

**New property:**

```swift
@Published var showNoAccountSheet = false
```

**Reset at the top of `handleSignInCompletion`** — add `showNoAccountSheet = false` alongside the existing `error = nil` so the flag is clean for each attempt:

```swift
isLoading = true
error = nil
showNoAccountSheet = false  // reset for subsequent attempts
```

**Changed code in `handleSignInCompletion`**, login branch only:

```swift
// Current:
try await authService.logInWithApple(credential: credential, rawNonce: currentNonce)

// New:
let result = try await authService.logInWithApple(credential: credential, rawNonce: currentNonce)
if result == .noAccountFound {
    showNoAccountSheet = true
    isLoading = false
    return
}
```

When `.noAccountFound` is returned, `error` stays `nil`. The existing `.alert` in `LoginView` (triggered by `error != nil`) does not fire. The sheet takes over. If the user dismisses the sheet and taps Apple again, `showNoAccountSheet` is reset to `false` at the top of the next call, so a fresh attempt works correctly.

The `isNewUser == true` signup branch, request handling, nonce generation, cancellation handling, and real error handling are all unchanged.

### 4. LoginView.swift

**New state:**

```swift
@State private var navigateToSignup = false
```

No separate `showNoAccountSheet` state on the View. The sheet binds directly to the ViewModel's `@Published var showNoAccountSheet` to avoid duplicated state (per CLAUDE.md State Management Rule 7).

**Apple completion handler changes from:**

```swift
if appleSignInViewModel.error == nil {
    await AppLaunchManager.shared.performCriticalLaunch()
} else {
    showError = true
}
```

**To:**

```swift
if appleSignInViewModel.showNoAccountSheet {
    // Sheet binding handles presentation — no action needed here
} else if appleSignInViewModel.error == nil {
    await AppLaunchManager.shared.performCriticalLaunch()
} else {
    showError = true
}
```

**New modifiers:**

```swift
.sheet(isPresented: $appleSignInViewModel.showNoAccountSheet, onDismiss: {
    // Trigger navigation AFTER sheet is fully dismissed to avoid
    // the SwiftUI race between sheet dismiss animation and nav push.
    if navigateToSignup {
        // navigateToSignup was set by the sheet's "Create Account" button.
        // Navigation fires now that the sheet is gone.
    }
}) {
    NoAccountFoundSheet(navigateToSignup: $navigateToSignup)
}
.navigationDestination(isPresented: $navigateToSignup) {
    SignupInviteCodeView()
}
```

**Dismiss/navigate timing:** The "Create Account" button in the sheet sets `navigateToSignup = true` and calls `dismiss()`. The `navigateToSignup` binding is read in the sheet's `onDismiss` closure, which fires only after the sheet animation completes. The `.navigationDestination(isPresented:)` then picks up the `true` value and pushes. This avoids the known SwiftUI race where setting nav state during a sheet dismiss animation causes the push to silently fail.

**Swipe-dismiss behavior:** If the user swipe-dismisses the sheet without tapping either button, `navigateToSignup` remains `false`, `showNoAccountSheet` is set back to `false` by SwiftUI automatically, and the user returns to the login screen in its original state. This is the same as tapping "Sign In with Email."

The existing `.alert` for real Apple errors (network, token) remains unchanged. The existing `.sheet(isPresented: $showPasswordReset)` for password reset remains unchanged.

### 5. NoAccountFoundSheet.swift (New File)

**Location:** `NaarsCars/NaarsCars/Features/Authentication/Views/NoAccountFoundSheet.swift`

**Structure:**

```swift
struct NoAccountFoundSheet: View {
    @Environment(\.dismiss) private var dismiss
    @Binding var navigateToSignup: Bool

    var body: some View {
        VStack(spacing: 24) {
            // Drag indicator
            Capsule()
                .fill(Color.secondary.opacity(0.3))
                .frame(width: 36, height: 5)
                .padding(.top, 12)

            // Icon
            Image(systemName: "person.crop.circle.badge.questionmark")
                .font(.system(size: 56))
                .foregroundStyle(.secondary)
                .accessibilityHidden(true)

            // Headline
            Text("auth_no_account_found_title".localized)
                .font(.naarsTitle3)
                .multilineTextAlignment(.center)

            // Body
            Text("auth_no_account_found_body".localized)
                .font(.naarsBody)
                .foregroundStyle(.secondary)
                .multilineTextAlignment(.center)
                .padding(.horizontal)

            // Actions
            VStack(spacing: 12) {
                Button {
                    navigateToSignup = true
                    dismiss()
                    // Navigation fires in the sheet's onDismiss callback
                    // after the dismiss animation completes.
                } label: {
                    Text("auth_create_account".localized)
                        .frame(maxWidth: .infinity)
                }
                .buttonStyle(.borderedProminent)
                .accessibilityIdentifier("noAccount.createAccount")
                // Button label serves as accessibilityLabel via SwiftUI

                Button {
                    dismiss()
                } label: {
                    Text("auth_sign_in_with_email".localized)
                        .frame(maxWidth: .infinity)
                }
                .buttonStyle(.bordered)
                .accessibilityIdentifier("noAccount.signInWithEmail")
                // Button label serves as accessibilityLabel via SwiftUI
            }

            // Footer
            Text("auth_no_account_found_footer".localized)
                .font(.naarsCaption)
                .foregroundStyle(.tertiary)
                .multilineTextAlignment(.center)
                .padding(.horizontal)

            Spacer()
        }
        .padding(.horizontal, 24)
        .presentationDetents([.medium])
        .presentationDragIndicator(.hidden)  // Hidden because custom Capsule indicator above provides consistent styling
        .accessibilityIdentifier("noAccountFoundSheet")
    }
}
```

### 6. Localization Keys

| Key | Value |
|---|---|
| `auth_no_account_found_title` | "No Account Found" |
| `auth_no_account_found_body` | "It looks like you don't have a Naar's Cars account yet. You'll need an invite code to create one." |
| `auth_create_account` | "Create Account" |
| `auth_sign_in_with_email` | "Sign In with Email" |
| `auth_no_account_found_footer` | "Already have an account? Try signing in with your email and password." |

All added to `Resources/Localizable.xcstrings`.

---

## User-Facing States (Complete)

| State | What user sees |
|---|---|
| **Login success** (email or Apple) | Transitions to main app or pending approval — no change |
| **Apple login, no account** | Sheet: "No Account Found" with Create Account / Sign In with Email |
| **Apple login, no account, sheet swipe-dismissed** | Returns to login screen in original state (same as "Sign In with Email") |
| **Apple login, real failure** (network/token) | Alert with error message — no change to existing behavior |
| **Login, wrong credentials** | Inline error text — no change |
| **Signup, invalid invite** | Inline error text — no change |
| **Signup success, pending approval** | PendingApprovalView — no change |
| **Apple signup (via Create Account path)** | Existing flow via SignupMethodChoiceView — no change |

---

## What Is NOT Changing

- Auth state machine (`initializing → checkingAuth → ready(authState)`)
- Launch routing (`AppLaunchManager`, `ContentView`)
- `AppState`
- Signup flow (invite code → method choice → details/Apple)
- Pending approval screen and polling
- Email/password login
- Apple Sign-In request/nonce handling
- Apple account linking/unlinking/revocation
- Sign-out teardown
- Any realtime, messaging, notification, or sync engine code

---

## App Store Review

### Risks Introduced

None. The change replaces a technical error with a friendly UX sheet. SIWA continues to work for returning users. No new permissions, SDKs, or data collection.

### Pre-Existing Risk

A reviewer may tap Apple on the login screen, see the "No Account Found" sheet, and flag it as a non-functional flow. The App Review Information note below preempts this.

### App Review Information Note

> **Naar's Cars is an invite-only community app.** New accounts require a valid invite code from an existing member.
>
> **To test the app, use these credentials:**
> - Email: [reviewer test email]
> - Password: [reviewer test password]
>
> **Sign in with Apple:** Works for returning users who already have an account. If a reviewer authenticates with Apple and no linked account exists, the app displays a prompt explaining that an account is needed and offers to create one with an invite code.
>
> **To test account creation:** Use invite code `[REVIEWER_CODE]` on the Create Account screen. After signup, the account will be auto-approved for review purposes.
>
> **Account deletion** is available at Settings > Account > Delete Account.

**Important:** Ensure the reviewer test code auto-approves accounts (bypasses pending approval) so the reviewer can complete the full flow.

---

## Verification Plan

1. **Apple login, existing account** — should log in normally (no regression)
2. **Apple login, no account** — sheet appears with correct copy, both buttons work
3. **"Create Account" button** — dismisses sheet, navigates to SignupInviteCodeView
4. **"Sign In with Email" button** — dismisses sheet, returns to LoginView with email field visible
5. **Apple login, network error** — existing alert fires (not the sheet)
6. **Apple signup via invite code** — existing flow unchanged
7. **Email/password login** — unchanged
8. **Pending approval** — unchanged
9. **Deep link with invite code** — unchanged
10. **Apple login, no account, retry** — dismiss sheet, tap Apple again: sheet should appear fresh (not stale from previous attempt)

**Unit tests:** Not added by default per CLAUDE.md ("Do not add tests unless explicitly asked"). Tests for the new result path and sheet presentation can be added on request.
