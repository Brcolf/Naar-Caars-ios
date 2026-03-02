//
//  SpotlightEntry.swift
//  NaarsCars
//
//  Spotlight winner model for leaderboard
//

import Foundation

/// A spotlight winner on the leaderboard
struct SpotlightEntry: Codable, Identifiable, Equatable, Sendable {
    let category: String
    let userId: UUID
    let name: String
    let avatarUrl: String?
    let value: Int

    var id: String { category }

    enum CodingKeys: String, CodingKey {
        case category
        case userId = "user_id"
        case name
        case avatarUrl = "avatar_url"
        case value
    }

    var displayCategory: String {
        switch category {
        case "longest_streak": return "spotlight_longest_streak".localized
        case "rising_star": return "spotlight_rising_star".localized
        default: return category
        }
    }

    var iconName: String {
        switch category {
        case "longest_streak": return "flame.fill"
        case "rising_star": return "rocket.fill"
        default: return "star.fill"
        }
    }

    var formattedValue: String {
        switch category {
        case "longest_streak": return "spotlight_streak_value".localized(with: value)
        case "rising_star": return "spotlight_rising_value".localized(with: value)
        default: return "\(value)"
        }
    }
}
