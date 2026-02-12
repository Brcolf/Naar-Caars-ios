//
//  Constants.swift
//  NaarsCars
//
//  App-wide constants for animations, spacing, timeouts, etc.
//

import Foundation

/// App-wide constants
enum Constants {
    /// Animation durations (in seconds)
    enum Animation {
        static let short: Double = 0.2
        static let medium: Double = 0.3
        static let long: Double = 0.5
    }
    
    /// Spacing values (in points)
    enum Spacing {
        static let xs: CGFloat = 4
        static let sm: CGFloat = 8
        static let md: CGFloat = 16
        static let lg: CGFloat = 24
        static let xl: CGFloat = 32
    }
    
    /// API and network timeouts (in seconds)
    enum Timeout {
        static let network: TimeInterval = 30
        static let upload: TimeInterval = 60
        static let download: TimeInterval = 60
    }
    
    /// Cache TTL values (in seconds)
    enum CacheTTL {
        static let profiles: TimeInterval = 300        // 5 minutes
        static let rides: TimeInterval = 120            // 2 minutes
        static let favors: TimeInterval = 120           // 2 minutes
        static let notifications: TimeInterval = 60     // 1 minute
        static let conversations: TimeInterval = 60     // 1 minute
        static let messages: TimeInterval = 30          // 30 seconds
        static let townHallPosts: TimeInterval = 120    // 2 minutes
        static let leaderboard: TimeInterval = 900      // 15 minutes
    }
    
    /// Rate limit intervals (in seconds) for user-facing actions
    enum RateLimits {
        static let messageSend: TimeInterval = 1.0
        static let claimRequest: TimeInterval = 10.0
        static let login: TimeInterval = 2.0
        static let passwordReset: TimeInterval = 30.0
        static let townHallPost: TimeInterval = 30.0
        static let townHallComment: TimeInterval = 10.0
        static let authAction: TimeInterval = 3.0
        static let throttleSend: TimeInterval = 1.0
        static let throttleMarkRead: TimeInterval = 0.5
        static let throttleLastSeen: TimeInterval = 5.0
    }
    
    /// Pagination page sizes
    enum PageSizes {
        static let messages: Int = 25
        static let messagesInitialRender: Int = 50
        static let conversations: Int = 10
        static let townHall: Int = 20
        static let searchMessages: Int = 30
        static let searchInConversation: Int = 50
        static let fetchAll: Int = 100
    }
    
    /// Timing constants (in nanoseconds for Task.sleep or seconds for intervals)
    enum Timing {
        /// Debounce interval for realtime/search events (0.3s)
        static let debounceNanoseconds: UInt64 = 300_000_000
        /// Debounce interval for requests realtime-triggered full refreshes (0.35s)
        static let requestsRealtimeReloadDebounceNanoseconds: UInt64 = 350_000_000
        /// Debounce interval for notifications realtime-triggered full refreshes (0.25s)
        static let notificationsRealtimeReloadDebounceNanoseconds: UInt64 = 250_000_000
        /// Debounce interval for malformed/unexpected notifications realtime payload fallback refreshes (1.5s)
        static let notificationsRealtimeFallbackReloadDebounceNanoseconds: UInt64 = 1_500_000_000
        /// Debounce interval for malformed/unexpected request-notification payload fallback refreshes (1.5s)
        static let requestsRealtimeFallbackReloadDebounceNanoseconds: UInt64 = 1_500_000_000
        /// Delay before dismissing success views (1.5s)
        static let successDismissNanoseconds: UInt64 = 1_500_000_000
        /// Toast display duration (4s)
        static let toastDurationNanoseconds: UInt64 = 4_000_000_000
        /// Typing indicator poll interval (3s)
        static let typingPollInterval: TimeInterval = 3.0
        /// Typing signal threshold (2s)
        static let typingSignalThreshold: TimeInterval = 2.0
        /// Auto-clear typing indicator when no new typing signal is sent (5s)
        static let typingAutoClearNanoseconds: UInt64 = 5_000_000_000
        /// Badge polling when connected (30s)
        static let badgePollConnected: TimeInterval = 30.0
        /// Badge polling when disconnected (90s)
        static let badgePollDisconnected: TimeInterval = 90.0
        /// Minimum interval between badge refresh executions
        static let badgeRefreshMinInterval: TimeInterval = 2.0
        /// Debounce interval before forcing a network badge refresh after local message read clear.
        static let badgeClearMessagesRefreshDebounceNanoseconds: UInt64 = 1_200_000_000
        /// Coalesce regular notification fetches within this window.
        static let notificationsFetchCoalesceWindow: TimeInterval = 2.0
        /// Coalesce forced notification fetches within this smaller window.
        static let notificationsForceRefreshCoalesceWindow: TimeInterval = 0.75
        /// Minimum interval between repeated initial sync-engine starts.
        static let syncEngineStartCooldown: TimeInterval = 5.0
        /// Minimum interval for automatic remote sync in conversations list.
        static let messagingListRemoteSyncMinInterval: TimeInterval = 2.0
        /// Audio playback progress timer interval (0.2s)
        static let audioPlaybackProgressInterval: TimeInterval = 0.2
    }

    /// Performance thresholds and retention policies
    enum Performance {
        /// Slow launch warning threshold
        static let launchCriticalPathSlowThreshold: TimeInterval = 2.5
        /// Slow conversation-open warning threshold
        static let conversationOpenSlowThreshold: TimeInterval = 1.2
        /// Slow server-accept warning threshold for message send
        static let messageSendServerAcceptSlowThreshold: TimeInterval = 0.5
        /// Slow claim operation warning threshold
        static let claimOperationSlowThreshold: TimeInterval = 1.0
        /// Offline cache retention window in days
        static let offlineCacheRetentionDays: Int = 14
    }

    /// Storage limits and cache budgets
    enum Storage {
        /// Max on-disk cache budget for downloaded audio playback files
        static let audioPlaybackCacheMaxBytes: Int64 = 100 * 1_024 * 1_024
        /// Trim target when audio cache exceeds budget
        static let audioPlaybackCacheTrimTargetBytes: Int64 = 80 * 1_024 * 1_024
    }
    
    /// External URLs
    enum URLs {
        static let googleMapsSearch = "https://www.google.com/maps/search/"
        static let googleMapsDirections = "https://www.google.com/maps/dir/"
        static let termsOfService = "https://stitch-hydrangea-9b8.notion.site/Naars-Cars-Terms-of-Service-2ee7d642e90c8005ae63d8731e3d50f5"
        static let privacyPolicy = "https://stitch-hydrangea-9b8.notion.site/Naars-Cars-Privacy-Policy-2ee7d642e90c8021b971f71c9cd957fc"
        static let appStore = "https://apps.apple.com/app/naars-cars/id0000000000"
        static let deepLinkBase = "https://naarscars.com"
    }
    
    /// Default map coordinates
    enum Map {
        static let defaultLatitude: Double = 47.6062    // Seattle
        static let defaultLongitude: Double = -122.3321
    }
}

/// Runtime feature flags for performance instrumentation.
/// Debug builds can toggle these in Settings; release builds keep instrumentation enabled.
enum FeatureFlags {
    private enum Keys {
        static let performanceInstrumentationEnabled = "debug.performance.instrumentation.enabled"
        static let metricKitEnabled = "debug.performance.metrickit.enabled"
        static let verbosePerformanceLogsEnabled = "debug.performance.verboseLogs.enabled"
    }

    static var performanceInstrumentationEnabled: Bool {
#if DEBUG
        UserDefaults.standard.object(forKey: Keys.performanceInstrumentationEnabled) as? Bool ?? true
#else
        true
#endif
    }

    static var metricKitEnabled: Bool {
#if DEBUG
        UserDefaults.standard.object(forKey: Keys.metricKitEnabled) as? Bool ?? true
#else
        true
#endif
    }

    static var verbosePerformanceLogsEnabled: Bool {
#if DEBUG
        UserDefaults.standard.object(forKey: Keys.verbosePerformanceLogsEnabled) as? Bool ?? false
#else
        false
#endif
    }

    /// When true, falls back to client-side badge computation on RPC failure.
    /// Set to false after confirming RPC reliability (target: 2026-03-01).
    static let badgeCountClientFallbackEnabled = false

#if DEBUG
    static func setPerformanceInstrumentationEnabled(_ enabled: Bool) {
        UserDefaults.standard.set(enabled, forKey: Keys.performanceInstrumentationEnabled)
    }

    static func setMetricKitEnabled(_ enabled: Bool) {
        UserDefaults.standard.set(enabled, forKey: Keys.metricKitEnabled)
    }

    static func setVerbosePerformanceLogsEnabled(_ enabled: Bool) {
        UserDefaults.standard.set(enabled, forKey: Keys.verbosePerformanceLogsEnabled)
    }
#endif
}