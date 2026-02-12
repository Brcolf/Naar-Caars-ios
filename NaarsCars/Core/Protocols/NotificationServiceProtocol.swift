//
//  NotificationServiceProtocol.swift
//  NaarsCars
//

import Foundation

@MainActor
protocol NotificationServiceProtocol: AnyObject {
    func fetchNotifications(userId: UUID, forceRefresh: Bool) async throws -> [AppNotification]
    func markAsRead(notificationId: UUID) async throws
    func markAllBellNotificationsAsRead(userId: UUID) async throws
    func markRequestScopedRead(
        requestType: String,
        requestId: UUID,
        notificationTypes: [NotificationType]?,
        includeReviews: Bool
    ) async -> Int
}
