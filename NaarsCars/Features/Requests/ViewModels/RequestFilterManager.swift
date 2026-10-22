//
//  RequestFilterManager.swift
//  NaarsCars
//
//  Filtering and badge-count logic for requests dashboard
//

import Foundation
import SwiftData
import Observation

/// Open requests per community: what the Open filter lists under All communities.
/// Rows with no community count only in `all`.
struct OpenRequestCounts: Equatable {
    let all: Int
    let byCommunity: [UUID: Int]

    static let zero = OpenRequestCounts(all: 0, byCommunity: [:])
}

extension OpenRequestCounts {
    /// Counts already filtered Open rows (the Open filter's list under `.all`).
    init(openRequests: [RequestItem]) {
        var byCommunity: [UUID: Int] = [:]
        for request in openRequests {
            let communityId: UUID?
            switch request {
            case .ride(let ride): communityId = ride.communityId
            case .favor(let favor): communityId = favor.communityId
            }
            guard let communityId else { continue }
            byCommunity[communityId, default: 0] += 1
        }
        self.init(all: openRequests.count, byCommunity: byCommunity)
    }
}

/// Extracted filtering/badge helper logic for requests dashboard.
@MainActor
@Observable
final class RequestFilterManager {
    private let authService: AuthService

    init(authService: AuthService = .shared) {
        self.authService = authService
    }

    func filterRequests(_ newFilter: RequestFilter) -> RequestFilter {
        newFilter
    }

    func getFilteredRequests(
        rides: [SDRide],
        favors: [SDFavor],
        filter: RequestFilter
    ) -> [RequestItem] {
        let userId = authService.currentUserId
        if userId == nil && filter != .open { return [] }

        var allRequests: [RequestItem] = []

        let ridesConverted: [Ride] = rides.map { sdRide in
            let poster = makeProfile(id: sdRide.userId, name: sdRide.posterName, avatarUrl: sdRide.posterAvatarUrl)
            let claimer = sdRide.claimedBy.flatMap { claimedBy in
                makeProfile(id: claimedBy, name: sdRide.claimerName, avatarUrl: sdRide.claimerAvatarUrl)
            }
            return Ride(
                id: sdRide.id,
                userId: sdRide.userId,
                type: sdRide.type,
                date: sdRide.date,
                time: sdRide.time,
                timezone: sdRide.timezone,
                pickup: sdRide.pickup,
                destination: sdRide.destination,
                seats: sdRide.seats,
                notes: sdRide.notes,
                gift: sdRide.gift,
                status: RideStatus(rawValue: sdRide.status) ?? .open,
                claimedBy: sdRide.claimedBy,
                reviewed: sdRide.reviewed,
                reviewSkipped: sdRide.reviewSkipped,
                reviewSkippedAt: sdRide.reviewSkippedAt,
                estimatedCost: sdRide.estimatedCost,
                flightNormalized: sdRide.flightNormalized,
                hiddenAt: sdRide.hiddenAt,
                hiddenBy: sdRide.hiddenBy,
                hiddenReason: sdRide.hiddenReason,
                communityId: sdRide.communityId,
                createdAt: sdRide.createdAt,
                updatedAt: sdRide.updatedAt,
                poster: poster,
                claimer: claimer,
                qaCount: sdRide.qaCount
            )
        }

        let favorsConverted: [Favor] = favors.map { sdFavor in
            let poster = makeProfile(id: sdFavor.userId, name: sdFavor.posterName, avatarUrl: sdFavor.posterAvatarUrl)
            let claimer = sdFavor.claimedBy.flatMap { claimedBy in
                makeProfile(id: claimedBy, name: sdFavor.claimerName, avatarUrl: sdFavor.claimerAvatarUrl)
            }
            return Favor(
                id: sdFavor.id,
                userId: sdFavor.userId,
                title: sdFavor.title,
                description: sdFavor.favorDescription,
                location: sdFavor.location,
                duration: FavorDuration(rawValue: sdFavor.duration) ?? .notSure,
                requirements: sdFavor.requirements,
                date: sdFavor.date,
                time: sdFavor.time,
                timezone: sdFavor.timezone,
                gift: sdFavor.gift,
                status: FavorStatus(rawValue: sdFavor.status) ?? .open,
                claimedBy: sdFavor.claimedBy,
                reviewed: sdFavor.reviewed,
                reviewSkipped: sdFavor.reviewSkipped,
                reviewSkippedAt: sdFavor.reviewSkippedAt,
                hiddenAt: sdFavor.hiddenAt,
                hiddenBy: sdFavor.hiddenBy,
                hiddenReason: sdFavor.hiddenReason,
                communityId: sdFavor.communityId,
                createdAt: sdFavor.createdAt,
                updatedAt: sdFavor.updatedAt,
                poster: poster,
                claimer: claimer,
                qaCount: sdFavor.qaCount
            )
        }

        allRequests = ridesConverted.map(RequestItem.ride) + favorsConverted.map(RequestItem.favor)

        // The converted values carry no `participants` (the cache stores ids only), so
        // `RequestItem.isParticipating` alone sees just the poster. A co-requester's shared
        // ride was listed under Open Requests with "I Can Help!" and never under My Requests.
        var participantIdsByRequest: [UUID: [UUID]] = [:]
        for sdRide in rides { participantIdsByRequest[sdRide.id] = sdRide.participantIds }
        for sdFavor in favors { participantIdsByRequest[sdFavor.id] = sdFavor.participantIds }
        func isRequester(_ item: RequestItem, _ uid: UUID) -> Bool {
            item.userId == uid || (participantIdsByRequest[item.id]?.contains(uid) ?? false)
        }

        switch filter {
        case .open:
            // Guests (userId nil) see all unclaimed. Authenticated users also exclude requests they participate in.
            allRequests = allRequests.filter { item in
                item.isUnclaimed && (userId == nil || !isRequester(item, userId!))
            }
        case .mine:
            allRequests = allRequests.filter { isRequester($0, userId!) }
        case .claimed:
            allRequests = allRequests.filter { $0.claimedBy == userId! }
        }

        let now = Date()
        allRequests = allRequests.filter { request in
            if request.isCompleted { return false }
            // Measured from the end of the request's window (RequestItem.windowEnd), not from
            // `eventTime`: a favor with no time was hidden from every tile at noon of its day.
            let hoursSinceEvent = now.timeIntervalSince(request.windowEnd) / 3600
            if hoursSinceEvent <= 12 { return true }
            // Past the 12 h window, a confirmed request the user is a party to still needs
            // "Mark as Complete" on its detail screen, so keep it on the Mine / Claimed tiles.
            guard filter != .open, let userId, request.status == .confirmed else { return false }
            return request.claimedBy == userId || isRequester(request, userId)
        }

        if filter == .open {
            allRequests.sort { $0.eventTime < $1.eventTime }
        } else {
            // Mine / Claimed: what is coming up first (soonest at the top), then anything
            // already past, most recent first. Past requests are listed only because they
            // still need "Mark as Complete", and used to push new requests to the bottom.
            allRequests.sort { lhs, rhs in
                let lhsUpcoming = lhs.windowEnd >= now
                let rhsUpcoming = rhs.windowEnd >= now
                if lhsUpcoming != rhsUpcoming { return lhsUpcoming }
                return lhsUpcoming ? lhs.eventTime < rhs.eventTime : lhs.eventTime > rhs.eventTime
            }
        }
        return allRequests
    }

    func fetchFilteredRides(in context: ModelContext, filter: RequestFilter, scope: RequestsScope = .all) -> [SDRide] {
        let userId = authService.currentUserId
        if userId == nil && filter != .open { return [] }

        let predicate: Predicate<SDRide>
        switch filter {
        case .open:
            predicate = #Predicate { $0.status == "open" && $0.claimedBy == nil }
        case .mine:
            // Participant-only rows are matched by the `participantIds` check after the fetch.
            // The predicate used to require poster or claimer, which dropped them first.
            predicate = #Predicate { $0.status != "completed" }
        case .claimed:
            let uid = userId!
            predicate = #Predicate { $0.claimedBy == uid && $0.status != "completed" }
        }

        let descriptor = FetchDescriptor<SDRide>(predicate: predicate, sortBy: [SortDescriptor(\.date, order: .forward)])
        let fetched = (try? context.fetch(descriptor)) ?? []
        if filter == .mine, let uid = userId {
            return fetched
                .filter { $0.participantIds.contains(uid) || $0.userId == uid || $0.claimedBy == uid }
                .filter { scope.includes($0.communityId) }
        }
        return fetched.filter { scope.includes($0.communityId) }
    }

    func fetchFilteredFavors(in context: ModelContext, filter: RequestFilter, scope: RequestsScope = .all) -> [SDFavor] {
        let userId = authService.currentUserId
        if userId == nil && filter != .open { return [] }

        let predicate: Predicate<SDFavor>
        switch filter {
        case .open:
            predicate = #Predicate { $0.status == "open" && $0.claimedBy == nil }
        case .mine:
            // Participant-only rows are matched by the `participantIds` check after the fetch.
            // The predicate used to require poster or claimer, which dropped them first.
            predicate = #Predicate { $0.status != "completed" }
        case .claimed:
            let uid = userId!
            predicate = #Predicate { $0.claimedBy == uid && $0.status != "completed" }
        }

        let descriptor = FetchDescriptor<SDFavor>(predicate: predicate, sortBy: [SortDescriptor(\.date, order: .forward)])
        let fetched = (try? context.fetch(descriptor)) ?? []
        if filter == .mine, let uid = userId {
            return fetched
                .filter { $0.participantIds.contains(uid) || $0.userId == uid || $0.claimedBy == uid }
                .filter { scope.includes($0.communityId) }
        }
        return fetched.filter { scope.includes($0.communityId) }
    }

    /// Whether the store holds any ride or favor, whatever the filter or scope. The dashboard's
    /// skeleton stands for "nothing cached yet"; an empty filter over a filled store already has
    /// its answer (the empty state). Two COUNT queries, no rows loaded.
    func hasStoredRequests(in context: ModelContext) -> Bool {
        ((try? context.fetchCount(FetchDescriptor<SDRide>())) ?? 0) > 0
            || ((try? context.fetchCount(FetchDescriptor<SDFavor>())) ?? 0) > 0
    }

    /// Requests the current filter would list under `.all` but `scope` hides: what the "N more" hint counts.
    /// 0 for `.all`. Rows with no community are shown by every narrow and never count; rows the list hides for
    /// time (getFilteredRequests) never count.
    func countOutsideScope(in context: ModelContext, filter: RequestFilter, scope: RequestsScope) -> Int {
        guard scope != .all else { return 0 }
        let everything = getFilteredRequests(
            rides: fetchFilteredRides(in: context, filter: filter, scope: .all),
            favors: fetchFilteredFavors(in: context, filter: filter, scope: .all),
            filter: filter
        ).count
        let narrowed = getFilteredRequests(
            rides: fetchFilteredRides(in: context, filter: filter, scope: scope),
            favors: fetchFilteredFavors(in: context, filter: filter, scope: scope),
            filter: filter
        ).count
        return max(0, everything - narrowed)
    }

    /// The Open filter's rows under `.all` (the 12-hour rule included), counted in total and per
    /// community. Local only: two fetches of open rows, no network.
    func openCounts(in context: ModelContext) -> OpenRequestCounts {
        OpenRequestCounts(openRequests: getFilteredRequests(
            rides: fetchFilteredRides(in: context, filter: .open, scope: .all),
            favors: fetchFilteredFavors(in: context, filter: .open, scope: .all),
            filter: .open
        ))
    }

    func computeFilterBadgeCounts(
        in context: ModelContext,
        requestNotificationSummaries: [String: RequestNotificationSummary],
        scope: RequestsScope = .all
    ) -> [RequestFilter: Int] {
        // Single fetch of ALL rides and favors (2 queries instead of 6)
        let allRides = (try? context.fetch(FetchDescriptor<SDRide>())) ?? []
        let allFavors = (try? context.fetch(FetchDescriptor<SDFavor>())) ?? []

        var counts: [RequestFilter: Int] = [:]
        for filterCase in RequestFilter.allCases {
            let filteredRides = filterRidesInMemory(allRides, for: filterCase, scope: scope)
            let filteredFavors = filterFavorsInMemory(allFavors, for: filterCase, scope: scope)
            let requests = getFilteredRequests(rides: filteredRides, favors: filteredFavors, filter: filterCase)
            let unreadTotal = requests.reduce(0) { total, request in
                total + (requestNotificationSummaries[request.notificationKey]?.unreadCount ?? 0)
            }
            counts[filterCase] = unreadTotal
        }
        return counts
    }

    func notificationTarget(
        for request: RequestItem,
        requestNotificationSummaries: [String: RequestNotificationSummary]
    ) -> RequestNotificationTarget? {
        guard let summary = requestNotificationSummaries[request.notificationKey] else { return nil }
        switch request {
        case .ride(let ride):
            return resolveRequestTarget(requestType: .ride, requestId: ride.id, latestType: summary.latestUnreadType)
        case .favor(let favor):
            return resolveRequestTarget(requestType: .favor, requestId: favor.id, latestType: summary.latestUnreadType)
        }
    }

    /// In-memory equivalent of the predicate + post-fetch filter in `fetchFilteredRides`.
    private func filterRidesInMemory(_ rides: [SDRide], for filter: RequestFilter, scope: RequestsScope) -> [SDRide] {
        filterRidesByStatus(rides, for: filter).filter { scope.includes($0.communityId) }
    }

    private func filterRidesByStatus(_ rides: [SDRide], for filter: RequestFilter) -> [SDRide] {
        let userId = authService.currentUserId
        if userId == nil && filter != .open { return [] }
        switch filter {
        case .open:
            return rides.filter { $0.status == "open" && $0.claimedBy == nil }
        case .mine:
            let uid = userId!
            // Matches the predicate (status != completed) then the post-fetch
            // poster / claimer / participantIds check.
            return rides.filter {
                $0.status != "completed"
            }.filter {
                $0.participantIds.contains(uid) || $0.userId == uid || $0.claimedBy == uid
            }
        case .claimed:
            let uid = userId!
            return rides.filter { $0.claimedBy == uid && $0.status != "completed" }
        }
    }

    /// In-memory equivalent of the predicate + post-fetch filter in `fetchFilteredFavors`.
    private func filterFavorsInMemory(_ favors: [SDFavor], for filter: RequestFilter, scope: RequestsScope) -> [SDFavor] {
        filterFavorsByStatus(favors, for: filter).filter { scope.includes($0.communityId) }
    }

    private func filterFavorsByStatus(_ favors: [SDFavor], for filter: RequestFilter) -> [SDFavor] {
        let userId = authService.currentUserId
        if userId == nil && filter != .open { return [] }
        switch filter {
        case .open:
            return favors.filter { $0.status == "open" && $0.claimedBy == nil }
        case .mine:
            let uid = userId!
            return favors.filter {
                $0.status != "completed"
            }.filter {
                $0.participantIds.contains(uid) || $0.userId == uid || $0.claimedBy == uid
            }
        case .claimed:
            let uid = userId!
            return favors.filter { $0.claimedBy == uid && $0.status != "completed" }
        }
    }

    private func makeProfile(id: UUID, name: String?, avatarUrl: String?) -> Profile? {
        guard let name = name, !name.isEmpty else { return nil }
        return Profile(id: id, name: name, email: "", avatarUrl: avatarUrl)
    }

    private func resolveRequestTarget(
        requestType: RequestType,
        requestId: UUID,
        latestType: NotificationType
    ) -> RequestNotificationTarget {
        let mapped: RequestNotificationTarget?
        switch requestType {
        case .ride:
            mapped = RequestNotificationMapping.target(for: latestType, rideId: requestId, favorId: nil)
        case .favor:
            mapped = RequestNotificationMapping.target(for: latestType, rideId: nil, favorId: requestId)
        }

        if let mapped { return mapped }
        return RequestNotificationTarget(
            requestType: requestType,
            requestId: requestId,
            anchor: .mainTop,
            scrollAnchor: nil,
            highlightAnchor: .mainTop,
            shouldAutoClear: true
        )
    }
}
