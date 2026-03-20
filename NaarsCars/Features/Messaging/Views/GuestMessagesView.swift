//
//  GuestMessagesView.swift
//  NaarsCars
//

import SwiftUI

/// Empty state shown to guest users on the Messages tab.
struct GuestMessagesView: View {
    @Environment(AppState.self) private var appState
    @State private var showSignInPrompt = false

    var body: some View {
        NavigationStack {
            VStack(spacing: 24) {
                Spacer()

                Image(systemName: "bubble.left.and.bubble.right")
                    .font(.system(size: 56))
                    .foregroundColor(.naarsPrimary.opacity(0.5))
                    .accessibilityHidden(true)

                Text("guest_messages_title".localized)
                    .font(.naarsTitle2)
                    .multilineTextAlignment(.center)
                    .accessibilityAddTraits(.isHeader)

                Text("guest_messages_privacy_rationale".localized)
                    .font(.naarsBody)
                    .foregroundColor(.naarsTextSecondary)
                    .multilineTextAlignment(.center)
                    .padding(.horizontal, 32)

                PrimaryButton(title: "guest_prompt_sign_up".localized) {
                    showSignInPrompt = true
                }
                .padding(.horizontal, 32)
                .accessibilityIdentifier("guestMessages.signUp")

                Spacer()
            }
            .background(Color.naarsBackground)
            .navigationTitle("nav_tab_messages".localized)
            .sheet(isPresented: $showSignInPrompt) {
                GuestSignInPromptView(
                    reason: .sendMessage,
                    onSignUp: {
                        appState.isGuestMode = false
                        AppLaunchManager.shared.exitGuestMode()
                    },
                    onLogIn: {
                        appState.isGuestMode = false
                        AppLaunchManager.shared.exitGuestMode()
                    }
                )
            }
        }
    }
}
