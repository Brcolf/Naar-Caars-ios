//
//  GuestSignInPromptView.swift
//  NaarsCars
//

import SwiftUI

/// Reusable half-sheet prompting guests to sign up or log in.
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
        VStack(spacing: 24) {
            Spacer()

            Image(systemName: "lock.shield")
                .font(.system(size: 48))
                .foregroundStyle(.secondary)
                .accessibilityHidden(true)

            Text(reason.title)
                .font(.title2.bold())
                .multilineTextAlignment(.center)
                .accessibilityAddTraits(.isHeader)

            Text(reason.message)
                .font(.body)
                .foregroundStyle(.secondary)
                .multilineTextAlignment(.center)
                .padding(.horizontal)

            VStack(spacing: 12) {
                Button {
                    pendingAction = .signUp
                    dismiss()
                } label: {
                    Text("guest_prompt_sign_up".localized)
                        .font(.headline)
                        .frame(maxWidth: .infinity)
                        .padding(.vertical, 14)
                }
                .buttonStyle(.borderedProminent)
                .accessibilityIdentifier("guestPrompt.signUp")

                Button {
                    pendingAction = .logIn
                    dismiss()
                } label: {
                    Text("guest_prompt_log_in".localized)
                        .font(.headline)
                        .frame(maxWidth: .infinity)
                        .padding(.vertical, 14)
                }
                .buttonStyle(.bordered)
                .accessibilityIdentifier("guestPrompt.logIn")
            }
            .padding(.horizontal, 32)

            Spacer()
        }
        .padding()
        .presentationDetents([.medium])
        .presentationDragIndicator(.visible)
        .onDisappear {
            switch pendingAction {
            case .signUp: onSignUp()
            case .logIn: onLogIn()
            case nil: break
            }
        }
    }
}
