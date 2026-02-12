//
//  MessageSendManager.swift
//  NaarsCars
//
//  Send/edit/unsend/retry workflow for conversation messages
//

import Foundation
import UIKit
internal import Combine

/// Extracted send/edit/unsend/retry logic for conversation detail.
@MainActor
final class MessageSendManager: ObservableObject {
    private let messageService: MessageService
    private let mediaService: MessageMediaService
    private let reactionService: MessageReactionService
    private let authService: AuthService
    private let repository: MessagingRepository

    init(
        messageService: MessageService = .shared,
        mediaService: MessageMediaService = .shared,
        reactionService: MessageReactionService = .shared,
        authService: AuthService = .shared,
        repository: MessagingRepository = .shared
    ) {
        self.messageService = messageService
        self.mediaService = mediaService
        self.reactionService = reactionService
        self.authService = authService
        self.repository = repository
    }

    func sendMessage(
        conversationId: UUID,
        messageText: String,
        image: UIImage?,
        replyToId: UUID? = nil,
        setMessageText: @escaping @MainActor (String) -> Void,
        setError: @escaping @MainActor (AppError?) -> Void
    ) async {
        let sendStart = Date()
        guard (!messageText.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty || image != nil),
              let fromId = authService.currentUserId else {
            return
        }

        let text = messageText.trimmingCharacters(in: .whitespacesAndNewlines)
        setMessageText("")
        HapticManager.lightImpact()

        var localPath: String? = nil
        if let image = image, let imageData = image.resizedForUpload(maxDimension: 1920).jpegData(compressionQuality: 0.7) {
            localPath = LocalAttachmentStorage.save(data: imageData, extension: "jpg")
        }

        let localId = UUID()
        let optimisticMessage = Message(
            id: localId,
            conversationId: conversationId,
            fromId: fromId,
            text: text,
            createdAt: Date(),
            replyToId: replyToId,
            sendStatus: .sending,
            localAttachmentPath: localPath
        )

        do {
            try repository.upsertMessage(optimisticMessage)
            try repository.save(changedConversationIds: Set([conversationId]))
        } catch {
            AppLogger.error("messaging", "Failed to persist optimistic message: \(error.localizedDescription)")
        }

        await PerformanceMonitor.shared.record(
            operation: "messaging.send.localVisible",
            duration: Date().timeIntervalSince(sendStart),
            metadata: [
                "conversationId": conversationId.uuidString,
                "hasImage": image != nil,
                "reply": replyToId != nil
            ]
        )

        var imageUrl: String? = nil
        if let image = image, let imageData = image.resizedForUpload(maxDimension: 1920).jpegData(compressionQuality: 0.7) {
            do {
                imageUrl = try await mediaService.uploadMessageImage(
                    imageData: imageData,
                    conversationId: conversationId,
                    fromId: fromId
                )
            } catch {
                updateMessageStatus(id: localId, conversationId: conversationId, status: .failed, syncError: "Failed to upload image: \(error.localizedDescription)")
                HapticManager.error()
                setError(AppError.processingError("Failed to upload image: \(error.localizedDescription)"))
                return
            }
        }

        do {
            let sentMessage = try await messageService.sendMessage(
                conversationId: conversationId,
                fromId: fromId,
                text: text,
                imageUrl: imageUrl,
                replyToId: replyToId
            )

            replaceOptimisticMessage(localId: localId, conversationId: conversationId, with: sentMessage)
            if let localPath = localPath {
                LocalAttachmentStorage.delete(path: localPath)
            }
            await PerformanceMonitor.shared.record(
                operation: "messaging.send.serverAccepted",
                duration: Date().timeIntervalSince(sendStart),
                metadata: [
                    "conversationId": conversationId.uuidString,
                    "hasImage": image != nil,
                    "reply": replyToId != nil
                ],
                slowThreshold: Constants.Performance.messageSendServerAcceptSlowThreshold
            )
        } catch {
            updateMessageStatus(id: localId, conversationId: conversationId, status: .failed, syncError: error.localizedDescription)
            HapticManager.error()
            setError(AppError.processingError(error.localizedDescription))
        }
    }

    func sendAudioMessage(
        conversationId: UUID,
        audioURL: URL,
        duration: Double,
        replyToId: UUID? = nil,
        setError: @escaping @MainActor (AppError?) -> Void
    ) async {
        guard let fromId = authService.currentUserId else { return }

        let localPath: String?
        do {
            let audioData = try await Self.loadAudioData(from: audioURL)
            localPath = LocalAttachmentStorage.save(data: audioData, extension: "m4a")
        } catch {
            setError(AppError.processingError("Failed to read audio: \(error.localizedDescription)"))
            return
        }

        let localId = UUID()
        let optimisticMessage = Message(
            id: localId,
            conversationId: conversationId,
            fromId: fromId,
            messageType: .audio,
            replyToId: replyToId,
            audioDuration: duration,
            sendStatus: .sending,
            localAttachmentPath: localPath
        )

        do {
            try repository.upsertMessage(optimisticMessage)
            try repository.save(changedConversationIds: Set([conversationId]))
        } catch {
            AppLogger.error("messaging", "Failed to persist optimistic audio message: \(error.localizedDescription)")
        }

        do {
            let audioData = try await Self.loadAudioData(from: audioURL)
            let uploadedUrl = try await mediaService.uploadAudioMessage(
                audioData: audioData,
                conversationId: conversationId,
                fromId: fromId
            )
            let sentMessage = try await messageService.sendAudioMessage(
                conversationId: conversationId,
                fromId: fromId,
                audioUrl: uploadedUrl,
                duration: duration,
                replyToId: replyToId
            )
            replaceOptimisticMessage(localId: localId, conversationId: conversationId, with: sentMessage)
            if let localPath = localPath {
                LocalAttachmentStorage.delete(path: localPath)
            }
            try? FileManager.default.removeItem(at: audioURL)
        } catch {
            updateMessageStatus(id: localId, conversationId: conversationId, status: .failed, syncError: error.localizedDescription)
            setError(AppError.processingError("Failed to send audio: \(error.localizedDescription)"))
        }
    }

    func sendLocationMessage(
        conversationId: UUID,
        latitude: Double,
        longitude: Double,
        locationName: String?,
        replyToId: UUID? = nil,
        setError: @escaping @MainActor (AppError?) -> Void
    ) async {
        guard let fromId = authService.currentUserId else { return }

        let localId = UUID()
        let optimisticMessage = Message(
            id: localId,
            conversationId: conversationId,
            fromId: fromId,
            text: locationName ?? "Shared location",
            messageType: .location,
            replyToId: replyToId,
            latitude: latitude,
            longitude: longitude,
            locationName: locationName,
            sendStatus: .sending
        )

        do {
            try repository.upsertMessage(optimisticMessage)
            try repository.save(changedConversationIds: Set([conversationId]))
        } catch {
            AppLogger.error("messaging", "Failed to persist optimistic location message: \(error.localizedDescription)")
        }

        do {
            let sentMessage = try await messageService.sendLocationMessage(
                conversationId: conversationId,
                fromId: fromId,
                latitude: latitude,
                longitude: longitude,
                locationName: locationName,
                replyToId: replyToId
            )
            replaceOptimisticMessage(localId: localId, conversationId: conversationId, with: sentMessage)
        } catch {
            updateMessageStatus(id: localId, conversationId: conversationId, status: .failed, syncError: error.localizedDescription)
            setError(AppError.processingError("Failed to send location: \(error.localizedDescription)"))
        }
    }

    func editMessage(
        newContent: String,
        editingMessage: Message?,
        getMessages: @escaping @MainActor () -> [Message],
        setMessages: @escaping @MainActor ([Message]) -> Void,
        setError: @escaping @MainActor (AppError?) -> Void
    ) async {
        guard let editMsg = editingMessage else { return }
        let trimmed = newContent.trimmingCharacters(in: .whitespacesAndNewlines)
        guard !trimmed.isEmpty else { return }

        var currentMessages = getMessages()
        if let index = currentMessages.firstIndex(where: { $0.id == editMsg.id }) {
            currentMessages[index].text = trimmed
            currentMessages[index].editedAt = Date()
            setMessages(currentMessages)
        }

        do {
            try await messageService.updateMessageContent(messageId: editMsg.id, newContent: trimmed)
        } catch {
            var rollbackMessages = getMessages()
            if let index = rollbackMessages.firstIndex(where: { $0.id == editMsg.id }) {
                rollbackMessages[index].text = editMsg.text
                rollbackMessages[index].editedAt = editMsg.editedAt
                setMessages(rollbackMessages)
            }
            setError(AppError.processingError("Failed to edit message: \(error.localizedDescription)"))
        }
    }

    func unsendMessage(
        id: UUID,
        getMessages: @escaping @MainActor () -> [Message],
        setMessages: @escaping @MainActor ([Message]) -> Void,
        setError: @escaping @MainActor (AppError?) -> Void
    ) async {
        var currentMessages = getMessages()
        guard let index = currentMessages.firstIndex(where: { $0.id == id }) else { return }
        let originalMessage = currentMessages[index]
        currentMessages[index].text = ""
        currentMessages[index].deletedAt = Date()
        setMessages(currentMessages)

        do {
            try await messageService.unsendMessage(messageId: id)
        } catch {
            var rollbackMessages = getMessages()
            if let revertIndex = rollbackMessages.firstIndex(where: { $0.id == id }) {
                rollbackMessages[revertIndex].text = originalMessage.text
                rollbackMessages[revertIndex].deletedAt = originalMessage.deletedAt
                setMessages(rollbackMessages)
            }
            setError(AppError.processingError("Failed to unsend message: \(error.localizedDescription)"))
        }
    }

    func retryMessage(
        id: UUID,
        conversationId: UUID,
        messages: [Message],
        setError: @escaping @MainActor (AppError?) -> Void
    ) async {
        guard let message = messages.first(where: { $0.id == id }), message.sendStatus == .failed else { return }
        updateMessageStatus(id: id, conversationId: conversationId, status: .sending, syncError: nil)

        do {
            var imageUrl: String? = message.imageUrl
            if imageUrl == nil, let localPath = message.localAttachmentPath,
               let data = LocalAttachmentStorage.load(path: localPath),
               let fromId = authService.currentUserId {
                imageUrl = try await mediaService.uploadMessageImage(
                    imageData: data,
                    conversationId: conversationId,
                    fromId: fromId
                )
            }
            guard let fromId = authService.currentUserId else { return }

            let sentMessage: Message
            if message.isAudioMessage, let localPath = message.localAttachmentPath,
               let audioData = LocalAttachmentStorage.load(path: localPath) {
                let uploadedUrl = try await mediaService.uploadAudioMessage(
                    audioData: audioData,
                    conversationId: conversationId,
                    fromId: fromId
                )
                sentMessage = try await messageService.sendAudioMessage(
                    conversationId: conversationId,
                    fromId: fromId,
                    audioUrl: uploadedUrl,
                    duration: message.audioDuration ?? 0,
                    replyToId: message.replyToId
                )
            } else if message.isLocationMessage, let lat = message.latitude, let lon = message.longitude {
                sentMessage = try await messageService.sendLocationMessage(
                    conversationId: conversationId,
                    fromId: fromId,
                    latitude: lat,
                    longitude: lon,
                    locationName: message.locationName,
                    replyToId: message.replyToId
                )
            } else {
                sentMessage = try await messageService.sendMessage(
                    conversationId: conversationId,
                    fromId: fromId,
                    text: message.text,
                    imageUrl: imageUrl,
                    replyToId: message.replyToId
                )
            }

            replaceOptimisticMessage(localId: id, conversationId: conversationId, with: sentMessage)
            if let localPath = message.localAttachmentPath {
                LocalAttachmentStorage.delete(path: localPath)
            }
        } catch {
            updateMessageStatus(id: id, conversationId: conversationId, status: .failed, syncError: error.localizedDescription)
            setError(AppError.processingError(error.localizedDescription))
        }
    }

    func dismissFailedMessage(id: UUID, conversationId: UUID) {
        do {
            if let sdMessage = try repository.fetchSDMessage(id: id),
               let localPath = sdMessage.localAttachmentPath {
                LocalAttachmentStorage.delete(path: localPath)
            }
            repository.deleteMessage(id: id)
            try repository.save(changedConversationIds: Set([conversationId]))
        } catch {
            AppLogger.error("messaging", "Failed to dismiss message from SwiftData: \(error.localizedDescription)")
        }
    }

    func addReaction(
        messageId: UUID,
        reaction: String,
        messages: [Message],
        setMessages: @escaping @MainActor ([Message]) -> Void,
        setError: @escaping @MainActor (AppError?) -> Void
    ) async {
        guard let userId = authService.currentUserId else { return }
        guard let index = messages.firstIndex(where: { $0.id == messageId }) else { return }

        let previousReactions = messages[index].reactions
        var updated = messages
        var updatedReactions = updated[index].reactions ?? MessageReactions()
        var userIds = updatedReactions.reactions[reaction] ?? []
        if !userIds.contains(userId) {
            userIds.append(userId)
        }
        for key in updatedReactions.reactions.keys where key != reaction {
            updatedReactions.reactions[key]?.removeAll { $0 == userId }
            if updatedReactions.reactions[key]?.isEmpty == true {
                updatedReactions.reactions.removeValue(forKey: key)
            }
        }
        updatedReactions.reactions[reaction] = userIds
        updated[index].reactions = updatedReactions
        setMessages(updated)

        do {
            try await reactionService.addReaction(messageId: messageId, userId: userId, reaction: reaction)
        } catch {
            var rollback = messages
            if let revertIndex = rollback.firstIndex(where: { $0.id == messageId }) {
                rollback[revertIndex].reactions = previousReactions
                setMessages(rollback)
            }
            setError(AppError.processingError(error.localizedDescription))
        }
    }

    func removeReaction(
        messageId: UUID,
        messages: [Message],
        setMessages: @escaping @MainActor ([Message]) -> Void,
        setError: @escaping @MainActor (AppError?) -> Void
    ) async {
        guard let userId = authService.currentUserId else { return }
        guard let index = messages.firstIndex(where: { $0.id == messageId }) else { return }

        let previousReactions = messages[index].reactions
        var updated = messages
        if var updatedReactions = updated[index].reactions {
            for key in updatedReactions.reactions.keys {
                updatedReactions.reactions[key]?.removeAll { $0 == userId }
                if updatedReactions.reactions[key]?.isEmpty == true {
                    updatedReactions.reactions.removeValue(forKey: key)
                }
            }
            updated[index].reactions = updatedReactions.reactions.isEmpty ? nil : updatedReactions
            setMessages(updated)
        }

        do {
            try await reactionService.removeReaction(messageId: messageId, userId: userId)
        } catch {
            var rollback = messages
            if let revertIndex = rollback.firstIndex(where: { $0.id == messageId }) {
                rollback[revertIndex].reactions = previousReactions
                setMessages(rollback)
            }
            setError(AppError.processingError(error.localizedDescription))
        }
    }

    private func updateMessageStatus(id: UUID, conversationId: UUID, status: MessageSendStatus, syncError: String?) {
        do {
            if let sdMessage = try repository.fetchSDMessage(id: id) {
                sdMessage.status = status.rawValue
                sdMessage.syncError = syncError
                if status == .sending {
                    sdMessage.isPending = true
                } else if status == .failed {
                    sdMessage.isPending = false
                }
                try repository.save(changedConversationIds: Set([conversationId]))
            }
        } catch {
            AppLogger.error("messaging", "Failed to update message status: \(error.localizedDescription)")
        }
    }

    private func replaceOptimisticMessage(localId: UUID, conversationId: UUID, with serverMessage: Message) {
        do {
            repository.deleteMessage(id: localId)
            var confirmed = serverMessage
            confirmed.sendStatus = .sent
            try repository.upsertMessage(confirmed)
            try repository.save(changedConversationIds: Set([conversationId]))
        } catch {
            AppLogger.error("messaging", "Failed to replace optimistic message: \(error.localizedDescription)")
        }
    }

    nonisolated private static func loadAudioData(from url: URL) async throws -> Data {
        try await Task.detached(priority: .userInitiated) {
            try Data(contentsOf: url)
        }.value
    }
}
