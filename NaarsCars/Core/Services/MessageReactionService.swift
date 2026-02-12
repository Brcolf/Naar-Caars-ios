//
//  MessageReactionService.swift
//  NaarsCars
//
//  Service for message reaction operations
//

import Foundation
import Supabase
import OSLog

/// Service for message reaction operations
/// Handles adding, removing, and fetching reactions on messages
final class MessageReactionService {
    
    // MARK: - Singleton
    
    static let shared = MessageReactionService()
    
    // MARK: - Private Properties
    
    private let supabase = SupabaseService.shared.client
    
    // MARK: - Initialization
    
    private init() {}
    
    // MARK: - Private Helpers
    
    /// Create a date decoder with custom date decoding strategy
    private func createDateDecoder() -> JSONDecoder {
        DateDecoderFactory.makeMessagingDecoder()
    }
    
    // MARK: - Reactions
    
    /// Add a reaction to a message
    /// - Parameters:
    ///   - messageId: The message ID
    ///   - userId: The user ID adding the reaction
    ///   - reaction: The reaction emoji/text
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
}
