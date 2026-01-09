//
//  ConversationService.swift
//  NaarsCars
//
//  Service for conversation-related operations
//

import Foundation
import Supabase

/// Service for conversation-related operations
/// Handles creating conversations for requests
@MainActor
final class ConversationService {
    
    // MARK: - Singleton
    
    static let shared = ConversationService()
    
    // MARK: - Private Properties
    
    private let supabase = SupabaseService.shared.client
    
    // MARK: - Initialization
    
    private init() {}
    
    // MARK: - Conversation Creation
    
    /// Create or get conversation for a request
    /// - Parameters:
    ///   - requestType: "ride" or "favor"
    ///   - requestId: Request ID
    ///   - posterId: User ID of the poster
    ///   - claimerId: User ID of the claimer
    /// - Returns: Conversation ID
    /// - Throws: AppError if creation fails
    func createConversationForRequest(
        requestType: String,
        requestId: UUID,
        posterId: UUID,
        claimerId: UUID
    ) async throws -> UUID {
        // Check if conversation already exists for this request
        let existingResponse = try? await supabase
            .from("conversations")
            .select("id")
            .eq(requestType == "ride" ? "ride_id" : "favor_id", value: requestId.uuidString)
            .single()
            .execute()
        
        if let existingData = existingResponse?.data {
            struct ConversationId: Codable {
                let id: UUID
            }
            if let existing = try? JSONDecoder().decode(ConversationId.self, from: existingData) {
                // Conversation exists, add claimer as participant if not already
                try await addParticipantIfNeeded(
                    conversationId: existing.id,
                    userId: claimerId
                )
                return existing.id
            }
        }
        
        // Create new conversation
        var conversationData: [String: AnyCodable] = [
            "created_by": AnyCodable(posterId.uuidString)
        ]
        
        if requestType == "ride" {
            conversationData["ride_id"] = AnyCodable(requestId.uuidString)
        } else {
            conversationData["favor_id"] = AnyCodable(requestId.uuidString)
        }
        
        let response = try await supabase
            .from("conversations")
            .insert(conversationData)
            .select()
            .single()
            .execute()
        
        let conversation: Conversation = try JSONDecoder().decode(Conversation.self, from: response.data)
        
        // Add poster as admin participant
        try await supabase
            .from("conversation_participants")
            .insert([
                "conversation_id": AnyCodable(conversation.id.uuidString),
                "user_id": AnyCodable(posterId.uuidString),
                "is_admin": AnyCodable(true)
            ])
            .execute()
        
        // Add claimer as participant
        try await supabase
            .from("conversation_participants")
            .insert([
                "conversation_id": AnyCodable(conversation.id.uuidString),
                "user_id": AnyCodable(claimerId.uuidString),
                "is_admin": AnyCodable(false)
            ])
            .execute()
        
        return conversation.id
    }
    
    // MARK: - Private Helpers
    
    /// Add participant to conversation if not already present
    private func addParticipantIfNeeded(
        conversationId: UUID,
        userId: UUID
    ) async throws {
        // Check if participant already exists
        let existingResponse = try? await supabase
            .from("conversation_participants")
            .select("id")
            .eq("conversation_id", value: conversationId.uuidString)
            .eq("user_id", value: userId.uuidString)
            .single()
            .execute()
        
        // If exists, return early
        if existingResponse != nil {
            return
        }
        
        // Add participant
        try await supabase
            .from("conversation_participants")
            .insert([
                "conversation_id": AnyCodable(conversationId.uuidString),
                "user_id": AnyCodable(userId.uuidString),
                "is_admin": AnyCodable(false)
            ])
            .execute()
    }
}




