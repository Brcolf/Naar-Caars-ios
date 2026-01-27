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
    /// - Returns: Created conversation ID
    /// - Throws: AppError if claim fails
    func claimRequest(
        requestType: String,
        requestId: UUID,
        claimerId: UUID
    ) async throws -> UUID {
        // Check rate limit (10 seconds between claims)
        let rateLimitKey = "claim_request_\(claimerId.uuidString)"
        let canProceed = await rateLimiter.checkAndRecord(
            action: rateLimitKey,
            minimumInterval: 10.0
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
        
        // Create conversation with poster and claimer
        let posterId = try await getPosterId(requestType: requestType, requestId: requestId)
        let conversation = try await MessageService.shared.createConversationWithUsers(
            userIds: [posterId, claimerId],
            createdBy: posterId,
            title: nil
        )
        let conversationId = conversation.id
        
        // Create notification for poster
        try await createClaimNotification(
            requestType: requestType,
            requestId: requestId,
            posterId: try await getPosterId(requestType: requestType, requestId: requestId),
            claimerId: claimerId
        )
        
        // Schedule completion reminder local notification
        await scheduleCompletionReminderIfNeeded(
            requestType: requestType,
            requestId: requestId,
            claimerId: claimerId
        )
        
        return conversationId
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
            minimumInterval: 10.0
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
            "claimed_by": AnyCodable(String?.none),
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
        
        // Cancel any scheduled completion reminder
        await cancelCompletionReminderIfExists(
            requestType: requestType,
            requestId: requestId
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
            "ride_id": AnyCodable(requestType == "ride" ? requestId.uuidString : nil),
            "favor_id": AnyCodable(requestType == "favor" ? requestId.uuidString : nil),
            "read": AnyCodable(false),
            "pinned": AnyCodable(false)
        ]
        
        try? await supabase
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
            "ride_id": AnyCodable(requestType == "ride" ? requestId.uuidString : nil),
            "favor_id": AnyCodable(requestType == "favor" ? requestId.uuidString : nil),
            "read": AnyCodable(false),
            "pinned": AnyCodable(false)
        ]
        
        try? await supabase
            .from("notifications")
            .insert(notificationData)
            .execute()
    }
    
    // MARK: - Completion Reminder Helpers
    
    /// Schedule a local notification for completion reminder
    /// The database trigger creates the completion_reminder record when claim happens
    private func scheduleCompletionReminderIfNeeded(
        requestType: String,
        requestId: UUID,
        claimerId: UUID
    ) async {
        do {
            // Fetch the completion reminder that was created by the database trigger
            let rideIdFilter = requestType == "ride" ? requestId.uuidString : nil
            let favorIdFilter = requestType == "favor" ? requestId.uuidString : nil
            
            var query = supabase
                .from("completion_reminders")
                .select("id, scheduled_for")
                .eq("claimer_user_id", value: claimerId.uuidString)
                .eq("completed", value: false)
            
            if let rideId = rideIdFilter {
                query = query.eq("ride_id", value: rideId)
            } else if let favorId = favorIdFilter {
                query = query.eq("favor_id", value: favorId)
            }
            
            let response = try await query
                .order("created_at", ascending: false)
                .limit(1)
                .single()
                .execute()
            
            struct ReminderInfo: Codable {
                let id: UUID
                let scheduledFor: Date
                
                enum CodingKeys: String, CodingKey {
                    case id
                    case scheduledFor = "scheduled_for"
                }
            }
            
            let decoder = JSONDecoder()
            decoder.dateDecodingStrategy = .iso8601
            let reminder = try decoder.decode(ReminderInfo.self, from: response.data)
            
            // Build request title for the notification
            let requestTitle: String
            if requestType == "ride" {
                // Try to get ride destination
                let rideResponse = try? await supabase
                    .from("rides")
                    .select("destination_name")
                    .eq("id", value: requestId.uuidString)
                    .single()
                    .execute()
                
                if let rideData = rideResponse?.data,
                   let ride = try? JSONDecoder().decode([String: String?].self, from: rideData),
                   let destination = ride["destination_name"] ?? nil {
                    requestTitle = "ride to \(destination)"
                } else {
                    requestTitle = "your ride"
                }
            } else {
                // Try to get favor title
                let favorResponse = try? await supabase
                    .from("favors")
                    .select("title")
                    .eq("id", value: requestId.uuidString)
                    .single()
                    .execute()
                
                if let favorData = favorResponse?.data,
                   let favor = try? JSONDecoder().decode([String: String?].self, from: favorData),
                   let title = favor["title"] ?? nil {
                    requestTitle = title
                } else {
                    requestTitle = "your favor"
                }
            }
            
            // Schedule the local notification
            await PushNotificationService.shared.scheduleCompletionReminder(
                reminderId: reminder.id,
                requestTitle: requestTitle,
                rideId: requestType == "ride" ? requestId : nil,
                favorId: requestType == "favor" ? requestId : nil,
                scheduledFor: reminder.scheduledFor
            )
            
            print("✅ [ClaimService] Scheduled completion reminder for \(reminder.scheduledFor)")
        } catch {
            print("⚠️ [ClaimService] Could not schedule completion reminder: \(error)")
            // This is non-critical, so we don't throw
        }
    }
    
    /// Cancel any existing completion reminder for a request
    private func cancelCompletionReminderIfExists(
        requestType: String,
        requestId: UUID
    ) async {
        do {
            let rideIdFilter = requestType == "ride" ? requestId.uuidString : nil
            let favorIdFilter = requestType == "favor" ? requestId.uuidString : nil
            
            var query = supabase
                .from("completion_reminders")
                .select("id")
                .eq("completed", value: false)
            
            if let rideId = rideIdFilter {
                query = query.eq("ride_id", value: rideId)
            } else if let favorId = favorIdFilter {
                query = query.eq("favor_id", value: favorId)
            }
            
            let response = try await query.execute()
            
            struct ReminderId: Codable {
                let id: UUID
            }
            
            let reminders = try JSONDecoder().decode([ReminderId].self, from: response.data)
            
            for reminder in reminders {
                // Cancel the local notification
                PushNotificationService.shared.cancelCompletionReminder(reminderId: reminder.id)
                
                // Mark as completed in database (unclaimed means no longer needed)
                try? await supabase
                    .from("completion_reminders")
                    .update(["completed": AnyCodable(true)])
                    .eq("id", value: reminder.id.uuidString)
                    .execute()
            }
            
            if !reminders.isEmpty {
                print("✅ [ClaimService] Cancelled \(reminders.count) completion reminder(s)")
            }
        } catch {
            print("⚠️ [ClaimService] Could not cancel completion reminders: \(error)")
        }
    }
}

