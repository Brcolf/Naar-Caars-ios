//
//  NotificationRealtimeHandler.swift
//  NaarsCars
//
//  Handles notifications realtime subscriptions and debounced reloads
//

import Foundation
internal import Combine

/// Extracted realtime subscription/debounce handling for notifications.
@MainActor
final class NotificationRealtimeHandler: ObservableObject {
    private enum RealtimeNotificationDecision {
        case ignore
        case refresh
        case fallbackRefresh
    }

    private let realtimeManager: RealtimeManager
    private let authService: AuthService
    private let badgeManager: BadgeCountManager
    private var subscriptionTask: Task<Void, Never>?
    private var realtimeReloadTask: Task<Void, Never>?

    init(
        realtimeManager: RealtimeManager = .shared,
        authService: AuthService = .shared,
        badgeManager: BadgeCountManager = .shared
    ) {
        self.realtimeManager = realtimeManager
        self.authService = authService
        self.badgeManager = badgeManager
    }

    func setupRealtimeSubscription(
        onRealtimeReload: @escaping @MainActor (_ reason: String, _ fallback: Bool) async -> Void
    ) {
        subscriptionTask = Task { [weak self] in
            guard let self, let userId = self.authService.currentUserId else { return }
            let userFilter = "user_id=eq.\(userId.uuidString)"
            await self.realtimeManager.subscribe(
                channelName: "notifications:all",
                table: "notifications",
                filter: userFilter,
                onInsert: { [weak self] record in
                    Task { @MainActor [weak self] in
                        self?.handleRealtimeEvent(record, reason: "notificationInsertRealtime", onRealtimeReload: onRealtimeReload)
                    }
                },
                onUpdate: { [weak self] record in
                    Task { @MainActor [weak self] in
                        self?.handleRealtimeEvent(record, reason: "notificationUpdateRealtime", onRealtimeReload: onRealtimeReload)
                    }
                },
                onDelete: { [weak self] record in
                    Task { @MainActor [weak self] in
                        self?.handleRealtimeEvent(record, reason: "notificationDeleteRealtime", onRealtimeReload: onRealtimeReload)
                    }
                }
            )
        }
    }

    func stop() async {
        subscriptionTask?.cancel()
        subscriptionTask = nil
        realtimeReloadTask?.cancel()
        realtimeReloadTask = nil
        await realtimeManager.unsubscribe(channelName: "notifications:all")
    }

    private func handleRealtimeEvent(
        _ event: RealtimeRecord,
        reason: String,
        onRealtimeReload: @escaping @MainActor (_ reason: String, _ fallback: Bool) async -> Void
    ) {
        switch realtimeDecision(for: event) {
        case .ignore:
            return
        case .refresh:
            scheduleRealtimeReload(reason: reason, fallback: false, onRealtimeReload: onRealtimeReload)
        case .fallbackRefresh:
            scheduleRealtimeReload(reason: "\(reason):fallback", fallback: true, onRealtimeReload: onRealtimeReload)
        }
    }

    private func realtimeDecision(for event: RealtimeRecord) -> RealtimeNotificationDecision {
        guard let type = event.record["type"] as? String else {
            return .fallbackRefresh
        }

        if type == NotificationType.message.rawValue || type == NotificationType.addedToConversation.rawValue {
            return .ignore
        }
        return .refresh
    }

    private func scheduleRealtimeReload(
        reason: String,
        fallback: Bool,
        onRealtimeReload: @escaping @MainActor (_ reason: String, _ fallback: Bool) async -> Void
    ) {
        realtimeReloadTask?.cancel()
        let debounce = fallback
            ? Constants.Timing.notificationsRealtimeFallbackReloadDebounceNanoseconds
            : Constants.Timing.notificationsRealtimeReloadDebounceNanoseconds
        realtimeReloadTask = Task { [weak self] in
            try? await Task.sleep(nanoseconds: debounce)
            guard let self, !Task.isCancelled else { return }
            AppLogger.info("notifications", "[NotificationRealtimeHandler] Coalesced realtime reload: \(reason)")
            await onRealtimeReload(reason, fallback)
            await self.badgeManager.refreshAllBadges(reason: reason)
        }
    }
}
