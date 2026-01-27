//
//  MessageService.swift
//  NaarsCars
//
//  Service for message and conversation operations
//

import Foundation
import Supabase
import UIKit
import OSLog

/// Service for message and conversation operations
/// Handles fetching, sending messages, and managing conversations
@MainActor
final class MessageService {
    
    // MARK: - Singleton
    
    static let shared = MessageService()
    
    // MARK: - Private Properties
    
    private let supabase = SupabaseService.shared.client
    private let rateLimiter = RateLimiter.shared
    
    // MARK: - Initialization
    
    private init() {}
    
    // MARK: - Conversations
    
    /// Fetch conversations for a user with pagination
    /// - Parameters:
    ///   - userId: The user ID
    ///   - limit: Maximum number of conversations to fetch (default: 10)
    ///   - offset: Number of conversations to skip (for pagination)
    /// - Returns: Array of conversations with details
    /// - Throws: AppError if fetch fails
    func fetchConversations(userId: UUID, limit: Int = 10, offset: Int = 0) async throws -> [ConversationWithDetails] {
        do {
            if let rpcConversations = try? await fetchConversationsViaRpc(userId: userId, limit: limit, offset: offset),
               !rpcConversations.isEmpty {
                AppLogger.network.info("Fetched \(rpcConversations.count) conversations via RPC.")
                return rpcConversations
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
                .not("read_by", operator: .cs, value: userId.uuidString)
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
            print("Error fetching participants for conversation \(conversationId): \(error.localizedDescription)")
            
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
        
        // Create new conversation
        let newConversation = Conversation(
            title: title,
            createdBy: createdBy
        )
        
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
        print("📥 [MessageService] addParticipantsToConversation called")
        print("   Conversation ID: \(conversationId)")
        print("   User IDs to add: \(userIds)")
        print("   Added by: \(addedBy)")
        print("   Create announcement: \(createAnnouncement)")
        
        guard !userIds.isEmpty else {
            print("⚠️ [MessageService] No user IDs provided, returning early")
            return
        }
        
        // Get conversation to check permissions
        print("🔍 [MessageService] Fetching conversation details...")
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
        print("✅ [MessageService] Conversation found, created by: \(conversationInfo.createdBy)")
        
        // Check if addedBy has permission to add participants
        // They can add if:
        // 1. They are the conversation creator, OR
        // 2. They are an existing participant
        var canAdd = false
        
        if conversationInfo.createdBy == addedBy {
            print("✅ [MessageService] User is conversation creator, has permission")
            canAdd = true
        } else {
            print("🔍 [MessageService] User is not creator, checking if they are a participant...")
            // Check if addedBy is a participant (using simple query that won't recurse)
            let participantCheck = try? await supabase
                .from("conversation_participants")
                .select("user_id")
                .eq("conversation_id", value: conversationId.uuidString)
                .eq("user_id", value: addedBy.uuidString)
                .is("left_at", value: nil)
                .limit(1)
                .execute()
            
            if let data = participantCheck?.data, !data.isEmpty {
                print("✅ [MessageService] User is a participant, has permission")
                canAdd = true
            } else {
                print("❌ [MessageService] User is not a participant")
            }
        }
        
        guard canAdd else {
            print("🔴 [MessageService] Permission denied: user cannot add participants")
            throw AppError.permissionDenied("You don't have permission to add participants to this conversation")
        }
        
        // Get existing participants to avoid duplicates
        // Use simple query that won't cause recursion (just check user_id = auth.uid())
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
        print("🔍 [MessageService] Existing participants: \(existingParticipants.count)")
        
        // Filter out users who are already participants
        let newUserIds = userIds.filter { !existingParticipants.contains($0) }
        print("🔍 [MessageService] New users to add (after filtering): \(newUserIds.count)")
        
        guard !newUserIds.isEmpty else {
            print("ℹ️ [MessageService] All users are already participants, nothing to add")
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
        
        print("📤 [MessageService] Inserting \(newUserIds.count) new participant(s)...")
        try await supabase
            .from("conversation_participants")
            .insert(inserts)
            .execute()
        print("✅ [MessageService] Successfully inserted participants")
        
        // Create announcement messages if requested
        if createAnnouncement {
            print("📢 [MessageService] Creating announcement messages...")
            // Get profile of added user(s) for announcement
            for userId in newUserIds {
                if let profile = try? await ProfileService.shared.fetchProfile(userId: userId) {
                    let announcementText = "\(profile.name) has been added to the conversation"
                    let announcement = Message(
                        conversationId: conversationId,
                        fromId: addedBy, // System message from the person who added
                        text: announcementText
                    )
                    
                    // Insert announcement message
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
    
    
    // MARK: - Private Helpers
    
    /// Create a date decoder with custom date decoding strategy
    private func createDateDecoder() -> JSONDecoder {
        let decoder = JSONDecoder()
        let formatter = ISO8601DateFormatter()
        formatter.formatOptions = [.withInternetDateTime, .withFractionalSeconds]
        
        decoder.dateDecodingStrategy = .custom { decoder in
            let container = try decoder.singleValueContainer()
            let dateString = try container.decode(String.self)
            
            if let date = formatter.date(from: dateString) {
                return date
            }
            
            formatter.formatOptions = [.withInternetDateTime]
            if let date = formatter.date(from: dateString) {
                return date
            }
            
            throw DecodingError.dataCorruptedError(
                in: container,
                debugDescription: "Invalid date format: \(dateString)"
            )
        }
        return decoder
    }

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
    
    // MARK: - Messages
    
    /// Fetch messages for a conversation
    /// - Parameter conversationId: The conversation ID
    /// - Returns: Array of messages ordered by createdAt
    /// - Throws: AppError if fetch fails
    /// Fetch messages for a conversation with pagination
    /// - Parameters:
    ///   - conversationId: The conversation ID
    ///   - limit: Maximum number of messages to fetch (default: 25)
    ///   - beforeMessageId: Optional message ID to fetch messages before (for pagination)
    /// - Returns: Array of messages ordered by creation date (oldest first)
    /// - Throws: AppError if fetch fails or user is not a participant
    func fetchMessages(conversationId: UUID, limit: Int = 25, beforeMessageId: UUID? = nil) async throws -> [Message] {
        // Security check: Verify user is a participant (RLS is disabled on conversation_participants)
        guard let currentUserId = AuthService.shared.currentUserId else {
            throw AppError.notAuthenticated
        }
        
        // Check if user is a participant or creator
        let participantCheck = try? await supabase
            .from("conversation_participants")
            .select("user_id")
            .eq("conversation_id", value: conversationId.uuidString)
            .eq("user_id", value: currentUserId.uuidString)
            .limit(1)
            .execute()
        
        let conversationCheck = try? await supabase
            .from("conversations")
            .select("created_by")
            .eq("id", value: conversationId.uuidString)
            .eq("created_by", value: currentUserId.uuidString)
            .limit(1)
            .execute()
        
        let hasParticipant = participantCheck?.data.isEmpty == false
        let isCreator = conversationCheck?.data.isEmpty == false
        let isParticipant = hasParticipant || isCreator
        
        guard isParticipant else {
            throw AppError.permissionDenied("You don't have permission to view messages in this conversation")
        }
        var query = supabase
            .from("messages")
            .select("*, sender:profiles!messages_from_id_fkey(*)")
            .eq("conversation_id", value: conversationId.uuidString)
        
        // If beforeMessageId is provided, fetch messages before that message
        if let beforeMessageId = beforeMessageId {
            // Get the created_at of the beforeMessageId message
            let beforeMessageResponse = try? await supabase
                .from("messages")
                .select("created_at")
                .eq("id", value: beforeMessageId.uuidString)
                .single()
                .execute()
            
            if let beforeData = beforeMessageResponse?.data {
                struct MessageDate: Codable {
                    let createdAt: Date
                    enum CodingKeys: String, CodingKey {
                        case createdAt = "created_at"
                    }
                }
                if let beforeMessage = try? createDateDecoder().decode(MessageDate.self, from: beforeData) {
                    // Fetch messages created before this date (for pagination - older messages)
                    let formatter = ISO8601DateFormatter()
                    formatter.formatOptions = [.withInternetDateTime, .withFractionalSeconds]
                    query = query.lt("created_at", value: formatter.string(from: beforeMessage.createdAt))
                }
            }
        }
        
        // Order by created_at descending (newest first), then reverse for display
        // When beforeMessageId is provided, we want older messages (created_at < beforeMessage.created_at)
        // For initial load, get the most recent messages
        let response = try await query
            .order("created_at", ascending: false)
            .limit(limit)
            .execute()
        
        let decoder = createDateDecoder()
        var messages: [Message] = try decoder.decode([Message].self, from: response.data)
        
        // Reverse to get oldest first (for display - newest at bottom)
        messages.reverse()
        
        // Fetch reactions for messages
        let messageIds = messages.map { $0.id.uuidString }
        if !messageIds.isEmpty {
            let reactionsResponse = try? await supabase
                .from("message_reactions")
                .select()
                .in("message_id", values: messageIds)
                .execute()
            
            if let reactionsData = reactionsResponse?.data {
                let reactions: [MessageReaction] = (try? decoder.decode([MessageReaction].self, from: reactionsData)) ?? []
                
                // Group reactions by message ID
                var reactionsDict: [UUID: [String: [UUID]]] = [:]
                for reaction in reactions {
                    if reactionsDict[reaction.messageId] == nil {
                        reactionsDict[reaction.messageId] = [:]
                    }
                    if reactionsDict[reaction.messageId]?[reaction.reaction] == nil {
                        reactionsDict[reaction.messageId]?[reaction.reaction] = []
                    }
                    reactionsDict[reaction.messageId]?[reaction.reaction]?.append(reaction.userId)
                }
                
                // Attach reactions to messages
                for i in 0..<messages.count {
                    if let reactionDict = reactionsDict[messages[i].id] {
                        messages[i].reactions = MessageReactions(reactions: reactionDict)
                    }
                }
            }
        }
        
        // Populate reply contexts (if any)
        let replyIds = Array(Set(messages.compactMap { $0.replyToId }))
        if !replyIds.isEmpty {
            if let replyContexts = try? await fetchReplyContexts(for: replyIds) {
                for index in messages.indices {
                    if let replyId = messages[index].replyToId,
                       let context = replyContexts[replyId] {
                        messages[index].replyToMessage = context
                    }
                }
            }
        }
        
        // Cache results (only cache if this is the initial load, not pagination)
        AppLogger.network.info("Fetched \(messages.count) messages from network.")
        return messages
    }

    /// Fetch reply contexts for a set of message IDs
    private func fetchReplyContexts(for messageIds: [UUID]) async throws -> [UUID: ReplyContext] {
        guard !messageIds.isEmpty else { return [:] }
        
        let response = try await supabase
            .from("messages")
            .select("id, text, from_id, image_url, sender:profiles!messages_from_id_fkey(*)")
            .in("id", values: messageIds.map { $0.uuidString })
            .execute()

        struct ReplyRow: Codable {
            let id: UUID
            let text: String
            let fromId: UUID
            let imageUrl: String?
            let sender: Profile?
            
            enum CodingKeys: String, CodingKey {
                case id
                case text
                case fromId = "from_id"
                case imageUrl = "image_url"
                case sender
            }
        }
        
        let replyRows: [ReplyRow] = try JSONDecoder().decode([ReplyRow].self, from: response.data)
        var contexts: [UUID: ReplyContext] = [:]
        for row in replyRows {
            contexts[row.id] = ReplyContext(
                id: row.id,
                text: row.text,
                senderName: row.sender?.name ?? "Unknown",
                senderId: row.fromId,
                imageUrl: row.imageUrl
            )
        }
        
        return contexts
    }

    /// Fetch a single message by ID with sender join (for realtime enrichment)
    func fetchMessageById(_ messageId: UUID) async throws -> Message {
        let response = try await supabase
            .from("messages")
            .select("*, sender:profiles!messages_from_id_fkey(*)")
            .eq("id", value: messageId.uuidString)
            .single()
            .execute()
        
        let decoder = createDateDecoder()
        var message = try decoder.decode(Message.self, from: response.data)
        
        if let replyId = message.replyToId {
            if let replyContext = try? await fetchReplyContexts(for: [replyId])[replyId] {
                message.replyToMessage = replyContext
            }
        }
        
        return message
    }
    
    /// Upload message image to storage
    /// - Parameters:
    ///   - imageData: The image data to upload
    ///   - conversationId: The conversation ID
    ///   - fromId: The sender's user ID
    /// - Returns: Public URL of uploaded image
    /// - Throws: AppError if upload fails
    func uploadMessageImage(imageData: Data, conversationId: UUID, fromId: UUID) async throws -> String {
        // Compress image using messageImage preset
        guard let uiImage = UIImage(data: imageData) else {
            throw AppError.invalidInput("Invalid image data")
        }
        
        guard let compressedData = await ImageCompressor.compressAsync(uiImage, preset: .messageImage) else {
            throw AppError.processingError("Failed to compress image")
        }
        
        // Upload to message-images bucket
        // Store in a folder per conversation for better organization
        let fileName = "\(conversationId.uuidString)/\(UUID().uuidString).jpg"
        
        try await supabase.storage
            .from("message-images")
            .upload(
                path: fileName,
                file: compressedData,
                options: FileOptions(contentType: "image/jpeg", upsert: false)
            )
        
        // Get public URL
        let publicUrl = try supabase.storage
            .from("message-images")
            .getPublicURL(path: fileName)
        
        print("📸 [MessageService] Uploaded image, public URL: \(publicUrl.absoluteString)")
        return publicUrl.absoluteString
    }
    
    /// Upload audio message to storage
    /// - Parameters:
    ///   - audioData: The audio file data
    ///   - conversationId: The conversation ID
    ///   - fromId: The sender user ID
    /// - Returns: Public URL of uploaded audio
    func uploadAudioMessage(audioData: Data, conversationId: UUID, fromId: UUID) async throws -> String {
        // Upload to audio-messages bucket
        let fileName = "\(conversationId.uuidString)/\(UUID().uuidString).m4a"
        
        try await supabase.storage
            .from("audio-messages")
            .upload(
                path: fileName,
                file: audioData,
                options: FileOptions(contentType: "audio/m4a", upsert: false)
            )
        
        // Get public URL
        let publicUrl = try await supabase.storage
            .from("audio-messages")
            .getPublicURL(path: fileName)
        
        return publicUrl.absoluteString
    }
    
    /// Send an audio message
    /// - Parameters:
    ///   - conversationId: The conversation ID
    ///   - fromId: The sender user ID
    ///   - audioUrl: The uploaded audio URL
    ///   - duration: Audio duration in seconds
    ///   - replyToId: Optional message ID being replied to
    /// - Returns: The created message
    func sendAudioMessage(conversationId: UUID, fromId: UUID, audioUrl: String, duration: Double, replyToId: UUID? = nil) async throws -> Message {
        let newMessage = Message(
            conversationId: conversationId,
            fromId: fromId,
            text: "",
            messageType: .audio,
            replyToId: replyToId,
            audioUrl: audioUrl,
            audioDuration: duration
        )
        
        let response = try await supabase
            .from("messages")
            .insert(newMessage)
            .select("*, sender:profiles!messages_from_id_fkey(*)")
            .single()
            .execute()
        
        let decoder = createDateDecoder()
        let message = try decoder.decode(Message.self, from: response.data)
        
        // Update conversation timestamp
        try await supabase
            .from("conversations")
            .update(["updated_at": ISO8601DateFormatter().string(from: Date())])
            .eq("id", value: conversationId.uuidString)
            .execute()
        
        AppLogger.database.info("Sent audio message: \(message.id)")
        return message
    }
    
    /// Send a location message
    /// - Parameters:
    ///   - conversationId: The conversation ID
    ///   - fromId: The sender user ID
    ///   - latitude: Location latitude
    ///   - longitude: Location longitude
    ///   - locationName: Human-readable location name/address
    ///   - replyToId: Optional message ID being replied to
    /// - Returns: The created message
    func sendLocationMessage(conversationId: UUID, fromId: UUID, latitude: Double, longitude: Double, locationName: String?, replyToId: UUID? = nil) async throws -> Message {
        let newMessage = Message(
            conversationId: conversationId,
            fromId: fromId,
            text: locationName ?? "Shared location",
            messageType: .location,
            replyToId: replyToId,
            latitude: latitude,
            longitude: longitude,
            locationName: locationName
        )
        
        let response = try await supabase
            .from("messages")
            .insert(newMessage)
            .select("*, sender:profiles!messages_from_id_fkey(*)")
            .single()
            .execute()
        
        let decoder = createDateDecoder()
        let message = try decoder.decode(Message.self, from: response.data)
        
        // Update conversation timestamp
        try await supabase
            .from("conversations")
            .update(["updated_at": ISO8601DateFormatter().string(from: Date())])
            .eq("id", value: conversationId.uuidString)
            .execute()
        
        AppLogger.database.info("Sent location message: \(message.id)")
        return message
    }
    
    /// Send a message
    /// - Parameters:
    ///   - conversationId: The conversation ID
    ///   - fromId: The sender's user ID
    ///   - text: The message text
    ///   - imageUrl: Optional image URL (if message includes an image)
    /// - Returns: The created message
    /// - Throws: AppError if send fails
    func sendMessage(conversationId: UUID, fromId: UUID, text: String, imageUrl: String? = nil, replyToId: UUID? = nil) async throws -> Message {
        // Security check: Verify user is a participant (RLS is disabled on conversation_participants)
        let participantCheck = try? await supabase
            .from("conversation_participants")
            .select("user_id")
            .eq("conversation_id", value: conversationId.uuidString)
            .eq("user_id", value: fromId.uuidString)
            .limit(1)
            .execute()
        
        let conversationCheck = try? await supabase
            .from("conversations")
            .select("created_by")
            .eq("id", value: conversationId.uuidString)
            .eq("created_by", value: fromId.uuidString)
            .limit(1)
            .execute()
        
        let hasParticipant = participantCheck?.data.isEmpty == false
        let isCreator = conversationCheck?.data.isEmpty == false
        let isParticipant = hasParticipant || isCreator
        
        guard isParticipant else {
            throw AppError.permissionDenied("You don't have permission to send messages in this conversation")
        }
        
        // Check rate limit (1 second between messages)
        let rateLimitKey = "send_message_\(fromId.uuidString)"
        let canProceed = await rateLimiter.checkAndRecord(
            action: rateLimitKey,
            minimumInterval: 1.0
        )
        
        guard canProceed else {
            throw AppError.rateLimitExceeded("Please wait before sending another message")
        }
        
        let newMessage = Message(
            conversationId: conversationId,
            fromId: fromId,
            text: text,
            imageUrl: imageUrl,
            replyToId: replyToId
        )
        
        let response = try await supabase
            .from("messages")
            .insert(newMessage)
            .select("*, sender:profiles!messages_from_id_fkey(*), reply_to_id")
            .single()
            .execute()
        
        // Decode message with joined sender profile
        let decoder = createDateDecoder()
        let message: Message
        do {
            message = try decoder.decode(Message.self, from: response.data)
        } catch {
            // Log the raw response for debugging
            if let jsonString = String(data: response.data, encoding: .utf8) {
                AppLogger.database.error("Failed to decode message. Raw JSON: \(jsonString.prefix(200))")
            }
            AppLogger.database.error("Decoding error: \(error)")
            // Try decoding again (might work if error was transient)
            message = try decoder.decode(Message.self, from: response.data)
        }
        
        // Update conversation updated_at
        try await supabase
            .from("conversations")
            .update(["updated_at": ISO8601DateFormatter().string(from: Date())])
            .eq("id", value: conversationId.uuidString)
            .execute()
        
        AppLogger.database.info("Sent message: \(message.id)")
        return message
    }
    
    /// Mark messages as read
    /// - Parameters:
    ///   - conversationId: The conversation ID
    ///   - userId: The user ID marking as read
    /// - Throws: AppError if update fails
    func markAsRead(conversationId: UUID, userId: UUID) async throws {
        // Get all unread messages
        let unreadResponse = try await supabase
            .from("messages")
            .select("id, read_by")
            .eq("conversation_id", value: conversationId.uuidString)
            .not("read_by", operator: .cs, value: userId.uuidString)
            .execute()
        
        struct MessageReadBy: Codable {
            let id: UUID
            let readBy: [UUID]
            
            enum CodingKeys: String, CodingKey {
                case id
                case readBy = "read_by"
            }
        }
        
        let unreadMessages: [MessageReadBy] = try JSONDecoder().decode([MessageReadBy].self, from: unreadResponse.data)
        
        if !unreadMessages.isEmpty {
            let messageIds = unreadMessages.map { $0.id.uuidString }
            do {
                try await supabase.rpc(
                    "mark_messages_read_batch",
                    params: [
                        "p_message_ids": AnyCodable(messageIds),
                        "p_user_id": AnyCodable(userId.uuidString)
                    ]
                ).execute()
            } catch {
                for message in unreadMessages {
                    var updatedReadBy = message.readBy
                    if !updatedReadBy.contains(userId) {
                        updatedReadBy.append(userId)
                    }
                    
                    try await supabase
                        .from("messages")
                        .update(["read_by": updatedReadBy.map { $0.uuidString }])
                        .eq("id", value: message.id.uuidString)
                        .execute()
                }
            }

        }
        
        // Update last_seen timestamp to indicate user is actively viewing
        // This prevents push notifications when user is viewing the conversation
        try? await updateLastSeen(conversationId: conversationId, userId: userId)
        
        AppLogger.database.debug("Marked \(unreadMessages.count) messages as read for conversation \(conversationId)")
    }
    
    /// Update last_seen timestamp for a user in a conversation
    /// This is used to prevent push notifications when user is actively viewing
    /// - Parameters:
    ///   - conversationId: The conversation ID
    ///   - userId: The user ID
    /// - Throws: AppError if update fails
    func updateLastSeen(conversationId: UUID, userId: UUID) async throws {
        let formatter = ISO8601DateFormatter()
        formatter.formatOptions = [.withInternetDateTime, .withFractionalSeconds]
        let now = formatter.string(from: Date())
        
        try await supabase
            .from("conversation_participants")
            .update(["last_seen": now])
            .eq("conversation_id", value: conversationId.uuidString)
            .eq("user_id", value: userId.uuidString)
            .execute()
        
        AppLogger.database.debug("Updated last_seen for user \(userId) in conversation \(conversationId)")
    }
    
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
            updateDict["title"] = AnyCodable(nil as String?)
        }
        
        try await supabase
            .from("conversations")
            .update(updateDict)
            .eq("id", value: conversationId.uuidString)
            .execute()
        
        AppLogger.database.info("Updated conversation title")
    }
    
    // MARK: - Message Reactions
    
    /// Add a reaction to a message
    /// - Parameters:
    ///   - messageId: The message ID
    ///   - userId: The user ID adding the reaction
    ///   - reaction: The reaction emoji/text (👍 👎 ❤️ 😂 ‼️ or "HaHa")
    /// - Throws: AppError if operation fails
    func addReaction(messageId: UUID, userId: UUID, reaction: String) async throws {
        // Validate reaction
        guard MessageReaction.validReactions.contains(reaction) else {
            throw AppError.invalidInput("Invalid reaction. Must be one of: \(MessageReaction.validReactions.joined(separator: ", "))")
        }
        
        // Check if user is a participant in the conversation
        let messageResponse = try await supabase
            .from("messages")
            .select("conversation_id")
            .eq("id", value: messageId.uuidString)
            .single()
            .execute()
        
        struct MessageConversation: Codable {
            let conversationId: UUID
            enum CodingKeys: String, CodingKey {
                case conversationId = "conversation_id"
            }
        }
        
        let messageConv = try JSONDecoder().decode(MessageConversation.self, from: messageResponse.data)
        
        // Check if user is a participant
        let participantCheck = try? await supabase
            .from("conversation_participants")
            .select("user_id")
            .eq("conversation_id", value: messageConv.conversationId.uuidString)
            .eq("user_id", value: userId.uuidString)
            .limit(1)
            .execute()
        
        guard participantCheck?.data.isEmpty == false else {
            throw AppError.permissionDenied("You must be a participant to react to messages")
        }
        
        // Insert or update reaction (upsert)
        let reactionData: [String: AnyCodable] = [
            "message_id": AnyCodable(messageId.uuidString),
            "user_id": AnyCodable(userId.uuidString),
            "reaction": AnyCodable(reaction)
        ]
        
        try await supabase
            .from("message_reactions")
            .upsert(reactionData, onConflict: "message_id,user_id")
            .execute()
        
        AppLogger.database.debug("Added reaction \(reaction) to message \(messageId)")
    }
    
    /// Remove a reaction from a message
    /// - Parameters:
    ///   - messageId: The message ID
    ///   - userId: The user ID removing the reaction
    /// - Throws: AppError if operation fails
    func removeReaction(messageId: UUID, userId: UUID) async throws {
        // Get conversation ID for cache invalidation
        let messageResponse = try? await supabase
            .from("messages")
            .select("conversation_id")
            .eq("id", value: messageId.uuidString)
            .single()
            .execute()
        
        struct MessageConversation: Codable {
            let conversationId: UUID
            enum CodingKeys: String, CodingKey {
                case conversationId = "conversation_id"
            }
        }
        
        let conversationId: UUID?
        if let messageData = messageResponse?.data,
           let messageConv = try? JSONDecoder().decode(MessageConversation.self, from: messageData) {
            conversationId = messageConv.conversationId
        } else {
            conversationId = nil
        }
        
        // Delete reaction
        try await supabase
            .from("message_reactions")
            .delete()
            .eq("message_id", value: messageId.uuidString)
            .eq("user_id", value: userId.uuidString)
            .execute()
        
        AppLogger.database.debug("Removed reaction from message \(messageId)")
    }
    
    /// Fetch reactions for a message
    /// - Parameter messageId: The message ID
    /// - Returns: MessageReactions object with all reactions
    /// - Throws: AppError if fetch fails
    func fetchReactions(messageId: UUID) async throws -> MessageReactions {
        let response = try await supabase
            .from("message_reactions")
            .select()
            .eq("message_id", value: messageId.uuidString)
            .execute()
        
        let decoder = createDateDecoder()
        let reactions: [MessageReaction] = try decoder.decode([MessageReaction].self, from: response.data)
        
        // Group reactions by reaction type
        var reactionsDict: [String: [UUID]] = [:]
        for reaction in reactions {
            if reactionsDict[reaction.reaction] == nil {
                reactionsDict[reaction.reaction] = []
            }
            reactionsDict[reaction.reaction]?.append(reaction.userId)
        }
        
        let groupedReactions = MessageReactions(reactions: reactionsDict)
        
        return groupedReactions
    }
    
    // MARK: - Group Management

    /// Delete a conversation (creator or admin)
    /// - Parameter id: Conversation ID to delete
    func deleteConversation(id: UUID) async throws {
        // Attempt delete; database should cascade to messages/participants if configured.
        try await supabase
            .from("conversations")
            .delete()
            .eq("id", value: id.uuidString)
            .execute()

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
                try? await sendSystemMessage(
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
            try? await sendSystemMessage(
                conversationId: conversationId,
                text: announcementText,
                fromId: removedBy
            )
        }
        
        AppLogger.database.info("Successfully removed user \(userId) from conversation \(conversationId)")
    }
    
    /// Send a system message (announcement)
    /// - Parameters:
    ///   - conversationId: The conversation ID
    ///   - text: The system message text
    ///   - fromId: The user ID associated with the action
    /// - Returns: The created message
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

    /// Invalidate conversation caches for a list of users
    func invalidateConversationCaches(for userIds: [UUID]) async {
        // Cache layer removed; keep no-op for callers.
        _ = userIds
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
                path: fileName,
                file: compressedData,
                options: FileOptions(contentType: "image/jpeg", upsert: true)
            )
        
        // Get public URL
        let publicUrl = try await supabase.storage
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
            updateDict["group_image_url"] = AnyCodable(nil as String?)
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
            try? await sendSystemMessage(
                conversationId: conversationId,
                text: announcementText,
                fromId: userId
            )
        }
        
        AppLogger.database.info("Updated group image for conversation \(conversationId)")
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
    
    // MARK: - Reporting
    
    /// Report type enum
    enum ReportType: String {
        case spam
        case harassment
        case inappropriateContent = "inappropriate_content"
        case scam
        case other
    }
    
    /// Submit a report for a user
    func reportUser(reporterId: UUID, reportedUserId: UUID, type: ReportType, description: String?) async throws {
        try await supabase.rpc(
            "submit_report",
            params: [
                "p_reporter_id": reporterId.uuidString,
                "p_reported_user_id": reportedUserId.uuidString,
                "p_report_type": type.rawValue,
                "p_description": description ?? ""
            ]
        ).execute()
        
        AppLogger.database.info("Reported user: \(reportedUserId)")
    }
    
    /// Submit a report for a message
    func reportMessage(reporterId: UUID, messageId: UUID, type: ReportType, description: String?) async throws {
        try await supabase.rpc(
            "submit_report",
            params: [
                "p_reporter_id": reporterId.uuidString,
                "p_reported_message_id": messageId.uuidString,
                "p_report_type": type.rawValue,
                "p_description": description ?? ""
            ]
        ).execute()
        
        AppLogger.database.info("Reported message: \(messageId)")
    }
    
    // MARK: - Blocking
    
    /// Block a user
    func blockUser(blockerId: UUID, blockedId: UUID, reason: String?) async throws {
        try await supabase.rpc(
            "block_user",
            params: [
                "p_blocker_id": blockerId.uuidString,
                "p_blocked_id": blockedId.uuidString,
                "p_reason": reason ?? ""
            ]
        ).execute()
        
        AppLogger.database.info("Blocked user: \(blockedId)")
    }
    
    /// Unblock a user
    func unblockUser(blockerId: UUID, blockedId: UUID) async throws {
        try await supabase.rpc(
            "unblock_user",
            params: [
                "p_blocker_id": blockerId.uuidString,
                "p_blocked_id": blockedId.uuidString
            ]
        ).execute()
        
        AppLogger.database.info("Unblocked user: \(blockedId)")
    }
    
    /// Check if a user is blocked
    func isUserBlocked(userId: UUID, otherUserId: UUID) async throws -> Bool {
        struct BlockedResult: Codable {
            let result: Bool
            
            enum CodingKeys: String, CodingKey {
                case result = "is_user_blocked"
            }
        }
        
        let response = try await supabase.rpc(
            "is_user_blocked",
            params: [
                "p_user_id": userId.uuidString,
                "p_other_user_id": otherUserId.uuidString
            ]
        ).execute()
        
        let decoder = JSONDecoder()
        if let result = try? decoder.decode(Bool.self, from: response.data) {
            return result
        }
        return false
    }
    
    /// Get list of blocked users
    func getBlockedUsers(userId: UUID) async throws -> [BlockedUser] {
        let response = try await supabase.rpc(
            "get_blocked_users",
            params: ["p_user_id": userId.uuidString]
        ).execute()
        
        let decoder = JSONDecoder()
        decoder.keyDecodingStrategy = .convertFromSnakeCase
        decoder.dateDecodingStrategy = .iso8601
        
        return try decoder.decode([BlockedUser].self, from: response.data)
    }
    
    // MARK: - Typing Indicators
    
    /// Set typing status for current user in a conversation
    /// - Parameters:
    ///   - conversationId: The conversation ID
    ///   - userId: The user ID
    func setTypingStatus(conversationId: UUID, userId: UUID) async {
        do {
            // Use upsert to update or insert typing indicator
            try await supabase
                .from("typing_indicators")
                .upsert([
                    "conversation_id": conversationId.uuidString,
                    "user_id": userId.uuidString,
                    "started_at": ISO8601DateFormatter().string(from: Date())
                ], onConflict: "conversation_id,user_id")
                .execute()
        } catch {
            // Typing indicator failures are non-critical, just log
            AppLogger.database.debug("Failed to set typing status: \(error.localizedDescription)")
        }
    }
    
    /// Clear typing status for current user in a conversation
    /// - Parameters:
    ///   - conversationId: The conversation ID
    ///   - userId: The user ID
    func clearTypingStatus(conversationId: UUID, userId: UUID) async {
        do {
            try await supabase
                .from("typing_indicators")
                .delete()
                .eq("conversation_id", value: conversationId.uuidString)
                .eq("user_id", value: userId.uuidString)
                .execute()
        } catch {
            // Typing indicator failures are non-critical, just log
            AppLogger.database.debug("Failed to clear typing status: \(error.localizedDescription)")
        }
    }
    
    /// Fetch currently typing users in a conversation
    /// - Parameter conversationId: The conversation ID
    /// - Returns: Array of typing users (excluding current user)
    func fetchTypingUsers(conversationId: UUID) async -> [TypingUser] {
        guard let currentUserId = AuthService.shared.currentUserId else { return [] }
        
        do {
            // Step 1: Fetch typing user IDs (no foreign key join - more reliable)
            let response = try await supabase
                .from("typing_indicators")
                .select("user_id, started_at")
                .eq("conversation_id", value: conversationId.uuidString)
                .neq("user_id", value: currentUserId.uuidString)
                .gte("started_at", value: ISO8601DateFormatter().string(from: Date().addingTimeInterval(-5)))
                .execute()
            
            struct TypingRow: Codable {
                let userId: UUID
                let startedAt: Date
                
                enum CodingKeys: String, CodingKey {
                    case userId = "user_id"
                    case startedAt = "started_at"
                }
            }
            
            let rows = try createDateDecoder().decode([TypingRow].self, from: response.data)
            
            guard !rows.isEmpty else { return [] }
            
            // Step 2: Fetch profiles for those user IDs
            let userIds = rows.map { $0.userId.uuidString }
            let profilesResponse = try await supabase
                .from("profiles")
                .select("id, name, avatar_url")
                .in("id", values: userIds)
                .execute()
            
            struct ProfileData: Codable {
                let id: UUID
                let name: String
                let avatarUrl: String?
                
                enum CodingKeys: String, CodingKey {
                    case id, name
                    case avatarUrl = "avatar_url"
                }
            }
            
            let profiles = try JSONDecoder().decode([ProfileData].self, from: profilesResponse.data)
            return profiles.map { TypingUser(id: $0.id, name: $0.name, avatarUrl: $0.avatarUrl) }
        } catch {
            // Silently fail - typing indicators are non-critical
            return []
        }
    }
}
