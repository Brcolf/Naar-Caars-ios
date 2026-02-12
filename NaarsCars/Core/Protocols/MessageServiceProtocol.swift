//
//  MessageServiceProtocol.swift
//  NaarsCars
//

import Foundation

@MainActor
protocol MessageServiceProtocol: AnyObject {
    func fetchMessages(conversationId: UUID, limit: Int, beforeMessageId: UUID?) async throws -> [Message]
    func searchMessages(query: String, userId: UUID, limit: Int) async throws -> [Message]
    func markAsRead(conversationId: UUID, userId: UUID, updateLastSeen: Bool) async throws
    func updateLastSeen(conversationId: UUID, userId: UUID) async throws
}
