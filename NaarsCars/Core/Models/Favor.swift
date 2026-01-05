//
//  Favor.swift
//  NaarsCars
//
//  Favor request model matching database schema
//

import Foundation

/// Favor status enum matching database enum
enum FavorStatus: String, Codable {
    case open = "open"
    case pending = "pending"
    case confirmed = "confirmed"
    case completed = "completed"
}

/// Favor duration enum matching database enum
enum FavorDuration: String, Codable {
    case underHour = "under_hour"
    case coupleHours = "couple_hours"
    case coupleDays = "couple_days"
    case notSure = "not_sure"
}

/// Favor request model
struct Favor: Codable, Identifiable, Equatable {
    let id: UUID
    let userId: UUID
    let title: String
    let description: String?
    let location: String
    let duration: FavorDuration
    let requirements: String?
    let date: Date
    let time: String? // TIME type in PostgreSQL (optional)
    let gift: String?
    let status: FavorStatus
    let claimedBy: UUID?
    let reviewed: Bool
    let reviewSkipped: Bool?
    let reviewSkippedAt: Date?
    let createdAt: Date
    let updatedAt: Date
    
    // MARK: - CodingKeys
    
    enum CodingKeys: String, CodingKey {
        case id
        case userId = "user_id"
        case title
        case description
        case location
        case duration
        case requirements
        case date
        case time
        case gift
        case status
        case claimedBy = "claimed_by"
        case reviewed
        case reviewSkipped = "review_skipped"
        case reviewSkippedAt = "review_skipped_at"
        case createdAt = "created_at"
        case updatedAt = "updated_at"
    }
    
    // MARK: - Initializers
    
    init(
        id: UUID = UUID(),
        userId: UUID,
        title: String,
        description: String? = nil,
        location: String,
        duration: FavorDuration = .notSure,
        requirements: String? = nil,
        date: Date,
        time: String? = nil,
        gift: String? = nil,
        status: FavorStatus = .open,
        claimedBy: UUID? = nil,
        reviewed: Bool = false,
        reviewSkipped: Bool? = nil,
        reviewSkippedAt: Date? = nil,
        createdAt: Date = Date(),
        updatedAt: Date = Date()
    ) {
        self.id = id
        self.userId = userId
        self.title = title
        self.description = description
        self.location = location
        self.duration = duration
        self.requirements = requirements
        self.date = date
        self.time = time
        self.gift = gift
        self.status = status
        self.claimedBy = claimedBy
        self.reviewed = reviewed
        self.reviewSkipped = reviewSkipped
        self.reviewSkippedAt = reviewSkippedAt
        self.createdAt = createdAt
        self.updatedAt = updatedAt
    }
}


