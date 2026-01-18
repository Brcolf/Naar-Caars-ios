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
    @Published var isLoadingMore: Bool = false
    @Published var hasMoreConversations: Bool = true
    @Published var error: AppError?
    
    private let messageService = MessageService.shared
    private let authService = AuthService.shared
    private let realtimeManager = RealtimeManager.shared
    private var cancellables = Set<AnyCancellable>()
    private let pageSize = 10
    private var currentOffset = 0
    
    init() {
        setupRealtimeSubscription()
    }
    
    deinit {
        // Use Task.detached to avoid capturing self strongly
        // Capture the channel name string instead of calling the method
        let channelName = "conversations:all"
        Task.detached {
            await RealtimeManager.shared.unsubscribe(channelName: channelName)
        }
    }
    
    func loadConversations() async {
        guard let userId = authService.currentUserId else {
            error = .notAuthenticated
            return
        }
        
        isLoading = true
        error = nil
        currentOffset = 0
        hasMoreConversations = true
        
        do {
            let fetched = try await messageService.fetchConversations(userId: userId, limit: pageSize, offset: currentOffset)
            self.conversations = fetched
            currentOffset = fetched.count
            hasMoreConversations = fetched.count == pageSize
        } catch {
            self.error = AppError.processingError(error.localizedDescription)
            print("🔴 Error loading conversations: \(error.localizedDescription)")
        }
        
        isLoading = false
    }
    
    func loadMoreConversations() async {
        guard !isLoadingMore, hasMoreConversations,
              let userId = authService.currentUserId else {
            return
        }
        
        isLoadingMore = true
        
        do {
            let fetched = try await messageService.fetchConversations(userId: userId, limit: pageSize, offset: currentOffset)
            self.conversations.append(contentsOf: fetched)
            currentOffset += fetched.count
            hasMoreConversations = fetched.count == pageSize
        } catch {
            print("🔴 Error loading more conversations: \(error.localizedDescription)")
            // Don't set error here - just log it
        }
        
        isLoadingMore = false
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

