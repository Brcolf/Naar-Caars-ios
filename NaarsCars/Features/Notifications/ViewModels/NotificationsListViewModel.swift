//
//  NotificationsListViewModel.swift
//  NaarsCars
//
//  ViewModel for notifications list
//

import Foundation
internal import Combine

/// ViewModel for notifications list
@MainActor
final class NotificationsListViewModel: ObservableObject {
    @Published var notifications: [AppNotification] = []
    @Published var isLoading: Bool = false
    @Published var error: AppError?
    @Published var unreadCount: Int = 0
    
    private let notificationService = NotificationService.shared
    private let authService = AuthService.shared
    private let realtimeManager = RealtimeManager.shared
    private var subscriptionTask: Task<Void, Never>?
    
    init() {
        setupRealtimeSubscription()
    }
    
    deinit {
        // Cancel any active subscription task
        subscriptionTask?.cancel()
        subscriptionTask = nil
        
        // Unsubscribe from realtime - use Task.detached to avoid capturing self
        // Note: RealtimeManager.unsubscribeAll() is already called during sign out,
        // but we ensure cleanup here as well. Since RealtimeManager.shared is a singleton,
        // we can reference it directly without capturing self.
        let manager = RealtimeManager.shared
        Task.detached {
            await manager.unsubscribe(channelName: "notifications:all")
        }
    }
    
    func loadNotifications() async {
        guard let userId = authService.currentUserId else {
            error = .notAuthenticated
            return
        }
        
        isLoading = true
        error = nil
        
        do {
            self.notifications = try await notificationService.fetchNotifications(userId: userId)
            self.unreadCount = try await notificationService.fetchUnreadCount(userId: userId)
        } catch {
            self.error = AppError.processingError(error.localizedDescription)
            print("🔴 Error loading notifications: \(error.localizedDescription)")
        }
        
        isLoading = false
    }
    
    func refreshNotifications() async {
        guard let userId = authService.currentUserId else { return }
        await CacheManager.shared.invalidateNotifications(userId: userId)
        await loadNotifications()
    }
    
    func markAsRead(_ notification: AppNotification) async {
        guard !notification.read else { return }
        
        do {
            try await notificationService.markAsRead(notificationId: notification.id)
            await loadNotifications() // Reload to update UI
        } catch {
            self.error = AppError.processingError(error.localizedDescription)
            print("🔴 Error marking notification as read: \(error.localizedDescription)")
        }
    }
    
    func markAllAsRead() async {
        guard let userId = authService.currentUserId else { return }
        
        do {
            try await notificationService.markAllAsRead(userId: userId)
            await loadNotifications() // Reload to update UI
        } catch {
            self.error = AppError.processingError(error.localizedDescription)
            print("🔴 Error marking all notifications as read: \(error.localizedDescription)")
        }
    }
    
    func handleNotificationTap(_ notification: AppNotification) {
        // Mark as read if unread
        if !notification.read {
            Task { [weak self] in
                guard let self = self, !Task.isCancelled else { return }
                await self.markAsRead(notification)
            }
        }
        
        // Navigate based on notification type and associated IDs
        let coordinator = NavigationCoordinator.shared
        
        switch notification.type {
        case .rideClaimed, .rideUnclaimed, .qaActivity:
            if let rideId = notification.rideId {
                coordinator.selectedTab = .requests
                coordinator.navigateToRide = rideId
            }
            
        case .favorClaimed, .favorUnclaimed:
            if let favorId = notification.favorId {
                coordinator.selectedTab = .requests
                coordinator.navigateToFavor = favorId
            }
            
        case .message:
            if let conversationId = notification.conversationId {
                coordinator.selectedTab = .messages
                coordinator.navigateToConversation = conversationId
            }
            
        case .adminAnnouncement, .other:
            // Notifications tab removed - navigate to appropriate tab based on notification type
            // For admin announcements, navigate to profile tab (admin panel)
            if notification.type == .adminAnnouncement {
                coordinator.selectedTab = .profile
            } else {
                coordinator.selectedTab = .requests
            }
            
        default:
            break
        }
    }
    
    private func setupRealtimeSubscription() {
        // Store the task so we can cancel it in deinit
        // Use RealtimeManager.shared directly to avoid capturing self
        let manager = RealtimeManager.shared
        subscriptionTask = Task { [weak self] in
            await manager.subscribe(
                channelName: "notifications:all",
                table: "notifications",
                onInsert: { [weak self] _ in
                    Task { @MainActor [weak self] in
                        guard let self = self, !Task.isCancelled else { return }
                        await self.loadNotifications()
                    }
                },
                onUpdate: { [weak self] _ in
                    Task { @MainActor [weak self] in
                        guard let self = self, !Task.isCancelled else { return }
                        await self.loadNotifications()
                    }
                },
                onDelete: { [weak self] _ in
                    Task { @MainActor [weak self] in
                        guard let self = self, !Task.isCancelled else { return }
                        await self.loadNotifications()
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
        
        if let index = notifications.firstIndex(where: { $0.id == updatedNotification.id }) {
            notifications[index] = updatedNotification
        } else {
            // Reload if not found
            Task { [weak self] in
                guard let self = self, !Task.isCancelled else { return }
                await self.loadNotifications()
            }
        }
    }
    
    private func handleNotificationDelete(_ deletedNotification: AppNotification) {
        notifications.removeAll { $0.id == deletedNotification.id }
    }
}



