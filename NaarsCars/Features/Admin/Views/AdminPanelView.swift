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
                ProgressView("admin_verifying_access".localized)
                    .frame(maxWidth: .infinity, maxHeight: .infinity)
            } else if viewModel.isAdmin {
                adminContent
            } else {
                // Unauthorized - show nothing useful
                VStack(spacing: 16) {
                    Image(systemName: "lock.shield.fill")
                        .font(.system(size: 64))
                        .foregroundColor(.secondary)
                    
                    Text("admin_access_denied".localized)
                        .font(.naarsTitle2)
                    
                    Text("admin_no_permission".localized)
                        .font(.naarsBody)
                        .foregroundColor(.secondary)
                        .multilineTextAlignment(.center)
                        .padding(.horizontal)
                    
                    Button("admin_back_to_profile".localized) {
                        dismiss()
                    }
                    .buttonStyle(.borderedProminent)
                    .padding(.top)
                    .accessibilityLabel("Back to profile")
                    .accessibilityHint("Double-tap to return to your profile")
                }
                .frame(maxWidth: .infinity, maxHeight: .infinity)
                .onAppear {
                    Log.security("Non-admin accessed admin panel view")
                }
            }
        }
        .navigationTitle("admin_panel_title".localized)
        .task {
            // Verify admin access when view first appears (only once due to hasVerified flag)
            await viewModel.verifyAdminAccess()
        }
        .trackScreen("AdminPanel")
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
                
                // Dev Tools (for testing)
                devToolsSection
            }
            .padding()
        }
    }
    
    @ViewBuilder
    private var statsSection: some View {
        VStack(alignment: .leading, spacing: 12) {
            Text("admin_stats".localized)
                .font(.naarsTitle3)
            
            HStack(spacing: 16) {
                StatCard(
                    title: "admin_stat_pending".localized,
                    value: "\(viewModel.pendingCount)",
                    icon: "clock.fill",
                    color: .naarsWarning
                )
                
                StatCard(
                    title: "admin_stat_members".localized,
                    value: "\(viewModel.totalMembers)",
                    icon: "person.3.fill",
                    color: .naarsPrimary
                )
                
                StatCard(
                    title: "admin_stat_active".localized,
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
            Text("admin_quick_actions".localized)
                .font(.naarsTitle3)
            
            NavigationLink(destination: BroadcastView()) {
                HStack {
                    Image(systemName: "megaphone.fill")
                        .foregroundColor(.naarsPrimary)
                    Text("admin_send_announcement".localized)
                    Spacer()
                    Image(systemName: "chevron.right")
                        .foregroundColor(.secondary)
                        .font(.naarsCaption)
                }
                .padding()
                .background(Color.naarsBackgroundSecondary)
                .cornerRadius(12)
                .overlay(
                    RoundedRectangle(cornerRadius: 12)
                        .stroke(Color(.separator), lineWidth: 1)
                )
            }
            .accessibilityIdentifier("admin.broadcast")
            .accessibilityLabel("Send announcement")
            .accessibilityHint("Double-tap to compose a broadcast announcement")
            
            NavigationLink(destination: AdminInviteView()) {
                HStack {
                    Image(systemName: "person.2.badge.plus")
                        .foregroundColor(.naarsPrimary)
                    Text("admin_generate_invite_code".localized)
                    Spacer()
                    Image(systemName: "chevron.right")
                        .foregroundColor(.secondary)
                        .font(.naarsCaption)
                }
                .padding()
                .background(Color.naarsBackgroundSecondary)
                .cornerRadius(12)
                .overlay(
                    RoundedRectangle(cornerRadius: 12)
                        .stroke(Color(.separator), lineWidth: 1)
                )
            }
            .accessibilityIdentifier("admin.inviteCodes")
            .accessibilityLabel("Generate invite code")
            .accessibilityHint("Double-tap to create a new invite code")
        }
    }
    
    @ViewBuilder
    private var navigationSection: some View {
        VStack(alignment: .leading, spacing: 12) {
            Text("admin_management".localized)
                .font(.naarsTitle3)
            
            NavigationLink(destination: PendingUsersView()) {
                HStack {
                    Image(systemName: "clock.fill")
                        .foregroundColor(.naarsWarning)
                    Text("admin_pending_approvals".localized)
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
                        .font(.naarsCaption)
                }
                .padding()
                .background(Color.naarsBackgroundSecondary)
                .cornerRadius(12)
                .overlay(
                    RoundedRectangle(cornerRadius: 12)
                        .stroke(Color(.separator), lineWidth: 1)
                )
            }
            .accessibilityIdentifier("admin.pendingUsers")
            .accessibilityLabel("Pending approvals\(viewModel.pendingCount > 0 ? ", \(viewModel.pendingCount) pending" : "")")
            .accessibilityHint("Double-tap to review pending user approvals")
            
            NavigationLink(destination: UserManagementView()) {
                HStack {
                    Image(systemName: "person.3.fill")
                        .foregroundColor(.naarsPrimary)
                    Text("admin_all_members".localized)
                    Spacer()
                    Image(systemName: "chevron.right")
                        .foregroundColor(.secondary)
                        .font(.naarsCaption)
                }
                .padding()
                .background(Color.naarsBackgroundSecondary)
                .cornerRadius(12)
                .overlay(
                    RoundedRectangle(cornerRadius: 12)
                        .stroke(Color(.separator), lineWidth: 1)
                )
            }
            .accessibilityIdentifier("admin.userManagement")
            .accessibilityLabel("All members")
            .accessibilityHint("Double-tap to manage community members")
        }
    }
    
    @ViewBuilder
    private var devToolsSection: some View {
        VStack(alignment: .leading, spacing: 12) {
            Text("admin_developer_tools".localized)
                .font(.naarsTitle3)
            
            NavigationLink(destination: DevNotificationTestView()) {
                HStack {
                    Image(systemName: "hammer.fill")
                        .foregroundColor(.orange)
                    Text("admin_notification_tester".localized)
                    Spacer()
                    Text("DEV")
                        .font(.naarsCaption)
                        .foregroundColor(.white)
                        .padding(.horizontal, 6)
                        .padding(.vertical, 2)
                        .background(Color.orange)
                        .cornerRadius(4)
                    Image(systemName: "chevron.right")
                        .foregroundColor(.secondary)
                        .font(.naarsCaption)
                }
                .padding()
                .background(Color.naarsBackgroundSecondary)
                .cornerRadius(12)
                .overlay(
                    RoundedRectangle(cornerRadius: 12)
                        .stroke(Color.orange.opacity(0.5), lineWidth: 1)
                )
            }
            .accessibilityLabel("Notification tester")
            .accessibilityHint("Double-tap to open the developer notification testing tool")
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
                .font(.naarsTitle2)
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
        .background(Color.naarsBackgroundSecondary)
        .cornerRadius(12)
        .overlay(
            RoundedRectangle(cornerRadius: 12)
                .stroke(Color(.separator), lineWidth: 1)
        )
        .accessibilityElement(children: .combine)
        .accessibilityLabel("\(title), \(value)")
    }
}

#Preview {
    AdminPanelView()
}

