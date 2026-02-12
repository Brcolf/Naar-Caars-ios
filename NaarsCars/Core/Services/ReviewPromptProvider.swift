//
//  ReviewPromptProvider.swift
//  NaarsCars
//
//  Real implementation of ReviewPromptProviding protocol
//

import Foundation

struct ReviewPromptDependencies {
    let fetchNotifications: (UUID, Bool) async throws -> [AppNotification]
    let markReviewRequestAsRead: (String, UUID) async -> Void
    let refreshBadges: (String) async -> Void
    let fetchRide: (UUID) async throws -> Ride
    let fetchFavor: (UUID) async throws -> Favor
    let fetchProfile: (UUID) async throws -> Profile
    let canStillReview: (String, UUID) async throws -> Bool

    @MainActor
    static func live() -> ReviewPromptDependencies {
        let notificationService = NotificationService.shared
        let badgeManager = BadgeCountManager.shared
        let profileService = ProfileService.shared
        let rideService = RideService.shared
        let favorService = FavorService.shared
        let reviewService = ReviewService.shared
        return ReviewPromptDependencies(
            fetchNotifications: { userId, forceRefresh in
                try await notificationService.fetchNotifications(userId: userId, forceRefresh: forceRefresh)
            },
            markReviewRequestAsRead: { requestType, requestId in
                await notificationService.markReviewRequestAsRead(requestType: requestType, requestId: requestId)
            },
            refreshBadges: { reason in
                await badgeManager.refreshAllBadges(reason: reason)
            },
            fetchRide: { id in
                try await rideService.fetchRide(id: id)
            },
            fetchFavor: { id in
                try await favorService.fetchFavor(id: id)
            },
            fetchProfile: { userId in
                try await profileService.fetchProfile(userId: userId)
            },
            canStillReview: { requestType, requestId in
                try await reviewService.canStillReview(requestType: requestType, requestId: requestId)
            }
        )
    }
}

final class ReviewPromptProvider: ReviewPromptProviding {
    private let dependencies: ReviewPromptDependencies

    init(dependencies: ReviewPromptDependencies) {
        self.dependencies = dependencies
    }

    convenience init() {
        self.init(dependencies: .live())
    }

    func fetchPendingReviewPrompts(userId: UUID) async throws -> [ReviewPrompt] {
        let notifications = try await dependencies.fetchNotifications(userId, true)
        let pending = notifications
            .filter { !$0.read && ($0.type == .reviewRequest || $0.type == .reviewReminder) }
            .sorted { $0.createdAt < $1.createdAt }

        var prompts: [ReviewPrompt] = []
        for notification in pending {
            if let prompt = try await buildPrompt(from: notification, userId: userId) {
                prompts.append(prompt)
            }
        }
        return prompts
    }

    func fetchReviewPrompt(requestType: RequestType, requestId: UUID, userId: UUID) async throws -> ReviewPrompt? {
        let notifications = try await dependencies.fetchNotifications(userId, true)
        let pending = notifications
            .filter { !$0.read && ($0.type == .reviewRequest || $0.type == .reviewReminder) }
            .sorted { $0.createdAt < $1.createdAt }

        for notification in pending {
            if (requestType == .ride && notification.rideId == requestId) ||
               (requestType == .favor && notification.favorId == requestId) {
                return try await buildPrompt(from: notification, userId: userId)
            }
        }
        return nil
    }

    private func buildPrompt(from notification: AppNotification, userId: UUID) async throws -> ReviewPrompt? {
        if let rideId = notification.rideId {
            let ride = try await dependencies.fetchRide(rideId)
            guard ride.userId == userId, let fulfillerId = ride.claimedBy else { return nil }
            let requestType = RequestType.ride.rawValue
            guard try await dependencies.canStillReview(requestType, rideId) else {
                await dependencies.markReviewRequestAsRead(requestType, rideId)
                await dependencies.refreshBadges("reviewPromptExpired")
                return nil
            }
            let fulfillerName = (try? await dependencies.fetchProfile(fulfillerId))?.name ?? "Someone"
            return ReviewPrompt(
                id: rideId,
                requestType: .ride,
                requestId: rideId,
                requestTitle: "\(ride.pickup) → \(ride.destination)",
                fulfillerId: fulfillerId,
                fulfillerName: fulfillerName,
                createdAt: notification.createdAt
            )
        }
        if let favorId = notification.favorId {
            let favor = try await dependencies.fetchFavor(favorId)
            guard favor.userId == userId, let fulfillerId = favor.claimedBy else { return nil }
            let requestType = RequestType.favor.rawValue
            guard try await dependencies.canStillReview(requestType, favorId) else {
                await dependencies.markReviewRequestAsRead(requestType, favorId)
                await dependencies.refreshBadges("reviewPromptExpired")
                return nil
            }
            let fulfillerName = (try? await dependencies.fetchProfile(fulfillerId))?.name ?? "Someone"
            return ReviewPrompt(
                id: favorId,
                requestType: .favor,
                requestId: favorId,
                requestTitle: favor.title,
                fulfillerId: fulfillerId,
                fulfillerName: fulfillerName,
                createdAt: notification.createdAt
            )
        }
        return nil
    }
}
