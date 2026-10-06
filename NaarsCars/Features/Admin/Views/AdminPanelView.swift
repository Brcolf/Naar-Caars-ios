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
    @State private var showFulfilledOverlay = false
    @State private var showSavingsOverlay = false
    @State private var showActiveRidesOverlay = false
    @State private var showReports = false
    var autoOpenReports: Bool = false

    /// Shown in a stat tile until the figures have loaded, so a failed load does not read as 0
    private static let statPlaceholder = "—"

    var body: some View {
        Group {
            if viewModel.isVerifyingAdmin {
                ProgressView("admin_verifying_access".localized)
                    .frame(maxWidth: .infinity, maxHeight: .infinity)
            } else if viewModel.isAdmin {
                adminContent
            } else if let message = viewModel.verificationErrorMessage {
                // The check itself failed (offline, server error): offer a retry rather than
                // telling an admin they have no access.
                ErrorView(
                    error: message,
                    retryAction: {
                        Task { await viewModel.verifyAdminAccess() }
                    }
                )
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
                    .accessibilityLabel("admin_back_to_profile".localized)
                    .accessibilityHint("admin_back_to_profile_hint".localized)
                }
                .frame(maxWidth: .infinity, maxHeight: .infinity)
                .onAppear {
                    AppLogger.error("security", "Non-admin accessed admin panel view")
                }
            }
        }
        .navigationTitle("admin_panel_title".localized)
        .navigationDestination(isPresented: $showReports) {
            AdminReportsView()
        }
        .task {
            // Verify admin access when view first appears (only once due to hasVerified flag)
            await viewModel.verifyAdminAccess()
            if autoOpenReports {
                showReports = true
            }
        }
        .errorBanner(
            message: $viewModel.statsErrorMessage,
            retryAction: {
                Task { await viewModel.loadStats() }
            }
        )
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
                Button { showFulfilledOverlay = true } label: {
                    StatCard(
                        title: "Fulfilled",
                        value: viewModel.hasLoadedStats ? "\(viewModel.fulfilledCount)" : Self.statPlaceholder,
                        icon: "checkmark.circle.fill",
                        color: .naarsSuccess
                    )
                }
                .buttonStyle(.plain)

                Button { showSavingsOverlay = true } label: {
                    StatCard(
                        title: "Savings",
                        value: viewModel.hasLoadedStats ? viewModel.formattedSavings : Self.statPlaceholder,
                        icon: "dollarsign.circle.fill",
                        color: .naarsSuccess
                    )
                }
                .buttonStyle(.plain)

                Button { showActiveRidesOverlay = true } label: {
                    StatCard(
                        title: "Active",
                        value: viewModel.hasLoadedStats ? "\(viewModel.activeRidesCount)" : Self.statPlaceholder,
                        icon: "clock.fill",
                        color: .naarsWarning
                    )
                }
                .buttonStyle(.plain)
            }
        }
        .sheet(isPresented: $showFulfilledOverlay) {
            AdminFulfilledOverlay()
        }
        .sheet(isPresented: $showSavingsOverlay) {
            AdminSavingsOverlay()
        }
        .sheet(isPresented: $showActiveRidesOverlay) {
            AdminActiveRidesOverlay()
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
                        .foregroundColor(.primary)
                    Spacer()
                    Image(systemName: "chevron.right")
                        .foregroundColor(.secondary)
                        .font(.naarsCaption)
                }
                .padding()
                .background(Color.naarsBackgroundSecondary)
                .cornerRadius(Constants.Radius.card)
                .overlay(
                    RoundedRectangle(cornerRadius: Constants.Radius.card)
                        .stroke(Color(.separator), lineWidth: 1)
                )
            }
            .accessibilityIdentifier("admin.broadcast")
            .accessibilityLabel("admin_send_announcement".localized)
            .accessibilityHint("admin_send_announcement_hint".localized)
            
            Button(action: {
                let items: [Any] = [
                    "admin_share_message".localized,
                    URL(string: Constants.URLs.appStore)!
                ]
                let controller = UIActivityViewController(activityItems: items, applicationActivities: nil)
                if let windowScene = UIApplication.shared.connectedScenes.first as? UIWindowScene,
                   let root = windowScene.windows.first?.rootViewController {
                    root.present(controller, animated: true)
                }
            }) {
                HStack {
                    Image(systemName: "square.and.arrow.up")
                        .foregroundColor(.naarsPrimary)
                    Text("admin_share_app_link".localized)
                    Spacer()
                    Image(systemName: "chevron.right")
                        .foregroundColor(.secondary)
                        .font(.naarsCaption)
                }
                .padding()
                .background(Color.naarsBackgroundSecondary)
                .cornerRadius(Constants.Radius.card)
                .overlay(
                    RoundedRectangle(cornerRadius: Constants.Radius.card)
                        .stroke(Color(.separator), lineWidth: 1)
                )
            }
            .buttonStyle(PlainButtonStyle())
            .accessibilityIdentifier("admin.shareApp")
            .accessibilityLabel("admin_share_app_link_accessibility".localized)
            .accessibilityHint("admin_share_app_link_hint".localized)
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
                        .foregroundColor(.primary)
                    Spacer()
                    Image(systemName: "chevron.right")
                        .foregroundColor(.secondary)
                        .font(.naarsCaption)
                }
                .padding()
                .background(Color.naarsBackgroundSecondary)
                .cornerRadius(Constants.Radius.card)
                .overlay(
                    RoundedRectangle(cornerRadius: Constants.Radius.card)
                        .stroke(Color(.separator), lineWidth: 1)
                )
            }
            .accessibilityIdentifier("admin.pendingUsers")
            .accessibilityLabel("admin_pending_approvals".localized)
            .accessibilityHint("admin_pending_approvals_hint".localized)
            
            NavigationLink(destination: UserManagementView()) {
                HStack {
                    Image(systemName: "person.3.fill")
                        .foregroundColor(.naarsPrimary)
                    Text("admin_all_members".localized)
                        .foregroundColor(.primary)
                    Spacer()
                    Image(systemName: "chevron.right")
                        .foregroundColor(.secondary)
                        .font(.naarsCaption)
                }
                .padding()
                .background(Color.naarsBackgroundSecondary)
                .cornerRadius(Constants.Radius.card)
                .overlay(
                    RoundedRectangle(cornerRadius: Constants.Radius.card)
                        .stroke(Color(.separator), lineWidth: 1)
                )
            }
            .accessibilityIdentifier("admin.userManagement")
            .accessibilityLabel("admin_all_members".localized)
            .accessibilityHint("admin_all_members_hint".localized)

            NavigationLink(destination: AdminReportsView()) {
                HStack {
                    Image(systemName: "flag.fill")
                        .foregroundColor(.naarsError)
                    Text("admin_reports_title".localized)
                        .foregroundColor(.primary)
                    Spacer()
                    Image(systemName: "chevron.right")
                        .foregroundColor(.secondary)
                        .font(.naarsCaption)
                }
                .padding()
                .background(Color.naarsBackgroundSecondary)
                .cornerRadius(Constants.Radius.card)
                .overlay(
                    RoundedRectangle(cornerRadius: Constants.Radius.card)
                        .stroke(Color(.separator), lineWidth: 1)
                )
            }
            .accessibilityIdentifier("admin.reports")
            .accessibilityLabel("admin_reports_title".localized)
            .accessibilityHint("admin_reports_hint".localized)
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
        .cornerRadius(Constants.Radius.card)
        .overlay(
            RoundedRectangle(cornerRadius: Constants.Radius.card)
                .stroke(Color(.separator), lineWidth: 1)
        )
        .accessibilityElement(children: .combine)
        .accessibilityLabel("\(title), \(value)")
    }
}

#Preview {
    AdminPanelView()
}

