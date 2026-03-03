//
//  NaarsTextField.swift
//  NaarsCars
//
//  Pill-shaped text field component with focus, error, and secure entry states.
//

import SwiftUI
import UIKit

struct NaarsTextField: View {
    let placeholder: String
    @Binding var text: String
    var isSecure: Bool = false
    var keyboardType: UIKeyboardType = .default
    var textContentType: UITextContentType? = nil
    var autocapitalization: TextInputAutocapitalization = .never
    var autocorrectionDisabled: Bool = true
    var errorMessage: String? = nil
    var accessibilityId: String? = nil

    @State private var isPasswordVisible = false
    @FocusState private var isFocused: Bool

    var body: some View {
        VStack(alignment: .leading, spacing: 4) {
            HStack(spacing: 0) {
                if isSecure && !isPasswordVisible {
                    SecureField(placeholder, text: $text)
                        .textContentType(textContentType)
                        .font(.naarsBody)
                        .focused($isFocused)
                        .conditionalAccessibilityId(accessibilityId)
                } else {
                    TextField(placeholder, text: $text)
                        .keyboardType(keyboardType)
                        .textContentType(textContentType)
                        .textInputAutocapitalization(autocapitalization)
                        .autocorrectionDisabled(autocorrectionDisabled)
                        .font(.naarsBody)
                        .focused($isFocused)
                        .conditionalAccessibilityId(accessibilityId)
                }

                if isSecure {
                    Button {
                        isPasswordVisible.toggle()
                    } label: {
                        Image(systemName: isPasswordVisible ? "eye.slash" : "eye")
                            .foregroundColor(.naarsTextSecondary)
                    }
                    .frame(width: 44, height: 44)
                    .contentShape(Rectangle())
                }
            }
            .padding(.leading, 20)
            .padding(.trailing, isSecure ? 8 : 20)
            .frame(height: 56)
            .background(Color.naarsBackgroundSecondary)
            .clipShape(Capsule())
            .overlay(
                Capsule()
                    .strokeBorder(strokeColor, lineWidth: hasStroke ? 1.5 : 0)
            )
            .scaleEffect(isFocused && errorMessage == nil ? 1.01 : 1.0)
            .animation(.spring(response: 0.3, dampingFraction: 0.8), value: isFocused)

            if let errorMessage {
                Text(errorMessage)
                    .font(.naarsCaption)
                    .foregroundColor(.naarsError)
                    .padding(.leading, 20)
            }
        }
    }

    // MARK: - Computed Helpers

    private var hasStroke: Bool {
        isFocused || errorMessage != nil
    }

    private var strokeColor: Color {
        if errorMessage != nil {
            return Color.naarsError.opacity(0.5)
        }
        return Color.naarsPrimary.opacity(0.4)
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
