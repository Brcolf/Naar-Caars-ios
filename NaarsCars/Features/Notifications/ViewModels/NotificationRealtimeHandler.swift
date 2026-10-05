//
//  NotificationRealtimeHandler.swift
//  NaarsCars
//
//  NotificationCenter observer for DashboardSyncEngine's .notificationsDidSync posts;
//  coalesces them into local-only (SwiftData) reloads.
//

import Foundation
import Observation

/// NotificationCenter observer for the notifications list.
///
/// Despite the historical name, this type owns NO Supabase Realtime (WebSocket) subscriptions.
/// It observes the `.notificationsDidSync` notification that `DashboardSyncEngine` posts after
/// `BackgroundSyncActor` has saved fresh server data to SwiftData, debounces it, and invokes the
/// owning ViewModel's local reload closure.
///
/// Invariant: the reload closure must never fetch from the network. The data that triggered the
/// notification is already in SwiftData (the list itself is `@Query`-driven), and
/// `RefreshCoordinator` is the single owner of network refresh decisions. (The name is kept
/// because the file is a classic Xcode file reference; renaming it would require a
/// `project.pbxproj` edit.)
@MainActor
@Observable
final class NotificationRealtimeHandler {
    private var notificationsDidSyncObserver: NSObjectProtocol?
    private var realtimeReloadTask: Task<Void, Never>?

    /// Registers the `.notificationsDidSync` NotificationCenter observer (not a WebSocket channel).
    /// - Parameter onRealtimeReload: Local-only reload; must not perform network I/O.
    func setupRealtimeSubscription(
        onRealtimeReload: @escaping @MainActor (_ reason: String) async -> Void
    ) {
        if notificationsDidSyncObserver == nil {
            notificationsDidSyncObserver = NotificationCenter.default.addObserver(
                forName: .notificationsDidSync,
                object: nil,
                queue: .main
            ) { [weak self] _ in
                self?.scheduleRealtimeReload(
                    reason: "notificationsDidSync",
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
        onRealtimeReload: @escaping @MainActor (_ reason: String) async -> Void
    ) {
        realtimeReloadTask?.cancel()
        realtimeReloadTask = Task { [weak self] in
            try? await Task.sleep(nanoseconds: Constants.Timing.notificationsRealtimeReloadDebounceNanoseconds)
            guard let self, !Task.isCancelled else { return }
            AppLogger.info("notifications", "[NotificationRealtimeHandler] Coalesced sync reload: \(reason)")
            await onRealtimeReload(reason)
        }
    }
}
