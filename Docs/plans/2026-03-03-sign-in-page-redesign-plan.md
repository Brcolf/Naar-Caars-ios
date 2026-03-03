# Sign-In Page Visual Redesign — Implementation Plan

> **For Claude:** REQUIRED SUB-SKILL: Use superpowers:executing-plans to implement this plan task-by-task.

**Goal:** Modernize all authentication screens with Ally Bank-inspired pill-shaped text fields, reordered login layout, save-username toggle, and keyboard navigation arrows.

**Architecture:** Create a single reusable `NaarsTextField` component in `UI/Components/Inputs/`, then swap it into LoginView, SignupDetailsView, SignupInviteCodeView, and PasswordResetView. No changes to view models, services, or navigation — purely view-layer work.

**Tech Stack:** SwiftUI, @AppStorage (UserDefaults), @FocusState

**Design doc:** `Docs/plans/2026-03-03-sign-in-page-redesign-design.md`

---

### Task 1: Create the NaarsTextField component

**Files:**
- Create: `NaarsCars/UI/Components/Inputs/NaarsTextField.swift`

**Step 1: Create the NaarsTextField file**

Create `NaarsCars/UI/Components/Inputs/NaarsTextField.swift` with this content:

```swift
//
//  NaarsTextField.swift
//  NaarsCars
//
//  Reusable pill-shaped text field for authentication screens
//

import SwiftUI

/// Pill-shaped text field with inline placeholder, optional secure toggle, and error state.
///
/// Usage:
/// ```swift
/// NaarsTextField(
///     placeholder: "Email",
///     text: $email,
///     keyboardType: .emailAddress,
///     textContentType: .emailAddress
/// )
/// ```
struct NaarsTextField: View {
    let placeholder: String
    @Binding var text: String
    var isSecure: Bool = false
    var keyboardType: UIKeyboardType = .default
    var textContentType: UITextContentType?
    var autocapitalization: TextInputAutocapitalization = .never
    var autocorrectionDisabled: Bool = true
    var errorMessage: String?
    var accessibilityId: String?

    @State private var isPasswordVisible = false
    @FocusState private var isFocused: Bool

    private let fieldHeight: CGFloat = 56

    var body: some View {
        VStack(alignment: .leading, spacing: 4) {
            ZStack {
                // Background capsule
                Capsule()
                    .fill(Color.naarsBackgroundSecondary)

                // Focus/error border
                Capsule()
                    .strokeBorder(borderColor, lineWidth: borderWidth)

                HStack(spacing: 0) {
                    // Text input
                    Group {
                        if isSecure && !isPasswordVisible {
                            SecureField(placeholder, text: $text)
                                .textContentType(textContentType)
                        } else {
                            TextField(placeholder, text: $text)
                                .keyboardType(keyboardType)
                                .textContentType(textContentType)
                                .textInputAutocapitalization(autocapitalization)
                                .autocorrectionDisabled(autocorrectionDisabled)
                        }
                    }
                    .focused($isFocused)
                    .font(.naarsBody)
                    .padding(.leading, 20)

                    Spacer(minLength: 0)

                    // Trailing icon: password visibility toggle
                    if isSecure {
                        Button {
                            isPasswordVisible.toggle()
                        } label: {
                            Image(systemName: isPasswordVisible ? "eye.slash.fill" : "eye.fill")
                                .foregroundColor(.naarsTextSecondary)
                                .frame(width: 44, height: 44)
                        }
                        .padding(.trailing, 6)
                        .accessibilityLabel(isPasswordVisible ? "Hide password" : "Show password")
                    }
                }
            }
            .frame(height: fieldHeight)
            .scaleEffect(isFocused ? 1.01 : 1.0)
            .animation(.spring(response: 0.3, dampingFraction: 0.8), value: isFocused)
            .conditionalAccessibilityId(accessibilityId)

            // Error message below field
            if let error = errorMessage {
                Text(error)
                    .font(.naarsCaption)
                    .foregroundColor(.naarsError)
                    .padding(.leading, 20)
                    .accessibilityLabel("Error: \(error)")
            }
        }
    }

    private var borderColor: Color {
        if errorMessage != nil {
            return .naarsError.opacity(0.5)
        } else if isFocused {
            return .naarsPrimary.opacity(0.4)
        } else {
            return .clear
        }
    }

    private var borderWidth: CGFloat {
        (errorMessage != nil || isFocused) ? 1.5 : 0
    }
}

// MARK: - Conditional Accessibility Modifier

private extension View {
    @ViewBuilder
    func conditionalAccessibilityId(_ id: String?) -> some View {
        if let id {
            self.accessibilityIdentifier(id)
        } else {
            self
        }
    }
}

// MARK: - Preview

#Preview("Default") {
    VStack(spacing: 16) {
        NaarsTextField(
            placeholder: "Email",
            text: .constant(""),
            keyboardType: .emailAddress,
            textContentType: .emailAddress,
            accessibilityId: "preview.email"
        )
        NaarsTextField(
            placeholder: "Password",
            text: .constant(""),
            isSecure: true,
            textContentType: .password,
            accessibilityId: "preview.password"
        )
        NaarsTextField(
            placeholder: "Email",
            text: .constant("bad@"),
            errorMessage: "Invalid email address",
            accessibilityId: "preview.error"
        )
    }
    .padding()
}
```

**Step 2: Add the file to the Xcode project**

Open `NaarsCars/NaarsCars.xcodeproj/project.pbxproj` and add `NaarsTextField.swift` to the same group and build phase as `LocationAutocompleteField.swift` (under `UI/Components/Inputs`).

**Step 3: Build to verify no compile errors**

Run: `xcodebuild build -project NaarsCars/NaarsCars.xcodeproj -scheme NaarsCars -destination 'platform=iOS Simulator,name=iPhone 16' -quiet 2>&1 | tail -5`
Expected: `** BUILD SUCCEEDED **`

**Step 4: Commit**

```
feat: add NaarsTextField pill-shaped input component
```

---

### Task 2: Redesign LoginView with new layout and NaarsTextField

**Files:**
- Modify: `NaarsCars/Features/Authentication/Views/LoginView.swift`

**Step 1: Replace LoginView body**

Rewrite the `body` property of `LoginView.swift`. The key changes:

1. Replace the Email VStack (lines 46-68) with:
```swift
NaarsTextField(
    placeholder: "auth_email_placeholder".localized,
    text: $viewModel.email,
    keyboardType: .emailAddress,
    textContentType: .emailAddress,
    accessibilityId: "login.email"
)
.focused($focusedField, equals: .email)
```

2. Replace the Password VStack (lines 71-82) with:
```swift
NaarsTextField(
    placeholder: "auth_password_placeholder".localized,
    text: $viewModel.password,
    isSecure: true,
    textContentType: .password,
    accessibilityId: "login.password"
)
.focused($focusedField, equals: .password)
```

3. Remove the label `Text("auth_email_label"...)` and `Text("auth_password_label"...)` lines — placeholders are inline now.

4. Add Save Username toggle after the password field:
```swift
Toggle("auth_save_username".localized, isOn: $saveUsernameEnabled)
    .font(.naarsCaption)
    .tint(.naarsPrimary)
    .padding(.horizontal, 4)
```

5. Reorder: after the Sign In button, place the Sign Up link, then Forgot Password, then divider, then Apple Sign-In.

6. Add `@FocusState` and keyboard toolbar:
```swift
enum LoginField: Hashable {
    case email, password
}
@FocusState private var focusedField: LoginField?
```

7. Add `@AppStorage` properties:
```swift
@AppStorage("saveUsernameEnabled") private var saveUsernameEnabled = false
@AppStorage("savedUsername") private var savedUsername = ""
```

8. Add `.onAppear` to pre-fill email and `.onChange(of: saveUsernameEnabled)` to clear on toggle-off.

9. On successful login, save or clear the username.

10. Add keyboard toolbar with prev/next/done to the `VStack`:
```swift
.toolbar {
    ToolbarItemGroup(placement: .keyboard) {
        Button {
            switch focusedField {
            case .password: focusedField = .email
            default: break
            }
        } label: {
            Image(systemName: "chevron.up")
        }
        .disabled(focusedField == .email)

        Button {
            switch focusedField {
            case .email: focusedField = .password
            default: break
            }
        } label: {
            Image(systemName: "chevron.down")
        }
        .disabled(focusedField == .password)

        Spacer()

        Button("Done") {
            focusedField = nil
        }
    }
}
```

**Complete replacement for LoginView.swift:**

```swift
//
//  LoginView.swift
//  NaarsCars
//
//  Login screen for email/password authentication
//

import SwiftUI
#if DEBUG
import os
#endif

/// Login view for email/password authentication
struct LoginView: View {
    @StateObject private var viewModel = LoginViewModel()
    @StateObject private var appleSignInViewModel = AppleSignInViewModel()
    @EnvironmentObject var appState: AppState
    @State private var showPasswordReset = false
    @State private var showError = false
    @State private var showSuccess = false
    @AppStorage("saveUsernameEnabled") private var saveUsernameEnabled = false
    @AppStorage("savedUsername") private var savedUsername = ""

    enum LoginField: Hashable {
        case email, password
    }
    @FocusState private var focusedField: LoginField?

#if DEBUG
    private static let _firstTapPerfLog = OSLog(subsystem: "com.naarscars.app", category: "FirstTapPerf")
#endif

    var body: some View {
        ScrollView {
            VStack(spacing: 24) {
                // NaarsCars Title Logo
                VStack(spacing: 12) {
                    Image("NaarsTextLogo")
                        .resizable()
                        .scaledToFit()
                        .frame(maxWidth: 280, maxHeight: 120)
                        .accessibilityLabel("Naar's Cars - Community Ride Sharing")

                    Text("auth_login_title".localized)
                        .font(.naarsSubheadline)
                        .foregroundColor(.secondary)
                }
                .padding(.top, 20)

                // Form
                VStack(spacing: 16) {
                    // Email field
                    NaarsTextField(
                        placeholder: "auth_email_placeholder".localized,
                        text: $viewModel.email,
                        keyboardType: .emailAddress,
                        textContentType: .emailAddress,
                        accessibilityId: "login.email"
                    )
                    .focused($focusedField, equals: .email)
#if DEBUG
                    .onChange(of: focusedField) { _, newValue in
                        if newValue == .email {
                            os_signpost(.event, log: Self._firstTapPerfLog, name: "LoginEmailFocus")
                            FirstTapPerfLogger.logFocusDelivered(source: "login")
                        }
                    }
#endif

                    // Password field
                    NaarsTextField(
                        placeholder: "auth_password_placeholder".localized,
                        text: $viewModel.password,
                        isSecure: true,
                        textContentType: .password,
                        accessibilityId: "login.password"
                    )
                    .focused($focusedField, equals: .password)

                    // Error message
                    if let error = viewModel.error {
                        Text(error.localizedDescription)
                            .font(.naarsCaption)
                            .foregroundColor(.naarsError)
                            .padding(.horizontal)
                    }

                    // Save Username toggle
                    Toggle("auth_save_username".localized, isOn: $saveUsernameEnabled)
                        .font(.naarsCaption)
                        .tint(.naarsPrimary)
                        .padding(.horizontal, 4)

                    // Login button
                    Button(action: {
                        Task {
                            await viewModel.login()
                            if viewModel.error == nil {
                                if saveUsernameEnabled {
                                    savedUsername = viewModel.email
                                } else {
                                    savedUsername = ""
                                }
                                showSuccess = true
                            }
                        }
                    }) {
                        if viewModel.isLoading {
                            ProgressView()
                                .frame(maxWidth: .infinity)
                        } else {
                            Text("auth_sign_in_button".localized)
                                .frame(maxWidth: .infinity)
                        }
                    }
                    .buttonStyle(.borderedProminent)
                    .disabled(viewModel.isLoading || viewModel.email.isEmpty || viewModel.password.isEmpty)
                    .accessibilityIdentifier("login.submit")

                    // Sign up link (moved up, directly below Sign In)
                    HStack {
                        Text("auth_no_account".localized)
                            .font(.naarsCaption)
                            .foregroundColor(.secondary)

                        NavigationLink("auth_sign_up".localized) {
                            SignupInviteCodeView()
                        }
                        .font(.naarsCaption)
                        .foregroundColor(.naarsPrimary)
                        .accessibilityIdentifier("login.signup")
                    }

                    // Forgot password (moved below sign up)
                    Button("auth_forgot_password".localized) {
                        showPasswordReset = true
                    }
                    .font(.naarsCaption)
                    .foregroundColor(.naarsPrimary)
                    .accessibilityIdentifier("login.forgot")

                    // Divider
                    HStack {
                        Rectangle()
                            .frame(height: 1)
                            .foregroundColor(.secondary.opacity(0.3))
                        Text("auth_or_continue_with".localized)
                            .font(.naarsCaption)
                            .foregroundColor(.secondary)
                            .padding(.horizontal, 8)
                        Rectangle()
                            .frame(height: 1)
                            .foregroundColor(.secondary.opacity(0.3))
                    }
                    .padding(.vertical, 8)

                    // Apple Sign-In button
                    AppleSignInButton(
                        onRequest: { request in
                            appleSignInViewModel.handleSignInRequest(request)
                        },
                        onCompletion: { result in
                            Task {
                                await appleSignInViewModel.handleSignInCompletion(
                                    result: result,
                                    inviteCodeId: nil,
                                    isNewUser: false
                                )
                                if appleSignInViewModel.error == nil {
                                    await AppLaunchManager.shared.performCriticalLaunch()
                                } else {
                                    showError = true
                                }
                            }
                        }
                    )
                    .disabled(viewModel.isLoading || appleSignInViewModel.isLoading)
                }
                .padding(.horizontal)
            }
            .padding()
        }
        .scrollDismissesKeyboard(.interactively)
        .toolbar {
            ToolbarItemGroup(placement: .keyboard) {
                Button {
                    switch focusedField {
                    case .password: focusedField = .email
                    default: break
                    }
                } label: {
                    Image(systemName: "chevron.up")
                }
                .disabled(focusedField == .email)

                Button {
                    switch focusedField {
                    case .email: focusedField = .password
                    default: break
                    }
                } label: {
                    Image(systemName: "chevron.down")
                }
                .disabled(focusedField == .password)

                Spacer()

                Button("Done") {
                    focusedField = nil
                }
            }
        }
        .onAppear {
            if saveUsernameEnabled && !savedUsername.isEmpty {
                viewModel.email = savedUsername
            }
        }
        .onChange(of: saveUsernameEnabled) { _, enabled in
            if !enabled {
                savedUsername = ""
            }
        }
        .sheet(isPresented: $showPasswordReset) {
            PasswordResetView()
        }
        .alert("common_error".localized, isPresented: $showError) {
            Button("common_ok".localized, role: .cancel) {}
        } message: {
            Text(appleSignInViewModel.error?.localizedDescription ?? "common_error".localized)
        }
        .successCheckmark(isShowing: $showSuccess)
        .trackScreen("Login")
    }
}

#Preview {
    NavigationStack {
        LoginView()
    }
}
```

**Step 2: Add localization key for "Save Username"**

Add `"auth_save_username"` key to `NaarsCars/Resources/Localizable.xcstrings` with value `"Save Username"` (English). Other languages: Spanish `"Guardar nombre de usuario"`, etc.

**Step 3: Build to verify no compile errors**

Run: `xcodebuild build -project NaarsCars/NaarsCars.xcodeproj -scheme NaarsCars -destination 'platform=iOS Simulator,name=iPhone 16' -quiet 2>&1 | tail -5`
Expected: `** BUILD SUCCEEDED **`

**Step 4: Commit**

```
feat: redesign LoginView with pill fields, save username, reordered layout
```

---

### Task 3: Update SignupDetailsView with NaarsTextField and keyboard nav

**Files:**
- Modify: `NaarsCars/Features/Authentication/Views/SignupDetailsView.swift`

**Step 1: Add FocusState enum and property**

Add at the top of `SignupDetailsView`:
```swift
enum SignupField: Hashable {
    case name, email, password, confirmPassword, car
}
@FocusState private var focusedField: SignupField?
```

**Step 2: Replace all 5 text field VStacks with NaarsTextField**

Replace each field's `VStack(alignment: .leading, spacing: 8)` block. For example, the Name field (lines 35-57) becomes:

```swift
NaarsTextField(
    placeholder: "signup_name_placeholder".localized,
    text: $viewModel.name,
    autocapitalization: .words,
    errorMessage: viewModel.nameError,
    accessibilityId: "signup.name"
)
.focused($focusedField, equals: .name)
.onChange(of: viewModel.name) { _, _ in
    if viewModel.nameError != nil { viewModel.nameError = nil }
}
```

Email field (lines 60-83):
```swift
NaarsTextField(
    placeholder: "signup_email_placeholder".localized,
    text: $viewModel.email,
    keyboardType: .emailAddress,
    textContentType: .emailAddress,
    errorMessage: viewModel.emailError,
    accessibilityId: "signup.email"
)
.focused($focusedField, equals: .email)
.onChange(of: viewModel.email) { _, _ in
    if viewModel.emailError != nil { viewModel.emailError = nil }
}
```

Password field (lines 86-113):
```swift
VStack(alignment: .leading, spacing: 4) {
    NaarsTextField(
        placeholder: "signup_password_placeholder".localized,
        text: $viewModel.password,
        isSecure: true,
        textContentType: .newPassword,
        errorMessage: viewModel.passwordError,
        accessibilityId: "signup.password"
    )
    .focused($focusedField, equals: .password)
    .onChange(of: viewModel.password) { _, _ in
        if viewModel.passwordError != nil { viewModel.passwordError = nil }
        if viewModel.confirmPasswordError != nil { viewModel.confirmPasswordError = nil }
    }

    if viewModel.passwordError == nil {
        Text("signup_password_hint".localized)
            .font(.naarsCaption)
            .foregroundColor(.secondary)
            .padding(.leading, 20)
    }
}
```

Confirm password field (lines 116-136):
```swift
NaarsTextField(
    placeholder: "signup_confirm_password_placeholder".localized,
    text: $viewModel.confirmPassword,
    isSecure: true,
    textContentType: .newPassword,
    errorMessage: viewModel.confirmPasswordError,
    accessibilityId: "signup.confirmPassword"
)
.focused($focusedField, equals: .confirmPassword)
.onChange(of: viewModel.confirmPassword) { _, _ in
    if viewModel.confirmPasswordError != nil { viewModel.confirmPasswordError = nil }
}
```

Car field (lines 139-148):
```swift
NaarsTextField(
    placeholder: "signup_car_placeholder".localized,
    text: $viewModel.car,
    autocapitalization: .words,
    accessibilityId: "signup.car"
)
.focused($focusedField, equals: .car)
```

**Step 3: Remove the label `Text(...)` lines above each field**

The old pattern had `Text("signup_full_name_label".localized)` etc. above each field — remove all of those. The placeholder inside NaarsTextField replaces them.

**Step 4: Add keyboard toolbar**

Add to the ScrollView:
```swift
.toolbar {
    ToolbarItemGroup(placement: .keyboard) {
        Button {
            moveFocus(forward: false)
        } label: {
            Image(systemName: "chevron.up")
        }
        .disabled(focusedField == .name)

        Button {
            moveFocus(forward: true)
        } label: {
            Image(systemName: "chevron.down")
        }
        .disabled(focusedField == .car)

        Spacer()

        Button("Done") {
            focusedField = nil
        }
    }
}
```

Add helper method:
```swift
private func moveFocus(forward: Bool) {
    let fields: [SignupField] = [.name, .email, .password, .confirmPassword, .car]
    guard let current = focusedField, let index = fields.firstIndex(of: current) else { return }
    let next = forward ? fields.index(after: index) : fields.index(before: index)
    if fields.indices.contains(next) {
        focusedField = fields[next]
    }
}
```

**Step 5: Build to verify**

Run: `xcodebuild build -project NaarsCars/NaarsCars.xcodeproj -scheme NaarsCars -destination 'platform=iOS Simulator,name=iPhone 16' -quiet 2>&1 | tail -5`
Expected: `** BUILD SUCCEEDED **`

**Step 6: Commit**

```
feat: adopt NaarsTextField in SignupDetailsView with keyboard nav
```

---

### Task 4: Update SignupInviteCodeView with NaarsTextField

**Files:**
- Modify: `NaarsCars/Features/Authentication/Views/SignupInviteCodeView.swift`

**Step 1: Replace invite code field**

Replace the invite code VStack (lines 41-51) with:
```swift
NaarsTextField(
    placeholder: "signup_invite_code_placeholder".localized,
    text: $inviteCode,
    autocapitalization: .characters,
    autocorrectionDisabled: true,
    accessibilityId: "signup.inviteCode"
)
.disabled(isValidating)
```

**Step 2: Remove the label above the field**

Remove `Text("signup_invite_code_label".localized)` and the enclosing VStack wrapper.

**Step 3: Add keyboard toolbar**

This screen has only one field, so just a Done button:
```swift
@FocusState private var isCodeFocused: Bool
```

Add `.focused($isCodeFocused)` to the NaarsTextField, and:
```swift
.toolbar {
    ToolbarItemGroup(placement: .keyboard) {
        Spacer()
        Button("Done") {
            isCodeFocused = false
        }
    }
}
```

**Step 4: Build to verify**

Run: `xcodebuild build -project NaarsCars/NaarsCars.xcodeproj -scheme NaarsCars -destination 'platform=iOS Simulator,name=iPhone 16' -quiet 2>&1 | tail -5`
Expected: `** BUILD SUCCEEDED **`

**Step 5: Commit**

```
feat: adopt NaarsTextField in SignupInviteCodeView
```

---

### Task 5: Update PasswordResetView with NaarsTextField

**Files:**
- Modify: `NaarsCars/Features/Authentication/Views/PasswordResetView.swift`

**Step 1: Replace email field**

Replace the email VStack (lines 27-37) with:
```swift
NaarsTextField(
    placeholder: "password_reset_email_placeholder".localized,
    text: $viewModel.email,
    keyboardType: .emailAddress,
    textContentType: .emailAddress,
    accessibilityId: "passwordReset.email"
)
```

**Step 2: Remove the label above the field**

Remove `Text("password_reset_email_label".localized)` and the enclosing VStack wrapper.

**Step 3: Add keyboard toolbar**

Single field — just a Done button:
```swift
@FocusState private var isEmailFocused: Bool
```

Add `.focused($isEmailFocused)` and:
```swift
.toolbar {
    ToolbarItemGroup(placement: .keyboard) {
        Spacer()
        Button("Done") {
            isEmailFocused = false
        }
    }
}
```

**Step 4: Build to verify**

Run: `xcodebuild build -project NaarsCars/NaarsCars.xcodeproj -scheme NaarsCars -destination 'platform=iOS Simulator,name=iPhone 16' -quiet 2>&1 | tail -5`
Expected: `** BUILD SUCCEEDED **`

**Step 5: Commit**

```
feat: adopt NaarsTextField in PasswordResetView
```

---

### Task 6: Add localization keys and final verification

**Files:**
- Modify: `NaarsCars/Resources/Localizable.xcstrings`

**Step 1: Add the `auth_save_username` localization key**

Add to Localizable.xcstrings:
- Key: `auth_save_username`
- English: `Save Username`
- Spanish: `Guardar usuario`
- Korean: `사용자 이름 저장`
- Vietnamese: `Lưu tên đăng nhập`
- Chinese (Simplified): `保存用户名`
- Chinese (Traditional): `儲存使用者名稱`

**Step 2: Full build and verify**

Run: `xcodebuild build -project NaarsCars/NaarsCars.xcodeproj -scheme NaarsCars -destination 'platform=iOS Simulator,name=iPhone 16' -quiet 2>&1 | tail -5`
Expected: `** BUILD SUCCEEDED **`

**Step 3: Run existing tests to verify nothing broke**

Run: `xcodebuild test -project NaarsCars/NaarsCars.xcodeproj -scheme NaarsCars -destination 'platform=iOS Simulator,name=iPhone 16' -quiet 2>&1 | tail -20`
Expected: All tests pass.

**Step 4: Commit**

```
feat: add localization keys for sign-in page redesign
```

---

## Summary of all tasks

| Task | Description | Files |
|------|-------------|-------|
| 1 | Create NaarsTextField component | `UI/Components/Inputs/NaarsTextField.swift` (new) |
| 2 | Redesign LoginView | `Features/Authentication/Views/LoginView.swift` |
| 3 | Update SignupDetailsView | `Features/Authentication/Views/SignupDetailsView.swift` |
| 4 | Update SignupInviteCodeView | `Features/Authentication/Views/SignupInviteCodeView.swift` |
| 5 | Update PasswordResetView | `Features/Authentication/Views/PasswordResetView.swift` |
| 6 | Localization keys + final verification | `Resources/Localizable.xcstrings` |
