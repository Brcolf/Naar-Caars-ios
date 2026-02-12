//
//  RequestFilterManager.swift
//  NaarsCars
//
//  Filtering and badge-count logic for requests dashboard
//

import Foundation
import SwiftData
internal import Combine

/// Extracted filtering/badge helper logic for requests dashboard.
@MainActor
final class RequestFilterManager: ObservableObject {
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
        guard let userId = authService.currentUserId else { return [] }

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
                gift: sdFavor.gift,
                status: FavorStatus(rawValue: sdFavor.status) ?? .open,
                claimedBy: sdFavor.claimedBy,
                reviewed: sdFavor.reviewed,
                reviewSkipped: sdFavor.reviewSkipped,
                reviewSkippedAt: sdFavor.reviewSkippedAt,
                createdAt: sdFavor.createdAt,
                updatedAt: sdFavor.updatedAt,
                poster: poster,
                claimer: claimer,
                qaCount: sdFavor.qaCount
            )
        }

        allRequests = ridesConverted.map(RequestItem.ride) + favorsConverted.map(RequestItem.favor)

        switch filter {
        case .open:
            allRequests = allRequests.filter { $0.isUnclaimed && !$0.isParticipating(userId: userId) }
        case .mine:
            allRequests = allRequests.filter { $0.isParticipating(userId: userId) }
        case .claimed:
            allRequests = allRequests.filter { $0.claimedBy == userId }
        }

        let now = Date()
        allRequests = allRequests.filter { request in
            if request.isCompleted { return false }
            let hoursSinceEvent = now.timeIntervalSince(request.eventTime) / 3600
            return hoursSinceEvent <= 12
        }

        allRequests.sort { $0.eventTime < $1.eventTime }
        return allRequests
    }

    func fetchFilteredRides(in context: ModelContext, filter: RequestFilter) -> [SDRide] {
        guard let userId = authService.currentUserId else { return [] }

        let predicate: Predicate<SDRide>
        switch filter {
        case .open:
            predicate = #Predicate { $0.status == "open" && $0.claimedBy == nil }
        case .mine:
            predicate = #Predicate { $0.status != "completed" && ($0.userId == userId || $0.claimedBy == userId) }
        case .claimed:
            predicate = #Predicate { $0.claimedBy == userId && $0.status != "completed" }
        }

        let descriptor = FetchDescriptor<SDRide>(predicate: predicate, sortBy: [SortDescriptor(\.date, order: .forward)])
        let fetched = (try? context.fetch(descriptor)) ?? []
        if filter == .mine {
            return fetched.filter { $0.participantIds.contains(userId) || $0.userId == userId || $0.claimedBy == userId }
        }
        return fetched
    }

    func fetchFilteredFavors(in context: ModelContext, filter: RequestFilter) -> [SDFavor] {
        guard let userId = authService.currentUserId else { return [] }

        let predicate: Predicate<SDFavor>
        switch filter {
        case .open:
            predicate = #Predicate { $0.status == "open" && $0.claimedBy == nil }
        case .mine:
            predicate = #Predicate { $0.status != "completed" && ($0.userId == userId || $0.claimedBy == userId) }
        case .claimed:
            predicate = #Predicate { $0.claimedBy == userId && $0.status != "completed" }
        }

        let descriptor = FetchDescriptor<SDFavor>(predicate: predicate, sortBy: [SortDescriptor(\.date, order: .forward)])
        let fetched = (try? context.fetch(descriptor)) ?? []
        if filter == .mine {
            return fetched.filter { $0.participantIds.contains(userId) || $0.userId == userId || $0.claimedBy == userId }
        }
        return fetched
    }

    func computeFilterBadgeCounts(
        in context: ModelContext,
        requestNotificationSummaries: [String: RequestNotificationSummary]
    ) -> [RequestFilter: Int] {
        var counts: [RequestFilter: Int] = [:]
        for filterCase in RequestFilter.allCases {
            let rides = fetchFilteredRides(in: context, filter: filterCase)
            let favors = fetchFilteredFavors(in: context, filter: filterCase)
            let requests = getFilteredRequests(rides: rides, favors: favors, filter: filterCase)
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
