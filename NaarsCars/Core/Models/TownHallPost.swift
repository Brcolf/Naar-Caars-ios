//
//  TownHallPost.swift
//  NaarsCars
//
//  Town hall post model matching database schema
//

import Foundation

/// Town hall post model
struct TownHallPost: Codable, Identifiable, Equatable {
    let id: UUID
    let userId: UUID
    let title: String
    let content: String
    let imageUrl: String?
    let pinned: Bool
    let createdAt: Date
    let updatedAt: Date
    
    // MARK: - CodingKeys
    
    enum CodingKeys: String, CodingKey {
        case id
        case userId = "user_id"
        case title
        case content
        case imageUrl = "image_url"
        case pinned
        case createdAt = "created_at"
        case updatedAt = "updated_at"
    }
    
    // MARK: - Initializers
    
    init(
        id: UUID = UUID(),
        userId: UUID,
        title: String,
        content: String,
        imageUrl: String? = nil,
        pinned: Bool = false,
        createdAt: Date = Date(),
        updatedAt: Date = Date()
    ) {
        self.id = id
        self.userId = userId
        self.title = title
        self.content = content
        self.imageUrl = imageUrl
        self.pinned = pinned
        self.createdAt = createdAt
        self.updatedAt = updatedAt
    }
}


