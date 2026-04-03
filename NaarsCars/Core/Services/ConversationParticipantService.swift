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

        // Enforce 50-member cap
        let countResp = try await supabase
            .from("conversation_participants")
            .select("id", head: true, count: .exact)
            .eq("conversation_id", value: conversationId.uuidString)
            .is("left_at", value: nil)
            .execute()
        let currentActiveCount = countResp.count ?? 0
        if currentActiveCount + userIds.count > 50 {
            throw AppError.invalidInput("This group has reached the maximum of 50 participants.")
        }

        // Fetch all participant records for these users (including left ones)
        let existingResp = try await supabase
            .from("conversation_participants")
            .select("user_id, left_at")
            .eq("conversation_id", value: conversationId.uuidString)
            .in("user_id", values: userIds.map { $0.uuidString })
            .execute()

        struct ExistingRow: Codable {
            let userId: UUID
            let leftAt: Date?
            enum CodingKeys: String, CodingKey {
                case userId = "user_id"
                case leftAt = "left_at"
            }
        }
        let decoder = DateDecoderFactory.makeMessagingDecoder()
        let existing = (try? decoder.decode([ExistingRow].self, from: existingResp.data)) ?? []

        let activeUserIds = Set(existing.filter { $0.leftAt == nil }.map { $0.userId })
        let leftUserIds = Set(existing.filter { $0.leftAt != nil }.map { $0.userId })

        // Skip already-active members
        let newUserIds = userIds.filter { !activeUserIds.contains($0) }
        let readdUserIds = newUserIds.filter { leftUserIds.contains($0) }
        let freshUserIds = newUserIds.filter { !leftUserIds.contains($0) }

        AppLogger.info("messaging", "Existing active: \(activeUserIds.count), previously left (re-add): \(readdUserIds.count), fresh: \(freshUserIds.count)")

        guard !newUserIds.isEmpty else {
            AppLogger.info("messaging", "All users are already active participants, nothing to add")
            AppLogger.database.debug("All users are already participants")
            return
        }

        // Insert new participant records for both fresh and re-added users.
        // Re-added users get a new record with fresh joined_at; their old
        // soft-deleted record stays for history.
        let allInsertIds = freshUserIds + readdUserIds
        let inserts = allInsertIds.map { userId in
            [
                "conversation_id": AnyCodable(conversationId.uuidString),
                "user_id": AnyCodable(userId.uuidString),
                "added_by": AnyCodable(addedBy.uuidString)
            ]
        }

        AppLogger.info("messaging", "Inserting \(allInsertIds.count) new participant record(s)")
#if DEBUG
        AppLogger.database.debug("[Membership] addParticipants payload: conversationId=\(conversationId), freshUserIds=\(freshUserIds), readdUserIds=\(readdUserIds), addedBy=\(addedBy)")
#endif
        try await supabase
            .from("conversation_participants")
            .insert(inserts)
            .execute()
        AppLogger.info("messaging", "Successfully inserted participants")
#if DEBUG
        await logParticipantStateAfterAction(conversationId: conversationId, action: "add(\(allInsertIds))", currentUserId: addedBy)
#endif
        // Create announcement messages if requested
        if createAnnouncement {
            AppLogger.info("messaging", "Creating announcement messages")
            // Fresh adds
            for userId in freshUserIds {
                if let profile = try? await ProfileService.shared.fetchProfile(userId: userId) {
                    let announcementText = "\(profile.name) has been added to the conversation"
                    do {
                        _ = try await sendSystemMessage(
                            conversationId: conversationId,
                            text: announcementText,
                            fromId: addedBy
                        )
                    } catch {
                        AppLogger.database.warning("Failed to create announcement message: \(error.localizedDescription)")
                    }
                }
            }
            // Re-adds
            for userId in readdUserIds {
                if let profile = try? await ProfileService.shared.fetchProfile(userId: userId) {
                    let announcementText = "\(profile.name) has been added back to the conversation"
                    do {
                        _ = try await sendSystemMessage(
                            conversationId: conversationId,
                            text: announcementText,
                            fromId: addedBy
                        )
                    } catch {
                        AppLogger.database.warning("Failed to create re-add announcement message: \(error.localizedDescription)")
                    }
                }
            }
        }

        AppLogger.database.info("Added \(allInsertIds.count) participant(s) to conversation \(conversationId)")
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
        
        // Create announcement message BEFORE the RPC sets left_at (RLS requires left_at IS NULL for INSERT)
        if createAnnouncement {
            if let profile = try? await ProfileService.shared.fetchProfile(userId: userId) {
                let announcementText = "\(profile.name) left the conversation"
                do {
                    _ = try await sendSystemMessage(
                        conversationId: conversationId,
                        text: announcementText,
                        fromId: userId
                    )
                } catch {
                    AppLogger.error("messaging", "Failed to send leave announcement: \(error.localizedDescription)")
                    CrashReportingService.shared.recordServiceError(error, operation: "sendLeaveAnnouncement", service: "ConversationParticipantService")
                }
            }
        }

#if DEBUG
        AppLogger.database.debug("[Membership] leave_conversation RPC payload: conversationId=\(conversationId), userId=\(userId)")
#endif
        // Use SECURITY DEFINER RPC so the update succeeds (RLS only allows updating own row)
        let leaveResponse = try await supabase.rpc(
            "leave_conversation",
            params: [
                "p_conversation_id": conversationId.uuidString,
                "p_user_id": userId.uuidString
            ]
        ).execute()
#if DEBUG
        if let json = String(data: leaveResponse.data, encoding: .utf8) {
            AppLogger.database.debug("[Membership] leave_conversation response: \(json)")
        }
        await logParticipantStateAfterAction(conversationId: conversationId, action: "leave", currentUserId: userId)
#endif

        await MessagingRepository.shared.removeParticipantLocally(conversationId: conversationId, userId: userId)

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
        
        // Create announcement message BEFORE the RPC sets left_at (RLS requires left_at IS NULL for INSERT)
        if createAnnouncement {
            let removedProfile = try? await ProfileService.shared.fetchProfile(userId: userId)
            let removerProfile = try? await ProfileService.shared.fetchProfile(userId: removedBy)

            let removedName = removedProfile?.name ?? "A user"
            let removerName = removerProfile?.name ?? "Someone"

            let announcementText = "\(removerName) removed \(removedName) from the conversation"
            do {
                _ = try await sendSystemMessage(
                    conversationId: conversationId,
                    text: announcementText,
                    fromId: removedBy
                )
            } catch {
                AppLogger.error("messaging", "Failed to send remove announcement: \(error.localizedDescription)")
                CrashReportingService.shared.recordServiceError(error, operation: "sendRemoveAnnouncement", service: "ConversationParticipantService")
            }
        }

#if DEBUG
        AppLogger.database.debug("[Membership] remove_conversation_participant RPC payload: conversationId=\(conversationId), userId=\(userId), removedBy=\(removedBy)")
#endif
        // Use SECURITY DEFINER RPC; RLS only allows updating own row so direct UPDATE would affect 0 rows when removing another user
        let removeResponse = try await supabase.rpc(
            "remove_conversation_participant",
            params: [
                "p_conversation_id": conversationId.uuidString,
                "p_user_id": userId.uuidString,
                "p_removed_by": removedBy.uuidString
            ]
        ).execute()
#if DEBUG
        if let json = String(data: removeResponse.data, encoding: .utf8) {
            AppLogger.database.debug("[Membership] remove_conversation_participant response: \(json)")
        }
        await logParticipantStateAfterAction(conversationId: conversationId, action: "remove(\(userId))", currentUserId: removedBy)
#endif

        await MessagingRepository.shared.removeParticipantLocally(conversationId: conversationId, userId: userId)

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
            // Network failure or decode error — assume user is still active.
            // Returning true here would freeze the conversation UI on slow connections.
            return false
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
    
#if DEBUG
    /// Refetch participants from Supabase after remove/leave/add and log authoritative state (for debugging membership stickiness).
    private func logParticipantStateAfterAction(conversationId: UUID, action: String, currentUserId: UUID) async {
        do {
            let response = try await supabase
                .from("conversation_participants")
                .select("user_id, left_at")
                .eq("conversation_id", value: conversationId.uuidString)
                .execute()
            struct Row: Codable {
                let userId: UUID
                let leftAt: Date?
                enum CodingKeys: String, CodingKey {
                    case userId = "user_id"
                    case leftAt = "left_at"
                }
            }
            let decoder = createDateDecoder()
            let rows = (try? decoder.decode([Row].self, from: response.data)) ?? []
            let active = rows.filter { $0.leftAt == nil }.map { $0.userId }
            let left = rows.filter { $0.leftAt != nil }.map { $0.userId }
            let currentUserRow = rows.first { $0.userId == currentUserId }
            AppLogger.database.debug("[Membership] After \(action): active=\(active), left=\(left), currentUserLeftAt=\(currentUserRow?.leftAt?.description ?? "nil")")
        } catch {
            AppLogger.database.debug("[Membership] Refetch after \(action) failed: \(error.localizedDescription)")
        }
    }
#endif
    
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
