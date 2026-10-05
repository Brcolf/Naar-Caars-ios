//
//  RequestRealtimeHandler.swift
//  NaarsCars
//
//  NotificationCenter observer for DashboardSyncEngine's .ridesDidSync / .favorsDidSync /
//  .notificationsDidSync posts; coalesces them into local-only (SwiftData) reloads.
//

import Foundation
import Observation

/// NotificationCenter observer for the requests dashboard.
///
/// Despite the historical name, this type owns NO Supabase Realtime (WebSocket) subscriptions.
/// It observes the `.ridesDidSync`, `.favorsDidSync` and `.notificationsDidSync` notifications
/// that `DashboardSyncEngine` posts after `BackgroundSyncActor` has saved fresh server data to
/// SwiftData, debounces them, and asks the owning ViewModel to re-read SwiftData.
///
/// Invariant: reactions here must never fetch from the network. The data that triggered the
/// notification is already in SwiftData, and `RefreshCoordinator` is the single owner of
/// network refresh decisions. (The name is kept because the file is a classic Xcode file
/// reference; renaming it would require a `project.pbxproj` edit.)
@MainActor
@Observable
final class RequestRealtimeHandler {
    private var requestsReloadTask: Task<Void, Never>?
    private var requestNotificationRefreshTask: Task<Void, Never>?

    private var ridesDidSyncObserver: NSObjectProtocol?
    private var favorsDidSyncObserver: NSObjectProtocol?
    private var notificationsDidSyncObserver: NSObjectProtocol?

    private var reloadRequestsFromLocalStore: (() async -> Void)?
    private var refreshRequestSummaries: (() async -> Void)?

    /// - Parameters:
    ///   - reloadRequestsFromLocalStore: Re-reads rides/favors (and derived badge state) from
    ///     SwiftData. Must not perform network I/O.
    ///   - refreshRequestSummaries: Re-reads unread request-notification summaries from SwiftData.
    func configure(
        reloadRequestsFromLocalStore: @escaping () async -> Void,
        refreshRequestSummaries: @escaping () async -> Void
    ) {
        self.reloadRequestsFromLocalStore = reloadRequestsFromLocalStore
        self.refreshRequestSummaries = refreshRequestSummaries
    }

    /// Registers NotificationCenter observers for the sync notifications (not WebSocket channels).
    func setupRealtimeSubscription() {
        if ridesDidSyncObserver == nil {
            ridesDidSyncObserver = NotificationCenter.default.addObserver(
                forName: .ridesDidSync,
                object: nil,
                queue: .main
            ) { [weak self] _ in
                self?.scheduleRequestsReload(reason: "ridesDidSync")
            }
        }

        if favorsDidSyncObserver == nil {
            favorsDidSyncObserver = NotificationCenter.default.addObserver(
                forName: .favorsDidSync,
                object: nil,
                queue: .main
            ) { [weak self] _ in
                self?.scheduleRequestsReload(reason: "favorsDidSync")
            }
        }

        if notificationsDidSyncObserver == nil {
            notificationsDidSyncObserver = NotificationCenter.default.addObserver(
                forName: .notificationsDidSync,
                object: nil,
                queue: .main
            ) { [weak self] _ in
                self?.scheduleRequestNotificationRefresh(reason: "notificationsDidSync")
            }
        }
    }

    /// Cancels pending debounced reloads and removes the NotificationCenter observers.
    func cleanupRealtimeSubscription() {
        requestsReloadTask?.cancel()
        requestNotificationRefreshTask?.cancel()
        requestsReloadTask = nil
        requestNotificationRefreshTask = nil

        if let observer = ridesDidSyncObserver {
            NotificationCenter.default.removeObserver(observer)
            ridesDidSyncObserver = nil
        }
        if let observer = favorsDidSyncObserver {
            NotificationCenter.default.removeObserver(observer)
            favorsDidSyncObserver = nil
        }
        if let observer = notificationsDidSyncObserver {
            NotificationCenter.default.removeObserver(observer)
            notificationsDidSyncObserver = nil
        }
    }

    private func scheduleRequestsReload(reason: String) {
        requestsReloadTask?.cancel()
        requestsReloadTask = Task { [weak self] in
            try? await Task.sleep(nanoseconds: Constants.Timing.requestsRealtimeReloadDebounceNanoseconds)
            guard let self, !Task.isCancelled else { return }
            AppLogger.info("requests", "[RequestRealtimeHandler] Coalesced local reload after sync: \(reason)")
            await self.reloadRequestsFromLocalStore?()
        }
    }

    private func scheduleRequestNotificationRefresh(reason: String) {
        requestNotificationRefreshTask?.cancel()
        requestNotificationRefreshTask = Task { [weak self] in
            try? await Task.sleep(nanoseconds: Constants.Timing.notificationsRealtimeReloadDebounceNanoseconds)
            guard let self, !Task.isCancelled else { return }
            AppLogger.info("requests", "[RequestRealtimeHandler] Coalesced request notification refresh: \(reason)")
            await self.refreshRequestSummaries?()
        }
    }
}
