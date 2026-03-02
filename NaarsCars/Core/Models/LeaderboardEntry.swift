//
//  LeaderboardEntry.swift
//  NaarsCars
//
//  Leaderboard entry model matching database schema
//

import Foundation

/// Leaderboard entry model
struct LeaderboardEntry: Codable, Identifiable, Equatable, Sendable {
    let userId: UUID
    let name: String
    let avatarUrl: String?
    let xp: Int
    let badges: [LeaderboardBadge]
    let streakWeeks: Int
    let requestsFulfilled: Int
    let requestsMade: Int
    var rank: Int?
    
    var id: UUID { userId }
    
    // MARK: - CodingKeys
    
    enum CodingKeys: String, CodingKey {
        case userId = "user_id"
        case name
        case avatarUrl = "avatar_url"
        case xp
        case badges
        case streakWeeks = "streak_weeks"
        case requestsFulfilled = "requests_fulfilled"
        case requestsMade = "requests_made"
    }
    
    // MARK: - Computed Properties
    
    /// Top 2 badges for display on leaderboard row
    var topBadges: [LeaderboardBadge] {
        Array(badges.prefix(2))
    }

    /// Whether this entry is the current user
    var isCurrentUser: Bool {
        guard let currentUserId = AuthService.shared.currentUserId else {
            return false
        }
        return userId == currentUserId
    }
    
    // MARK: - Decodable

    /// Custom decoder that gracefully skips unknown badge strings
    /// for forward-compatibility with server-side badge additions
    init(from decoder: Decoder) throws {
        let container = try decoder.container(keyedBy: CodingKeys.self)
        userId = try container.decode(UUID.self, forKey: .userId)
        name = try container.decode(String.self, forKey: .name)
        avatarUrl = try container.decodeIfPresent(String.self, forKey: .avatarUrl)
        xp = try container.decode(Int.self, forKey: .xp)
        let rawBadges = try container.decode([String].self, forKey: .badges)
        badges = rawBadges.compactMap { LeaderboardBadge(rawValue: $0) }
        streakWeeks = try container.decode(Int.self, forKey: .streakWeeks)
        requestsFulfilled = try container.decode(Int.self, forKey: .requestsFulfilled)
        requestsMade = try container.decode(Int.self, forKey: .requestsMade)
    }

    // MARK: - Initializers

    init(
        userId: UUID,
        name: String,
        avatarUrl: String? = nil,
        xp: Int = 0,
        badges: [LeaderboardBadge] = [],
        streakWeeks: Int = 0,
        requestsFulfilled: Int,
        requestsMade: Int,
        rank: Int? = nil
    ) {
        self.userId = userId
        self.name = name
        self.avatarUrl = avatarUrl
        self.xp = xp
        self.badges = badges
        self.streakWeeks = streakWeeks
        self.requestsFulfilled = requestsFulfilled
        self.requestsMade = requestsMade
        self.rank = rank
    }
}



