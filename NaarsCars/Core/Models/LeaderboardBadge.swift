//
//  LeaderboardBadge.swift
//  NaarsCars
//
//  Badge types earned on the leaderboard
//

import Foundation

/// Badge types earned on the leaderboard
enum LeaderboardBadge: String, Codable, CaseIterable, Equatable, Sendable {
    case roadWarrior = "road_warrior"
    case goodNeighbor = "good_neighbor"
    case streakChampion = "streak_champion"
    case fiveStar = "five_star"
    case bigSaver = "big_saver"
    case frequentCarbardian = "frequent_carbardian"

    var displayName: String {
        switch self {
        case .roadWarrior: return "badge_road_warrior_name".localized
        case .goodNeighbor: return "badge_good_neighbor_name".localized
        case .streakChampion: return "badge_streak_champ_name".localized
        case .fiveStar: return "badge_five_star_name".localized
        case .bigSaver: return "badge_big_saver_name".localized
        case .frequentCarbardian: return "badge_frequent_carbardian_name".localized
        }
    }

    var iconName: String {
        switch self {
        case .roadWarrior: return "car.fill"
        case .goodNeighbor: return "person.2.fill"
        case .streakChampion: return "flame.fill"
        case .fiveStar: return "star.fill"
        case .bigSaver: return "dollarsign.circle.fill"
        case .frequentCarbardian: return "car.2.fill"
        }
    }

    var emoji: String {
        switch self {
        case .roadWarrior: return "🚗"
        case .goodNeighbor: return "🤝"
        case .streakChampion: return "🔥"
        case .fiveStar: return "⭐"
        case .bigSaver: return "💰"
        case .frequentCarbardian: return "🚙"
        }
    }

    var badgeDescription: String {
        switch self {
        case .roadWarrior: return "badge_road_warrior_desc".localized
        case .goodNeighbor: return "badge_good_neighbor_desc".localized
        case .streakChampion: return "badge_streak_champ_desc".localized
        case .fiveStar: return "badge_five_star_desc".localized
        case .bigSaver: return "badge_big_saver_desc".localized
        case .frequentCarbardian: return "badge_frequent_carbardian_desc".localized
        }
    }
}
