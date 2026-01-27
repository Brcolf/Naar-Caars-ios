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
internal import Combine

/// Callback types for realtime events
typealias RealtimeInsertCallback = (Any) -> Void
typealias RealtimeUpdateCallback = (Any) -> Void
typealias RealtimeDeleteCallback = (Any) -> Void

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
    
    /// Maximum concurrent subscriptions (per FR-049)
    private let maxConcurrentSubscriptions = 10
    
    /// Protected channel prefixes that should not be evicted when possible
    private let protectedChannelPrefixes = ["messages:", "typing:"]

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
        let tokenLength = (try? await supabaseClient.auth.session.accessToken.count) ?? 0
        if tokenLength > 0 {
            // Ensure realtime auth is set before subscribing.
            let token = (try? await supabaseClient.auth.session.accessToken) ?? ""
            if !token.isEmpty {
                await supabaseClient.realtimeV2.setAuth(token)
                await supabaseClient.realtimeV2.connect()
            }
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
            print("🔴 [Realtime] Subscribing to channel: \(channelName) table: \(table) filter: \(filter ?? "(none)")")
            try await channel.subscribeWithError()
            print("🔴 [Realtime] Channel status after subscribe: \(channel.status)")
            Task {
                try? await Task.sleep(nanoseconds: 2_000_000_000)
                print("🔴 [Realtime] Channel status after 2s: \(channel.status)")
            }
        } catch {
            print("🔴 [Realtime] Failed to subscribe to channel \(channelName): \(error)")
            // Don't throw - log the error but continue
            // The caller can check if subscription was successful by checking activeChannels
            return
        }
        
        var tasks: [Task<Void, Never>] = []
        
        if let onInsert, let insertStream {
            tasks.append(Task {
                for await action in insertStream {
                    onInsert(action)
                }
            })
        }
        
        if let onUpdate, let updateStream {
            tasks.append(Task {
                for await action in updateStream {
                    onUpdate(action)
                }
            })
        }
        
        if let onDelete, let deleteStream {
            tasks.append(Task {
                for await action in deleteStream {
                    onDelete(action)
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
        
        print("🔴 [Realtime] Subscribed to channel: \(channelName) (table: \(table))")
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
        
        print("🔴 [Realtime] Unsubscribed from channel: \(channelName)")
    }
    
    /// Unsubscribe from all channels
    func unsubscribeAll() async {
        let channelNames = Array(activeChannels.keys)
        
        for channelName in channelNames {
            await unsubscribe(channelName: channelName)
        }
        await supabaseClient.removeAllChannels()
        isConnected = false
        
        print("🔴 [Realtime] Unsubscribed from all channels")
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
        
        print("🔴 [Realtime] Removing oldest subscription: \(oldest.key) to make room for new subscription")
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
        #endif
    }
    
    /// Handle app entering background - auto-unsubscribe after 30 seconds
    private func handleDidEnterBackground() async {
        print("🔴 [Realtime] App entered background, will auto-unsubscribe in 30 seconds")
        
        // Cancel any existing timer
        backgroundUnsubscribeTimer?.invalidate()
        
        // Set timer to unsubscribe after 30 seconds
        backgroundUnsubscribeTimer = Timer.scheduledTimer(withTimeInterval: 30.0, repeats: false) { [weak self] _ in
            Task { @MainActor in
                await self?.unsubscribeAll()
                print("🔴 [Realtime] Auto-unsubscribed all channels after 30 seconds in background")
            }
        }
    }
    
    /// Handle app entering foreground - resubscribe if needed
    private func handleWillEnterForeground() async {
        print("🔴 [Realtime] App entered foreground")
        
        // Cancel background unsubscribe timer
        backgroundUnsubscribeTimer?.invalidate()
        backgroundUnsubscribeTimer = nil
        
        // Note: Actual resubscription should be handled by the view models
        // that need the subscriptions. This manager just cleans up.
    }
    
    deinit {
        backgroundUnsubscribeTimer?.invalidate()
        #if os(iOS) || os(tvOS)
        NotificationCenter.default.removeObserver(self)
        #endif
    }
}

