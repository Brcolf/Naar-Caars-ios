//
//  MessagePaginationManager.swift
//  NaarsCars
//
//  Pagination and initial load behavior for conversation messages
//

import Foundation
internal import Combine

/// Extracted message load/pagination logic for conversation detail.
@MainActor
final class MessagePaginationManager: ObservableObject {
    private let pageSize = Constants.PageSizes.messages
    private let initialRenderLimit = Constants.PageSizes.messagesInitialRender
    private var oldestMessageId: UUID?
    private var isLoadingMessagesInFlight = false
    private var isMarkReadInFlight = false

    func loadMessages(
        conversationId: UUID,
        repository: MessagingRepository,
        authService: any AuthServiceProtocol,
        markConversationReadImmediately: @escaping @MainActor (UUID) async -> Void,
        setMessages: @escaping @MainActor ([Message]) -> Void,
        getMessages: @escaping @MainActor () -> [Message],
        setIsLoading: @escaping @MainActor (Bool) -> Void,
        setHasMoreMessages: @escaping @MainActor (Bool) -> Void
    ) async {
        guard !isLoadingMessagesInFlight else { return }
        isLoadingMessagesInFlight = true
        defer { isLoadingMessagesInFlight = false }

        let loadStart = Date()
        var source = "local"
        setIsLoading(true)
        oldestMessageId = nil

        var localMessages: [Message] = []
        do {
            localMessages = try repository.getMessages(for: conversationId)
        } catch {
            AppLogger.warning("messaging", "[MessagePaginationManager] Error loading local messages: \(error.localizedDescription)")
        }

        if localMessages.contains(where: { $0.replyToId != nil && $0.replyToMessage == nil }) {
            localMessages = await Self.buildReplyContexts(from: localMessages)
        }

        let localCountBeforeTrim = localMessages.count
        if localMessages.count > initialRenderLimit {
            localMessages = Array(localMessages.suffix(initialRenderLimit))
        }

        if !localMessages.isEmpty {
            setMessages(localMessages)
            oldestMessageId = localMessages.first?.id
            setHasMoreMessages((localCountBeforeTrim > localMessages.count) || localMessages.count >= pageSize)
        }

        setIsLoading(false)

        if let userId = authService.currentUserId {
            Task { @MainActor in
                await markConversationReadImmediately(userId)
            }
        }

        Task { @MainActor [weak self] in
            guard let self else { return }
            do {
                try await repository.syncMessages(conversationId: conversationId)
                source = "synced"
            } catch {
                source = localMessages.isEmpty ? "empty" : "local_only"
                AppLogger.warning("messaging", "[MessagePaginationManager] Background sync failed: \(error.localizedDescription)")
            }

            let currentMessages = getMessages()
            setHasMoreMessages(currentMessages.count >= self.pageSize)
            self.oldestMessageId = currentMessages.first?.id
        }

        await PerformanceMonitor.shared.record(
            operation: "messaging.conversationOpen",
            duration: Date().timeIntervalSince(loadStart),
            metadata: [
                "source": source,
                "messagesCount": getMessages().count,
                "conversationId": conversationId.uuidString
            ],
            slowThreshold: Constants.Performance.conversationOpenSlowThreshold
        )
    }

    func loadMoreMessages(
        conversationId: UUID,
        messageService: any MessageServiceProtocol,
        repository: MessagingRepository,
        getMessages: @escaping @MainActor () -> [Message],
        getIsLoadingMore: @escaping @MainActor () -> Bool,
        setIsLoadingMore: @escaping @MainActor (Bool) -> Void,
        getHasMoreMessages: @escaping @MainActor () -> Bool,
        setHasMoreMessages: @escaping @MainActor (Bool) -> Void,
        onHydrateReplyContexts: @escaping @MainActor () -> Void
    ) async {
        guard !getIsLoadingMore(), getHasMoreMessages(), let beforeId = oldestMessageId else {
            AppLogger.info("messaging", "[MessagePaginationManager] loadMore skipped")
            return
        }

        setIsLoadingMore(true)
        defer { setIsLoadingMore(false) }

        do {
            let fetched = try await messageService.fetchMessages(
                conversationId: conversationId,
                limit: pageSize,
                beforeMessageId: beforeId
            )
            for msg in fetched {
                try repository.upsertMessage(msg)
            }
            try repository.save(changedConversationIds: Set([conversationId]))
            oldestMessageId = getMessages().first?.id
            setHasMoreMessages(fetched.count >= pageSize)
            onHydrateReplyContexts()
        } catch {
            AppLogger.error("messaging", "Error loading more messages: \(error.localizedDescription)")
        }
    }

    func hydrateReplyContexts(from messages: [Message]) async -> [Message] {
        await Self.buildReplyContexts(from: messages)
    }

    func markConversationReadImmediately(
        conversationId: UUID,
        messages: [Message],
        userId: UUID,
        messageService: any MessageServiceProtocol,
        throttler: Throttler
    ) async {
        guard !isMarkReadInFlight else {
            await scheduleLastSeenHeartbeat(
                conversationId: conversationId,
                userId: userId,
                messageService: messageService,
                throttler: throttler
            )
            return
        }

        let hasUnreadFromOthers = messages.contains { message in
            message.fromId != userId && !message.readBy.contains(userId)
        }
        guard hasUnreadFromOthers else {
            await scheduleLastSeenHeartbeat(
                conversationId: conversationId,
                userId: userId,
                messageService: messageService,
                throttler: throttler
            )
            return
        }

        isMarkReadInFlight = true
        defer { isMarkReadInFlight = false }

        do {
            try await messageService.markAsRead(
                conversationId: conversationId,
                userId: userId,
                updateLastSeen: false
            )
        } catch {
            AppLogger.warning("messaging", "[MessagePaginationManager] markAsRead failed: \(error.localizedDescription)")
        }

        await throttler.run(
            key: "messages.clearBadge.\(conversationId.uuidString)",
            minimumInterval: Constants.Timing.badgeRefreshMinInterval
        ) {
            await BadgeCountManager.shared.clearMessagesBadge(for: conversationId)
        }
        await scheduleLastSeenHeartbeat(
            conversationId: conversationId,
            userId: userId,
            messageService: messageService,
            throttler: throttler
        )
    }

    func scheduleLastSeenHeartbeat(
        conversationId: UUID,
        userId: UUID,
        messageService: any MessageServiceProtocol,
        throttler: Throttler
    ) async {
        await throttler.run(
            key: "messages.lastSeen.\(conversationId.uuidString)",
            minimumInterval: Constants.RateLimits.throttleLastSeen
        ) {
            try? await messageService.updateLastSeen(
                conversationId: conversationId,
                userId: userId
            )
        }
    }

    func insertNewMessage(_ newMessage: Message, into messages: [Message]) -> [Message] {
        guard !messages.contains(where: { $0.id == newMessage.id }) else { return messages }
        var updated = messages
        let idx = Self.insertionIndex(for: newMessage, in: updated)
        updated.insert(newMessage, at: idx)
        return updated
    }

    func applyMessageUpdate(_ message: Message, in messages: [Message]) -> [Message] {
        var updated = messages
        if let index = updated.firstIndex(where: { $0.id == message.id }), index < updated.count {
            updated[index] = message
        }
        return updated
    }

    func applyMessageDelete(_ message: Message, from messages: [Message]) -> [Message] {
        messages.filter { $0.id != message.id }
    }

    nonisolated private static func buildReplyContexts(from messages: [Message]) async -> [Message] {
        let replyParentIds = Set(messages.compactMap { $0.replyToId })
        guard !replyParentIds.isEmpty else { return messages }

        let messagesById = Dictionary(uniqueKeysWithValues: messages.map { ($0.id, $0) })
        let senderIds = Set(replyParentIds.compactMap { messagesById[$0]?.fromId })
        var profilesById: [UUID: Profile] = [:]

        for senderId in senderIds {
            if let profile = await CacheManager.shared.getCachedProfile(id: senderId) {
                profilesById[senderId] = profile
            }
        }

        let finalProfiles = profilesById
        return await MainActor.run { ReplyContextBuilder.applyReplyContexts(messages: messages, profilesById: finalProfiles) }
    }

    nonisolated private static func insertionIndex(for message: Message, in messages: [Message]) -> Int {
        var low = 0
        var high = messages.count
        while low < high {
            let mid = (low + high) / 2
            if messages[mid].createdAt < message.createdAt {
                low = mid + 1
            } else {
                high = mid
            }
        }
        return low
    }
}
