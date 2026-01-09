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
    
    var body: some View {
        NavigationStack {
            Group {
                if viewModel.isLoading && viewModel.pendingUsers.isEmpty {
                    ProgressView("Loading pending users...")
                        .frame(maxWidth: .infinity, maxHeight: .infinity)
                } else if viewModel.pendingUsers.isEmpty {
                    EmptyStateView(
                        icon: "checkmark.circle.fill",
                        title: "No Pending Users",
                        message: "All users have been approved."
                    )
                } else {
                    List {
                        ForEach(viewModel.pendingUsers) { user in
                            NavigationLink(destination: PendingUserDetailView(user: user)) {
                                PendingUserRow(
                                    user: user,
                                    inviter: user.invitedBy.flatMap { viewModel.inviterProfiles[$0] },
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
            .navigationTitle("Pending Approvals")
            .navigationBarTitleDisplayMode(.large)
            .task {
                await viewModel.loadPendingUsers()
            }
            .refreshable {
                await viewModel.loadPendingUsers()
            }
            .alert("Approve User", isPresented: $showingApproveConfirmation) {
                Button("Cancel", role: .cancel) {
                    userToApprove = nil
                    showingApproveConfirmation = false
                }
                Button("Approve", role: .none) {
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
                Text("Are you sure you want to approve this user? They will be able to access all app features.")
            }
            .alert("Reject User", isPresented: $showingRejectConfirmation) {
                Button("Cancel", role: .cancel) {
                    userToReject = nil
                    showingRejectConfirmation = false
                }
                Button("Reject", role: .destructive) {
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
                Text("Are you sure you want to reject this user? Their account will be deleted.")
            }
        }
    }
}

/// Row component for pending user
private struct PendingUserRow: View {
    let user: Profile
    let inviter: Profile?
    let onApprove: () -> Void
    let onReject: () -> Void
    
    var body: some View {
        VStack(alignment: .leading, spacing: 12) {
            HStack(spacing: 12) {
                // Avatar
                AvatarView(
                    imageUrl: user.avatarUrl,
                    name: user.name,
                    size: 50
                )
                
                // User info
                VStack(alignment: .leading, spacing: 4) {
                    Text(user.name)
                        .font(.naarsHeadline)
                    
                    Text(user.email)
                        .font(.naarsCaption)
                        .foregroundColor(.secondary)
                    
                    // Show invited by info if available
                    if let inviter = inviter {
                        Text("Invited by: \(inviter.name)")
                            .font(.naarsCaption)
                            .foregroundColor(.secondary)
                    } else if user.invitedBy != nil {
                        Text("Invited by: Unknown")
                            .font(.naarsCaption)
                            .foregroundColor(.secondary)
                    }
                }
                
                Spacer()
            }
            
            // Action buttons
            HStack(spacing: 12) {
                Button(action: onReject) {
                    Text("Reject")
                        .font(.naarsBody)
                        .foregroundColor(.naarsError)
                        .frame(maxWidth: .infinity)
                        .padding()
                        .background(Color.naarsError.opacity(0.1))
                        .cornerRadius(10)
                }
                .buttonStyle(PlainButtonStyle())
                
                Button(action: onApprove) {
                    Text("Approve")
                        .font(.naarsBody)
                        .fontWeight(.semibold)
                        .foregroundColor(.white)
                        .frame(maxWidth: .infinity)
                        .padding()
                        .background(Color.naarsPrimary)
                        .cornerRadius(10)
                }
                .buttonStyle(PlainButtonStyle())
            }
        }
        .padding()
        .background(Color(.systemBackground))
        .cornerRadius(12)
        .overlay(
            RoundedRectangle(cornerRadius: 12)
                .stroke(Color(.separator), lineWidth: 1)
        )
        .padding(.horizontal)
        .padding(.vertical, 4)
    }
}

#Preview {
    PendingUsersView()
}

