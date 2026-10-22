//
//  MyCommunitiesView.swift
//  NaarsCars
//
//  Explore's content: your communities, the listed communities, an invite code and Start a community
//

import SwiftUI
import SwiftData

/// The root of the Explore tab, for members and guests alike. No NavigationStack: `ExploreView`
/// supplies it. A community row opens its page (`CommunityPageView`), which owns invite, mute,
/// leave and Manage; the rows of the waiting section keep their own menu.
struct MyCommunitiesView: View {
    /// Where a pending intent opens on Explore. `.root` is this screen with nothing pushed on top.
    enum ExploreRoute: Equatable {
        case root
        case pendingMembers(PendingMembersTarget)
        case communityReports(UUID)
        case communityMembers(UUID)
    }

    private enum ActiveSheet: Identifiable {
        case report(CommunityMembership)
        case leave(CommunityMembership, LeavePlan)
        case create
        case join
        case limitRequest(currentMax: Int)
        case guestPrompt(GuestRestrictionReason)

        var id: String {
            switch self {
            case .report(let m): return "report-\(m.communityId)"
            case .leave(let m, _): return "leave-\(m.communityId)"
            case .create: return "create"
            case .join: return "join"
            case .limitRequest: return "limit-request"
            case .guestPrompt(let reason): return "guest-\(reason.id)"
            }
        }
    }

    @Environment(\.modelContext) private var modelContext
    @Environment(AppState.self) private var appState
    @Environment(\.dynamicTypeSize) private var dynamicTypeSize
    /// The monogram circle of a row: this size at the default text size, growing with Dynamic Type
    /// up to `maxMonogramSize`, so the initials stay inside the circle and the name keeps its room.
    private static let baseMonogramSize: CGFloat = 40
    private static let maxMonogramSize: CGFloat = 64
    @ScaledMetric(relativeTo: .headline) private var scaledMonogramSize: CGFloat = MyCommunitiesView.baseMonogramSize
    @StateObject private var viewModel: MyCommunitiesViewModel
    @State private var activeSheet: ActiveSheet?
    @State private var navigationCoordinator = NavigationCoordinator.shared
    @State private var pendingTarget: PendingMembersTarget?
    /// A community's reports opened from a `.communityReports` intent (`content_reported`).
    @State private var reportsTarget: UUID?
    /// The Members screen opened from a `.communityMembers` intent (`membership_update`: made an owner).
    @State private var membersTarget: CommunityMembersTarget?
    /// The community whose page is open.
    @State private var communityPageTarget: UUID?
    /// Recorded by Create and Join; acted on in the sheet's `onDismiss`.
    @State private var createdCommunityId: UUID?
    @State private var joinResult: JoinResult?
    @State private var reopenLimitRequest = false
    @State private var limitRequestSent = false
    /// The code the Join sheet opens with (a saved invite code), nil for a plain Join.
    @State private var joinPrefilledCode: String?
    /// The invite code saved on Welcome before sign-in; re-read in `.task` and after every sheet.
    @State private var storedInviteCode: String? = PendingInviteStore().peek()
    /// Whether a saved code may open the Join sheet by itself has been decided: once per view
    /// lifetime, on the first `.task`. A code saved later is decided by the store-change rule
    /// instead, so this is also set on every store change.
    @State private var didAutoOpenStoredCode = false
    /// False while a screen is pushed on top (a community page, Members, Reports, Requests to
    /// join), while another tab is selected, or once this one is popped, so a hidden copy never
    /// presents the Join sheet on a store change.
    @State private var isVisible = false
    /// True while one of this screen's destinations is pushed on top of it: set by the destination's
    /// `onAppear`, cleared by this screen's `onAppear`. A tab switch does not change it.
    @State private var screenPushedOnTop = false
    /// A code saved while this screen was hidden only by a tab switch (nothing pushed on top): the
    /// Join sheet opens on the next appearance, which the link's own route brings about.
    @State private var openJoinOnNextAppear = false
    /// The pending intent present when this view first appeared is opened once per view lifetime.
    @State private var didReplayInitialIntent = false
    /// The banner over kept listed rows was closed; shown again by the next load.
    @State private var listedBannerDismissed = false

    @MainActor init(viewModel: @autoclosure @escaping @MainActor () -> MyCommunitiesViewModel = MyCommunitiesViewModel()) {
        _viewModel = StateObject(wrappedValue: viewModel())
    }

    var body: some View {
        List {
            // A guest has no memberships to wait for, so no skeleton.
            if !viewModel.isGuest && viewModel.active.isEmpty && viewModel.pending.isEmpty && !viewModel.hasLoadedMemberships {
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
                inviteCodeRow
                startCommunityRow
            }

            listedSection
        }
        .listStyle(.insetGrouped)
        .scrollContentBackground(.hidden)
        .background(Color.naarsBackground)
        .navigationTitle("explore_title".localized)
        .navigationBarTitleDisplayMode(.large)
        .navigationDestination(item: $pendingTarget) { target in
            PendingMembersView(target: target)
                // The identity rule of Members below: a push for another community while this
                // screen is open needs a fresh view model; the same community keeps the screen.
                .id(target.communityId)
                .onAppear { screenPushedOnTop = true }
        }
        .navigationDestination(item: $membersTarget) { target in
            CommunityMembersView(target: target)
                // A push for another community while Members is open changes the item in place:
                // without a new identity the pushed screen keeps its first view model (its
                // @StateObject) and shows the first community. The same community keeps the screen.
                .id(target.communityId)
                .onAppear { screenPushedOnTop = true }
        }
        .navigationDestination(item: $reportsTarget) { communityId in
            CommunityReportsView(communityId: communityId, communityName: CommunityContext.shared.name(for: communityId))
                // The same identity rule as Members.
                .id(communityId)
                .onAppear { screenPushedOnTop = true }
        }
        .navigationDestination(item: $communityPageTarget) { communityId in
            // The same identity rule as Members: another community in place needs a fresh view model.
            CommunityPageView(communityId: communityId)
                .id(communityId)
                .onAppear { screenPushedOnTop = true }
        }
        .task {
            viewModel.setup(modelContext: modelContext)
            storedInviteCode = PendingInviteStore().peek()
            if let code = Self.joinCodeToOpenOnAppear(
                storedCode: storedInviteCode,
                isGuest: viewModel.isGuest,
                hasSheet: activeSheet != nil,
                hasScreenOnTop: hasScreenOnTop,
                pendingIntent: navigationCoordinator.pendingIntent,
                alreadyDecided: didAutoOpenStoredCode
            ) {
                openJoin(with: code)
            }
            didAutoOpenStoredCode = true
            await viewModel.loadIfStale()
        }
        .onAppear {
            isVisible = true
            screenPushedOnTop = false
            // A link that arrived while another tab was selected: its route brings this screen back.
            if openJoinOnNextAppear {
                openJoinOnNextAppear = false
                storedInviteCode = PendingInviteStore().peek()
                if let code = Self.joinCodeToOpenOnStoreChange(
                    storedCode: storedInviteCode,
                    hasSheet: activeSheet != nil,
                    isVisible: true,
                    isGuest: viewModel.isGuest
                ) {
                    openJoin(with: code)
                }
            }
        }
        .onDisappear { isVisible = false }
        // initial: true also opens a route whose intent was set before this view existed (the
        // Explore tab's first appearance after a push or a link); onChange alone never fires for a
        // value that is already there. The replay rule is RequestsDashboardView's.
        .onChange(of: navigationCoordinator.pendingIntent, initial: true) { oldIntent, intent in
            // Old and new are the same value only on the pass that initial: true adds. That pass
            // comes round again on every appearance; it is honoured once per view lifetime.
            let isInitialPass = oldIntent == intent
            if isInitialPass {
                guard !didReplayInitialIntent else { return }
                didReplayInitialIntent = true
            }
            guard let intent else { return }
            if isInitialPass {
                // One main-actor turn later: a push requested in the same update as the stack's
                // first render can be dropped. Skipped if the intent was consumed or replaced
                // meanwhile, so it is never applied twice.
                Task { @MainActor in
                    guard navigationCoordinator.pendingIntent == intent else { return }
                    openExploreRoute(from: intent)
                }
                return
            }
            openExploreRoute(from: intent)
        }
        // A join link opened while this screen exists. Visible with no sheet: Join opens now. Hidden
        // by a tab switch: Join opens on the next appearance. With a sheet up or a screen pushed on
        // top the code only refreshes the saved-code row, whose Use button stays the way in. A guest
        // never gets Join by itself: Use shows the sign-in prompt.
        .onReceive(NotificationCenter.default.publisher(for: PendingInviteStore.didChange)) { _ in
            storedInviteCode = PendingInviteStore().peek()
            // The store-change rule owns this code; the `.task` re-run on the next appearance must not
            // open it as well (it would open Join after back from a pushed screen).
            didAutoOpenStoredCode = true
            if let code = Self.joinCodeToOpenOnStoreChange(
                storedCode: storedInviteCode,
                hasSheet: activeSheet != nil,
                isVisible: isVisible,
                isGuest: viewModel.isGuest
            ) {
                openJoinOnNextAppear = false
                openJoin(with: code)
            } else {
                openJoinOnNextAppear = Self.opensJoinOnNextAppear(
                    storedCode: storedInviteCode,
                    isVisible: isVisible,
                    screenPushedOnTop: screenPushedOnTop,
                    isGuest: viewModel.isGuest
                )
            }
        }
        .onChange(of: viewModel.isLoading) { _, isLoading in
            if isLoading { listedBannerDismissed = false }
        }
        .refreshable { await viewModel.load() }
        .sheet(item: $activeSheet, onDismiss: sheetDismissed) { sheet in
            sheetContent(sheet)
        }
        .toast(message: $viewModel.toastMessage)
        .errorBanner(message: listedBanner, retryAction: { Task { await viewModel.load() } })
        .errorBanner(message: $viewModel.errorMessage)
    }

    // MARK: - Routes

    /// "Find communities" in the Requests and Town Hall title menus. Its Explore route is `.root`,
    /// so Explore opens at its root, not on the screen last pushed there. Both menus are for
    /// members only (a guest has no title menu), so the intent's sign-in rule never applies.
    static let findCommunitiesIntent: NavigationIntent = .myCommunities

    /// Where a pending intent opens on Explore; nil leaves it to another tab. Pure, for tests.
    static func exploreRoute(for intent: NavigationIntent) -> ExploreRoute? {
        switch intent {
        case .myCommunities, .joinCommunity:
            // `.joinCommunity`: this screen opens Join from the saved code (PendingInviteStore).
            return .root
        case .pendingMembers(let communityId):
            return .pendingMembers(.community(communityId, name: nil))
        case .communityReports(let communityId):
            return .communityReports(communityId)
        case .communityMembers(let communityId):
            return .communityMembers(communityId)
        default:
            return nil
        }
    }

    /// Opens the route of an Explore intent and clears the intent; any other intent is left alone.
    private func openExploreRoute(from intent: NavigationIntent) {
        guard let route = Self.exploreRoute(for: intent) else { return }
        switch route {
        case .root:
            // Back to this screen, so the saved-code rule decides on the visible root.
            pendingTarget = nil
            reportsTarget = nil
            membersTarget = nil
            communityPageTarget = nil
        case .pendingMembers(let target):
            pendingTarget = target
        case .communityReports(let communityId):
            reportsTarget = communityId
        case .communityMembers(let communityId):
            // Opened from a push: the role change may not be in the memberships yet.
            membersTarget = CommunityMembersTarget(
                communityId: communityId,
                communityName: CommunityContext.shared.name(for: communityId),
                refreshesRoleFirst: true
            )
        }
        navigationCoordinator.pendingIntent = nil
    }

    /// True while a screen of this tab is pushed on top of the root.
    private var hasScreenOnTop: Bool {
        screenPushedOnTop || pendingTarget != nil || reportsTarget != nil
            || membersTarget != nil || communityPageTarget != nil
    }

    // MARK: - Saved invite code

    /// A saved code whose sheet was dismissed, or never shown, stays reachable here until it is
    /// redeemed or removed.
    private func storedInviteRow(_ code: String) -> some View {
        VStack(alignment: .leading, spacing: Constants.Spacing.sm) {
            Label("community_invite_saved_row".localized, systemImage: "envelope.open.fill")
                .font(.naarsSubheadline)
                .foregroundColor(.naarsTextPrimary)
            // Side by side while both words fit whole, stacked when they do not (accessibility sizes).
            ViewThatFits(in: .horizontal) {
                HStack(spacing: Constants.Spacing.md) {
                    useCodeButton(code)
                    Spacer(minLength: 0)
                    removeCodeButton
                }
                VStack(alignment: .leading, spacing: 0) {
                    useCodeButton(code)
                    removeCodeButton
                }
            }
        }
        .padding(.vertical, Constants.Spacing.xs)
    }

    private func useCodeButton(_ code: String) -> some View {
        Button {
            useStoredCode(code)
        } label: {
            Text("community_invite_use".localized)
                .font(.naarsSubheadline.weight(.semibold))
                .foregroundColor(.naarsPrimary)
                .frame(minHeight: 44)
        }
        .buttonStyle(.borderless)
        .accessibilityLabel("community_invite_use".localized)
        .accessibilityIdentifier("community.my.inviteCode.use")
    }

    private var removeCodeButton: some View {
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

    /// A guest cannot redeem a code: the sign-in prompt comes first, and the code stays saved.
    private func useStoredCode(_ code: String) {
        if viewModel.isGuest {
            activeSheet = .guestPrompt(.joinCommunity)
        } else {
            openJoin(with: code)
        }
    }

    private func openJoin(with code: String) {
        joinPrefilledCode = code
        activeSheet = .join
    }

    /// The code to open the Join sheet with after a store change: only when one is saved, no sheet
    /// is up, this screen is the visible one and the person is not a guest. Pure, for tests.
    static func joinCodeToOpenOnStoreChange(storedCode: String?, hasSheet: Bool, isVisible: Bool, isGuest: Bool = false) -> String? {
        guard let storedCode, !hasSheet, isVisible, !isGuest else { return nil }
        return storedCode
    }

    /// Whether a store change that did not open Join now opens it on the next appearance: only when a
    /// code is saved and this screen is hidden with nothing pushed on top of it (another tab is
    /// selected). Under a pushed screen the saved-code row is the way in. A guest never. Pure, for tests.
    static func opensJoinOnNextAppear(storedCode: String?, isVisible: Bool, screenPushedOnTop: Bool, isGuest: Bool = false) -> Bool {
        storedCode != nil && !isVisible && !screenPushedOnTop && !isGuest
    }

    /// The code the first `.task` opens the Join sheet with, once per view lifetime: only for a
    /// member, with no sheet and no screen on top, and not while the pending intent opens a screen
    /// of its own (a community admin's push). Pure, for tests.
    static func joinCodeToOpenOnAppear(
        storedCode: String?,
        isGuest: Bool,
        hasSheet: Bool,
        hasScreenOnTop: Bool,
        pendingIntent: NavigationIntent?,
        alreadyDecided: Bool
    ) -> String? {
        guard !alreadyDecided, !isGuest, !hasSheet, !hasScreenOnTop, let storedCode else { return nil }
        if let pendingIntent, let route = exploreRoute(for: pendingIntent), route != .root {
            return nil
        }
        return storedCode
    }

    // MARK: - Invite code and Start a community

    private var inviteCodeRow: some View {
        actionRow(
            systemImage: "person.badge.plus",
            title: "explore_have_invite_code".localized,
            subtitle: nil,
            identifier: "explore.inviteCode"
        ) {
            if viewModel.isGuest {
                activeSheet = .guestPrompt(.joinCommunity)
            } else {
                joinPrefilledCode = nil
                activeSheet = .join
            }
        }
    }

    private var startCommunityRow: some View {
        actionRow(
            systemImage: "plus.circle",
            title: "explore_start_community".localized,
            subtitle: "explore_start_community_subtitle".localized,
            identifier: "explore.startCommunity"
        ) {
            if viewModel.isGuest {
                activeSheet = .guestPrompt(.startCommunity)
            } else {
                activeSheet = .create
            }
        }
    }

    private func actionRow(
        systemImage: String,
        title: String,
        subtitle: String?,
        identifier: String,
        action: @escaping () -> Void
    ) -> some View {
        Button(action: action) {
            HStack(spacing: Constants.Spacing.md) {
                // At accessibility sizes the icon would leave the title a few letters per line.
                if !dynamicTypeSize.isAccessibilitySize {
                    Image(systemName: systemImage)
                        .font(.naarsTitle3)
                        .foregroundColor(.naarsPrimary)
                        .frame(minWidth: 28)
                        .accessibilityHidden(true)
                }
                VStack(alignment: .leading, spacing: Constants.Spacing.xs) {
                    Text(title)
                        .font(.naarsBody)
                        .foregroundColor(.naarsPrimary)
                    if let subtitle {
                        Text(subtitle)
                            .font(.naarsFootnote)
                            .foregroundColor(.naarsTextSecondary)
                    }
                }
                .frame(maxWidth: .infinity, alignment: .leading)
            }
            .frame(minHeight: 44)
            .contentShape(Rectangle())
        }
        .buttonStyle(.plain)
        .accessibilityLabel(subtitle.map { "\(title). \($0)" } ?? title)
        .accessibilityIdentifier(identifier)
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

    // MARK: - Your communities

    /// The row layout: monogram, text and chevron in a line; stacked at accessibility text sizes,
    /// where the line leaves the name no room.
    private var rowLayout: AnyLayout {
        dynamicTypeSize.isAccessibilitySize
            ? AnyLayout(VStackLayout(alignment: .leading, spacing: Constants.Spacing.sm))
            : AnyLayout(HStackLayout(alignment: .center, spacing: Constants.Spacing.md))
    }

    private var monogramSize: CGFloat { min(scaledMonogramSize, Self.maxMonogramSize) }

    private var rowChevron: some View {
        Image(systemName: "chevron.right")
            .font(.naarsCaption)
            .foregroundColor(.secondary)
            .accessibilityHidden(true)
    }

    private func activeRow(_ membership: CommunityMembership) -> some View {
        let detail = Self.rowDetail(joinPolicy: membership.joinPolicy, memberCount: membership.memberCount)
        let muted = viewModel.isMuted(membership)
        return Button {
            communityPageTarget = membership.communityId
        } label: {
            rowLayout {
                CommunityMonogram(name: membership.name, size: monogramSize)
                VStack(alignment: .leading, spacing: Constants.Spacing.xs) {
                    Text(membership.name)
                        .font(.naarsHeadline)
                        .foregroundColor(.naarsTextPrimary)
                        .lineLimit(3)
                        .multilineTextAlignment(.leading)
                    Text(detail)
                        .font(.naarsFootnote)
                        .foregroundColor(.naarsTextSecondary)
                        .multilineTextAlignment(.leading)
                    HStack(spacing: Constants.Spacing.xs) {
                        NaarsChip(text: roleText(membership.role), tint: membership.role == .member ? nil : .naarsPrimary)
                        if muted {
                            NaarsChip(text: "community_muted_chip".localized, systemImage: "bell.slash.fill", tint: nil)
                        }
                    }
                }
                .frame(maxWidth: .infinity, alignment: .leading)
                if !dynamicTypeSize.isAccessibilitySize {
                    rowChevron
                }
            }
            .padding(.vertical, Constants.Spacing.xs)
            .frame(minHeight: 44)
            .contentShape(Rectangle())
        }
        .buttonStyle(.plain)
        .accessibilityLabel(
            ([membership.name, detail, roleText(membership.role)] + (muted ? ["community_muted_chip".localized] : []))
                .joined(separator: ", ")
        )
        .accessibilityIdentifier("explore.community.row")
    }

    /// Sets `pendingTarget`, as the Manage page does. A `NavigationLink(value:)` did nothing here
    /// while this screen was pushed from Profile: a value link cannot see a pushed screen's own
    /// `navigationDestination(for:)` (5b gate G2). The item-driven form stays.
    private func requestsLink(_ membership: CommunityMembership, count: Int) -> some View {
        Button {
            pendingTarget = .community(membership.communityId, name: membership.name)
        } label: {
            HStack(spacing: Constants.Spacing.sm) {
                if dynamicTypeSize.isAccessibilitySize {
                    // Without the icon "Requests" stays whole at accessibility sizes.
                    Text("community_action_requests".localized)
                        .font(.naarsSubheadline)
                        .foregroundColor(.naarsTextPrimary)
                } else {
                    Label("community_action_requests".localized, systemImage: "person.badge.clock")
                        .font(.naarsSubheadline)
                        .foregroundColor(.naarsTextPrimary)
                }
                Spacer(minLength: 0)
                NotificationBadge(count: count)
                Image(systemName: "chevron.right")
                    .font(.naarsCaption)
                    .foregroundColor(.secondary)
                    .accessibilityHidden(true)
            }
            .contentShape(Rectangle())
        }
        .buttonStyle(.plain)
        .accessibilityLabel(requestsTitle(count: count))
        .accessibilityIdentifier("community.my.requests")
    }

    /// "Ask to join · 12 members"; just the count for a policy this build does not know.
    /// Pure, for tests.
    static func rowDetail(joinPolicy: String, memberCount: Int) -> String {
        let count = String(
            format: (memberCount == 1 ? "community_member_count_one" : "community_member_count_other").localized,
            memberCount
        )
        guard let policy = CommunityJoinPolicy(rawValue: joinPolicy) else { return count }
        return String(format: "explore_row_detail".localized, policy.chipText, count)
    }

    // MARK: - Waiting for approval

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

    // MARK: - Listed communities

    @ViewBuilder
    private var listedSection: some View {
        let rows = viewModel.listedToShow
        Section {
            if !rows.isEmpty {
                ForEach(rows) { community in
                    listedRow(community)
                }
            } else if viewModel.listedLoadFailed {
                listedFailureRow
            } else if viewModel.hasLoadedListed {
                Text("explore_listed_empty".localized)
                    .font(.naarsSubheadline)
                    .foregroundColor(.naarsTextSecondary)
                    .accessibilityIdentifier("explore.listed.empty")
            } else {
                listedSkeletonRow
            }
        } header: {
            Text("explore_section_listed".localized)
        } footer: {
            Text("explore_listed_footer".localized)
        }
    }

    private func listedRow(_ community: PublicCommunity) -> some View {
        let policy = CommunityJoinPolicy(rawValue: community.joinPolicy)
        return Button {
            communityPageTarget = community.id
        } label: {
            rowLayout {
                CommunityMonogram(name: community.name, size: monogramSize)
                VStack(alignment: .leading, spacing: Constants.Spacing.xs) {
                    Text(community.name)
                        .font(.naarsHeadline)
                        .foregroundColor(.naarsTextPrimary)
                        .lineLimit(3)
                        .multilineTextAlignment(.leading)
                    if let policy {
                        CommunityPolicyChip(policy: policy)
                    }
                }
                .frame(maxWidth: .infinity, alignment: .leading)
                if !dynamicTypeSize.isAccessibilitySize {
                    rowChevron
                }
            }
            .padding(.vertical, Constants.Spacing.xs)
            .frame(minHeight: 44)
            .contentShape(Rectangle())
        }
        .buttonStyle(.plain)
        .accessibilityLabel(([community.name] + (policy.map { [$0.chipText] } ?? [])).joined(separator: ", "))
        .accessibilityIdentifier("explore.listed.row")
    }

    /// The failure row, only where the section would otherwise be empty. With rows on screen a
    /// failed refresh keeps them and shows the banner instead.
    private var listedFailureRow: some View {
        VStack(alignment: .leading, spacing: Constants.Spacing.sm) {
            Label("explore_listed_load_failed".localized, systemImage: "exclamationmark.triangle.fill")
                .font(.naarsSubheadline)
                .foregroundColor(.naarsTextSecondary)
            Button {
                Task { await viewModel.load() }
            } label: {
                Text("common_retry".localized)
                    .font(.naarsSubheadline.weight(.semibold))
                    .foregroundColor(.naarsPrimary)
                    .frame(minHeight: 44)
            }
            .buttonStyle(.borderless)
            .accessibilityLabel("common_retry".localized)
            .accessibilityIdentifier("explore.listed.retry")
        }
        .padding(.vertical, Constants.Spacing.xs)
    }

    /// The failure banner over listed rows that stayed on screen. Closed by its own dismiss button
    /// until the next load, and not drawn while an action error uses the banner slot.
    private var listedBanner: Binding<String?> {
        Binding(
            get: {
                guard viewModel.listedLoadFailed, !viewModel.listedToShow.isEmpty,
                      !listedBannerDismissed, viewModel.errorMessage == nil else { return nil }
                return "explore_listed_load_failed".localized
            },
            set: { if $0 == nil { listedBannerDismissed = true } }
        )
    }

    private var listedSkeletonRow: some View {
        HStack(spacing: Constants.Spacing.md) {
            SkeletonRectangle(width: monogramSize, height: monogramSize, cornerRadius: monogramSize / 2)
            VStack(alignment: .leading, spacing: Constants.Spacing.sm) {
                SkeletonRectangle(width: 180, height: 16)
                SkeletonRectangle(width: 80, height: 12)
            }
        }
        .padding(.vertical, Constants.Spacing.xs)
        .accessibilityHidden(true)
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
            // The sheet shows its own done state; the result is recorded the moment the server
            // answers and acted on in `sheetDismissed`.
            JoinCommunitySheet(target: .code(prefilled: joinPrefilledCode), onJoined: { joinResult = $0 })
        case .guestPrompt(let reason):
            GuestSignInPromptView(
                reason: reason,
                onSignUp: { exitGuestMode() },
                onLogIn: { exitGuestMode() }
            )
        }
    }

    private func exitGuestMode() {
        appState.isGuestMode = false
        AppLaunchManager.shared.exitGuestMode()
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

    private func requestsTitle(count: Int) -> String {
        let title = "community_action_requests".localized
        return count > 0 ? "\(title) (\(count))" : title
    }
}

#if DEBUG
private enum ExplorePreviewData {
    /// Explore for `memberships` (empty with `isGuest`: a guest), the listed communities `listed`,
    /// and a saved invite code when `savedCode` is set.
    @MainActor
    static func screen(
        memberships: [CommunityMembership],
        listed: [PublicCommunity] = PreviewCommunityService.samplePublicCommunities,
        limits: CommunityLimits? = nil,
        failListed: Bool = false,
        isGuest: Bool = false,
        savedCode: String? = nil
    ) -> some View {
        let service = PreviewCommunityService()
        service.memberships = memberships
        service.publicCommunities = listed
        service.failPublicCommunities = failListed
        if let limits { service.limits = limits }
        let context = CommunityContext(service: service, defaults: UserDefaults(suiteName: "preview")!)
        context.debugSetMemberships(memberships)
        if let savedCode { PendingInviteStore().save(savedCode) } else { PendingInviteStore().clear() }
        return NavigationStack {
            MyCommunitiesView(viewModel: MyCommunitiesViewModel(
                service: service, communityContext: context, refreshDashboard: { _ in }, isGuest: { isGuest }
            ))
        }
        .environment(AppState())
    }
}

#Preview("Member, two communities") {
    ExplorePreviewData.screen(memberships: [
        PreviewCommunityService.membership(name: "Naar's Cars Seattle", memberCount: 140, isDefault: true),
        PreviewCommunityService.membership(name: "Ballard Neighbors", memberCount: 12)
    ])
}

#Preview("Admin with requests and a waiting row") {
    ExplorePreviewData.screen(memberships: PreviewCommunityService.sampleMemberships)
}

#Preview("Limit reached") {
    ExplorePreviewData.screen(
        memberships: PreviewCommunityService.sampleMemberships,
        limits: CommunityLimits(maxOwned: 3, ownedCount: 3, nextCreateAt: nil, canCreate: false, latestRequest: nil)
    )
}

#Preview("Limit request pending") {
    ExplorePreviewData.screen(
        memberships: PreviewCommunityService.sampleMemberships,
        limits: CommunityLimits(
            maxOwned: 3, ownedCount: 3, nextCreateAt: nil, canCreate: false,
            latestRequest: CommunityLimitRequest(
                requestId: UUID(), requestedMax: 5, reason: "Three groups", status: .pending,
                createdAt: Date(), decidedAt: nil
            )
        )
    )
}

#Preview("Guest") {
    ExplorePreviewData.screen(memberships: [], isGuest: true)
}

// A member with a saved code gets the Join sheet by itself on first appearance; a guest never does,
// so this is the preview that shows the saved-code row.
#Preview("Guest with a saved invite code") {
    ExplorePreviewData.screen(memberships: [], isGuest: true, savedCode: "NC7K2PQ9XA")
}

#Preview("Listed communities failed to load") {
    ExplorePreviewData.screen(
        memberships: [PreviewCommunityService.membership(name: "Ballard Neighbors", memberCount: 12)],
        failListed: true
    )
}
#endif

private extension PendingMembersTarget {
    /// The community a pushed Requests to join screen shows (nil: the default community), its
    /// identity on Explore whatever name the target carries.
    var communityId: UUID? {
        if case .community(let id, _) = self { return id }
        return nil
    }
}
