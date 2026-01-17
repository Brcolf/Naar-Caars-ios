//
//  Ride.swift
//  NaarsCars
//
//  Ride request model matching database schema
//

import Foundation
import SwiftUI

/// Ride status enum matching database enum
enum RideStatus: String, Codable {
    case open = "open"
    case pending = "pending"
    case confirmed = "confirmed"
    case completed = "completed"
    
    /// Human-readable display text
    var displayText: String {
        switch self {
        case .open: return "Open"
        case .pending: return "Pending"
        case .confirmed: return "Claimed"
        case .completed: return "Completed"
        }
    }
    
    /// Color for status badge
    var color: Color {
        switch self {
        case .open: return .naarsSuccess
        case .pending: return .naarsWarning
        case .confirmed: return .naarsPrimary
        case .completed: return .gray
        }
    }
}

/// Ride request model
struct Ride: Codable, Identifiable, Equatable, Sendable {
    let id: UUID
    let userId: UUID
    let type: String
    let date: Date
    let time: String // TIME type in PostgreSQL
    let pickup: String
    let destination: String
    let seats: Int
    let notes: String?
    let gift: String?
    let status: RideStatus
    let claimedBy: UUID?
    let reviewed: Bool
    let reviewSkipped: Bool?
    let reviewSkippedAt: Date?
    let estimatedCost: Double?
    let createdAt: Date
    let updatedAt: Date
    
    // MARK: - Optional Joined Fields (populated when fetched with joins)
    
    /// Profile of the user who posted the ride
    var poster: Profile?
    
    /// Profile of the user who claimed the ride
    var claimer: Profile?
    
    /// List of participants (co-requestors)
    var participants: [Profile]?
    
    /// Count of Q&A questions/answers
    var qaCount: Int?
    
    // MARK: - CodingKeys
    
    enum CodingKeys: String, CodingKey {
        case id
        case userId = "user_id"
        case type
        case date
        case time
        case pickup
        case destination
        case seats
        case notes
        case gift
        case status
        case claimedBy = "claimed_by"
        case reviewed
        case reviewSkipped = "review_skipped"
        case reviewSkippedAt = "review_skipped_at"
        case estimatedCost = "estimated_cost"
        case createdAt = "created_at"
        case updatedAt = "updated_at"
        // Joined fields are not in CodingKeys - they're populated separately
    }
    
    // MARK: - Initializers
    
    init(
        id: UUID = UUID(),
        userId: UUID,
        type: String = "request",
        date: Date,
        time: String,
        pickup: String,
        destination: String,
        seats: Int = 1,
        notes: String? = nil,
        gift: String? = nil,
        status: RideStatus = .open,
        claimedBy: UUID? = nil,
        reviewed: Bool = false,
        reviewSkipped: Bool? = nil,
        reviewSkippedAt: Date? = nil,
        estimatedCost: Double? = nil,
        createdAt: Date = Date(),
        updatedAt: Date = Date(),
        poster: Profile? = nil,
        claimer: Profile? = nil,
        participants: [Profile]? = nil,
        qaCount: Int? = nil
    ) {
        self.id = id
        self.userId = userId
        self.type = type
        self.date = date
        self.time = time
        self.pickup = pickup
        self.destination = destination
        self.seats = seats
        self.notes = notes
        self.gift = gift
        self.status = status
        self.claimedBy = claimedBy
        self.reviewed = reviewed
        self.reviewSkipped = reviewSkipped
        self.reviewSkippedAt = reviewSkippedAt
        self.estimatedCost = estimatedCost
        self.createdAt = createdAt
        self.updatedAt = updatedAt
        self.poster = poster
        self.claimer = claimer
        self.participants = participants
        self.qaCount = qaCount
    }
}


