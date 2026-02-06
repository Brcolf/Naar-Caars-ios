//
//  TypingIndicatorManager.swift
//  NaarsCars
//
//  Manages typing indicator poll timer and status updates
//

import Foundation
internal import Combine

/// Manages typing indicator polling and status updates for a conversation
@MainActor
final class TypingIndicatorManager: ObservableObject {
    @Published var typingUsers: [TypingUser] = []
    
    private let conversationId: UUID
    private let messageService: MessageService
    private let authService: AuthService
    private var typingPollTimer: Timer?
    private var typingDebounceTask: Task<Void, Never>?
    private var lastTypingSignal: Date = .distantPast
    
    init(conversationId: UUID, messageService: MessageService = .shared, authService: AuthService = .shared) {
        self.conversationId = conversationId
        self.messageService = messageService
        self.authService = authService
    }
    
    deinit {
        typingPollTimer?.invalidate()
        typingDebounceTask?.cancel()
    }
    
    // MARK: - Observation
    
    /// Start polling for typing users in this conversation
    func startTypingObservation() {
        // Poll every 3 seconds for typing status
        typingPollTimer?.invalidate()
        typingPollTimer = Timer.scheduledTimer(withTimeInterval: 3.0, repeats: true) { [weak self] _ in
            Task { [weak self] in
                await self?.refreshTypingUsers()
            }
        }
        // Fetch immediately on start
        Task { await refreshTypingUsers() }
    }
    
    /// Stop polling for typing users
    func stopTypingObservation() {
        typingPollTimer?.invalidate()
        typingPollTimer = nil
        typingUsers = []
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
        // Only send typing signal if at least 2 seconds since last signal
        guard now.timeIntervalSince(lastTypingSignal) >= 2.0 else { return }
        lastTypingSignal = now
        
        Task {
            await messageService.setTypingStatus(conversationId: conversationId, userId: userId)
        }
        
        // Schedule auto-clear after 5 seconds of no typing
        typingDebounceTask?.cancel()
        typingDebounceTask = Task { [weak self] in
            try? await Task.sleep(nanoseconds: 5_000_000_000)
            guard let self = self, !Task.isCancelled else { return }
            await self.messageService.clearTypingStatus(conversationId: self.conversationId, userId: userId)
        }
    }
    
    /// Clear own typing status (e.g. after sending a message)
    func clearOwnTypingStatus() {
        guard let userId = authService.currentUserId else { return }
        typingDebounceTask?.cancel()
        lastTypingSignal = .distantPast
        Task {
            await messageService.clearTypingStatus(conversationId: conversationId, userId: userId)
        }
    }
    
    // MARK: - Private
    
    private func refreshTypingUsers() async {
        let users = await messageService.fetchTypingUsers(conversationId: conversationId)
        typingUsers = users
    }
}
