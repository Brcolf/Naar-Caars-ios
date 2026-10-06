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
        self.createdAt = createdAt
        self.updatedAt = updatedAt
        self.poster = poster
        self.claimer = claimer
        self.participants = participants
        self.qaCount = qaCount
    }
}


