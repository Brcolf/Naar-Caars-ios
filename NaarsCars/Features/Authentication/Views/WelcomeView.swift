//
//  WelcomeView.swift
//  NaarsCars
//
//  Public-facing welcome screen — entry point for new and returning users
//

import SwiftUI

/// Welcome screen shown to unauthenticated users.
/// Provides Apple Sign-In and email signup for new users,
/// plus a sign-in link for returning users.
struct WelcomeView: View {
    @StateObject private var appleSignInViewModel = AppleSignInViewModel()
    // Owned here so the pushed sign-up form keeps what was typed: built inline in the
    // destination, every re-evaluation of this body handed the form a new, empty model.
    @StateObject private var signupViewModel = SignupViewModel()
    @Environment(AppState.self) var appState
    @State private var showError = false
    @State private var navigateToEmailSignup = false
    @State private var navigateToLogin = false
    @State private var showInviteEntry = false
    /// The invite code kept on this device, if any. Only its presence is shown: a signed-out
    /// person cannot look a code up, so no community details appear here.
    @State private var savedInviteCode: String?

    private let pendingInviteStore: PendingInviteStore

    init(pendingInviteStore: PendingInviteStore = PendingInviteStore()) {
        self.pendingInviteStore = pendingInviteStore
    }

    var body: some View {
        ScrollView {
            VStack(spacing: 24) {
                Spacer()
                    .frame(height: 20)

                // Logo
                VStack(spacing: 12) {
                    Image("NaarsLogo")
                        .resizable()
                        .scaledToFit()
                        .frame(maxWidth: 240, maxHeight: 160)
                        .accessibilityLabel("app_name".localized)

                    Text("welcome_title".localized)
                        .font(.naarsTitle)
                        .fontWeight(.bold)
                        .multilineTextAlignment(.center)

                    Text("welcome_body".localized)
                        .font(.naarsBody)
                        .foregroundColor(.secondary)
                        .multilineTextAlignment(.center)
                        .padding(.horizontal, 16)
                }

                Spacer()
                    .frame(height: 8)

                // Primary sign-in options
                VStack(spacing: 16) {
                    // Apple Sign-In (primary — handles both sign-in and sign-up)
                    AppleSignInButton(
                        onRequest: { request in
                            appleSignInViewModel.handleSignInRequest(request)
                        },
                        onCompletion: { result in
                            Task {
                                await appleSignInViewModel.handleSignUpCompletion(result: result)

                                if appleSignInViewModel.error == nil {
                                    await AppLaunchManager.shared.performCriticalLaunch()
                                } else {
                                    showError = true
                                }
                            }
                        }
                    )
                    .disabled(appleSignInViewModel.isLoading)

                    // Log in with Email (primary)
                    Button(action: {
                        navigateToLogin = true
                    }) {
                        HStack(spacing: Constants.Spacing.sm) {
                            Image(systemName: "envelope.fill")
                            Text("welcome_sign_in_with_email".localized)
                        }
                        .font(.naarsHeadline)
                        .frame(maxWidth: .infinity)
                        .padding()
                        .background(Color.naarsBackgroundSecondary)
                        .clipShape(Capsule())
                        .overlay(
                            Capsule()
                                .strokeBorder(Color.naarsBorder, lineWidth: 1)
                        )
                    }
                    .buttonStyle(.scale)
                    .accessibilityIdentifier("welcome.emailLogin")

                    if appleSignInViewModel.isLoading {
                        ProgressView()
                            .padding(.top, 4)
                    }
                }
                .padding(.horizontal)

                // Divider
                HStack {
                    Rectangle()
                        .frame(height: 1)
                        .foregroundColor(.naarsDivider)
                    Text("auth_or_continue_with".localized)
                        .font(.naarsCaption)
                        .foregroundColor(.naarsTextSecondary)
                        .padding(.horizontal, 8)
                    Rectangle()
                        .frame(height: 1)
                        .foregroundColor(.naarsDivider)
                }
                .padding(.horizontal)

                // Secondary options — sign up with email + guest
                VStack(spacing: 12) {
                    SecondaryButton(title: "welcome_signup_with_email".localized) {
                        navigateToEmailSignup = true
                    }
                    .accessibilityIdentifier("welcome.emailSignup")

                    Button {
                        appState.isGuestMode = true
                        AppLaunchManager.shared.enterGuestMode()
                    } label: {
                        Text("welcome_continue_as_guest".localized)
                            .font(.naarsSubheadline)
                            .foregroundColor(.naarsTextSecondary)
                            .frame(maxWidth: .infinity)
                            .padding(.vertical, 12)
                    }
                    .accessibilityIdentifier("welcome.continueAsGuest")

                    inviteCodeEntry
                }
                .padding(.horizontal)

                // Says before any account exists how joining works: by invite, by asking a
                // public community, or by starting one; community admins review new members.
                Text("welcome_footer_communities".localized)
                    .font(.naarsFootnote)
                    .foregroundColor(.naarsTextSecondary)
                    .multilineTextAlignment(.center)
                    .padding(.horizontal, 32)

                // Legal links — visible before any account creation (Guideline 5.1.1)
                VStack(spacing: 4) {
                    Text("signup_terms_agreement".localized)
                        .font(.naarsCaption)
                        .foregroundColor(.naarsTextSecondary)

                    HStack(spacing: 4) {
                        if let tosURL = URL(string: Constants.URLs.termsOfService) {
                            Link("signup_terms_of_service".localized, destination: tosURL)
                                .font(.naarsCaption)
                        }
                        Text("signup_terms_and".localized)
                            .font(.naarsCaption)
                            .foregroundColor(.naarsTextSecondary)
                        if let privacyURL = URL(string: Constants.URLs.privacyPolicy) {
                            Link("signup_privacy_policy".localized, destination: privacyURL)
                                .font(.naarsCaption)
                        }
                    }
                }
                .multilineTextAlignment(.center)
                .padding(.horizontal, 32)
                .padding(.bottom, 32)
            }
            .padding()
        }
        .navigationTitle("")
        .navigationBarHidden(true)
        .navigationDestination(isPresented: $navigateToEmailSignup) {
            SignupDetailsView(viewModel: signupViewModel)
                .environment(appState)
        }
        .navigationDestination(isPresented: $navigateToLogin) {
            LoginView()
                .environment(appState)
        }
        .alert("common_error".localized, isPresented: $showError) {
            Button("common_ok".localized, role: .cancel) {}
        } message: {
            Text(appleSignInViewModel.errorMessage ?? "common_error_occurred".localized)
        }
        .sheet(isPresented: $showInviteEntry) {
            InviteCodeEntrySheet(store: pendingInviteStore) {
                savedInviteCode = pendingInviteStore.peek()
            }
        }
        .trackScreen("Welcome")
        // A join link opened while Welcome is on screen shows the banner without a relaunch.
        .onReceive(NotificationCenter.default.publisher(for: PendingInviteStore.didChange)) { _ in
            savedInviteCode = pendingInviteStore.peek()
        }
        .task {
            savedInviteCode = pendingInviteStore.peek()
            // A guest who chose "Sign In" continues to the sign-in form instead of having
            // to choose again here.
            if WelcomeEntryRoute.opensSignIn {
                WelcomeEntryRoute.opensSignIn = false
                navigateToLogin = true
            }
        }
    }
}

extension WelcomeView {
    /// "I have an invite code", or, once a code is saved, the banner that says so with Remove.
    @ViewBuilder
    var inviteCodeEntry: some View {
        if savedInviteCode != nil {
            VStack(alignment: .leading, spacing: Constants.Spacing.sm) {
                HStack(alignment: .top, spacing: Constants.Spacing.sm) {
                    Image(systemName: "envelope.open.fill")
                        .foregroundColor(.naarsPrimary)
                        .accessibilityHidden(true)
                    Text("community_invite_saved_banner".localized)
                        .font(.naarsSubheadline)
                        .foregroundColor(.naarsTextPrimary)
                        .multilineTextAlignment(.leading)
                        .frame(maxWidth: .infinity, alignment: .leading)
                }
                Button {
                    pendingInviteStore.clear()
                    savedInviteCode = nil
                } label: {
                    Text("community_invite_remove".localized)
                        .font(.naarsSubheadline)
                        .foregroundColor(.naarsPrimary)
                        .frame(minHeight: 44)
                }
                .buttonStyle(.plain)
                .frame(maxWidth: .infinity, alignment: .trailing)
                .accessibilityLabel("community_invite_remove".localized)
                .accessibilityIdentifier("welcome.inviteCode.remove")
            }
            .frame(maxWidth: .infinity, alignment: .leading)
            .cardStyle()
            .accessibilityIdentifier("welcome.inviteCode.banner")
        } else {
            Button {
                showInviteEntry = true
            } label: {
                Text("community_invite_entry_link".localized)
                    .font(.naarsFootnote)
                    .foregroundColor(.naarsPrimary)
                    .frame(maxWidth: .infinity)
                    .padding(.vertical, Constants.Spacing.sm)
            }
            .accessibilityLabel("community_invite_entry_link".localized)
            .accessibilityIdentifier("welcome.inviteCode.entry")
        }
    }
}

/// One-shot hint for the Welcome screen. Leaving guest mode always lands on Welcome, which is
/// the sign-up screen; a guest who tapped "Sign In" sets this so Welcome opens the sign-in
/// form for them. Read and cleared once by `WelcomeView`.
@MainActor
enum WelcomeEntryRoute {
    static var opensSignIn = false
}

#if DEBUG
#Preview {
    NavigationStack {
        WelcomeView(pendingInviteStore: PendingInviteStore(defaults: UserDefaults(suiteName: "preview.welcome.empty")!))
            .environment(AppState())
    }
}

#Preview("Saved invite") {
    let store = PendingInviteStore(defaults: UserDefaults(suiteName: "preview.welcome.saved")!)
    store.save("NC7K2PQ9XA")
    return NavigationStack {
        WelcomeView(pendingInviteStore: store)
            .environment(AppState())
    }
}
#endif
