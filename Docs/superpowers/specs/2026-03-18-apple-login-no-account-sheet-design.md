# Auth Flow: Apple Login No-Account Sheet

**Date:** 2026-03-18
**Status:** Reviewed — production-ready
**Approach:** Minimal Patch (Approach A)

---

## Problem

When a user taps "Sign in with Apple" on the login screen and no linked account exists, the app throws a technical `.processingError` with language about "Hide My Email" and "private relay." App Review interpreted this as broken Sign in with Apple.

## Goal

Replace the technical error with a friendly sheet that explains no account exists and offers clear next steps. No other auth behavior changes.

## Scope

| File | Change |
|---|---|
| `Core/Protocols/AuthServiceProtocol.swift` | Add `AppleLoginResult` enum above protocol; update `logInWithApple` return type |
| `Core/Services/AuthService+AppleSignIn.swift` | `logInWithApple` returns `.noAccountFound` for missing profile, re-throws real errors; add `isProfileNotFoundError` helper; clear local Supabase session on cleanup |
| `Features/Authentication/ViewModels/AppleSignInViewModel.swift` | New `@Published var showNoAccountSheet` flag, reset on each attempt, set on `.noAccountFound` |
| `Features/Authentication/Views/LoginView.swift` | Bind sheet to ViewModel's `showNoAccountSheet`; add `onDismiss`-driven nav; add `.navigationDestination` for signup |
| **New:** `Features/Authentication/Views/NoAccountFoundSheet.swift` | Friendly sheet with two action buttons |
| `Resources/Localizable.xcstrings` | 5 new localization keys |

**Not touched:** `AuthService.swift`, `AppState.swift`, `AppLaunchManager.swift`, signup flow, invite code validation, pending approval screen, launch state machine, any fragile system.

---

## Design

### 1. New Result Type

```swift
/// Defined in AuthServiceProtocol.swift, above the protocol declaration.
enum AppleLoginResult: Sendable {
    case success
    case noAccountFound
}
```

Placed in the protocol file because the protocol's method signature references it. Simple enum with no associated values — implicitly `Sendable`. `AppleSignInViewModel` is the **only** consumer of `logInWithApple` (confirmed by grep).

### 2. AuthService+AppleSignIn.swift — `logInWithApple`

**Current behavior:** When profile fetch fails after successful Apple auth, the method cleans up the orphaned auth user and throws a technical `.processingError` string.

**New behavior:** The entire method, showing exactly what changes:

```swift
func logInWithApple(
    credential: ASAuthorizationAppleIDCredential,
    rawNonce: String? = nil
) async throws -> AppleLoginResult {
    isLoading = true
    defer { isLoading = false }

    guard let identityTokenData = credential.identityToken,
          let identityToken = String(data: identityTokenData, encoding: .utf8) else {
        throw AppError.unknown("Failed to get Apple identity token")
    }

    // signInWithIdToken creates a Supabase session (and possibly a new auth
    // user). If no profile exists, we must clean up BOTH the server-side
    // auth user AND the local session before returning .noAccountFound.
    let session = try await SupabaseService.shared.client.auth.signInWithIdToken(
        credentials: OpenIDConnectCredentials(
            provider: .apple,
            idToken: identityToken,
            nonce: rawNonce
        )
    )

    let userIdString = session.user.id.uuidString
    guard let userId = UUID(uuidString: userIdString) else {
        throw AppError.invalidCredentials
    }

    do {
        let profile = try await ProfileService.shared.fetchProfile(userId: userId)

        // Update local state
        currentUserId = userId
        currentProfile = profile

        // Store Apple user identifier for credential checking
        AppleUserKeychain.save(credential.user)

        AppLogger.auth.info("User logged in with Apple: \(userId), approved: \(profile.approved)")
        return .success
    } catch {
        // ── CHANGED SECTION ──────────────────────────────────────────
        // Distinguish "no profile exists" from transient failures.
        // Only treat PostgREST "no rows" as .noAccountFound.
        // All other errors (network, decode, server 500) are re-thrown
        // so the existing error alert fires in the UI.
        guard isProfileNotFoundError(error) else {
            throw error
        }

        AppLogger.auth.warning("Apple login: no profile for user \(userId). Cleaning up.")

        // 1. Delete the orphaned server-side auth user (idempotent, never throws)
        await cleanupOrphanedAuthUser(userIdString: userIdString)

        // 2. Clear the local Supabase session that signInWithIdToken created.
        //    Use the raw Supabase client — NOT AuthService.signOut() — to avoid
        //    firing .userDidSignOut notifications or tearing down sync engines
        //    for a login that never completed.
        try? await SupabaseService.shared.client.auth.signOut()

        return .noAccountFound
        // ── END CHANGED SECTION ──────────────────────────────────────
    }
}
```

**`isProfileNotFoundError` helper** — added as a private method on `AuthService`, in the same file:

```swift
/// Check if an error indicates "no rows returned" from a .single() query.
/// Uses typed PostgrestError check, matching the pattern in ConversationService
/// and BadgeCountManager. Only PostgrestError passes — URLError, DecodingError,
/// and other failure types fall through to `false` and get re-thrown as real errors.
private func isProfileNotFoundError(_ error: Error) -> Bool {
    guard let pgError = error as? PostgrestError else {
        return false
    }
    // Primary: PostgREST error code for ".single() returned 0 rows"
    if pgError.code == "PGRST116" {
        return true
    }
    // Fallback: message matching for SDK/PostgREST version variance.
    // The .single() modifier produces "JSON object requested, multiple (or no)
    // rows returned" — we check the structured message field, not localizedDescription.
    let msg = (pgError.message ?? "").lowercased()
    return msg.contains("json object requested") || msg.contains("0 rows")
}
```

**Why this is safe:**
- Only `PostgrestError` can match — network errors, timeouts, decode errors all fall through to `return false` and get re-thrown
- Checks `code` first (typed), then `message` (structured SDK field) — never `localizedDescription`
- Follows the established pattern in `ConversationService.swift:177-180` and `BadgeCountManager.swift:448`
- Local Supabase session is cleared after cleanup, preventing stale session state
- `cleanupOrphanedAuthUser` is idempotent and never throws

**Protocol update** in `AuthServiceProtocol.swift`:

```swift
func logInWithApple(credential: ASAuthorizationAppleIDCredential, rawNonce: String?) async throws -> AppleLoginResult
```

### 3. AppleSignInViewModel.swift

**New property:**

```swift
@Published var showNoAccountSheet = false
```

**Reset at the top of `handleSignInCompletion`:**

```swift
isLoading = true
error = nil
showNoAccountSheet = false  // reset for subsequent attempts
```

**Changed code in `handleSignInCompletion`**, login branch only:

```swift
} else {
    // Existing user login with Apple
    let result = try await authService.logInWithApple(
        credential: credential,
        rawNonce: currentNonce
    )
    if result == .noAccountFound {
        showNoAccountSheet = true
        isLoading = false
        return
    }
}
```

When `.noAccountFound` is returned, `error` stays `nil`, so the existing `.alert` does not fire. The sheet takes over via binding.

The `isNewUser == true` signup branch, `.failure` handling (including cancellation), nonce generation, and real error `catch` are all unchanged.

**Cancellation behavior (confirmed safe):** Apple cancellation fires in `.failure`, sets `isLoading = false`, returns early. `showNoAccountSheet` remains `false`, `error` remains `nil`. The existing completion handler in `LoginView` then calls `performCriticalLaunch()`, which finds no session and resolves to unauthenticated — a harmless no-op from the user's perspective. This is existing behavior, unchanged by this patch.

### 4. LoginView.swift

**New state:**

```swift
@State private var didRequestCreateAccount = false
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
    // Sheet presentation handled by binding — no action needed
} else if appleSignInViewModel.error == nil {
    await AppLaunchManager.shared.performCriticalLaunch()
} else {
    showError = true
}
```

**New modifiers** (placed after the existing `.sheet(isPresented: $showPasswordReset)`):

```swift
.sheet(isPresented: $appleSignInViewModel.showNoAccountSheet, onDismiss: {
    // Set navigateToSignup ONLY after the sheet animation completes.
    // This avoids the known SwiftUI race where setting navigation state
    // during a sheet dismiss causes the push to silently fail.
    if didRequestCreateAccount {
        didRequestCreateAccount = false
        navigateToSignup = true
    }
}) {
    NoAccountFoundSheet(didRequestCreateAccount: $didRequestCreateAccount)
}
.navigationDestination(isPresented: $navigateToSignup) {
    SignupInviteCodeView()
}
```

**Why this pattern is safe:**
- `didRequestCreateAccount` is a flag set by the sheet's button, but navigation is not triggered until `onDismiss` fires
- `onDismiss` runs only after the sheet dismiss animation completes
- `navigateToSignup` is set inside `onDismiss`, so `.navigationDestination` evaluates cleanly with no animation overlap
- `.navigationDestination(isPresented:)` automatically resets `navigateToSignup` to `false` when the user navigates back
- `didRequestCreateAccount` is reset immediately after use in `onDismiss`
- Swipe-dismiss: `didRequestCreateAccount` remains `false`, `onDismiss` does nothing, user returns to login screen

### 5. NoAccountFoundSheet.swift (New File)

**Location:** `NaarsCars/NaarsCars/Features/Authentication/Views/NoAccountFoundSheet.swift`

```swift
//
//  NoAccountFoundSheet.swift
//  NaarsCars
//

import SwiftUI

/// Sheet presented when Apple Sign-In succeeds but no Naar's Cars account
/// exists for the authenticated Apple ID. Offers to create an account
/// or switch to email login.
struct NoAccountFoundSheet: View {
    @Environment(\.dismiss) private var dismiss
    @Binding var didRequestCreateAccount: Bool

    var body: some View {
        VStack(spacing: 24) {
            // Custom drag indicator (system one hidden for consistent styling)
            Capsule()
                .fill(Color.secondary.opacity(0.3))
                .frame(width: 36, height: 5)
                .padding(.top, 12)

            Image(systemName: "person.crop.circle.badge.plus")
                .font(.system(size: 56))
                .foregroundStyle(.naarsPrimary)
                .accessibilityHidden(true)

            Text("auth_create_account_needed_title".localized)
                .font(.naarsTitle3)
                .multilineTextAlignment(.center)

            Text("auth_create_account_needed_body".localized)
                .font(.naarsBody)
                .foregroundStyle(.secondary)
                .multilineTextAlignment(.center)
                .padding(.horizontal)

            VStack(spacing: 12) {
                Button {
                    didRequestCreateAccount = true
                    dismiss()
                } label: {
                    Text("auth_create_account_button".localized)
                        .frame(maxWidth: .infinity)
                }
                .buttonStyle(.borderedProminent)
                .accessibilityIdentifier("noAccount.createAccount")

                Button {
                    dismiss()
                } label: {
                    Text("auth_use_email_instead_button".localized)
                        .frame(maxWidth: .infinity)
                }
                .buttonStyle(.bordered)
                .accessibilityIdentifier("noAccount.useEmail")
            }

            Text("auth_create_account_needed_footer".localized)
                .font(.naarsCaption)
                .foregroundStyle(.tertiary)
                .multilineTextAlignment(.center)
                .padding(.horizontal)

            Spacer()
        }
        .padding(.horizontal, 24)
        .presentationDetents([.medium])
        .presentationDragIndicator(.hidden)
        .accessibilityIdentifier("noAccountFoundSheet")
    }
}
```

### 6. Localization Keys

| Key | Value |
|---|---|
| `auth_create_account_needed_title` | "Welcome to Naar's Cars" |
| `auth_create_account_needed_body` | "Looks like you're new here! To get started, you'll need an invite code from a current member." |
| `auth_create_account_button` | "Create Account" |
| `auth_use_email_instead_button` | "Use Email Instead" |
| `auth_create_account_needed_footer` | "If you already have an account, try signing in with your email and password." |

All added to `Resources/Localizable.xcstrings`.

**Copy rationale:** "Welcome" framing instead of "No Account Found" — the state should feel like a natural branch in the flow, not an error. "Looks like you're new here" is warm and intentional. "Use Email Instead" (not "Sign In with Email") frames it as a natural alternative. The `person.crop.circle.badge.plus` icon suggests creation, not confusion.

---

## User-Facing States (Complete)

| State | What user sees |
|---|---|
| **Login success** (email or Apple) | Transitions to main app or pending approval — no change |
| **Apple login, no account** | Sheet: "Welcome to Naar's Cars" with Create Account / Use Email Instead |
| **Apple login, no account, sheet swipe-dismissed** | Returns to login screen in original state (same as "Use Email Instead") |
| **Apple login, sheet → Create Account** | Sheet dismisses, then navigates to SignupInviteCodeView |
| **Apple login, real failure** (network/token) | Alert with error message — no change to existing behavior |
| **Apple login, user cancelled** | Silent reset — no sheet, no alert, no change to existing behavior |
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

A reviewer may tap Apple on the login screen, see the "Welcome" sheet, and flag it. The App Review Information note below preempts this.

### App Review Information Note

> **Naar's Cars is an invite-only community app.** New accounts require a valid invite code from an existing member.
>
> **To test the app, use these credentials:**
> - Email: [reviewer test email]
> - Password: [reviewer test password]
>
> **Sign in with Apple:** Works for returning users who already have an account. If a reviewer authenticates with Apple and no linked account exists, the app displays a welcome prompt explaining how to create an account with an invite code.
>
> **To test account creation:** Use invite code `[REVIEWER_CODE]` on the Create Account screen. After signup, the account will be auto-approved for review purposes.
>
> **Account deletion** is available at Settings > Account > Delete Account.

**Important:** Ensure the reviewer test code auto-approves accounts (bypasses pending approval) so the reviewer can complete the full flow.

---

## Verification Plan

1. **Apple login, existing account** — logs in normally (no regression)
2. **Apple login, no account** — "Welcome" sheet appears with correct copy
3. **"Create Account" button** — sheet dismisses fully, THEN navigates to SignupInviteCodeView
4. **"Use Email Instead" button** — dismisses sheet, returns to LoginView
5. **Sheet swipe-dismiss** — returns to LoginView, same as "Use Email Instead"
6. **Apple login, network error** — existing alert fires (NOT the sheet)
7. **Apple login, Supabase 500** — existing alert fires (NOT the sheet)
8. **Apple login, user cancels** — silent, no sheet, no alert
9. **Apple login, no account, retry** — dismiss sheet, tap Apple again: sheet appears fresh
10. **Apple signup via invite code** — existing flow unchanged
11. **Email/password login** — unchanged
12. **Pending approval** — unchanged
13. **Deep link with invite code** — unchanged
14. **After "no account" cleanup, app foreground** — no stale session (verified by local signOut)

**Unit tests:** Not added per CLAUDE.md ("Do not add tests unless explicitly asked"). Tests for `isProfileNotFoundError`, the result path, and sheet presentation can be added on request.
