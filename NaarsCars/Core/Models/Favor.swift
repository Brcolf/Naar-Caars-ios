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
    /// Community the favor was posted to. Nil when the payload has no `community_id`
    /// (unknown: shown everywhere, never filtered out).
    let communityId: UUID?
    let createdAt: Date
    let updatedAt: Date
    /// Example content of the example community. False when `is_example` is absent (a server
    /// before Release 2). The server refuses a claim of an example (`example_request`) and every
    /// client write of the flag, so it is read only, never sent.
    let isExample: Bool
    
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
        case communityId = "community_id"
        case createdAt = "created_at"
        case updatedAt = "updated_at"
        case isExample = "is_example"
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
        communityId: UUID? = nil,
        createdAt: Date = Date(),
        updatedAt: Date = Date(),
        isExample: Bool = false,
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
        self.communityId = communityId
        self.createdAt = createdAt
        self.updatedAt = updatedAt
        self.isExample = isExample
        self.poster = poster
        self.claimer = claimer
        self.participants = participants
        self.qaCount = qaCount
    }
}

extension Favor {
    /// Matches the synthesized decoder for every other key; `is_example` may be absent (a server
    /// before Release 2, or a payload that does not select it) and then reads false.
    init(from decoder: Decoder) throws {
        let c = try decoder.container(keyedBy: CodingKeys.self)
        id = try c.decode(UUID.self, forKey: .id)
        userId = try c.decode(UUID.self, forKey: .userId)
        title = try c.decode(String.self, forKey: .title)
        description = try c.decodeIfPresent(String.self, forKey: .description)
        location = try c.decode(String.self, forKey: .location)
        duration = try c.decode(FavorDuration.self, forKey: .duration)
        requirements = try c.decodeIfPresent(String.self, forKey: .requirements)
        date = try c.decode(Date.self, forKey: .date)
        time = try c.decodeIfPresent(String.self, forKey: .time)
        timezone = try c.decode(String.self, forKey: .timezone)
        gift = try c.decodeIfPresent(String.self, forKey: .gift)
        status = try c.decode(FavorStatus.self, forKey: .status)
        claimedBy = try c.decodeIfPresent(UUID.self, forKey: .claimedBy)
        reviewed = try c.decode(Bool.self, forKey: .reviewed)
        reviewSkipped = try c.decodeIfPresent(Bool.self, forKey: .reviewSkipped)
        reviewSkippedAt = try c.decodeIfPresent(Date.self, forKey: .reviewSkippedAt)
        hiddenAt = try c.decodeIfPresent(Date.self, forKey: .hiddenAt)
        hiddenBy = try c.decodeIfPresent(UUID.self, forKey: .hiddenBy)
        hiddenReason = try c.decodeIfPresent(String.self, forKey: .hiddenReason)
        communityId = try c.decodeIfPresent(UUID.self, forKey: .communityId)
        createdAt = try c.decode(Date.self, forKey: .createdAt)
        updatedAt = try c.decode(Date.self, forKey: .updatedAt)
        isExample = try c.decodeIfPresent(Bool.self, forKey: .isExample) ?? false
    }
}
