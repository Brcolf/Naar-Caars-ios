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

    var displayName: String {
        switch self {
        case .roadWarrior: return "Road Warrior"
        case .goodNeighbor: return "Good Neighbor"
        case .streakChampion: return "Streak Champ"
        case .fiveStar: return "Five Star"
        case .bigSaver: return "Big Saver"
        }
    }

    var iconName: String {
        switch self {
        case .roadWarrior: return "car.fill"
        case .goodNeighbor: return "person.2.fill"
        case .streakChampion: return "flame.fill"
        case .fiveStar: return "star.fill"
        case .bigSaver: return "dollarsign.circle.fill"
        }
    }

    var emoji: String {
        switch self {
        case .roadWarrior: return "🚗"
        case .goodNeighbor: return "🤝"
        case .streakChampion: return "🔥"
        case .fiveStar: return "⭐"
        case .bigSaver: return "💰"
        }
    }

    var badgeDescription: String {
        switch self {
        case .roadWarrior: return "badge_road_warrior_desc".localized
        case .goodNeighbor: return "badge_good_neighbor_desc".localized
        case .streakChampion: return "badge_streak_champ_desc".localized
        case .fiveStar: return "badge_five_star_desc".localized
        case .bigSaver: return "badge_big_saver_desc".localized
        }
    }
}
