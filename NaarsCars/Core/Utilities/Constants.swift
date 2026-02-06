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
    }
    
    /// Pagination page sizes
    enum PageSizes {
        static let messages: Int = 25
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
        /// Delay before dismissing success views (1.5s)
        static let successDismissNanoseconds: UInt64 = 1_500_000_000
        /// Toast display duration (4s)
        static let toastDurationNanoseconds: UInt64 = 4_000_000_000
        /// Typing indicator poll interval (3s)
        static let typingPollInterval: TimeInterval = 3.0
        /// Typing signal threshold (2s)
        static let typingSignalThreshold: TimeInterval = 2.0
        /// Badge polling when connected (10s)
        static let badgePollConnected: TimeInterval = 10.0
        /// Badge polling when disconnected (90s)
        static let badgePollDisconnected: TimeInterval = 90.0
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

