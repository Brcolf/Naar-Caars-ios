//
//  MyCommunitiesView.swift
//  NaarsCars
//
//  The member's communities: invite, requests to join, mute, report, leave, create and join
//

import SwiftUI
import SwiftData

/// My communities. No NavigationStack: always pushed from Profile.
struct MyCommunitiesView: View {
    private enum ActiveSheet: Identifiable {
        case invite(CommunityMembership)
        case report(CommunityMembership)
        case leave(CommunityMembership, LeavePlan)
        case create
        case join
        case limitRequest(currentMax: Int)

        var id: String {
            switch self {
            case .invite(let m): return "invite-\(m.communityId)"
            case .report(let m): return "report-\(m.communityId)"
            case .leave(let m, _): return "leave-\(m.communityId)"
            case .create: return "create"
            case .join: return "join"
            case .limitRequest: return "limit-request"
            }
        }
    }

    @Environment(\.modelContext) private var modelContext
    @StateObject private var viewModel: MyCommunitiesViewModel
    @State private var activeSheet: ActiveSheet?
    @State private var pendingTarget: PendingMembersTarget?
    /// Recorded by Create and Join; acted on in the sheet's `onDismiss`.
    @State private var createdCommunityId: UUID?
    @State private var joinResult: JoinResult?
    @State private var reopenLimitRequest = false
    @State private var limitRequestSent = false
    /// The code the Join sheet opens with (a saved invite code), nil for a plain Join.
    @State private var joinPrefilledCode: String?
    /// The invite code saved on Welcome before sign-in; re-read in `.task` and after every sheet.
    @State private var storedInviteCode: String? = PendingInviteStore().peek()
    /// A saved code opens the Join sheet by itself once per view lifetime.
    @State private var didAutoOpenStoredCode = false

    @MainActor init(viewModel: @autoclosure @escaping @MainActor () -> MyCommunitiesViewModel = MyCommunitiesViewModel()) {
        _viewModel = StateObject(wrappedValue: viewModel())
    }

    var body: some View {
        List {
            if viewModel.active.isEmpty && viewModel.pending.isEmpty && !viewModel.hasLoadedMemberships {
                skeletonSection
            }

            if !viewModel.active.isEmpty {
                Section {
                    ForEach(viewModel.active) { membership in
                        activeRow(membership)
                        if viewModel.isAdmin(of: membership.communityId), let count = membership.pendingCount, count > 0 {
                            requestsLink(membership, count: count)
                        }
                    }
                } header: {
                    Text("community_section_yours".localized)
                }
            }

            if !viewModel.pending.isEmpty {
                Section {
                    ForEach(viewModel.pending) { membership in
                        pendingRow(membership)
                    }
                } header: {
                    Text("community_section_waiting".localized)
                }
            }

            if let offer = viewModel.limitOffer {
                limitSection(offer)
            }

            Section {
                if let code = storedInviteCode {
                    storedInviteRow(code)
                }

                Button {
                    activeSheet = .create
                } label: {
                    Label("community_action_create".localized, systemImage: "plus.circle")
                }
                .accessibilityIdentifier("community.my.create")

                Button {
                    joinPrefilledCode = nil
                    activeSheet = .join
                } label: {
                    Label("community_action_join".localized, systemImage: "person.badge.plus")
                }
                .accessibilityIdentifier("community.my.join")
            }
        }
        .listStyle(.insetGrouped)
        .scrollContentBackground(.hidden)
        .background(Color.naarsBackground)
        .navigationTitle("community_my_title".localized)
        .navigationBarTitleDisplayMode(.large)
        .navigationDestination(for: PendingMembersTarget.self) { target in
            PendingMembersView(target: target)
        }
        .navigationDestination(item: $pendingTarget) { target in
            PendingMembersView(target: target)
        }
        .task {
            viewModel.setup(modelContext: modelContext)
            storedInviteCode = PendingInviteStore().peek()
            if !didAutoOpenStoredCode, let code = storedInviteCode, activeSheet == nil {
                didAutoOpenStoredCode = true
                openJoin(with: code)
            }
            await viewModel.load()
        }
        .refreshable { await viewModel.load() }
        .sheet(item: $activeSheet, onDismiss: sheetDismissed) { sheet in
            sheetContent(sheet)
        }
        .toast(message: $viewModel.toastMessage)
        .errorBanner(message: $viewModel.errorMessage)
    }

    // MARK: - Saved invite code

    /// A saved code whose sheet was dismissed, or never shown, stays reachable here until it is
    /// redeemed or removed.
    private func storedInviteRow(_ code: String) -> some View {
        VStack(alignment: .leading, spacing: Constants.Spacing.sm) {
            Label("community_invite_saved_row".localized, systemImage: "envelope.open.fill")
                .font(.naarsSubheadline)
                .foregroundColor(.naarsTextPrimary)
            HStack(spacing: Constants.Spacing.md) {
                Button {
                    openJoin(with: code)
                } label: {
                    Text("community_invite_use".localized)
                        .font(.naarsSubheadline.weight(.semibold))
                        .foregroundColor(.naarsPrimary)
                        .frame(minHeight: 44)
                }
                .buttonStyle(.borderless)
                .accessibilityLabel("community_invite_use".localized)
                .accessibilityIdentifier("community.my.inviteCode.use")

                Spacer(minLength: 0)

                Button {
                    PendingInviteStore().clear()
                    storedInviteCode = nil
                } label: {
                    Text("community_invite_remove".localized)
                        .font(.naarsSubheadline)
                        .foregroundColor(.naarsTextSecondary)
                        .frame(minHeight: 44)
                }
                .buttonStyle(.borderless)
                .accessibilityLabel("community_invite_remove".localized)
                .accessibilityIdentifier("community.my.inviteCode.remove")
            }
        }
        .padding(.vertical, Constants.Spacing.xs)
    }

    private func openJoin(with code: String) {
        joinPrefilledCode = code
        activeSheet = .join
    }

    // MARK: - Limit

    @ViewBuilder
    private func limitSection(_ offer: LimitOffer) -> some View {
        Section {
            switch offer {
            case .requestPending(let requestedMax):
                Label(
                    String(format: "community_limit_request_pending".localized, requestedMax),
                    systemImage: "clock"
                )
                .font(.naarsSubheadline)
                .foregroundColor(.naarsTextSecondary)
                .accessibilityIdentifier("community.my.limitPending")
            case .canRequest(let currentMax, let ownedCount):
                Text(String(format: "community_limit_offer".localized, ownedCount))
                    .font(.naarsSubheadline)
                    .foregroundColor(.naarsTextSecondary)
                Button {
                    activeSheet = .limitRequest(currentMax: currentMax)
                } label: {
                    Label("community_limit_request_button".localized, systemImage: "arrow.up.circle")
                }
                .accessibilityIdentifier("community.my.limitRequest")
            }
        }
    }

    // MARK: - Rows

    private func activeRow(_ membership: CommunityMembership) -> some View {
        HStack(alignment: .top, spacing: Constants.Spacing.md) {
            VStack(alignment: .leading, spacing: Constants.Spacing.xs) {
                Text(membership.name)
                    .font(.naarsHeadline)
                    .foregroundColor(.naarsTextPrimary)
                    .lineLimit(3)
                HStack(spacing: Constants.Spacing.xs) {
                    NaarsChip(text: roleText(membership.role), tint: membership.role == .member ? nil : .naarsPrimary)
                    if viewModel.isMuted(membership) {
                        NaarsChip(text: "community_muted_chip".localized, systemImage: "bell.slash.fill", tint: nil)
                    }
                }
                Text(memberCountText(membership.memberCount))
                    .font(.naarsFootnote)
                    .foregroundColor(.naarsTextSecondary)
            }
            .frame(maxWidth: .infinity, alignment: .leading)
            .accessibilityElement(children: .combine)

            Menu {
                activeMenu(membership)
            } label: {
                menuLabel(membership)
            }
            .disabled(viewModel.busyCommunityId != nil)
            .accessibilityLabel(String(format: "community_actions_accessibility".localized, membership.name))
            .accessibilityIdentifier("community.my.actions")
        }
        .padding(.vertical, Constants.Spacing.xs)
    }

    @ViewBuilder
    private func activeMenu(_ membership: CommunityMembership) -> some View {
        let isAdmin = viewModel.isAdmin(of: membership.communityId)
        if membership.canInvite {
            Button {
                activeSheet = .invite(membership)
            } label: {
                Label("community_action_invite".localized, systemImage: "person.crop.circle.badge.plus")
            }
        }
        if isAdmin {
            Button {
                pendingTarget = .community(membership.communityId, name: membership.name)
            } label: {
                Label(requestsTitle(count: membership.pendingCount ?? 0), systemImage: "person.badge.clock")
            }
        }
        let muted = viewModel.isMuted(membership)
        Button {
            Task { await viewModel.setMuted(!muted, for: membership) }
        } label: {
            Label(
                muted ? "community_action_unmute".localized : "community_action_mute".localized,
                systemImage: muted ? "bell.fill" : "bell.slash"
            )
        }
        Button {
            activeSheet = .report(membership)
        } label: {
            Label("community_action_report".localized, systemImage: "exclamationmark.bubble")
        }
        Button(role: .destructive) {
            activeSheet = .leave(membership, viewModel.leavePlan(for: membership))
        } label: {
            Label("community_action_leave".localized, systemImage: "rectangle.portrait.and.arrow.right")
        }
    }

    private func requestsLink(_ membership: CommunityMembership, count: Int) -> some View {
        NavigationLink(value: PendingMembersTarget.community(membership.communityId, name: membership.name)) {
            HStack(spacing: Constants.Spacing.sm) {
                Label("community_action_requests".localized, systemImage: "person.badge.clock")
                    .font(.naarsSubheadline)
                    .foregroundColor(.naarsTextPrimary)
                Spacer(minLength: 0)
                NotificationBadge(count: count)
            }
        }
        .accessibilityLabel(requestsTitle(count: count))
        .accessibilityIdentifier("community.my.requests")
    }

    private func pendingRow(_ membership: CommunityMembership) -> some View {
        HStack(alignment: .top, spacing: Constants.Spacing.md) {
            VStack(alignment: .leading, spacing: Constants.Spacing.xs) {
                Text(membership.name)
                    .font(.naarsHeadline)
                    .foregroundColor(.naarsTextPrimary)
                    .lineLimit(3)
                NaarsChip(text: "community_status_pending".localized, systemImage: "clock", tint: .naarsWarning)
            }
            .frame(maxWidth: .infinity, alignment: .leading)
            .accessibilityElement(children: .combine)

            Menu {
                Button {
                    activeSheet = .report(membership)
                } label: {
                    Label("community_action_report".localized, systemImage: "exclamationmark.bubble")
                }
                Button(role: .destructive) {
                    activeSheet = .leave(membership, viewModel.leavePlan(for: membership))
                } label: {
                    Label("community_action_withdraw".localized, systemImage: "xmark.circle")
                }
            } label: {
                menuLabel(membership)
            }
            .disabled(viewModel.busyCommunityId != nil)
            .accessibilityLabel(String(format: "community_actions_accessibility".localized, membership.name))
            .accessibilityIdentifier("community.my.pendingActions")
        }
        .padding(.vertical, Constants.Spacing.xs)
    }

    @ViewBuilder
    private func menuLabel(_ membership: CommunityMembership) -> some View {
        if viewModel.busyCommunityId == membership.communityId {
            ProgressView()
                .frame(minWidth: 44, minHeight: 44)
        } else {
            Image(systemName: "ellipsis.circle")
                .font(.naarsTitle3)
                .foregroundColor(.naarsPrimary)
                .frame(minWidth: 44, minHeight: 44)
        }
    }

    private var skeletonSection: some View {
        Section {
            ForEach(0..<2, id: \.self) { _ in
                VStack(alignment: .leading, spacing: Constants.Spacing.sm) {
                    SkeletonRectangle(width: 180, height: 16)
                    SkeletonRectangle(width: 80, height: 12)
                }
                .padding(.vertical, Constants.Spacing.xs)
            }
        }
        .accessibilityHidden(true)
    }

    // MARK: - Sheets

    @ViewBuilder
    private func sheetContent(_ sheet: ActiveSheet) -> some View {
        switch sheet {
        case .invite(let membership):
            CommunityInviteSheet(
                communityId: membership.communityId,
                communityName: membership.name,
                isAdmin: viewModel.isAdmin(of: membership.communityId),
                onDone: { activeSheet = nil }
            )
        case .report(let membership):
            ReportContentSheet(context: .community(id: membership.communityId, code: nil, name: membership.name))
        case .leave(let membership, let plan):
            LeaveCommunitySheet(
                membership: membership,
                plan: plan,
                isOnlyActiveCommunity: membership.status == .active && viewModel.active.count == 1,
                onConfirm: {
                    let target = membership
                    activeSheet = nil
                    Task { await viewModel.leave(target) }
                }
            )
        case .create:
            CreateCommunityView(
                onCreated: { createdCommunityId = $0 },
                onRequestHigherLimit: {
                    // Swap sheets once Create is gone.
                    activeSheet = nil
                    reopenLimitRequest = true
                }
            )
        case .limitRequest(let currentMax):
            OwnedLimitRequestSheet(currentMax: currentMax, onSent: {
                limitRequestSent = true
            })
        case .join:
            NavigationStack {
                ScrollView {
                    CommunityJoinOptionsView(
                        excludedCommunityIds: viewModel.allMembershipIds,
                        prefilledCode: joinPrefilledCode,
                        onJoined: { result in
                            joinResult = result
                            activeSheet = nil
                        }
                    )
                    .padding()
                }
                .background(Color.naarsBackground)
                .navigationTitle("community_action_join".localized)
                .navigationBarTitleDisplayMode(.inline)
                .toolbar {
                    ToolbarItem(placement: .cancellationAction) {
                        Button("common_cancel".localized) { activeSheet = nil }
                            .accessibilityIdentifier("community.my.join.cancel")
                    }
                }
            }
        }
    }

    /// Create and Join record their result; the follow-up runs once the sheet is gone, so nothing
    /// reloads underneath a sheet that is still on screen.
    private func sheetDismissed() {
        // A redemption (or a dead code) clears the store; a cancel keeps it.
        storedInviteCode = PendingInviteStore().peek()
        if limitRequestSent {
            limitRequestSent = false
            viewModel.toastMessage = "community_limit_request_sent".localized
            Task { await viewModel.load() }
        }
        if reopenLimitRequest {
            reopenLimitRequest = false
            if let limits = viewModel.limits, OwnedLimitRequestViewModel.canRequestMore(currentMax: limits.maxOwned) {
                activeSheet = .limitRequest(currentMax: limits.maxOwned)
            }
        }
        if let communityId = createdCommunityId {
            createdCommunityId = nil
            Task { await viewModel.didCreate(communityId) }
        }
        if let result = joinResult {
            joinResult = nil
            Task { await viewModel.didJoin(result) }
        }
    }

    // MARK: - Copy

    private func roleText(_ role: CommunityRole) -> String {
        switch role {
        case .owner: return "community_role_owner".localized
        case .admin: return "community_role_admin".localized
        case .member: return "community_role_member".localized
        }
    }

    private func memberCountText(_ count: Int) -> String {
        String(format: (count == 1 ? "community_member_count_one" : "community_member_count_other").localized, count)
    }

    private func requestsTitle(count: Int) -> String {
        let title = "community_action_requests".localized
        return count > 0 ? "\(title) (\(count))" : title
    }
}

#if DEBUG
#Preview("One membership") {
    let service = PreviewCommunityService()
    service.memberships = [PreviewCommunityService.sampleMemberships[0]]
    let context = CommunityContext(service: service, defaults: UserDefaults(suiteName: "preview")!)
    context.debugSetMemberships(service.memberships)
    return NavigationStack {
        MyCommunitiesView(viewModel: MyCommunitiesViewModel(service: service, communityContext: context, refreshDashboard: { _ in }))
    }
}

#Preview("Limit reached") {
    let service = PreviewCommunityService()
    service.limits = CommunityLimits(maxOwned: 3, ownedCount: 3, nextCreateAt: nil, canCreate: false, latestRequest: nil)
    let context = CommunityContext(service: service, defaults: UserDefaults(suiteName: "preview")!)
    context.debugSetMemberships(PreviewCommunityService.sampleMemberships)
    return NavigationStack {
        MyCommunitiesView(viewModel: MyCommunitiesViewModel(service: service, communityContext: context, refreshDashboard: { _ in }))
    }
}

#Preview("Limit request pending") {
    let service = PreviewCommunityService()
    service.limits = CommunityLimits(
        maxOwned: 3, ownedCount: 3, nextCreateAt: nil, canCreate: false,
        latestRequest: CommunityLimitRequest(
            requestId: UUID(), requestedMax: 5, reason: "Three groups", status: .pending,
            createdAt: Date(), decidedAt: nil
        )
    )
    let context = CommunityContext(service: service, defaults: UserDefaults(suiteName: "preview")!)
    context.debugSetMemberships(PreviewCommunityService.sampleMemberships)
    return NavigationStack {
        MyCommunitiesView(viewModel: MyCommunitiesViewModel(service: service, communityContext: context, refreshDashboard: { _ in }))
    }
}

#Preview("Owner with requests and a pending row") {
    let service = PreviewCommunityService()
    let context = CommunityContext(service: service, defaults: UserDefaults(suiteName: "preview")!)
    context.debugSetMemberships(PreviewCommunityService.sampleMemberships)
    return NavigationStack {
        MyCommunitiesView(viewModel: MyCommunitiesViewModel(service: service, communityContext: context, refreshDashboard: { _ in }))
    }
}
#endif
