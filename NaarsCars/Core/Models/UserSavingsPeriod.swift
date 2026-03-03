//
//  UserSavingsPeriod.swift
//  NaarsCars
//
//  Model for user savings breakdown by period
//

import Foundation

/// Represents savings for a single period (month/year/all-time)
struct UserSavingsPeriod: Codable, Identifiable {
    let periodLabel: String
    let totalSavings: Double
    let rideCount: Int

    var id: String { periodLabel }

    enum CodingKeys: String, CodingKey {
        case periodLabel = "period_label"
        case totalSavings = "total_savings"
        case rideCount = "ride_count"
    }
}
