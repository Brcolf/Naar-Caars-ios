//
//  RequestRealtimeHandler.swift
//  NaarsCars
//
//  Handles requests dashboard realtime subscriptions and coalescing
//

import Foundation
import SwiftData
internal import Combine
import Realtime

/// Extracted realtime handling for requests dashboard.
@MainActor
final class RequestRealtimeHandler: ObservableObject {
    private enum RequestNotificationDecision {
        case ignore
        case refresh
        case fallbackRefresh
    }

    private let rideService: RideService
    private let favorService: FavorService
    private let realtimeManager: RealtimeManager
    private let badgeManager: BadgeCountManager
    private let requestNotificationTypeRawValues: Set<String>

    private var requestsReloadTask: Task<Void, Never>?
    private var requestNotificationRefreshTask: Task<Void, Never>?
    private var ridesRealtimeSyncTask: Task<Void, Never>?
    private var favorsRealtimeSyncTask: Task<Void, Never>?
    private var pendingRideSyncIds = Set<UUID>()
    private var pendingFavorSyncIds = Set<UUID>()

    private var modelContextProvider: (() -> ModelContext?)?
    private var authUserIdProvider: (() -> UUID?)?
    private var syncRidesToSwiftData: (([Ride], ModelContext) -> Void)?
    private var syncFavorsToSwiftData: (([Favor], ModelContext) -> Void)?
    private var refreshFilteredRequests: (() -> Void)?
    private var refreshRequestSummaries: (() async -> Void)?
    private var loadRequestsForceRefresh: (() async -> Void)?

    init(
        rideService: RideService = .shared,
        favorService: FavorService = .shared,
        realtimeManager: RealtimeManager = .shared,
        badgeManager: BadgeCountManager = .shared
    ) {
        self.rideService = rideService
        self.favorService = favorService
        self.realtimeManager = realtimeManager
        self.badgeManager = badgeManager
        self.requestNotificationTypeRawValues = Set(NotificationGrouping.requestTypes.map(\.rawValue))
    }

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
        self.authUserIdProvider = authUserIdProvider
        self.syncRidesToSwiftData = syncRidesToSwiftData
        self.syncFavorsToSwiftData = syncFavorsToSwiftData
        self.refreshFilteredRequests = refreshFilteredRequests
        self.refreshRequestSummaries = refreshRequestSummaries
        self.loadRequestsForceRefresh = loadRequestsForceRefresh
    }

    func setupRealtimeSubscription() {
        Task {
            await realtimeManager.subscribe(
                channelName: "requests-dashboard-rides",
                table: "rides",
                filter: nil,
                onInsert: { [weak self] record in self?.handleRideRealtimeEvent(record, reason: "rideInsertRealtime") },
                onUpdate: { [weak self] record in self?.handleRideRealtimeEvent(record, reason: "rideUpdateRealtime") },
                onDelete: { [weak self] record in self?.handleRideRealtimeEvent(record, reason: "rideDeleteRealtime") }
            )

            await realtimeManager.subscribe(
                channelName: "requests-dashboard-favors",
                table: "favors",
                filter: nil,
                onInsert: { [weak self] record in self?.handleFavorRealtimeEvent(record, reason: "favorInsertRealtime") },
                onUpdate: { [weak self] record in self?.handleFavorRealtimeEvent(record, reason: "favorUpdateRealtime") },
                onDelete: { [weak self] record in self?.handleFavorRealtimeEvent(record, reason: "favorDeleteRealtime") }
            )

            if let userId = authUserIdProvider?() {
                let userFilter = "user_id=eq.\(userId.uuidString)"
                await realtimeManager.subscribe(
                    channelName: "requests-dashboard-notifications",
                    table: "notifications",
                    filter: userFilter,
                    onInsert: { [weak self] record in self?.handleRequestNotificationEvent(record, reason: "requestNotificationInsertRealtime") },
                    onUpdate: { [weak self] record in self?.handleRequestNotificationEvent(record, reason: "requestNotificationUpdateRealtime") },
                    onDelete: { [weak self] record in self?.handleRequestNotificationEvent(record, reason: "requestNotificationDeleteRealtime") }
                )
            }
        }
    }

    func cleanupRealtimeSubscription() {
        requestsReloadTask?.cancel()
        requestNotificationRefreshTask?.cancel()
        ridesRealtimeSyncTask?.cancel()
        favorsRealtimeSyncTask?.cancel()
        requestsReloadTask = nil
        requestNotificationRefreshTask = nil
        ridesRealtimeSyncTask = nil
        favorsRealtimeSyncTask = nil
        pendingRideSyncIds.removeAll()
        pendingFavorSyncIds.removeAll()

        Task {
            await realtimeManager.unsubscribe(channelName: "requests-dashboard-rides")
            await realtimeManager.unsubscribe(channelName: "requests-dashboard-favors")
            await realtimeManager.unsubscribe(channelName: "requests-dashboard-notifications")
        }
    }

    private func handleRequestNotificationEvent(_ event: RealtimeRecord, reason: String) {
        switch requestNotificationDecision(for: event) {
        case .ignore:
            return
        case .refresh:
            scheduleRequestNotificationRefresh(reason: reason, fallback: false)
        case .fallbackRefresh:
            scheduleRequestNotificationRefresh(reason: "\(reason):fallback", fallback: true)
        }
    }

    private func requestNotificationDecision(for event: RealtimeRecord) -> RequestNotificationDecision {
        guard let rawType = parseString(event.record["type"]) else {
            return .fallbackRefresh
        }
        return requestNotificationTypeRawValues.contains(rawType) ? .refresh : .ignore
    }

    private func handleRideRealtimeEvent(_ event: RealtimeRecord, reason: String) {
        guard let rideId = parseUUID(event.record["id"]) else {
            scheduleRequestsReload(reason: "\(reason):payloadFallback", fallback: true)
            return
        }
        switch event.eventType {
        case .insert, .update:
            scheduleRideRealtimeSync(rideId: rideId, reason: reason)
        case .delete:
            applyRideDeletion(rideId: rideId, reason: reason)
        }
    }

    private func handleFavorRealtimeEvent(_ event: RealtimeRecord, reason: String) {
        guard let favorId = parseUUID(event.record["id"]) else {
            scheduleRequestsReload(reason: "\(reason):payloadFallback", fallback: true)
            return
        }
        switch event.eventType {
        case .insert, .update:
            scheduleFavorRealtimeSync(favorId: favorId, reason: reason)
        case .delete:
            applyFavorDeletion(favorId: favorId, reason: reason)
        }
    }

    private func scheduleRideRealtimeSync(rideId: UUID, reason: String) {
        pendingRideSyncIds.insert(rideId)
        ridesRealtimeSyncTask?.cancel()
        ridesRealtimeSyncTask = Task { [weak self] in
            try? await Task.sleep(nanoseconds: Constants.Timing.requestsRealtimeReloadDebounceNanoseconds)
            guard let self, !Task.isCancelled else { return }
            await self.syncPendingRideRealtime(reason: reason)
        }
    }

    private func scheduleFavorRealtimeSync(favorId: UUID, reason: String) {
        pendingFavorSyncIds.insert(favorId)
        favorsRealtimeSyncTask?.cancel()
        favorsRealtimeSyncTask = Task { [weak self] in
            try? await Task.sleep(nanoseconds: Constants.Timing.requestsRealtimeReloadDebounceNanoseconds)
            guard let self, !Task.isCancelled else { return }
            await self.syncPendingFavorRealtime(reason: reason)
        }
    }

    private func syncPendingRideRealtime(reason: String) async {
        let rideIds = pendingRideSyncIds
        pendingRideSyncIds.removeAll()
        guard !rideIds.isEmpty else { return }
        guard let context = modelContextProvider?() else {
            scheduleRequestsReload(reason: "\(reason):missingContext", fallback: true)
            return
        }

        var hasFailures = false
        for rideId in rideIds {
            do {
                let ride = try await rideService.fetchRide(id: rideId)
                syncRidesToSwiftData?([ride], context)
            } catch {
                hasFailures = true
                AppLogger.warning("requests", "Failed to realtime-sync ride \(rideId): \(error.localizedDescription)")
            }
        }

        try? context.save()
        refreshFilteredRequests?()
        if hasFailures {
            scheduleRequestsReload(reason: "\(reason):fallback", fallback: true)
        }
    }

    private func syncPendingFavorRealtime(reason: String) async {
        let favorIds = pendingFavorSyncIds
        pendingFavorSyncIds.removeAll()
        guard !favorIds.isEmpty else { return }
        guard let context = modelContextProvider?() else {
            scheduleRequestsReload(reason: "\(reason):missingContext", fallback: true)
            return
        }

        var hasFailures = false
        for favorId in favorIds {
            do {
                let favor = try await favorService.fetchFavor(id: favorId)
                syncFavorsToSwiftData?([favor], context)
            } catch {
                hasFailures = true
                AppLogger.warning("requests", "Failed to realtime-sync favor \(favorId): \(error.localizedDescription)")
            }
        }

        try? context.save()
        refreshFilteredRequests?()
        if hasFailures {
            scheduleRequestsReload(reason: "\(reason):fallback", fallback: true)
        }
    }

    private func applyRideDeletion(rideId: UUID, reason: String) {
        guard let context = modelContextProvider?() else {
            scheduleRequestsReload(reason: "\(reason):missingContext", fallback: true)
            return
        }
        let descriptor = FetchDescriptor<SDRide>(predicate: #Predicate { $0.id == rideId })
        if let ride = try? context.fetch(descriptor).first {
            context.delete(ride)
            try? context.save()
        }
        refreshFilteredRequests?()
    }

    private func applyFavorDeletion(favorId: UUID, reason: String) {
        guard let context = modelContextProvider?() else {
            scheduleRequestsReload(reason: "\(reason):missingContext", fallback: true)
            return
        }
        let descriptor = FetchDescriptor<SDFavor>(predicate: #Predicate { $0.id == favorId })
        if let favor = try? context.fetch(descriptor).first {
            context.delete(favor)
            try? context.save()
        }
        refreshFilteredRequests?()
    }

    private func scheduleRequestsReload(reason: String, fallback: Bool = false) {
        requestsReloadTask?.cancel()
        let debounce = fallback
            ? Constants.Timing.requestsRealtimeFallbackReloadDebounceNanoseconds
            : Constants.Timing.requestsRealtimeReloadDebounceNanoseconds
        requestsReloadTask = Task { [weak self] in
            try? await Task.sleep(nanoseconds: debounce)
            guard let self, !Task.isCancelled else { return }
            AppLogger.info("requests", "[RequestRealtimeHandler] Coalesced realtime reload: \(reason)")
            await self.loadRequestsForceRefresh?()
        }
    }

    private func scheduleRequestNotificationRefresh(reason: String, fallback: Bool) {
        requestNotificationRefreshTask?.cancel()
        let debounce = fallback
            ? Constants.Timing.requestsRealtimeFallbackReloadDebounceNanoseconds
            : Constants.Timing.notificationsRealtimeReloadDebounceNanoseconds
        requestNotificationRefreshTask = Task { [weak self] in
            try? await Task.sleep(nanoseconds: debounce)
            guard let self, !Task.isCancelled else { return }
            AppLogger.info("requests", "[RequestRealtimeHandler] Coalesced request notification refresh: \(reason)")
            await self.refreshRequestSummaries?()
            await self.badgeManager.refreshAllBadges(reason: reason)
        }
    }

    private func parseUUID(_ value: Any?) -> UUID? {
        var current = value
        while let anyHashable = current as? AnyHashable {
            current = anyHashable.base
        }
        guard let current else { return nil }
        if let uuid = current as? UUID { return uuid }
        if let nsuuid = current as? NSUUID { return nsuuid as UUID }
        if let string = parseString(current) { return UUID(uuidString: string) }
        return nil
    }

    private func parseString(_ value: Any?) -> String? {
        guard var value else { return nil }
        while let anyHashable = value as? AnyHashable {
            value = anyHashable.base
        }
        if value is NSNull { return nil }
        if let string = value as? String { return string }
        if let substring = value as? Substring { return String(substring) }
        if let nsString = value as? NSString { return nsString as String }
        if let anyJSON = value as? AnyJSON,
           let data = try? JSONEncoder().encode(anyJSON),
           let decoded = try? JSONSerialization.jsonObject(with: data, options: []),
           let stringValue = decoded as? String {
            return stringValue
        }
        return nil
    }
}
