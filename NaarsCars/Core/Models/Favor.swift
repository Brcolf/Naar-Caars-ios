//
//  Favor.swift
//  NaarsCars
//
//  Favor request model matching database schema
//

import Foundation
import SwiftUI
import SwiftUI

/// Favor status enum matching database enum
enum FavorStatus: String, Codable {
    case open = "open"
    case pending = "pending"
    case confirmed = "confirmed"
    case completed = "completed"
    
    /// Human-readable display text
    var displayText: String {
        switch self {
        case .open: return "request_status_open".localized
        case .pending: return "request_status_pending".localized
        case .confirmed: return "request_status_claimed".localized
        case .completed: return "request_status_completed".localized
        }
    }
    
    /// Color for status badge
    var color: Color {
        switch self {
        case .open: return .naarsSuccess
        case .pending: return .naarsWarning
        case .confirmed: return .naarsPrimary
        case .completed: return .naarsTextSecondary
        }
    }
}

/// Favor duration enum matching database enum
enum FavorDuration: String, Codable, CaseIterable {
    case underHour = "under_hour"
    case coupleHours = "couple_hours"
    case coupleDays = "couple_days"
    case notSure = "not_sure"
    
    /// Human-readable display text
    var displayText: String {
        switch self {
        case .underHour: return "favor_duration_under_hour".localized
        case .coupleHours: return "favor_duration_couple_hours".localized
        case .coupleDays: return "favor_duration_couple_days".localized
        case .notSure: return "favor_duration_not_sure".localized
        }
    }
    
    /// Icon for duration
    var icon: String {
        switch self {
        case .underHour: return "clock"
        case .coupleHours: return "clock.badge"
        case .coupleDays: return "calendar"
        case .notSure: return "questionmark.circle"
        }
    }
}

/// Favor request model
struct Favor: Codable, Identifiable, Equatable, Sendable {
    let id: UUID
    let userId: UUID
    let title: String
    let description: String?
    let location: String
    let duration: FavorDuration
    let requirements: String?
    let date: Date
    let time: String? // TIME type in PostgreSQL (optional)
    let timezone: String
    let gift: String?
    let status: FavorStatus
    let claimedBy: UUID?
    let reviewed: Bool
    let reviewSkipped: Bool?
    let reviewSkippedAt: Date?
    let hiddenAt: Date?
    let hiddenBy: UUID?
    let hiddenReason: String?
    let createdAt: Date
    let updatedAt: Date
    
    // MARK: - Optional Joined Fields (populated when fetched with joins)
    
    /// Profile of the user who posted the favor
    var poster: Profile?
    
    /// Profile of the user who claimed the favor
    var claimer: Profile?
    
    /// List of participants (co-requestors)
    var participants: [Profile]?
    
    /// Count of Q&A questions/answers
    var qaCount: Int?

    // MARK: - Computed Properties

    /// Resolved TimeZone from the IANA identifier stored in `timezone`
    var timeZone: TimeZone {
        TimeZone(identifier: timezone) ?? TimeZone(identifier: "America/Los_Angeles") ?? .current
    }

    var isModerationHidden: Bool {
        hiddenAt != nil
    }

    /// The nightly expiry job closes an open favor nobody claimed by marking it `completed`
    /// with no claimer. It was never fulfilled, so it must not read "Completed".
    var isExpiredUnclaimed: Bool {
        status == .completed && claimedBy == nil && !reviewed
    }

    /// Text for the status chip on cards and in the detail header
    var statusDisplayText: String {
        isExpiredUnclaimed ? "request_status_expired".localized : status.displayText
    }

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
        case timezone
        case gift
        case status
        case claimedBy = "claimed_by"
        case reviewed
        case reviewSkipped = "review_skipped"
        case reviewSkippedAt = "review_skipped_at"
        case hiddenAt = "hidden_at"
        case hiddenBy = "hidden_by"
        case hiddenReason = "hidden_reason"
        case createdAt = "created_at"
        case updatedAt = "updated_at"
        // Joined fields are not in CodingKeys - they're populated separately
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
        timezone: String = "America/Los_Angeles",
        gift: String? = nil,
        status: FavorStatus = .open,
        claimedBy: UUID? = nil,
        reviewed: Bool = false,
        reviewSkipped: Bool? = nil,
        reviewSkippedAt: Date? = nil,
        hiddenAt: Date? = nil,
        hiddenBy: UUID? = nil,
        hiddenReason: String? = nil,
        createdAt: Date = Date(),
        updatedAt: Date = Date(),
        poster: Profile? = nil,
        claimer: Profile? = nil,
        participants: [Profile]? = nil,
        qaCount: Int? = nil
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
        self.timezone = timezone
        self.gift = gift
        self.status = status
        self.claimedBy = claimedBy
        self.reviewed = reviewed
        self.reviewSkipped = reviewSkipped
        self.reviewSkippedAt = reviewSkippedAt
        self.hiddenAt = hiddenAt
        self.hiddenBy = hiddenBy
        self.hiddenReason = hiddenReason
        self.createdAt = createdAt
        self.updatedAt = updatedAt
        self.poster = poster
        self.claimer = claimer
        self.participants = participants
        self.qaCount = qaCount
    }
}


