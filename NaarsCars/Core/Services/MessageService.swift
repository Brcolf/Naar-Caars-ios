//
//  MessageService.swift
//  NaarsCars
//
//  Service for message and conversation operations
//

import Foundation
import Supabase
import UIKit

/// Service for message and conversation operations
/// Handles fetching, sending messages, and managing conversations
@MainActor
final class MessageService {
    
    // MARK: - Singleton
    
    static let shared = MessageService()
    
    // MARK: - Private Properties
    
    private let supabase = SupabaseService.shared.client
    private let cacheManager = CacheManager.shared
    private let rateLimiter = RateLimiter.shared
    private let logger = MessagingLogger.shared
    
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
        let operationId = "fetchConversations_\(userId)_\(offset)"
        await logger.startOperation(operationId, description: "Fetch conversations (limit: \(limit), offset: \(offset))")
        
        // Check for cancellation before starting
        do {
            try Task.checkCancellation()
        } catch {
            await logger.endOperation(operationId, success: false, resultDescription: "Task cancelled")
            throw error
        }
        
        // DISABLED: Cache causes inconsistent data with real-time updates
        // Always fetch fresh data for conversations
        await logger.log("Cache disabled for conversations - fetching fresh data", level: .info)
        
        do {
            try Task.checkCancellation()
            
            await logger.log("Fetching conversation participants for user", level: .network)
            
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
            
            await logger.log("Found \(participantConversationIds.count) conversations where user is participant", level: .info)
            
            // Get conversations where user is creator
            let createdConversationsResponse = try? await supabase
                .from("conversations")
                .select("id, created_by, title, created_at, updated_at")
                .eq("created_by", value: userId.uuidString)
                .execute()
            
            var allConversationIds = participantConversationIds
            if let createdData = createdConversationsResponse?.data {
                let decoder = createDateDecoder()
                let created: [Conversation] = try decoder.decode([Conversation].self, from: createdData)
                allConversationIds.formUnion(created.map { $0.id })
                await logger.log("Found \(created.count) conversations where user is creator", level: .info)
            }
            
            guard !allConversationIds.isEmpty else {
                await logger.endOperation(operationId, success: true, resultDescription: "No conversations found")
                await cacheManager.cacheConversations(userId: userId, [])
                return []
            }
            
            await logger.log("Total unique conversations: \(allConversationIds.count)", level: .info)
            
            // First, fetch ALL conversations to get their updated_at timestamps for sorting
            // This is necessary because we need to sort before paginating
            await logger.log("Fetching conversation timestamps for sorting", level: .network)
            
            let allConversationsResponse = try await supabase
                .from("conversations")
                .select("id, updated_at")
                .in("id", values: Array(allConversationIds).map { $0.uuidString })
                .order("updated_at", ascending: false)
                .execute()
            
            struct ConversationTimestamp: Codable {
                let id: UUID
                let updatedAt: Date
                enum CodingKeys: String, CodingKey {
                    case id
                    case updatedAt = "updated_at"
                }
            }
            
            let timestamps = try createDateDecoder().decode([ConversationTimestamp].self, from: allConversationsResponse.data)
            
            // Now we have properly sorted IDs
            let sortedIds = timestamps.map { $0.id }
            let paginatedIds = Array(sortedIds[offset..<min(offset + limit, sortedIds.count)])
            
            await logger.log("Applying pagination: offset=\(offset), limit=\(limit), result count=\(paginatedIds.count)", level: .info)
            
            guard !paginatedIds.isEmpty else {
                await logger.endOperation(operationId, success: true, resultDescription: "No conversations in page range")
                await cacheManager.cacheConversations(userId: userId, [])
                return []
            }
            
            await logger.log("Fetching conversation details", level: .network)
            
            let conversationsResponse = try await supabase
                .from("conversations")
                .select("id, created_by, title, created_at, updated_at")
                .in("id", values: paginatedIds.map { $0.uuidString })
                .order("updated_at", ascending: false)
                .execute()
            
            // Decode conversations with custom date decoder
            let decoder = createDateDecoder()
            let conversations: [Conversation] = try decoder.decode([Conversation].self, from: conversationsResponse.data)
            
            await logger.log("Decoded \(conversations.count) conversations", level: .info)
            
            guard !conversations.isEmpty else {
                await logger.endOperation(operationId, success: true, resultDescription: "No conversations after decode")
                await cacheManager.cacheConversations(userId: userId, [])
                return []
            }
            
            // Check cancellation before expensive loop
            try Task.checkCancellation()
            
            // OPTIMIZATION: Batch fetch all data instead of sequential per-conversation fetches
            // This reduces N queries to 3 queries total (last messages, unread counts, participants)
            
            let conversationIds = conversations.map { $0.id }
            
            await logger.log("Starting batch fetch for \(conversationIds.count) conversations", level: .info)
            
            // 1. Batch fetch last messages for all conversations
            let lastMessagesDict = await fetchLastMessagesForConversations(conversationIds: conversationIds)
            await logger.log("Fetched last messages for \(lastMessagesDict.count) conversations", level: .success)
            
            // 2. Batch fetch unread counts for all conversations
            let unreadCountsDict = await fetchUnreadCountsForConversations(conversationIds: conversationIds, userId: userId)
            await logger.log("Fetched unread counts: total unread in \(unreadCountsDict.filter { $0.value > 0 }.count) conversations", level: .success)
            
            // 3. Batch fetch all participants for all conversations
            let participantsDict = await fetchParticipantsForConversations(conversationIds: conversationIds, userId: userId)
            await logger.log("Fetched participants: total \(participantsDict.values.reduce(0) { $0 + $1.count }) participants", level: .success)
            
            // 4. Hydrate conversations with cached display names (local-first)
            let displayNameCache = ConversationDisplayNameCache.shared
            var conversationsWithDetails: [ConversationWithDetails] = []  // Declare the array
            var conversationsToCompute: [(Conversation, [Profile])] = []  // Track conversations needing name computation
            
            for var conversation in conversations {
                try Task.checkCancellation()
                
                // Try to hydrate from cache first
                if let cachedName = await displayNameCache.getDisplayName(for: conversation.id) {
                    conversation.cachedDisplayName = cachedName
                    await logger.logDisplayNameResolution(conversationId: conversation.id, cached: true)
                } else {
                    // No cached name - will need to compute and cache
                    let otherParticipants = participantsDict[conversation.id] ?? []
                    conversationsToCompute.append((conversation, otherParticipants))
                    await logger.logDisplayNameResolution(conversationId: conversation.id, cached: false)
                    // Leave cachedDisplayName as nil for now (UI will show "Loading...")
                }
                
                let details = ConversationWithDetails(
                    conversation: conversation,
                    lastMessage: lastMessagesDict[conversation.id],
                    unreadCount: unreadCountsDict[conversation.id] ?? 0,
                    otherParticipants: participantsDict[conversation.id] ?? []
                )
                conversationsWithDetails.append(details)
            }
            
            // 5. Background task: Compute and cache missing display names
            if !conversationsToCompute.isEmpty {
                await logger.log("Scheduling background task to compute \(conversationsToCompute.count) display names", level: .info)
                
                Task.detached(priority: .background) {
                    await MessagingLogger.shared.log("Computing \(conversationsToCompute.count) missing display names", level: .info)
                    
                    var namesToCache: [UUID: String] = [:]
                    
                    for (conversation, otherParticipants) in conversationsToCompute {
                        if let displayName = ConversationDisplayNameCache.computeDisplayName(
                            conversation: conversation,
                            otherParticipants: otherParticipants,
                            currentUserId: userId
                        ) {
                            namesToCache[conversation.id] = displayName
                        }
                    }
                    
                    // Batch save to cache
                    if !namesToCache.isEmpty {
                        await displayNameCache.setDisplayNames(namesToCache)
                        await MessagingLogger.shared.log("Cached \(namesToCache.count) display names in background", level: .success)
                    }
                }
            }
            
            // DISABLED: Don't cache conversations - causes stale data issues
            await logger.log("Skipping cache write (disabled for real-time consistency)", level: .info)
            
            await logger.endOperation(operationId, success: true, resultDescription: "Fetched \(conversationsWithDetails.count) conversations")
            return conversationsWithDetails
            
        } catch {
            // Handle RLS recursion error gracefully
            let errorString = String(describing: error).lowercased()
            if errorString.contains("infinite recursion") || errorString.contains("recursion") {
                await logger.log("RLS policy recursion detected - returning empty conversations", level: .error)
                await logger.endOperation(operationId, success: false, resultDescription: "RLS recursion error")
                await cacheManager.cacheConversations(userId: userId, [])
                return []
            }
            // Re-throw other errors
            await logger.logError(error, context: "fetchConversations")
            await logger.endOperation(operationId, success: false, resultDescription: error.localizedDescription)
            throw error
        }
    }
    
    /// Get or create direct conversation between two users
    /// - Parameters:
    ///   - userId: First user ID
    ///   - otherUserId: Second user ID
    /// - Returns: Conversation
    /// - Throws: AppError if operation fails
    func getOrCreateDirectConversation(userId: UUID, otherUserId: UUID) async throws -> Conversation {
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
                        .select("id, created_by, title, created_at, updated_at")
                        .eq("id", value: userConv.conversationId.uuidString)
                        .single()
                        .execute()
                    
                    if let convData = conversationResponse?.data {
                        let decoder = createDateDecoder()
                        if let existing = try? decoder.decode(Conversation.self, from: convData) {
                            print("✅ [MessageService] Found existing DM conversation: \(existing.id)")
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
            print("🔴 [MessageService] Error creating conversation: \(error)")
            print("   Error type: \(type(of: error))")
            print("   Error description: \(error.localizedDescription)")
            
            // Check if this is an RLS recursion error
            let errorString = String(describing: error).lowercased()
            if errorString.contains("infinite recursion") || errorString.contains("recursion") {
                print("⚠️ [MessageService] RLS recursion detected when creating conversation.")
                print("   This is a database-level issue. Fix the RLS policy in Supabase.")
                // Re-throw as AppError for better user experience
                throw AppError.serverError("Cannot create conversation due to database policy issue. Please contact support.")
            }
            // Re-throw other errors
            throw error
        }
        
        // Add all users as participants
        print("🔄 [MessageService] Adding \(userIds.count) participants to conversation \(conversation.id)")
        print("   User IDs to add: \(userIds)")
        
        let participantInserts = userIds.map { userId in
            [
                "conversation_id": AnyCodable(conversation.id.uuidString),
                "user_id": AnyCodable(userId.uuidString)
            ]
        }
        
        print("📤 [MessageService] Participant insert payload: \(participantInserts)")
        
        do {
            let response = try await supabase
                .from("conversation_participants")
                .insert(participantInserts)
                .execute()
            
            print("📥 [MessageService] Participants insert response status: \(response.response.statusCode)")
            print("   Response data: \(String(data: response.data, encoding: .utf8) ?? "nil")")
            print("✅ [MessageService] Created conversation \(conversation.id) with \(userIds.count) participant(s)")
            
            // Update display name cache (local-first)
            Task.detached(priority: .background) {
                // Fetch participant profiles to compute display name
                let otherUserIds = userIds.filter { $0 != createdBy }
                var otherParticipants: [Profile] = []
                
                for userId in otherUserIds {
                    if let profile = try? await ProfileService.shared.fetchProfile(userId: userId) {
                        otherParticipants.append(profile)
                    }
                }
                
                // Compute and cache display name
                if let displayName = ConversationDisplayNameCache.computeDisplayName(
                    conversation: conversation,
                    otherParticipants: otherParticipants,
                    currentUserId: createdBy
                ) {
                    await ConversationDisplayNameCache.shared.setDisplayName(displayName, for: conversation.id)
                }
            }
        } catch {
            // Handle RLS recursion error - check multiple error formats
            let errorString = String(describing: error).lowercased()
            print("🔴 [MessageService] Error adding participants to conversation \(conversation.id)")
            print("   Error: \(error)")
            print("   Error type: \(type(of: error))")
            print("   Error description: \(error.localizedDescription)")
            
            if errorString.contains("infinite recursion") || errorString.contains("recursion") {
                print("⚠️ [MessageService] RLS policy recursion when creating participants.")
                print("   This is a database-level issue. Fix the RLS policy in Supabase.")
                // Throw error - conversation without participants is useless
                throw AppError.serverError("Cannot add participants due to database policy issue. Please contact support.")
            } else {
                // For other errors, also throw - participants are essential
                print("⚠️ [MessageService] Failed to add participants")
                throw AppError.processingError("Failed to add participants: \(error.localizedDescription)")
            }
        }
        
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
        guard !userIds.isEmpty else { return }
        
        // Get conversation to check permissions
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
        
        // Check if addedBy has permission to add participants
        // They can add if:
        // 1. They are the conversation creator, OR
        // 2. They are an existing participant
        var canAdd = false
        
        if conversationInfo.createdBy == addedBy {
            canAdd = true
        } else {
            // Check if addedBy is a participant (using simple query that won't recurse)
            let participantCheck = try? await supabase
                .from("conversation_participants")
                .select("user_id")
                .eq("conversation_id", value: conversationId.uuidString)
                .eq("user_id", value: addedBy.uuidString)
                .limit(1)
                .execute()
            
            if let data = participantCheck?.data, !data.isEmpty {
                canAdd = true
            }
        }
        
        guard canAdd else {
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
        
        // Filter out users who are already participants
        let newUserIds = userIds.filter { !existingParticipants.contains($0) }
        
        guard !newUserIds.isEmpty else {
            print("ℹ️ [MessageService] All users are already participants")
            return
        }
        
        // Insert new participants
        let inserts = newUserIds.map { userId in
            [
                "conversation_id": AnyCodable(conversationId.uuidString),
                "user_id": AnyCodable(userId.uuidString)
            ]
        }
        
        try await supabase
            .from("conversation_participants")
            .insert(inserts)
            .execute()
        
        // Create announcement messages if requested
        if createAnnouncement {
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
                        print("⚠️ [MessageService] Failed to create announcement message: \(error.localizedDescription)")
                    }
                }
            }
        }
        
        // Invalidate conversation cache for all added users
        for userId in newUserIds {
            await cacheManager.invalidateConversations(userId: userId)
        }
        await cacheManager.invalidateConversations(userId: addedBy)
        await cacheManager.invalidateMessages(conversationId: conversationId)
        
        // Update display name cache (local-first)
        // When participants change, recompute and update the cached name
        Task.detached(priority: .background) {
            print("🔄 [MessageService] Updating display name cache after adding participants")
            
            // Fetch ALL current participants (including newly added ones)
            let allParticipantsResponse = try? await self.supabase
                .from("conversation_participants")
                .select("user_id")
                .eq("conversation_id", value: conversationId.uuidString)
                .execute()
            
            struct ParticipantUserId: Codable {
                let userId: UUID
                enum CodingKeys: String, CodingKey {
                    case userId = "user_id"
                }
            }
            
            let allParticipantIds = (try? JSONDecoder().decode([ParticipantUserId].self, from: allParticipantsResponse?.data ?? Data()))?.map { $0.userId } ?? []
            
            // Fetch profiles for all participants (excluding the current user)
            let otherParticipantIds = allParticipantIds.filter { $0 != addedBy }
            var otherParticipants: [Profile] = []
            
            for userId in otherParticipantIds {
                if let profile = try? await ProfileService.shared.fetchProfile(userId: userId) {
                    otherParticipants.append(profile)
                }
            }
            
            // Fetch conversation to get title
            let conversationResponse = try? await self.supabase
                .from("conversations")
                .select("id, title, created_by, created_at, updated_at")
                .eq("id", value: conversationId.uuidString)
                .single()
                .execute()
            
            if let convData = conversationResponse?.data,
               let conversation = try? self.createDateDecoder().decode(Conversation.self, from: convData) {
                
                // Compute new display name with updated participant list
                if let displayName = ConversationDisplayNameCache.computeDisplayName(
                    conversation: conversation,
                    otherParticipants: otherParticipants,
                    currentUserId: addedBy
                ) {
                    await ConversationDisplayNameCache.shared.setDisplayName(displayName, for: conversationId)
                    print("✅ [MessageService] Updated cached display name: '\(displayName)'")
                }
            }
        }
        
        print("✅ [MessageService] Added \(newUserIds.count) participant(s) to conversation \(conversationId)")
    }
    
    
    // MARK: - Private Helpers
    
    /// Create a date decoder with custom date decoding strategy
    private nonisolated func createDateDecoder() -> JSONDecoder {
        return JSONDecoderFactory.createSupabaseDecoder()
    }
    
    // MARK: - Messages
    
    /// Fetch messages for a conversation with pagination
    /// - Parameters:
    ///   - conversationId: The conversation ID
    ///   - limit: Maximum number of messages to fetch (default: 25)
    ///   - beforeMessageId: Optional message ID to fetch messages before (for pagination)
    /// - Returns: PaginatedMessages with messages, hasMore flag, and endCursor
    /// - Throws: AppError if fetch fails or user is not a participant
    func fetchMessages(conversationId: UUID, limit: Int = 25, beforeMessageId: UUID? = nil) async throws -> PaginatedMessages {
        let operationId = "fetchMessages_\(conversationId)_\(beforeMessageId?.uuidString ?? "initial")"
        let isPagination = beforeMessageId != nil
        await logger.startOperation(operationId, description: "Fetch messages (limit: \(limit), pagination: \(isPagination))")
        
        // Check for cancellation before starting
        do {
            try Task.checkCancellation()
        } catch {
            await logger.endOperation(operationId, success: false, resultDescription: "Task cancelled")
            throw error
        }
        
        // Security check: Verify user is a participant (RLS is disabled on conversation_participants)
        guard let currentUserId = AuthService.shared.currentUserId else {
            await logger.log("No authenticated user", level: .error)
            await logger.endOperation(operationId, success: false, resultDescription: "Not authenticated")
            throw AppError.notAuthenticated
        }
        
        try Task.checkCancellation()
        
        await logger.log("Verifying user is participant in conversation", level: .info)
        
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
            await logger.log("User is not a participant - permission denied", level: .error)
            await logger.endOperation(operationId, success: false, resultDescription: "Permission denied")
            throw AppError.permissionDenied("You don't have permission to view messages in this conversation")
        }
        
        await logger.log("User verified as participant", level: .success)
        
        // Check cache first (only for initial load, not pagination)
        if beforeMessageId == nil {
            if let cached = await cacheManager.getCachedMessages(conversationId: conversationId), !cached.isEmpty {
                await logger.logCache(operation: "getMessage s", hit: true, key: conversationId.uuidString)
                await logger.endOperation(operationId, success: true, resultDescription: "Returned \(cached.count) cached messages")
                // For cached results, assume more might exist
                return PaginatedMessages(
                    messages: cached,
                    hasMore: true, // Conservative: assume more exist
                    endCursor: cached.last?.id
                )
            } else {
                await logger.logCache(operation: "getMessages", hit: false, key: conversationId.uuidString)
            }
        } else {
            await logger.log("Pagination request - skipping cache", level: .info)
        }
        
        await logger.log("Fetching messages from network", level: .network)
        
        var query = supabase
            .from("messages")
            .select("*, sender:profiles!messages_from_id_fkey(id, name, avatar_url)")
            .eq("conversation_id", value: conversationId.uuidString)
        
        // If beforeMessageId is provided, fetch messages before that message
        if let beforeMessageId = beforeMessageId {
            await logger.log("Fetching messages before: \(beforeMessageId)", level: .info)
            
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
                    await logger.log("Pagination anchor date: \(beforeMessage.createdAt)", level: .info)
                }
            }
        }
        
        // Fetch limit + 1 to determine if more exist
        let response = try await query
            .order("created_at", ascending: false)
            .limit(limit + 1)
            .execute()
        
        let decoder = createDateDecoder()
        var messages: [Message] = try decoder.decode([Message].self, from: response.data)
        
        await logger.log("Decoded \(messages.count) messages", level: .info)
        
        // Check if more messages exist
        let hasMore = messages.count > limit
        if hasMore {
            // Remove the extra message we fetched
            messages = Array(messages.prefix(limit))
            await logger.log("More messages available (pagination possible)", level: .info)
        } else {
            await logger.log("All messages loaded (end of conversation)", level: .info)
        }
        
        // Reverse to get oldest first (for display - newest at bottom)
        messages.reverse()
        
        // Fetch reactions for messages
        let messageIds = messages.map { $0.id.uuidString }
        if !messageIds.isEmpty {
            await logger.log("Fetching reactions for \(messageIds.count) messages", level: .network)
            
            let reactionsResponse = try? await supabase
                .from("message_reactions")
                .select()
                .in("message_id", values: messageIds)
                .execute()
            
            if let reactionsData = reactionsResponse?.data {
                let reactions: [MessageReaction] = try! decoder.decode([MessageReaction].self, from: reactionsData) ?? []
                
                await logger.log("Found \(reactions.count) reactions", level: .success)
                
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
        
        // Cache results (only cache if this is the initial load, not pagination)
        if beforeMessageId == nil {
            await cacheManager.cacheMessages(conversationId: conversationId, messages)
            await logger.log("Cached messages for future requests", level: .cache)
        }
        
        await logger.endOperation(operationId, success: true, resultDescription: "Fetched \(messages.count) messages, hasMore: \(hasMore)")
        
        return PaginatedMessages(
            messages: messages,
            hasMore: hasMore,
            endCursor: messages.last?.id
        )
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
        
        guard let compressedData = ImageCompressor.compress(uiImage, preset: .messageImage) else {
            throw AppError.processingError("Failed to compress image")
        }
        
        // Upload to message-images bucket
        // Store in a folder per conversation for better organization
        let fileName = "\(conversationId.uuidString)/\(UUID().uuidString).jpg"
        
        try await supabase.storage
            .from("message-images")
            .upload(
                fileName,
                data: compressedData,
                options: FileOptions(contentType: "image/jpeg", upsert: false)
            )
        
        // Get public URL
        let publicUrl = try supabase.storage
            .from("message-images")
            .getPublicURL(path: fileName)
        
        return publicUrl.absoluteString
    }
    
    /// Send a message
    /// - Parameters:
    ///   - conversationId: The conversation ID
    ///   - fromId: The sender's user ID
    ///   - text: The message text
    ///   - imageUrl: Optional image URL (if message includes an image)
    /// - Returns: The created message
    /// - Throws: AppError if send fails
    func sendMessage(conversationId: UUID, fromId: UUID, text: String, imageUrl: String? = nil) async throws -> Message {
        // Check for cancellation before starting
        try Task.checkCancellation()
        
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
            imageUrl: imageUrl
        )
        
        let response = try await supabase
            .from("messages")
            .insert(newMessage)
            .select("*, sender:profiles!messages_from_id_fkey(id, name, avatar_url)")
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
                print("🔴 [MessageService] Failed to decode message. Raw JSON: \(jsonString)")
            }
            print("🔴 [MessageService] Decoding error: \(error)")
            // Try decoding again (might work if error was transient)
            message = try decoder.decode(Message.self, from: response.data)
        }
        
        // Update conversation updated_at
        try await supabase
            .from("conversations")
            .update(["updated_at": ISO8601DateFormatter().string(from: Date())])
            .eq("id", value: conversationId.uuidString)
            .execute()
        
        // Invalidate caches
        await cacheManager.invalidateMessages(conversationId: conversationId)
        await cacheManager.invalidateConversations(userId: fromId)
        
        print("✅ [MessageService] Sent message: \(message.id)")
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
        
        // Update each message to add userId to readBy array
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
        
        // Update last_seen timestamp to indicate user is actively viewing
        // This prevents push notifications when user is viewing the conversation
        try? await updateLastSeen(conversationId: conversationId, userId: userId)
        
        // Invalidate caches
        await cacheManager.invalidateMessages(conversationId: conversationId)
        await cacheManager.invalidateConversations(userId: userId)
        
        print("✅ [MessageService] Marked messages as read for conversation \(conversationId)")
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
        
        print("✅ [MessageService] Updated last_seen for user \(userId) in conversation \(conversationId)")
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
        
        // Invalidate caches
        await cacheManager.invalidateConversations(userId: userId)
        
        // Update display name cache (title changed)
        // The title is part of the cached display name, so update it
        Task.detached(priority: .background) {
            print("🔄 [MessageService] Updating display name cache after title change")
            
            // Fetch updated conversation
            let conversationResponse = try? await self.supabase
                .from("conversations")
                .select("id, title, created_by, created_at, updated_at")
                .eq("id", value: conversationId.uuidString)
                .single()
                .execute()
            
            if let convData = conversationResponse?.data,
               let conversation = try? self.createDateDecoder().decode(Conversation.self, from: convData) {
                
                // Fetch participants to compute full display name
                let participantsResponse = try? await self.supabase
                    .from("conversation_participants")
                    .select("user_id")
                    .eq("conversation_id", value: conversationId.uuidString)
                    .execute()
                
                struct ParticipantUserId: Codable {
                    let userId: UUID
                    enum CodingKeys: String, CodingKey {
                        case userId = "user_id"
                    }
                }
                
                let participantIds = (try? JSONDecoder().decode([ParticipantUserId].self, from: participantsResponse?.data ?? Data()))?.map { $0.userId } ?? []
                let otherParticipantIds = participantIds.filter { $0 != userId }
                
                var otherParticipants: [Profile] = []
                for participantId in otherParticipantIds {
                    if let profile = try? await ProfileService.shared.fetchProfile(userId: participantId) {
                        otherParticipants.append(profile)
                    }
                }
                
                // Compute and cache new display name
                if let displayName = ConversationDisplayNameCache.computeDisplayName(
                    conversation: conversation,
                    otherParticipants: otherParticipants,
                    currentUserId: userId
                ) {
                    await ConversationDisplayNameCache.shared.setDisplayName(displayName, for: conversationId)
                    print("✅ [MessageService] Updated cached display name after title change: '\(displayName)'")
                }
            }
        }
        
        print("✅ [MessageService] Updated conversation title: \(title ?? "nil")")
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
        
        // Invalidate message cache
        await cacheManager.invalidateMessages(conversationId: messageConv.conversationId)
        
        print("✅ [MessageService] Added reaction \(reaction) to message \(messageId)")
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
        
        // Invalidate message cache
        if let conversationId = conversationId {
            await cacheManager.invalidateMessages(conversationId: conversationId)
        }
        
        print("✅ [MessageService] Removed reaction from message \(messageId)")
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
    
    // MARK: - Batch Fetch Helpers (Performance Optimization)
    
    /// Batch fetch last messages for multiple conversations
    /// Reduces N queries to 1 query using concurrent task group
    private func fetchLastMessagesForConversations(conversationIds: [UUID]) async -> [UUID: Message] {
        guard !conversationIds.isEmpty else { return [:] }
        
        var lastMessagesDict: [UUID: Message] = [:]
        
        // Fetch last message for each conversation concurrently
        await withTaskGroup(of: (UUID, Message?).self) { group in
            for conversationId in conversationIds {
                group.addTask {
                    let lastMessageResponse = try? await self.supabase
                        .from("messages")
                        .select("*, sender:profiles!messages_from_id_fkey(id, name, avatar_url)")
                        .eq("conversation_id", value: conversationId.uuidString)
                        .order("created_at", ascending: false)
                        .limit(1)
                        .single()
                        .execute()
                    
                    var lastMessage: Message? = nil
                    if let lastMessageData = lastMessageResponse?.data {
                        let decoder = self.createDateDecoder()
                        lastMessage = try? decoder.decode(Message.self, from: lastMessageData)
                    }
                    return (conversationId, lastMessage)
                }
            }
            
            for await (conversationId, message) in group {
                if let message = message {
                    lastMessagesDict[conversationId] = message
                }
            }
        }
        
        return lastMessagesDict
    }
    
    /// Batch fetch unread counts for multiple conversations
    /// Reduces N queries to 1 query
    private func fetchUnreadCountsForConversations(conversationIds: [UUID], userId: UUID) async -> [UUID: Int] {
        guard !conversationIds.isEmpty else { return [:] }
        
        // Fetch all unread messages for user across all conversations
        let unreadResponse = try? await supabase
            .from("messages")
            .select("id, conversation_id")
            .in("conversation_id", values: conversationIds.map { $0.uuidString })
            .not("read_by", operator: .cs, value: userId.uuidString)
            .execute()
        
        guard let unreadData = unreadResponse?.data else { return [:] }
        
        struct MessageConversation: Codable {
            let id: UUID
            let conversationId: UUID
            
            enum CodingKeys: String, CodingKey {
                case id
                case conversationId = "conversation_id"
            }
        }
        
        let unreadMessages = (try? JSONDecoder().decode([MessageConversation].self, from: unreadData)) ?? []
        
        // Count unread messages per conversation
        var unreadCountsDict: [UUID: Int] = [:]
        for conversationId in conversationIds {
            unreadCountsDict[conversationId] = 0
        }
        
        for message in unreadMessages {
            unreadCountsDict[message.conversationId, default: 0] += 1
        }
        
        return unreadCountsDict
    }
    
    /// Batch fetch participants for multiple conversations
    /// Reduces N queries to 2 queries (participants + profiles)
    private func fetchParticipantsForConversations(conversationIds: [UUID], userId: UUID) async -> [UUID: [Profile]] {
        guard !conversationIds.isEmpty else { return [:] }
        
        // Initialize empty dict for all conversations
        var participantsDict: [UUID: [Profile]] = [:]
        for conversationId in conversationIds {
            participantsDict[conversationId] = []
        }
        
        do {
            // Step 1: Fetch all participant relationships (conversation_id, user_id)
            let participantsResponse = try await supabase
                .from("conversation_participants")
                .select("conversation_id, user_id")
                .in("conversation_id", values: conversationIds.map { $0.uuidString })
                .neq("user_id", value: userId.uuidString)
                .execute()
            
            struct ParticipantRow: Codable {
                let conversationId: UUID
                let userId: UUID
                
                enum CodingKeys: String, CodingKey {
                    case conversationId = "conversation_id"
                    case userId = "user_id"
                }
            }
            
            let rows = try JSONDecoder().decode([ParticipantRow].self, from: participantsResponse.data)
            
            guard !rows.isEmpty else {
                print("⚠️ [MessageService] No participants found for conversations (excluding current user)")
                return participantsDict
            }
            
            // Step 2: Collect unique user IDs
            let userIds = Set(rows.map { $0.userId })
            
            print("📊 [MessageService] Found \(rows.count) participant relationships for \(userIds.count) unique users")
            
            // Step 3: Batch fetch all profiles for these users
            // Only select fields needed for conversation display (minimal query for performance)
            let profilesResponse = try await supabase
                .from("profiles")
                .select("id, name, email, avatar_url, car, is_admin, approved, created_at, updated_at")
                .in("id", values: Array(userIds).map { $0.uuidString })
                .execute()
            
            let decoder = createDateDecoder()
            let profiles = try decoder.decode([Profile].self, from: profilesResponse.data)
            
            // Create a lookup dictionary: userId -> Profile
            var profileLookup: [UUID: Profile] = [:]
            for profile in profiles {
                profileLookup[profile.id] = profile
            }
            
            // Step 4: Map participants to conversations
            for row in rows {
                if let profile = profileLookup[row.userId] {
                    participantsDict[row.conversationId, default: []].append(profile)
                } else {
                    print("⚠️ [MessageService] No profile found for participant userId=\(row.userId)")
                }
            }
            
            let totalParticipants = participantsDict.values.reduce(0) { $0 + $1.count }
            print("✅ [MessageService] Fetched participants for \(conversationIds.count) conversations. Total participants: \(totalParticipants)")
            
            return participantsDict
            
        } catch {
            print("🔴 [MessageService] Error fetching participants for conversations: \(error)")
            print("   Error description: \(error.localizedDescription)")
            if let decodingError = error as? DecodingError {
                switch decodingError {
                case .dataCorrupted(let context):
                    print("   Data corrupted: \(context)")
                case .keyNotFound(let key, let context):
                    print("   Key '\(key)' not found: \(context.debugDescription)")
                case .typeMismatch(let type, let context):
                    print("   Type '\(type)' mismatch: \(context.debugDescription)")
                case .valueNotFound(let type, let context):
                    print("   Value '\(type)' not found: \(context.debugDescription)")
                @unknown default:
                    print("   Unknown decoding error")
                }
            }
            return participantsDict
        }
    }
}

