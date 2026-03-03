# Sign-In Page Visual Redesign

**Date:** 2026-03-03
**Status:** Approved

## Overview

Visual cleanup of the sign-in page inspired by Ally Bank's login screen. Introduces a reusable `NaarsTextField` design-system component and applies it across all authentication screens.

## Goals

- Modernize the sign-in page with cleaner, larger pill-shaped input fields
- Remove redundant field labels in favor of inline placeholders
- Reorder layout to place the sign-up link directly below the sign-in button
- Add a "Save Username" toggle that persists across sessions
- Add keyboard navigation arrows (previous/next) for field traversal
- Extend the new field style to signup and password-reset screens

## NaarsTextField Component

### Properties

| Property | Type | Purpose |
|----------|------|---------|
| `placeholder` | `String` | Inline placeholder text |
| `text` | `Binding<String>` | Bound text value |
| `isSecure` | `Bool` | Toggle between TextField/SecureField with eye icon |
| `keyboardType` | `UIKeyboardType` | Keyboard variant |
| `textContentType` | `UITextContentType?` | Autofill hints |
| `errorMessage` | `String?` | Error state with red tint |
| `trailingIcon` | `Image?` | Optional custom trailing icon |
| `autocapitalization` | `TextInputAutocapitalization` | Capitalization behavior |

### Visual Spec

- **Height:** 56pt
- **Shape:** Capsule (fully rounded ends, corner radius = height/2)
- **Background:** `naarsBackgroundSecondary` fill, no border stroke
- **Placeholder:** `.secondary` color, left-aligned with 20pt leading padding
- **Text:** Primary color, same positioning
- **Focus state:** Subtle `naarsPrimary.opacity(0.3)` stroke + slight scale animation
- **Error state:** `naarsError.opacity(0.3)` stroke + error message text below field
- **Trailing icon area:** 44pt touch target, right-aligned with 16pt trailing padding
- **Secure field:** Eye icon toggles password visibility

## Login Page Layout (New Order)

```
Logo + subtitle
Email field (NaarsTextField)
Password field (NaarsTextField, secure)
Save Username toggle (iOS native Toggle)
Sign In button
"Don't have an account? Sign Up" link
"Forgot Password?" link
"Or continue with" divider
Sign in with Apple button
```

### Changes from current layout

- Labels removed from above fields (inline placeholder only)
- "Sign Up" link moved from bottom to directly below Sign In button
- "Forgot Password" moved from above divider to below Sign Up link
- "Save Username" toggle added between password and Sign In button
- Fields use NaarsTextField component

## Save Username Persistence

- `@AppStorage("savedUsername")` stores the email string
- `@AppStorage("saveUsernameEnabled")` stores toggle state (Bool, default: false)
- On view appear: if toggle on, pre-fill email from saved value
- On successful login: if toggle on, save current email; if off, clear saved value
- Password is never saved (iOS Keychain autofill handles that natively)
- When toggle is turned off, saved email is immediately cleared

## Keyboard Navigation

- `.toolbar(.keyboard)` with previous/next chevron buttons
- `@FocusState` enum tracks active field
- Previous/next buttons move focus between email and password fields
- Done button dismisses keyboard
- Applied to login, signup, and password-reset forms

## Signup Screen Updates

### SignupDetailsView.swift

Replace 4 text fields (name, email, password, confirm password) with NaarsTextField. Add keyboard navigation arrows. No logic changes.

### SignupInviteCodeView.swift

Replace invite code field with NaarsTextField. Add keyboard toolbar. No logic changes.

### PasswordResetView.swift

Replace email field with NaarsTextField for visual consistency. No logic changes.

## Forgot Password Status

Fully implemented and functional. No changes needed to logic. Only visual update to use NaarsTextField.

## Files Affected

| File | Change |
|------|--------|
| `NaarsTextField.swift` (new) | Reusable design-system text field component |
| `LoginView.swift` | Layout reorder, NaarsTextField adoption, save username toggle, keyboard nav |
| `LoginViewModel.swift` | No changes (save username handled at view level via @AppStorage) |
| `SignupDetailsView.swift` | NaarsTextField adoption, keyboard nav |
| `SignupInviteCodeView.swift` | NaarsTextField adoption, keyboard nav |
| `PasswordResetView.swift` | NaarsTextField adoption, keyboard nav |

## Non-Goals

- No changes to authentication logic or API calls
- No changes to Apple Sign-In flow
- No changes to navigation structure
- No new validation rules
