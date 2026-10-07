//
//  RequestFilterManager.swift
//  NaarsCars
//
//  Filtering and badge-count logic for requests dashboard
//

import Foundation
import SwiftData
import Observation

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

        let allRequests = convertRides(rides).map(RequestItem.ride)
            + convertFavors(favors).map(RequestItem.favor)
        return applyFilterAndSort(allRequests, filter: filter, userId: userId)
    }

    /// Converts SwiftData rides to domain `Ride` values.
    /// NOTE: `participants` is intentionally left nil (matching prior behavior); callers that need
    /// participant/claimer membership rely on the SwiftData pre-filter, not `isParticipating`.
    private func convertRides(_ rides: [SDRide]) -> [Ride] {
        rides.map { sdRide in
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
                createdAt: sdRide.createdAt,
                updatedAt: sdRide.updatedAt,
                poster: poster,
                claimer: claimer,
                qaCount: sdRide.qaCount
            )
        }
    }

    /// Converts SwiftData favors to domain `Favor` values. See `convertRides` note on `participants`.
    private func convertFavors(_ favors: [SDFavor]) -> [Favor] {
        favors.map { sdFavor in
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
                createdAt: sdFavor.createdAt,
                updatedAt: sdFavor.updatedAt,
                poster: poster,
                claimer: claimer,
                qaCount: sdFavor.qaCount
            )
        }
    }

    /// Applies the active-filter predicate, the 12-hour recency window, and the event-time sort.
    /// Mirrors the tail of `getFilteredRequests` exactly so both entry points produce identical output.
    private func applyFilterAndSort(
        _ allRequests: [RequestItem],
        filter: RequestFilter,
        userId: UUID?
    ) -> [RequestItem] {
        if userId == nil && filter != .open { return [] }

        var result: [RequestItem]
        switch filter {
        case .open:
            // Guests (userId nil) see all unclaimed. Authenticated users also exclude requests they participate in.
            result = allRequests.filter { item in
                item.isUnclaimed && (userId == nil || !item.isParticipating(userId: userId!))
            }
        case .mine:
            result = allRequests.filter { $0.isParticipating(userId: userId!) }
        case .claimed:
            result = allRequests.filter { $0.claimedBy == userId! }
        }

        let now = Date()
        result = result.filter { request in
            if request.isCompleted { return false }
            let hoursSinceEvent = now.timeIntervalSince(request.eventTime) / 3600
            return hoursSinceEvent <= 12
        }

        result.sort { $0.eventTime < $1.eventTime }
        return result
    }

    func fetchFilteredRides(in context: ModelContext, filter: RequestFilter) -> [SDRide] {
        let userId = authService.currentUserId
        if userId == nil && filter != .open { return [] }

        let predicate: Predicate<SDRide>
        switch filter {
        case .open:
            predicate = #Predicate { $0.status == "open" && $0.claimedBy == nil }
        case .mine:
            let uid = userId!
            predicate = #Predicate { $0.status != "completed" && ($0.userId == uid || $0.claimedBy == uid) }
        case .claimed:
            let uid = userId!
            predicate = #Predicate { $0.claimedBy == uid && $0.status != "completed" }
        }

        let descriptor = FetchDescriptor<SDRide>(predicate: predicate, sortBy: [SortDescriptor(\.date, order: .forward)])
        let fetched = (try? context.fetch(descriptor)) ?? []
        if filter == .mine, let uid = userId {
            return fetched.filter { $0.participantIds.contains(uid) || $0.userId == uid || $0.claimedBy == uid }
        }
        return fetched
    }

    func fetchFilteredFavors(in context: ModelContext, filter: RequestFilter) -> [SDFavor] {
        let userId = authService.currentUserId
        if userId == nil && filter != .open { return [] }

        let predicate: Predicate<SDFavor>
        switch filter {
        case .open:
            predicate = #Predicate { $0.status == "open" && $0.claimedBy == nil }
        case .mine:
            let uid = userId!
            predicate = #Predicate { $0.status != "completed" && ($0.userId == uid || $0.claimedBy == uid) }
        case .claimed:
            let uid = userId!
            predicate = #Predicate { $0.claimedBy == uid && $0.status != "completed" }
        }

        let descriptor = FetchDescriptor<SDFavor>(predicate: predicate, sortBy: [SortDescriptor(\.date, order: .forward)])
        let fetched = (try? context.fetch(descriptor)) ?? []
        if filter == .mine, let uid = userId {
            return fetched.filter { $0.participantIds.contains(uid) || $0.userId == uid || $0.claimedBy == uid }
        }
        return fetched
    }

    func computeFilterBadgeCounts(
        in context: ModelContext,
        requestNotificationSummaries: [String: RequestNotificationSummary]
    ) -> [RequestFilter: Int] {
        // Single fetch of ALL rides and favors (2 queries instead of 6)
        let allRides = (try? context.fetch(FetchDescriptor<SDRide>())) ?? []
        let allFavors = (try? context.fetch(FetchDescriptor<SDFavor>())) ?? []

        // Convert each SwiftData model to a domain RequestItem exactly ONCE and reuse across all tabs,
        // instead of re-converting a per-tab subset inside getFilteredRequests for every filter case.
        // Keyed by id so the cheap per-tab SwiftData pre-filter can look up its already-converted items.
        let rideItemsById = Dictionary(
            convertRides(allRides).map(RequestItem.ride).map { ($0.id, $0) },
            uniquingKeysWith: { first, _ in first }
        )
        let favorItemsById = Dictionary(
            convertFavors(allFavors).map(RequestItem.favor).map { ($0.id, $0) },
            uniquingKeysWith: { first, _ in first }
        )

        let userId = authService.currentUserId
        var counts: [RequestFilter: Int] = [:]
        for filterCase in RequestFilter.allCases {
            // Cheap SwiftData-field pre-filter (unchanged), then map to pre-converted domain items.
            let filteredRides = filterRidesInMemory(allRides, for: filterCase)
            let filteredFavors = filterFavorsInMemory(allFavors, for: filterCase)
            let preFilteredItems = filteredRides.compactMap { rideItemsById[$0.id] }
                + filteredFavors.compactMap { favorItemsById[$0.id] }
            let requests = applyFilterAndSort(preFilteredItems, filter: filterCase, userId: userId)
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
    private func filterRidesInMemory(_ rides: [SDRide], for filter: RequestFilter) -> [SDRide] {
        let userId = authService.currentUserId
        if userId == nil && filter != .open { return [] }
        switch filter {
        case .open:
            return rides.filter { $0.status == "open" && $0.claimedBy == nil }
        case .mine:
            let uid = userId!
            // Matches the predicate (status != completed && (poster or claimer))
            // then the post-fetch participantIds check.
            return rides.filter {
                $0.status != "completed"
                    && ($0.userId == uid || $0.claimedBy == uid)
            }.filter {
                $0.participantIds.contains(uid) || $0.userId == uid || $0.claimedBy == uid
            }
        case .claimed:
            let uid = userId!
            return rides.filter { $0.claimedBy == uid && $0.status != "completed" }
        }
    }

    /// In-memory equivalent of the predicate + post-fetch filter in `fetchFilteredFavors`.
    private func filterFavorsInMemory(_ favors: [SDFavor], for filter: RequestFilter) -> [SDFavor] {
        let userId = authService.currentUserId
        if userId == nil && filter != .open { return [] }
        switch filter {
        case .open:
            return favors.filter { $0.status == "open" && $0.claimedBy == nil }
        case .mine:
            let uid = userId!
            return favors.filter {
                $0.status != "completed"
                    && ($0.userId == uid || $0.claimedBy == uid)
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
