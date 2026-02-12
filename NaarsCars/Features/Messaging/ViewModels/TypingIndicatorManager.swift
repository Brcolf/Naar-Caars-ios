//
//  TypingIndicatorManager.swift
//  NaarsCars
//
//  Manages typing indicator realtime observation and status updates
//

import Foundation
internal import Combine

/// Manages typing indicator realtime observation and status updates for a conversation
@MainActor
final class TypingIndicatorManager: ObservableObject {
    @Published var typingUsers: [TypingUser] = []
    
    private let conversationId: UUID
    private let messageService: MessageService
    private let authService: AuthService
    private let realtimeManager: RealtimeManager
    private var typingDebounceTask: Task<Void, Never>?
    private var typingSignalTask: Task<Void, Never>?
    private var typingRefreshTask: Task<Void, Never>?
    private var isObservingTyping = false
    private var lastTypingSignal: Date = .distantPast

    private var typingChannelName: String {
        "typing:\(conversationId.uuidString)"
    }
    
    init(
        conversationId: UUID,
        messageService: MessageService? = nil,
        authService: AuthService? = nil,
        realtimeManager: RealtimeManager? = nil
    ) {
        self.conversationId = conversationId
        self.messageService = messageService ?? .shared
        self.authService = authService ?? .shared
        self.realtimeManager = realtimeManager ?? .shared
    }
    
    deinit {
        typingDebounceTask?.cancel()
        typingSignalTask?.cancel()
        typingRefreshTask?.cancel()
    }
    
    // MARK: - Observation
    
    /// Start realtime observation for typing users in this conversation
    func startTypingObservation() {
        guard !isObservingTyping else { return }
        isObservingTyping = true

        Task { [weak self] in
            guard let self else { return }
            await self.realtimeManager.subscribe(
                channelName: self.typingChannelName,
                table: "typing_indicators",
                filter: "conversation_id=eq.\(self.conversationId.uuidString)",
                onInsert: { [weak self] _ in
                    Task { @MainActor in
                        self?.scheduleTypingUsersRefresh()
                    }
                },
                onUpdate: { [weak self] _ in
                    Task { @MainActor in
                        self?.scheduleTypingUsersRefresh()
                    }
                },
                onDelete: { [weak self] _ in
                    Task { @MainActor in
                        self?.scheduleTypingUsersRefresh()
                    }
                }
            )
            await self.refreshTypingUsers()
        }
    }
    
    /// Stop realtime observation for typing users
    func stopTypingObservation() {
        guard isObservingTyping else { return }
        isObservingTyping = false
        typingRefreshTask?.cancel()
        typingRefreshTask = nil
        typingUsers = []

        Task { [weak self] in
            guard let self else { return }
            await self.realtimeManager.unsubscribe(channelName: self.typingChannelName)
        }

        // Clear own typing status when leaving
        Task { [weak self] in
            guard let self = self,
                  let userId = self.authService.currentUserId else { return }
            await self.messageService.clearTypingStatus(conversationId: self.conversationId, userId: userId)
        }
    }
    
    // MARK: - Typing Status
    
    /// Signal that the current user is typing (debounced)
    func userDidType() {
        guard let userId = authService.currentUserId else { return }
        
        let now = Date()
        // Only send typing signal if enough time has elapsed since the previous signal.
        guard now.timeIntervalSince(lastTypingSignal) >= Constants.Timing.typingSignalThreshold else { return }
        typingSignalTask?.cancel()
        typingSignalTask = Task { [weak self] in
            try? await Task.sleep(nanoseconds: 150_000_000)
            guard let self, !Task.isCancelled else { return }
            self.lastTypingSignal = Date()
            await self.messageService.setTypingStatus(conversationId: self.conversationId, userId: userId)
        }
        
        // Schedule auto-clear after 5 seconds of no typing
        typingDebounceTask?.cancel()
        typingDebounceTask = Task { [weak self] in
            try? await Task.sleep(nanoseconds: Constants.Timing.typingAutoClearNanoseconds)
            guard let self = self, !Task.isCancelled else { return }
            await self.messageService.clearTypingStatus(conversationId: self.conversationId, userId: userId)
        }
    }
    
    /// Clear own typing status (e.g. after sending a message)
    func clearOwnTypingStatus() {
        guard let userId = authService.currentUserId else { return }
        typingDebounceTask?.cancel()
        typingSignalTask?.cancel()
        lastTypingSignal = .distantPast
        Task {
            await messageService.clearTypingStatus(conversationId: conversationId, userId: userId)
        }
    }
    
    // MARK: - Private
    
    private func scheduleTypingUsersRefresh() {
        typingRefreshTask?.cancel()
        typingRefreshTask = Task { [weak self] in
            try? await Task.sleep(nanoseconds: Constants.Timing.debounceNanoseconds)
            guard let self, !Task.isCancelled else { return }
            await self.refreshTypingUsers()
        }
    }

    private func refreshTypingUsers() async {
        let users = await messageService.fetchTypingUsers(conversationId: conversationId)
        if users != typingUsers {
            typingUsers = users
        }
    }
}
