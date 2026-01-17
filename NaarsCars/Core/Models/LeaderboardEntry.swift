//
//  LeaderboardEntry.swift
//  NaarsCars
//
//  Leaderboard entry model matching database schema
//

import Foundation

/// Leaderboard entry model
struct LeaderboardEntry: Codable, Identifiable, Equatable {
    let userId: UUID
    let name: String
    let avatarUrl: String?
    let requestsFulfilled: Int
    let requestsMade: Int
    var rank: Int?
    
    var id: UUID { userId }
    
    // MARK: - CodingKeys
    
    enum CodingKeys: String, CodingKey {
        case userId = "user_id"
        case name
        case avatarUrl = "avatar_url"
        case requestsFulfilled = "requests_fulfilled"
        case requestsMade = "requests_made"
    }
    
    // MARK: - Computed Properties
    
    /// Whether this entry is the current user
    var isCurrentUser: Bool {
        guard let currentUserId = AuthService.shared.currentUserId else {
            return false
        }
        return userId == currentUserId
    }
    
    // MARK: - Initializers
    
    init(
        userId: UUID,
        name: String,
        avatarUrl: String? = nil,
        requestsFulfilled: Int,
        requestsMade: Int,
        rank: Int? = nil
    ) {
        self.userId = userId
        self.name = name
        self.avatarUrl = avatarUrl
        self.requestsFulfilled = requestsFulfilled
        self.requestsMade = requestsMade
        self.rank = rank
    }
}



