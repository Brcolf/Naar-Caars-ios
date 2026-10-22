//
//  CommunityPageView.swift
//  NaarsCars
//
//  One community's page: for a member (actions, open requests, recent posts, leaderboard), for
//  someone waiting for approval, and for a visitor (the listed preview with a floating join bar)
//

import SwiftUI
import SwiftData

/// The community page. No NavigationStack: it is pushed from Explore. Every push the page makes is
/// driven by a bool or an item (or a destination-style link to a profile), never a value-based link.
struct CommunityPageView: View {
    private enum ActiveSheet: Identifiable {
        case invite(CommunityMembership)
        case report(name: String)
        case leave(CommunityMembership, LeavePlan)
        case join(JoinTarget)
        case guestPrompt(GuestRestrictionReason)

        var id: String {
            switch self {
            case .invite(let membership): return "invite-\(membership.communityId)"
            case .report: return "report"
            case .leave(let membership, _): return "leave-\(membership.communityId)"
            case .join(let target):
                switch target {
                case .code: return "join-code"
                case .publicCommunity(let community): return "join-\(community.id)"
                }
            case .guestPrompt(let reason): return "guest-\(reason.id)"
            }
        }
    }

    @Environment(\.modelContext) private var modelContext
    @Environment(AppState.self) private var appState
    @StateObject private var viewModel: CommunityPageViewModel
    /// Leave, mute and the follow-up of a join run on the same view model Explore uses.
    @StateObject private var communitiesViewModel: MyCommunitiesViewModel
    @StateObject private var leaderboardViewModel: LeaderboardViewModel
    @Environment(\.dynamicTypeSize) private var dynamicTypeSize
    @ScaledMetric(relativeTo: .title3) private var scaledMonogramSize: CGFloat = 56
    @ScaledMetric(relativeTo: .subheadline) private var scaledAvatarSize: CGFloat = 36

    @State private var activeSheet: ActiveSheet?
    /// Recorded by the Join sheet; acted on in its `onDismiss`.
    @State private var joinResult: JoinResult?
    @State private var showAdminPanel = false
    @State private var showLeaderboard = false
    @State private var showGuidelines = false
    /// Members, opened to choose a new owner after a `last_owner` refusal.
    @State private var membersTarget: CommunityMembersTarget?

    @MainActor init(communityId: UUID) {
        _viewModel = StateObject(wrappedValue: CommunityPageViewModel(communityId: communityId))
        _communitiesViewModel = StateObject(wrappedValue: MyCommunitiesViewModel())
        _leaderboardViewModel = StateObject(wrappedValue: LeaderboardViewModel(communityId: communityId))
    }

    /// For previews and tests.
    @MainActor init(
        viewModel: @autoclosure @escaping @MainActor () -> CommunityPageViewModel,
        communitiesViewModel: @autoclosure @escaping @MainActor () -> MyCommunitiesViewModel,
        leaderboardViewModel: @autoclosure @escaping @MainActor () -> LeaderboardViewModel
    ) {
        _viewModel = StateObject(wrappedValue: viewModel())
        _communitiesViewModel = StateObject(wrappedValue: communitiesViewModel())
        _leaderboardViewModel = StateObject(wrappedValue: leaderboardViewModel())
    }

    // MARK: - Body

    var body: some View {
        content
            .frame(maxWidth: .infinity, maxHeight: .infinity)
            .background(Color.naarsBackground)
            .safeAreaInset(edge: .bottom, spacing: 0) { joinBar }
            .navigationTitle(viewModel.communityName ?? "")
            .navigationBarTitleDisplayMode(.inline)
            .toolbar { visitorMenu }
            // Runs on appearance and again whenever the person's own row changes (a join, a leave,
            // a mute, an approval), so the page follows the membership.
            .task(id: viewModel.currentMembership) {
                communitiesViewModel.setup(modelContext: modelContext)
                await viewModel.loadIfStale()
            }
            .task(id: isMemberMode) {
                guard isMemberMode else { return }
                await leaderboardViewModel.loadLeaderboard()
            }
            .sheet(item: $activeSheet, onDismiss: sheetDismissed) { sheet in
                sheetContent(sheet)
            }
            .navigationDestination(isPresented: $showAdminPanel) {
                AdminPanelView(
                    scope: .community(viewModel.communityId),
                    communityName: viewModel.communityName,
                    onCommunityArchived: { communitiesViewModel.toastMessage = $0 }
                )
            }
            .navigationDestination(isPresented: $showLeaderboard) {
                LeaderboardView(viewModel: leaderboardViewModel)
                    .background(Color.naarsBackground)
                    .navigationTitle("leaderboard_title".localized)
                    .navigationBarTitleDisplayMode(.inline)
            }
            .navigationDestination(isPresented: $showGuidelines) {
                CommunityGuidelinesView(showDismissButton: false)
            }
            .navigationDestination(item: $membersTarget) { target in
                CommunityMembersView(target: target)
                    .id(target.communityId)
            }
            .toast(message: $communitiesViewModel.toastMessage)
            .errorBanner(message: $communitiesViewModel.errorMessage)
            .errorBanner(message: $viewModel.bannerMessage)
            .alert(
                "community_leave_needs_owner_title".localized,
                isPresented: Binding(
                    get: { communitiesViewModel.newOwnerNeededFor != nil },
                    set: { if !$0 { communitiesViewModel.newOwnerNeededFor = nil } }
                ),
                presenting: communitiesViewModel.newOwnerNeededFor
            ) { membership in
                Button("community_leave_needs_owner_action".localized) {
                    let target = CommunityMembersTarget(
                        communityId: membership.communityId,
                        communityName: membership.name,
                        highlightTransfer: true
                    )
                    communitiesViewModel.newOwnerNeededFor = nil
                    membersTarget = target
                }
                .accessibilityIdentifier("communityPage.chooseNewOwner")
                Button("common_cancel".localized, role: .cancel) {
                    communitiesViewModel.newOwnerNeededFor = nil
                }
            } message: { membership in
                Text(String(format: "community_leave_needs_owner_body".localized, membership.name))
            }
    }

    /// Grows with the text, up to a size that still leaves the name room beside it.
    private var monogramSize: CGFloat { min(scaledMonogramSize, 84) }

    private var avatarSize: CGFloat { min(scaledAvatarSize, 56) }

    private var isMemberMode: Bool {
        if case .member = viewModel.mode { return true }
        return false
    }

    @ViewBuilder
    private var content: some View {
        switch viewModel.mode {
        case .loading:
            skeleton
        case .member(let membership):
            memberContent(membership)
        case .pending(let membership):
            scrollContent {
                header(name: membership.name, role: nil)
            }
        case .visitor(let preview):
            visitorContent(preview)
        case .unavailable:
            EmptyStateView(
                icon: "building.2",
                title: "community_page_unavailable".localized,
                message: ""
            )
            .padding(.horizontal, Constants.Spacing.md)
        case .failed:
            ErrorView(
                error: "community_page_load_failed".localized,
                retryAction: { Task { await viewModel.load() } }
            )
            .accessibilityIdentifier("communityPage.retry")
        }
    }

    private func scrollContent<Content: View>(@ViewBuilder _ content: () -> Content) -> some View {
        ScrollView {
            VStack(alignment: .leading, spacing: Constants.Spacing.md) {
                content()
            }
            .padding(.horizontal, Constants.Spacing.md)
            .padding(.vertical, Constants.Spacing.md)
            .frame(maxWidth: .infinity, alignment: .leading)
        }
        .refreshable { await refreshPage() }
    }

    private func refreshPage() async {
        await viewModel.refresh()
        if isMemberMode {
            await leaderboardViewModel.refresh()
        }
    }

    private var skeleton: some View {
        VStack(alignment: .leading, spacing: Constants.Spacing.md) {
            HStack(spacing: Constants.Spacing.md) {
                SkeletonRectangle(width: monogramSize, height: monogramSize, cornerRadius: monogramSize / 2)
                VStack(alignment: .leading, spacing: Constants.Spacing.sm) {
                    SkeletonRectangle(width: 180, height: 18)
                    SkeletonRectangle(width: 90, height: 12)
                }
            }
            SkeletonRectangle(height: 14)
            SkeletonRectangle(width: 220, height: 14)
            SkeletonRectangle(height: 120, cornerRadius: Constants.Radius.card)
            Spacer(minLength: 0)
        }
        .padding(Constants.Spacing.md)
        .frame(maxWidth: .infinity, alignment: .leading)
        .accessibilityHidden(true)
    }

    // MARK: - Header

    private func header(name: String, role: CommunityRole?) -> some View {
        VStack(alignment: .leading, spacing: Constants.Spacing.ms) {
            // The monogram sits above the name once the text is too large to share a line with it.
            let layout = dynamicTypeSize.isAccessibilitySize
                ? AnyLayout(VStackLayout(alignment: .leading, spacing: Constants.Spacing.sm))
                : AnyLayout(HStackLayout(alignment: .center, spacing: Constants.Spacing.md))
            layout {
                CommunityMonogram(name: name, size: monogramSize)
                VStack(alignment: .leading, spacing: Constants.Spacing.xxs) {
                    Text(name)
                        .font(.naarsTitle3)
                        .foregroundColor(.naarsTextPrimary)
                        .lineLimit(3)
                        .fixedSize(horizontal: false, vertical: true)
                        .accessibilityAddTraits(.isHeader)
                    if let count = viewModel.memberCount {
                        Text(memberCountText(count))
                            .font(.naarsFootnote)
                            .foregroundColor(.naarsTextSecondary)
                    }
                }
            }
            chips(role: role)
            if let policy = viewModel.policy {
                Text(policy.ruleSentence)
                    .font(.naarsBody)
                    .foregroundColor(.naarsTextSecondary)
                    .fixedSize(horizontal: false, vertical: true)
            }
        }
    }

    /// One row of chips while they fit, one under the other when they do not (large text).
    private func chips(role: CommunityRole?) -> some View {
        ViewThatFits(in: .horizontal) {
            HStack(spacing: Constants.Spacing.sm) { chipViews(role: role) }
            VStack(alignment: .leading, spacing: Constants.Spacing.sm) { chipViews(role: role) }
        }
    }

    @ViewBuilder
    private func chipViews(role: CommunityRole?) -> some View {
        if let policy = viewModel.policy {
            CommunityPolicyChip(policy: policy)
        }
        if viewModel.isListed {
            NaarsChip(text: "community_page_listed_chip".localized, systemImage: "magnifyingglass", tint: nil)
        }
        if let role, role != .member {
            NaarsChip(text: roleText(role), tint: .naarsPrimary)
        }
    }

    // MARK: - Member

    private func memberContent(_ membership: CommunityMembership) -> some View {
        scrollContent {
            header(name: membership.name, role: membership.role)
            memberActions(membership)
            LocalCommunityActivity(communityId: membership.communityId) { requests, posts in
                // The store holds only the Town Hall tab's community's posts; any other community
                // gets a way to its Town Hall rather than a wrong "no posts yet".
                activity(requests: requests, posts: viewModel.showsLocalTownHallPosts ? posts : nil)
            }
            leaderboardCard
            otherActions(membership)
        }
    }

    private func memberActions(_ membership: CommunityMembership) -> some View {
        let muted = communitiesViewModel.isMuted(membership)
        let busy = communitiesViewModel.busyCommunityId != nil
        return VStack(spacing: 0) {
            if membership.canInvite {
                actionRow(
                    icon: "person.crop.circle.badge.plus",
                    title: "community_action_invite".localized,
                    identifier: "communityPage.invite"
                ) {
                    activeSheet = .invite(membership)
                }
                Divider()
            }
            actionRow(
                icon: muted ? "bell.fill" : "bell.slash",
                title: (muted ? "community_action_unmute" : "community_action_mute").localized,
                isBusy: communitiesViewModel.busyCommunityId == membership.communityId,
                isDisabled: busy,
                identifier: "communityPage.mute"
            ) {
                Task { await communitiesViewModel.setMuted(!muted, for: membership) }
            }
            if viewModel.isAdmin {
                Divider()
                actionRow(
                    icon: "shield",
                    title: "community_page_manage".localized,
                    subtitle: "community_page_manage_subtitle".localized,
                    badge: membership.pendingCount ?? 0,
                    showsChevron: true,
                    identifier: "communityPage.manage"
                ) {
                    showAdminPanel = true
                }
            }
        }
        .cardSurface()
    }

    private func otherActions(_ membership: CommunityMembership) -> some View {
        VStack(spacing: 0) {
            actionRow(
                icon: "book.closed",
                title: "settings_community_guidelines".localized,
                showsChevron: true,
                identifier: "communityPage.guidelines"
            ) {
                showGuidelines = true
            }
            Divider()
            actionRow(
                icon: "exclamationmark.bubble",
                title: "community_report_this_community".localized,
                identifier: "communityPage.report"
            ) {
                activeSheet = .report(name: membership.name)
            }
            Divider()
            actionRow(
                icon: "rectangle.portrait.and.arrow.right",
                title: String(format: "community_page_leave".localized, membership.name),
                isDestructive: true,
                isDisabled: communitiesViewModel.busyCommunityId != nil,
                identifier: "communityPage.leave"
            ) {
                activeSheet = .leave(membership, communitiesViewModel.leavePlan(for: membership))
            }
        }
        .cardSurface()
    }

    /// A tappable row of an actions card: icon, title (and subtitle), an optional count and chevron.
    private func actionRow(
        icon: String,
        title: String,
        subtitle: String? = nil,
        badge: Int = 0,
        showsChevron: Bool = false,
        isDestructive: Bool = false,
        isBusy: Bool = false,
        isDisabled: Bool = false,
        identifier: String,
        action: @escaping () -> Void
    ) -> some View {
        Button(action: action) {
            HStack(spacing: Constants.Spacing.ms) {
                // Decorative; at accessibility text sizes the words need the width more.
                if !dynamicTypeSize.isAccessibilitySize {
                    Image(systemName: icon)
                        .font(.naarsBody)
                        .foregroundColor(isDestructive ? .naarsError : .naarsPrimary)
                        .frame(width: 28)
                        .accessibilityHidden(true)
                }
                VStack(alignment: .leading, spacing: Constants.Spacing.xxs) {
                    HStack(spacing: Constants.Spacing.sm) {
                        Text(title)
                            .font(.naarsBody)
                            .foregroundColor(isDestructive ? .naarsError : .naarsTextPrimary)
                            .multilineTextAlignment(.leading)
                        NotificationBadge(count: badge)
                    }
                    if let subtitle {
                        Text(subtitle)
                            .font(.naarsFootnote)
                            .foregroundColor(.naarsTextSecondary)
                            .multilineTextAlignment(.leading)
                    }
                }
                .frame(maxWidth: .infinity, alignment: .leading)
                if isBusy {
                    ProgressView()
                }
                if showsChevron {
                    Image(systemName: "chevron.right")
                        .font(.naarsCaption)
                        .foregroundColor(.secondary)
                        .accessibilityHidden(true)
                }
            }
            .padding(.horizontal, Constants.Spacing.md)
            .padding(.vertical, Constants.Spacing.ms)
            .frame(minHeight: 44)
            .contentShape(Rectangle())
        }
        .buttonStyle(.plain)
        .disabled(isDisabled)
        .accessibilityIdentifier(identifier)
    }

    // MARK: - Leaderboard

    private var leaderboardCard: some View {
        VStack(alignment: .leading, spacing: Constants.Spacing.sm) {
            // The title and "See all" share a line until the text is too large for both.
            let titleLayout = dynamicTypeSize.isAccessibilitySize
                ? AnyLayout(VStackLayout(alignment: .leading, spacing: Constants.Spacing.xs))
                : AnyLayout(HStackLayout(alignment: .center, spacing: Constants.Spacing.sm))
            titleLayout {
                Text("leaderboard_title".localized)
                    .font(.naarsHeadline)
                    .foregroundColor(.naarsTextPrimary)
                    .accessibilityAddTraits(.isHeader)
                if !dynamicTypeSize.isAccessibilitySize {
                    Spacer(minLength: Constants.Spacing.sm)
                }
                Button {
                    showLeaderboard = true
                } label: {
                    Text("community_page_see_all".localized)
                        .font(.naarsSubheadline.weight(.semibold))
                        .foregroundColor(.naarsPrimary)
                        .frame(minHeight: 44)
                }
                .buttonStyle(.plain)
                .accessibilityIdentifier("communityPage.leaderboard")
            }

            if leaderboardViewModel.entries.isEmpty {
                if leaderboardViewModel.isLoading {
                    VStack(spacing: Constants.Spacing.sm) {
                        SkeletonRectangle(height: 44)
                        SkeletonRectangle(height: 44)
                    }
                    .accessibilityHidden(true)
                } else {
                    Text("leaderboard_no_rankings".localized)
                        .font(.naarsSubheadline)
                        .foregroundColor(.naarsTextSecondary)
                }
            } else {
                ForEach(Array(leaderboardViewModel.entries.prefix(Constants.Community.pageLeaderboardRows))) { entry in
                    NavigationLink(destination: PublicProfileView(userId: entry.userId)) {
                        LeaderboardRow(entry: entry)
                    }
                    .buttonStyle(.plain)
                }
            }
        }
        .frame(maxWidth: .infinity, alignment: .leading)
        .cardStyle()
    }

    // MARK: - Requests and posts

    /// `posts` nil: the posts are not at hand (member mode, a community other than the Town Hall
    /// tab's); the card offers that community's Town Hall.
    private func activity(requests: [CommunityPreview.Request], posts: [CommunityPreview.Post]?) -> some View {
        VStack(alignment: .leading, spacing: Constants.Spacing.md) {
            requestsCard(requests)
            postsCard(posts)
        }
    }

    private func requestsCard(_ requests: [CommunityPreview.Request]) -> some View {
        VStack(alignment: .leading, spacing: Constants.Spacing.sm) {
            sectionTitle("community_page_open_requests".localized)
            if requests.isEmpty {
                Text("community_page_no_open_requests".localized)
                    .font(.naarsSubheadline)
                    .foregroundColor(.naarsTextSecondary)
            } else {
                ForEach(Array(requests.enumerated()), id: \.element.id) { index, request in
                    if index > 0 { Divider() }
                    requestRow(request)
                }
            }
        }
        .frame(maxWidth: .infinity, alignment: .leading)
        .cardStyle()
    }

    private func requestRow(_ request: CommunityPreview.Request) -> some View {
        let when = CommunityPageViewModel.whenText(date: request.date, time: request.time)
        let kind = String(
            format: (request.isRide ? "community_page_ride_row" : "community_page_favor_row").localized,
            request.posterName,
            when
        )
        return HStack(alignment: .center, spacing: Constants.Spacing.ms) {
            UserAvatarLink(
                profile: Profile(id: request.posterId, name: request.posterName, email: "", avatarUrl: request.posterAvatarUrl),
                size: avatarSize
            )
            VStack(alignment: .leading, spacing: Constants.Spacing.xxs) {
                if !request.isRide, let title = request.title, !title.isEmpty {
                    Text(title)
                        .font(.naarsSubheadline.weight(.semibold))
                        .foregroundColor(.naarsTextPrimary)
                        .lineLimit(2)
                    Text(kind)
                        .font(.naarsFootnote)
                        .foregroundColor(.naarsTextSecondary)
                } else {
                    Text(kind)
                        .font(.naarsSubheadline)
                        .foregroundColor(.naarsTextPrimary)
                }
            }
            .frame(maxWidth: .infinity, alignment: .leading)
            .accessibilityElement(children: .combine)
        }
    }

    private func postsCard(_ posts: [CommunityPreview.Post]?) -> some View {
        VStack(alignment: .leading, spacing: Constants.Spacing.sm) {
            sectionTitle("community_page_recent_town_hall".localized)
            if let posts, posts.isEmpty {
                Text("community_page_no_posts".localized)
                    .font(.naarsSubheadline)
                    .foregroundColor(.naarsTextSecondary)
            } else if let posts {
                ForEach(Array(posts.enumerated()), id: \.element.id) { index, post in
                    if index > 0 { Divider() }
                    postRow(post)
                }
            } else {
                townHallLink
            }
        }
        .frame(maxWidth: .infinity, alignment: .leading)
        .cardStyle()
    }

    /// Makes this community the Town Hall tab's community and selects the tab.
    private var townHallLink: some View {
        Button {
            viewModel.openTownHall()
        } label: {
            HStack(spacing: Constants.Spacing.sm) {
                Text("community_page_open_town_hall".localized)
                    .font(.naarsSubheadline.weight(.semibold))
                    .foregroundColor(.naarsPrimary)
                    .multilineTextAlignment(.leading)
                    .frame(maxWidth: .infinity, alignment: .leading)
                Image(systemName: "chevron.right")
                    .font(.naarsCaption)
                    .foregroundColor(.secondary)
                    .accessibilityHidden(true)
            }
            .frame(minHeight: 44)
            .contentShape(Rectangle())
        }
        .buttonStyle(.plain)
        .accessibilityHint("community_page_open_town_hall_hint".localized)
        .accessibilityIdentifier("communityPage.openTownHall")
    }

    private func postRow(_ post: CommunityPreview.Post) -> some View {
        VStack(alignment: .leading, spacing: Constants.Spacing.xxs) {
            Text(post.content)
                .font(.naarsSubheadline)
                .foregroundColor(.naarsTextPrimary)
                .lineLimit(2)
            Text(postMeta(post))
                .font(.naarsFootnote)
                .foregroundColor(.naarsTextSecondary)
        }
        .frame(maxWidth: .infinity, alignment: .leading)
        .accessibilityElement(children: .combine)
    }

    private func sectionTitle(_ text: String) -> some View {
        Text(text)
            .font(.naarsHeadline)
            .foregroundColor(.naarsTextPrimary)
            .accessibilityAddTraits(.isHeader)
    }

    // MARK: - Visitor

    private func visitorContent(_ preview: CommunityPreview) -> some View {
        scrollContent {
            if viewModel.isGuest {
                guestNotice
            }
            header(name: preview.community.name, role: nil)
            activity(requests: preview.requests, posts: preview.posts)
        }
    }

    private var guestNotice: some View {
        HStack(alignment: .top, spacing: Constants.Spacing.ms) {
            if !dynamicTypeSize.isAccessibilitySize {
                Image(systemName: "info.circle")
                    .font(.naarsBody)
                    .foregroundColor(.naarsPrimary)
                    .accessibilityHidden(true)
            }
            Text("community_page_guest_notice".localized)
                .font(.naarsSubheadline)
                .foregroundColor(.naarsTextPrimary)
                .fixedSize(horizontal: false, vertical: true)
        }
        .frame(maxWidth: .infinity, alignment: .leading)
        .cardStyle()
        .accessibilityElement(children: .combine)
        .accessibilityIdentifier("communityPage.guestNotice")
    }

    @ToolbarContentBuilder
    private var visitorMenu: some ToolbarContent {
        if case .visitor(let preview) = viewModel.mode {
            ToolbarItem(placement: .navigationBarTrailing) {
                Menu {
                    Button {
                        if viewModel.isGuest {
                            activeSheet = .guestPrompt(.reportContent)
                        } else {
                            activeSheet = .report(name: preview.community.name)
                        }
                    } label: {
                        Label("community_report_this_community".localized, systemImage: "exclamationmark.bubble")
                    }
                } label: {
                    Image(systemName: "ellipsis.circle")
                }
                .accessibilityLabel(String(format: "community_actions_accessibility".localized, preview.community.name))
                .accessibilityIdentifier("communityPage.more")
            }
        }
    }

    // MARK: - Join bar

    /// The floating bar of a visitor or a pending member. A glass surface: it floats over the
    /// scrolling content, and the safe-area inset keeps that content clear of it. Waiting for
    /// approval is plain text, not a disabled button: dimmed text is hard to read and there is
    /// nothing to press.
    @ViewBuilder
    private var joinBar: some View {
        if let action = viewModel.visitorAction {
            let text = barText(for: action)
            let label = [text.title, text.subtitle].compactMap { $0 }.joined(separator: ", ")
            Group {
                if action == .waitingForApproval {
                    barContent(action, text: text)
                        .accessibilityElement(children: .combine)
                } else {
                    Button {
                        barTapped(action)
                    } label: {
                        barContent(action, text: text)
                    }
                    .buttonStyle(.plain)
                }
            }
            .glassEffect(.regular, in: .rect(cornerRadius: Constants.Radius.card))
            .padding(.horizontal, Constants.Spacing.md)
            .padding(.bottom, Constants.Spacing.sm)
            .accessibilityLabel(label)
            .accessibilityIdentifier("communityPage.join")
        }
    }

    private func barContent(_ action: CommunityVisitorAction, text: (title: String, subtitle: String?)) -> some View {
        HStack(spacing: Constants.Spacing.ms) {
            Image(systemName: barIcon(for: action))
                .font(.naarsTitle3)
                .foregroundColor(action == .waitingForApproval ? .naarsWarning : .naarsPrimary)
                .accessibilityHidden(true)
            VStack(alignment: .leading, spacing: Constants.Spacing.xxs) {
                Text(text.title)
                    .font(.naarsHeadline)
                    .foregroundColor(.naarsTextPrimary)
                    .multilineTextAlignment(.leading)
                // At accessibility text sizes the bar would take half the screen: the title
                // stays, and VoiceOver still reads both through the bar's label.
                if let subtitle = text.subtitle, !dynamicTypeSize.isAccessibilitySize {
                    Text(subtitle)
                        .font(.naarsFootnote)
                        .foregroundColor(.naarsTextSecondary)
                        .multilineTextAlignment(.leading)
                }
            }
            .frame(maxWidth: .infinity, alignment: .leading)
            if action != .waitingForApproval {
                Image(systemName: "chevron.right")
                    .font(.naarsCaption)
                    .foregroundColor(.secondary)
                    .accessibilityHidden(true)
            }
        }
        .padding(.horizontal, Constants.Spacing.md)
        .padding(.vertical, Constants.Spacing.ms)
        .frame(minHeight: 56)
        .contentShape(Rectangle())
    }

    private func barText(for action: CommunityVisitorAction) -> (title: String, subtitle: String?) {
        switch action {
        case .signUp:
            return ("community_page_bar_signup_title".localized, "community_page_bar_signup_subtitle".localized)
        case .askToJoin:
            // An open community needs no answer; the others wait for an admin.
            if viewModel.policy == .open {
                return ("community_join_submit_join".localized, nil)
            }
            return ("community_policy_ask_to_join".localized, "community_page_bar_ask_subtitle".localized)
        case .enterInviteCode:
            return ("community_page_bar_code_title".localized, "community_page_bar_code_subtitle".localized)
        case .waitingForApproval:
            return ("community_status_pending".localized, nil)
        }
    }

    private func barIcon(for action: CommunityVisitorAction) -> String {
        switch action {
        case .signUp: return "person.crop.circle.badge.plus"
        case .askToJoin: return "person.badge.plus"
        case .enterInviteCode: return "key.fill"
        case .waitingForApproval: return "clock"
        }
    }

    private func barTapped(_ action: CommunityVisitorAction) {
        switch action {
        case .signUp:
            activeSheet = .guestPrompt(.joinCommunity)
        case .askToJoin(let community):
            activeSheet = .join(.publicCommunity(community))
        case .enterInviteCode:
            activeSheet = .join(.code(prefilled: nil))
        case .waitingForApproval:
            break
        }
    }

    // MARK: - Sheets

    @ViewBuilder
    private func sheetContent(_ sheet: ActiveSheet) -> some View {
        switch sheet {
        case .invite(let membership):
            CommunityInviteSheet(
                communityId: membership.communityId,
                communityName: membership.name,
                isAdmin: viewModel.isAdmin,
                onDone: { activeSheet = nil }
            )
        case .report(let name):
            ReportContentSheet(context: .community(id: viewModel.communityId, code: nil, name: name))
        case .leave(let membership, let plan):
            LeaveCommunitySheet(
                membership: membership,
                plan: plan,
                isOnlyActiveCommunity: membership.status == .active && communitiesViewModel.active.count == 1,
                onConfirm: {
                    let target = membership
                    activeSheet = nil
                    Task { await communitiesViewModel.leave(target) }
                }
            )
        case .join(let target):
            JoinCommunitySheet(target: target, onJoined: { joinResult = $0 })
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

    /// Join records its result; the follow-up runs once the sheet is gone, so nothing reloads
    /// underneath a sheet that is still on screen.
    private func sheetDismissed() {
        guard let result = joinResult else { return }
        joinResult = nil
        Task {
            await communitiesViewModel.didJoin(result)
            await viewModel.load()
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

    private func postMeta(_ post: CommunityPreview.Post) -> String {
        String(
            format: (post.commentCount == 1 ? "community_page_post_meta_one" : "community_page_post_meta_other").localized,
            post.authorName,
            post.createdAt.timeAgoString,
            post.commentCount
        )
    }
}

/// Member mode's open requests and recent posts, read from the local store: no request of its own.
/// Sync engines write the rows; `@Query` redraws when they change.
private struct LocalCommunityActivity<Content: View>: View {
    let communityId: UUID
    let content: ([CommunityPreview.Request], [CommunityPreview.Post]) -> Content
    @Query private var rides: [SDRide]
    @Query private var favors: [SDFavor]
    @Query private var posts: [SDTownHallPost]

    init(
        communityId: UUID,
        @ViewBuilder content: @escaping ([CommunityPreview.Request], [CommunityPreview.Post]) -> Content
    ) {
        self.communityId = communityId
        self.content = content
        let community: UUID? = communityId
        _rides = Query(filter: #Predicate<SDRide> { $0.communityId == community })
        _favors = Query(filter: #Predicate<SDFavor> { $0.communityId == community })
        _posts = Query(filter: #Predicate<SDTownHallPost> { $0.communityId == community })
    }

    var body: some View {
        let isBlocked: (UUID) -> Bool = { MessageService.shared.isBlocked($0) }
        content(
            CommunityPageViewModel.localRequests(
                rides: rides, favors: favors, communityId: communityId, isBlocked: isBlocked
            ),
            CommunityPageViewModel.localPosts(posts, communityId: communityId, isBlocked: isBlocked)
        )
    }
}

#if DEBUG
// MARK: - Previews

/// Canned rows for the previews: a leaderboard and a local store with a few requests and posts.
private enum CommunityPagePreviewData {
    final class Leaderboard: LeaderboardFetching {
        func fetchLeaderboard(period: LeaderboardPeriod, communityId: UUID?) async throws -> [LeaderboardEntry] {
            let rows = [
                LeaderboardEntry(userId: UUID(), name: "Sam Neighbor", avatarUrl: nil, xp: 420, badges: [], streakWeeks: 3, requestsFulfilled: 12, requestsMade: 4),
                LeaderboardEntry(userId: UUID(), name: "Pat Quinn", avatarUrl: nil, xp: 310, badges: [], streakWeeks: 1, requestsFulfilled: 8, requestsMade: 2),
                LeaderboardEntry(userId: UUID(), name: "Dana Rivera", avatarUrl: nil, xp: 150, badges: [], streakWeeks: 0, requestsFulfilled: 3, requestsMade: 5),
                LeaderboardEntry(userId: UUID(), name: "Lee Park", avatarUrl: nil, xp: 90, badges: [], streakWeeks: 0, requestsFulfilled: 1, requestsMade: 1)
            ]
            // The service numbers the rows from 1.
            return rows.enumerated().map { index, entry in
                var ranked = entry
                ranked.rank = index + 1
                return ranked
            }
        }

        func fetchSpotlights(period: LeaderboardPeriod, communityId: UUID?) async throws -> [SpotlightEntry] { [] }
    }

    /// Loaded as it is built, so a preview snapshot taken right after the first render has rows.
    @MainActor
    static func leaderboardViewModel(communityId: UUID) -> LeaderboardViewModel {
        let viewModel = LeaderboardViewModel(leaderboardService: Leaderboard(), communityId: communityId)
        Task { await viewModel.loadLeaderboard() }
        return viewModel
    }

    /// An in-memory store holding the community's open requests and posts.
    @MainActor
    static func container(communityId: UUID) -> ModelContainer {
        let container = try! ModelContainer(
            for: SDRide.self, SDFavor.self, SDTownHallPost.self,
            configurations: ModelConfiguration(isStoredInMemoryOnly: true)
        )
        let context = container.mainContext
        let poster = UUID()
        let today = Calendar.current.startOfDay(for: Date())
        context.insert(SDRide(
            id: UUID(), userId: poster, date: today, time: "09:30:00", pickup: "Pickup", destination: "Destination",
            posterName: "Sam Neighbor", communityId: communityId
        ))
        context.insert(SDFavor(
            id: UUID(), userId: poster, title: "Help moving a couch", location: "Location",
            date: today.addingTimeInterval(86_400), posterName: "Pat Quinn", communityId: communityId
        ))
        context.insert(SDTownHallPost(
            id: UUID(), userId: poster, content: "Welcome to the group! Say hello and tell us what you could use help with.",
            createdAt: Date().addingTimeInterval(-7_200), authorName: "Sam Neighbor", commentCount: 3, communityId: communityId
        ))
        context.insert(SDTownHallPost(
            id: UUID(), userId: poster, content: "Anyone driving to the airport on Friday morning?",
            createdAt: Date().addingTimeInterval(-86_400), authorName: "Dana Rivera", commentCount: 1, communityId: communityId
        ))
        return container
    }

    static func preview(id: UUID, policy: CommunityJoinPolicy) -> CommunityPreview {
        let poster = UUID()
        let date = Calendar.current.startOfDay(for: Date())
        return CommunityPreview(
            community: .init(
                id: id, name: "Ballard Neighbors", description: nil, joinPolicy: policy.rawValue, isPublic: true,
                isDefault: false, memberCount: 12, timezone: "America/Los_Angeles"
            ),
            requests: [
                .init(type: "ride", id: UUID(), title: nil, date: date, time: "09:30:00", timezone: "America/Los_Angeles",
                      seats: 2, posterId: poster, posterName: "Sam Neighbor", posterAvatarUrl: nil),
                .init(type: "favor", id: UUID(), title: "Help moving a couch", date: date.addingTimeInterval(86_400), time: nil,
                      timezone: nil, seats: nil, posterId: poster, posterName: "Pat Quinn", posterAvatarUrl: nil)
            ],
            posts: [
                .init(id: UUID(), type: nil, title: nil, content: "Welcome to the group! Say hello and tell us what you could use help with.",
                      createdAt: Date().addingTimeInterval(-7_200), authorId: poster, authorName: "Sam Neighbor",
                      authorAvatarUrl: nil, commentCount: 3)
            ]
        )
    }

    /// A page for `communityId` whose memberships are `rows` (empty: the person is not a member).
    /// `isTownHallCommunity`: the community is the Town Hall tab's, so member mode shows its posts.
    @MainActor
    static func page(
        communityId: UUID,
        memberships rows: [CommunityMembership],
        preview: CommunityPreview?,
        isGuest: Bool = false,
        isTownHallCommunity: Bool = true
    ) -> some View {
        let service = PreviewCommunityService()
        service.memberships = rows
        service.preview = preview
        let context = CommunityContext(service: service, defaults: UserDefaults(suiteName: "preview")!)
        context.debugSetMemberships(rows)
        context.communityTabId = isTownHallCommunity ? communityId : nil
        return NavigationStack {
            CommunityPageView(
                viewModel: CommunityPageViewModel(
                    communityId: communityId, service: service, communityContext: context, isGuest: { isGuest }
                ),
                communitiesViewModel: MyCommunitiesViewModel(service: service, communityContext: context, refreshDashboard: { _ in }),
                leaderboardViewModel: leaderboardViewModel(communityId: communityId)
            )
        }
        .modelContainer(container(communityId: communityId))
        .environment(AppState())
    }
}

#Preview("Member, owner with 3 requests") {
    let id = UUID()
    let owned = CommunityMembership(
        communityId: id, name: "Ballard Neighbors", description: nil, role: .owner, status: .active, isPrimary: false,
        joinPolicy: "approve", isPublic: true, isDefault: false, membersCanInvite: true, timezone: "America/Los_Angeles",
        canInvite: true, memberCount: 12, pendingCount: 3, notificationsMuted: false, mutedUntil: nil,
        joinedAt: Date(timeIntervalSince1970: 1_790_000_000), activatedAt: Date(timeIntervalSince1970: 1_790_000_100)
    )
    return CommunityPagePreviewData.page(communityId: id, memberships: [owned], preview: nil)
}

#Preview("Member, not the Town Hall community") {
    let id = UUID()
    let member = CommunityMembership(
        communityId: id, name: "Ballard Neighbors", description: nil, role: .member, status: .active, isPrimary: false,
        joinPolicy: "approve", isPublic: true, isDefault: false, membersCanInvite: true, timezone: "America/Los_Angeles",
        canInvite: true, memberCount: 12, pendingCount: nil, notificationsMuted: false, mutedUntil: nil,
        joinedAt: Date(timeIntervalSince1970: 1_790_000_000), activatedAt: Date(timeIntervalSince1970: 1_790_000_100)
    )
    return CommunityPagePreviewData.page(communityId: id, memberships: [member], preview: nil, isTownHallCommunity: false)
}

#Preview("Visitor, ask to join") {
    let id = UUID()
    return CommunityPagePreviewData.page(
        communityId: id, memberships: [], preview: CommunityPagePreviewData.preview(id: id, policy: .approve)
    )
}

#Preview("Visitor, invite only") {
    let id = UUID()
    return CommunityPagePreviewData.page(
        communityId: id, memberships: [], preview: CommunityPagePreviewData.preview(id: id, policy: .invite)
    )
}

#Preview("Guest visitor") {
    let id = UUID()
    return CommunityPagePreviewData.page(
        communityId: id, memberships: [], preview: CommunityPagePreviewData.preview(id: id, policy: .open), isGuest: true
    )
}

#Preview("Waiting for approval") {
    let id = UUID()
    let pending = CommunityMembership(
        communityId: id, name: "Fremont Families", description: nil, role: .member, status: .pending, isPrimary: false,
        joinPolicy: "approve", isPublic: true, isDefault: false, membersCanInvite: true, timezone: "America/Los_Angeles",
        canInvite: false, memberCount: 8, pendingCount: nil, notificationsMuted: false, mutedUntil: nil,
        joinedAt: Date(timeIntervalSince1970: 1_790_000_000), activatedAt: nil
    )
    return CommunityPagePreviewData.page(communityId: id, memberships: [pending], preview: nil)
}

#Preview("No longer available") {
    CommunityPagePreviewData.page(communityId: UUID(), memberships: [], preview: nil)
}
#endif
