//
//  BadgeCache.swift
//  NaarsCars
//
//  In-memory cache for user badge data
//

import Foundation
import Observation

/// In-memory cache for user badge data, populated by existing fetches
@Observable
@MainActor
final class BadgeCache {
    static let shared = BadgeCache()

    private var cache: [UUID: (badges: [LeaderboardBadge], cachedAt: Date)] = [:]
    private let ttl: TimeInterval = 3600 // 1 hour

    private init() {}

    /// Get cached badges for a user. Returns empty array on miss or expiry.
    func badges(for userId: UUID) -> [LeaderboardBadge] {
        guard let entry = cache[userId],
              Date().timeIntervalSince(entry.cachedAt) < ttl else {
            return []
        }
        return entry.badges
    }

    /// Store badges for a single user
    func store(badges: [LeaderboardBadge], for userId: UUID) {
        cache[userId] = (badges, Date())
    }

    /// Bulk populate from leaderboard entries
    func storeBatch(entries: [LeaderboardEntry]) {
        let now = Date()
        for entry in entries {
            cache[entry.userId] = (entry.badges, now)
        }
    }
}
