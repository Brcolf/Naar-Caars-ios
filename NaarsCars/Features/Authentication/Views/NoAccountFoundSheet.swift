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
        // Scrollable, with a large detent to pull to, so nothing is cut off at larger text sizes
        ScrollView {
            VStack(spacing: 24) {
                Image(systemName: "person.crop.circle.badge.plus")
                    .font(.system(size: 56))
                    .foregroundColor(.naarsPrimary)
                    .accessibilityHidden(true)

                Text("auth_create_account_needed_title".localized)
                    .font(.naarsTitle3)
                    .multilineTextAlignment(.center)
                    .accessibilityAddTraits(.isHeader)

                Text("auth_create_account_needed_body".localized)
                    .font(.naarsBody)
                    .foregroundStyle(.secondary)
                    .multilineTextAlignment(.center)
                    .padding(.horizontal)

                VStack(spacing: 12) {
                    PrimaryButton(title: "auth_create_account_button".localized, action: {
                        didRequestCreateAccount = true
                        dismiss()
                    })
                    .accessibilityIdentifier("noAccount.createAccount")

                    SecondaryButton(title: "auth_use_email_instead_button".localized) {
                        dismiss()
                    }
                    .accessibilityIdentifier("noAccount.useEmail")
                }

                // Secondary, not tertiary: this is the line that helps someone who already
                // has an email account, and tertiary grey is for placeholders only.
                Text("auth_create_account_needed_footer".localized)
                    .font(.naarsCaption)
                    .foregroundStyle(.secondary)
                    .multilineTextAlignment(.center)
                    .padding(.horizontal)
            }
            .frame(maxWidth: .infinity)
            .padding(.horizontal, 24)
            // Clears the system drag indicator, which stays put while the content scrolls
            .padding(.top, Constants.Spacing.lg)
            .padding(.bottom, Constants.Spacing.lg)
        }
        .scrollBounceBehavior(.basedOnSize)
        .presentationDetents([.medium, .large])
        .presentationDragIndicator(.visible)
        .accessibilityIdentifier("noAccountFoundSheet")
    }
}
