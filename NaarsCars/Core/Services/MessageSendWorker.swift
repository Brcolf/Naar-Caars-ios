//
//  MessageSendWorker.swift
//  NaarsCars
//
//  Durable message send worker that watches for pending messages in SwiftData
//  and sends them with exponential backoff. Survives UI lifecycle.
//

import Foundation
import SwiftData
import Network
internal import Combine

/// Durable actor that watches for messages with status == .sending in SwiftData
/// and attempts to send them via the network with exponential backoff.
actor MessageSendWorker {
    
    // MARK: - Singleton
    
    static let shared = MessageSendWorker()
    
    // MARK: - Private Properties
    
    private var isRunning = false
    private var retryTask: Task<Void, Never>?
    private let networkMonitor = NWPathMonitor()
    private let monitorQueue = DispatchQueue(label: "com.naarscars.sendWorker.network")
    private var isNetworkAvailable = true
    
    // MARK: - Constants
    
    private let initialBackoffDelay: TimeInterval = 1.0
    private let maxBackoffDelay: TimeInterval = 30.0
    private let maxRetryAttempts = 5
    
    // MARK: - Initialization
    
    private init() {}
    
    // MARK: - Public API
    
    /// Start the send worker — begins monitoring for pending messages
    func start() {
        guard !isRunning else { return }
        isRunning = true
        
        // Start network monitoring
        networkMonitor.pathUpdateHandler = { [weak self] path in
            Task { [weak self] in
                await self?.handleNetworkChange(isAvailable: path.status == .satisfied)
            }
        }
        networkMonitor.start(queue: monitorQueue)
        
        // Process any pending messages immediately
        retryTask = Task { [weak self] in
            await self?.processPendingMessages()
        }
        
        Task { @MainActor in
            AppLogger.info("messaging", "[MessageSendWorker] Started")
        }
    }
    
    /// Stop the send worker
    func stop() {
        isRunning = false
        retryTask?.cancel()
        retryTask = nil
        networkMonitor.cancel()
        Task { @MainActor in
            AppLogger.info("messaging", "[MessageSendWorker] Stopped")
        }
    }
    
    /// Notify the worker that new pending messages are available (e.g. after a send)
    func notifyNewPendingMessage() {
        guard isRunning else { return }
        retryTask?.cancel()
        retryTask = Task { [weak self] in
            await self?.processPendingMessages()
        }
    }
    
    // MARK: - Private Methods
    
    private func handleNetworkChange(isAvailable: Bool) {
        let wasUnavailable = !self.isNetworkAvailable
        self.isNetworkAvailable = isAvailable
        
        // When network comes back, retry all pending messages
        if isAvailable && wasUnavailable {
            Task { @MainActor in
                AppLogger.info("messaging", "[MessageSendWorker] Network restored, retrying pending messages")
            }
            retryTask?.cancel()
            retryTask = Task { [weak self] in
                await self?.processPendingMessages()
            }
        }
    }
    
    /// Main processing loop — fetches pending messages from SwiftData and sends them
    private func processPendingMessages() async {
        guard isRunning, !Task.isCancelled else { return }
        
        let pendingMessages = await fetchPendingMessages()
        guard !pendingMessages.isEmpty else { return }
        
        let count = pendingMessages.count
        Task { @MainActor in
            AppLogger.info("messaging", "[MessageSendWorker] Processing \(count) pending message(s)")
        }
        
        for messageInfo in pendingMessages {
            guard isRunning, !Task.isCancelled else { return }
            guard isNetworkAvailable else {
                Task { @MainActor in
                    AppLogger.info("messaging", "[MessageSendWorker] Network unavailable, pausing")
                }
                return
            }
            
            await sendWithBackoff(messageInfo: messageInfo)
        }
    }
    
    /// Attempt to send a single message with exponential backoff
    private func sendWithBackoff(messageInfo: PendingMessageInfo) async {
        var attempt = 0
        var delay = initialBackoffDelay
        
        while attempt < maxRetryAttempts && isRunning && !Task.isCancelled {
            attempt += 1
            
            do {
                try await sendMessage(messageInfo: messageInfo)
                let msgId = messageInfo.id
                let attemptNum = attempt
                Task { @MainActor in
                    AppLogger.info("messaging", "[MessageSendWorker] Sent message \(msgId) on attempt \(attemptNum)")
                }
                return // Success
            } catch {
                if attempt >= maxRetryAttempts {
                    // Mark as failed after all retries exhausted
                    await markMessageFailed(id: messageInfo.id, error: error.localizedDescription)
                    let msgId = messageInfo.id
                    let maxAttempts = maxRetryAttempts
                    let errorDesc = error.localizedDescription
                    Task { @MainActor in
                        AppLogger.error("messaging", "[MessageSendWorker] Message \(msgId) failed after \(maxAttempts) attempts: \(errorDesc)")
                    }
                    return
                }
                
                let attemptNum = attempt
                let msgId = messageInfo.id
                let errorDesc = error.localizedDescription
                let retryDelay = delay
                Task { @MainActor in
                    AppLogger.warning("messaging", "[MessageSendWorker] Attempt \(attemptNum) failed for message \(msgId): \(errorDesc). Retrying in \(retryDelay)s")
                }
                
                // Wait with exponential backoff
                try? await Task.sleep(nanoseconds: UInt64(delay * 1_000_000_000))
                delay = min(delay * 2, maxBackoffDelay)
            }
        }
    }
    
    /// Send a single message via the network
    private func sendMessage(messageInfo: PendingMessageInfo) async throws {
        let fromId = messageInfo.fromId
        let conversationId = messageInfo.conversationId
        
        // Access services on the main actor
        let messageService = await MainActor.run { MessageService.shared }
        let mediaService = await MainActor.run { MessageMediaService.shared }
        
        let sentMessage: Message
        
        switch messageInfo.messageType {
        case .audio:
            // Upload audio if we have a local attachment
            var audioUrl = messageInfo.audioUrl
            if audioUrl == nil, let localPath = messageInfo.localAttachmentPath {
                let audioData = LocalAttachmentStorage.load(path: localPath)
                if let audioData = audioData {
                    audioUrl = try await mediaService.uploadAudioMessage(
                        audioData: audioData,
                        conversationId: conversationId,
                        fromId: fromId
                    )
                }
            }
            guard let finalAudioUrl = audioUrl else {
                throw AppError.processingError("No audio data available for send")
            }
            sentMessage = try await messageService.sendAudioMessage(
                conversationId: conversationId,
                fromId: fromId,
                audioUrl: finalAudioUrl,
                duration: messageInfo.audioDuration ?? 0,
                replyToId: messageInfo.replyToId
            )
            
        case .location:
            guard let lat = messageInfo.latitude, let lon = messageInfo.longitude else {
                throw AppError.processingError("No location data available for send")
            }
            sentMessage = try await messageService.sendLocationMessage(
                conversationId: conversationId,
                fromId: fromId,
                latitude: lat,
                longitude: lon,
                locationName: messageInfo.locationName,
                replyToId: messageInfo.replyToId
            )
            
        default:
            // Text/image message
            var imageUrl = messageInfo.imageUrl
            if imageUrl == nil, let localPath = messageInfo.localAttachmentPath {
                let imageData = LocalAttachmentStorage.load(path: localPath)
                if let imageData = imageData {
                    imageUrl = try await mediaService.uploadMessageImage(
                        imageData: imageData,
                        conversationId: conversationId,
                        fromId: fromId
                    )
                }
            }
            sentMessage = try await messageService.sendMessage(
                conversationId: conversationId,
                fromId: fromId,
                text: messageInfo.text,
                imageUrl: imageUrl,
                replyToId: messageInfo.replyToId
            )
        }
        
        // Replace optimistic message with server-confirmed message in SwiftData
        await replaceOptimisticMessage(localId: messageInfo.id, with: sentMessage, conversationId: conversationId)
        
        // Clean up local attachment
        if let localPath = messageInfo.localAttachmentPath {
            LocalAttachmentStorage.delete(path: localPath)
        }
    }
    
    // MARK: - SwiftData Operations (MainActor)
    
    /// Fetch all pending messages from SwiftData
    @MainActor
    private func fetchPendingMessages() -> [PendingMessageInfo] {
        let repository = MessagingRepository.shared
        guard repository.isConfigured else { return [] }
        
        do {
            let sendingStatus = MessageSendStatus.sending.rawValue
            let descriptor = FetchDescriptor<SDMessage>(
                predicate: #Predicate { $0.status == sendingStatus },
                sortBy: [SortDescriptor(\.createdAt, order: .forward)]
            )
            guard let modelContext = repository.modelContextForWorker else { return [] }
            let sdMessages = try modelContext.fetch(descriptor)
            
            return sdMessages.map { sd in
                PendingMessageInfo(
                    id: sd.id,
                    conversationId: sd.conversationId,
                    fromId: sd.fromId,
                    text: sd.text,
                    imageUrl: sd.imageUrl,
                    audioUrl: sd.audioUrl,
                    audioDuration: sd.audioDuration,
                    latitude: sd.latitude,
                    longitude: sd.longitude,
                    locationName: sd.locationName,
                    replyToId: sd.replyToId,
                    localAttachmentPath: sd.localAttachmentPath,
                    messageType: MessageType(rawValue: sd.messageType) ?? .text
                )
            }
        } catch {
            AppLogger.error("messaging", "[MessageSendWorker] Failed to fetch pending messages: \(error.localizedDescription)")
            return []
        }
    }
    
    /// Mark a message as failed in SwiftData
    @MainActor
    private func markMessageFailed(id: UUID, error: String) {
        do {
            if let sdMessage = try MessagingRepository.shared.fetchSDMessage(id: id) {
                sdMessage.status = MessageSendStatus.failed.rawValue
                sdMessage.syncError = error
                sdMessage.isPending = false
                try MessagingRepository.shared.save(changedConversationIds: Set([sdMessage.conversationId]))
            }
        } catch {
            AppLogger.error("messaging", "[MessageSendWorker] Failed to mark message as failed: \(error.localizedDescription)")
        }
    }
    
    /// Replace an optimistic message with the server-confirmed message
    @MainActor
    private func replaceOptimisticMessage(localId: UUID, with serverMessage: Message, conversationId: UUID) {
        do {
            let repository = MessagingRepository.shared
            repository.deleteMessage(id: localId)
            
            var confirmed = serverMessage
            confirmed.sendStatus = .sent
            try repository.upsertMessage(confirmed)
            try repository.save(changedConversationIds: Set([conversationId]))
        } catch {
            AppLogger.error("messaging", "[MessageSendWorker] Failed to replace optimistic message: \(error.localizedDescription)")
        }
    }
}

// MARK: - Pending Message Info

/// Sendable snapshot of a pending message for the worker actor
struct PendingMessageInfo: Sendable {
    let id: UUID
    let conversationId: UUID
    let fromId: UUID
    let text: String
    let imageUrl: String?
    let audioUrl: String?
    let audioDuration: Double?
    let latitude: Double?
    let longitude: Double?
    let locationName: String?
    let replyToId: UUID?
    let localAttachmentPath: String?
    let messageType: MessageType
}
