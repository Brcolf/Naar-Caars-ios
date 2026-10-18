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
    private let defaults: UserDefaults
    private let now: () -> Date

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

    // MARK: - Init

    init(
        service: any CommunityServiceProtocol = CommunityService.shared,
        defaults: UserDefaults = .standard,
        now: @escaping () -> Date = Date.init
    ) {
        self.service = service
        self.defaults = defaults
        self.now = now
    }

    // MARK: - Lookups

    /// The community's name, or nil for a nil or unknown id.
    func name(for communityId: UUID?) -> String? {
        guard let communityId else { return nil }
        return memberships.first { $0.communityId == communityId }?.name
    }

    /// Text for a community chip: nil with one active membership, and nil when `respectingScope`
    /// is set and Requests is narrowed (every card then belongs to the same community).
    func chipText(for communityId: UUID?, respectingScope: Bool) -> String? {
        guard hasMultipleCommunities else { return nil }
        if respectingScope && requestsScope != .all { return nil }
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
        apply(Self.appendingDebugMemberships(to: rows))
        #else
        apply(rows)
        #endif

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
        if let narrowed = requestsScope.communityId, !activeIds.contains(narrowed) {
            requestsScope = .all
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
                joinPolicy: "invite_only",
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
