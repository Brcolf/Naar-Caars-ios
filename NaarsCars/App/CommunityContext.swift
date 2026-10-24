//
//  CommunityContext.swift
//  NaarsCars
//
//  The signed-in member's communities and the community each screen shows
//

import Foundation
import Observation

/// Holds the member's communities, the Community tab's community, the Requests narrow and the
/// last community posted to. Restored synchronously from UserDefaults before the sync engines
/// start, refreshed from `get_my_memberships` off the launch path, and cleared on sign-out.
///
/// A nil community means "no community filter" everywhere; nothing waits for this to load.
@Observable
@MainActor
final class CommunityContext {

    // MARK: - Singleton

    static let shared = CommunityContext()

    // MARK: - Persistence keys (suffixed with the user id)

    static let tabKeyPrefix = "community.tab."
    static let requestsScopeKeyPrefix = "community.requestsScope."
    static let lastPostedKeyPrefix = "community.lastPosted."

    // MARK: - Dependencies

    private let service: any CommunityServiceProtocol
    /// Reads the merges that touched the member's memberships; nil makes no merge lookup.
    private let mergeService: (any CommunityMergeServiceProtocol)?
    private let defaults: UserDefaults
    private let now: () -> Date
    private let platformAdminProvider: @MainActor () -> Bool

    // MARK: - Session

    /// The user whose keys were read by `restore(for:)`; assignments persist only while it is set.
    @ObservationIgnored private var restoredUserId: UUID?
    /// When the last membership fetch started (for `refreshMembershipsIfStale`).
    @ObservationIgnored private var lastRefreshAttempt: Date?

    /// Called after a successful load that returned no active membership.
    @ObservationIgnored var onActiveMembershipsEmpty: (@MainActor () async -> Void)?

    // MARK: - Observed state

    /// Active and pending rows, in server order.
    private(set) var memberships: [CommunityMembership] = []

    /// Set by the first successful load for the restored user; cleared when another user is
    /// restored and on sign-out.
    private(set) var hasLoadedMemberships = false

    /// A session is restored and its first membership load has not returned yet (cold start:
    /// the load runs off the launch path). False for a guest, who has no memberships.
    var isAwaitingMemberships: Bool {
        restoredUserId != nil && !hasLoadedMemberships
    }

    var activeMemberships: [CommunityMembership] {
        memberships.filter { $0.status == .active }
    }

    var hasMultipleCommunities: Bool {
        activeMemberships.count > 1
    }

    // communityTabId, requestsScope and lastPostedCommunityId use equality-guarded setters
    // (the NavigationCoordinator pattern) so a same-value assignment does not invalidate views.

    @ObservationIgnored private var _communityTabId: UUID?
    /// The Community tab's community. Nil means no filter.
    var communityTabId: UUID? {
        get {
            access(keyPath: \.communityTabId)
            return _communityTabId
        }
        set {
            guard setCommunityTabId(newValue) else { return }
            persistCommunityTabId()
        }
    }

    @ObservationIgnored private var _requestsScope: RequestsScope = .all
    /// The Requests narrow. `.all` shows every community.
    var requestsScope: RequestsScope {
        get {
            access(keyPath: \.requestsScope)
            return _requestsScope
        }
        set {
            guard setRequestsScope(newValue) else { return }
            persistRequestsScope()
        }
    }

    @ObservationIgnored private var _lastPostedCommunityId: UUID?
    /// The community of the member's last post or request.
    var lastPostedCommunityId: UUID? {
        get {
            access(keyPath: \.lastPostedCommunityId)
            return _lastPostedCommunityId
        }
        set {
            guard setLastPostedCommunityId(newValue) else { return }
            persistLastPostedCommunityId()
        }
    }

    /// Communities anyone may find (`fetchPublicCommunities`), loaded by `loadListedCommunities()`.
    private(set) var listedCommunities: [PublicCommunity] = []

    // MARK: - Init

    /// - Parameter mergeService: Defaults to `service` when it also answers the merge calls
    ///   (`CommunityService` does); otherwise no merge lookup is made.
    init(
        service: any CommunityServiceProtocol = CommunityService.shared,
        mergeService: (any CommunityMergeServiceProtocol)? = nil,
        defaults: UserDefaults = .standard,
        now: @escaping () -> Date = Date.init,
        platformAdminProvider: @escaping @MainActor () -> Bool = { AuthService.shared.currentProfile?.isAdmin == true }
    ) {
        self.service = service
        self.mergeService = mergeService ?? (service as? any CommunityMergeServiceProtocol)
        self.defaults = defaults
        self.now = now
        self.platformAdminProvider = platformAdminProvider
    }

    // MARK: - Lookups

    /// The community's name, or nil for a nil or unknown id.
    func name(for communityId: UUID?) -> String? {
        guard let communityId else { return nil }
        return memberships.first { $0.communityId == communityId }?.name
    }

    /// The join policy of a community: the member's own row first, else the listed community's.
    /// Nil for a nil id, an unknown id, or a policy this build does not know.
    func joinPolicy(for communityId: UUID?) -> CommunityJoinPolicy? {
        guard let communityId else { return nil }
        if let row = memberships.first(where: { $0.communityId == communityId }) {
            return CommunityJoinPolicy(rawValue: row.joinPolicy)
        }
        return listedCommunities.first { $0.id == communityId }.flatMap { CommunityJoinPolicy(rawValue: $0.joinPolicy) }
    }

    /// Text for a community chip: nil with one active membership, and nil when `respectingScope`
    /// is set and Requests is narrowed to one community (every card then belongs to it). A list
    /// that leaves some communities out still shows several, so it keeps its chips.
    func chipText(for communityId: UUID?, respectingScope: Bool) -> String? {
        guard hasMultipleCommunities else { return nil }
        if respectingScope, case .community = requestsScope { return nil }
        return name(for: communityId)
    }

    /// The "Post to" default (D24): the Requests narrow, else the Community tab's community,
    /// else the last community posted to, else the primary membership, else the first one;
    /// each only while it is an active membership.
    var defaultPostCommunityId: UUID? {
        let active = activeMemberships
        let activeIds = Set(active.map(\.communityId))
        let candidates: [UUID?] = [requestsScope.communityId, communityTabId, lastPostedCommunityId]
        for case let id? in candidates where activeIds.contains(id) {
            return id
        }
        return active.first(where: \.isPrimary)?.communityId ?? active.first?.communityId
    }

    // MARK: - Admin lookups

    /// True for a platform admin (`profiles.is_admin`), who may administer any community.
    var isPlatformAdmin: Bool {
        platformAdminProvider()
    }

    /// The member's row for a community, or nil for a nil or unknown id.
    func membership(for communityId: UUID?) -> CommunityMembership? {
        guard let communityId else { return nil }
        return memberships.first { $0.communityId == communityId }
    }

    /// An active owner or admin membership of the community, or a platform admin.
    /// The server decides every admin action; this only chooses what the client shows.
    func isAdmin(of communityId: UUID) -> Bool {
        if isPlatformAdmin { return true }
        guard let row = membership(for: communityId) else { return false }
        return Self.isActiveAdmin(row)
    }

    /// Memberships still waiting for an admin's approval.
    var pendingMemberships: [CommunityMembership] {
        memberships.filter { $0.status == .pending }
    }

    /// The active owner and admin memberships, in membership order (the Admin panel's communities
    /// for someone who is not a platform admin). Pending rows are left out.
    var administeredCommunities: [CommunityMembership] {
        memberships.filter(Self.isActiveAdmin)
    }

    /// True when the member owns or administers at least one community (platform admin not counted).
    var isAdminOfAnyCommunity: Bool {
        memberships.contains(where: Self.isActiveAdmin)
    }

    /// Requests to join waiting in the communities the member administers.
    var administeredPendingTotal: Int {
        memberships.filter(Self.isActiveAdmin).reduce(0) { $0 + ($1.pendingCount ?? 0) }
    }

    private static func isActiveAdmin(_ row: CommunityMembership) -> Bool {
        row.status == .active && (row.role == .owner || row.role == .admin)
    }

    // MARK: - Requests filter

    /// Includes or leaves out one active community in the Requests list (the community chips).
    /// From `.all` the community is left out; in `.excluding` it is left out or included again, and
    /// including the last left-out community is `.all`. Leaving out the last included community, a
    /// community that is not an active membership, and any change while narrowed to one community
    /// (`.community`) are no-ops. Local only; the change persists like any other assignment.
    func toggleRequestsInclusion(_ communityId: UUID) {
        let activeIds = Set(activeMemberships.map(\.communityId))
        guard activeIds.contains(communityId) else { return }

        var excluded: Set<UUID>
        switch requestsScope {
        case .community: return
        case .all: excluded = []
        case .excluding(let ids): excluded = ids.intersection(activeIds)
        }

        if excluded.contains(communityId) {
            excluded.remove(communityId)
        } else {
            excluded.insert(communityId)
            // Never leave every community out.
            guard !activeIds.isSubset(of: excluded) else { return }
        }
        requestsScope = excluded.isEmpty ? .all : .excluding(excluded)
    }

    // MARK: - Lifecycle

    /// Reads the user's three stored values. Synchronous, no network, cannot fail.
    func restore(for userId: UUID) {
        if restoredUserId != userId {
            memberships = []
            hasLoadedMemberships = false
            lastRefreshAttempt = nil
        }
        restoredUserId = userId
        let suffix = userId.uuidString
        setCommunityTabId(defaults.string(forKey: Self.tabKeyPrefix + suffix).flatMap(UUID.init(uuidString:)))
        setRequestsScope(RequestsScope(storageValue: defaults.string(forKey: Self.requestsScopeKeyPrefix + suffix)))
        setLastPostedCommunityId(defaults.string(forKey: Self.lastPostedKeyPrefix + suffix).flatMap(UUID.init(uuidString:)))
    }

    /// Loads `get_my_memberships`. Never throws; a no-op before `restore(for:)`. On failure it
    /// keeps what it had. A result that returns after sign-out (or for another user) is dropped.
    /// When the Requests filter, the Town Hall community or the last community posted to names a
    /// community that is no longer an active membership, one `get_my_community_merges` moves each
    /// merged one to its survivor (when the survivor is active) before the load is applied; a failed
    /// lookup moves nothing, and the load then normalises as usual (a narrow falls back to All).
    func refreshMemberships() async {
        guard let requestedFor = restoredUserId else { return }
        lastRefreshAttempt = now()

        let rows: [CommunityMembership]
        do {
            rows = try await service.fetchMyMemberships()
        } catch {
            guard restoredUserId == requestedFor else { return }
            AppLogger.warning("community", "Membership load failed; keeping the previous state: \(error.localizedDescription)")
            return
        }
        guard restoredUserId == requestedFor else { return }

        #if DEBUG
        let loaded = Self.appendingDebugMemberships(to: rows)
        #else
        let loaded = rows
        #endif

        let activeIds = Set(loaded.filter { $0.status == .active }.map(\.communityId))
        let survivors = await survivorsOfMergedReferences(activeIds: activeIds)
        // Re-checked on every path: a failed lookup (nil) is the likeliest sign of a sign-out.
        guard restoredUserId == requestedFor else { return }
        if let survivors { moveReferences(to: survivors) }
        apply(loaded)

        if activeMemberships.isEmpty {
            await onActiveMembershipsEmpty?()
        }
    }

    /// Loads the listed communities. True on success, false on failure (the previous list is kept),
    /// nil when the load was cancelled (a cancelled pull-to-refresh is not a failure). Never throws.
    func loadListedCommunities() async -> Bool? {
        do {
            listedCommunities = try await service.fetchPublicCommunities()
            return true
        } catch is CancellationError {
            return nil
        } catch let error as URLError where error.code == .cancelled {
            return nil
        } catch {
            AppLogger.warning("community", "Listed communities load failed; keeping the previous list: \(error.localizedDescription)")
            return false
        }
    }

    /// Drops one membership locally after the server confirmed it ended (a leave or a withdrawn
    /// request), so it disappears even when the follow-up `refreshMemberships()` fails. The tab,
    /// the Requests narrow and the last community posted to normalise as on a load. Calls
    /// `onActiveMembershipsEmpty` when no active membership is left. A no-op for an unknown id.
    func forgetMembership(_ communityId: UUID) async {
        guard memberships.contains(where: { $0.communityId == communityId }) else { return }
        apply(memberships.filter { $0.communityId != communityId })

        if activeMemberships.isEmpty {
            await onActiveMembershipsEmpty?()
        }
    }

    /// Refreshes unless the last attempt is newer than `Constants.Timing.membershipRefreshMinInterval`.
    func refreshMembershipsIfStale() async {
        if let lastRefreshAttempt,
           now().timeIntervalSince(lastRefreshAttempt) < Constants.Timing.membershipRefreshMinInterval {
            return
        }
        await refreshMemberships()
    }

    /// Clears memory and removes the stored keys of `userId` and of the restored user.
    /// `userId` may be nil when the session ended before sign-out ran.
    func resetForSignOut(userId: UUID?) {
        let restored = restoredUserId
        restoredUserId = nil
        lastRefreshAttempt = nil
        memberships = []
        listedCommunities = []
        hasLoadedMemberships = false
        setCommunityTabId(nil)
        setRequestsScope(.all)
        setLastPostedCommunityId(nil)

        var ids: [UUID] = []
        if let userId { ids.append(userId) }
        if let restored, restored != userId { ids.append(restored) }
        for id in ids {
            let suffix = id.uuidString
            defaults.removeObject(forKey: Self.tabKeyPrefix + suffix)
            defaults.removeObject(forKey: Self.requestsScopeKeyPrefix + suffix)
            defaults.removeObject(forKey: Self.lastPostedKeyPrefix + suffix)
        }
    }

    // MARK: - Private

    /// The communities the three stored references name that are not in `activeIds`.
    private func missingReferences(activeIds: Set<UUID>) -> Set<UUID> {
        var ids: Set<UUID> = []
        switch requestsScope {
        case .all: break
        case .community(let id): ids.insert(id)
        case .excluding(let excluded): ids.formUnion(excluded)
        }
        if let communityTabId { ids.insert(communityTabId) }
        if let lastPostedCommunityId { ids.insert(lastPostedCommunityId) }
        return ids.subtracting(activeIds)
    }

    /// Merged community → survivor, for the missing references whose survivor is active. nil when
    /// nothing is missing, when there is no merge service, or when the lookup fails (no call is
    /// made in the first two cases).
    private func survivorsOfMergedReferences(activeIds: Set<UUID>) async -> [UUID: UUID]? {
        let missing = missingReferences(activeIds: activeIds)
        guard !missing.isEmpty, let mergeService else { return nil }
        let merges: [CommunityMerge]
        do {
            merges = try await mergeService.fetchMyCommunityMerges()
        } catch {
            AppLogger.warning("community", "Merge lookup failed; stored filters fall back as usual: \(error.localizedDescription)")
            return nil
        }
        var survivors: [UUID: UUID] = [:]
        for merge in merges where missing.contains(merge.mergedId) && activeIds.contains(merge.survivorId) {
            survivors[merge.mergedId] = merge.survivorId
        }
        return survivors
    }

    /// Moves the Requests filter, the Town Hall community and the last community posted to from a
    /// merged community to its survivor. The assignments persist; `apply` then normalises.
    private func moveReferences(to survivors: [UUID: UUID]) {
        guard !survivors.isEmpty else { return }
        requestsScope = requestsScope.afterMerges(survivors)
        if let tab = communityTabId, let survivor = survivors[tab] {
            communityTabId = survivor
        }
        if let lastPosted = lastPostedCommunityId, let survivor = survivors[lastPosted] {
            lastPostedCommunityId = survivor
        }
    }

    /// Applies a successful load (spec §3.7 "Membership load").
    private func apply(_ rows: [CommunityMembership]) {
        memberships = rows
        let active = activeMemberships
        let activeIds = Set(active.map(\.communityId))

        if let tab = communityTabId, activeIds.contains(tab) {
            // Still a member; keep it.
        } else {
            communityTabId = active.first(where: \.isPrimary)?.communityId ?? active.first?.communityId
        }
        switch requestsScope {
        case .all:
            break
        case .community(let narrowed):
            if !activeIds.contains(narrowed) { requestsScope = .all }
        case .excluding(let ids):
            // Only active communities stay left out; none left, or every one left out, is `.all`.
            let kept = ids.intersection(activeIds)
            requestsScope = kept.isEmpty || activeIds.isSubset(of: kept) ? .all : .excluding(kept)
        }
        if let lastPosted = lastPostedCommunityId, !activeIds.contains(lastPosted) {
            lastPostedCommunityId = nil
        }
        // Last, so an observer of this flag sees the memberships and the tab already settled.
        hasLoadedMemberships = true
    }

    @discardableResult
    private func setCommunityTabId(_ value: UUID?) -> Bool {
        guard _communityTabId != value else { return false }
        withMutation(keyPath: \.communityTabId) { _communityTabId = value }
        return true
    }

    @discardableResult
    private func setRequestsScope(_ value: RequestsScope) -> Bool {
        guard _requestsScope != value else { return false }
        withMutation(keyPath: \.requestsScope) { _requestsScope = value }
        return true
    }

    @discardableResult
    private func setLastPostedCommunityId(_ value: UUID?) -> Bool {
        guard _lastPostedCommunityId != value else { return false }
        withMutation(keyPath: \.lastPostedCommunityId) { _lastPostedCommunityId = value }
        return true
    }

    private func persistCommunityTabId() {
        guard let userId = restoredUserId else { return }
        let key = Self.tabKeyPrefix + userId.uuidString
        if let id = _communityTabId {
            defaults.set(id.uuidString, forKey: key)
        } else {
            defaults.removeObject(forKey: key)
        }
    }

    private func persistRequestsScope() {
        guard let userId = restoredUserId else { return }
        defaults.set(_requestsScope.storageValue, forKey: Self.requestsScopeKeyPrefix + userId.uuidString)
    }

    private func persistLastPostedCommunityId() {
        guard let userId = restoredUserId else { return }
        let key = Self.lastPostedKeyPrefix + userId.uuidString
        if let id = _lastPostedCommunityId {
            defaults.set(id.uuidString, forKey: key)
        } else {
            defaults.removeObject(forKey: key)
        }
    }

    // MARK: - DEBUG seam

    #if DEBUG
    /// Launch argument `-debugCommunityCount N`: every successful load is padded with synthetic
    /// active memberships until there are N, to exercise the multi-community UI on one account.
    static let debugCommunityCountArgument = "-debugCommunityCount"

    /// Replaces the memberships without a fetch (previews and debugging).
    func debugSetMemberships(_ memberships: [CommunityMembership]) {
        self.memberships = memberships
        hasLoadedMemberships = true
    }

    private static func appendingDebugMemberships(to rows: [CommunityMembership]) -> [CommunityMembership] {
        let arguments = ProcessInfo.processInfo.arguments
        guard let index = arguments.firstIndex(of: debugCommunityCountArgument),
              index + 1 < arguments.count,
              let target = Int(arguments[index + 1]) else { return rows }

        var result = rows
        var activeCount = rows.filter { $0.status == .active }.count
        while activeCount < target {
            activeCount += 1
            let name = activeCount == 3
                ? "Debug Community With A Deliberately Long Name For Truncation"
                : "Debug Community \(activeCount)"
            let id = UUID(uuidString: String(format: "DEB00000-0000-4000-8000-%012d", activeCount))!
            result.append(CommunityMembership(
                communityId: id,
                name: name,
                description: nil,
                role: .member,
                status: .active,
                isPrimary: false,
                joinPolicy: "invite",
                isPublic: false,
                isDefault: false,
                membersCanInvite: true,
                timezone: TimeZone.current.identifier,
                canInvite: true,
                memberCount: 1,
                pendingCount: nil,
                notificationsMuted: false,
                mutedUntil: nil,
                joinedAt: Date(timeIntervalSince1970: 0),
                activatedAt: nil
            ))
        }
        return result
    }
    #endif
}
