//
//  CommunitiesAdminView.swift
//  NaarsCars
//
//  Platform admins: every community, archive and restore, public or private, and owned-limit requests
//

import SwiftUI

/// Admin → Communities. No NavigationStack: always pushed from the Admin panel.
struct CommunitiesAdminView: View {
    /// An action that runs only after the admin confirms it.
    private struct PendingConfirmation: Identifiable {
        let action: CommunityAdminAction
        let community: PlatformCommunity
        var id: String { "\(action)-\(community.id)" }
    }

    @StateObject private var viewModel: CommunitiesAdminViewModel
    @State private var confirmation: PendingConfirmation?
    @State private var requestsTarget: PendingMembersTarget?

    @MainActor init(viewModel: @autoclosure @escaping @MainActor () -> CommunitiesAdminViewModel = CommunitiesAdminViewModel()) {
        _viewModel = StateObject(wrappedValue: viewModel())
    }

    var body: some View {
        Group {
            if viewModel.communities.isEmpty && viewModel.limitRequests.isEmpty {
                if let loadError = viewModel.loadError {
                    ErrorView(error: loadError) {
                        Task { await viewModel.load() }
                    }
                } else if !viewModel.hasLoaded {
                    skeleton
                } else {
                    EmptyStateView(
                        icon: "building.2",
                        title: "admin_communities_title".localized,
                        message: "admin_communities_empty".localized
                    )
                }
            } else {
                list
            }
        }
        .frame(maxWidth: .infinity, maxHeight: .infinity)
        .background(Color.naarsBackground)
        .navigationTitle("admin_communities_title".localized)
        .navigationBarTitleDisplayMode(.large)
        .navigationDestination(item: $requestsTarget) { target in
            PendingMembersView(target: target)
        }
        .task { await viewModel.load() }
        .alert(
            confirmationTitle,
            isPresented: Binding(get: { confirmation != nil }, set: { if !$0 { confirmation = nil } }),
            presenting: confirmation
        ) { pending in
            Button("common_cancel".localized, role: .cancel) {}
            Button(actionTitle(pending.action), role: .destructive) {
                let action = pending.action
                let community = pending.community
                Task { await viewModel.perform(action, on: community) }
            }
            .accessibilityIdentifier("admin.communities.confirm")
        } message: { pending in
            Text(confirmationBody(pending.action))
        }
        .toast(message: $viewModel.toastMessage)
        .errorBanner(message: $viewModel.actionErrorMessage)
    }

    // MARK: - List

    private var list: some View {
        ScrollView {
            LazyVStack(alignment: .leading, spacing: Constants.Spacing.md) {
                if !viewModel.limitRequests.isEmpty {
                    sectionHeader("admin_communities_limit_requests".localized)
                    ForEach(viewModel.limitRequests) { request in
                        limitRequestCard(request)
                    }
                    sectionHeader("admin_communities_title".localized)
                        .padding(.top, Constants.Spacing.sm)
                }
                ForEach(viewModel.communities) { community in
                    communityCard(community)
                }
            }
            .padding()
        }
        .refreshable { await viewModel.load() }
        .accessibilityIdentifier("admin.communities.list")
    }

    private func sectionHeader(_ title: String) -> some View {
        Text(title)
            .font(.naarsTitle3)
            .foregroundColor(.naarsTextPrimary)
            .accessibilityAddTraits(.isHeader)
    }

    // MARK: - Limit requests

    private func limitRequestCard(_ request: PlatformLimitRequest) -> some View {
        let isBusy = viewModel.busyId == request.id
        let isDisabled = viewModel.busyId != nil
        return VStack(alignment: .leading, spacing: Constants.Spacing.sm) {
            VStack(alignment: .leading, spacing: Constants.Spacing.xs) {
                Text(String(
                    format: "admin_communities_limit_row".localized,
                    request.userName ?? "—",
                    request.requestedMax,
                    request.currentMax,
                    request.ownedCount
                ))
                .font(.naarsHeadline)
                .foregroundColor(.naarsTextPrimary)
                .fixedSize(horizontal: false, vertical: true)
                Text(request.reason)
                    .font(.naarsSubheadline)
                    .foregroundColor(.naarsTextSecondary)
                    .fixedSize(horizontal: false, vertical: true)
            }
            .accessibilityElement(children: .combine)

            ViewThatFits(in: .horizontal) {
                HStack(spacing: Constants.Spacing.md) { limitButtons(request, isBusy: isBusy, isDisabled: isDisabled) }
                VStack(spacing: Constants.Spacing.sm) { limitButtons(request, isBusy: isBusy, isDisabled: isDisabled) }
            }
        }
        .frame(maxWidth: .infinity, alignment: .leading)
        .cardStyle()
        .accessibilityIdentifier("admin.communities.limitRequest")
    }

    @ViewBuilder
    private func limitButtons(_ request: PlatformLimitRequest, isBusy: Bool, isDisabled: Bool) -> some View {
        SecondaryButton(
            title: "admin_communities_decline".localized,
            action: { Task { await viewModel.decide(request, approve: false) } },
            isDisabled: isDisabled,
            isDestructive: true
        )
        .accessibilityIdentifier("admin.communities.limitDecline")
        PrimaryButton(
            title: "admin_communities_approve".localized,
            action: { Task { await viewModel.decide(request, approve: true) } },
            isLoading: isBusy,
            isDisabled: isDisabled
        )
        .accessibilityIdentifier("admin.communities.limitApprove")
    }

    // MARK: - Communities

    private func communityCard(_ community: PlatformCommunity) -> some View {
        let actions = CommunitiesAdminViewModel.actions(for: community)
        return HStack(alignment: .top, spacing: Constants.Spacing.md) {
            VStack(alignment: .leading, spacing: Constants.Spacing.xs) {
                Text(community.name)
                    .font(.naarsHeadline)
                    .foregroundColor(.naarsTextPrimary)
                    .lineLimit(3)
                ViewThatFits(in: .horizontal) {
                    HStack(spacing: Constants.Spacing.xs) { chips(community) }
                    VStack(alignment: .leading, spacing: Constants.Spacing.xs) { chips(community) }
                }
                Text(String(format: "admin_communities_members".localized, community.memberCount, community.pendingCount))
                    .font(.naarsFootnote)
                    .foregroundColor(.naarsTextSecondary)
                Text(String(
                    format: "admin_communities_created_by".localized,
                    community.creatorName ?? "—",
                    community.createdAt.formatted(date: .abbreviated, time: .omitted)
                ))
                .font(.naarsFootnote)
                .foregroundColor(.naarsTextSecondary)
                .fixedSize(horizontal: false, vertical: true)
            }
            .frame(maxWidth: .infinity, alignment: .leading)
            .accessibilityElement(children: .combine)

            if !actions.isEmpty {
                Menu {
                    menuItems(actions, for: community)
                } label: {
                    menuLabel(community)
                }
                .disabled(viewModel.busyId != nil)
                .accessibilityLabel(String(format: "community_actions_accessibility".localized, community.name))
                .accessibilityIdentifier("admin.communities.actions")
            }
        }
        .cardStyle()
        .accessibilityIdentifier("admin.communities.row")
    }

    @ViewBuilder
    private func chips(_ community: PlatformCommunity) -> some View {
        if community.isDefault {
            NaarsChip(text: "admin_communities_default_chip".localized, systemImage: "star.fill")
        }
        if community.isPublic {
            NaarsChip(text: "admin_communities_public_chip".localized, systemImage: "globe", tint: nil)
        }
        if community.archivedAt != nil {
            NaarsChip(text: "admin_communities_archived_chip".localized, systemImage: "archivebox", tint: nil)
        }
        if community.ownerCount == 0 {
            NaarsChip(text: "admin_communities_no_owner_chip".localized, systemImage: "person.crop.circle.badge.questionmark", tint: nil)
        }
        if community.openReportCount > 0 {
            NaarsChip(
                text: String(format: "admin_communities_reported_chip".localized, community.openReportCount),
                systemImage: "flag.fill",
                tint: .naarsWarning
            )
        }
    }

    @ViewBuilder
    private func menuItems(_ actions: [CommunityAdminAction], for community: PlatformCommunity) -> some View {
        ForEach(actions, id: \.self) { action in
            switch action {
            case .requestsToJoin:
                Button {
                    requestsTarget = .community(community.id, name: community.name)
                } label: {
                    Label(
                        "\("admin_communities_requests".localized) (\(community.pendingCount))",
                        systemImage: "person.badge.clock"
                    )
                }
            case .archive, .makePrivate:
                // Both reach every member or every guest at once: always confirmed first.
                Button(role: action == .archive ? .destructive : nil) {
                    confirmation = PendingConfirmation(action: action, community: community)
                } label: {
                    Label(actionTitle(action), systemImage: systemImage(action))
                }
            case .restore, .makePublic:
                Button {
                    Task { await viewModel.perform(action, on: community) }
                } label: {
                    Label(actionTitle(action), systemImage: systemImage(action))
                }
            }
        }
    }

    @ViewBuilder
    private func menuLabel(_ community: PlatformCommunity) -> some View {
        if viewModel.busyId == community.id {
            ProgressView()
                .frame(minWidth: 44, minHeight: 44)
        } else {
            Image(systemName: "ellipsis.circle")
                .font(.naarsTitle3)
                .foregroundColor(.naarsPrimary)
                .frame(minWidth: 44, minHeight: 44)
        }
    }

    private var skeleton: some View {
        ScrollView {
            VStack(spacing: Constants.Spacing.md) {
                ForEach(0..<3, id: \.self) { _ in
                    VStack(alignment: .leading, spacing: Constants.Spacing.sm) {
                        SkeletonRectangle(width: 180, height: 16)
                        SkeletonRectangle(width: 120, height: 20, cornerRadius: Constants.Radius.button)
                        SkeletonRectangle(width: 150, height: 12)
                    }
                    .frame(maxWidth: .infinity, alignment: .leading)
                    .cardStyle()
                }
            }
            .padding()
        }
        .disabled(true)
        .accessibilityHidden(true)
    }

    // MARK: - Copy

    private func actionTitle(_ action: CommunityAdminAction) -> String {
        switch action {
        case .requestsToJoin: return "admin_communities_requests".localized
        case .archive: return "admin_communities_archive".localized
        case .restore: return "admin_communities_restore".localized
        case .makePrivate: return "admin_communities_make_private".localized
        case .makePublic: return "admin_communities_make_public".localized
        }
    }

    private func systemImage(_ action: CommunityAdminAction) -> String {
        switch action {
        case .requestsToJoin: return "person.badge.clock"
        case .archive: return "archivebox"
        case .restore: return "arrow.uturn.backward"
        case .makePrivate: return "lock"
        case .makePublic: return "globe"
        }
    }

    private var confirmationTitle: String {
        guard let confirmation else { return "" }
        let key = confirmation.action == .archive ? "admin_communities_archive_title" : "admin_communities_make_private_title"
        return String(format: key.localized, confirmation.community.name)
    }

    private func confirmationBody(_ action: CommunityAdminAction) -> String {
        action == .archive
            ? "admin_communities_archive_body".localized
            : "admin_communities_make_private_body".localized
    }
}

#if DEBUG
#Preview("List with a limit request") {
    NavigationStack {
        CommunitiesAdminView(viewModel: CommunitiesAdminViewModel(adminService: PreviewCommunityService()))
    }
}

#Preview("Empty") {
    let service = PreviewCommunityService()
    service.platformCommunities = PlatformCommunities(communities: [], limitRequests: [])
    return NavigationStack {
        CommunitiesAdminView(viewModel: CommunitiesAdminViewModel(adminService: service))
    }
}
#endif
