//
//  MessageThreadViewModel.swift
//  NaarsCars
//
//  ViewModel for managing a message thread (parent + replies).
//  Extracted from ConversationDetailView.swift for use by both SwiftUI
//  and UIKit thread views.
//

import Foundation

@Observable
@MainActor
final class MessageThreadViewModel {
    var parentMessage: Message?
    var replies: [Message] = []
    var isLoading = false
    var error: AppError?

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
            let fetched = try await messageService.fetchReplies(
                conversationId: conversationId,
                replyToId: parentMessageId
            )
            // The server does not know about Delete for Me: leave out replies hidden on this
            // device, or one deleted in the thread came back the next time it was opened.
            let hiddenIds = MessagingRepository.shared.fetchLocallyDeletedMessageIds(for: conversationId)
            replies = hiddenIds.isEmpty ? fetched : fetched.filter { !hiddenIds.contains($0.id) }
        } catch {
            self.error = AppError.processingError(error.localizedDescription)
        }

        isLoading = false
    }

    /// Brings the thread in line with the conversation's loaded messages.
    ///
    /// Rows already shown are refreshed from the conversation's copy, so an edit, unsend,
    /// reaction or send-status change shows here too (this used to append unseen ids only, and
    /// everything else stayed stale until the thread was reopened). A row that is still sending
    /// or failed and is no longer in the conversation is dropped: its server copy arrives under a
    /// new id, and keeping the local one showed the reply twice. Any other row the conversation
    /// does not hold is older than its loaded pages and is kept as fetched.
    func mergeReplies(from messages: [Message]) {
        if let parent = messages.first(where: { $0.id == parentMessageId }) {
            let refreshed = Self.keepingJoinedFields(of: parentMessage, in: parent)
            if refreshed != parentMessage { parentMessage = refreshed }
        }

        let matching = messages.filter { $0.replyToId == parentMessageId }
        let matchingById = Dictionary(matching.map { ($0.id, $0) }, uniquingKeysWith: { _, new in new })

        var merged: [Message] = []
        merged.reserveCapacity(max(replies.count, matching.count))
        for shown in replies {
            if let fresh = matchingById[shown.id] {
                merged.append(Self.keepingJoinedFields(of: shown, in: fresh))
            } else if shown.sendStatus != .sending && shown.sendStatus != .failed {
                merged.append(shown)
            }
        }
        let shownIds = Set(replies.map { $0.id })
        for message in matching where !shownIds.contains(message.id) {
            merged.append(message)
        }
        merged.sort { $0.createdAt < $1.createdAt }
        // Assign only on a real change: every assignment rebuilds the thread's snapshot.
        if merged != replies { replies = merged }
    }

    /// Removes a reply from the thread after Delete for Me. The conversation no longer holds
    /// the row, so `mergeReplies` would keep it as an older reply.
    func removeReply(id: UUID) {
        replies.removeAll { $0.id == id }
    }

    /// Shows a confirmed edit on a row the conversation's loaded pages do not hold (an older
    /// reply). Rows the conversation does hold are refreshed by `mergeReplies`.
    func applyConfirmedEdit(messageId: UUID, text: String) {
        let trimmed = text.trimmingCharacters(in: .whitespacesAndNewlines)
        guard !trimmed.isEmpty else { return }
        if var parent = parentMessage, parent.id == messageId {
            guard parent.text != trimmed else { return }
            parent.text = trimmed
            parent.editedAt = Date()
            parentMessage = parent
        } else if let index = replies.firstIndex(where: { $0.id == messageId }), replies[index].text != trimmed {
            replies[index].text = trimmed
            replies[index].editedAt = Date()
        }
    }

    /// The conversation's copy of a message comes from the local store and can lack the joined
    /// sender and reactions that have not been loaded yet. Keep what the thread's own fetch had
    /// for those, so refreshing a row cannot drop its sender name or reaction badge. Only nil
    /// slots are filled; a non-nil value from the conversation always wins.
    private static func keepingJoinedFields(of shown: Message?, in fresh: Message) -> Message {
        guard let shown else { return fresh }
        var result = fresh
        if result.sender == nil { result.sender = shown.sender }
        if result.individualReactions == nil, let reactions = shown.individualReactions {
            result.setIndividualReactions(reactions)
        }
        return result
    }
}
