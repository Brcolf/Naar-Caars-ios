//
//  ProfileService.swift
//  NaarsCars
//
//  Service for profile-related operations with caching and image compression
//

import Foundation
import UIKit
import Supabase
import OSLog

/// Service for profile-related operations
/// Handles fetching, updating profiles, avatar uploads, reviews, and invite codes
@MainActor
final class ProfileService {
    
    // MARK: - Singleton
    
    static let shared = ProfileService()
    
    // MARK: - Private Properties
    
    private let supabase = SupabaseService.shared.client
    
    // MARK: - Initialization
    
    private init() {}
    
    // MARK: - Profile Operations
    
    /// Fetch a profile by user ID
    /// Checks cache before making network request
    /// - Parameter userId: The user ID to fetch
    /// - Returns: Profile if found
    /// - Throws: AppError if fetch fails
    func fetchProfile(userId: UUID) async throws -> Profile {
        // Check cache first
        if let cached = await CacheManager.shared.getCachedProfile(id: userId) {
            return cached
        }
        
        // Fetch from network
        let profile: Profile = try await supabase
            .from("profiles")
            .select()
            .eq("id", value: userId.uuidString)
            .single()
            .execute()
            .value
        
        // Cache the profile
        await CacheManager.shared.cacheProfile(profile)
        
        return profile
    }
    
    /// Update the current user's profile
    /// - Parameters:
    ///   - userId: The user ID
    ///   - name: Optional new name
    ///   - phoneNumber: Optional new phone number (E.164 format)
    ///   - car: Optional new car description
    ///   - avatarUrl: Optional new avatar URL
    /// - Throws: AppError if update fails
    func updateProfile(
        userId: UUID,
        name: String? = nil,
        phoneNumber: String? = nil,
        car: String? = nil,
        avatarUrl: String? = nil,
        shouldUpdateAvatar: Bool = false
    ) async throws {
        let dateFormatter = ISO8601DateFormatter()
        dateFormatter.formatOptions = [.withInternetDateTime, .withFractionalSeconds]

        var update: [String: AnyCodable] = [
            "updated_at": AnyCodable(dateFormatter.string(from: Date()))
        ]
        
        // Only include phone_number and car when explicitly provided
        // to avoid nullifying them on every profile update
        if let phoneNumber = phoneNumber {
            update["phone_number"] = AnyCodable(phoneNumber)
        }
        if let car = car {
            update["car"] = AnyCodable(car)
        }

        if let name = name {
            update["name"] = AnyCodable(name)
        }

        if shouldUpdateAvatar {
            update["avatar_url"] = AnyCodable(avatarUrl as Any)
        }
        
        try await supabase
            .from("profiles")
            .update(update)
            .eq("id", value: userId.uuidString)
            .execute()
        
        // Invalidate cache after update
        await CacheManager.shared.invalidateProfile(id: userId)
    }
    
    /// Update notification preferences for the current user's profile
    /// - Parameters:
    ///   - userId: The user ID
    ///   - preferences: Dictionary of notification preference updates
    /// - Throws: AppError if update fails
    func updateNotificationPreferences(
        userId: UUID,
        notifyRideUpdates: Bool? = nil,
        notifyMessages: Bool? = nil,
        notifyAnnouncements: Bool? = nil,
        notifyNewRequests: Bool? = nil,
        notifyQaActivity: Bool? = nil,
        notifyReviewReminders: Bool? = nil,
        notifyTownHall: Bool? = nil
    ) async throws {
        struct NotificationPreferencesUpdate: Codable {
            let notifyRideUpdates: Bool?
            let notifyMessages: Bool?
            let notifyAnnouncements: Bool?
            let notifyNewRequests: Bool?
            let notifyQaActivity: Bool?
            let notifyReviewReminders: Bool?
            let notifyTownHall: Bool?
            let updatedAt: String
            
            enum CodingKeys: String, CodingKey {
                case notifyRideUpdates = "notify_ride_updates"
                case notifyMessages = "notify_messages"
                case notifyAnnouncements = "notify_announcements"
                case notifyNewRequests = "notify_new_requests"
                case notifyQaActivity = "notify_qa_activity"
                case notifyReviewReminders = "notify_review_reminders"
                case notifyTownHall = "notify_town_hall"
                case updatedAt = "updated_at"
            }
        }
        
        let dateFormatter = ISO8601DateFormatter()
        dateFormatter.formatOptions = [.withInternetDateTime, .withFractionalSeconds]
        
        let update = NotificationPreferencesUpdate(
            notifyRideUpdates: notifyRideUpdates,
            notifyMessages: notifyMessages,
            notifyAnnouncements: notifyAnnouncements,
            notifyNewRequests: notifyNewRequests,
            notifyQaActivity: notifyQaActivity,
            notifyReviewReminders: notifyReviewReminders,
            notifyTownHall: notifyTownHall,
            updatedAt: dateFormatter.string(from: Date())
        )
        
        try await supabase
            .from("profiles")
            .update(update)
            .eq("id", value: userId.uuidString)
            .execute()
        
        // Invalidate cache after update
        await CacheManager.shared.invalidateProfile(id: userId)
    }
    
    /// Accept community guidelines
    /// - Parameter userId: The user ID
    /// - Throws: AppError if update fails
    func acceptCommunityGuidelines(userId: UUID) async throws {
        struct GuidelinesAcceptance: Codable {
            let guidelinesAccepted: Bool
            let guidelinesAcceptedAt: String
            let updatedAt: String
            
            enum CodingKeys: String, CodingKey {
                case guidelinesAccepted = "guidelines_accepted"
                case guidelinesAcceptedAt = "guidelines_accepted_at"
                case updatedAt = "updated_at"
            }
        }
        
        let dateFormatter = ISO8601DateFormatter()
        dateFormatter.formatOptions = [.withInternetDateTime, .withFractionalSeconds]
        let now = dateFormatter.string(from: Date())
        
        let acceptance = GuidelinesAcceptance(
            guidelinesAccepted: true,
            guidelinesAcceptedAt: now,
            updatedAt: now
        )
        
        try await supabase
            .from("profiles")
            .update(acceptance)
            .eq("id", value: userId.uuidString)
            .execute()
        
        // Invalidate cache after update
        await CacheManager.shared.invalidateProfile(id: userId)
    }
    
    /// Upload avatar image to Supabase Storage
    /// Compresses image before upload using avatar preset
    /// - Parameters:
    ///   - imageData: The image data to upload
    ///   - userId: The user ID
    /// - Returns: Public URL of uploaded avatar
    /// - Throws: AppError if upload fails
    func uploadAvatar(imageData: Data, userId: UUID) async throws -> String {
        // Compress image using avatar preset
        guard let uiImage = UIImage(data: imageData) else {
            throw AppError.invalidInput("Invalid image data")
        }
        
        guard let compressedData = await ImageCompressor.compressAsync(uiImage, preset: .avatar) else {
            throw AppError.processingError("Failed to compress image")
        }
        
        // Upload to avatars bucket
        let fileName = "\(userId.uuidString).jpg"
        
        try await supabase.storage
            .from("avatars")
            .upload(
                fileName,
                data: compressedData,
                options: FileOptions(contentType: "image/jpeg", upsert: true)
            )
        
        // Get public URL with cache-busting query param
        let publicUrl = try supabase.storage
            .from("avatars")
            .getPublicURL(path: fileName)
        
        // Append cache-busting query parameter
        let timestamp = Int(Date().timeIntervalSince1970)
        let urlWithCacheBust = "\(publicUrl.absoluteString)?t=\(timestamp)"
        
        return urlWithCacheBust
    }
    
    /// Fetch multiple profiles by user IDs in a single batch query
    /// Checks cache first, only fetches missing profiles from network
    /// - Parameter userIds: Array of user IDs to fetch
    /// - Returns: Array of profiles (order not guaranteed)
    /// - Throws: AppError if fetch fails
    func fetchProfiles(userIds: [UUID]) async throws -> [Profile] {
        guard !userIds.isEmpty else { return [] }
        
        // Check cache first, only fetch missing
        var cached: [Profile] = []
        var missing: [UUID] = []
        for id in userIds {
            if let p = await CacheManager.shared.getCachedProfile(id: id) {
                cached.append(p)
            } else {
                missing.append(id)
            }
        }
        
        guard !missing.isEmpty else { return cached }
        
        // Batch fetch missing profiles in a single query
        let fetched: [Profile] = try await supabase
            .from("profiles")
            .select()
            .in("id", values: missing.map { $0.uuidString })
            .execute()
            .value
        
        // Cache all fetched profiles
        for profile in fetched {
            await CacheManager.shared.cacheProfile(profile)
        }
        
        return cached + fetched
    }
    
    // MARK: - Reviews Operations
    
    /// Fetch reviews for a user
    /// - Parameter userId: The user ID
    /// - Returns: Array of reviews
    /// - Throws: AppError if fetch fails
    func fetchReviews(forUserId userId: UUID) async throws -> [Review] {
        let reviews: [Review] = try await supabase
            .from("reviews")
            .select()
            .eq("fulfiller_id", value: userId.uuidString)
            .order("created_at", ascending: false)
            .execute()
            .value
        
        return reviews
    }
    
    /// Calculate average rating for a user
    /// - Parameter userId: The user ID
    /// - Returns: Average rating (0.0 to 5.0), or nil if no reviews
    func calculateAverageRating(userId: UUID) async throws -> Double? {
        let reviews: [ReviewRating] = try await supabase
            .from("reviews")
            .select("rating")
            .eq("fulfiller_id", value: userId.uuidString)
            .execute()
            .value
        
        guard !reviews.isEmpty else {
            return nil
        }
        
        let sum = reviews.reduce(0.0) { $0 + Double($1.rating) }
        return sum / Double(reviews.count)
    }
    
    // MARK: - Invite Codes Operations
    
    /// Fetch invite codes for a user
    /// - Parameter userId: The user ID
    /// - Returns: Array of invite codes ordered by created_at descending
    /// - Throws: AppError if fetch fails
    func fetchInviteCodes(forUserId userId: UUID) async throws -> [InviteCode] {
        let codes: [InviteCode] = try await supabase
            .from("invite_codes")
            .select()
            .eq("created_by", value: userId.uuidString)
            .order("created_at", ascending: false)
            .execute()
            .value
        
        return codes
    }
    
    /// Generate a new invite code for a user
    /// Uses InviteCodeGenerator for secure 8-character codes
    /// - Parameter userId: The user ID
    /// - Returns: The newly created invite code
    /// - Throws: AppError if generation fails
    func generateInviteCode(userId: UUID) async throws -> InviteCode {
        // Generate secure 8-character code
        let code = InviteCodeGenerator.generate()
        
        let newCode = InviteCode(
            id: UUID(),
            code: code,
            createdBy: userId,
            usedBy: nil,
            usedAt: nil,
            createdAt: Date()
        )
        
        let insertedCode: InviteCode = try await supabase
            .from("invite_codes")
            .insert(newCode)
            .select()
            .single()
            .execute()
            .value
        
        return insertedCode
    }
    
    // MARK: - Stats Operations
    
    /// Fetch fulfilled count for a user
    /// Counts confirmed/completed rides and favors
    /// - Parameter userId: The user ID
    /// - Returns: Total count of fulfilled requests
    func fetchFulfilledCount(userId: UUID) async throws -> Int {
        // Count confirmed/completed rides
        let ridesResponse = try await supabase
            .from("rides")
            .select("id", head: true, count: .exact)
            .eq("claimed_by", value: userId.uuidString)
            .in("status", values: ["confirmed", "completed"])
            .execute()
        
        let ridesCount = ridesResponse.count ?? 0
        
        // Count confirmed/completed favors
        let favorsResponse = try await supabase
            .from("favors")
            .select("id", head: true, count: .exact)
            .eq("claimed_by", value: userId.uuidString)
            .in("status", values: ["confirmed", "completed"])
            .execute()
        
        let favorsCount = favorsResponse.count ?? 0
        
        return ridesCount + favorsCount
    }
    
    /// Delete user account and all associated data
    /// Uses database function to handle cascade deletion
    /// Also revokes Apple Sign-In if linked (required by Apple for account deletion)
    /// - Parameter userId: The user ID to delete
    /// - Throws: AppError if deletion fails
    func deleteAccount(userId: UUID) async throws {
        // 1. Revoke Apple Sign-In if linked (Apple App Store requirement)
        // This must be done BEFORE deleting the account
        let _ = await AuthService.shared.revokeAppleSignIn()
        
        // 2. Use database function to delete account (handles cascade deletes)
        let params: [String: AnyCodable] = [
            "p_user_id": AnyCodable(userId.uuidString)
        ]
        let client = SupabaseService.shared.client
        _ = try await client
            .rpc("delete_user_account", params: params)
            .execute()
        
        // 3. Invalidate cache
        await CacheManager.shared.invalidateProfile(id: userId)
        
        AppLogger.database.info("Account deleted: \(userId.uuidString)")
    }
}

// MARK: - Helper Types

/// Helper struct for decoding review ratings
private struct ReviewRating: Codable {
    let rating: Int
}

