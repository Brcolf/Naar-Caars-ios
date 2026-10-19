//
//  AdminPanelView.swift
//  NaarsCars
//
//  Admin panel dashboard view
//

import SwiftUI

/// Admin panel dashboard view.
/// `.all` (every community) is for platform admins (is_admin = true); a community scope is for
/// that community's owners and admins, and for platform admins. The server decides every action.
struct AdminPanelView: View {
    @StateObject private var viewModel: AdminPanelViewModel
    @Environment(\.dismiss) private var dismiss
    @Environment(\.dynamicTypeSize) private var dynamicTypeSize
    @State private var showFulfilledOverlay = false
    @State private var showSavingsOverlay = false
    @State private var showActiveRidesOverlay = false
    @State private var showReports = false
    /// Set by Settings after an archive; the panel then closes itself when it is shown again.
    @State private var didArchiveCommunity = false
    private let autoOpenReports: Bool
    /// Receives "<name> was archived." for the presenter to show: the panel closes right after an
    /// archive, so a toast of its own would not be seen.
    private let onCommunityArchived: (_ confirmation: String) -> Void

    /// Shown in a stat tile until the figures have loaded, so a failed load does not read as 0
    private static let statPlaceholder = "—"

    init(
        scope: AdminPanelScope = .all,
        communityName: String? = nil,
        autoOpenReports: Bool = false,
        onCommunityArchived: @escaping (_ confirmation: String) -> Void = { _ in }
    ) {
        _viewModel = StateObject(wrappedValue: AdminPanelViewModel(initialScope: scope, communityName: communityName))
        self.autoOpenReports = autoOpenReports
        self.onCommunityArchived = onCommunityArchived
    }

    /// Previews and tests: a view model built on stand-in services.
    init(
        viewModel: @autoclosure @escaping () -> AdminPanelViewModel,
        autoOpenReports: Bool = false,
        onCommunityArchived: @escaping (_ confirmation: String) -> Void = { _ in }
    ) {
        _viewModel = StateObject(wrappedValue: viewModel())
        self.autoOpenReports = autoOpenReports
        self.onCommunityArchived = onCommunityArchived
    }

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
        .navigationTitle(viewModel.title)
        .communityTitleMenu(enabled: viewModel.menuEntries.count > 1) {
            ForEach(viewModel.menuEntries) { entry in
                let isCurrent = entry.scope == viewModel.scope
                Button {
                    Task { await viewModel.select(entry.scope) }
                } label: {
                    if isCurrent {
                        Label(entry.title, systemImage: "checkmark")
                    } else {
                        Text(entry.title)
                    }
                }
                .accessibilityAddTraits(isCurrent ? .isSelected : [])
            }
        }
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
        .onAppear {
            // Back from Settings after an archive: the community is gone, so is its panel.
            if didArchiveCommunity {
                dismiss()
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

            // Side by side at standard sizes; stacked at accessibility sizes so a title or a figure
            // is never broken inside a word or number.
            let statsLayout = dynamicTypeSize.isAccessibilitySize
                ? AnyLayout(VStackLayout(spacing: Constants.Spacing.ms))
                : AnyLayout(HStackLayout(spacing: Constants.Spacing.md))
            statsLayout {
                Button { showFulfilledOverlay = true } label: {
                    StatCard(
                        title: "admin_stat_fulfilled".localized,
                        value: viewModel.hasLoadedStats ? "\(viewModel.fulfilledCount)" : Self.statPlaceholder,
                        icon: "checkmark.circle.fill",
                        color: .naarsSuccess
                    )
                }
                .buttonStyle(.plain)

                Button { showSavingsOverlay = true } label: {
                    StatCard(
                        title: "admin_stat_savings".localized,
                        value: viewModel.hasLoadedStats ? viewModel.formattedSavings : Self.statPlaceholder,
                        icon: "dollarsign.circle.fill",
                        color: .naarsSuccess
                    )
                }
                .buttonStyle(.plain)

                Button { showActiveRidesOverlay = true } label: {
                    StatCard(
                        title: "admin_stat_active".localized,
                        value: viewModel.hasLoadedStats ? "\(viewModel.activeRidesCount)" : Self.statPlaceholder,
                        icon: "clock.fill",
                        color: .naarsWarning
                    )
                }
                .buttonStyle(.plain)
            }
        }
        .sheet(isPresented: $showFulfilledOverlay) {
            AdminFulfilledOverlay(communityId: viewModel.scope.communityId)
        }
        .sheet(isPresented: $showSavingsOverlay) {
            AdminSavingsOverlay(communityId: viewModel.scope.communityId)
        }
        .sheet(isPresented: $showActiveRidesOverlay) {
            AdminActiveRidesOverlay(communityId: viewModel.scope.communityId)
        }
    }
    
    @ViewBuilder
    private var quickActionsSection: some View {
        VStack(alignment: .leading, spacing: 12) {
            Text("admin_quick_actions".localized)
                .font(.naarsTitle3)

            // Both scopes: a community scope announces to that community, "All" to the default
            // community. Hidden until the target resolves (and when it could not be).
            if let target = viewModel.broadcastTarget {
            NavigationLink(destination: BroadcastView(communityId: target.communityId, communityName: target.communityName)) {
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
            }

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

            switch viewModel.scope {
            case .all:
                allCommunitiesRows
            case .community(let communityId):
                communityRows(communityId)
            }
        }
    }

    // MARK: - One community

    @ViewBuilder
    private func communityRows(_ communityId: UUID) -> some View {
        let name = viewModel.communityName
        let pending = viewModel.pendingCount ?? 0
        managementRow(
            title: "community_action_requests".localized,
            accessibilityTitle: pending > 0
                ? "\("community_action_requests".localized) (\(pending))"
                : "community_action_requests".localized,
            hint: "admin_pending_approvals_hint".localized,
            systemImage: "person.badge.clock",
            tint: .naarsWarning,
            badgeCount: pending,
            identifier: "admin.panel.requests"
        ) {
            PendingMembersView(target: .community(communityId, name: name))
        }

        managementRow(
            title: "admin_panel_members".localized,
            hint: "admin_panel_members_hint".localized,
            systemImage: "person.3.fill",
            tint: .naarsPrimary,
            identifier: "admin.panel.members"
        ) {
            CommunityMembersView(target: CommunityMembersTarget(communityId: communityId, communityName: name))
        }

        managementRow(
            title: "admin_reports_title".localized,
            hint: "admin_panel_reports_community_hint".localized,
            systemImage: "flag.fill",
            tint: .naarsError,
            identifier: "admin.panel.reports"
        ) {
            CommunityReportsView(communityId: communityId, communityName: name)
        }

        managementRow(
            title: "admin_panel_settings".localized,
            hint: "admin_panel_settings_hint".localized,
            systemImage: "gearshape.fill",
            tint: .naarsPrimary,
            identifier: "admin.panel.settings"
        ) {
            CommunitySettingsView(communityId: communityId, onArchived: { confirmation in
                didArchiveCommunity = true
                onCommunityArchived(confirmation)
            })
        }
    }

    /// A management row for the community scope; the `.all` rows keep their own markup.
    private func managementRow<Destination: View>(
        title: String,
        accessibilityTitle: String? = nil,
        hint: String,
        systemImage: String,
        tint: Color,
        badgeCount: Int = 0,
        identifier: String,
        @ViewBuilder destination: () -> Destination
    ) -> some View {
        NavigationLink(destination: destination()) {
            HStack {
                Image(systemName: systemImage)
                    .foregroundColor(tint)
                    .accessibilityHidden(true)
                Text(title)
                    .foregroundColor(.primary)
                Spacer()
                if badgeCount > 0 {
                    NotificationBadge(count: badgeCount)
                }
                Image(systemName: "chevron.right")
                    .foregroundColor(.secondary)
                    .font(.naarsCaption)
                    .accessibilityHidden(true)
            }
            .padding()
            .background(Color.naarsBackgroundSecondary)
            .cornerRadius(Constants.Radius.card)
            .overlay(
                RoundedRectangle(cornerRadius: Constants.Radius.card)
                    .stroke(Color(.separator), lineWidth: 1)
            )
        }
        .accessibilityIdentifier(identifier)
        .accessibilityLabel(accessibilityTitle ?? title)
        .accessibilityHint(hint)
    }

    // MARK: - Every community (platform admins)

    @ViewBuilder
    private var allCommunitiesRows: some View {
            NavigationLink(destination: PendingMembersView(target: .defaultCommunity)) {
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

            NavigationLink(destination: CommunitiesAdminView()) {
                HStack {
                    Image(systemName: "building.2.fill")
                        .foregroundColor(.naarsPrimary)
                    Text("admin_communities_title".localized)
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
            .accessibilityIdentifier("admin.communities")
            .accessibilityLabel("admin_communities_title".localized)
            .accessibilityHint("admin_communities_hint".localized)

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
                .lineLimit(1)
                .minimumScaleFactor(0.6)
            
            Text(title)
                .font(.naarsCaption)
                .foregroundColor(.secondary)
                .multilineTextAlignment(.center)
                .lineLimit(2)
                .minimumScaleFactor(0.8)
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

#if DEBUG
@MainActor
enum AdminPanelPreview {
    static let capitolHill = PreviewCommunityService.membership(name: "Capitol Hill Carpool", role: .admin, memberCount: 9)

    /// Seattle (member, default), Ballard (owner, two requests) and Capitol Hill (admin): two
    /// administered communities, so the title menu is enabled in both scopes.
    static func viewModel(platformAdmin: Bool, scope: AdminPanelScope) -> AdminPanelViewModel {
        let context = CommunityContext(
            service: PreviewCommunityService(),
            defaults: UserDefaults(suiteName: "preview")!,
            platformAdminProvider: { platformAdmin }
        )
        context.debugSetMemberships([
            PreviewCommunityService.sampleMemberships[0],
            PreviewCommunityService.sampleMemberships[1],
            capitolHill
        ])
        return AdminPanelViewModel(
            initialScope: scope,
            adminService: PreviewAdminService(),
            communityAdminService: PreviewCommunityService(),
            communityContext: context,
            verifyPlatformAdmin: {}
        )
    }

    static var ballardId: UUID { PreviewCommunityService.sampleMemberships[1].communityId }
}

#Preview {
    AdminPanelView()
}

#Preview("All communities") {
    NavigationStack {
        AdminPanelView(viewModel: AdminPanelPreview.viewModel(platformAdmin: true, scope: .all))
    }
}

#Preview("One community") {
    NavigationStack {
        AdminPanelView(viewModel: AdminPanelPreview.viewModel(platformAdmin: false, scope: .community(AdminPanelPreview.ballardId)))
    }
}
#endif

