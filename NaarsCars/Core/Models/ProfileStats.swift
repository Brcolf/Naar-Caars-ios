//
//  ProfileStats.swift
//  NaarsCars
//

import Foundation

/// Reputation numbers from the `get_profile_stats` RPC. The RPC answers `{}` when the viewer
/// may not see the person, which decodes as "nothing visible" (nil rating, zero counts).
struct ProfileStats: Decodable, Equatable, Sendable {
    let averageRating: Double?
    let reviewCount: Int
    let fulfilledCount: Int

    init(averageRating: Double?, reviewCount: Int, fulfilledCount: Int) {
        self.averageRating = averageRating
        self.reviewCount = reviewCount
        self.fulfilledCount = fulfilledCount
    }

    private enum CodingKeys: String, CodingKey {
        case averageRating = "avg_rating"
        case reviewCount = "review_count"
        case fulfilledCount = "fulfilled_count"
    }

    init(from decoder: Decoder) throws {
        let container = try decoder.container(keyedBy: CodingKeys.self)
        averageRating = try container.decodeIfPresent(Double.self, forKey: .averageRating)
        reviewCount = try container.decodeIfPresent(Int.self, forKey: .reviewCount) ?? 0
        fulfilledCount = try container.decodeIfPresent(Int.self, forKey: .fulfilledCount) ?? 0
    }
}
