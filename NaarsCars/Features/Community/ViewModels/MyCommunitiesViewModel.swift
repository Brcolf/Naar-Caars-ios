//
//  MyCommunitiesViewModel.swift
//  NaarsCars
//
//  The member's communities: mute, leave, and the follow-ups of a create or a join
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

    private let service: any CommunityServiceProtocol
    private let communityContext: CommunityContext
    private let authService: any AuthServiceProtocol
    private let refreshDashboard: @MainActor (String) async -> Void
    private var modelContext: ModelContext?

    init(
        service: any CommunityServiceProtocol = CommunityService.shared,
        communityContext: CommunityContext? = nil,
        authService: any AuthServiceProtocol = AuthService.shared,
        refreshDashboard: @escaping @MainActor (String) async -> Void = {
            _ = await RefreshCoordinator.shared.forceFullRefreshAndWait(.dashboard, trigger: $0)
        }
    ) {
        self.service = service
        self.communityContext = communityContext ?? .shared
        self.authService = authService
        self.refreshDashboard = refreshDashboard
    }

    /// Set up the model context the Leave counts are read from.
    func setup(modelContext: ModelContext) {
        self.modelContext = modelContext
    }

    // MARK: - Memberships

    var active: [CommunityMembership] { communityContext.activeMemberships }
    var pending: [CommunityMembership] { communityContext.pendingMemberships }

    /// Every membership id, active or pending (excluded from the public list in Join).
    var allMembershipIds: Set<UUID> { Set(communityContext.memberships.map(\.communityId)) }

    var hasLoadedMemberships: Bool { communityContext.hasLoadedMemberships }

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

    func load() async {
        guard !isLoading else { return }
        isLoading = true
        defer { isLoading = false }

        await communityContext.refreshMemberships()
        do {
            limits = try await service.fetchMyCommunityLimits()
        } catch {
            AppLogger.warning("community", "fetchMyCommunityLimits failed: \(error)")
            limits = nil
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
            errorMessage = refusal.localizedMessage
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
