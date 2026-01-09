//
//  RequestQA.swift
//  NaarsCars
//
//  Q&A model for ride and favor requests
//

import Foundation

/// Q&A question/answer for ride or favor requests
struct RequestQA: Codable, Identifiable, Equatable, Sendable {
    let id: UUID
    let rideId: UUID?
    let favorId: UUID?
    let userId: UUID
    let question: String
    let answer: String?
    let createdAt: Date
    
    // MARK: - Optional Joined Fields
    
    /// Profile of the user who asked the question
    var asker: Profile?
    
    // MARK: - Computed Properties
    
    /// The request ID (either rideId or favorId)
    var requestId: UUID? {
        rideId ?? favorId
    }
    
    /// The request type ("ride" or "favor")
    var requestType: String? {
        if rideId != nil {
            return "ride"
        } else if favorId != nil {
            return "favor"
        }
        return nil
    }
    
    // MARK: - CodingKeys
    
    enum CodingKeys: String, CodingKey {
        case id
        case rideId = "ride_id"
        case favorId = "favor_id"
        case userId = "user_id"
        case question
        case answer
        case createdAt = "created_at"
    }
    
    // MARK: - Initializers
    
    init(
        id: UUID = UUID(),
        rideId: UUID? = nil,
        favorId: UUID? = nil,
        userId: UUID,
        question: String,
        answer: String? = nil,
        createdAt: Date = Date(),
        asker: Profile? = nil
    ) {
        self.id = id
        self.rideId = rideId
        self.favorId = favorId
        self.userId = userId
        self.question = question
        self.answer = answer
        self.createdAt = createdAt
        self.asker = asker
    }
}



