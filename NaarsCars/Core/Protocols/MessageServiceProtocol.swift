//
//  MessageServiceProtocol.swift
//  NaarsCars
//

import Foundation

protocol MessageServiceProtocol: AnyObject {
    func fetchMessages(conversationId: UUID, limit: Int, beforeMessageId: UUID?) async throws -> [Message]
    func searchMessages(query: String, userId: UUID, limit: Int) async throws -> [Message]
    func markAsRead(conversationId: UUID, userId: UUID, updateLastSeen: Bool) async throws
    func updateLastSeen(conversationId: UUID, userId: UUID) async throws

    // Blocking
    func isBlocked(_ userId: UUID) -> Bool
    func blockUser(blockerId: UUID, blockedId: UUID, reason: String?) async throws
    func unblockUser(blockerId: UUID, blockedId: UUID) async throws
    func getBlockedUsers(userId: UUID) async throws -> [BlockedUser]

    // Reporting
    func reportUser(reporterId: UUID, reportedUserId: UUID, type: MessageService.ReportType, description: String?) async throws
    func reportMessage(reporterId: UUID, messageId: UUID, type: MessageService.ReportType, description: String?) async throws
    func reportPost(reporterId: UUID, postId: UUID, authorId: UUID, type: MessageService.ReportType, description: String?) async throws
    func reportComment(reporterId: UUID, commentId: UUID, authorId: UUID, type: MessageService.ReportType, description: String?) async throws
    func reportRide(reporterId: UUID, rideId: UUID, authorId: UUID, type: MessageService.ReportType, description: String?) async throws
    func reportFavor(reporterId: UUID, favorId: UUID, authorId: UUID, type: MessageService.ReportType, description: String?) async throws
}
