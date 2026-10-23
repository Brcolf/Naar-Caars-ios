//
//  CommunityPageViewModel.swift
//  NaarsCars
//
//  The community page: what a member, a pending member and a visitor see of one community
//

internal import Combine
import Foundation

/// What the community page shows.
enum CommunityPageMode: Equatable {
    /// Nothing known yet, or the preview is being read.
    case loading
    /// An active member: the page is built from the membership row and the local store.
    case member(CommunityMembership)
    /// Waiting for an admin's approval.
    case pending(CommunityMembership)
    /// Anyone else (a signed-in non-member or a guest): the listed community's preview.
    case visitor(CommunityPreview)
    /// The community was merged into another one the person may see (`get_community_preview`'s
    /// `merged` refusal): the page points to the survivor.
    case merged(survivorId: UUID, survivorName: String)
    /// The community is not listed (or no longer exists) and the person is not a member.
    case unavailable
    /// The preview could not be read.
    case failed
}

/// What the visitor's bottom bar offers. The server decides every join; this only picks the words
/// and the sheet.
enum CommunityVisitorAction: Equatable {
    case signUp
    case askToJoin(PublicCommunity)
    case enterInviteCode
    case waitingForApproval
}

@MainActor
final class CommunityPageViewModel: ObservableObject {
    let communityId: UUID

    @Published private(set) var mode: CommunityPageMode = .loading
    /// A refresh that failed while the preview is on screen; the view shows it as a banner.
    @Published var bannerMessage: String?
    /// The authors member mode leaves out of the local requests and posts. Read in `start()` and
    /// again on `.blockedUsersDidChange` (a block or unblock made anywhere).
    @Published private(set) var blockedAuthorIds: Set<UUID> = []
    /// The community's service area, shown under the rule sentence. A visitor's comes with the
    /// preview; a member's is read once per page (`fetchServiceArea`), and a failed read leaves it nil.
    @Published private(set) var area: ServiceArea?

    private let service: any CommunityServiceProtocol
    private let communityContext: CommunityContext
    private let isGuestProvider: @MainActor () -> Bool
    private let selectTab: @MainActor (NavigationCoordinator.Tab) -> Void
    private let blockedAuthorIdsProvider: @MainActor () -> Set<UUID>
    private let notificationCenter: NotificationCenter
    private var blockedUsersCancellable: AnyCancellable?
    /// Each `load()` takes the next number; a result that comes back after a newer load started
    /// is dropped, so a slow preview cannot overwrite the page a later membership change built.
    private var loadGeneration = 0
    /// When a preview was last read successfully (for `loadIfStale()`).
    private var lastPreviewRead: Date?
    /// A member's area was read (with or without an area); the page does not read it again.
    private var memberAreaRead = false
    /// The community's own name as this page last knew it (a member row, a preview, the listed
    /// communities), kept for the merged sentence: the `merged` refusal names only the survivor.
    private var knownName: String?

    /// - Parameter isGuest: Defaults to "the injected `authService` has no signed-in user".
    /// - Parameter selectTab: Defaults to setting `NavigationCoordinator.shared.selectedTab`.
    /// - Parameter blockedAuthorIds: Defaults to `MessageService.shared.cachedBlockedUserIds`, as
    ///   `TownHallService` reads it. Not read before `start()`.
    init(
        communityId: UUID,
        service: any CommunityServiceProtocol = CommunityService.shared,
        communityContext: CommunityContext? = nil,
        authService: any AuthServiceProtocol = AuthService.shared,
        isGuest: (@MainActor () -> Bool)? = nil,
        selectTab: (@MainActor (NavigationCoordinator.Tab) -> Void)? = nil,
        blockedAuthorIds: (@MainActor () -> Set<UUID>)? = nil,
        notificationCenter: NotificationCenter = .default
    ) {
        self.communityId = communityId
        self.service = service
        self.communityContext = communityContext ?? .shared
        self.isGuestProvider = isGuest ?? { [authService] in authService.currentUserId == nil }
        self.selectTab = selectTab ?? { NavigationCoordinator.shared.selectedTab = $0 }
        self.blockedAuthorIdsProvider = blockedAuthorIds ?? { MessageService.shared.cachedBlockedUserIds }
        self.notificationCenter = notificationCenter
    }

    /// Reads the blocked authors and follows `.blockedUsersDidChange` from then on. Called from the
    /// view's `.task`, never from `init`; safe to call again (it subscribes once).
    func start() {
        guard blockedUsersCancellable == nil else { return }
        blockedAuthorIds = blockedAuthorIdsProvider()
        blockedUsersCancellable = notificationCenter.publisher(for: .blockedUsersDidChange)
            .sink { [weak self] _ in
                Task { @MainActor in
                    self?.reloadBlockedAuthors()
                }
            }
    }

    private func reloadBlockedAuthors() {
        let ids = blockedAuthorIdsProvider()
        // Published only when the set changes, so an unrelated notification redraws nothing.
        if ids != blockedAuthorIds { blockedAuthorIds = ids }
    }

    // MARK: - Derived state

    var isGuest: Bool { isGuestProvider() }

    /// The person's own row for this community (active or pending). Reading it in a view body
    /// tracks the context, so the page reloads when a join, a leave or a mute changes it.
    var currentMembership: CommunityMembership? {
        communityContext.membership(for: communityId)
    }

    /// An owner or admin of this community, or a platform admin (the server decides every action).
    var isAdmin: Bool {
        communityContext.isAdmin(of: communityId)
    }

    var communityName: String? {
        switch mode {
        case .member(let row), .pending(let row): return row.name
        case .visitor(let preview): return preview.community.name
        case .merged: return knownName
        case .loading, .unavailable, .failed: return nil
        }
    }

    /// "<this> is now part of <survivor>." in merged mode; the plain "now part of another community"
    /// sentence when the page never knew this community's name (the button still names the survivor).
    var mergedMessage: String? {
        guard case .merged(_, let survivorName) = mode else { return nil }
        guard let knownName else { return "community_error_merged".localized }
        return String(format: "community_page_merged".localized, knownName, survivorName)
    }

    var memberCount: Int? {
        switch mode {
        case .member(let row), .pending(let row): return row.memberCount
        case .visitor(let preview): return preview.community.memberCount
        case .loading, .merged, .unavailable, .failed: return nil
        }
    }

    /// Whether member mode leaves this author's requests and posts out.
    func isBlocked(_ userId: UUID) -> Bool {
        blockedAuthorIds.contains(userId)
    }

    /// Whether anyone can find the community in Explore.
    var isListed: Bool {
        switch mode {
        case .member(let row), .pending(let row): return row.isPublic
        case .visitor(let preview): return preview.community.isPublic
        case .loading, .merged, .unavailable, .failed: return false
        }
    }

    var policy: CommunityJoinPolicy? {
        switch mode {
        case .member(let row), .pending(let row): return CommunityJoinPolicy(rawValue: row.joinPolicy)
        case .visitor(let preview): return CommunityJoinPolicy(rawValue: preview.community.joinPolicy)
        case .loading, .merged, .unavailable, .failed: return nil
        }
    }

    var visitorAction: CommunityVisitorAction? {
        switch mode {
        case .pending:
            return .waitingForApproval
        case .visitor(let preview):
            if isGuest { return .signUp }
            if policy == .invite { return .enterInviteCode }
            // Approve, open or a policy this build does not know: the request goes to the server.
            let community = preview.community
            return .askToJoin(PublicCommunity(
                id: community.id,
                name: community.name,
                description: community.description,
                joinPolicy: community.joinPolicy,
                isDefault: community.isDefault
            ))
        case .loading, .member, .merged, .unavailable, .failed:
            return nil
        }
    }

    /// Whether member mode can show this community's recent posts from the local store. The store
    /// holds Town Hall posts of the Town Hall tab's community only (`TownHallSyncEngine` syncs that
    /// community's first page and prunes every other post), so for any other community an empty
    /// list would wrongly read as "no posts yet"; the page offers that community's Town Hall instead.
    var showsLocalTownHallPosts: Bool {
        communityContext.communityTabId == communityId
    }

    // MARK: - Actions

    /// "See this community's Town Hall": makes this community the Town Hall tab's community, as the
    /// title menu does, then selects the tab (in that order, so the tab's badge clear reads this
    /// community). The feed reloads itself through the coordinator when its community changes.
    /// Only for an active membership; anything else is a no-op.
    func openTownHall() {
        guard communityContext.membership(for: communityId)?.status == .active else { return }
        communityContext.communityTabId = communityId
        selectTab(.townHall)
    }

    // MARK: - Load

    /// Pull-to-refresh. A member's mode comes from the membership row, which a refresh does not
    /// change. Anyone else may have become a member since the page loaded (an approval, a join made
    /// elsewhere), so a signed-in non-member reads the memberships again first; the reload then
    /// decides the mode from the new row. A guest has no memberships to read.
    func refresh() async {
        if case .member = mode {
            // The row decides; nothing to read.
        } else if !isGuest {
            await communityContext.refreshMemberships()
        }
        await load()
    }

    /// The page's appearance. A visitor's preview that was read within
    /// `Constants.Timing.refreshStalenessWindow` is shown as it is: returning from a profile or a
    /// sheet costs no request. Everything else (first appearance, a membership that changed,
    /// an older preview) loads.
    func loadIfStale() async {
        if currentMembership == nil, case .visitor = mode, let lastPreviewRead,
           Date().timeIntervalSince(lastPreviewRead) < Constants.Timing.refreshStalenessWindow {
            return
        }
        await load()
    }

    /// A membership decides the mode with no request; anyone else reads the listed preview.
    /// A cancelled read changes nothing. Safe to call again (Retry, pull-to-refresh, and after the
    /// person's membership changed).
    func load() async {
        loadGeneration += 1
        let generation = loadGeneration
        rememberName()

        if let row = communityContext.membership(for: communityId) {
            switch row.status {
            case .active:
                mode = .member(row)
                bannerMessage = nil
                await loadMemberAreaIfNeeded(generation: generation)
                return
            case .pending:
                mode = .pending(row)
                bannerMessage = nil
                return
            case .left, .removed:
                break
            }
        }

        // A refresh keeps the preview on screen; anything else starts from the skeleton.
        let showsPreview: Bool
        if case .visitor = mode { showsPreview = true } else { showsPreview = false }
        if !showsPreview { mode = .loading }

        do {
            let preview = try await service.fetchCommunityPreview(communityId: communityId)
            guard generation == loadGeneration else { return }
            mode = .visitor(preview)
            area = preview.community.area
            lastPreviewRead = Date()
            bannerMessage = nil
        } catch is CancellationError {
            return
        } catch let error as URLError where error.code == .cancelled {
            return
        } catch let refusal as CommunityRPCError where refusal.code == .notListed {
            guard generation == loadGeneration else { return }
            mode = .unavailable
            bannerMessage = nil
        } catch let refusal as CommunityRPCError where refusal.code == .merged {
            guard generation == loadGeneration else { return }
            // A survivor the caller may not see is not named: the page is then simply unavailable.
            if let survivorId = refusal.mergedIntoId, let survivorName = refusal.mergedIntoName {
                mode = .merged(survivorId: survivorId, survivorName: survivorName)
            } else {
                mode = .unavailable
            }
            bannerMessage = nil
        } catch {
            guard generation == loadGeneration else { return }
            AppLogger.warning("community", "Community preview load failed: \(error.localizedDescription)")
            if showsPreview {
                bannerMessage = "community_page_load_failed".localized
            } else {
                mode = .failed
            }
        }
    }

    /// Keeps the name the page shows now, else the person's row or the listed community's, for a
    /// later merged answer (which carries only the survivor's name).
    private func rememberName() {
        let listedName = communityContext.listedCommunities.first { $0.id == communityId }?.name
        if let name = communityName ?? communityContext.name(for: communityId) ?? listedName {
            knownName = name
        }
    }

    /// One `fetchServiceArea` per page: `loadIfStale()` runs `load()` on every appearance of a
    /// member's page, and the area changes only when the owner moves it. A failure is quiet (the
    /// page reads without the area) and the next load tries again.
    private func loadMemberAreaIfNeeded(generation: Int) async {
        guard !memberAreaRead else { return }
        do {
            let stored = try await service.fetchServiceArea(communityId: communityId)
            guard generation == loadGeneration else { return }
            area = stored
            memberAreaRead = true
        } catch is CancellationError {
            return
        } catch let error as URLError where error.code == .cancelled {
            return
        } catch {
            AppLogger.warning("community", "Community area load failed: \(error.localizedDescription)")
        }
    }

    // MARK: - Local store (member mode)

    /// The community's live requests from rows already in the local store, with the server's
    /// preview rules (`get_community_preview`): open, unclaimed, not hidden, from today on,
    /// soonest first (a request with no time after the timed ones that day), at most
    /// `Constants.Community.pagePreviewRequests`. Addresses are not carried.
    static func localRequests(
        rides: [SDRide],
        favors: [SDFavor],
        communityId: UUID,
        now: Date = Date(),
        calendar: Calendar = .current,
        isBlocked: (UUID) -> Bool
    ) -> [CommunityPreview.Request] {
        let today = calendar.startOfDay(for: now)
        let unnamed = "community_former_member".localized

        let rideRows: [CommunityPreview.Request] = rides
            .filter {
                $0.communityId == communityId && $0.status == RideStatus.open.rawValue
                    && $0.claimedBy == nil && $0.hiddenAt == nil
                    && calendar.startOfDay(for: $0.date) >= today && !isBlocked($0.userId)
            }
            .map {
                CommunityPreview.Request(
                    type: "ride", id: $0.id, title: nil, date: $0.date, time: $0.time, timezone: $0.timezone,
                    seats: $0.seats, posterId: $0.userId, posterName: $0.posterName ?? unnamed,
                    posterAvatarUrl: $0.posterAvatarUrl, isExample: $0.isExample
                )
            }
        let favorRows: [CommunityPreview.Request] = favors
            .filter {
                $0.communityId == communityId && $0.status == FavorStatus.open.rawValue
                    && $0.claimedBy == nil && $0.hiddenAt == nil
                    && calendar.startOfDay(for: $0.date) >= today && !isBlocked($0.userId)
            }
            .map {
                CommunityPreview.Request(
                    type: "favor", id: $0.id, title: $0.title, date: $0.date, time: $0.time, timezone: $0.timezone,
                    seats: nil, posterId: $0.userId, posterName: $0.posterName ?? unnamed,
                    posterAvatarUrl: $0.posterAvatarUrl, isExample: $0.isExample
                )
            }

        let sorted = (rideRows + favorRows).sorted { a, b in
            let dayA = calendar.startOfDay(for: a.date)
            let dayB = calendar.startOfDay(for: b.date)
            if dayA != dayB { return dayA < dayB }
            switch (a.time, b.time) {
            case let (timeA?, timeB?) where timeA != timeB: return timeA < timeB
            case (nil, .some): return false
            case (.some, nil): return true
            default: return a.id.uuidString < b.id.uuidString
            }
        }
        return Array(sorted.prefix(Constants.Community.pagePreviewRequests))
    }

    /// The community's newest visible Town Hall posts from the local store, at most
    /// `Constants.Community.pagePreviewPosts`.
    static func localPosts(
        _ posts: [SDTownHallPost],
        communityId: UUID,
        isBlocked: (UUID) -> Bool
    ) -> [CommunityPreview.Post] {
        let unnamed = "community_former_member".localized
        let newestFirst = posts
            .filter { $0.communityId == communityId && $0.hiddenAt == nil && !isBlocked($0.userId) }
            .sorted { ($0.createdAt, $0.id.uuidString) > ($1.createdAt, $1.id.uuidString) }
        return newestFirst.prefix(Constants.Community.pagePreviewPosts).map {
            CommunityPreview.Post(
                id: $0.id, type: $0.type, title: $0.title, content: $0.content, createdAt: $0.createdAt,
                authorId: $0.userId, authorName: $0.authorName ?? unnamed, authorAvatarUrl: $0.authorAvatarUrl,
                commentCount: $0.commentCount
            )
        }
    }

    // MARK: - Text

    /// The day of a request, with its time when it has one ("Oct 23 at 9:30 AM"). The day is the
    /// stored date in the device's zone (the database date arrives as the device's midnight) and the
    /// time is the database's `HH:mm:ss` text, shown as written.
    static func whenText(date: Date, time: String?, calendar: Calendar = .current) -> String {
        let parts = time?.trimmingCharacters(in: .whitespaces).split(separator: ":").compactMap { Int($0) } ?? []
        guard parts.count >= 2, (0...23).contains(parts[0]), (0...59).contains(parts[1]),
              let moment = calendar.date(bySettingHour: parts[0], minute: parts[1], second: 0, of: date) else {
            return DateFormatters.monthDayFormatter.string(from: date)
        }
        return DateFormatters.monthDayTimeFormatter.string(from: moment)
    }
}
