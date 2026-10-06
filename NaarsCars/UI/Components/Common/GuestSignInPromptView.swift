//
//  GuestSignInPromptView.swift
//  NaarsCars
//

import SwiftUI

/// Reusable half-sheet prompting guests to sign up or sign in.
/// Uses onDisappear to fire the callback after the sheet has fully dismissed,
/// avoiding the timing issue where dismiss() + immediate state change tears
/// down the sheet mid-animation.
struct GuestSignInPromptView: View {
    let reason: GuestRestrictionReason
    let onSignUp: () -> Void
    let onLogIn: () -> Void

    private enum PendingAction { case signUp, logIn }
    @State private var pendingAction: PendingAction?
    @Environment(\.dismiss) private var dismiss

    var body: some View {
        // Scrollable, with a large detent to pull to: at half height the content only just
        // fits at the default text size, and this sheet gates every guest action.
        ScrollView {
            VStack(spacing: 24) {
                Image(systemName: "lock.shield")
                    .font(.system(size: 48))
                    .foregroundColor(.naarsPrimary.opacity(0.6))
                    .accessibilityHidden(true)

                Text(reason.title)
                    .font(.naarsTitle2)
                    .multilineTextAlignment(.center)
                    .accessibilityAddTraits(.isHeader)

                Text(reason.message)
                    .font(.naarsBody)
                    .foregroundColor(.naarsTextSecondary)
                    .multilineTextAlignment(.center)
                    .padding(.horizontal)

                VStack(spacing: 12) {
                    PrimaryButton(title: "guest_prompt_sign_up".localized) {
                        pendingAction = .signUp
                        dismiss()
                    }
                    .accessibilityIdentifier("guestPrompt.signUp")

                    // "Sign In", the wording the sheet's title and the sign-in screen use
                    SecondaryButton(title: "auth_sign_in_button".localized) {
                        pendingAction = .logIn
                        dismiss()
                    }
                    .accessibilityIdentifier("guestPrompt.logIn")
                }
                .padding(.horizontal, 32)
            }
            .frame(maxWidth: .infinity)
            .padding()
            // Clears the drag indicator without pushing the buttons below the half-height fold
            .padding(.top, Constants.Spacing.sm)
        }
        .scrollBounceBehavior(.basedOnSize)
        .presentationDetents([.medium, .large])
        .presentationDragIndicator(.visible)
        .onDisappear {
            // Every call site leaves guest mode for the Welcome screen in both callbacks.
            // Record which button it was so Welcome can take "Sign In" on to the sign-in
            // form; before this the two buttons did exactly the same thing.
            switch pendingAction {
            case .signUp:
                WelcomeEntryRoute.opensSignIn = false
                onSignUp()
            case .logIn:
                WelcomeEntryRoute.opensSignIn = true
                onLogIn()
            case nil:
                break
            }
        }
    }
}
