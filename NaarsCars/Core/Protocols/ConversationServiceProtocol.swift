//
//  ConversationServiceProtocol.swift
//  NaarsCars
//

import Foundation

protocol ConversationServiceProtocol: AnyObject {
    func fetchConversations(userId: UUID, limit: Int, offset: Int) async throws -> [ConversationWithDetails]
    func fetchConversationWithDetails(conversationId: UUID, userId: UUID) async throws -> ConversationWithDetails?
    func getHiddenConversationIds(for userId: UUID) -> Set<UUID>
    func unhideConversationForUser(conversationId: UUID, userId: UUID)

    // Creation
    func getOrCreateDirectConversation(userId: UUID, otherUserId: UUID) async throws -> Conversation
    func createConversationWithUsers(userIds: [UUID], createdBy: UUID, title: String?) async throws -> Conversation
    /// The existing untitled conversation whose active members are exactly `userIds`, if any
    /// (one thread per participant set). Returns nil on lookup failure so callers can create.
    func findConversation(forParticipants userIds: [UUID]) async -> UUID?

    // Group details
    func updateConversationTitle(conversationId: UUID, title: String?, userId: UUID) async throws
    func uploadGroupImage(imageData: Data, conversationId: UUID) async throws -> String
    func updateGroupImage(conversationId: UUID, imageUrl: String?, userId: UUID) async throws
}
