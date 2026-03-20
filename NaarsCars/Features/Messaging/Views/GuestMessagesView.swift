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
                    .foregroundStyle(.secondary)
                    .accessibilityHidden(true)

                Text("guest_messages_title".localized)
                    .font(.title2.bold())
                    .multilineTextAlignment(.center)
                    .accessibilityAddTraits(.isHeader)

                Text("guest_messages_privacy_rationale".localized)
                    .font(.body)
                    .foregroundStyle(.secondary)
                    .multilineTextAlignment(.center)
                    .padding(.horizontal, 32)

                Button {
                    showSignInPrompt = true
                } label: {
                    Text("guest_prompt_sign_up".localized)
                        .font(.headline)
                        .frame(maxWidth: .infinity)
                        .padding(.vertical, 14)
                }
                .buttonStyle(.borderedProminent)
                .padding(.horizontal, 32)
                .accessibilityIdentifier("guestMessages.signUp")

                Spacer()
            }
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
