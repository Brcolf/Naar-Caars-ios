//
//  ConversationServiceProtocol.swift
//  NaarsCars
//

import Foundation

@MainActor
protocol ConversationServiceProtocol: AnyObject {
    func fetchConversations(userId: UUID, limit: Int, offset: Int) async throws -> [ConversationWithDetails]
    func getHiddenConversationIds(for userId: UUID) -> Set<UUID>
}
