//
//  NotificationRealtimeHandler.swift
//  NaarsCars
//
//  Handles notifications sync observers and debounced reloads
//

import Foundation
internal import Combine

/// Handles debounced notifications-list refreshes from centralized sync notifications.
@MainActor
final class NotificationRealtimeHandler: ObservableObject {
    private var notificationsDidSyncObserver: NSObjectProtocol?
    private var realtimeReloadTask: Task<Void, Never>?

    func setupRealtimeSubscription(
        onRealtimeReload: @escaping @MainActor (_ reason: String, _ fallback: Bool) async -> Void
    ) {
        if notificationsDidSyncObserver == nil {
            notificationsDidSyncObserver = NotificationCenter.default.addObserver(
                forName: .notificationsDidSync,
                object: nil,
                queue: .main
            ) { [weak self] _ in
                self?.scheduleRealtimeReload(
                    reason: "notificationsDidSync",
                    fallback: false,
                    onRealtimeReload: onRealtimeReload
                )
            }
        }
    }

    func stop() async {
        cancelAndRemoveObserver()
    }

    /// Synchronous teardown for use from VM stop() or when tearing down. Cancels debounce task and removes NotificationCenter observer.
    func cancelAndRemoveObserver() {
        realtimeReloadTask?.cancel()
        realtimeReloadTask = nil
        if let observer = notificationsDidSyncObserver {
            NotificationCenter.default.removeObserver(observer)
            notificationsDidSyncObserver = nil
        }
    }

    private func scheduleRealtimeReload(
        reason: String,
        fallback: Bool,
        onRealtimeReload: @escaping @MainActor (_ reason: String, _ fallback: Bool) async -> Void
    ) {
        realtimeReloadTask?.cancel()
        realtimeReloadTask = Task { [weak self] in
            try? await Task.sleep(nanoseconds: Constants.Timing.notificationsRealtimeReloadDebounceNanoseconds)
            guard let self, !Task.isCancelled else { return }
            AppLogger.info("notifications", "[NotificationRealtimeHandler] Coalesced sync reload: \(reason)")
            await onRealtimeReload(reason, fallback)
        }
    }
}
