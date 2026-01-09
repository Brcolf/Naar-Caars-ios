//
//  AdminPanelView.swift
//  NaarsCars
//
//  Admin panel dashboard view
//

import SwiftUI

/// Admin panel dashboard view
/// Only accessible to users with is_admin = true
struct AdminPanelView: View {
    @StateObject private var viewModel = AdminPanelViewModel()
    @Environment(\.dismiss) private var dismiss
    
    var body: some View {
        Group {
            if viewModel.isVerifyingAdmin {
                ProgressView("Verifying access...")
                    .frame(maxWidth: .infinity, maxHeight: .infinity)
            } else if viewModel.isAdmin {
                adminContent
            } else {
                // Unauthorized - show nothing useful
                VStack(spacing: 16) {
                    Image(systemName: "lock.shield.fill")
                        .font(.system(size: 64))
                        .foregroundColor(.secondary)
                    
                    Text("Access Denied")
                        .font(.naarsTitle2)
                    
                    Text("You don't have permission to access the admin panel.")
                        .font(.naarsBody)
                        .foregroundColor(.secondary)
                        .multilineTextAlignment(.center)
                        .padding(.horizontal)
                    
                    Button("Back to Profile") {
                        dismiss()
                    }
                    .buttonStyle(.borderedProminent)
                    .padding(.top)
                }
                .frame(maxWidth: .infinity, maxHeight: .infinity)
                .onAppear {
                    Log.security("Non-admin accessed admin panel view")
                }
            }
        }
        .navigationTitle("Admin Panel")
        .task {
            // Verify admin access when view first appears (only once due to hasVerified flag)
            await viewModel.verifyAdminAccess()
        }
    }
    
    @ViewBuilder
    private var adminContent: some View {
        ScrollView {
            VStack(spacing: 24) {
                // Stats Section
                statsSection
                
                // Quick Actions
                quickActionsSection
                
                // Navigation Links
                navigationSection
            }
            .padding()
        }
    }
    
    @ViewBuilder
    private var statsSection: some View {
        VStack(alignment: .leading, spacing: 12) {
            Text("Stats")
                .font(.naarsTitle3)
            
            HStack(spacing: 16) {
                StatCard(
                    title: "Pending",
                    value: "\(viewModel.pendingCount)",
                    icon: "clock.fill",
                    color: .naarsWarning
                )
                
                StatCard(
                    title: "Members",
                    value: "\(viewModel.totalMembers)",
                    icon: "person.3.fill",
                    color: .naarsPrimary
                )
                
                StatCard(
                    title: "Active",
                    value: "\(viewModel.activeMembers)",
                    icon: "checkmark.circle.fill",
                    color: .naarsSuccess
                )
            }
        }
    }
    
    @ViewBuilder
    private var quickActionsSection: some View {
        VStack(alignment: .leading, spacing: 12) {
            Text("Quick Actions")
                .font(.naarsTitle3)
            
            NavigationLink(destination: BroadcastView()) {
                HStack {
                    Image(systemName: "megaphone.fill")
                        .foregroundColor(.naarsPrimary)
                    Text("Send Announcement")
                    Spacer()
                    Image(systemName: "chevron.right")
                        .foregroundColor(.secondary)
                        .font(.caption)
                }
                .padding()
                .background(Color(.systemBackground))
                .cornerRadius(12)
                .overlay(
                    RoundedRectangle(cornerRadius: 12)
                        .stroke(Color(.separator), lineWidth: 1)
                )
            }
            
            NavigationLink(destination: AdminInviteView()) {
                HStack {
                    Image(systemName: "person.2.badge.plus")
                        .foregroundColor(.naarsPrimary)
                    Text("Generate Invite Code")
                    Spacer()
                    Image(systemName: "chevron.right")
                        .foregroundColor(.secondary)
                        .font(.caption)
                }
                .padding()
                .background(Color(.systemBackground))
                .cornerRadius(12)
                .overlay(
                    RoundedRectangle(cornerRadius: 12)
                        .stroke(Color(.separator), lineWidth: 1)
                )
            }
        }
    }
    
    @ViewBuilder
    private var navigationSection: some View {
        VStack(alignment: .leading, spacing: 12) {
            Text("Management")
                .font(.naarsTitle3)
            
            NavigationLink(destination: PendingUsersView()) {
                HStack {
                    Image(systemName: "clock.fill")
                        .foregroundColor(.naarsWarning)
                    Text("Pending Approvals")
                    if viewModel.pendingCount > 0 {
                        Spacer()
                        Text("\(viewModel.pendingCount)")
                            .font(.naarsCaption)
                            .foregroundColor(.white)
                            .padding(.horizontal, 8)
                            .padding(.vertical, 4)
                            .background(Color.naarsWarning)
                            .cornerRadius(12)
                    }
                    Spacer()
                    Image(systemName: "chevron.right")
                        .foregroundColor(.secondary)
                        .font(.caption)
                }
                .padding()
                .background(Color(.systemBackground))
                .cornerRadius(12)
                .overlay(
                    RoundedRectangle(cornerRadius: 12)
                        .stroke(Color(.separator), lineWidth: 1)
                )
            }
            
            NavigationLink(destination: UserManagementView()) {
                HStack {
                    Image(systemName: "person.3.fill")
                        .foregroundColor(.naarsPrimary)
                    Text("All Members")
                    Spacer()
                    Image(systemName: "chevron.right")
                        .foregroundColor(.secondary)
                        .font(.caption)
                }
                .padding()
                .background(Color(.systemBackground))
                .cornerRadius(12)
                .overlay(
                    RoundedRectangle(cornerRadius: 12)
                        .stroke(Color(.separator), lineWidth: 1)
                )
            }
        }
    }
}

/// Stat card component for dashboard
private struct StatCard: View {
    let title: String
    let value: String
    let icon: String
    let color: Color
    
    var body: some View {
        VStack(spacing: 8) {
            Image(systemName: icon)
                .font(.title2)
                .foregroundColor(color)
            
            Text(value)
                .font(.naarsTitle2)
                .fontWeight(.bold)
            
            Text(title)
                .font(.naarsCaption)
                .foregroundColor(.secondary)
        }
        .frame(maxWidth: .infinity)
        .padding()
        .background(Color(.systemBackground))
        .cornerRadius(12)
        .overlay(
            RoundedRectangle(cornerRadius: 12)
                .stroke(Color(.separator), lineWidth: 1)
        )
    }
}

#Preview {
    AdminPanelView()
}

