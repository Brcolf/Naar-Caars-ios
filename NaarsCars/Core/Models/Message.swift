//
//  Message.swift
//  NaarsCars
//
//  Message model matching database schema
//

import Foundation

/// Message model
struct Message: Codable, Identifiable, Equatable, Sendable {
    let id: UUID
    let conversationId: UUID
    let fromId: UUID
    let text: String
    let imageUrl: String?
    var readBy: [UUID] // UUID array from PostgreSQL
    let createdAt: Date
    
    // MARK: - Optional Joined Fields (populated when fetched with joins)
    
    /// Profile of the sender
    var sender: Profile?
    
    // MARK: - CodingKeys
    
    enum CodingKeys: String, CodingKey {
        case id
        case conversationId = "conversation_id"
        case fromId = "from_id"
        case text
        case imageUrl = "image_url"
        case readBy = "read_by"
        case createdAt = "created_at"
    }
    
    // MARK: - Initializers
    
    init(
        id: UUID = UUID(),
        conversationId: UUID,
        fromId: UUID,
        text: String,
        imageUrl: String? = nil,
        readBy: [UUID] = [],
        createdAt: Date = Date(),
        sender: Profile? = nil
    ) {
        self.id = id
        self.conversationId = conversationId
        self.fromId = fromId
        self.text = text
        self.imageUrl = imageUrl
        self.readBy = readBy
        self.createdAt = createdAt
        self.sender = sender
    }
}


