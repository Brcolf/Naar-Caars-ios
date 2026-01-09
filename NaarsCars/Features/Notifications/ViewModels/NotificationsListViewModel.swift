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
    
    init() {
        setupRealtimeSubscription()
    }
    
    deinit {
        Task {
            await unsubscribeFromNotifications()
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
            Task {
                await markAsRead(notification)
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
            // Navigate to notifications tab for announcements
            coordinator.selectedTab = .notifications
            coordinator.navigateToNotifications = true
            
        default:
            break
        }
    }
    
    private func setupRealtimeSubscription() {
        Task {
            await realtimeManager.subscribe(
                channelName: "notifications:all",
                table: "notifications",
                onInsert: { [weak self] _ in
                    Task { @MainActor [weak self] in
                        await self?.loadNotifications()
                    }
                },
                onUpdate: { [weak self] _ in
                    Task { @MainActor [weak self] in
                        await self?.loadNotifications()
                    }
                },
                onDelete: { [weak self] _ in
                    Task { @MainActor [weak self] in
                        await self?.loadNotifications()
                    }
                }
            )
        }
    }
    
    private func unsubscribeFromNotifications() async {
        await realtimeManager.unsubscribe(channelName: "notifications:all")
    }
    
    private func handleNewNotification(_ newNotification: AppNotification) {
        // Only add if it's for the current user
        guard newNotification.userId == authService.currentUserId else { return }
        
        // Reload to get full list with proper ordering
        Task {
            await loadNotifications()
        }
    }
    
    private func handleNotificationUpdate(_ updatedNotification: AppNotification) {
        // Only update if it's for the current user
        guard updatedNotification.userId == authService.currentUserId else { return }
        
        if let index = notifications.firstIndex(where: { $0.id == updatedNotification.id }) {
            notifications[index] = updatedNotification
        } else {
            // Reload if not found
            Task {
                await loadNotifications()
            }
        }
    }
    
    private func handleNotificationDelete(_ deletedNotification: AppNotification) {
        notifications.removeAll { $0.id == deletedNotification.id }
    }
}



