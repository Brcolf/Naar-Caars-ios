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

/// Priority levels for realtime subscriptions
enum SubscriptionPriority: Int, Comparable {
    case low = 0        // Background updates, prefetch
    case normal = 1     // Standard updates
    case critical = 2   // Active view updates (messages, live data)
    
    static func < (lhs: SubscriptionPriority, rhs: SubscriptionPriority) -> Bool {
        lhs.rawValue < rhs.rawValue
    }
}

/// Callback types for realtime events
typealias RealtimeInsertCallback = (Any) -> Void
typealias RealtimeUpdateCallback = (Any) -> Void
typealias RealtimeDeleteCallback = (Any) -> Void

/// Channel subscription info
private struct ChannelSubscription {
    let channel: RealtimeChannelV2
    let subscribedAt: Date
    let priority: SubscriptionPriority
}

/// Centralized manager for Supabase realtime subscriptions
/// Limits concurrent subscriptions and handles background/foreground transitions
@MainActor
final class RealtimeManager {
    /// Shared singleton instance
    static let shared = RealtimeManager()
    
    /// Maximum concurrent subscriptions (per FR-049)
    private let maxConcurrentSubscriptions = 3
    
    /// Active channel subscriptions
    private var activeChannels: [String: ChannelSubscription] = [:]
    
    /// Background unsubscribe timer
    private var backgroundUnsubscribeTimer: Timer?
    
    private let supabaseClient: SupabaseClient
    
    /// Store observer tokens for proper cleanup
    private var observerTokens: [NSObjectProtocol] = []
    
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
    ///   - priority: Subscription priority (default: .normal)
    ///   - onInsert: Callback for insert events
    ///   - onUpdate: Callback for update events
    ///   - onDelete: Callback for delete events
    func subscribe(
        channelName: String,
        table: String,
        filter: String? = nil,
        priority: SubscriptionPriority = .normal,
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
            await removeLowestPrioritySubscription()
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
        
        // Store subscription with priority
        activeChannels[channelName] = ChannelSubscription(
            channel: channel,
            subscribedAt: Date(),
            priority: priority
        )
        
        print("🔴 [Realtime] Subscribed to channel: \(channelName) (table: \(table), priority: \(priority))")
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
    
    /// Remove the lowest priority subscription (or oldest if same priority)
    private func removeLowestPrioritySubscription() async {
        guard let lowest = activeChannels.min(by: { lhs, rhs in
            // First compare by priority (lower priority first)
            if lhs.value.priority != rhs.value.priority {
                return lhs.value.priority < rhs.value.priority
            }
            // If same priority, compare by age (older first)
            return lhs.value.subscribedAt < rhs.value.subscribedAt
        }) else {
            return
        }
        
        print("🔴 [Realtime] Removing lowest priority subscription: \(lowest.key) (priority: \(lowest.value.priority))")
        await unsubscribe(channelName: lowest.key)
    }
    
    /// Set up observers for app lifecycle events
    private func setupAppLifecycleObservers() {
        #if os(iOS) || os(tvOS)
        // Store observer tokens for proper cleanup
        let backgroundToken = NotificationCenter.default.addObserver(
            forName: UIApplication.didEnterBackgroundNotification,
            object: nil,
            queue: .main
        ) { [weak self] _ in
            Task { @MainActor [weak self] in
                await self?.handleDidEnterBackground()
            }
        }
        observerTokens.append(backgroundToken)
        
        let foregroundToken = NotificationCenter.default.addObserver(
            forName: UIApplication.willEnterForegroundNotification,
            object: nil,
            queue: .main
        ) { [weak self] _ in
            Task { @MainActor [weak self] in
                await self?.handleWillEnterForeground()
            }
        }
        observerTokens.append(foregroundToken)
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
        // Cancel and invalidate timer
        backgroundUnsubscribeTimer?.invalidate()
        backgroundUnsubscribeTimer = nil
        
        #if os(iOS) || os(tvOS)
        // Remove all observers using stored tokens
        for token in observerTokens {
            NotificationCenter.default.removeObserver(token)
        }
        observerTokens.removeAll()
        #endif
    }
}

