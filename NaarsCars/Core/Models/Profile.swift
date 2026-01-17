//
//  Profile.swift
//  NaarsCars
//
//  User profile model matching database schema
//

import Foundation

/// User profile model
struct Profile: Codable, Identifiable, Equatable, Sendable {
    let id: UUID
    let name: String
    let email: String
    let car: String?
    let phoneNumber: String?
    let avatarUrl: String?
    let isAdmin: Bool
    let approved: Bool
    let invitedBy: UUID?
    
    // Notification preferences
    let notifyRideUpdates: Bool
    let notifyMessages: Bool
    let notifyAnnouncements: Bool
    let notifyNewRequests: Bool
    let notifyQaActivity: Bool
    let notifyReviewReminders: Bool
    
    let createdAt: Date
    let updatedAt: Date
    
    // MARK: - Computed Properties
    
    /// User initials (first letter of first and last name)
    var initials: String {
        let components = name.split(separator: " ")
        guard components.count >= 2 else {
            // Single name - use first two characters
            return String(name.prefix(2)).uppercased()
        }
        let firstInitial = String(components[0].prefix(1))
        let lastInitial = String(components[components.count - 1].prefix(1))
        return (firstInitial + lastInitial).uppercased()
    }
    
    // MARK: - CodingKeys
    
    enum CodingKeys: String, CodingKey {
        case id
        case name
        case email
        case car
        case phoneNumber = "phone_number"
        case avatarUrl = "avatar_url"
        case isAdmin = "is_admin"
        case approved
        case invitedBy = "invited_by"
        case notifyRideUpdates = "notify_ride_updates"
        case notifyMessages = "notify_messages"
        case notifyAnnouncements = "notify_announcements"
        case notifyNewRequests = "notify_new_requests"
        case notifyQaActivity = "notify_qa_activity"
        case notifyReviewReminders = "notify_review_reminders"
        case createdAt = "created_at"
        case updatedAt = "updated_at"
    }
    
    // MARK: - Custom Decoder
    
    /// Custom decoder to handle missing optional fields gracefully
    init(from decoder: Decoder) throws {
        let container = try decoder.container(keyedBy: CodingKeys.self)
        
        // Required fields
        id = try container.decode(UUID.self, forKey: .id)
        name = try container.decode(String.self, forKey: .name)
        email = try container.decode(String.self, forKey: .email)
        
        // Optional fields
        car = try container.decodeIfPresent(String.self, forKey: .car)
        phoneNumber = try container.decodeIfPresent(String.self, forKey: .phoneNumber)
        avatarUrl = try container.decodeIfPresent(String.self, forKey: .avatarUrl)
        
        // Admin/approval fields with defaults
        isAdmin = try container.decodeIfPresent(Bool.self, forKey: .isAdmin) ?? false
        approved = try container.decodeIfPresent(Bool.self, forKey: .approved) ?? false
        invitedBy = try container.decodeIfPresent(UUID.self, forKey: .invitedBy)
        
        // Notification preferences with defaults (true)
        notifyRideUpdates = try container.decodeIfPresent(Bool.self, forKey: .notifyRideUpdates) ?? true
        notifyMessages = try container.decodeIfPresent(Bool.self, forKey: .notifyMessages) ?? true
        notifyAnnouncements = try container.decodeIfPresent(Bool.self, forKey: .notifyAnnouncements) ?? true
        notifyNewRequests = try container.decodeIfPresent(Bool.self, forKey: .notifyNewRequests) ?? true
        notifyQaActivity = try container.decodeIfPresent(Bool.self, forKey: .notifyQaActivity) ?? true
        notifyReviewReminders = try container.decodeIfPresent(Bool.self, forKey: .notifyReviewReminders) ?? true
        
        // Date fields
        createdAt = try container.decode(Date.self, forKey: .createdAt)
        updatedAt = try container.decodeIfPresent(Date.self, forKey: .updatedAt) ?? createdAt
    }
    
    // MARK: - Initializers
    
    init(
        id: UUID,
        name: String,
        email: String,
        car: String? = nil,
        phoneNumber: String? = nil,
        avatarUrl: String? = nil,
        isAdmin: Bool = false,
        approved: Bool = false,
        invitedBy: UUID? = nil,
        notifyRideUpdates: Bool = true,
        notifyMessages: Bool = true,
        notifyAnnouncements: Bool = true,
        notifyNewRequests: Bool = true,
        notifyQaActivity: Bool = true,
        notifyReviewReminders: Bool = true,
        createdAt: Date = Date(),
        updatedAt: Date = Date()
    ) {
        self.id = id
        self.name = name
        self.email = email
        self.car = car
        self.phoneNumber = phoneNumber
        self.avatarUrl = avatarUrl
        self.isAdmin = isAdmin
        self.approved = approved
        self.invitedBy = invitedBy
        self.notifyRideUpdates = notifyRideUpdates
        self.notifyMessages = notifyMessages
        self.notifyAnnouncements = notifyAnnouncements
        self.notifyNewRequests = notifyNewRequests
        self.notifyQaActivity = notifyQaActivity
        self.notifyReviewReminders = notifyReviewReminders
        self.createdAt = createdAt
        self.updatedAt = updatedAt
    }
}


