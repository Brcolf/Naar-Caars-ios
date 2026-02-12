//
//  RealtimeManager.swift
//  NaarsCars
//
//  Centralized realtime subscription management
//

import Foundation
import UIKit
import Supabase
import Realtime
import OSLog
internal import Combine

/// Callback types for realtime events
typealias RealtimeInsertCallback = (RealtimeRecord) -> Void
typealias RealtimeUpdateCallback = (RealtimeRecord) -> Void
typealias RealtimeDeleteCallback = (RealtimeRecord) -> Void

/// Canonical representation of a decoded Supabase Realtime event.
struct RealtimeRecord {
    enum EventType {
        case insert
        case update
        case delete
    }

    let table: String
    let eventType: EventType
    let record: [String: Any]
    let oldRecord: [String: Any]?
}

/// Decodes Supabase Realtime action payloads into canonical `RealtimeRecord` values.
enum RealtimePayloadAdapter {
    static func decodeInsert(_ payload: Any, table: String) -> RealtimeRecord? {
        if let action = payload as? InsertAction {
            let record = normalizeRecord(action.record)
            return RealtimeRecord(
                table: table,
                eventType: .insert,
                record: record,
                oldRecord: nil
            )
        }

        if let dict = payload as? [String: Any] {
            let extracted = (dict["record"] as? [String: Any]) ?? dict
            return RealtimeRecord(
                table: table,
                eventType: .insert,
                record: extracted,
                oldRecord: nil
            )
        }

        AppLogger.warning("realtime", "Failed to decode insert payload: \(type(of: payload))")
        return nil
    }

    static func decodeUpdate(_ payload: Any, table: String) -> RealtimeRecord? {
        if let action = payload as? UpdateAction {
            let record = normalizeRecord(action.record)
            let oldRecord = normalizeRecord(action.oldRecord)
            return RealtimeRecord(
                table: table,
                eventType: .update,
                record: record,
                oldRecord: oldRecord
            )
        }

        if let dict = payload as? [String: Any] {
            let extractedRecord = (dict["record"] as? [String: Any]) ?? dict
            let extractedOldRecord = dict["old_record"] as? [String: Any]
            return RealtimeRecord(
                table: table,
                eventType: .update,
                record: extractedRecord,
                oldRecord: extractedOldRecord
            )
        }

        AppLogger.warning("realtime", "Failed to decode update payload: \(type(of: payload))")
        return nil
    }

    static func decodeDelete(_ payload: Any, table: String) -> RealtimeRecord? {
        if let action = payload as? DeleteAction {
            let oldRecord = normalizeRecord(action.oldRecord)
            return RealtimeRecord(
                table: table,
                eventType: .delete,
                record: oldRecord,
                oldRecord: oldRecord
            )
        }

        if let dict = payload as? [String: Any] {
            let extractedOldRecord = (dict["old_record"] as? [String: Any]) ?? dict
            return RealtimeRecord(
                table: table,
                eventType: .delete,
                record: extractedOldRecord,
                oldRecord: extractedOldRecord
            )
        }

        AppLogger.warning("realtime", "Failed to decode delete payload: \(type(of: payload))")
        return nil
    }

    static func normalizeRecord(_ record: [String: AnyJSON]) -> [String: Any] {
        var normalized: [String: Any] = [:]
        normalized.reserveCapacity(record.count)
        for (key, value) in record {
            normalized[key] = normalizeValue(value) ?? NSNull()
        }
        return normalized
    }

    static func normalizeValue(_ value: Any?) -> Any? {
        guard let value else { return nil }
        if value is NSNull { return nil }
        if let anyJSON = value as? AnyJSON {
            return decodeAnyJSON(anyJSON)
        }
        if type(of: value) == AnyHashable.self, let anyHashable = value as? AnyHashable {
            return normalizeValue(anyHashable.base)
        }
        return value
    }

    static func decodeAnyJSON(_ anyJSON: AnyJSON) -> Any? {
        if let mirrorValue = decodeAnyJSONMirror(anyJSON) {
            return mirrorValue
        }
        guard let data = try? JSONEncoder().encode(anyJSON),
              let object = try? JSONSerialization.jsonObject(with: data, options: []) else {
            return nil
        }
        if object is NSNull {
            return nil
        }
        return object
    }

    static func decodeAnyJSONMirror(_ anyJSON: AnyJSON) -> Any? {
        let mirror = Mirror(reflecting: anyJSON)
        if mirror.displayStyle == .enum, let child = mirror.children.first {
            return decodeAnyJSONMirrorValue(label: child.label, value: child.value)
        }
        if mirror.displayStyle == .struct || mirror.displayStyle == .class {
            for child in mirror.children {
                if child.label == "value" || child.label == "rawValue" || child.label == "storage" || child.label == "wrapped" {
                    return decodeAnyJSONMirrorValue(label: child.label, value: child.value)
                }
            }
            if let child = mirror.children.first {
                return decodeAnyJSONMirrorValue(label: child.label, value: child.value)
            }
        }
        return nil
    }

    static func decodeAnyJSONMirrorValue(label: String?, value: Any) -> Any? {
        if value is NSNull { return nil }
        if let nested = value as? AnyJSON { return decodeAnyJSONMirror(nested) }
        if let dict = value as? [String: Any] {
            var result: [String: Any] = [:]
            for (key, val) in dict {
                result[key] = normalizeValue(val) ?? NSNull()
            }
            return result
        }
        if let dict = value as? [String: AnyJSON] {
            var result: [String: Any] = [:]
            for (key, val) in dict {
                result[key] = decodeAnyJSONMirror(val) ?? NSNull()
            }
            return result
        }
        if let array = value as? [Any] {
            return array.map { normalizeValue($0) ?? NSNull() }
        }
        if let array = value as? [AnyJSON] {
            return array.map { decodeAnyJSONMirror($0) ?? NSNull() }
        }
        if label == "null" {
            return nil
        }
        return value
    }
}

/// Channel subscription info
private struct ChannelSubscription {
    let channel: RealtimeChannelV2
    let subscribedAt: Date
    let authTokenLength: Int
    let tasks: [Task<Void, Never>]
}

/// Channel subscription config for resubscribe
private struct SubscriptionConfig {
    let channelName: String
    let table: String
    let filter: String?
    let onInsert: RealtimeInsertCallback?
    let onUpdate: RealtimeUpdateCallback?
    let onDelete: RealtimeDeleteCallback?
}

/// Centralized manager for Supabase realtime subscriptions
/// Limits concurrent subscriptions and handles background/foreground transitions
@MainActor
final class RealtimeManager {
    /// Shared singleton instance
    static let shared = RealtimeManager()
    
    /// Maximum concurrent subscriptions across app features.
    private let maxConcurrentSubscriptions = 30
    
    /// Protected channel prefixes that should not be evicted when possible
    private let protectedChannelPrefixes = [
        "messages:",
        "typing:",
        "rides:sync",
        "favors:sync",
        "notifications:sync",
        "notifications:all",
        "town-hall-",
        "requests-dashboard-"
    ]

    /// Active channel subscriptions
    private var activeChannels: [String: ChannelSubscription] = [:]
    /// Stored channel configs for resubscribing after auth changes
    private var subscriptionConfigs: [String: SubscriptionConfig] = [:]

    /// Realtime connection status (best-effort)
    @Published private(set) var isConnected: Bool = false
    
    /// Background unsubscribe timer
    private var backgroundUnsubscribeTimer: Timer?
    
    private let supabaseClient: SupabaseClient
    
    private init() {
        self.supabaseClient = SupabaseService.shared.client
        
        // Observe app lifecycle events
        setupAppLifecycleObservers()
    }
    
    // MARK: - Public Methods
    
    /// Subscribe to realtime updates for a table
    /// - Parameters:
    ///   - channelName: Unique identifier for this subscription
    ///   - table: Database table name
    ///   - filter: Optional filter string (e.g., "status=eq.open")
    ///   - onInsert: Callback for insert events
    ///   - onUpdate: Callback for update events
    ///   - onDelete: Callback for delete events
    func subscribe(
        channelName: String,
        table: String,
        filter: String? = nil,
        onInsert: RealtimeInsertCallback? = nil,
        onUpdate: RealtimeUpdateCallback? = nil,
        onDelete: RealtimeDeleteCallback? = nil
    ) async {
        subscriptionConfigs[channelName] = SubscriptionConfig(
            channelName: channelName,
            table: table,
            filter: filter,
            onInsert: onInsert,
            onUpdate: onUpdate,
            onDelete: onDelete
        )
        // Read token once to avoid race condition between two reads
        let token = (try? await supabaseClient.auth.session.accessToken) ?? ""
        let tokenLength = token.count
        if !token.isEmpty {
            // Ensure realtime auth is set before subscribing.
            await supabaseClient.realtimeV2.setAuth(token)
            await supabaseClient.realtimeV2.connect()
        }
        if let existing = activeChannels[channelName], existing.channel.status == .subscribed {
            if existing.authTokenLength == 0 && tokenLength > 0 {
                // Channel was created before auth; resubscribe with user token.
                await unsubscribe(channelName: channelName, removeConfig: false)
            } else {
                return
            }
        }
        // If channel already exists, unsubscribe first
        if activeChannels[channelName] != nil {
            await unsubscribe(channelName: channelName, removeConfig: false)
        }
        
        // Check if we need to remove oldest subscription
        if activeChannels.count >= maxConcurrentSubscriptions {
            await removeOldestSubscription()
        }
        
        // Create channel on realtime V2 client (RLS-aware)
        let channelTopic: String
        if channelName.hasPrefix("messages:") {
            channelTopic = "public:\(table)"
        } else {
            channelTopic = channelName
        }
        let channel = supabaseClient.realtimeV2.channel(channelTopic)
        
        let insertStream = onInsert == nil ? nil : await channel.postgresChange(
            InsertAction.self,
            schema: "public",
            table: table,
            filter: filter
        )
        let updateStream = onUpdate == nil ? nil : await channel.postgresChange(
            UpdateAction.self,
            schema: "public",
            table: table,
            filter: filter
        )
        let deleteStream = onDelete == nil ? nil : await channel.postgresChange(
            DeleteAction.self,
            schema: "public",
            table: table,
            filter: filter
        )
        
        // Subscribe to the channel (using subscribeWithError instead of deprecated subscribe)
        do {
            AppLogger.realtime.info("Subscribing to channel: \(channelName) table: \(table) filter: \(filter ?? "(none)")")
            try await channel.subscribeWithError()
            AppLogger.realtime.debug("Channel status after subscribe: \(String(describing: channel.status))")
            Task {
                try? await Task.sleep(nanoseconds: 2_000_000_000)
                AppLogger.realtime.debug("Channel status after 2s: \(String(describing: channel.status))")
            }
        } catch {
            AppLogger.realtime.error("Failed to subscribe to channel \(channelName): \(error)")
            // Don't throw - log the error but continue
            // The caller can check if subscription was successful by checking activeChannels
            return
        }
        
        var tasks: [Task<Void, Never>] = []
        
        if let onInsert, let insertStream {
            tasks.append(Task {
                for await action in insertStream {
                    guard let record = RealtimePayloadAdapter.decodeInsert(action, table: table) else {
                        continue
                    }
                    onInsert(record)
                }
            })
        }
        
        if let onUpdate, let updateStream {
            tasks.append(Task {
                for await action in updateStream {
                    guard let record = RealtimePayloadAdapter.decodeUpdate(action, table: table) else {
                        continue
                    }
                    onUpdate(record)
                }
            })
        }
        
        if let onDelete, let deleteStream {
            tasks.append(Task {
                for await action in deleteStream {
                    guard let record = RealtimePayloadAdapter.decodeDelete(action, table: table) else {
                        continue
                    }
                    onDelete(record)
                }
            })
        }
        
        // Store subscription
        activeChannels[channelName] = ChannelSubscription(
            channel: channel,
            subscribedAt: Date(),
            authTokenLength: tokenLength,
            tasks: tasks
        )
        isConnected = true
        
        AppLogger.realtime.info("Subscribed to channel: \(channelName) (table: \(table))")
    }
    
    /// Unsubscribe from a specific channel
    /// - Parameter channelName: Channel identifier to unsubscribe
    func unsubscribe(channelName: String, removeConfig: Bool = true) async {
        guard let subscription = activeChannels[channelName] else {
            return
        }
        
        subscription.tasks.forEach { $0.cancel() }
        await subscription.channel.unsubscribe()
        await supabaseClient.removeChannel(subscription.channel)
        activeChannels.removeValue(forKey: channelName)
        if removeConfig {
            subscriptionConfigs.removeValue(forKey: channelName)
        }
        if activeChannels.isEmpty {
            isConnected = false
        }
        
        AppLogger.realtime.info("Unsubscribed from channel: \(channelName)")
    }
    
    /// Unsubscribe from all channels
    func unsubscribeAll(removeConfigs: Bool = true) async {
        let channelNames = Array(activeChannels.keys)
        
        for channelName in channelNames {
            await unsubscribe(channelName: channelName, removeConfig: removeConfigs)
        }
        await supabaseClient.removeAllChannels()
        isConnected = false
        
        AppLogger.realtime.info("Unsubscribed from all channels")
    }

    /// Update realtime auth and resubscribe to active channels
    func refreshAuth(accessToken: String) async {
        guard !accessToken.isEmpty else { return }
        let realtime = supabaseClient.realtimeV2
        await realtime.connect()
        await realtime.setAuth(accessToken)
        await resubscribeAll()
    }
    
    // MARK: - Private Methods
    
    /// Remove the oldest subscription to make room for a new one
    private func removeOldestSubscription() async {
        guard !activeChannels.isEmpty else { return }
        
        // Prefer evicting non-protected channels first
        let nonProtected = activeChannels.filter { key, _ in
            !protectedChannelPrefixes.contains { key.hasPrefix($0) }
        }
        
        let candidatePool = nonProtected.isEmpty ? activeChannels : nonProtected
        guard let oldest = candidatePool.min(by: { $0.value.subscribedAt < $1.value.subscribedAt }) else {
            return
        }
        
        AppLogger.realtime.warning("Removing oldest subscription: \(oldest.key) to make room for new subscription")
        await unsubscribe(channelName: oldest.key)
    }

    /// Resubscribe to all tracked channels (used after auth refresh)
    private func resubscribeAll() async {
        let configs = Array(subscriptionConfigs.values)
        for config in configs {
            await subscribe(
                channelName: config.channelName,
                table: config.table,
                filter: config.filter,
                onInsert: config.onInsert,
                onUpdate: config.onUpdate,
                onDelete: config.onDelete
            )
        }
    }

    /// Set up observers for app lifecycle events
    private func setupAppLifecycleObservers() {
        #if os(iOS) || os(tvOS)
        NotificationCenter.default.addObserver(
            forName: UIApplication.didEnterBackgroundNotification,
            object: nil,
            queue: .main
        ) { [weak self] _ in
            Task { @MainActor in
                await self?.handleDidEnterBackground()
            }
        }
        
        NotificationCenter.default.addObserver(
            forName: UIApplication.willEnterForegroundNotification,
            object: nil,
            queue: .main
        ) { [weak self] _ in
            Task { @MainActor in
                await self?.handleWillEnterForeground()
            }
        }

        NotificationCenter.default.addObserver(
            forName: UIApplication.didBecomeActiveNotification,
            object: nil,
            queue: .main
        ) { [weak self] _ in
            // Defer to next run loop so the first frame after foreground isn't blocked (reduces freeze).
            DispatchQueue.main.async {
                Task { @MainActor in
                    await self?.handleDidBecomeActive()
                }
            }
        }
        #endif
    }
    
    /// Handle app entering background - auto-unsubscribe after 30 seconds
    private func handleDidEnterBackground() async {
        AppLogger.realtime.info("App entered background, will auto-unsubscribe in 30 seconds")
        
        // Cancel any existing timer
        backgroundUnsubscribeTimer?.invalidate()
        
        // Set timer to unsubscribe after 30 seconds
        backgroundUnsubscribeTimer = Timer.scheduledTimer(withTimeInterval: 30.0, repeats: false) { [weak self] _ in
            Task { @MainActor in
                // Keep configs so channels can be restored when app returns foreground.
                await self?.unsubscribeAll(removeConfigs: false)
                AppLogger.realtime.info("Auto-unsubscribed all channels after 30 seconds in background")
            }
        }
    }
    
    /// Handle app entering foreground - resubscribe if needed
    private func handleWillEnterForeground() async {
        AppLogger.realtime.info("App entered foreground")
        
        // Cancel background unsubscribe timer
        backgroundUnsubscribeTimer?.invalidate()
        backgroundUnsubscribeTimer = nil
        await restoreTrackedSubscriptionsIfNeeded(reason: "foreground")
    }

    private func handleDidBecomeActive() async {
        await restoreTrackedSubscriptionsIfNeeded(reason: "didBecomeActive")
    }

    private func restoreTrackedSubscriptionsIfNeeded(reason: String) async {
        guard !subscriptionConfigs.isEmpty else { return }

        let hasMissingChannels = activeChannels.count < subscriptionConfigs.count
        let shouldRestore = activeChannels.isEmpty || hasMissingChannels || !isConnected
        guard shouldRestore else { return }

        let accessToken = (try? await supabaseClient.auth.session.accessToken) ?? ""
        let realtime = supabaseClient.realtimeV2
        await realtime.connect()
        if !accessToken.isEmpty {
            await realtime.setAuth(accessToken)
        }

        await resubscribeAll()
        AppLogger.realtime.info(
            "Resubscribed \(self.subscriptionConfigs.count) tracked channel(s) on \(reason)"
        )
    }
    
    deinit {
        backgroundUnsubscribeTimer?.invalidate()
        #if os(iOS) || os(tvOS)
        NotificationCenter.default.removeObserver(self)
        #endif
    }
}
