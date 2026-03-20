//
//  GuestProfileView.swift
//  NaarsCars
//

import SwiftUI

/// Profile tab view shown to guest users.
struct GuestProfileView: View {
    @Environment(AppState.self) private var appState
    @State private var showSignInPrompt = false

    var body: some View {
        NavigationStack {
            List {
                // Guest identity + CTA section
                Section {
                    VStack(spacing: 16) {
                        Image(systemName: "person.crop.circle")
                            .font(.system(size: 72))
                            .foregroundStyle(.secondary)
                            .accessibilityHidden(true)

                        Text("guest_profile_name".localized)
                            .font(.title2.bold())

                        Text("guest_profile_cta_message".localized)
                            .font(.subheadline)
                            .foregroundStyle(.secondary)
                            .multilineTextAlignment(.center)

                        Button {
                            showSignInPrompt = true
                        } label: {
                            Text("guest_prompt_sign_up".localized)
                                .font(.headline)
                                .frame(maxWidth: .infinity)
                                .padding(.vertical, 14)
                        }
                        .buttonStyle(.borderedProminent)
                        .accessibilityIdentifier("guestProfile.signUp")

                        Button {
                            showSignInPrompt = true
                        } label: {
                            Text("guest_prompt_log_in".localized)
                                .font(.headline)
                                .frame(maxWidth: .infinity)
                                .padding(.vertical, 14)
                        }
                        .buttonStyle(.bordered)
                        .accessibilityIdentifier("guestProfile.logIn")
                    }
                    .frame(maxWidth: .infinity)
                    .padding(.vertical, 8)
                }

                // About section — replicated from SettingsView
                Section {
                    NavigationLink(destination: CommunityGuidelinesView(showDismissButton: false)) {
                        Label("settings_community_guidelines".localized, systemImage: "doc.text")
                    }

                    Link(destination: URL(string: Constants.URLs.privacyPolicy) ?? URL(string: "about:blank") ?? URL(fileURLWithPath: "/")) {
                        Label {
                            HStack {
                                Text("settings_privacy_policy".localized)
                                    .foregroundColor(.primary)
                                Spacer()
                                Image(systemName: "arrow.up.right.square")
                                    .font(.caption)
                                    .foregroundColor(.secondary)
                            }
                        } icon: {
                            Image(systemName: "hand.raised")
                        }
                    }

                    Link(destination: URL(string: Constants.URLs.termsOfService) ?? URL(string: "about:blank") ?? URL(fileURLWithPath: "/")) {
                        Label {
                            HStack {
                                Text("settings_terms_of_service".localized)
                                    .foregroundColor(.primary)
                                Spacer()
                                Image(systemName: "arrow.up.right.square")
                                    .font(.caption)
                                    .foregroundColor(.secondary)
                            }
                        } icon: {
                            Image(systemName: "doc.plaintext")
                        }
                    }

                    // Contact support — open mailto
                    if let url = URL(string: "mailto:naarscars@gmail.com") {
                        Link(destination: url) {
                            Label {
                                HStack {
                                    Text("settings_contact_support".localized)
                                        .foregroundColor(.primary)
                                    Spacer()
                                    Image(systemName: "arrow.up.right.square")
                                        .font(.caption)
                                        .foregroundColor(.secondary)
                                }
                            } icon: {
                                Image(systemName: "envelope")
                            }
                        }
                    }
                } header: {
                    Text("settings_about".localized)
                }
            }
            .navigationTitle("nav_tab_profile".localized)
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
