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
                            NavigationLink(destination: MemberDetailView(member: member, viewModel: viewModel)) {
                                MemberRow(member: member)
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
            .toast(message: $toastMessage)
        }
    }
}

/// Row component for member
private struct MemberRow: View {
    let member: Profile

    var body: some View {
        HStack(spacing: 12) {
            AvatarView(
                imageUrl: member.avatarUrl,
                name: member.name,
                size: 44,
                userId: member.id
            )

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

                    if member.isBanned {
                        Text("admin_user_restricted_badge".localized)
                            .font(.naarsCaption)
                            .fontWeight(.semibold)
                            .foregroundColor(.white)
                            .padding(.horizontal, 8)
                            .padding(.vertical, 4)
                            .background(Color.naarsError)
                            .cornerRadius(8)
                    }
                }

                Text(member.email)
                    .font(.naarsCaption)
                    .foregroundColor(.secondary)
            }

            Spacer()
        }
        .padding(.vertical, 8)
        .padding(.horizontal, 12)
        .contentShape(Rectangle())
    }
}

#Preview {
    UserManagementView()
}

