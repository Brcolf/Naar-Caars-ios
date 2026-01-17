//
//  Review.swift
//  NaarsCars
//
//  Review model matching database schema
//

import Foundation

/// Review model
struct Review: Codable, Identifiable, Equatable {
    let id: UUID
    let reviewerId: UUID
    let fulfillerId: UUID
    let rideId: UUID?
    let favorId: UUID?
    let rating: Int // 1-5
    let comment: String?
    let imageUrl: String?
    let createdAt: Date
    
    // MARK: - CodingKeys
    
    enum CodingKeys: String, CodingKey {
        case id
        case reviewerId = "reviewer_id"
        case fulfillerId = "fulfiller_id"
        case rideId = "ride_id"
        case favorId = "favor_id"
        case rating
        case comment
        case imageUrl = "image_url"
        case createdAt = "created_at"
    }
    
    // MARK: - Validation
    
    var isValid: Bool {
        return rating >= 1 && rating <= 5
    }
    
    // MARK: - Initializers
    
    init(
        id: UUID = UUID(),
        reviewerId: UUID,
        fulfillerId: UUID,
        rideId: UUID? = nil,
        favorId: UUID? = nil,
        rating: Int,
        comment: String? = nil,
        imageUrl: String? = nil,
        createdAt: Date = Date()
    ) {
        self.id = id
        self.reviewerId = reviewerId
        self.fulfillerId = fulfillerId
        self.rideId = rideId
        self.favorId = favorId
        self.rating = rating
        self.comment = comment
        self.imageUrl = imageUrl
        self.createdAt = createdAt
    }
}


