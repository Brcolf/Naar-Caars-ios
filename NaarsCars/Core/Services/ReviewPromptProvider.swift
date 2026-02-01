//
//  ReviewPromptProvider.swift
//  NaarsCars
//
//  Real implementation of ReviewPromptProviding protocol
//

import Foundation

@MainActor
final class ReviewPromptProvider: ReviewPromptProviding {
    private let notificationService = NotificationService.shared
    private let profileService = ProfileService.shared
    private let rideService = RideService.shared
    private let favorService = FavorService.shared
    private let reviewService = ReviewService.shared

    func fetchPendingReviewPrompts(userId: UUID) async throws -> [ReviewPrompt] {
        let notifications = try await notificationService.fetchNotifications(userId: userId, forceRefresh: true)
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
        let notifications = try await notificationService.fetchNotifications(userId: userId, forceRefresh: true)
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
            let ride = try await rideService.fetchRide(id: rideId)
            guard ride.userId == userId, let fulfillerId = ride.claimedBy else { return nil }
            guard try await reviewService.canStillReview(requestType: "ride", requestId: rideId) else { return nil }
            let fulfillerName = (try? await profileService.fetchProfile(userId: fulfillerId))?.name ?? "Someone"
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
            let favor = try await favorService.fetchFavor(id: favorId)
            guard favor.userId == userId, let fulfillerId = favor.claimedBy else { return nil }
            guard try await reviewService.canStillReview(requestType: "favor", requestId: favorId) else { return nil }
            let fulfillerName = (try? await profileService.fetchProfile(userId: fulfillerId))?.name ?? "Someone"
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
