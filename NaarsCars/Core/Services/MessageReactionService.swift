//
//  MessageReactionService.swift
//  NaarsCars
//
//  Service for message reaction operations
//

import Foundation
import Supabase
import PostgREST
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
        // Participation is enforced server-side by the `message_reactions_insert` RLS policy
        // (user_id = auth.uid() AND caller is in the message's conversation), so no lookups
        // precede the write. A policy rejection surfaces as a permission error.
        let reactionData: [String: AnyCodable] = [
            "message_id": AnyCodable(messageId.uuidString),
            "user_id": AnyCodable(userId.uuidString),
            "reaction": AnyCodable(reaction)
        ]

        do {
            try await supabase
                .from("message_reactions")
                .upsert(reactionData, onConflict: "message_id,user_id")
                .execute()
        } catch let error as PostgrestError where error.code == "42501" {
            throw AppError.permissionDenied("You must be a participant to react to messages")
        }

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

    /// Fetch individual reaction records for a message.
    /// - Parameter messageId: The message ID
    /// - Returns: Array of individual `MessageReaction` records
    /// - Throws: AppError if fetch fails
    func fetchIndividualReactions(messageId: UUID) async throws -> [MessageReaction] {
        let response = try await supabase
            .from("message_reactions")
            .select("id, message_id, user_id, reaction, created_at")
            .eq("message_id", value: messageId.uuidString)
            .execute()

        let decoder = createDateDecoder()
        return try decoder.decode([MessageReaction].self, from: response.data)
    }

    /// Batch-fetch individual reaction records for multiple messages in a single query.
    /// Uses a 10s timeout to fail fast on degraded QUIC connections instead of
    /// queuing for 60s (the default), which caused thousands of accumulated
    /// URLSession tasks and OOM kills.
    /// - Parameter messageIds: Array of message IDs
    /// - Returns: Dictionary mapping message ID → its reaction records
    func fetchIndividualReactionsBatch(messageIds: [UUID]) async throws -> [UUID: [MessageReaction]] {
        guard !messageIds.isEmpty else { return [:] }

        let response = try await withThrowingTaskGroup(of: PostgrestResponse.self) { group in
            group.addTask {
                try await self.supabase
                    .from("message_reactions")
                    .select("id, message_id, user_id, reaction, created_at")
                    .in("message_id", values: messageIds.map { $0.uuidString })
                    .execute()
            }
            group.addTask {
                try await Task.sleep(for: .seconds(Constants.Timeout.reactionBatchFetch))
                throw URLError(.timedOut)
            }
            let result = try await group.next()!
            group.cancelAll()
            return result
        }

        let decoder = createDateDecoder()
        let allReactions = try decoder.decode([MessageReaction].self, from: response.data)
        return Dictionary(grouping: allReactions, by: \.messageId)
    }
}
