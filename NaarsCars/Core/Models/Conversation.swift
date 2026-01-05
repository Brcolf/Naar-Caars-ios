//
//  Conversation.swift
//  NaarsCars
//
//  Conversation model matching database schema
//

import Foundation

/// Conversation model
struct Conversation: Codable, Identifiable, Equatable {
    let id: UUID
    let rideId: UUID?
    let favorId: UUID?
    let createdBy: UUID
    let createdAt: Date
    let updatedAt: Date
    
    // MARK: - CodingKeys
    
    enum CodingKeys: String, CodingKey {
        case id
        case rideId = "ride_id"
        case favorId = "favor_id"
        case createdBy = "created_by"
        case createdAt = "created_at"
        case updatedAt = "updated_at"
    }
    
    // MARK: - Initializers
    
    init(
        id: UUID = UUID(),
        rideId: UUID? = nil,
        favorId: UUID? = nil,
        createdBy: UUID,
        createdAt: Date = Date(),
        updatedAt: Date = Date()
    ) {
        self.id = id
        self.rideId = rideId
        self.favorId = favorId
        self.createdBy = createdBy
        self.createdAt = createdAt
        self.updatedAt = updatedAt
    }
}


