//
//  ConversationService.swift
//  NaarsCars
//
//  Service for conversation operations
//

import Foundation
import Supabase
import UIKit
import OSLog

/// Service for conversation operations
/// Handles creating, fetching, and managing conversations and participants
@MainActor
final class ConversationService {
    
    // MARK: - Singleton
    
    static let shared = ConversationService()
    
    // MARK: - Private Properties
    
    private let supabase = SupabaseService.shared.client
    
    // MARK: - Initialization
    
    private init() {}
    
    // MARK: - Private Helpers
    
    /// Create a date decoder with custom date decoding strategy
    private func createDateDecoder() -> JSONDecoder {
        DateDecoderFactory.makeMessagingDecoder()
    }
    
    // MARK: - Fetch Conversations
    
    /// Fetch conversations for a user with pagination
    /// - Parameters:
    ///   - userId: The user ID
    ///   - limit: Maximum number of conversations to fetch (default: 10)
    ///   - offset: Number of conversations to skip (for pagination)
    /// - Returns: Array of conversations with details
    /// - Throws: AppError if fetch fails
    func fetchConversations(userId: UUID, limit: Int = 10, offset: Int = 0) async throws -> [ConversationWithDetails] {
        do {
            do {
                let rpcConversations = try await fetchConversationsViaRpc(userId: userId, limit: limit, offset: offset)
                if !rpcConversations.isEmpty {
                    AppLogger.network.info("Fetched \(rpcConversations.count) conversations via RPC.")
                    return rpcConversations
                }
            } catch {
                AppLogger.network.error("RPC get_conversations_with_details failed: \(error)")
            }

            // Get user's conversation IDs from conversation_participants
            // (RLS is disabled on this table, so we can query it directly)
            // This query uses an index on user_id, so it's efficient even with many conversations
            let participantsResponse = try await supabase
                .from("conversation_participants")
                .select("conversation_id")
                .eq("user_id", value: userId.uuidString)
                .execute()
            
            struct ParticipantRow: Codable {
                let conversationId: UUID
                enum CodingKeys: String, CodingKey {
                    case conversationId = "conversation_id"
                }
            }
            
            let participantRows = try JSONDecoder().decode([ParticipantRow].self, from: participantsResponse.data)
            let participantConversationIds = Set(participantRows.map { $0.conversationId })
            
            // Get conversations where user is creator
            let createdConversationsResponse = try? await supabase
                .from("conversations")
                .select("id, created_by, title, group_image_url, is_archived, created_at, updated_at")
                .eq("created_by", value: userId.uuidString)
                .execute()
            
            var allConversationIds = participantConversationIds
            if let createdData = createdConversationsResponse?.data {
                let decoder = createDateDecoder()
                let created: [Conversation] = try decoder.decode([Conversation].self, from: createdData)
                allConversationIds.formUnion(created.map { $0.id })
            }
            
            guard !allConversationIds.isEmpty else { return [] }
            
            // Query conversations by IDs with ORDER BY first (chronological, latest first)
            // PostgreSQL optimizes IN clauses efficiently with indexes on id
            // IMPORTANT: Order BEFORE pagination to get latest conversations
            let conversationsResponse = try await supabase
                .from("conversations")
                .select("id, created_by, title, group_image_url, is_archived, created_at, updated_at")
                .in("id", values: Array(allConversationIds).map { $0.uuidString })
                .order("updated_at", ascending: false)
                .range(from: offset, to: offset + limit - 1)
                .execute()
            
            // Decode conversations with custom date decoder
            let decoder = createDateDecoder()
            let conversations: [Conversation] = try decoder.decode([Conversation].self, from: conversationsResponse.data)
            
            guard !conversations.isEmpty else { return [] }
            
            // Fetch details for all conversations in parallel to avoid N+1 query problem
            // This significantly improves performance when loading multiple conversations
            let conversationsWithDetails = await withTaskGroup(of: ConversationWithDetails?.self) { group in
                for conversation in conversations {
                    group.addTask { [supabase] in
                        await self.fetchConversationDetails(
                            conversation: conversation,
                            userId: userId,
                            supabase: supabase
                        )
                    }
                }
                
                var results: [ConversationWithDetails] = []
                for await result in group {
                    if let details = result {
                        results.append(details)
                    }
                }
                
                // Sort by updated_at (most recent first) to maintain order after parallel fetch
                return results.sorted { $0.conversation.updatedAt > $1.conversation.updatedAt }
            }
            
            AppLogger.network.info("Fetched \(conversationsWithDetails.count) conversations from network.")
            return conversationsWithDetails
            
        } catch {
            // Handle RLS recursion error gracefully
            let errorString = String(describing: error).lowercased()
            if errorString.contains("infinite recursion") || errorString.contains("recursion") {
                AppLogger.database.warning("RLS policy recursion detected. Returning empty conversations.")
                return []
            }
            // Re-throw other errors
            throw error
        }
    }
    
    /// Fetch details for a single conversation (last message, unread count, participants)
    /// Used by fetchConversations to parallelize queries
    /// - Parameters:
    ///   - conversation: The conversation to fetch details for
    ///   - userId: The current user ID
    ///   - supabase: The Supabase client
    /// - Returns: ConversationWithDetails or nil if fetch fails
    private func fetchConversationDetails(
        conversation: Conversation,
        userId: UUID,
        supabase: SupabaseClient
    ) async -> ConversationWithDetails? {
        // Fetch last message, unread count, and participants in parallel
        async let lastMessageTask = fetchLastMessage(conversationId: conversation.id, supabase: supabase)
        async let unreadCountTask = fetchUnreadCount(conversationId: conversation.id, userId: userId, supabase: supabase)
        async let participantsTask = fetchOtherParticipants(conversationId: conversation.id, userId: userId, supabase: supabase)
        
        let (lastMessage, unreadCount, otherParticipants) = await (lastMessageTask, unreadCountTask, participantsTask)
        
        return ConversationWithDetails(
            conversation: conversation,
            lastMessage: lastMessage,
            unreadCount: unreadCount,
            otherParticipants: otherParticipants
        )
    }
    
    /// Fetch the last message for a conversation
    private func fetchLastMessage(conversationId: UUID, supabase: SupabaseClient) async -> Message? {
        do {
            let response = try await supabase
                .from("messages")
                .select("*, sender:profiles!messages_from_id_fkey(*)")
                .eq("conversation_id", value: conversationId.uuidString)
                .order("created_at", ascending: false)
                .limit(1)
                .single()
                .execute()
            
            let decoder = createDateDecoder()
            return try? decoder.decode(Message.self, from: response.data)
        } catch {
            return nil
        }
    }
    
    /// Fetch unread message count for a conversation
    private func fetchUnreadCount(conversationId: UUID, userId: UUID, supabase: SupabaseClient) async -> Int {
        struct MessageId: Codable {
            let id: UUID
        }
        
        do {
            let response = try await supabase
                .from("messages")
                .select("id")
                .eq("conversation_id", value: conversationId.uuidString)
                .neq("from_id", value: userId.uuidString)
                .or(MessageService.unreadReadByFilter(userId: userId))
                .execute()
            
            let unreadMessages = try? JSONDecoder().decode([MessageId].self, from: response.data)
            return unreadMessages?.count ?? 0
        } catch {
            return 0
        }
    }
    
    /// Fetch other participants for a conversation (excluding current user)
    private func fetchOtherParticipants(conversationId: UUID, userId: UUID, supabase: SupabaseClient) async -> [Profile] {
        // Use two-step approach for reliability (avoid foreign key join issues)
        do {
            // Step 1: Get participant user IDs
            let participantsResponse = try await supabase
                .from("conversation_participants")
                .select("user_id")
                .eq("conversation_id", value: conversationId.uuidString)
                .neq("user_id", value: userId.uuidString)
                .is("left_at", value: nil) // Only active participants
                .execute()
            
            struct ParticipantUserId: Codable {
                let userId: UUID
                enum CodingKeys: String, CodingKey {
                    case userId = "user_id"
                }
            }
            
            let participantIds = try JSONDecoder().decode([ParticipantUserId].self, from: participantsResponse.data)
            
            guard !participantIds.isEmpty else { return [] }
            
            // Step 2: Fetch profiles for those user IDs
            let userIdStrings = participantIds.map { $0.userId.uuidString }
            let profilesResponse = try await supabase
                .from("profiles")
                .select("*")
                .in("id", values: userIdStrings)
                .execute()
            
            let decoder = createDateDecoder()
            return try decoder.decode([Profile].self, from: profilesResponse.data)
        } catch {
            AppLogger.error("messaging", "Error fetching participants for conversation \(conversationId): \(error.localizedDescription)")
            
            // Fallback: try old approach
            return await fetchParticipantsFallback(conversationId: conversationId, userId: userId, supabase: supabase)
        }
    }
    
    /// Fallback method to fetch participants when join fails
    private func fetchParticipantsFallback(conversationId: UUID, userId: UUID, supabase: SupabaseClient) async -> [Profile] {
        struct ParticipantUserId: Codable {
            let userId: UUID
            enum CodingKeys: String, CodingKey {
                case userId = "user_id"
            }
        }
        
        do {
            let response = try await supabase
                .from("conversation_participants")
                .select("user_id")
                .eq("conversation_id", value: conversationId.uuidString)
                .neq("user_id", value: userId.uuidString)
                .execute()
            
            let userIdRows = try JSONDecoder().decode([ParticipantUserId].self, from: response.data)
            
            // Fetch profiles in parallel
            return await withTaskGroup(of: Profile?.self) { group in
                for row in userIdRows {
                    group.addTask {
                        try? await ProfileService.shared.fetchProfile(userId: row.userId)
                    }
                }
                
                var profiles: [Profile] = []
                for await profile in group {
                    if let profile = profile {
                        profiles.append(profile)
                    }
                }
                return profiles
            }
        } catch {
            AppLogger.database.warning("Error in fallback participant fetch: \(error.localizedDescription)")
            return []
        }
    }
    
    // MARK: - Create & Find Conversations
    
    /// Get or create direct conversation between two users
    /// - Parameters:
    ///   - userId: First user ID
    ///   - otherUserId: Second user ID
    /// - Returns: Conversation
    /// - Throws: AppError if operation fails
    func getOrCreateDirectConversation(userId: UUID, otherUserId: UUID) async throws -> Conversation {
        if let existingConversationId = await findDirectConversationId(userId: userId, otherUserId: otherUserId) {
            if let conversation = try? await fetchConversationById(existingConversationId) {
                AppLogger.database.debug("Found existing DM conversation via RPC: \(conversation.id)")
                return conversation
            }
        }

        // Check for existing DM conversation by finding conversations where both users are participants
        // and the conversation has exactly 2 participants
        let participantsResponse = try? await supabase
            .from("conversation_participants")
            .select("conversation_id")
            .eq("user_id", value: userId.uuidString)
            .execute()
        
        struct ParticipantRow: Codable {
            let conversationId: UUID
            enum CodingKeys: String, CodingKey {
                case conversationId = "conversation_id"
            }
        }
        
        guard let participantData = participantsResponse?.data,
              let userConversations = try? JSONDecoder().decode([ParticipantRow].self, from: participantData) else {
            // No conversations found, create new one
            return try await createConversationWithUsers(userIds: [userId, otherUserId], createdBy: userId, title: nil)
        }
        
        // Check each conversation to see if it has both users as participants and exactly 2 participants
        for userConv in userConversations {
            let otherParticipantsResponse = try? await supabase
                .from("conversation_participants")
                .select("user_id")
                .eq("conversation_id", value: userConv.conversationId.uuidString)
                .execute()
            
            struct OtherParticipantRow: Codable {
                let userId: UUID
                enum CodingKeys: String, CodingKey {
                    case userId = "user_id"
                }
            }
            
            if let otherData = otherParticipantsResponse?.data,
               let otherParticipants = try? JSONDecoder().decode([OtherParticipantRow].self, from: otherData),
               otherParticipants.count == 2 {
                // Check if both users are in this conversation
                let participantIds = Set(otherParticipants.map { $0.userId })
                if participantIds.contains(userId) && participantIds.contains(otherUserId) {
                    // Found existing DM conversation
                    let conversationResponse = try? await supabase
                        .from("conversations")
                        .select("id, created_by, title, group_image_url, is_archived, created_at, updated_at")
                        .eq("id", value: userConv.conversationId.uuidString)
                        .single()
                        .execute()
                    
                    if let convData = conversationResponse?.data {
                        let decoder = createDateDecoder()
                        if let existing = try? decoder.decode(Conversation.self, from: convData) {
                            AppLogger.database.debug("Found existing DM conversation: \(existing.id)")
                            return existing
                        }
                    }
                }
            }
        }
        
        // No existing DM found, create new one
        return try await createConversationWithUsers(userIds: [userId, otherUserId], createdBy: userId, title: nil)
    }
    
    /// Create a conversation with specified users
    /// - Parameters:
    ///   - userIds: Array of user IDs to include in the conversation
    ///   - createdBy: User ID creating the conversation
    ///   - title: Optional title for group conversations
    /// - Returns: Created conversation
    /// - Throws: AppError if creation fails
    func createConversationWithUsers(userIds: [UUID], createdBy: UUID, title: String? = nil) async throws -> Conversation {
        guard !userIds.isEmpty else {
            throw AppError.invalidInput("Must provide at least one user ID")
        }
        
        // Create conversation - handle RLS recursion errors
        let conversation: Conversation
        do {
            var conversationData: [String: AnyCodable] = [
                "created_by": AnyCodable(createdBy.uuidString)
            ]
            if let title = title, !title.isEmpty {
                conversationData["title"] = AnyCodable(title)
            }
            
            let response = try await supabase
                .from("conversations")
                .insert(conversationData)
                .select()
                .single()
                .execute()
            
            // Use same date decoder as fetchConversations
            let decoder = createDateDecoder()
            conversation = try decoder.decode(Conversation.self, from: response.data)
        } catch {
            // Log the full error for debugging
            AppLogger.database.error("Error creating conversation: \(error.localizedDescription)")
            
            // Check if this is an RLS recursion error
            let errorString = String(describing: error).lowercased()
            if errorString.contains("infinite recursion") || errorString.contains("recursion") {
                AppLogger.database.error("RLS recursion detected when creating conversation.")
                // Re-throw as AppError for better user experience
                throw AppError.serverError("Cannot create conversation due to database policy issue. Please contact support.")
            }
            // Re-throw other errors
            throw error
        }
        
        // Add all users as participants
        let participantInserts = userIds.map { userId in
            [
                "conversation_id": AnyCodable(conversation.id.uuidString),
                "user_id": AnyCodable(userId.uuidString)
            ]
        }
        
        do {
            try await supabase
                .from("conversation_participants")
                .insert(participantInserts)
                .execute()
            AppLogger.database.info("Created conversation with \(userIds.count) participant(s)")
        } catch {
            // Handle RLS recursion error - check multiple error formats
            let errorString = String(describing: error).lowercased()
            if errorString.contains("infinite recursion") || errorString.contains("recursion") {
                AppLogger.database.warning("RLS policy recursion when creating participants.")
                // Still return the conversation - it was created successfully
                // Participants will need to be added after RLS policy is fixed
            } else {
                // For other errors, log but don't throw - conversation was created
                AppLogger.database.warning("Error adding participants: \(error.localizedDescription)")
            }
        }

        let allUserIds = Array(Set(userIds + [createdBy]))
        await invalidateConversationCaches(for: allUserIds)
        
        return conversation
    }
    
    // MARK: - Conversation Updates
    
    /// Update conversation title (for group conversations)
    /// - Parameters:
    ///   - conversationId: The conversation ID
    ///   - title: The new title (nil to clear)
    ///   - userId: The user ID making the update (must be a participant)
    /// - Throws: AppError if update fails
    func updateConversationTitle(conversationId: UUID, title: String?, userId: UUID) async throws {
        // Verify user is a participant
        let participantResponse = try? await supabase
            .from("conversation_participants")
            .select("user_id")
            .eq("conversation_id", value: conversationId.uuidString)
            .eq("user_id", value: userId.uuidString)
            .single()
            .execute()
        
        guard participantResponse != nil else {
            throw AppError.permissionDenied("You must be a participant to update the conversation title")
        }
        
        // Update the title
        let dateFormatter = ISO8601DateFormatter()
        dateFormatter.formatOptions = [.withInternetDateTime, .withFractionalSeconds]
        
        var updateDict: [String: AnyCodable] = [
            "updated_at": AnyCodable(dateFormatter.string(from: Date()))
        ]
        
        if let title = title, !title.isEmpty {
            updateDict["title"] = AnyCodable(title)
        } else {
            updateDict["title"] = AnyCodable(nil as String? as Any)
        }
        
        try await supabase
            .from("conversations")
            .update(updateDict)
            .eq("id", value: conversationId.uuidString)
            .execute()
        
        AppLogger.database.info("Updated conversation title")
    }
    
    /// Soft-delete a conversation for the current user.
    ///
    /// Rather than removing the conversation from the database (which would affect
    /// all participants), this hides the conversation locally for the current user
    /// by storing the conversation ID in UserDefaults.  Messages remain intact on
    /// the server so the other participant(s) are unaffected.
    ///
    /// - Parameter id: Conversation ID to hide
    /// - Throws: `AppError.notAuthenticated` if there is no logged-in user
    func deleteConversation(id: UUID) async throws {
        guard let userId = AuthService.shared.currentUserId else {
            throw AppError.notAuthenticated
        }
        hideConversationForUser(conversationId: id, userId: userId)
    }
    
    // MARK: - Soft Delete Helpers
    
    private static let hiddenConversationsKeyPrefix = "hiddenConversations_"
    
    /// UserDefaults key scoped to a specific user
    private func hiddenConversationsKey(for userId: UUID) -> String {
        Self.hiddenConversationsKeyPrefix + userId.uuidString
    }
    
    /// Hide a conversation for a specific user (soft-delete).
    /// The conversation is not deleted from the database — it is only hidden
    /// from this user's conversation list.
    func hideConversationForUser(conversationId: UUID, userId: UUID) {
        var hiddenIds = getHiddenConversationIds(for: userId)
        hiddenIds.insert(conversationId)
        let idsArray = hiddenIds.map { $0.uuidString }
        UserDefaults.standard.set(idsArray, forKey: hiddenConversationsKey(for: userId))
        AppLogger.database.info("Hid conversation \(conversationId) for user \(userId)")
    }
    
    /// Returns all conversation IDs that a user has soft-deleted (hidden).
    func getHiddenConversationIds(for userId: UUID) -> Set<UUID> {
        let key = hiddenConversationsKey(for: userId)
        guard let idsArray = UserDefaults.standard.array(forKey: key) as? [String] else {
            return []
        }
        return Set(idsArray.compactMap { UUID(uuidString: $0) })
    }
    
    /// Check whether a conversation is hidden for a user.
    func isConversationHidden(conversationId: UUID, for userId: UUID) -> Bool {
        getHiddenConversationIds(for: userId).contains(conversationId)
    }
    
    /// Unhide a previously soft-deleted conversation (e.g. when a new message
    /// arrives in it, so the user sees it again).
    func unhideConversationForUser(conversationId: UUID, userId: UUID) {
        var hiddenIds = getHiddenConversationIds(for: userId)
        guard hiddenIds.remove(conversationId) != nil else { return }
        let idsArray = hiddenIds.map { $0.uuidString }
        UserDefaults.standard.set(idsArray, forKey: hiddenConversationsKey(for: userId))
        AppLogger.database.info("Unhid conversation \(conversationId) for user \(userId)")
    }
    
    // MARK: - Group Image Management
    
    /// Upload a group image to storage
    /// - Parameters:
    ///   - imageData: The image data to upload
    ///   - conversationId: The conversation ID
    /// - Returns: Public URL of uploaded image
    /// - Throws: AppError if upload fails
    func uploadGroupImage(imageData: Data, conversationId: UUID) async throws -> String {
        // Compress image
        guard let uiImage = UIImage(data: imageData) else {
            throw AppError.invalidInput("Invalid image data")
        }
        
        guard let compressedData = await ImageCompressor.compressAsync(uiImage, preset: .avatar) else {
            throw AppError.processingError("Failed to compress image")
        }
        
        // Upload to group-images bucket
        let fileName = "\(conversationId.uuidString)/avatar_\(UUID().uuidString).jpg"
        
        try await supabase.storage
            .from("group-images")
            .upload(
                fileName,
                data: compressedData,
                options: FileOptions(contentType: "image/jpeg", upsert: true)
            )
        
        // Get public URL
        let publicUrl = try supabase.storage
            .from("group-images")
            .getPublicURL(path: fileName)
        
        AppLogger.database.info("Uploaded group image for conversation \(conversationId)")
        return publicUrl.absoluteString
    }
    
    /// Update the group image URL for a conversation
    /// - Parameters:
    ///   - conversationId: The conversation ID
    ///   - imageUrl: The new image URL (nil to remove)
    ///   - userId: The user making the update (must be a participant)
    /// - Throws: AppError if update fails
    func updateGroupImage(
        conversationId: UUID,
        imageUrl: String?,
        userId: UUID
    ) async throws {
        // Verify user is a participant
        let participantCheck = try? await supabase
            .from("conversation_participants")
            .select("user_id")
            .eq("conversation_id", value: conversationId.uuidString)
            .eq("user_id", value: userId.uuidString)
            .limit(1)
            .execute()
        
        guard participantCheck?.data.isEmpty == false else {
            throw AppError.permissionDenied("You must be a participant to update the group image")
        }
        
        // Update the group image URL
        let dateFormatter = ISO8601DateFormatter()
        dateFormatter.formatOptions = [.withInternetDateTime, .withFractionalSeconds]
        
        var updateDict: [String: AnyCodable] = [
            "updated_at": AnyCodable(dateFormatter.string(from: Date()))
        ]
        
        if let imageUrl = imageUrl {
            updateDict["group_image_url"] = AnyCodable(imageUrl)
        } else {
            updateDict["group_image_url"] = AnyCodable(nil as String? as Any)
        }
        
        try await supabase
            .from("conversations")
            .update(updateDict)
            .eq("id", value: conversationId.uuidString)
            .execute()
        
        // Create announcement
        if let profile = try? await ProfileService.shared.fetchProfile(userId: userId) {
            let announcementText = imageUrl != nil 
                ? "\(profile.name) updated the group photo"
                : "\(profile.name) removed the group photo"
            _ = try? await sendSystemMessage(
                conversationId: conversationId,
                text: announcementText,
                fromId: userId
            )
        }
        
        AppLogger.database.info("Updated group image for conversation \(conversationId)")
    }
    
    // MARK: - Cache Invalidation
    
    /// Invalidate conversation caches for a list of users
    func invalidateConversationCaches(for userIds: [UUID]) async {
        // Cache layer removed; keep no-op for callers.
        _ = userIds
    }
    
    // MARK: - Private Helpers
    
    private func fetchConversationsViaRpc(userId: UUID, limit: Int, offset: Int) async throws -> [ConversationWithDetails] {
        struct ConversationRpcRow: Codable {
            let conversationId: UUID
            let createdBy: UUID
            let title: String?
            let groupImageUrl: String?
            let isArchived: Bool?
            let createdAt: Date
            let updatedAt: Date
            let lastMessage: Message?
            let unreadCount: Int?
            let otherParticipants: [Profile]?

            enum CodingKeys: String, CodingKey {
                case conversationId = "conversation_id"
                case createdBy = "created_by"
                case title
                case groupImageUrl = "group_image_url"
                case isArchived = "is_archived"
                case createdAt = "created_at"
                case updatedAt = "updated_at"
                case lastMessage = "last_message"
                case unreadCount = "unread_count"
                case otherParticipants = "other_participants"
            }
        }

        let response = try await supabase.rpc(
            "get_conversations_with_details",
            params: [
                "p_user_id": AnyCodable(userId.uuidString),
                "p_limit": AnyCodable(limit),
                "p_offset": AnyCodable(offset)
            ]
        ).execute()

        let decoder = createDateDecoder()
        let rows = try decoder.decode([ConversationRpcRow].self, from: response.data)
        return rows.map { row in
            let conversation = Conversation(
                id: row.conversationId,
                title: row.title,
                groupImageUrl: row.groupImageUrl,
                createdBy: row.createdBy,
                isArchived: row.isArchived ?? false,
                createdAt: row.createdAt,
                updatedAt: row.updatedAt
            )
            return ConversationWithDetails(
                conversation: conversation,
                lastMessage: row.lastMessage,
                unreadCount: row.unreadCount ?? 0,
                otherParticipants: row.otherParticipants ?? []
            )
        }
    }

    private func fetchConversationById(_ conversationId: UUID) async throws -> Conversation? {
        let response = try await supabase
            .from("conversations")
            .select("id, created_by, title, group_image_url, is_archived, created_at, updated_at")
            .eq("id", value: conversationId.uuidString)
            .single()
            .execute()

        let decoder = createDateDecoder()
        return try decoder.decode(Conversation.self, from: response.data)
    }

    private func findDirectConversationId(userId: UUID, otherUserId: UUID) async -> UUID? {
        do {
            let response = try await supabase.rpc(
                "find_dm_conversation",
                params: [
                    "p_user_a": AnyCodable(userId.uuidString),
                    "p_user_b": AnyCodable(otherUserId.uuidString)
                ]
            ).execute()
            return decodeSingleUuid(from: response.data)
        } catch {
            return nil
        }
    }

    private func decodeSingleUuid(from data: Data) -> UUID? {
        if let id = try? JSONDecoder().decode(UUID.self, from: data) {
            return id
        }
        if let array = try? JSONDecoder().decode([UUID].self, from: data) {
            return array.first
        }
        if let dict = try? JSONDecoder().decode([String: UUID].self, from: data) {
            return dict.values.first
        }
        if let json = try? JSONSerialization.jsonObject(with: data) as? [Any] {
            for item in json {
                if let string = item as? String, let uuid = UUID(uuidString: string) {
                    return uuid
                }
                if let dict = item as? [String: Any],
                   let value = dict["conversation_id"] as? String,
                   let uuid = UUID(uuidString: value) {
                    return uuid
                }
            }
        }
        if let string = String(data: data, encoding: .utf8),
           let uuid = UUID(uuidString: string.trimmingCharacters(in: CharacterSet(charactersIn: "\""))) {
            return uuid
        }
        return nil
    }
    
    /// Send a system message (announcement)
    /// - Parameters:
    ///   - conversationId: The conversation ID
    ///   - text: The system message text
    ///   - fromId: The user ID associated with the action
    /// - Returns: The created message
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
