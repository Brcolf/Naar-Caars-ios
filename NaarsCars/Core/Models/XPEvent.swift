//
//  XPEvent.swift
//  NaarsCars
//
//  Model for XP earning events displayed in XP history
//

import Foundation

/// Represents a single XP earning event
struct XPEvent: Codable, Identifiable {
    let id: UUID
    let amount: Int
    let sourceType: String
    let sourceId: UUID
    let description: String?
    let createdAt: Date

    enum CodingKeys: String, CodingKey {
        case id
        case amount
        case sourceType = "source_type"
        case sourceId = "source_id"
        case description
        case createdAt = "created_at"
    }
}
