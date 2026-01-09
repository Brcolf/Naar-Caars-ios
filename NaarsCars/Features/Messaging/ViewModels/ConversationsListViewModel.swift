//
//  ConversationsListViewModel.swift
//  NaarsCars
//
//  ViewModel for conversations list
//

import Foundation
internal import Combine

/// ViewModel for conversations list
@MainActor
final class ConversationsListViewModel: ObservableObject {
    @Published var conversations: [ConversationWithDetails] = []
    @Published var isLoading: Bool = false
    @Published var error: AppError?
    
    private let messageService = MessageService.shared
    private let authService = AuthService.shared
    private let realtimeManager = RealtimeManager.shared
    private var cancellables = Set<AnyCancellable>()
    
    init() {
        setupRealtimeSubscription()
    }
    
    deinit {
        Task {
            await unsubscribeFromConversations()
        }
    }
    
    func loadConversations() async {
        guard let userId = authService.currentUserId else {
            error = .notAuthenticated
            return
        }
        
        isLoading = true
        error = nil
        
        do {
            self.conversations = try await messageService.fetchConversations(userId: userId)
        } catch {
            self.error = AppError.processingError(error.localizedDescription)
            print("🔴 Error loading conversations: \(error.localizedDescription)")
        }
        
        isLoading = false
    }
    
    func refreshConversations() async {
        guard let userId = authService.currentUserId else { return }
        await CacheManager.shared.invalidateConversations(userId: userId)
        await loadConversations()
    }
    
    private func setupRealtimeSubscription() {
        Task {
            await realtimeManager.subscribe(
                channelName: "conversations:all",
                table: "conversations",
                onInsert: { [weak self] _ in
                    Task { @MainActor [weak self] in
                        await self?.loadConversations()
                    }
                },
                onUpdate: { [weak self] _ in
                    Task { @MainActor [weak self] in
                        await self?.loadConversations()
                    }
                },
                onDelete: { [weak self] _ in
                    Task { @MainActor [weak self] in
                        await self?.loadConversations()
                    }
                }
            )
        }
    }
    
    private func unsubscribeFromConversations() async {
        await realtimeManager.unsubscribe(channelName: "conversations:all")
    }
    
    private func handleNewConversation(_ newConversation: Conversation) {
        // Reload conversations to get full details
        Task {
            await loadConversations()
        }
    }
    
    private func handleConversationUpdate(_ updatedConversation: Conversation) {
        if let index = conversations.firstIndex(where: { $0.conversation.id == updatedConversation.id }) {
            // Reload to get updated details
            Task {
                await loadConversations()
            }
        }
    }
    
    private func handleConversationDelete(_ deletedConversation: Conversation) {
        conversations.removeAll { $0.conversation.id == deletedConversation.id }
    }
}

