//
//  MessageThreadViewModel.swift
//  NaarsCars
//
//  ViewModel for managing a message thread (parent + replies).
//  Extracted from ConversationDetailView.swift for use by both SwiftUI
//  and UIKit thread views.
//

import Foundation
internal import Combine

@MainActor
final class MessageThreadViewModel: ObservableObject {
    @Published var parentMessage: Message?
    @Published var replies: [Message] = []
    @Published var isLoading = false
    @Published var error: AppError?

    private let conversationId: UUID
    private let parentMessageId: UUID
    private let messageService = MessageService.shared

    init(conversationId: UUID, parentMessageId: UUID) {
        self.conversationId = conversationId
        self.parentMessageId = parentMessageId
    }

    func loadThread(seedMessages: [Message] = []) async {
        isLoading = true
        error = nil

        if let seedParent = seedMessages.first(where: { $0.id == parentMessageId }) {
            parentMessage = seedParent
        }
        replies = []

        do {
            parentMessage = try await messageService.fetchMessageById(parentMessageId)
            replies = try await messageService.fetchReplies(
                conversationId: conversationId,
                replyToId: parentMessageId
            )
        } catch {
            self.error = AppError.processingError(error.localizedDescription)
        }

        isLoading = false
    }

    func mergeReplies(from messages: [Message]) {
        if let parent = messages.first(where: { $0.id == parentMessageId }) {
            parentMessage = parent
        }

        let matching = messages.filter { $0.replyToId == parentMessageId }
        guard !matching.isEmpty else { return }

        var merged = replies
        let existingIds = Set(merged.map { $0.id })
        for message in matching where !existingIds.contains(message.id) {
            merged.append(message)
        }
        merged.sort { $0.createdAt < $1.createdAt }
        replies = merged
    }
}
