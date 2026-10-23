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

/// Ride request model
struct Ride: Codable, Identifiable, Equatable, Sendable {
    let id: UUID
    let userId: UUID
    let type: String
    let date: Date
    let time: String // TIME type in PostgreSQL
    let timezone: String
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
    /// First parsed flight code from notes (e.g. DL123), saved in background after creation
    let flightNormalized: String?
    let hiddenAt: Date?
    let hiddenBy: UUID?
    let hiddenReason: String?
    /// Community the ride was posted to. Nil when the payload has no `community_id`
    /// (unknown: shown everywhere, never filtered out).
    let communityId: UUID?
    let createdAt: Date
    let updatedAt: Date
    /// Example content of the example community. False when `is_example` is absent (a server
    /// before Release 2). The server refuses a claim of an example (`example_request`) and every
    /// client write of the flag, so it is read only, never sent.
    let isExample: Bool
    
    // MARK: - Optional Joined Fields (populated when fetched with joins)
    
    /// Profile of the user who posted the ride
    var poster: Profile?
    
    /// Profile of the user who claimed the ride
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

    /// The nightly expiry job closes an open ride nobody claimed by marking it `completed`
    /// with no claimer. It was never fulfilled, so it must not read "Completed".
    var isExpiredUnclaimed: Bool {
        status == .completed && claimedBy == nil && !reviewed
    }

    /// Text for the status chip on cards and in the detail header
    var statusDisplayText: String {
        isExpiredUnclaimed ? "request_status_expired".localized : status.displayText
    }

    /// "1 seat" / "3 seats". The string catalog has no plural variants, so the form is chosen
    /// here; appending an English "s" produced "3석s" and "3 chỗs" in other languages.
    var seatsDisplayText: String {
        (seats == 1 ? "ride_seats_count_one" : "ride_seats_count_other").localized(with: seats)
    }

    // MARK: - CodingKeys

    enum CodingKeys: String, CodingKey {
        case id
        case userId = "user_id"
        case type
        case date
        case time
        case timezone
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
        case flightNormalized = "flight_normalized"
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
        type: String = "request",
        date: Date,
        time: String,
        timezone: String = "America/Los_Angeles",
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
        flightNormalized: String? = nil,
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
        self.type = type
        self.date = date
        self.time = time
        self.timezone = timezone
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
        self.flightNormalized = flightNormalized
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

extension Ride {
    /// Matches the synthesized decoder for every other key; `is_example` may be absent (a server
    /// before Release 2, or a payload that does not select it) and then reads false.
    init(from decoder: Decoder) throws {
        let c = try decoder.container(keyedBy: CodingKeys.self)
        id = try c.decode(UUID.self, forKey: .id)
        userId = try c.decode(UUID.self, forKey: .userId)
        type = try c.decode(String.self, forKey: .type)
        date = try c.decode(Date.self, forKey: .date)
        time = try c.decode(String.self, forKey: .time)
        timezone = try c.decode(String.self, forKey: .timezone)
        pickup = try c.decode(String.self, forKey: .pickup)
        destination = try c.decode(String.self, forKey: .destination)
        seats = try c.decode(Int.self, forKey: .seats)
        notes = try c.decodeIfPresent(String.self, forKey: .notes)
        gift = try c.decodeIfPresent(String.self, forKey: .gift)
        status = try c.decode(RideStatus.self, forKey: .status)
        claimedBy = try c.decodeIfPresent(UUID.self, forKey: .claimedBy)
        reviewed = try c.decode(Bool.self, forKey: .reviewed)
        reviewSkipped = try c.decodeIfPresent(Bool.self, forKey: .reviewSkipped)
        reviewSkippedAt = try c.decodeIfPresent(Date.self, forKey: .reviewSkippedAt)
        estimatedCost = try c.decodeIfPresent(Double.self, forKey: .estimatedCost)
        flightNormalized = try c.decodeIfPresent(String.self, forKey: .flightNormalized)
        hiddenAt = try c.decodeIfPresent(Date.self, forKey: .hiddenAt)
        hiddenBy = try c.decodeIfPresent(UUID.self, forKey: .hiddenBy)
        hiddenReason = try c.decodeIfPresent(String.self, forKey: .hiddenReason)
        communityId = try c.decodeIfPresent(UUID.self, forKey: .communityId)
        createdAt = try c.decode(Date.self, forKey: .createdAt)
        updatedAt = try c.decode(Date.self, forKey: .updatedAt)
        isExample = try c.decodeIfPresent(Bool.self, forKey: .isExample) ?? false
    }
}
