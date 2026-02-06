//
//  ConversationParticipantService.swift
//  NaarsCars
//
//  Service for conversation participant management
//

import Foundation
import Supabase
import OSLog

/// Service for managing conversation participants
/// Handles adding, removing, and checking participant status
@MainActor
final class ConversationParticipantService {
    
    // MARK: - Singleton
    
    static let shared = ConversationParticipantService()
    
    // MARK: - Private Properties
    
    private let supabase = SupabaseService.shared.client
    
    // MARK: - Initialization
    
    private init() {}
    
    // MARK: - Private Helpers
    
    /// Create a date decoder with custom date decoding strategy
    private func createDateDecoder() -> JSONDecoder {
        DateDecoderFactory.makeMessagingDecoder()
    }
    
    // MARK: - Participant Management
    
    /// Add participants to an existing conversation
    /// - Parameters:
    ///   - conversationId: The conversation ID
    ///   - userIds: Array of user IDs to add
    ///   - addedBy: User ID adding the participants
    ///   - createAnnouncement: Whether to create an announcement message (default: false)
    /// - Throws: AppError if operation fails
    func addParticipantsToConversation(
        conversationId: UUID,
        userIds: [UUID],
        addedBy: UUID,
        createAnnouncement: Bool = false
    ) async throws {
        AppLogger.info("messaging", "addParticipantsToConversation called - conversationId: \(conversationId), userIds: \(userIds), addedBy: \(addedBy), createAnnouncement: \(createAnnouncement)")
        
        guard !userIds.isEmpty else {
            AppLogger.warning("messaging", "No user IDs provided, returning early")
            return
        }
        
        // Get conversation to check permissions
        AppLogger.info("messaging", "Fetching conversation details")
        let conversationResponse = try await supabase
            .from("conversations")
            .select("id, title, created_by")
            .eq("id", value: conversationId.uuidString)
            .single()
            .execute()
        
        struct ConversationInfo: Codable {
            let id: UUID
            let createdBy: UUID
            enum CodingKeys: String, CodingKey {
                case id, createdBy = "created_by"
            }
        }
        
        let conversationInfo = try JSONDecoder().decode(ConversationInfo.self, from: conversationResponse.data)
        AppLogger.info("messaging", "Conversation found, created by: \(conversationInfo.createdBy)")
        
        // Check if addedBy has permission to add participants
        let canAdd = try await canModifyParticipants(
            conversationId: conversationId,
            userId: addedBy,
            creatorId: conversationInfo.createdBy
        )
        
        guard canAdd else {
            AppLogger.error("messaging", "Permission denied: user cannot add participants")
            throw AppError.permissionDenied("You don't have permission to add participants to this conversation")
        }
        
        // Get existing participants to avoid duplicates
        let existingResponse = try? await supabase
            .from("conversation_participants")
            .select("user_id")
            .eq("conversation_id", value: conversationId.uuidString)
            .execute()
        
        struct ParticipantRow: Codable {
            let userId: UUID
            enum CodingKeys: String, CodingKey {
                case userId = "user_id"
            }
        }
        
        let existingParticipants: [UUID] = (try? JSONDecoder().decode([ParticipantRow].self, from: existingResponse?.data ?? Data()))?.map { $0.userId } ?? []
        AppLogger.info("messaging", "Existing participants: \(existingParticipants.count)")
        
        // Filter out users who are already participants
        let newUserIds = userIds.filter { !existingParticipants.contains($0) }
        AppLogger.info("messaging", "New users to add (after filtering): \(newUserIds.count)")
        
        guard !newUserIds.isEmpty else {
            AppLogger.info("messaging", "All users are already participants, nothing to add")
            AppLogger.database.debug("All users are already participants")
            return
        }
        
        // Insert new participants
        let inserts = newUserIds.map { userId in
            [
                "conversation_id": AnyCodable(conversationId.uuidString),
                "user_id": AnyCodable(userId.uuidString)
            ]
        }
        
        AppLogger.info("messaging", "Inserting \(newUserIds.count) new participant(s)")
        try await supabase
            .from("conversation_participants")
            .insert(inserts)
            .execute()
        AppLogger.info("messaging", "Successfully inserted participants")
        
        // Create announcement messages if requested
        if createAnnouncement {
            AppLogger.info("messaging", "Creating announcement messages")
            for userId in newUserIds {
                if let profile = try? await ProfileService.shared.fetchProfile(userId: userId) {
                    let announcementText = "\(profile.name) has been added to the conversation"
                    let announcement = Message(
                        conversationId: conversationId,
                        fromId: addedBy,
                        text: announcementText
                    )
                    
                    do {
                        try await supabase
                            .from("messages")
                            .insert(announcement)
                            .execute()
                    } catch {
                        AppLogger.database.warning("Failed to create announcement message: \(error.localizedDescription)")
                    }
                }
            }
        }
        
        AppLogger.database.info("Added \(newUserIds.count) participant(s) to conversation \(conversationId)")
    }
    
    /// Leave a conversation (self-removal)
    /// - Parameters:
    ///   - conversationId: The conversation ID
    ///   - userId: The user leaving
    ///   - createAnnouncement: Whether to create a system message (default: true)
    /// - Throws: AppError if operation fails
    func leaveConversation(
        conversationId: UUID,
        userId: UUID,
        createAnnouncement: Bool = true
    ) async throws {
        AppLogger.database.info("User \(userId) leaving conversation \(conversationId)")
        
        // Verify user is a participant
        let participantCheck = try? await supabase
            .from("conversation_participants")
            .select("user_id, left_at")
            .eq("conversation_id", value: conversationId.uuidString)
            .eq("user_id", value: userId.uuidString)
            .single()
            .execute()
        
        struct ParticipantStatus: Codable {
            let userId: UUID
            let leftAt: Date?
            enum CodingKeys: String, CodingKey {
                case userId = "user_id"
                case leftAt = "left_at"
            }
        }
        
        guard let participantData = participantCheck?.data,
              let status = try? createDateDecoder().decode(ParticipantStatus.self, from: participantData) else {
            throw AppError.permissionDenied("You are not a participant in this conversation")
        }
        
        // Check if already left
        if status.leftAt != nil {
            AppLogger.database.debug("User already left conversation")
            return
        }
        
        // Update left_at timestamp
        let formatter = ISO8601DateFormatter()
        formatter.formatOptions = [.withInternetDateTime, .withFractionalSeconds]
        let now = formatter.string(from: Date())
        
        try await supabase
            .from("conversation_participants")
            .update(["left_at": now])
            .eq("conversation_id", value: conversationId.uuidString)
            .eq("user_id", value: userId.uuidString)
            .execute()
        
        // Create announcement message if requested
        if createAnnouncement {
            if let profile = try? await ProfileService.shared.fetchProfile(userId: userId) {
                let announcementText = "\(profile.name) left the conversation"
                _ = try? await sendSystemMessage(
                    conversationId: conversationId,
                    text: announcementText,
                    fromId: userId
                )
            }
        }
        
        AppLogger.database.info("User \(userId) successfully left conversation \(conversationId)")
    }
    
    /// Remove a participant from a conversation (admin/member action)
    /// - Parameters:
    ///   - conversationId: The conversation ID
    ///   - userId: The user ID to remove
    ///   - removedBy: The user performing the removal
    ///   - createAnnouncement: Whether to create a system message (default: true)
    /// - Throws: AppError if operation fails
    func removeParticipantFromConversation(
        conversationId: UUID,
        userId: UUID,
        removedBy: UUID,
        createAnnouncement: Bool = true
    ) async throws {
        AppLogger.database.info("Removing user \(userId) from conversation \(conversationId) by \(removedBy)")
        
        // Verify remover is a participant or creator
        let removerCheck = try? await supabase
            .from("conversation_participants")
            .select("user_id, left_at")
            .eq("conversation_id", value: conversationId.uuidString)
            .eq("user_id", value: removedBy.uuidString)
            .single()
            .execute()
        
        let conversationCheck = try? await supabase
            .from("conversations")
            .select("created_by")
            .eq("id", value: conversationId.uuidString)
            .single()
            .execute()
        
        struct CreatorInfo: Codable {
            let createdBy: UUID
            enum CodingKeys: String, CodingKey {
                case createdBy = "created_by"
            }
        }
        
        let isParticipant = removerCheck?.data.isEmpty == false
        var isCreator = false
        if let creatorData = conversationCheck?.data,
           let creatorInfo = try? JSONDecoder().decode(CreatorInfo.self, from: creatorData) {
            isCreator = creatorInfo.createdBy == removedBy
        }
        
        guard isParticipant || isCreator else {
            throw AppError.permissionDenied("You must be a participant to remove others")
        }
        
        // Verify target user is a participant and hasn't left
        let targetCheck = try? await supabase
            .from("conversation_participants")
            .select("user_id, left_at")
            .eq("conversation_id", value: conversationId.uuidString)
            .eq("user_id", value: userId.uuidString)
            .single()
            .execute()
        
        struct ParticipantStatus: Codable {
            let userId: UUID
            let leftAt: Date?
            enum CodingKeys: String, CodingKey {
                case userId = "user_id"
                case leftAt = "left_at"
            }
        }
        
        guard let targetData = targetCheck?.data,
              let targetStatus = try? createDateDecoder().decode(ParticipantStatus.self, from: targetData),
              targetStatus.leftAt == nil else {
            throw AppError.invalidInput("User is not an active participant")
        }
        
        // Update left_at timestamp
        let formatter = ISO8601DateFormatter()
        formatter.formatOptions = [.withInternetDateTime, .withFractionalSeconds]
        let now = formatter.string(from: Date())
        
        try await supabase
            .from("conversation_participants")
            .update(["left_at": now])
            .eq("conversation_id", value: conversationId.uuidString)
            .eq("user_id", value: userId.uuidString)
            .execute()
        
        // Create announcement message if requested
        if createAnnouncement {
            let removedProfile = try? await ProfileService.shared.fetchProfile(userId: userId)
            let removerProfile = try? await ProfileService.shared.fetchProfile(userId: removedBy)
            
            let removedName = removedProfile?.name ?? "A user"
            let removerName = removerProfile?.name ?? "Someone"
            
            let announcementText = "\(removerName) removed \(removedName) from the conversation"
            _ = try? await sendSystemMessage(
                conversationId: conversationId,
                text: announcementText,
                fromId: removedBy
            )
        }
        
        AppLogger.database.info("Successfully removed user \(userId) from conversation \(conversationId)")
    }
    
    /// Check if user has left a conversation
    /// - Parameters:
    ///   - conversationId: The conversation ID
    ///   - userId: The user ID to check
    /// - Returns: True if user has left, false if still active
    func hasUserLeftConversation(conversationId: UUID, userId: UUID) async -> Bool {
        let response = try? await supabase
            .from("conversation_participants")
            .select("left_at")
            .eq("conversation_id", value: conversationId.uuidString)
            .eq("user_id", value: userId.uuidString)
            .single()
            .execute()
        
        struct LeftStatus: Codable {
            let leftAt: Date?
            enum CodingKeys: String, CodingKey {
                case leftAt = "left_at"
            }
        }
        
        guard let data = response?.data,
              let status = try? createDateDecoder().decode(LeftStatus.self, from: data) else {
            return true // Not found = effectively left
        }
        
        return status.leftAt != nil
    }
    
    // MARK: - Permission Checking
    
    /// Check if a user has permission to modify participants in a conversation
    /// - Parameters:
    ///   - conversationId: The conversation ID
    ///   - userId: The user requesting to modify participants
    ///   - creatorId: The conversation creator's ID
    /// - Returns: True if the user can modify participants
    private func canModifyParticipants(
        conversationId: UUID,
        userId: UUID,
        creatorId: UUID
    ) async throws -> Bool {
        if creatorId == userId {
            AppLogger.info("messaging", "User is conversation creator, has permission")
            return true
        }
        
        AppLogger.info("messaging", "User is not creator, checking if they are a participant")
        let participantCheck = try? await supabase
            .from("conversation_participants")
            .select("user_id")
            .eq("conversation_id", value: conversationId.uuidString)
            .eq("user_id", value: userId.uuidString)
            .is("left_at", value: nil)
            .limit(1)
            .execute()
        
        if let data = participantCheck?.data, !data.isEmpty {
            AppLogger.info("messaging", "User is a participant, has permission")
            return true
        }
        
        AppLogger.error("messaging", "User is not a participant")
        return false
    }
    
    // MARK: - Private Helpers
    
    /// Send a system message (announcement)
    @discardableResult
    private func sendSystemMessage(
        conversationId: UUID,
        text: String,
        fromId: UUID
    ) async throws -> Message {
        let messageData: [String: AnyCodable] = [
            "conversation_id": AnyCodable(conversationId.uuidString),
            "from_id": AnyCodable(fromId.uuidString),
            "text": AnyCodable(text),
            "message_type": AnyCodable("system")
        ]
        
        let response = try await supabase
            .from("messages")
            .insert(messageData)
            .select()
            .single()
            .execute()
        
        let decoder = createDateDecoder()
        return try decoder.decode(Message.self, from: response.data)
    }
}
