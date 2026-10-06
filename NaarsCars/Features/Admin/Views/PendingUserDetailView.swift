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
                .cornerRadius(Constants.Radius.card)
                
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
                            // Inset fill: the card's own color made the answer block invisible.
                            .background(Color.naarsInsetBackground)
                            .cornerRadius(Constants.Radius.sm)
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
                            .background(Color.naarsInsetBackground)
                            .cornerRadius(Constants.Radius.sm)
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
                .cornerRadius(Constants.Radius.card)
                .overlay(
                    RoundedRectangle(cornerRadius: Constants.Radius.card)
                        .stroke(Color(.separator), lineWidth: 1)
                )
                
                // Action Buttons
                VStack(spacing: 12) {
                    if viewModel.isRejecting {
                        ProgressView()
                            .accessibilityLabel("common_loading".localized)
                    }

                    // Both stay disabled while either request runs, so neither can be sent twice.
                    SecondaryButton(
                        title: "admin_reject".localized,
                        action: { showingRejectConfirmation = true },
                        isDisabled: viewModel.isApproving || viewModel.isRejecting,
                        isDestructive: true
                    )

                    PrimaryButton(
                        title: "admin_approve".localized,
                        action: { showingApproveConfirmation = true },
                        isLoading: viewModel.isApproving,
                        isDisabled: viewModel.isRejecting
                    )
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
                    if await viewModel.approveUser(userId: user.id) {
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
                    if await viewModel.rejectUser(userId: user.id) {
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
        .errorBanner(message: $viewModel.actionErrorMessage)
    }
}

/// ViewModel for pending user detail view
@MainActor
final class PendingUserDetailViewModel: ObservableObject {
    @Published var inviteInfo: (inviter: Profile?, statement: String?)?
    @Published var isLoading: Bool = false
    @Published var error: AppError?
    /// A failed approve or reject, shown in the error banner
    @Published var actionErrorMessage: String?
    @Published var isApproving: Bool = false
    @Published var isRejecting: Bool = false

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
    
    /// Approve the applicant. Returns false, with `actionErrorMessage` set, when it fails.
    func approveUser(userId: UUID) async -> Bool {
        guard !isApproving, !isRejecting else { return false }
        error = nil
        actionErrorMessage = nil
        isApproving = true
        defer { isApproving = false }
        do {
            try await adminService.approveUser(userId: userId)
            // Same as approving from the list: the pending-approvals badge must drop now,
            // not at the next push or safety poll.
            _ = await RefreshCoordinator.shared.forceFullRefreshAndWait(.badges, trigger: "adminApproveUser")
            return true
        } catch {
            self.error = error as? AppError ?? AppError.processingError(error.localizedDescription)
            actionErrorMessage = "admin_approve_failed".localized
            HapticManager.error()
            AppLogger.error("admin", "Error approving user: \(error.localizedDescription)")
            return false
        }
    }

    /// Reject the applicant. Returns false, with `actionErrorMessage` set, when it fails.
    func rejectUser(userId: UUID) async -> Bool {
        guard !isApproving, !isRejecting else { return false }
        error = nil
        actionErrorMessage = nil
        isRejecting = true
        defer { isRejecting = false }
        do {
            try await adminService.rejectUser(userId: userId)
            _ = await RefreshCoordinator.shared.forceFullRefreshAndWait(.badges, trigger: "adminRejectUser")
            return true
        } catch {
            self.error = error as? AppError ?? AppError.processingError(error.localizedDescription)
            actionErrorMessage = "admin_reject_failed".localized
            HapticManager.error()
            AppLogger.error("admin", "Error rejecting user: \(error.localizedDescription)")
            return false
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

