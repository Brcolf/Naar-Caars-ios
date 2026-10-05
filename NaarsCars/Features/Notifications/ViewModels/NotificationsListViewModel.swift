//
//  NotificationsListViewModel.swift
//  NaarsCars
//
//  ViewModel for notifications list
//

import Foundation
import Observation
import SwiftData
internal import Combine

/// ViewModel for notifications list
@MainActor
@Observable final class NotificationsListViewModel {
    var isLoading: Bool = false
    var error: AppError?
    var unreadCount: Int = 0

    private var modelContext: ModelContext?
    private let notificationService: any NotificationServiceProtocol
    private let authService: any AuthServiceProtocol
    private let groupingManager: NotificationGroupingManager
    private let navigationRouter: NotificationNavigationRouter
    private let realtimeHandler: NotificationRealtimeHandler
    /// In-flight load/refresh task; cancelled in stop() and on next load to avoid use-after-free when view disappears.
    private var loadTask: Task<Void, Never>?

    init(
        notificationService: any NotificationServiceProtocol = NotificationService.shared,
        authService: any AuthServiceProtocol = AuthService.shared
    ) {
        self.notificationService = notificationService
        self.authService = authService
        groupingManager = NotificationGroupingManager()
        navigationRouter = NotificationNavigationRouter()
        realtimeHandler = NotificationRealtimeHandler()
        // Realtime subscription setup is deferred to setup(modelContext:) so that
        // throwaway instances (created by @State default evaluation during parent
        // body re-evaluation) stay lightweight and don't register observers.
        #if DEBUG
        print("[NotificationsListVM] init")
        #endif
    }

    deinit {
        #if DEBUG
        print("[NotificationsListVM] deinit")
        #endif
        // Cleanup is done in stop() from onDisappear. Do not start Task or touch MainActor state here (deinit is nonisolated).
    }

    /// Call from view onDisappear to cancel in-flight work and realtime subscription so VM can tear down safely.
    func stop() {
        AppLogger.info("notifications", "[NotificationsListVM] stop() called; cancelling loadTask and realtime observer")
        loadTask?.cancel()
        loadTask = nil
        realtimeHandler.cancelAndRemoveObserver()
    }

    /// Set up the model context and realtime subscription.
    /// Called from .task — only runs for the VM that actually renders (not throwaway @State instances).
    func setup(modelContext: ModelContext) {
        self.modelContext = modelContext
        realtimeHandler.setupRealtimeSubscription { [weak self] reason in
            await self?.handleRealtimeReload(reason: reason)
        }
    }

    /// Get filtered notifications from SwiftData models
    func getFilteredNotifications(sdNotifications: [SDNotification]) -> [AppNotification] {
        groupingManager.getFilteredNotifications(sdNotifications: sdNotifications)
    }

    /// Get notification groups from SwiftData models
    func getNotificationGroups(sdNotifications: [SDNotification]) -> [NotificationGroup] {
        groupingManager.getNotificationGroups(sdNotifications: sdNotifications)
    }

    /// Get precomputed grouped notifications (pinned + date-sectioned) for display
    func computeGroupedNotifications(sdNotifications: [SDNotification]) -> GroupedNotifications {
        groupingManager.computeGroupedNotifications(sdNotifications: sdNotifications)
    }

    /// Load notifications. Persistence is owned by `RefreshCoordinator` → `DashboardSyncEngine`
    /// (notifications are part of the `.dashboard` domain) → `BackgroundSyncActor`; the views'
    /// `@Query` re-renders and this method only recomputes `unreadCount` from SwiftData.
    func loadNotifications(forceRefresh: Bool = false) async {
        loadTask?.cancel()
        loadTask = Task { @MainActor in
            defer { loadTask = nil }
            guard !Task.isCancelled else { return }
            guard let userId = authService.currentUserId else {
                error = .notAuthenticated
                return
            }
            #if DEBUG
            print("[NotificationsListVM] loadNotifications start forceRefresh=\(forceRefresh)")
            #endif
            isLoading = true
            error = nil
            if let context = modelContext {
                refreshUnreadCount(from: context, userId: userId)
            }
            guard !Task.isCancelled else { isLoading = false; return }
            let result = await RefreshCoordinator.shared.forceFullRefreshAndWait(
                .dashboard,
                trigger: forceRefresh ? "pullToRefresh:notifications" : "manualReload:notifications"
            )
            guard !Task.isCancelled else { isLoading = false; return }
            if case .failed(let error, _)? = result {
                self.error = AppError.processingError(error.localizedDescription)
                AppLogger.error("notifications", "Error loading notifications: \(error.localizedDescription)")
            } else if let context = modelContext {
                refreshUnreadCount(from: context, userId: userId)
            }
            isLoading = false
            #if DEBUG
            print("[NotificationsListVM] loadNotifications end cancelled=\(Task.isCancelled)")
            #endif
        }
        await loadTask?.value
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
            _ = await RefreshCoordinator.shared.forceFullRefreshAndWait(.badges, trigger: "notificationMarkedRead")
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
            _ = await RefreshCoordinator.shared.forceFullRefreshAndWait(.badges, trigger: "notificationsMarkAllRead")
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
            await withTaskGroup(of: Void.self) { group in
                for notification in notificationsToMark {
                    group.addTask {
                        try? await self.notificationService.markAsRead(notificationId: notification.id)
                    }
                }
            }
            if self.modelContext == nil {
                await self.loadNotifications()
            }
            _ = await RefreshCoordinator.shared.forceFullRefreshAndWait(.badges, trigger: "notificationGroupMarkedRead")
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

    /// Local-only reload used after `DashboardSyncEngine` posts `.notificationsDidSync`.
    ///
    /// `BackgroundSyncActor` has already written the fresh rows to SwiftData and the list itself
    /// is `@Query`-driven, so only the derived `unreadCount` needs recomputing. This must never
    /// hit the network: `RefreshCoordinator` is the single owner of refresh decisions.
    private func handleRealtimeReload(reason: String) async {
        AppLogger.info("notifications", "[NotificationsListVM] Coalesced local reload after sync: \(reason)")
        guard let context = modelContext, let userId = authService.currentUserId else { return }
        refreshUnreadCount(from: context, userId: userId)
    }
}
