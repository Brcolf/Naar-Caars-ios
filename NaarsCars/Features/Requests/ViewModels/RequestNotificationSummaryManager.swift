//
//  RequestNotificationSummaryManager.swift
//  NaarsCars
//
//  Builds unseen request keys and notification summaries
//

import Foundation
import SwiftData
internal import Combine

/// Extracted request-notification summary logic for dashboard badges/anchors.
@MainActor
final class RequestNotificationSummaryManager: ObservableObject {
    @Published var unseenRequestKeys: Set<String> = []
    @Published var requestNotificationSummaries: [String: RequestNotificationSummary] = [:]

    private let authService: AuthService
    private let notificationService: NotificationService

    init(
        authService: AuthService = .shared,
        notificationService: NotificationService = .shared
    ) {
        self.authService = authService
        self.notificationService = notificationService
    }

    func refreshUnseenRequestKeys(modelContext: ModelContext?) async {
        guard let userId = authService.currentUserId else {
            unseenRequestKeys = []
            requestNotificationSummaries = [:]
            return
        }

        if let context = modelContext {
            let descriptor = FetchDescriptor<SDNotification>(
                predicate: #Predicate { notification in
                    notification.userId == userId && notification.read == false
                }
            )
            let localNotifications = (try? context.fetch(descriptor)) ?? []
            let summaries = buildRequestNotificationSummaries(from: localNotifications)
            requestNotificationSummaries = summaries
            unseenRequestKeys = Set(summaries.keys)
            AppLogger.info("requests", "Unseen request keys: \(unseenRequestKeys.count) (local)")
            return
        }

        do {
            let notifications = try await notificationService.fetchNotifications(userId: userId, forceRefresh: true)
            if !Task.isCancelled {
                let summaries = buildRequestNotificationSummaries(from: notifications)
                requestNotificationSummaries = summaries
                unseenRequestKeys = Set(summaries.keys)
                AppLogger.info("requests", "Unseen request keys: \(unseenRequestKeys.count) (network)")
            }
        } catch {
            if (error as NSError).code != NSURLErrorCancelled {
                AppLogger.warning("requests", "Failed to refresh request keys: \(error.localizedDescription)")
            }
        }
    }

    func buildRequestNotificationSummaries(
        from notifications: [AppNotification]
    ) -> [String: RequestNotificationSummary] {
        var summaries: [String: RequestNotificationSummary] = [:]

        for notification in notifications where !notification.read {
            guard let key = NotificationGrouping.requestKey(for: notification) else { continue }
            let createdAt = notification.createdAt

            if let existing = summaries[key] {
                let unreadCount = existing.unreadCount + 1
                if createdAt > existing.latestUnreadAt {
                    summaries[key] = RequestNotificationSummary(
                        unreadCount: unreadCount,
                        latestUnreadType: notification.type,
                        latestUnreadAt: createdAt
                    )
                } else {
                    summaries[key] = RequestNotificationSummary(
                        unreadCount: unreadCount,
                        latestUnreadType: existing.latestUnreadType,
                        latestUnreadAt: existing.latestUnreadAt
                    )
                }
            } else {
                summaries[key] = RequestNotificationSummary(
                    unreadCount: 1,
                    latestUnreadType: notification.type,
                    latestUnreadAt: createdAt
                )
            }
        }

        return summaries
    }

    func buildRequestNotificationSummaries(
        from notifications: [SDNotification]
    ) -> [String: RequestNotificationSummary] {
        var summaries: [String: RequestNotificationSummary] = [:]

        for notification in notifications {
            guard let type = NotificationType(rawValue: notification.type),
                  NotificationGrouping.requestBadgeTypes.contains(type) else {
                continue
            }

            let key: String?
            if let rideId = notification.rideId {
                key = "ride:\(rideId)"
            } else if let favorId = notification.favorId {
                key = "favor:\(favorId)"
            } else {
                key = nil
            }
            guard let key else { continue }

            let createdAt = notification.createdAt
            if let existing = summaries[key] {
                let unreadCount = existing.unreadCount + 1
                if createdAt > existing.latestUnreadAt {
                    summaries[key] = RequestNotificationSummary(
                        unreadCount: unreadCount,
                        latestUnreadType: type,
                        latestUnreadAt: createdAt
                    )
                } else {
                    summaries[key] = RequestNotificationSummary(
                        unreadCount: unreadCount,
                        latestUnreadType: existing.latestUnreadType,
                        latestUnreadAt: existing.latestUnreadAt
                    )
                }
            } else {
                summaries[key] = RequestNotificationSummary(
                    unreadCount: 1,
                    latestUnreadType: type,
                    latestUnreadAt: createdAt
                )
            }
        }

        return summaries
    }
}
