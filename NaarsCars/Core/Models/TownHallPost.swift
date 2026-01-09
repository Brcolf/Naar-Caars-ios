//
//  TownHallPost.swift
//  NaarsCars
//
//  Town hall post model matching database schema
//

import Foundation

/// Post type enum for town hall posts
enum PostType: String, Codable {
    case userPost = "user_post"
    case review = "review"
    case completion = "completion"
}

/// Town hall post model
struct TownHallPost: Codable, Identifiable, Equatable {
    let id: UUID
    let userId: UUID
    var content: String
    var imageUrl: String?
    let createdAt: Date
    let updatedAt: Date
    
    // Optional fields (may not exist in all database schemas)
    let title: String?
    let pinned: Bool?
    let type: PostType?
    
    // Joined data (not from database)
    var author: Profile?
    
    // MARK: - CodingKeys
    
    enum CodingKeys: String, CodingKey {
        case id
        case userId = "user_id"
        case title
        case content
        case imageUrl = "image_url"
        case pinned
        case type
        case createdAt = "created_at"
        case updatedAt = "updated_at"
    }
    
    // MARK: - Custom Encoding
    
    /// Custom encoder that excludes type field (not in database schema)
    func encode(to encoder: Encoder) throws {
        var container = encoder.container(keyedBy: CodingKeys.self)
        try container.encode(id, forKey: .id)
        try container.encode(userId, forKey: .userId)
        try container.encodeIfPresent(title, forKey: .title)
        try container.encode(content, forKey: .content)
        try container.encodeIfPresent(imageUrl, forKey: .imageUrl)
        try container.encodeIfPresent(pinned, forKey: .pinned)
        // Exclude type - not in database schema
        // try container.encodeIfPresent(type, forKey: .type)
        try container.encode(createdAt, forKey: .createdAt)
        try container.encode(updatedAt, forKey: .updatedAt)
    }
    
    // MARK: - Initializers
    
    init(
        id: UUID = UUID(),
        userId: UUID,
        content: String,
        imageUrl: String? = nil,
        title: String? = nil,
        pinned: Bool? = nil,
        type: PostType? = nil,
        createdAt: Date = Date(),
        updatedAt: Date = Date(),
        author: Profile? = nil
    ) {
        self.id = id
        self.userId = userId
        self.content = content
        self.imageUrl = imageUrl
        self.title = title
        self.pinned = pinned
        self.type = type ?? .userPost
        self.createdAt = createdAt
        self.updatedAt = updatedAt
        self.author = author
    }
}


