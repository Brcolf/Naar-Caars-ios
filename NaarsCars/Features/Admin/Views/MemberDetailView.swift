//
//  MemberDetailView.swift
//  NaarsCars
//
//  Admin detail view for a member — toggle admin, restrict/unrestrict
//

import SwiftUI

/// Admin detail view for managing a single member.
/// Consolidates admin actions: toggle admin status, ban/unban.
struct MemberDetailView: View {
    let member: Profile
    @ObservedObject var viewModel: UserManagementViewModel

    @State private var showAdminConfirmation = false
    @State private var showBanSheet = false
    @State private var showUnbanConfirmation = false
    @State private var banReason = ""
    @State private var toastMessage: String?

    private var isSelf: Bool {
        member.id == AuthService.shared.currentUserId
    }

    var body: some View {
        List {
            // Member info header
            Section {
                HStack(spacing: 16) {
                    AvatarView(
                        imageUrl: member.avatarUrl,
                        name: member.name,
                        size: 64,
                        userId: member.id
                    )

                    VStack(alignment: .leading, spacing: 4) {
                        HStack {
                            Text(member.name)
                                .font(.naarsTitle3)
                                .fontWeight(.semibold)

                            if member.isAdmin {
                                NaarsChip(text: "admin_badge".localized)
                            }

                            if member.isBanned {
                                NaarsChip(text: "admin_user_restricted_badge".localized, tint: .naarsError)
                            }
                        }

                        Text(member.email)
                            .font(.naarsCaption)
                            .foregroundColor(.secondary)

                        Text("admin_member_joined".localized(with: member.createdAt.formatted(date: .abbreviated, time: .omitted)))
                            .font(.naarsCaption)
                            .foregroundColor(.secondary)
                    }
                }
                .padding(.vertical, 8)
            }

            // Admin actions
            if !isSelf {
                Section("admin_actions_header".localized) {
                    // Toggle Admin
                    Button(action: {
                        showAdminConfirmation = true
                    }) {
                        HStack {
                            Image(systemName: member.isAdmin ? "person.badge.minus" : "person.badge.shield.checkmark")
                                .foregroundColor(member.isAdmin ? .naarsError : .naarsPrimary)
                            Text(member.isAdmin ? "admin_remove_admin".localized : "admin_make_admin".localized)
                                .foregroundColor(.primary)
                            Spacer()
                        }
                    }

                    // Ban / Unban
                    if member.isBanned {
                        Button(action: {
                            showUnbanConfirmation = true
                        }) {
                            HStack {
                                Image(systemName: "checkmark.shield")
                                    .foregroundColor(.naarsSuccess)
                                Text("admin_remove_restriction".localized)
                                    .foregroundColor(.primary)
                                Spacer()
                            }
                        }
                    } else {
                        Button(action: {
                            banReason = ""
                            showBanSheet = true
                        }) {
                            HStack {
                                Image(systemName: "exclamationmark.shield")
                                    .foregroundColor(.naarsError)
                                Text("admin_restrict_user".localized)
                                    .foregroundColor(.naarsError)
                                Spacer()
                            }
                        }
                    }
                }
                // One request at a time; the toolbar shows a spinner while it runs.
                .disabled(viewModel.isPerformingAction)
            }

            // View public profile link
            Section {
                NavigationLink(destination: PublicProfileView(userId: member.id)) {
                    HStack {
                        Image(systemName: "person.crop.circle")
                        Text("admin_view_profile".localized)
                    }
                }
            }
        }
        .navigationTitle(member.name)
        .navigationBarTitleDisplayMode(.inline)
        // Admin toggle confirmation
        .alert(
            member.isAdmin ? "admin_remove_admin".localized : "admin_make_admin".localized,
            isPresented: $showAdminConfirmation
        ) {
            Button("common_cancel".localized, role: .cancel) {}
            Button(
                member.isAdmin ? "admin_remove_admin".localized : "admin_make_admin".localized,
                role: member.isAdmin ? .destructive : .none
            ) {
                Task {
                    if await viewModel.toggleAdminStatus(userId: member.id, isAdmin: !member.isAdmin) {
                        toastMessage = "toast_admin_status_updated".localized
                    }
                }
            }
        } message: {
            Text(member.isAdmin ? "admin_remove_admin_confirmation".localized : "admin_make_admin_confirmation".localized)
        }
        // Unban confirmation
        .alert("admin_remove_restriction".localized, isPresented: $showUnbanConfirmation) {
            Button("common_cancel".localized, role: .cancel) {}
            Button("admin_remove_restriction".localized) {
                Task {
                    if await viewModel.unbanUser(userId: member.id) {
                        toastMessage = "admin_restriction_removed_toast".localized
                    }
                }
            }
        } message: {
            Text("admin_remove_restriction_confirm".localized)
        }
        // Ban reason sheet
        .sheet(isPresented: $showBanSheet) {
            NavigationStack {
                Form {
                    Section {
                        Text("admin_restrict_confirm_message".localized)
                            .font(.naarsBody)
                            .foregroundColor(.secondary)
                    }

                    Section("admin_restrict_reason_prompt".localized) {
                        TextField(
                            "admin_restrict_reason_placeholder".localized,
                            text: $banReason,
                            axis: .vertical
                        )
                        .lineLimit(3...6)
                    }
                }
                .navigationTitle("admin_restrict_user".localized)
                .navigationBarTitleDisplayMode(.inline)
                .toolbar {
                    ToolbarItem(placement: .cancellationAction) {
                        Button("common_cancel".localized) {
                            showBanSheet = false
                        }
                    }
                    ToolbarItem(placement: .confirmationAction) {
                        Button("admin_restrict_confirm".localized) {
                            showBanSheet = false
                            Task {
                                if await viewModel.banUser(userId: member.id, reason: banReason) {
                                    toastMessage = "admin_user_restricted_toast".localized
                                }
                            }
                        }
                        .disabled(banReason.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty)
                    }
                }
            }
            .presentationDetents([.medium])
        }
        .toolbar {
            if viewModel.isPerformingAction {
                ToolbarItem(placement: .topBarTrailing) {
                    ProgressView()
                }
            }
        }
        .toast(message: $toastMessage)
        .errorBanner(message: $viewModel.actionErrorMessage)
        // Every member's detail screen shares this view model and the banner stays until
        // dismissed, so clear it on leaving or it shows up on the next member opened.
        .onDisappear { viewModel.actionErrorMessage = nil }
    }
}
