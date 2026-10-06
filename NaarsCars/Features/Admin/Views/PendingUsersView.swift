//
//  PendingUsersView.swift
//  NaarsCars
//
//  View for pending user approvals
//

import SwiftUI

/// View for pending user approvals
struct PendingUsersView: View {
    @StateObject private var viewModel = PendingUsersViewModel()
    @State private var userToApprove: UUID?
    @State private var userToReject: UUID?
    @State private var showingApproveConfirmation = false
    @State private var showingRejectConfirmation = false
    
    // No NavigationStack here: this screen is pushed onto the Profile tab's stack (from the
    // admin panel and from the pending-approvals notification route), so it only contributes
    // content. A stack of its own drew a second navigation bar.
    var body: some View {
        Group {
            if viewModel.isLoading && viewModel.pendingUsers.isEmpty {
                ProgressView("admin_loading_pending".localized)
                    .frame(maxWidth: .infinity, maxHeight: .infinity)
            } else if let error = viewModel.error, viewModel.pendingUsers.isEmpty {
                // A failed load is not "everyone has been approved".
                ErrorView(
                    error: error.localizedDescription,
                    retryAction: {
                        Task { await viewModel.loadPendingUsers() }
                    }
                )
            } else if viewModel.pendingUsers.isEmpty {
                EmptyStateView(
                    icon: "checkmark.circle.fill",
                    title: "admin_no_pending_users".localized,
                    message: "admin_all_approved".localized
                )
            } else {
                List {
                    ForEach(viewModel.pendingUsers) { user in
                        NavigationLink(destination: PendingUserDetailView(user: user)) {
                            PendingUserRow(
                                user: user,
                                isActionDisabled: viewModel.isPerformingAction,
                                onApprove: {
                                    userToApprove = user.id
                                    showingApproveConfirmation = true
                                },
                                onReject: {
                                    userToReject = user.id
                                    showingRejectConfirmation = true
                                }
                            )
                        }
                        .buttonStyle(PlainButtonStyle())
                    }
                }
                .listStyle(.plain)
            }
        }
        .navigationTitle("admin_pending_approvals".localized)
        .navigationBarTitleDisplayMode(.large)
        .id("profile.admin.pendingUsersList")
        .toolbar {
            if viewModel.isPerformingAction {
                ToolbarItem(placement: .topBarTrailing) {
                    ProgressView()
                }
            }
        }
        .task {
            await viewModel.loadPendingUsers()
        }
        .refreshable {
            await viewModel.loadPendingUsers()
        }
        .onDisappear { viewModel.stop() }
        .alert("admin_approve_user".localized, isPresented: $showingApproveConfirmation) {
            Button("common_cancel".localized, role: .cancel) {
                userToApprove = nil
                showingApproveConfirmation = false
            }
            Button("admin_approve".localized, role: .none) {
                let userId = userToApprove
                userToApprove = nil
                showingApproveConfirmation = false
                if let userId = userId {
                    Task {
                        await viewModel.approveUser(userId: userId)
                    }
                }
            }
        } message: {
            Text("admin_approve_confirmation".localized)
        }
        .alert("admin_reject_user".localized, isPresented: $showingRejectConfirmation) {
            Button("common_cancel".localized, role: .cancel) {
                userToReject = nil
                showingRejectConfirmation = false
            }
            Button("admin_reject".localized, role: .destructive) {
                let userId = userToReject
                userToReject = nil
                showingRejectConfirmation = false
                if let userId = userId {
                    Task {
                        await viewModel.rejectUser(userId: userId)
                    }
                }
            }
        } message: {
            Text("admin_reject_confirmation".localized)
        }
        .errorBanner(message: $viewModel.actionErrorMessage)
    }
}

/// Row component for pending user
private struct PendingUserRow: View {
    let user: Profile
    /// True while an approve or reject request is running, so a second one cannot be started
    let isActionDisabled: Bool
    let onApprove: () -> Void
    let onReject: () -> Void

    var body: some View {
        VStack(alignment: .leading, spacing: 12) {
            HStack(spacing: 12) {
                // Avatar
                AvatarView(
                    imageUrl: user.avatarUrl,
                    name: user.name,
                    size: 50,
                    userId: user.id
                )

                // User info
                VStack(alignment: .leading, spacing: 4) {
                    Text(user.name)
                        .font(.naarsHeadline)

                    Text(user.email)
                        .font(.naarsCaption)
                        .foregroundColor(.secondary)

                    // Show application reason if available
                    if let reason = user.joinReason, !reason.isEmpty {
                        Text(reason)
                            .font(.naarsCaption)
                            .foregroundColor(.secondary)
                            .lineLimit(2)
                    }
                }

                Spacer()
            }
            
            // Action buttons
            HStack(spacing: 12) {
                Button(action: onReject) {
                    Text("admin_reject".localized)
                        .font(.naarsBody)
                        .foregroundColor(.naarsError)
                        .frame(maxWidth: .infinity)
                        .padding()
                        .background(Color.naarsError.opacity(0.12))
                        .clipShape(Capsule())
                }
                .buttonStyle(PlainButtonStyle())
                
                Button(action: onApprove) {
                    Text("admin_approve".localized)
                        .font(.naarsBody)
                        .fontWeight(.semibold)
                        .foregroundColor(.white)
                        .frame(maxWidth: .infinity)
                        .padding()
                        .background(Color.naarsPrimary)
                        .clipShape(Capsule())
                }
                .buttonStyle(PlainButtonStyle())
            }
            .disabled(isActionDisabled)
            .opacity(isActionDisabled ? 0.5 : 1)
        }
        .padding()
        .background(Color.naarsBackgroundSecondary)
        .cornerRadius(Constants.Radius.card)
        .overlay(
            RoundedRectangle(cornerRadius: Constants.Radius.card)
                .stroke(Color(.separator), lineWidth: 1)
        )
        .padding(.horizontal)
        .padding(.vertical, 4)
    }
}

#Preview {
    NavigationStack {
        PendingUsersView()
    }
}

