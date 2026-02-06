//
//  ClaimService.swift
//  NaarsCars
//
//  Service for claim-related operations
//

import Foundation
import Supabase

/// Service for claim-related operations
/// Handles claiming, unclaiming, and completing requests
@MainActor
final class ClaimService {
    
    // MARK: - Singleton
    
    static let shared = ClaimService()
    
    // MARK: - Private Properties
    
    private let supabase = SupabaseService.shared.client
    private let rateLimiter = RateLimiter.shared
    
    // MARK: - Initialization
    
    private init() {}
    
    // MARK: - Claim Request
    
    /// Claim a request (ride or favor)
    /// - Parameters:
    ///   - requestType: "ride" or "favor"
    ///   - requestId: Request ID
    ///   - claimerId: User ID of the claimer
    /// - Throws: AppError if claim fails
    func claimRequest(
        requestType: String,
        requestId: UUID,
        claimerId: UUID
    ) async throws {
        // Check rate limit (10 seconds between claims)
        let rateLimitKey = "claim_request_\(claimerId.uuidString)"
        let canProceed = await rateLimiter.checkAndRecord(
            action: rateLimitKey,
            minimumInterval: Constants.RateLimits.claimRequest
        )
        
        guard canProceed else {
            throw AppError.rateLimitExceeded("Please wait before claiming another request")
        }
        
        // Verify user has phone number
        let profile = try await ProfileService.shared.fetchProfile(userId: claimerId)
        guard profile.phoneNumber != nil, !profile.phoneNumber!.isEmpty else {
            throw AppError.invalidInput("Phone number is required to claim requests")
        }
        
        // Determine table name
        let tableName = requestType == "ride" ? "rides" : "favors"
        
        // Update request status to "confirmed" and set claimed_by
        let updates: [String: AnyCodable] = [
            "status": AnyCodable("confirmed"),
            "claimed_by": AnyCodable(claimerId.uuidString),
            "updated_at": AnyCodable(ISO8601DateFormatter().string(from: Date()))
        ]
        
        try await supabase
            .from(tableName)
            .update(updates)
            .eq("id", value: requestId.uuidString)
            .execute()
        
        let posterId = try await getPosterId(requestType: requestType, requestId: requestId)
        
        // Create notification for poster
        try await createClaimNotification(
            requestType: requestType,
            requestId: requestId,
            posterId: posterId,
            claimerId: claimerId
        )

        // Completion reminders are server-scheduled via database triggers.
    }
    
    // MARK: - Unclaim Request
    
    /// Unclaim a request (reset to open)
    /// - Parameters:
    ///   - requestType: "ride" or "favor"
    ///   - requestId: Request ID
    ///   - claimerId: User ID of the claimer (for verification)
    /// - Throws: AppError if unclaim fails
    func unclaimRequest(
        requestType: String,
        requestId: UUID,
        claimerId: UUID
    ) async throws {
        // Check rate limit
        let rateLimitKey = "unclaim_request_\(claimerId.uuidString)"
        let canProceed = await rateLimiter.checkAndRecord(
            action: rateLimitKey,
            minimumInterval: Constants.RateLimits.claimRequest
        )
        
        guard canProceed else {
            throw AppError.rateLimitExceeded("Please wait before unclaiming again")
        }
        
        // Determine table name
        let tableName = requestType == "ride" ? "rides" : "favors"
        
        // Verify the claimer is the one who claimed it
        let response = try await supabase
            .from(tableName)
            .select("claimed_by")
            .eq("id", value: requestId.uuidString)
            .single()
            .execute()
        
        struct ClaimedBy: Codable {
            let claimedBy: UUID?
            
            enum CodingKeys: String, CodingKey {
                case claimedBy = "claimed_by"
            }
        }
        
        let claimedBy: ClaimedBy = try JSONDecoder().decode(ClaimedBy.self, from: response.data)
        
        guard claimedBy.claimedBy == claimerId else {
            throw AppError.permissionDenied("You can only unclaim requests you claimed")
        }
        
        // Reset status to "open" and clear claimed_by
        let updates: [String: AnyCodable] = [
            "status": AnyCodable("open"),
            "claimed_by": AnyCodable(String?.none as Any),
            "updated_at": AnyCodable(ISO8601DateFormatter().string(from: Date()))
        ]
        
        try await supabase
            .from(tableName)
            .update(updates)
            .eq("id", value: requestId.uuidString)
            .execute()
        
        // Create notification for poster
        try await createUnclaimNotification(
            requestType: requestType,
            requestId: requestId,
            posterId: try await getPosterId(requestType: requestType, requestId: requestId)
        )
        
    }
    
    // MARK: - Complete Request
    
    /// Mark a request as completed (only poster can do this)
    /// - Parameters:
    ///   - requestType: "ride" or "favor"
    ///   - requestId: Request ID
    ///   - posterId: User ID of the poster (for verification)
    /// - Throws: AppError if complete fails
    func completeRequest(
        requestType: String,
        requestId: UUID,
        posterId: UUID
    ) async throws {
        // Determine table name
        let tableName = requestType == "ride" ? "rides" : "favors"
        
        // Verify the poster is the one who created it
        let response = try await supabase
            .from(tableName)
            .select("user_id")
            .eq("id", value: requestId.uuidString)
            .single()
            .execute()
        
        struct UserId: Codable {
            let userId: UUID
            
            enum CodingKeys: String, CodingKey {
                case userId = "user_id"
            }
        }
        
        let userId: UserId = try JSONDecoder().decode(UserId.self, from: response.data)
        
        guard userId.userId == posterId else {
            throw AppError.permissionDenied("Only the poster can mark a request as complete")
        }
        
        // Update status to "completed"
        let updates: [String: AnyCodable] = [
            "status": AnyCodable("completed"),
            "updated_at": AnyCodable(ISO8601DateFormatter().string(from: Date()))
        ]
        
        try await supabase
            .from(tableName)
            .update(updates)
            .eq("id", value: requestId.uuidString)
            .execute()
        
        // Note: Review prompt will be handled by the UI layer
    }
    
    // MARK: - Private Helpers
    
    /// Get the poster ID for a request
    private func getPosterId(requestType: String, requestId: UUID) async throws -> UUID {
        let tableName = requestType == "ride" ? "rides" : "favors"
        
        let response = try await supabase
            .from(tableName)
            .select("user_id")
            .eq("id", value: requestId.uuidString)
            .single()
            .execute()
        
        struct UserId: Codable {
            let userId: UUID
            
            enum CodingKeys: String, CodingKey {
                case userId = "user_id"
            }
        }
        
        let userId: UserId = try JSONDecoder().decode(UserId.self, from: response.data)
        return userId.userId
    }
    
    /// Create notification when request is claimed
    private func createClaimNotification(
        requestType: String,
        requestId: UUID,
        posterId: UUID,
        claimerId: UUID
    ) async throws {
        // Get claimer profile for notification
        let claimerProfile = try await ProfileService.shared.fetchProfile(userId: claimerId)
        
        let notificationType = requestType == "ride" ? "ride_claimed" : "favor_claimed"
        let title = requestType == "ride" ? "Ride Claimed!" : "Favor Claimed!"
        let body = "\(claimerProfile.name) is helping with your \(requestType) request"
        
        let notificationData: [String: AnyCodable] = [
            "user_id": AnyCodable(posterId.uuidString),
            "type": AnyCodable(notificationType),
            "title": AnyCodable(title),
            "body": AnyCodable(body),
            "ride_id": AnyCodable((requestType == "ride" ? requestId.uuidString : nil) as Any),
            "favor_id": AnyCodable((requestType == "favor" ? requestId.uuidString : nil) as Any),
            "read": AnyCodable(false),
            "pinned": AnyCodable(false)
        ]
        
        _ = try? await supabase
            .from("notifications")
            .insert(notificationData)
            .execute()
    }
    
    /// Create notification when request is unclaimed
    private func createUnclaimNotification(
        requestType: String,
        requestId: UUID,
        posterId: UUID
    ) async throws {
        let notificationType = requestType == "ride" ? "ride_unclaimed" : "favor_unclaimed"
        let title = requestType == "ride" ? "Ride Unclaimed" : "Favor Unclaimed"
        let body = "Your \(requestType) request is open again"
        
        let notificationData: [String: AnyCodable] = [
            "user_id": AnyCodable(posterId.uuidString),
            "type": AnyCodable(notificationType),
            "title": AnyCodable(title),
            "body": AnyCodable(body),
            "ride_id": AnyCodable((requestType == "ride" ? requestId.uuidString : nil) as Any),
            "favor_id": AnyCodable((requestType == "favor" ? requestId.uuidString : nil) as Any),
            "read": AnyCodable(false),
            "pinned": AnyCodable(false)
        ]
        
        _ = try? await supabase
            .from("notifications")
            .insert(notificationData)
            .execute()
    }
    
}

