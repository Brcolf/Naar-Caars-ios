//
//  PendingUserDetailView.swift
//  NaarsCars
//
//  Detail view for pending user approval
//  Shows inviter information and invitation statement
//

import SwiftUI
internal import Combine

/// Detail view for a pending user showing invite information
struct PendingUserDetailView: View {
    let user: Profile
    @StateObject private var viewModel = PendingUserDetailViewModel()
    @Environment(\.dismiss) private var dismiss
    @State private var showingApproveConfirmation = false
    @State private var showingRejectConfirmation = false
    
    var body: some View {
        ScrollView {
            VStack(spacing: 24) {
                // User Info Section
                VStack(spacing: 16) {
                    AvatarView(
                        imageUrl: user.avatarUrl,
                        name: user.name,
                        size: 80
                    )
                    
                    Text(user.name)
                        .font(.title2)
                        .fontWeight(.semibold)
                    
                    Text(user.email)
                        .font(.subheadline)
                        .foregroundColor(.secondary)
                    
                    if let car = user.car, !car.isEmpty {
                        Text(car)
                            .font(.subheadline)
                            .foregroundColor(.secondary)
                    }
                }
                .padding()
                .frame(maxWidth: .infinity)
                .background(Color(.systemGray6))
                .cornerRadius(12)
                
                // Invite Information Section
                if viewModel.isLoading {
                    ProgressView("Loading invite details...")
                        .frame(maxWidth: .infinity, minHeight: 200)
                } else if let inviteInfo = viewModel.inviteInfo {
                    VStack(alignment: .leading, spacing: 16) {
                        Text("Invite Information")
                            .font(.headline)
                        
                        // Inviter
                        if let inviter = inviteInfo.inviter {
                            VStack(alignment: .leading, spacing: 8) {
                                Text("Invited By")
                                    .font(.subheadline)
                                    .foregroundColor(.secondary)
                                
                                HStack(spacing: 12) {
                                    AvatarView(
                                        imageUrl: inviter.avatarUrl,
                                        name: inviter.name,
                                        size: 40
                                    )
                                    
                                    Text(inviter.name)
                                        .font(.body)
                                        .fontWeight(.medium)
                                }
                            }
                            .padding()
                            .background(Color(.systemGray6))
                            .cornerRadius(8)
                        }
                        
                        // Invitation Statement
                        if let statement = inviteInfo.statement, !statement.isEmpty {
                            VStack(alignment: .leading, spacing: 8) {
                                Text("Invitation Statement")
                                    .font(.subheadline)
                                    .foregroundColor(.secondary)
                                
                                Text(statement)
                                    .font(.body)
                                    .padding()
                                    .frame(maxWidth: .infinity, alignment: .leading)
                                    .background(Color(.systemGray6))
                                    .cornerRadius(8)
                            }
                        } else {
                            Text("No invitation statement provided")
                                .font(.subheadline)
                                .foregroundColor(.secondary)
                                .italic()
                        }
                    }
                    .padding()
                    .background(Color(.systemBackground))
                    .cornerRadius(12)
                    .overlay(
                        RoundedRectangle(cornerRadius: 12)
                            .stroke(Color(.separator), lineWidth: 1)
                    )
                } else if viewModel.error != nil {
                    ErrorView(
                        error: viewModel.error?.localizedDescription ?? "Failed to load invite details",
                        retryAction: {
                            Task {
                                await viewModel.loadInviteInfo(for: user.id)
                            }
                        }
                    )
                }
                
                // Action Buttons
                VStack(spacing: 12) {
                    Button(action: {
                        showingRejectConfirmation = true
                    }) {
                        Text("Reject")
                            .font(.naarsBody)
                            .fontWeight(.semibold)
                            .foregroundColor(.white)
                            .frame(maxWidth: .infinity)
                            .padding()
                            .background(Color.naarsError)
                            .cornerRadius(10)
                    }
                    
                    Button(action: {
                        showingApproveConfirmation = true
                    }) {
                        Text("Approve")
                            .font(.naarsBody)
                            .fontWeight(.semibold)
                            .foregroundColor(.white)
                            .frame(maxWidth: .infinity)
                            .padding()
                            .background(Color.naarsPrimary)
                            .cornerRadius(10)
                    }
                }
                .padding(.horizontal)
            }
            .padding()
        }
        .navigationTitle("User Details")
        .navigationBarTitleDisplayMode(.inline)
        .task {
            await viewModel.loadInviteInfo(for: user.id)
        }
        .alert("Approve User", isPresented: $showingApproveConfirmation) {
            Button("Cancel", role: .cancel) {
                showingApproveConfirmation = false
            }
            Button("Approve", role: .none) {
                showingApproveConfirmation = false
                Task {
                    await viewModel.approveUser(userId: user.id)
                    if viewModel.error == nil {
                        dismiss()
                    }
                }
            }
        } message: {
            Text("Are you sure you want to approve this user? They will be able to access all app features.")
        }
        .alert("Reject User", isPresented: $showingRejectConfirmation) {
            Button("Cancel", role: .cancel) {
                showingRejectConfirmation = false
            }
            Button("Reject", role: .destructive) {
                showingRejectConfirmation = false
                Task {
                    await viewModel.rejectUser(userId: user.id)
                    if viewModel.error == nil {
                        dismiss()
                    }
                }
            }
        } message: {
            Text("Are you sure you want to reject this user? Their account will be deleted.")
        }
    }
}

/// ViewModel for pending user detail view
@MainActor
final class PendingUserDetailViewModel: ObservableObject {
    @Published var inviteInfo: (inviter: Profile?, statement: String?)?
    @Published var isLoading: Bool = false
    @Published var error: AppError?
    
    private let inviteService = InviteService.shared
    private let adminService = AdminService.shared
    
    func loadInviteInfo(for userId: UUID) async {
        isLoading = true
        error = nil
        defer { isLoading = false }
        
        do {
            if let details = try await inviteService.fetchInviteCodeForUser(userId: userId) {
                inviteInfo = (details.inviter, details.statement)
            } else {
                // No invite code found - user might have been created differently
                inviteInfo = (nil, nil)
            }
        } catch {
            self.error = error as? AppError ?? AppError.unknown(error.localizedDescription)
        }
    }
    
    func approveUser(userId: UUID) async {
        error = nil
        do {
            try await adminService.approveUser(userId: userId)
        } catch {
            self.error = error as? AppError ?? AppError.processingError(error.localizedDescription)
        }
    }
    
    func rejectUser(userId: UUID) async {
        error = nil
        do {
            try await adminService.rejectUser(userId: userId)
        } catch {
            self.error = error as? AppError ?? AppError.processingError(error.localizedDescription)
        }
    }
}

#Preview {
    NavigationStack {
        PendingUserDetailView(
            user: Profile(
                id: UUID(),
                name: "John Doe",
                email: "john@example.com",
                car: "Toyota Camry",
                phoneNumber: nil,
                avatarUrl: nil,
                isAdmin: false,
                approved: false,
                invitedBy: UUID(),
                notifyRideUpdates: true,
                notifyMessages: true,
                notifyAnnouncements: true,
                notifyNewRequests: true,
                notifyQaActivity: true,
                notifyReviewReminders: true,
                createdAt: Date(),
                updatedAt: Date()
            )
        )
    }
}

