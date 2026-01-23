//
//  NotificationsListViewModel.swift
//  NaarsCars
//
//  ViewModel for notifications list
//

import Foundation
import SwiftData
internal import Combine
import Realtime

/// ViewModel for notifications list
@MainActor
final class NotificationsListViewModel: ObservableObject {
    @Published var isLoading: Bool = false
    @Published var error: AppError?
    @Published var unreadCount: Int = 0
    
    private var modelContext: ModelContext?
    private let notificationService = NotificationService.shared
    private let authService = AuthService.shared
    private let realtimeManager = RealtimeManager.shared
    private let badgeManager = BadgeCountManager.shared
    private var subscriptionTask: Task<Void, Never>?
    
    init() {
        setupRealtimeSubscription()
    }
    
    deinit {
        // Cancel any active subscription task
        subscriptionTask?.cancel()
        subscriptionTask = nil
        
        // Unsubscribe from realtime - use Task.detached to avoid capturing self
        let manager = RealtimeManager.shared
        Task.detached {
            await manager.unsubscribe(channelName: "notifications:all")
        }
    }
    
    /// Set up the model context for SwiftData operations
    func setup(modelContext: ModelContext) {
        self.modelContext = modelContext
    }
    
    /// Get filtered notifications from SwiftData models
    func getFilteredNotifications(sdNotifications: [SDNotification]) -> [AppNotification] {
        let notifications = sdNotifications.map { sd in
            AppNotification(
                id: sd.id,
                userId: sd.userId,
                type: NotificationType(rawValue: sd.type) ?? .other,
                title: sd.title,
                body: sd.body,
                read: sd.read,
                pinned: sd.pinned,
                createdAt: sd.createdAt,
                rideId: sd.rideId,
                favorId: sd.favorId,
                conversationId: sd.conversationId,
                reviewId: sd.reviewId,
                townHallPostId: sd.townHallPostId,
                sourceUserId: sd.sourceUserId
            )
        }
        return NotificationGrouping.filterBellNotifications(from: notifications)
    }
    
    /// Get notification groups from SwiftData models
    func getNotificationGroups(sdNotifications: [SDNotification]) -> [NotificationGroup] {
        let filtered = getFilteredNotifications(sdNotifications: sdNotifications)
        return NotificationGrouping.groupBellNotifications(from: filtered)
    }
    
    func loadNotifications(forceRefresh: Bool = false) async {
        guard let userId = authService.currentUserId else {
            error = .notAuthenticated
            return
        }
        
        isLoading = true
        error = nil
        
        do {
            let fetched = try await notificationService.fetchNotifications(userId: userId, forceRefresh: forceRefresh)
            
            // Sync to SwiftData
            if let context = modelContext {
                syncNotificationsToSwiftData(fetched, in: context)
                try? context.save()
            }
            
            self.unreadCount = try await notificationService.fetchUnreadCount(userId: userId)
        } catch {
            self.error = AppError.processingError(error.localizedDescription)
            print("🔴 Error loading notifications: \(error.localizedDescription)")
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
        guard let userId = authService.currentUserId else { return }
        await CacheManager.shared.invalidateNotifications(userId: userId)
        await loadNotifications(forceRefresh: true)
    }
    
    func markAsRead(_ notification: AppNotification) async {
        guard !notification.read else { return }
        
        do {
            try await notificationService.markAsRead(notificationId: notification.id)
            await loadNotifications() // Reload to update UI
            await badgeManager.refreshAllBadges(reason: "notificationMarkedRead")
        } catch {
            self.error = AppError.processingError(error.localizedDescription)
            print("🔴 Error marking notification as read: \(error.localizedDescription)")
        }
    }
    
    func markAllAsRead() async {
        guard let userId = authService.currentUserId else { return }
        
        do {
            try await notificationService.markAllBellNotificationsAsRead(userId: userId)
            await loadNotifications() // Reload to update UI
            await badgeManager.refreshAllBadges(reason: "notificationsMarkAllRead")
        } catch {
            self.error = AppError.processingError(error.localizedDescription)
            print("🔴 Error marking all notifications as read: \(error.localizedDescription)")
        }
    }

    func handleNotificationTap(_ notification: AppNotification, group: NotificationGroup? = nil) {
        if NotificationGrouping.announcementTypes.contains(notification.type) {
            handleAnnouncementTap(notification)
            return
        }

        if let group = group {
            markGroupAsRead(group)
        } else if shouldMarkReadOnTap(notification.type) && !notification.read {
            Task { [weak self] in
                guard let self = self, !Task.isCancelled else { return }
                await self.markAsRead(notification)
            }
        }

        // Post notification to dismiss the bell dropdown/sheet
        NotificationCenter.default.post(name: .dismissNotificationsSurface, object: nil)

        handleNotificationNavigation(for: notification)
    }

    func handleAnnouncementTap(_ notification: AppNotification) {
        if !notification.read {
            Task { [weak self] in
                guard let self = self, !Task.isCancelled else { return }
                await self.markAsRead(notification)
            }
        }
        
        // Post notification to dismiss the bell dropdown/sheet
        NotificationCenter.default.post(name: .dismissNotificationsSurface, object: nil)
        
        print("🔔 [NotificationsListViewModel] Announcement tapped: \(notification.id)")
    }

    private func markGroupAsRead(_ group: NotificationGroup) {
        let notificationsToMark = group.notifications.filter { shouldMarkReadOnTap($0.type) && !$0.read }
        guard !notificationsToMark.isEmpty else { return }

        Task { [weak self] in
            guard let self = self, !Task.isCancelled else { return }
            for notification in notificationsToMark {
                try? await self.notificationService.markAsRead(notificationId: notification.id)
            }
            await self.loadNotifications()
            await self.badgeManager.refreshAllBadges(reason: "notificationGroupMarkedRead")
        }
    }

    private func handleNotificationNavigation(for notification: AppNotification) {
        let coordinator = NavigationCoordinator.shared
        
        // 1. Check if this is a request notification that needs specific anchor routing
        if let target = RequestNotificationMapping.target(
            for: notification.type,
            rideId: notification.rideId,
            favorId: notification.favorId
        ) {
            print("📍 [NotificationsListVM] Request target found: \(target.anchor.rawValue)")
            coordinator.selectedTab = .requests
            
            // Set the detailed navigation target FIRST
            coordinator.requestNavigationTarget = target
            
            // Then trigger the navigation to the specific ID
            switch target.requestType {
            case .ride:
                coordinator.navigateToRide = target.requestId
            case .favor:
                coordinator.navigateToFavor = target.requestId
            }
            return // Exit early as we've handled the navigation
        }

        // 2. Fallback to generic type-based navigation
        switch notification.type {
        case .newRide, .rideUpdate, .rideClaimed, .rideUnclaimed, .rideCompleted,
             .qaActivity, .qaQuestion, .qaAnswer, .completionReminder:
            if let rideId = notification.rideId {
                coordinator.selectedTab = .requests
                coordinator.navigateToRide = rideId
            }

        case .newFavor, .favorUpdate, .favorClaimed, .favorUnclaimed, .favorCompleted:
            if let favorId = notification.favorId {
                coordinator.selectedTab = .requests
                coordinator.navigateToFavor = favorId
            }

        case .message, .addedToConversation:
            if let conversationId = notification.conversationId {
                coordinator.selectedTab = .messages
                coordinator.navigateToConversation = conversationId
            }

        case .reviewRequest, .reviewReminder:
            if let rideId = notification.rideId {
                coordinator.selectedTab = .requests
                coordinator.navigateToRide = rideId
                if coordinator.requestNavigationTarget == nil {
                    coordinator.requestNavigationTarget = RequestNotificationMapping.target(
                        for: notification.type,
                        rideId: rideId,
                        favorId: nil
                    )
                }
                NotificationCenter.default.post(
                    name: .showReviewPrompt,
                    object: nil,
                    userInfo: ["rideId": rideId]
                )
            } else if let favorId = notification.favorId {
                coordinator.selectedTab = .requests
                coordinator.navigateToFavor = favorId
                if coordinator.requestNavigationTarget == nil {
                    coordinator.requestNavigationTarget = RequestNotificationMapping.target(
                        for: notification.type,
                        rideId: nil,
                        favorId: favorId
                    )
                }
                NotificationCenter.default.post(
                    name: .showReviewPrompt,
                    object: nil,
                    userInfo: ["favorId": favorId]
                )
            }

        case .townHallPost:
            if let postId = notification.townHallPostId {
                coordinator.selectedTab = .community
                coordinator.townHallNavigationTarget = .init(postId: postId, mode: .openComments)
            }

        case .townHallComment, .townHallReaction:
            if let postId = notification.townHallPostId {
                coordinator.selectedTab = .community
                coordinator.townHallNavigationTarget = .init(postId: postId, mode: .highlightPost)
            }

        case .pendingApproval:
            coordinator.selectedTab = .profile
            coordinator.navigateToPendingUsers = true

        case .reviewReceived:
            coordinator.selectedTab = .profile
            coordinator.profileScrollTarget = "profile.myProfile.reviewsSection"

        case .userApproved:
            coordinator.navigate(to: .enterApp)

        case .adminAnnouncement, .announcement, .broadcast:
            handleAnnouncementTap(notification)

        case .other:
            coordinator.selectedTab = .requests

        default:
            break
        }
    }

    private func shouldMarkReadOnTap(_ type: NotificationType) -> Bool {
        switch type {
        case .reviewRequest, .reviewReminder:
            return false
        default:
            return true
        }
    }
    
    private func setupRealtimeSubscription() {
        // Store the task so we can cancel it in deinit
        // Use RealtimeManager.shared directly to avoid capturing self
        let manager = RealtimeManager.shared
        subscriptionTask = Task { [weak self] in
            guard let self = self, let userId = self.authService.currentUserId else { return }
            let userFilter = "user_id=eq.\(userId.uuidString)"
            await manager.subscribe(
                channelName: "notifications:all",
                table: "notifications",
                filter: userFilter,
                onInsert: { [weak self] payload in
                    Task { @MainActor [weak self] in
                        guard let self = self, !Task.isCancelled else { return }
                        guard self.shouldProcessRealtimePayload(payload) else { return }
                        if let userId = self.authService.currentUserId {
                            await CacheManager.shared.invalidateNotifications(userId: userId)
                        }
                        await self.loadNotifications(forceRefresh: true)
                        await self.badgeManager.refreshAllBadges(reason: "notificationInsertRealtime")
                    }
                },
                onUpdate: { [weak self] payload in
                    Task { @MainActor [weak self] in
                        guard let self = self, !Task.isCancelled else { return }
                        guard self.shouldProcessRealtimePayload(payload) else { return }
                        if let userId = self.authService.currentUserId {
                            await CacheManager.shared.invalidateNotifications(userId: userId)
                        }
                        await self.loadNotifications(forceRefresh: true)
                        await self.badgeManager.refreshAllBadges(reason: "notificationUpdateRealtime")
                    }
                },
                onDelete: { [weak self] payload in
                    Task { @MainActor [weak self] in
                        guard let self = self, !Task.isCancelled else { return }
                        guard self.shouldProcessRealtimePayload(payload) else { return }
                        if let userId = self.authService.currentUserId {
                            await CacheManager.shared.invalidateNotifications(userId: userId)
                        }
                        await self.loadNotifications(forceRefresh: true)
                        await self.badgeManager.refreshAllBadges(reason: "notificationDeleteRealtime")
                    }
                }
            )
        }
    }
    
    private func unsubscribeFromNotifications() async {
        // Cancel the subscription task first
        subscriptionTask?.cancel()
        subscriptionTask = nil
        await realtimeManager.unsubscribe(channelName: "notifications:all")
    }
    
    private func handleNewNotification(_ newNotification: AppNotification) {
        // Only add if it's for the current user
        guard newNotification.userId == authService.currentUserId else { return }
        
        // Reload to get full list with proper ordering
        Task { [weak self] in
            guard let self = self, !Task.isCancelled else { return }
            await self.loadNotifications()
        }
    }
    
    private func handleNotificationUpdate(_ updatedNotification: AppNotification) {
        // Only update if it's for the current user
        guard updatedNotification.userId == authService.currentUserId else { return }
        
        // Reload if not found in local store (handled by sync engine)
        Task { [weak self] in
            guard let self = self, !Task.isCancelled else { return }
            await self.loadNotifications()
        }
    }
    
    private func handleNotificationDelete(_ deletedNotification: AppNotification) {
        // Reload to update local store (handled by sync engine)
        Task { [weak self] in
            guard let self = self, !Task.isCancelled else { return }
            await self.loadNotifications()
        }
    }

    private func shouldProcessRealtimePayload(_ payload: Any) -> Bool {
        guard let record = extractRecord(from: payload),
              let type = record["type"] as? String else {
            return true
        }

        return type != NotificationType.message.rawValue &&
            type != NotificationType.addedToConversation.rawValue
    }

    private func extractRecord(from payload: Any) -> [String: Any]? {
        if let insertAction = payload as? InsertAction {
            return insertAction.record
        }

        if let dict = payload as? [String: Any] {
            return dict["record"] as? [String: Any] ?? dict
        }

        return nil
    }
}



