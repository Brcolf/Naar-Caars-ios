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
        // If channel already exists, unsubscribe first
        if activeChannels[channelName] != nil {
            await unsubscribe(channelName: channelName)
        }
        
        // Check if we need to remove oldest subscription
        if activeChannels.count >= maxConcurrentSubscriptions {
            await removeOldestSubscription()
        }
        
        // Create channel
        let channel = supabaseClient.channel(channelName)
        
        // Set up postgres changes for INSERT events
        _ = channel.onPostgresChange(
            InsertAction.self,
            schema: "public",
            table: table,
            filter: filter
        ) { action in
            onInsert?(action)
        }
        
        // Add UPDATE events if callback provided
        if let onUpdate = onUpdate {
            _ = channel.onPostgresChange(
                UpdateAction.self,
                schema: "public",
                table: table,
                filter: filter
            ) { action in
                onUpdate(action)
            }
        }
        
        // Add DELETE events if callback provided
        if let onDelete = onDelete {
            _ = channel.onPostgresChange(
                DeleteAction.self,
                schema: "public",
                table: table,
                filter: filter
            ) { action in
                onDelete(action)
            }
        }
        
        // Subscribe to the channel (using subscribeWithError instead of deprecated subscribe)
        do {
            try await channel.subscribeWithError()
        } catch {
            print("🔴 [Realtime] Failed to subscribe to channel \(channelName): \(error)")
            // Don't throw - log the error but continue
            // The caller can check if subscription was successful by checking activeChannels
            return
        }
        
        // Store subscription
        activeChannels[channelName] = ChannelSubscription(
            channel: channel,
            subscribedAt: Date()
        )
        
        print("🔴 [Realtime] Subscribed to channel: \(channelName) (table: \(table))")
    }
    
    /// Unsubscribe from a specific channel
    /// - Parameter channelName: Channel identifier to unsubscribe
    func unsubscribe(channelName: String) async {
        guard let subscription = activeChannels[channelName] else {
            return
        }
        
        await subscription.channel.unsubscribe()
        activeChannels.removeValue(forKey: channelName)
        
        print("🔴 [Realtime] Unsubscribed from channel: \(channelName)")
    }
    
    /// Unsubscribe from all channels
    func unsubscribeAll() async {
        let channelNames = Array(activeChannels.keys)
        
        for channelName in channelNames {
            await unsubscribe(channelName: channelName)
        }
        
        print("🔴 [Realtime] Unsubscribed from all channels")
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

