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
        static let profiles: TimeInterval = 300      // 5 minutes
        static let rides: TimeInterval = 120          // 2 minutes
        static let favors: TimeInterval = 120         // 2 minutes
        static let conversations: TimeInterval = 60   // 1 minute
        static let leaderboard: TimeInterval = 900    // 15 minutes
    }
}

