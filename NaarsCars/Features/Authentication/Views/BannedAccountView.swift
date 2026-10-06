//
//  BannedAccountView.swift
//  NaarsCars
//
//  Restricted screen shown to banned users — delete account, contact support, or sign out
//

import SwiftUI

/// View displayed when a user's account has been restricted by an admin.
/// Users can only contact support, delete their account, or sign out.
struct BannedAccountView: View {
    @StateObject private var viewModel = BannedAccountViewModel()
    @State private var showDeleteConfirmation = false

    var body: some View {
        // Scrolls when the content is taller than the screen (a long reason, large text
        // sizes), so Delete Account and Sign Out stay reachable; otherwise the stack is one
        // screen tall and keeps the centred layout.
        GeometryReader { proxy in
            ScrollView {
                VStack(spacing: Constants.Spacing.lg) {
                    Spacer(minLength: 0)

                    // Icon
                    Image(systemName: "exclamationmark.shield")
                        .font(.system(size: 64))
                        .foregroundColor(.naarsError)
                        .accessibilityHidden(true)

                    // Title
                    Text("banned_title".localized)
                        .font(.naarsTitle2)
                        .fontWeight(.semibold)
                        .multilineTextAlignment(.center)
                        .padding(.horizontal, Constants.Spacing.xl)
                        .accessibilityAddTraits(.isHeader)

                    // Reason section
                    VStack(spacing: 8) {
                        Text("banned_reason_label".localized)
                            .font(.naarsHeadline)
                            .foregroundColor(.secondary)

                        if viewModel.isLoadingReason {
                            ProgressView()
                        } else {
                            Text(viewModel.banReason?.isEmpty == false ? viewModel.banReason! : "banned_reason_fallback".localized)
                                .font(.naarsBody)
                                .foregroundColor(.primary)
                                .multilineTextAlignment(.center)
                                .padding(.horizontal, 24)
                        }
                    }
                    .padding()
                    .frame(maxWidth: .infinity)
                    .background(Color(.secondarySystemGroupedBackground))
                    .cornerRadius(Constants.Radius.card)
                    .padding(.horizontal, 32)

                    // Body
                    Text("banned_body".localized)
                        .font(.naarsCaption)
                        .foregroundColor(.secondary)
                        .multilineTextAlignment(.center)
                        .padding(.horizontal, 32)

                    Spacer(minLength: 0)

                    // Actions
                    VStack(spacing: Constants.Spacing.ms) {
                        // Contact Support
                        PrimaryButton(title: "banned_contact_support".localized, action: {
                            if let url = URL(string: "mailto:naarscars@gmail.com") {
                                UIApplication.shared.open(url)
                            }
                        })
                        .accessibilityIdentifier("banned.contactSupport")

                        // Delete Account
                        SecondaryButton(
                            title: "banned_delete_account".localized,
                            action: { showDeleteConfirmation = true },
                            isDisabled: viewModel.isDeletingAccount || viewModel.isSigningOut,
                            isDestructive: true
                        )
                        .accessibilityIdentifier("banned.deleteAccount")

                        if viewModel.isDeletingAccount {
                            HStack(spacing: Constants.Spacing.sm) {
                                ProgressView()
                                    .scaleEffect(0.8)
                                Text("profile_deleting_account".localized)
                                    .font(.naarsCaption)
                                    .foregroundColor(.secondary)
                            }
                        }

                        // Sign Out
                        AccountTextAction(
                            title: "banned_sign_out".localized,
                            isBusy: viewModel.isSigningOut
                        ) {
                            Task { await viewModel.signOut() }
                        }
                        .disabled(viewModel.isDeletingAccount)
                        .accessibilityIdentifier("banned.signOut")
                    }
                    .padding(.horizontal, Constants.Spacing.xl)
                    .padding(.bottom, Constants.Spacing.lg)
                }
                .frame(maxWidth: .infinity, minHeight: proxy.size.height)
            }
        }
        .background(Color.naarsBackground)
        .task {
            await viewModel.loadBanReason()
        }
        .accountDeletionFlow(
            isConfirming: $showDeleteConfirmation,
            viewModel: viewModel,
            message: "profile_delete_account_message".localized
        )
        .trackScreen("BannedAccount")
    }
}

// MARK: - Shared account actions

/// Low-emphasis text action (Sign Out, Delete Account) used on the application, pending-review
/// and restricted screens. The label fills a 44-pt-tall row so the whole row is tappable.
struct AccountTextAction: View {
    let title: String
    var isDestructive: Bool = false
    var isBusy: Bool = false
    let action: () -> Void

    var body: some View {
        Button(action: action) {
            HStack(spacing: Constants.Spacing.sm) {
                if isBusy {
                    ProgressView()
                        .scaleEffect(0.8)
                }
                Text(title)
                    .font(.naarsSubheadline)
                    .foregroundColor(isDestructive ? Color.naarsError : Color.secondary)
            }
            .frame(maxWidth: .infinity, minHeight: 44)
            .contentShape(Rectangle())
        }
        .disabled(isBusy)
    }
}

/// The delete-account confirmation, result and failure alerts. One implementation for every
/// screen that holds a signed-in user outside the main app, so the flow cannot drift between
/// them: confirm, delete through the view model, confirm the result, then sign out.
private struct AccountDeletionFlowModifier: ViewModifier {
    @Binding var isConfirming: Bool
    @ObservedObject var viewModel: BannedAccountViewModel
    let message: String

    @State private var showSuccess = false
    @State private var showFailure = false
    @State private var failureMessage: String?

    func body(content: Content) -> some View {
        content
            .alert("profile_delete_account".localized, isPresented: $isConfirming) {
                Button("common_cancel".localized, role: .cancel) {}
                Button("profile_delete_account_confirm".localized, role: .destructive) {
                    Task { await deleteAccount() }
                }
            } message: {
                Text(message)
            }
            .alert("profile_account_deleted".localized, isPresented: $showSuccess) {
                Button("common_ok".localized) {
                    Task { await viewModel.signOut() }
                }
            } message: {
                Text("profile_account_deleted_message".localized)
            }
            .alert("profile_deletion_failed".localized, isPresented: $showFailure) {
                Button("common_ok".localized, role: .cancel) {}
            } message: {
                Text(failureMessage ?? "profile_deletion_failed_message".localized)
            }
    }

    private func deleteAccount() async {
        do {
            if try await viewModel.deleteAccount() {
                showSuccess = true
            } else {
                // No session to act on: say so instead of silently doing nothing
                failureMessage = "profile_deletion_failed_message".localized
                showFailure = true
            }
        } catch {
            failureMessage = viewModel.deletionFailureMessage(for: error)
            showFailure = true
        }
    }
}

extension View {
    /// Attaches the shared delete-account flow.
    /// - Parameters:
    ///   - isConfirming: Set to true to ask for confirmation
    ///   - viewModel: Performs the deletion and the sign-out that follows it
    ///   - message: What the confirmation says will be deleted
    func accountDeletionFlow(
        isConfirming: Binding<Bool>,
        viewModel: BannedAccountViewModel,
        message: String
    ) -> some View {
        modifier(AccountDeletionFlowModifier(
            isConfirming: isConfirming,
            viewModel: viewModel,
            message: message
        ))
    }
}

#Preview {
    BannedAccountView()
}
