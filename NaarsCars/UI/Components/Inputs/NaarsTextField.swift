//
//  NaarsTextField.swift
//  NaarsCars
//
//  Pill-shaped text field component with focus, error, and secure entry states.
//

import SwiftUI
import UIKit

struct NaarsTextField: View {
    /// Optional visible label above the field. A placeholder disappears as soon as the user
    /// types, so a form with several fields should name each one here; the label is also
    /// what VoiceOver reads for the field.
    var label: String? = nil
    let placeholder: String
    @Binding var text: String
    var isSecure: Bool = false
    var keyboardType: UIKeyboardType = .default
    var textContentType: UITextContentType? = nil
    var autocapitalization: TextInputAutocapitalization = .never
    var autocorrectionDisabled: Bool = true
    var errorMessage: String? = nil
    var isFocused: Bool = false
    var accessibilityId: String? = nil

    @State private var isPasswordVisible = false

    var body: some View {
        VStack(alignment: .leading, spacing: 4) {
            if let label {
                Text(label)
                    .font(.naarsSubheadline)
                    .fontWeight(.medium)
                    .foregroundColor(.secondary)
                    .padding(.leading, 20)
                    // The field itself carries the label for assistive tech
                    .accessibilityHidden(true)
            }

            HStack(spacing: 0) {
                if isSecure && !isPasswordVisible {
                    SecureField(placeholder, text: $text)
                        .textContentType(textContentType)
                        .font(.naarsBody)
                        .conditionalAccessibilityLabel(fieldAccessibilityLabel)
                        .conditionalAccessibilityId(accessibilityId)
                } else {
                    TextField(placeholder, text: $text)
                        .keyboardType(keyboardType)
                        .textContentType(textContentType)
                        .textInputAutocapitalization(autocapitalization)
                        .autocorrectionDisabled(autocorrectionDisabled)
                        .font(.naarsBody)
                        .conditionalAccessibilityLabel(fieldAccessibilityLabel)
                        .conditionalAccessibilityId(accessibilityId)
                }

                if isSecure {
                    Button {
                        isPasswordVisible.toggle()
                    } label: {
                        Image(systemName: isPasswordVisible ? "eye.slash.fill" : "eye.fill")
                            .foregroundColor(.naarsTextSecondary)
                    }
                    .frame(width: 44, height: 44)
                    .contentShape(Rectangle())
                    .accessibilityLabel(isPasswordVisible ? "common_hide_password_accessibility".localized : "common_show_password_accessibility".localized)
                }
            }
            .padding(.leading, 20)
            .padding(.trailing, isSecure ? 8 : 20)
            // A minimum, not a fixed height: at the accessibility text sizes one line of
            // body text is taller than 56 pt and was clipped by the capsule.
            .frame(minHeight: 56)
            // An adaptive fill, not the card colour: on the white log-in / sign-up screens the
            // field was invisible until focused.
            .background(Color(.tertiarySystemFill))
            .clipShape(Capsule())
            .overlay(
                Capsule()
                    .strokeBorder(strokeColor, lineWidth: hasStroke ? 1.5 : 0)
            )
            .scaleEffect(isFocused && errorMessage == nil ? 1.01 : 1.0)
            .animation(.naarsStandard, value: isFocused)

            if let errorMessage {
                Text(errorMessage)
                    .font(.naarsCaption)
                    .foregroundColor(.naarsError)
                    .padding(.leading, 20)
                    .accessibilityLabel("app_error_format".localized(with: errorMessage))
            }
        }
    }

    // MARK: - Computed Helpers

    /// What VoiceOver reads for the field: the visible label without its required-field
    /// asterisk. Nil when there is no label, which leaves the placeholder as the name.
    private var fieldAccessibilityLabel: String? {
        guard let label else { return nil }
        return label
            .replacingOccurrences(of: "*", with: "")
            .trimmingCharacters(in: .whitespaces)
    }

    private var hasStroke: Bool {
        isFocused || errorMessage != nil
    }

    private var strokeColor: Color {
        if errorMessage != nil {
            return Color.naarsError.opacity(0.3)
        }
        return Color.naarsPrimary.opacity(0.3)
    }
}

// MARK: - Conditional Accessibility Identifier

private extension View {
    @ViewBuilder
    func conditionalAccessibilityId(_ id: String?) -> some View {
        if let id {
            self.accessibilityIdentifier(id)
        } else {
            self
        }
    }

    @ViewBuilder
    func conditionalAccessibilityLabel(_ label: String?) -> some View {
        if let label {
            self.accessibilityLabel(label)
        } else {
            self
        }
    }
}

// MARK: - Previews

#Preview {
    VStack(spacing: 16) {
        NaarsTextField(
            placeholder: "Email address",
            text: .constant(""),
            keyboardType: .emailAddress,
            textContentType: .emailAddress,
            accessibilityId: "email_field"
        )

        NaarsTextField(
            placeholder: "Password",
            text: .constant(""),
            isSecure: true,
            textContentType: .password,
            accessibilityId: "password_field"
        )

        NaarsTextField(
            placeholder: "Email address",
            text: .constant("bad-email"),
            keyboardType: .emailAddress,
            errorMessage: "Please enter a valid email address",
            accessibilityId: "email_error_field"
        )
    }
    .padding()
}
