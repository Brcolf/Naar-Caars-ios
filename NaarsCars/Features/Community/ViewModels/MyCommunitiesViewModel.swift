//
//  MyCommunitiesViewModel.swift
//  NaarsCars
//
//  Explore's content: the member's communities, the listed communities, and the follow-ups of a
//  leave, a create or a join
//

internal import Combine
import Foundation
import SwiftData

/// What leaving a community will do to the member's requests and claims there, estimated from
/// the local cache with the server's `unwind_member_requests` rules (20261017_0004, steps 1-3).
/// The sheet shows it before the leave; the server decides what actually happens.
struct LeaveConsequences: Equatable {
    /// Claims the member made on confirmed requests; they reopen.
    let reopened: Int
    /// The member's own unclaimed requests that are not completed; they are deleted.
    let removed: Int
    /// The member's own claimed requests that are not completed; the helper is told and they are deleted.
    let cancelled: Int

    static let none = LeaveConsequences(reopened: 0, removed: 0, cancelled: 0)

    var isEmpty: Bool { reopened == 0 && removed == 0 && cancelled == 0 }

    static func estimate(rides: [SDRide], favors: [SDFavor], userId: UUID, communityId: UUID) -> LeaveConsequences {
        typealias Row = (userId: UUID, claimedBy: UUID?, status: String)
        let rows: [Row] =
            rides.filter { $0.communityId == communityId }.map { ($0.userId, $0.claimedBy, $0.status) } +
            favors.filter { $0.communityId == communityId }.map { ($0.userId, $0.claimedBy, $0.status) }

        var reopened = 0
        var removed = 0
        var cancelled = 0
        for row in rows {
            if row.claimedBy == userId && row.status == "confirmed" {
                reopened += 1
            }
            guard row.userId == userId, row.status != "completed" else { continue }
            if row.claimedBy == nil {
                removed += 1
            } else {
                cancelled += 1
            }
        }
        return LeaveConsequences(reopened: reopened, removed: removed, cancelled: cancelled)
    }
}

/// What the Leave sheet asks for.
enum LeavePlan: Equatable {
    /// A request still waiting for approval.
    case withdrawRequest
    case leave(LeaveConsequences)
    /// The only member is the owner: leaving closes (archives) the community.
    case closesCommunity(LeaveConsequences)
}

/// What the owned-community limit row on My communities shows.
enum LimitOffer: Equatable {
    case requestPending(requestedMax: Int)
    case canRequest(currentMax: Int, ownedCount: Int)
}

@MainActor
final class MyCommunitiesViewModel: ObservableObject {
    @Published private(set) var limits: CommunityLimits?
    @Published private(set) var isLoading = false
    @Published var toastMessage: String?
    @Published var errorMessage: String?
    /// The community a leave or mute is running for; one action at a time.
    @Published private(set) var busyCommunityId: UUID?
    /// Set instead of `errorMessage` when a leave is refused with `last_owner`: the view offers
    /// to choose a new owner on the community's Members screen.
    @Published var newOwnerNeededFor: CommunityMembership?
    /// True when the last listed-communities load failed (a cancelled one changes nothing). The
    /// rows already on screen stay; the view shows a banner with Retry, or a Retry row when the
    /// section would otherwise be empty.
    @Published private(set) var listedLoadFailed = false
    /// True once a listed-communities load has succeeded: before that an empty list means "not
    /// loaded yet", not "no listed communities".
    @Published private(set) var hasLoadedListed = false

    private let service: any CommunityServiceProtocol
    private let communityContext: CommunityContext
    private let authService: any AuthServiceProtocol
    private let refreshDashboard: @MainActor (String) async -> Void
    private let isGuestProvider: @MainActor () -> Bool
    private let now: () -> Date
    /// When `load()` last read the listed list successfully (for `loadIfStale()`).
    private var lastSuccessfulLoad: Date?
    private var modelContext: ModelContext?

    /// - Parameter isGuest: Defaults to "the injected `authService` has no signed-in user".
    init(
        service: any CommunityServiceProtocol = CommunityService.shared,
        communityContext: CommunityContext? = nil,
        authService: any AuthServiceProtocol = AuthService.shared,
        refreshDashboard: @escaping @MainActor (String) async -> Void = {
            _ = await RefreshCoordinator.shared.forceFullRefreshAndWait(.dashboard, trigger: $0)
        },
        isGuest: (@MainActor () -> Bool)? = nil,
        now: @escaping () -> Date = Date.init
    ) {
        self.service = service
        self.communityContext = communityContext ?? .shared
        self.authService = authService
        self.refreshDashboard = refreshDashboard
        self.isGuestProvider = isGuest ?? { [authService] in authService.currentUserId == nil }
        self.now = now
    }

    /// Set up the model context the Leave counts are read from.
    func setup(modelContext: ModelContext) {
        self.modelContext = modelContext
    }

    // MARK: - Memberships

    var active: [CommunityMembership] { communityContext.activeMemberships }
    var pending: [CommunityMembership] { communityContext.pendingMemberships }

    var hasLoadedMemberships: Bool { communityContext.hasLoadedMemberships }

    /// A guest has no memberships, no limits and no skeleton; only the listed communities load.
    var isGuest: Bool { isGuestProvider() }

    /// The listed communities the person is not already in: every one except an active or a
    /// pending membership. A community the person left or was removed from stays listed.
    var listedToShow: [PublicCommunity] {
        let joined = Set((active + pending).map(\.communityId))
        return communityContext.listedCommunities.filter { !joined.contains($0.id) }
    }

    func isAdmin(of communityId: UUID) -> Bool {
        communityContext.isAdmin(of: communityId)
    }

    func isMuted(_ membership: CommunityMembership, now: Date = Date()) -> Bool {
        if membership.notificationsMuted { return true }
        if let mutedUntil = membership.mutedUntil, mutedUntil > now { return true }
        return false
    }

    /// A pending limit request shows until decided; otherwise the offer shows at the limit.
    var limitOffer: LimitOffer? {
        guard let limits else { return nil }
        if let request = limits.latestRequest, request.status == .pending {
            return .requestPending(requestedMax: request.requestedMax)
        }
        if limits.ownedCount >= limits.maxOwned && OwnedLimitRequestViewModel.canRequestMore(currentMax: limits.maxOwned) {
            return .canRequest(currentMax: limits.maxOwned, ownedCount: limits.ownedCount)
        }
        return nil
    }

    // MARK: - Load

    /// A tab appearance: shows what is stored and reads again only when the last successful
    /// `load()` is older than `Constants.Timing.refreshStalenessWindow`. Pull-to-refresh and
    /// Retry call `load()`, which always reads.
    func loadIfStale() async {
        // A member whose memberships never loaded (the read failed quietly) has nothing stored to show.
        let hasStoredState = isGuest || hasLoadedMemberships
        if hasStoredState, let lastSuccessfulLoad,
           now().timeIntervalSince(lastSuccessfulLoad) < Constants.Timing.refreshStalenessWindow {
            return
        }
        await load()
    }

    /// A member reads the memberships, the owned-community limits and the listed communities,
    /// in that order (the listed rows leave out the memberships, so they come last). A guest
    /// reads the listed communities only and calls no membership or limit function.
    func load() async {
        guard !isLoading else { return }
        isLoading = true
        defer { isLoading = false }

        if !isGuest {
            await communityContext.refreshMemberships()
            do {
                limits = try await service.fetchMyCommunityLimits()
            } catch {
                AppLogger.warning("community", "fetchMyCommunityLimits failed: \(error)")
                limits = nil
            }
        }

        // nil: the load was cancelled (a cancelled pull-to-refresh), which is not a failure.
        switch await communityContext.loadListedCommunities() {
        case true?:
            listedLoadFailed = false
            hasLoadedListed = true
            lastSuccessfulLoad = now()
        case false?:
            listedLoadFailed = true
        case nil:
            break
        }
    }

    // MARK: - Leave

    /// The counts come from the local request cache, so they are an estimate of what the server will do.
    func leavePlan(for membership: CommunityMembership) -> LeavePlan {
        if membership.status == .pending { return .withdrawRequest }
        let consequences = estimateConsequences(communityId: membership.communityId)
        if membership.role == .owner && membership.memberCount <= 1 && !membership.isDefault {
            return .closesCommunity(consequences)
        }
        // A sole owner with other members gets the server's last_owner refusal.
        return .leave(consequences)
    }

    /// Leaves an active community or withdraws a pending request. A success drops the row
    /// locally before the follow-up refreshes, so a refresh that fails cannot bring it back or
    /// show an error for a leave that worked. Either step may end the session's last membership
    /// (`onActiveMembershipsEmpty` → account status re-check).
    @discardableResult
    func leave(_ membership: CommunityMembership) async -> Bool {
        guard busyCommunityId == nil else { return false }
        busyCommunityId = membership.communityId
        defer { busyCommunityId = nil }
        errorMessage = nil

        do {
            _ = try await service.leaveCommunity(communityId: membership.communityId)
        } catch let refusal as CommunityRPCError {
            if refusal.code == .lastOwner {
                newOwnerNeededFor = membership
            } else {
                errorMessage = refusal.localizedMessage
            }
            return false
        } catch {
            AppLogger.error("community", "leaveCommunity failed: \(error)")
            errorMessage = "community_error_generic".localized
            return false
        }

        HapticManager.success()
        await communityContext.forgetMembership(membership.communityId)
        await communityContext.refreshMemberships()
        await refreshDashboard("leftCommunity")
        toastMessage = String(format: "community_left_toast".localized, membership.name)
        return true
    }

    // MARK: - Mute

    func setMuted(_ muted: Bool, for membership: CommunityMembership) async {
        guard busyCommunityId == nil else { return }
        busyCommunityId = membership.communityId
        defer { busyCommunityId = nil }
        errorMessage = nil

        do {
            try await service.setCommunityMuted(communityId: membership.communityId, muted: muted)
        } catch let refusal as CommunityRPCError {
            errorMessage = refusal.localizedMessage
            return
        } catch {
            AppLogger.error("community", "setCommunityMuted failed: \(error)")
            errorMessage = "community_error_generic".localized
            return
        }
        await communityContext.refreshMemberships()
    }

    // MARK: - Create and join follow-ups (run after their sheet is gone)

    func didJoin(_ result: JoinResult) async {
        await communityContext.refreshMemberships()
        let name = communityContext.name(for: result.communityId)
        switch result.status {
        case .active:
            await refreshDashboard("joinedCommunity")
            if let name { toastMessage = String(format: "community_joined_toast".localized, name) }
        case .pending:
            if let name { toastMessage = String(format: "community_requested_toast".localized, name) }
        case .left, .removed:
            break
        }
    }

    func didCreate(_ communityId: UUID) async {
        await communityContext.refreshMemberships()
        await refreshDashboard("joinedCommunity")
    }

    // MARK: - Private

    private func estimateConsequences(communityId: UUID) -> LeaveConsequences {
        guard let modelContext, let userId = authService.currentUserId else { return .none }
        do {
            let rides = try modelContext.fetch(FetchDescriptor<SDRide>())
            let favors = try modelContext.fetch(FetchDescriptor<SDFavor>())
            return LeaveConsequences.estimate(rides: rides, favors: favors, userId: userId, communityId: communityId)
        } catch {
            AppLogger.warning("community", "Leave estimate fetch failed: \(error)")
            return .none
        }
    }
}
