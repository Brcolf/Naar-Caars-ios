//
//  NotificationsListViewModel.swift
//  NaarsCars
//
//  ViewModel for notifications list
//

import Foundation
import SwiftData
internal import Combine

/// ViewModel for notifications list
@MainActor
final class NotificationsListViewModel: ObservableObject {
    @Published var isLoading: Bool = false
    @Published var error: AppError?
    @Published var unreadCount: Int = 0

    private var modelContext: ModelContext?
    private let notificationService: any NotificationServiceProtocol
    private let authService: any AuthServiceProtocol
    private let badgeManager: any BadgeCountManaging
    private let groupingManager: NotificationGroupingManager
    private let navigationRouter: NotificationNavigationRouter
    private let realtimeHandler: NotificationRealtimeHandler
    private var managerCancellables = Set<AnyCancellable>()

    init(
        notificationService: any NotificationServiceProtocol = NotificationService.shared,
        authService: any AuthServiceProtocol = AuthService.shared,
        badgeManager: any BadgeCountManaging = BadgeCountManager.shared
    ) {
        self.notificationService = notificationService
        self.authService = authService
        self.badgeManager = badgeManager
        groupingManager = NotificationGroupingManager()
        navigationRouter = NotificationNavigationRouter()
        realtimeHandler = NotificationRealtimeHandler()

        groupingManager.objectWillChange
            .sink { [weak self] in self?.objectWillChange.send() }
            .store(in: &managerCancellables)
        navigationRouter.objectWillChange
            .sink { [weak self] in self?.objectWillChange.send() }
            .store(in: &managerCancellables)
        realtimeHandler.objectWillChange
            .sink { [weak self] in self?.objectWillChange.send() }
            .store(in: &managerCancellables)

        realtimeHandler.setupRealtimeSubscription { [weak self] reason, fallback in
            await self?.handleRealtimeReload(reason: reason, fallback: fallback)
        }
    }

    deinit {
        Task { @MainActor in
            await realtimeHandler.stop()
        }
    }

    /// Set up the model context for SwiftData operations
    func setup(modelContext: ModelContext) {
        self.modelContext = modelContext
    }

    /// Get filtered notifications from SwiftData models
    func getFilteredNotifications(sdNotifications: [SDNotification]) -> [AppNotification] {
        groupingManager.getFilteredNotifications(sdNotifications: sdNotifications)
    }

    /// Get notification groups from SwiftData models
    func getNotificationGroups(sdNotifications: [SDNotification]) -> [NotificationGroup] {
        groupingManager.getNotificationGroups(sdNotifications: sdNotifications)
    }

    func loadNotifications(forceRefresh: Bool = false) async {
        guard let userId = authService.currentUserId else {
            error = .notAuthenticated
            return
        }
        
        isLoading = true
        error = nil
        
        do {
            if let context = modelContext {
                refreshUnreadCount(from: context, userId: userId)
            }
            
            let fetched = try await notificationService.fetchNotifications(userId: userId, forceRefresh: forceRefresh)
            
            // Sync to SwiftData
            if let context = modelContext {
                syncNotificationsToSwiftData(fetched, in: context)
                try? context.save()
                refreshUnreadCount(from: context, userId: userId)
            } else {
                self.unreadCount = fetched.filter { !$0.read }.count
            }
        } catch {
            self.error = AppError.processingError(error.localizedDescription)
            AppLogger.error("notifications", "Error loading notifications: \(error.localizedDescription)")
        }

        isLoading = false
    }

    private func syncNotificationsToSwiftData(_ notifications: [AppNotification], in context: ModelContext) {
        for notification in notifications {
            let id = notification.id
            let fetchDescriptor = FetchDescriptor<SDNotification>(predicate: #Predicate { $0.id == id })
            if let existing = try? context.fetch(fetchDescriptor).first {
                existing.read = notification.read
                existing.pinned = notification.pinned
                existing.title = notification.title
                existing.body = notification.body
                existing.createdAt = notification.createdAt
                existing.rideId = notification.rideId
                existing.favorId = notification.favorId
                existing.conversationId = notification.conversationId
                existing.reviewId = notification.reviewId
                existing.townHallPostId = notification.townHallPostId
                existing.sourceUserId = notification.sourceUserId
            } else {
                let sd = SDNotification(
                    id: notification.id,
                    userId: notification.userId,
                    type: notification.type.rawValue,
                    title: notification.title,
                    body: notification.body,
                    read: notification.read,
                    pinned: notification.pinned,
                    createdAt: notification.createdAt,
                    rideId: notification.rideId,
                    favorId: notification.favorId,
                    conversationId: notification.conversationId,
                    reviewId: notification.reviewId,
                    townHallPostId: notification.townHallPostId,
                    sourceUserId: notification.sourceUserId
                )
                context.insert(sd)
            }
        }
    }

    func refreshNotifications() async {
        await loadNotifications(forceRefresh: true)
    }

    func markAsRead(_ notification: AppNotification) async {
        guard !notification.read else { return }

        do {
            markNotificationsReadLocally([notification.id])
            try await notificationService.markAsRead(notificationId: notification.id)
            if modelContext == nil {
                await loadNotifications()
            }
            await badgeManager.refreshAllBadges(reason: "notificationMarkedRead")
        } catch {
            self.error = AppError.processingError(error.localizedDescription)
            AppLogger.error("notifications", "Error marking notification as read: \(error.localizedDescription)")
        }
    }

    func markAllAsRead() async {
        guard let userId = authService.currentUserId else { return }

        do {
            markAllBellNotificationsReadLocally()
            try await notificationService.markAllBellNotificationsAsRead(userId: userId)
            if modelContext == nil {
                await loadNotifications()
            }
            await badgeManager.refreshAllBadges(reason: "notificationsMarkAllRead")
        } catch {
            self.error = AppError.processingError(error.localizedDescription)
            AppLogger.error("notifications", "Error marking all notifications as read: \(error.localizedDescription)")
        }
    }

    /// Types that require explicit user action and should NOT be bulk-marked as read
    private static let bulkReadExcludedTypes: Set<NotificationType> = [
        .reviewRequest, .reviewReminder, .completionReminder
    ]

    private func markAllBellNotificationsReadLocally() {
        guard let context = modelContext, let userId = authService.currentUserId else { return }
        let fetchDescriptor = FetchDescriptor<SDNotification>(predicate: #Predicate { $0.userId == userId })
        if let notifications = try? context.fetch(fetchDescriptor) {
            for notification in notifications {
                guard let type = NotificationType(rawValue: notification.type),
                      !NotificationGrouping.messageTypes.contains(type),
                      !Self.bulkReadExcludedTypes.contains(type) else { continue }
                notification.read = true
            }
            try? context.save()
            refreshUnreadCount(from: context, userId: userId)
        }
    }

    private func markNotificationsReadLocally(_ ids: [UUID]) {
        guard let context = modelContext, let userId = authService.currentUserId else { return }
        for id in ids {
            let fetchDescriptor = FetchDescriptor<SDNotification>(predicate: #Predicate { $0.id == id })
            if let notification = try? context.fetch(fetchDescriptor).first {
                notification.read = true
            }
        }
        try? context.save()
        refreshUnreadCount(from: context, userId: userId)
    }

    private func refreshUnreadCount(from context: ModelContext, userId: UUID) {
        let fetchDescriptor = FetchDescriptor<SDNotification>(predicate: #Predicate { $0.userId == userId })
        if let notifications = try? context.fetch(fetchDescriptor) {
            let filtered = getFilteredNotifications(sdNotifications: notifications)
            unreadCount = filtered.filter { !$0.read }.count
        }
    }

    func handleNotificationTap(_ notification: AppNotification, group: NotificationGroup? = nil) {
        navigationRouter.handleNotificationTap(
            notification,
            group: group,
            markAsRead: { [weak self] tapped in
                Task { @MainActor [weak self] in
                    await self?.markAsRead(tapped)
                }
            },
            markGroupAsRead: { [weak self] tappedGroup in
                self?.markGroupAsRead(tappedGroup)
            },
            handleReviewPromptNotification: { [weak self] tapped in
                self?.handleReviewPromptNotification(tapped)
            }
        )
    }

    func handleAnnouncementTap(_ notification: AppNotification) {
        navigationRouter.handleAnnouncementTap(notification) { [weak self] tapped in
            Task { @MainActor [weak self] in
                await self?.markAsRead(tapped)
            }
        }
    }

    private func markGroupAsRead(_ group: NotificationGroup) {
        let notificationsToMark = group.notifications.filter { shouldMarkReadOnTap($0.type) && !$0.read }
        guard !notificationsToMark.isEmpty else { return }

        Task { [weak self] in
            guard let self = self, !Task.isCancelled else { return }
            self.markNotificationsReadLocally(notificationsToMark.map { $0.id })
            for notification in notificationsToMark {
                try? await self.notificationService.markAsRead(notificationId: notification.id)
            }
            if self.modelContext == nil {
                await self.loadNotifications()
            }
            await self.badgeManager.refreshAllBadges(reason: "notificationGroupMarkedRead")
        }
    }

    private func shouldMarkReadOnTap(_ type: NotificationType) -> Bool {
        switch type {
        case .reviewRequest, .reviewReminder, .completionReminder:
            return false
        default:
            return true
        }
    }

    private func handleReviewPromptNotification(_ notification: AppNotification) {
        if let rideId = notification.rideId {
            NotificationCenter.default.post(
                name: .showReviewPrompt,
                object: nil,
                userInfo: ["rideId": rideId]
            )
        } else if let favorId = notification.favorId {
            NotificationCenter.default.post(
                name: .showReviewPrompt,
                object: nil,
                userInfo: ["favorId": favorId]
            )
        }
    }

    private func handleRealtimeReload(reason: String, fallback: Bool) async {
        AppLogger.info("notifications", "[NotificationsListVM] Coalesced realtime reload: \(reason)")
        if let context = modelContext, let userId = authService.currentUserId {
            refreshUnreadCount(from: context, userId: userId)
            if fallback {
                await loadNotifications(forceRefresh: false)
            }
        } else {
            await loadNotifications(forceRefresh: !fallback)
        }
    }
}
