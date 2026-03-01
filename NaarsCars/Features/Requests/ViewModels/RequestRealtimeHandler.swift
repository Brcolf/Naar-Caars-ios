//
//  RequestRealtimeHandler.swift
//  NaarsCars
//
//  Handles requests dashboard sync notifications and coalescing
//

import Foundation
import SwiftData
import Observation

/// Handles requests dashboard refreshes driven by centralized sync-engine notifications.
@MainActor
@Observable
final class RequestRealtimeHandler {
    private var requestsReloadTask: Task<Void, Never>?
    private var requestNotificationRefreshTask: Task<Void, Never>?

    private var ridesDidSyncObserver: NSObjectProtocol?
    private var favorsDidSyncObserver: NSObjectProtocol?
    private var notificationsDidSyncObserver: NSObjectProtocol?

    private var modelContextProvider: (() -> ModelContext?)?
    private var refreshFilteredRequests: (() -> Void)?
    private var refreshRequestSummaries: (() async -> Void)?
    private var loadRequestsForceRefresh: (() async -> Void)?

    func configure(
        modelContextProvider: @escaping () -> ModelContext?,
        authUserIdProvider: @escaping () -> UUID?,
        syncRidesToSwiftData: @escaping ([Ride], ModelContext) -> Void,
        syncFavorsToSwiftData: @escaping ([Favor], ModelContext) -> Void,
        refreshFilteredRequests: @escaping () -> Void,
        refreshRequestSummaries: @escaping () async -> Void,
        loadRequestsForceRefresh: @escaping () async -> Void
    ) {
        self.modelContextProvider = modelContextProvider
        self.refreshFilteredRequests = refreshFilteredRequests
        self.refreshRequestSummaries = refreshRequestSummaries
        self.loadRequestsForceRefresh = loadRequestsForceRefresh
    }

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
            AppLogger.info("requests", "[RequestRealtimeHandler] Coalesced sync refresh: \(reason)")
            await self.loadRequestsForceRefresh?()
            self.refreshFilteredRequests?()
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
