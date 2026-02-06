//
//  UserManagementView.swift
//  NaarsCars
//
//  View for managing all members and admin status
//

import SwiftUI

/// View for managing all members and admin status
struct UserManagementView: View {
    @StateObject private var viewModel = UserManagementViewModel()
    @State private var userToToggle: UUID?
    @State private var targetAdminStatus: Bool = false
    @State private var showingToggleConfirmation = false
    @State private var toastMessage: String? = nil
    
    var body: some View {
        NavigationStack {
            Group {
                if viewModel.isLoading && viewModel.members.isEmpty {
                    ProgressView("admin_loading_members".localized)
                        .frame(maxWidth: .infinity, maxHeight: .infinity)
                } else if viewModel.members.isEmpty {
                    EmptyStateView(
                        icon: "person.3.fill",
                        title: "admin_no_members".localized,
                        message: "admin_no_members_found".localized
                    )
                } else {
                    List {
                        ForEach(viewModel.members) { member in
                            NavigationLink(destination: PublicProfileView(userId: member.id)) {
                                MemberRow(
                                    member: member,
                                    canChangeAdmin: viewModel.canChangeAdminStatus(for: member.id),
                                    onToggleAdmin: { isAdmin in
                                        userToToggle = member.id
                                        targetAdminStatus = isAdmin
                                        showingToggleConfirmation = true
                                    }
                                )
                            }
                            .buttonStyle(PlainButtonStyle())
                        }
                    }
                    .listStyle(.plain)
                }
            }
            .navigationTitle("admin_all_members".localized)
            .navigationBarTitleDisplayMode(.large)
            .task {
                await viewModel.loadAllMembers()
            }
            .refreshable {
                await viewModel.loadAllMembers()
            }
            .alert(
                targetAdminStatus ? "admin_make_admin".localized : "admin_remove_admin".localized,
                isPresented: $showingToggleConfirmation
            ) {
                Button("common_cancel".localized, role: .cancel) {
                    userToToggle = nil
                    showingToggleConfirmation = false
                }
                Button(targetAdminStatus ? "admin_make_admin".localized : "admin_remove_admin".localized, role: targetAdminStatus ? .none : .destructive) {
                    let userId = userToToggle
                    userToToggle = nil
                    showingToggleConfirmation = false
                    if let userId = userId {
                        Task {
                            await viewModel.toggleAdminStatus(userId: userId, isAdmin: targetAdminStatus)
                            if viewModel.error == nil {
                                toastMessage = "toast_admin_status_updated".localized
                            }
                        }
                    }
                }
            } message: {
                if targetAdminStatus {
                    Text("admin_make_admin_confirmation".localized)
                } else {
                    Text("admin_remove_admin_confirmation".localized)
                }
            }
            .toast(message: $toastMessage)
        }
    }
}

/// Row component for member
private struct MemberRow: View {
    let member: Profile
    let canChangeAdmin: Bool
    let onToggleAdmin: (Bool) -> Void
    
    var body: some View {
        HStack(spacing: 12) {
            // Avatar
            AvatarView(
                imageUrl: member.avatarUrl,
                name: member.name,
                size: 44
            )
            
            // User info
            VStack(alignment: .leading, spacing: 4) {
                HStack {
                    Text(member.name)
                        .font(.naarsHeadline)
                    
                    if member.isAdmin {
                        Text("admin_badge".localized)
                            .font(.naarsCaption)
                            .fontWeight(.semibold)
                            .foregroundColor(.white)
                            .padding(.horizontal, 8)
                            .padding(.vertical, 4)
                            .background(Color.naarsPrimary)
                            .cornerRadius(8)
                    }
                }
                
                Text(member.email)
                    .font(.naarsCaption)
                    .foregroundColor(.secondary)
            }
            
            Spacer()
            
            // Toggle admin button
            if canChangeAdmin {
                Button(action: {
                    onToggleAdmin(!member.isAdmin)
                }) {
                    Text(member.isAdmin ? "admin_remove_admin".localized : "admin_make_admin".localized)
                        .font(.naarsCaption)
                        .fontWeight(.semibold)
                        .foregroundColor(member.isAdmin ? .naarsError : .naarsPrimary)
                        .padding(.horizontal, 12)
                        .padding(.vertical, 6)
                        .background(
                            (member.isAdmin ? Color.naarsError : Color.naarsPrimary).opacity(0.1)
                        )
                        .cornerRadius(8)
                }
                .buttonStyle(PlainButtonStyle())
                .highPriorityGesture(
                    TapGesture()
                        .onEnded { _ in
                            onToggleAdmin(!member.isAdmin)
                        }
                )
            }
        }
        .padding(.vertical, 8)
        .padding(.horizontal, 12)
        .contentShape(Rectangle())
    }
}

#Preview {
    UserManagementView()
}

