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
    @State private var showSuccess = false
    
    var body: some View {
        ScrollView {
            VStack(spacing: 24) {
                // User Info Section
                VStack(spacing: 16) {
                    AvatarView(
                        imageUrl: user.avatarUrl,
                        name: user.name,
                        size: 80,
                        userId: user.id
                    )
                    
                    Text(user.name)
                        .font(.naarsTitle2)
                        .fontWeight(.semibold)
                    
                    Text(user.email)
                        .font(.naarsSubheadline)
                        .foregroundColor(.secondary)
                    
                    if let car = user.car, !car.isEmpty {
                        Text(car)
                            .font(.naarsSubheadline)
                            .foregroundColor(.secondary)
                    }
                }
                .padding()
                .frame(maxWidth: .infinity)
                .background(Color.naarsCardBackground)
                .cornerRadius(12)
                
                // Application Information Section
                VStack(alignment: .leading, spacing: 16) {
                    Text("admin_application_info".localized)
                        .font(.naarsHeadline)

                    // How they heard about the app
                    VStack(alignment: .leading, spacing: 8) {
                        Text("admin_heard_about_label".localized)
                            .font(.naarsSubheadline)
                            .foregroundColor(.secondary)

                        Text(user.heardAbout ?? "admin_not_provided".localized)
                            .font(.naarsBody)
                            .padding()
                            .frame(maxWidth: .infinity, alignment: .leading)
                            .background(Color.naarsCardBackground)
                            .cornerRadius(8)
                    }

                    // Why they want to join
                    VStack(alignment: .leading, spacing: 8) {
                        Text("admin_join_reason_label".localized)
                            .font(.naarsSubheadline)
                            .foregroundColor(.secondary)

                        Text(user.joinReason ?? "admin_not_provided".localized)
                            .font(.naarsBody)
                            .padding()
                            .frame(maxWidth: .infinity, alignment: .leading)
                            .background(Color.naarsCardBackground)
                            .cornerRadius(8)
                    }

                    // Submitted at
                    if let submittedAt = user.applicationSubmittedAt {
                        HStack {
                            Text("admin_submitted_at_label".localized)
                                .font(.naarsCaption)
                                .foregroundColor(.secondary)
                            Spacer()
                            Text(submittedAt.dateString)
                                .font(.naarsCaption)
                                .foregroundColor(.secondary)
                        }
                    }

                    // Account created at
                    HStack {
                        Text("admin_account_created_label".localized)
                            .font(.naarsCaption)
                            .foregroundColor(.secondary)
                        Spacer()
                        Text(user.createdAt.dateString)
                            .font(.naarsCaption)
                            .foregroundColor(.secondary)
                    }
                }
                .padding()
                .background(Color.naarsBackgroundSecondary)
                .cornerRadius(12)
                .overlay(
                    RoundedRectangle(cornerRadius: 12)
                        .stroke(Color(.separator), lineWidth: 1)
                )
                
                // Action Buttons
                VStack(spacing: 12) {
                    Button(action: {
                        showingRejectConfirmation = true
                    }) {
                        Text("admin_reject".localized)
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
                        Text("admin_approve".localized)
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
        .navigationTitle("admin_user_details".localized)
        .navigationBarTitleDisplayMode(.inline)
        .task {
            // Application fields are on the Profile object — no async load needed
        }
        .alert("admin_approve_user".localized, isPresented: $showingApproveConfirmation) {
            Button("common_cancel".localized, role: .cancel) {
                showingApproveConfirmation = false
            }
            Button("admin_approve".localized, role: .none) {
                showingApproveConfirmation = false
                Task {
                    await viewModel.approveUser(userId: user.id)
                    if viewModel.error == nil {
                        showSuccess = true
                    }
                }
            }
        } message: {
            Text("admin_approve_confirmation".localized)
        }
        .alert("admin_reject_user".localized, isPresented: $showingRejectConfirmation) {
            Button("common_cancel".localized, role: .cancel) {
                showingRejectConfirmation = false
            }
            Button("admin_reject".localized, role: .destructive) {
                showingRejectConfirmation = false
                Task {
                    await viewModel.rejectUser(userId: user.id)
                    if viewModel.error == nil {
                        showSuccess = true
                    }
                }
            }
        } message: {
            Text("admin_reject_confirmation".localized)
        }
        .successCheckmark(isShowing: $showSuccess)
        .onChange(of: showSuccess) { _, newValue in
            if !newValue {
                dismiss()
            }
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

