# Apple Login No-Account Sheet — Implementation Plan

> **For agentic workers:** REQUIRED SUB-SKILL: Use superpowers:subagent-driven-development (recommended) or superpowers:executing-plans to implement this plan task-by-task. Steps use checkbox (`- [ ]`) syntax for tracking.

**Goal:** Replace the technical error shown when Apple Sign-In finds no account with a friendly "Welcome" sheet offering Create Account or Use Email Instead.

**Architecture:** Minimal patch — change the return type of `logInWithApple` from `Void` to `AppleLoginResult`, add a typed error-detection helper, expose a `showNoAccountSheet` flag on the ViewModel, and present a new sheet view from LoginView. No changes to auth state machine, launch routing, or signup flow.

**Tech Stack:** SwiftUI, Supabase Swift SDK (PostgREST error types), ASAuthorizationServices

**Spec:** `Docs/superpowers/specs/2026-03-18-apple-login-no-account-sheet-design.md`

---

## File Map

| File | Action | Responsibility |
|---|---|---|
| `NaarsCars/Core/Protocols/AuthServiceProtocol.swift` | Modify | Add `AppleLoginResult` enum, update protocol signature |
| `NaarsCars/Core/Services/AuthService+AppleSignIn.swift` | Modify | Change `logInWithApple` to return result, add `isProfileNotFoundError`, clear local session on cleanup |
| `NaarsCars/Features/Authentication/ViewModels/AppleSignInViewModel.swift` | Modify | Add `showNoAccountSheet` flag, handle `.noAccountFound` result |
| `NaarsCars/Features/Authentication/Views/LoginView.swift` | Modify | Bind sheet, add `onDismiss`-driven navigation |
| `NaarsCars/Features/Authentication/Views/NoAccountFoundSheet.swift` | Create | New sheet view with two action buttons |
| `NaarsCars/Resources/Localizable.xcstrings` | Modify | Add 5 localization keys |

---

### Task 1: Add `AppleLoginResult` enum and update protocol

**Files:**
- Modify: `NaarsCars/Core/Protocols/AuthServiceProtocol.swift`

- [ ] **Step 1: Add the `AppleLoginResult` enum above the protocol and update the `logInWithApple` signature**

In `AuthServiceProtocol.swift`, replace the entire file content. The changes are:
1. Add `AppleLoginResult` enum before the protocol
2. Change `logInWithApple` return type from `Void` (implicit) to `-> AppleLoginResult`

```swift
//
//  AuthServiceProtocol.swift
//  NaarsCars
//

import Foundation
import AuthenticationServices

/// Result of an Apple login attempt. `.noAccountFound` is not an error —
/// it means Apple auth succeeded but no Naar's Cars profile exists.
enum AppleLoginResult: Sendable {
    case success
    case noAccountFound
}

protocol AuthServiceProtocol: AnyObject {
    var currentUserId: UUID? { get }
    var currentProfile: Profile? { get }

    func signIn(email: String, password: String) async throws
    func signUp(email: String, password: String, name: String, car: String?, inviteCodeId: UUID) async throws
    func signOut() async throws
    func sendPasswordReset(email: String) async throws
    func validateInviteCode(_ code: String) async throws -> InviteCode
    func signUpWithApple(credential: ASAuthorizationAppleIDCredential, inviteCodeId: UUID, rawNonce: String?) async throws
    func logInWithApple(credential: ASAuthorizationAppleIDCredential, rawNonce: String?) async throws -> AppleLoginResult
}
```

- [ ] **Step 2: Verify the project still builds (will fail — AuthService+AppleSignIn doesn't return AppleLoginResult yet)**

Run: `xcodebuild -project NaarsCars/NaarsCars.xcodeproj -scheme NaarsCars -sdk iphonesimulator -configuration Debug build 2>&1 | tail -5`

Expected: Build FAILS with error about `logInWithApple` return type mismatch. This confirms the protocol change is picked up.

- [ ] **Step 3: Commit protocol change**

```bash
git add NaarsCars/Core/Protocols/AuthServiceProtocol.swift
git commit -m "feat(auth): add AppleLoginResult enum and update protocol signature"
```

---

### Task 2: Update `logInWithApple` and add `isProfileNotFoundError` helper

**Files:**
- Modify: `NaarsCars/Core/Services/AuthService+AppleSignIn.swift`

**Context for implementer:** Read `ConversationService.swift:177-180` and `BadgeCountManager.swift:448` to see the existing PostgREST error checking patterns. The new helper follows the same approach.

- [ ] **Step 1: Add `import PostgREST` to the imports**

In `AuthService+AppleSignIn.swift`, add `import PostgREST` after the existing `import Supabase` (line 10). This is needed for the `PostgrestError` type used in `isProfileNotFoundError`.

Find:
```swift
import Supabase
import AuthenticationServices
```

Replace with:
```swift
import Supabase
import PostgREST
import AuthenticationServices
```

- [ ] **Step 2: Replace the `logInWithApple` method**

Find (lines 156-207 — the entire method including doc comment):
```swift
    /// Handle Apple Sign-In for existing users (login flow)
    /// - Parameter credential: Apple ID credential from ASAuthorization
    /// - Throws: AppError if login fails
    func logInWithApple(credential: ASAuthorizationAppleIDCredential, rawNonce: String? = nil) async throws {
        isLoading = true
        defer { isLoading = false }

        guard let identityTokenData = credential.identityToken,
              let identityToken = String(data: identityTokenData, encoding: .utf8) else {
            throw AppError.unknown("Failed to get Apple identity token")
        }

        // Sign in with Supabase using Apple token
        // The rawNonce must match the SHA256 hash embedded in the id_token
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

        // Fetch profile — may not exist if Apple created a new auth user
        // that isn't linked to the existing email/password account
        do {
            let profile = try await ProfileService.shared.fetchProfile(userId: userId)

            // Update local state
            currentUserId = userId
            currentProfile = profile
            // Sync engines started by AppLaunchManager.performDeferredLoading()

            // Store Apple user identifier for credential checking
            AppleUserKeychain.save(credential.user)

            AppLogger.auth.info("User logged in with Apple: \(userId), approved: \(profile.approved)")
        } catch {
            // No profile exists for this Apple auth user.
            // Clean up the orphaned auth user to avoid blocking future signups.
            AppLogger.auth.warning("Apple login succeeded but no profile found for user \(userId). Cleaning up.")
            await cleanupOrphanedAuthUser(userIdString: userIdString)

            throw AppError.processingError(
                "No account found for this Apple ID. If you chose \"Hide My Email\", Apple uses a private address that can't be matched to your account. Please sign in with email and password, then link your Apple ID in Settings. If you re-try and choose to share your real email, it will link automatically."
            )
        }
    }
```

Replace with:
```swift
    /// Handle Apple Sign-In for existing users (login flow)
    /// - Parameter credential: Apple ID credential from ASAuthorization
    /// - Returns: `.success` if profile found, `.noAccountFound` if no profile exists
    /// - Throws: AppError for real failures (network, token, server errors)
    func logInWithApple(credential: ASAuthorizationAppleIDCredential, rawNonce: String? = nil) async throws -> AppleLoginResult {
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

        // Fetch profile — may not exist if Apple created a new auth user
        // that isn't linked to the existing email/password account
        do {
            let profile = try await ProfileService.shared.fetchProfile(userId: userId)

            // Update local state
            currentUserId = userId
            currentProfile = profile
            // Sync engines started by AppLaunchManager.performDeferredLoading()

            // Store Apple user identifier for credential checking
            AppleUserKeychain.save(credential.user)

            AppLogger.auth.info("User logged in with Apple: \(userId), approved: \(profile.approved)")
            return .success
        } catch {
            // Distinguish "no profile exists" from transient failures.
            // Only PostgREST "no rows" errors are treated as .noAccountFound.
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
        }
    }
```

- [ ] **Step 3: Add the `isProfileNotFoundError` helper**

Add this method inside the `extension AuthService` block, in the `// MARK: - Private Helper Methods` section (after the `createOrUpdateAppleProfile` method, before the `// MARK: - Account Deletion` section). Find:

```swift
    // MARK: - Account Deletion with Apple Token Revocation
```

Insert before it:
```swift
    /// Check if an error indicates "no rows returned" from a `.single()` query.
    /// Uses typed `PostgrestError` check, matching the pattern in `ConversationService`
    /// and `BadgeCountManager`. Only `PostgrestError` passes — `URLError`, `DecodingError`,
    /// and other failure types return `false` and get re-thrown as real errors.
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
        // rows returned" — check the structured message field, not localizedDescription.
        let msg = pgError.message.lowercased()
        return msg.contains("json object requested") || msg.contains("0 rows")
    }

    // MARK: - Account Deletion with Apple Token Revocation
```

(Note: remove the duplicate `// MARK:` line — the find/replace should place the helper just above the existing MARK comment.)

- [ ] **Step 4: Build to verify**

Run: `xcodebuild -project NaarsCars/NaarsCars.xcodeproj -scheme NaarsCars -sdk iphonesimulator -configuration Debug build 2>&1 | tail -5`

Expected: Build FAILS — `AppleSignInViewModel` still calls `logInWithApple` without handling the return value. This is expected; we fix it in Task 3.

- [ ] **Step 5: Commit**

```bash
git add NaarsCars/Core/Services/AuthService+AppleSignIn.swift
git commit -m "feat(auth): return AppleLoginResult from logInWithApple, add isProfileNotFoundError helper

logInWithApple now returns .noAccountFound instead of throwing a technical
error when no profile exists. Real errors (network, decode) are still thrown.
Local Supabase session is cleared after orphaned user cleanup."
```

---

### Task 3: Update `AppleSignInViewModel` to handle `.noAccountFound`

**Files:**
- Modify: `NaarsCars/Features/Authentication/ViewModels/AppleSignInViewModel.swift`

- [ ] **Step 1: Add the `showNoAccountSheet` property**

Find:
```swift
    @Published var isLoading = false
    @Published var error: AppError?
```

Replace with:
```swift
    @Published var isLoading = false
    @Published var error: AppError?
    @Published var showNoAccountSheet = false
```

- [ ] **Step 2: Reset `showNoAccountSheet` at the top of `handleSignInCompletion`**

Find:
```swift
        isLoading = true
        error = nil
```

Replace with:
```swift
        isLoading = true
        error = nil
        showNoAccountSheet = false
```

- [ ] **Step 3: Handle the `AppleLoginResult` return value in the login branch**

Find:
```swift
                } else {
                    // Existing user login with Apple
                    try await authService.logInWithApple(
                        credential: credential,
                        rawNonce: currentNonce
                    )
                }
```

Replace with:
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

- [ ] **Step 4: Build to verify**

Run: `xcodebuild -project NaarsCars/NaarsCars.xcodeproj -scheme NaarsCars -sdk iphonesimulator -configuration Debug build 2>&1 | tail -5`

Expected: Build SUCCEEDS. The ViewModel now handles the return value correctly. LoginView hasn't changed yet but still compiles because `showNoAccountSheet` doesn't require a view binding to exist.

- [ ] **Step 5: Commit**

```bash
git add NaarsCars/Features/Authentication/ViewModels/AppleSignInViewModel.swift
git commit -m "feat(auth): handle AppleLoginResult.noAccountFound in AppleSignInViewModel

Sets showNoAccountSheet flag instead of error when no profile exists.
Flag is reset at the start of each sign-in attempt."
```

---

### Task 4: Create `NoAccountFoundSheet.swift`

**Files:**
- Create: `NaarsCars/Features/Authentication/Views/NoAccountFoundSheet.swift`

**Note:** This file goes in the Xcode filesystem-synced group — no `project.pbxproj` edit needed.

- [ ] **Step 1: Create the sheet view file**

Create `NaarsCars/Features/Authentication/Views/NoAccountFoundSheet.swift` with:

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

- [ ] **Step 2: Build to verify the new file is picked up**

Run: `xcodebuild -project NaarsCars/NaarsCars.xcodeproj -scheme NaarsCars -sdk iphonesimulator -configuration Debug build 2>&1 | tail -5`

Expected: Build SUCCEEDS. The file is auto-discovered by Xcode's filesystem-synced groups. The localization keys will show warnings (keys not in xcstrings yet) but this is not a build failure.

- [ ] **Step 3: Commit**

```bash
git add NaarsCars/Features/Authentication/Views/NoAccountFoundSheet.swift
git commit -m "feat(auth): add NoAccountFoundSheet view

Friendly welcome sheet with Create Account and Use Email Instead buttons.
Uses onDismiss-driven navigation pattern (wired in LoginView next)."
```

---

### Task 5: Wire up `LoginView` to present the sheet and handle navigation

**Files:**
- Modify: `NaarsCars/Features/Authentication/Views/LoginView.swift`

- [ ] **Step 1: Add new state properties**

Find:
```swift
    @State private var showPasswordReset = false
    @State private var showError = false
    @State private var showSuccess = false
```

Replace with:
```swift
    @State private var showPasswordReset = false
    @State private var showError = false
    @State private var showSuccess = false
    @State private var didRequestCreateAccount = false
    @State private var navigateToSignup = false
```

- [ ] **Step 2: Update the Apple Sign-In completion handler**

Find:
```swift
                                // If successful, trigger AppLaunchManager to re-check auth state
                                if appleSignInViewModel.error == nil {
                                    await AppLaunchManager.shared.performCriticalLaunch()
                                } else {
                                    showError = true
                                }
```

Replace with:
```swift
                                if appleSignInViewModel.showNoAccountSheet {
                                    // Sheet presentation handled by binding — no action needed
                                } else if appleSignInViewModel.error == nil {
                                    await AppLaunchManager.shared.performCriticalLaunch()
                                } else {
                                    showError = true
                                }
```

- [ ] **Step 3: Add the sheet and navigationDestination modifiers**

Find:
```swift
        .sheet(isPresented: $showPasswordReset) {
            PasswordResetView()
        }
```

Replace with:
```swift
        .sheet(isPresented: $showPasswordReset) {
            PasswordResetView()
        }
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

- [ ] **Step 4: Build to verify**

Run: `xcodebuild -project NaarsCars/NaarsCars.xcodeproj -scheme NaarsCars -sdk iphonesimulator -configuration Debug build 2>&1 | tail -5`

Expected: Build SUCCEEDS.

- [ ] **Step 5: Commit**

```bash
git add NaarsCars/Features/Authentication/Views/LoginView.swift
git commit -m "feat(auth): wire NoAccountFoundSheet into LoginView

Sheet bound to ViewModel's showNoAccountSheet. Navigation to
SignupInviteCodeView triggered via onDismiss to avoid SwiftUI
sheet/navigation race condition."
```

---

### Task 6: Add localization keys

**Files:**
- Modify: `NaarsCars/Resources/Localizable.xcstrings`

- [ ] **Step 1: Add the 5 new localization keys**

In `Localizable.xcstrings`, find the entry for `"auth_email_placeholder"` (around line 5337). After the closing `},` of that entry (which ends around line 5377), insert the following 5 new key blocks. They go between `auth_email_placeholder` and `auth_error_email_required` alphabetically.

Find the exact boundary:
```json
    },
    "auth_error_email_required" : {
```

Insert before `"auth_error_email_required"`:

```json
    "auth_create_account_button" : {
      "extractionState" : "manual",
      "localizations" : {
        "en" : {
          "stringUnit" : {
            "state" : "translated",
            "value" : "Create Account"
          }
        }
      }
    },
    "auth_create_account_needed_body" : {
      "extractionState" : "manual",
      "localizations" : {
        "en" : {
          "stringUnit" : {
            "state" : "translated",
            "value" : "Looks like you're new here! To get started, you'll need an invite code from a current member."
          }
        }
      }
    },
    "auth_create_account_needed_footer" : {
      "extractionState" : "manual",
      "localizations" : {
        "en" : {
          "stringUnit" : {
            "state" : "translated",
            "value" : "If you already have an account, try signing in with your email and password."
          }
        }
      }
    },
    "auth_create_account_needed_title" : {
      "extractionState" : "manual",
      "localizations" : {
        "en" : {
          "stringUnit" : {
            "state" : "translated",
            "value" : "Welcome to Naar's Cars"
          }
        }
      }
    },
```

Then find the entry for `"auth_sign_up"` (around line 5993). After its closing `},`, insert:

```json
    "auth_use_email_instead_button" : {
      "extractionState" : "manual",
      "localizations" : {
        "en" : {
          "stringUnit" : {
            "state" : "translated",
            "value" : "Use Email Instead"
          }
        }
      }
    },
```

This goes between `"auth_sign_up"` and `"auth_valid_email_required"` alphabetically.

- [ ] **Step 2: Build to verify localization keys are picked up**

Run: `xcodebuild -project NaarsCars/NaarsCars.xcodeproj -scheme NaarsCars -sdk iphonesimulator -configuration Debug build 2>&1 | tail -5`

Expected: Build SUCCEEDS with no localization warnings for the new keys.

- [ ] **Step 3: Commit**

```bash
git add NaarsCars/Resources/Localizable.xcstrings
git commit -m "feat(auth): add localization keys for no-account sheet

Keys: auth_create_account_needed_title, auth_create_account_needed_body,
auth_create_account_button, auth_use_email_instead_button,
auth_create_account_needed_footer (English only for now)."
```

---

### Task 7: Final build verification

- [ ] **Step 1: Clean build**

Run: `xcodebuild -project NaarsCars/NaarsCars.xcodeproj -scheme NaarsCars -sdk iphonesimulator -configuration Debug clean build 2>&1 | tail -10`

Expected: Build SUCCEEDS with 0 errors.

- [ ] **Step 2: Run existing tests to check for regressions**

Run: `xcodebuild test -project NaarsCars/NaarsCars.xcodeproj -scheme NaarsCars -sdk iphonesimulator -destination 'platform=iOS Simulator,name=iPhone 16' 2>&1 | grep -E '(Test Suite|Executed|FAIL)'`

Expected: All existing tests pass. No test files were modified.

- [ ] **Step 3: Verify changed files match expectations**

Run: `git diff --stat HEAD~6..HEAD`

Expected output should show exactly these files changed:
```
NaarsCars/Core/Protocols/AuthServiceProtocol.swift
NaarsCars/Core/Services/AuthService+AppleSignIn.swift
NaarsCars/Features/Authentication/ViewModels/AppleSignInViewModel.swift
NaarsCars/Features/Authentication/Views/LoginView.swift
NaarsCars/Features/Authentication/Views/NoAccountFoundSheet.swift  (new)
NaarsCars/Resources/Localizable.xcstrings
```

No other files should be modified. If `project.pbxproj` shows changes, something went wrong with filesystem-synced groups.
