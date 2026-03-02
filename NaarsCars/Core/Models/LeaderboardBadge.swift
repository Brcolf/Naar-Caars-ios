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
    case risingStar = "rising_star"
    case bigSaver = "big_saver"

    var displayName: String {
        switch self {
        case .roadWarrior: return "Road Warrior"
        case .goodNeighbor: return "Good Neighbor"
        case .streakChampion: return "Streak Champ"
        case .fiveStar: return "Five Star"
        case .risingStar: return "Rising Star"
        case .bigSaver: return "Big Saver"
        }
    }

    var iconName: String {
        switch self {
        case .roadWarrior: return "car.fill"
        case .goodNeighbor: return "person.2.fill"
        case .streakChampion: return "flame.fill"
        case .fiveStar: return "star.fill"
        case .risingStar: return "rocket.fill"
        case .bigSaver: return "dollarsign.circle.fill"
        }
    }
}
