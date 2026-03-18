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
                .foregroundColor(.naarsPrimary)
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
