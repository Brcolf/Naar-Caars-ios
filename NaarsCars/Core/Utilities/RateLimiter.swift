//
//  RateLimiter.swift
//  NaarsCars
//
//  Rate limiting utility to prevent rapid duplicate actions
//

import Foundation

/// Actor-based rate limiter to prevent rapid duplicate actions
/// Thread-safe implementation using Swift actors
/// 
/// Rate limit intervals per FR-045:
/// - Claim/unclaim: 5 seconds
/// - Send message: 1 second
/// - Generate invite: 10 seconds
/// - Pull-to-refresh: 2 seconds
/// - Login attempt: 2 seconds
/// - Password reset: 30 seconds
actor RateLimiter {
    /// Shared singleton instance
    static let shared = RateLimiter()
    
    /// Track last action time for each action type
    private var lastActionTime: [String: Date] = [:]
    
    private init() {}
    
    /// Check if action is allowed and record the action time
    /// - Parameters:
    ///   - action: Unique identifier for the action (e.g., "claim_ride_\(rideId)")
    ///   - minimumInterval: Minimum time interval in seconds between actions
    /// - Returns: `true` if action is allowed, `false` if rate limited
    func checkAndRecord(action: String, minimumInterval: TimeInterval) -> Bool {
        let now = Date()
        
        if let lastTime = lastActionTime[action],
           now.timeIntervalSince(lastTime) < minimumInterval {
            return false
        }
        
        lastActionTime[action] = now
        return true
    }
    
    /// Reset rate limit for a specific action
    /// - Parameter action: Action identifier to reset
    func reset(action: String) {
        lastActionTime.removeValue(forKey: action)
    }
    
    /// Reset all rate limits (useful for testing or logout)
    func resetAll() {
        lastActionTime.removeAll()
    }
}

