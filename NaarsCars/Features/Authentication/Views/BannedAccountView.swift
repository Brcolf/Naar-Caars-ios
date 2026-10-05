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
    @State private var showDeleteSuccess = false
    @State private var showDeleteError = false
    @State private var deleteErrorMessage: String?

    var body: some View {
        VStack(spacing: 24) {
            Spacer()

            // Icon
            Image(systemName: "exclamationmark.shield")
                .font(.system(size: 64))
                .foregroundColor(.naarsError)

            // Title
            Text("banned_title".localized)
                .font(.naarsTitle2)
                .fontWeight(.semibold)
                .multilineTextAlignment(.center)

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
            .cornerRadius(12)
            .padding(.horizontal, 32)

            // Body
            Text("banned_body".localized)
                .font(.naarsCaption)
                .foregroundColor(.secondary)
                .multilineTextAlignment(.center)
                .padding(.horizontal, 32)

            Spacer()

            // Actions
            VStack(spacing: 12) {
                // Contact Support
                Button(action: {
                    if let url = URL(string: "mailto:naarscars@gmail.com") {
                        UIApplication.shared.open(url)
                    }
                }) {
                    Text("banned_contact_support".localized)
                        .font(.naarsHeadline)
                        .foregroundColor(.white)
                        .frame(maxWidth: .infinity)
                        .frame(height: 50)
                        .background(Color.naarsPrimary)
                        .cornerRadius(12)
                }
                .accessibilityIdentifier("banned.contactSupport")

                // Delete Account
                Button(action: {
                    showDeleteConfirmation = true
                }) {
                    HStack {
                        if viewModel.isDeletingAccount {
                            ProgressView()
                                .progressViewStyle(CircularProgressViewStyle())
                                .scaleEffect(0.8)
                        }
                        Text("banned_delete_account".localized)
                            .font(.naarsHeadline)
                            .foregroundColor(.naarsError)
                    }
                    .frame(maxWidth: .infinity)
                    .frame(height: 50)
                    .background(Color.naarsBackgroundSecondary)
                    .cornerRadius(12)
                    .overlay(
                        RoundedRectangle(cornerRadius: 12)
                            .stroke(Color(.separator), lineWidth: 1)
                    )
                }
                .disabled(viewModel.isDeletingAccount)
                .accessibilityIdentifier("banned.deleteAccount")

                // Sign Out
                Button(action: {
                    signOut()
                }) {
                    HStack {
                        if viewModel.isSigningOut {
                            ProgressView()
                                .progressViewStyle(CircularProgressViewStyle())
                                .scaleEffect(0.8)
                        }
                        Text("banned_sign_out".localized)
                            .font(.naarsSubheadline)
                            .foregroundColor(.secondary)
                    }
                }
                .disabled(viewModel.isSigningOut)
                .accessibilityIdentifier("banned.signOut")
            }
            .padding(.horizontal, 32)
            .padding(.bottom, 40)
        }
        .frame(maxWidth: .infinity, maxHeight: .infinity)
        .background(Color(.systemGroupedBackground))
        .task {
            await viewModel.loadBanReason()
        }
        .alert("profile_delete_account".localized, isPresented: $showDeleteConfirmation) {
            Button("common_cancel".localized, role: .cancel) {}
            Button("profile_delete_account_confirm".localized, role: .destructive) {
                Task { await deleteAccount() }
            }
        } message: {
            Text("profile_delete_account_message".localized)
        }
        .alert("profile_account_deleted".localized, isPresented: $showDeleteSuccess) {
            Button("common_ok".localized) {
                signOut()
            }
        } message: {
            Text("profile_account_deleted_message".localized)
        }
        .alert("common_error".localized, isPresented: $showDeleteError) {
            Button("common_ok".localized, role: .cancel) {}
        } message: {
            Text(deleteErrorMessage ?? "common_error_occurred".localized)
        }
        .trackScreen("BannedAccount")
    }

    // MARK: - Actions

    private func deleteAccount() async {
        do {
            guard try await viewModel.deleteAccount() else { return }
            showDeleteSuccess = true
        } catch {
            deleteErrorMessage = error.localizedDescription
            showDeleteError = true
        }
    }

    private func signOut() {
        Task { await viewModel.signOut() }
    }
}

#Preview {
    BannedAccountView()
}
