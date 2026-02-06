//
//  ConversationsListViewModel.swift
//  NaarsCars
//
//  ViewModel for conversations list
//

import Foundation
import SwiftUI
internal import Combine

/// Result of a message search across conversations
struct MessageSearchResult: Identifiable {
    let id: UUID
    let message: Message
    let conversationId: UUID
    let conversationTitle: String
    
    init(message: Message, conversationId: UUID, conversationTitle: String) {
        self.id = message.id
        self.message = message
        self.conversationId = conversationId
        self.conversationTitle = conversationTitle
    }
}

/// ViewModel for conversations list
@MainActor
final class ConversationsListViewModel: ObservableObject {
    @Published var conversations: [ConversationWithDetails] = []
    @Published var isLoading: Bool = false
    @Published var isLoadingMore: Bool = false
    @Published var hasMoreConversations: Bool = true
    @Published var error: AppError?
    
    // MARK: - Search State
    @Published var searchText: String = ""
    @Published var searchResults: [MessageSearchResult] = []
    @Published var isSearching: Bool = false
    
    private let conversationService = ConversationService.shared
    private let profileService = ProfileService.shared
    private let messageService = MessageService.shared
    private let repository = MessagingRepository.shared
    private let authService = AuthService.shared
    private var cancellables = Set<AnyCancellable>()
    private let pageSize = 10
    private var currentOffset = 0
    private var searchTask: Task<Void, Never>?
    
    init() {
        setupUnreadCountObservers()
        setupLocalObservation()
        setupSearchDebounce()
    }

    private func setupLocalObservation() {
        repository.getConversationsPublisher()
            .sink { [weak self] updatedConversations in
                self?.applyLocalConversations(updatedConversations, animated: false)
            }
            .store(in: &cancellables)
    }

    static func shouldShowLoading(conversations: [ConversationWithDetails]) -> Bool {
        conversations.isEmpty
    }

    func applyLocalConversations(_ updatedConversations: [ConversationWithDetails], animated: Bool = false) {
        // Filter out conversations the user has soft-deleted
        let visible = filterHiddenConversations(updatedConversations)

        let mergedConversations = visible.map { updated in
            guard updated.otherParticipants.isEmpty,
                  let existing = conversations.first(where: { $0.id == updated.id }),
                  !existing.otherParticipants.isEmpty else {
                return updated
            }
            return ConversationWithDetails(
                conversation: updated.conversation,
                lastMessage: updated.lastMessage,
                unreadCount: updated.unreadCount,
                otherParticipants: existing.otherParticipants
            )
        }

        guard mergedConversations != conversations else { return }
        if animated {
            withAnimation(.easeInOut) {
                conversations = mergedConversations
            }
        } else {
            conversations = mergedConversations
        }
    }
    
    /// Exclude conversations the current user has soft-deleted (hidden via UserDefaults).
    private func filterHiddenConversations(_ conversations: [ConversationWithDetails]) -> [ConversationWithDetails] {
        guard let userId = authService.currentUserId else { return conversations }
        let hiddenIds = conversationService.getHiddenConversationIds(for: userId)
        guard !hiddenIds.isEmpty else { return conversations }
        return conversations.filter { !hiddenIds.contains($0.conversation.id) }
    }
    
    private func setupUnreadCountObservers() {
        NotificationCenter.default.publisher(for: .conversationUnreadCountsUpdated)
            .receive(on: RunLoop.main)
            .sink { [weak self] notification in
                guard let self = self,
                      let details = notification.userInfo?["counts"] as? [BadgeCountManager.ConversationCountDetail] else {
                    return
                }
                self.applyUnreadCounts(details)
            }
            .store(in: &cancellables)
    }

    private func applyUnreadCounts(_ details: [BadgeCountManager.ConversationCountDetail]) {
        let countsById = Dictionary(uniqueKeysWithValues: details.map { ($0.conversationId, $0.unreadCount) })
        
        var hasChanges = false
        for index in conversations.indices {
            let conversationId = conversations[index].conversation.id
            let serverCount = countsById[conversationId] ?? 0
            
            if conversations[index].unreadCount != serverCount {
                let existing = conversations[index]
                conversations[index] = ConversationWithDetails(
                    conversation: existing.conversation,
                    lastMessage: existing.lastMessage,
                    unreadCount: serverCount,
                    otherParticipants: existing.otherParticipants
                )
                
                // Update local SwiftData unread count to keep it in sync
                if let sdConv = try? repository.fetchSDConversation(id: conversationId) {
                    sdConv.unreadCount = serverCount
                }
                
                hasChanges = true
            }
        }
        
        if hasChanges {
            AppLogger.info("messaging", "[ConversationsListVM] Applied server-side unread counts to list and local storage")
            try? repository.save()
            // Force a UI refresh
            objectWillChange.send()
        }
    }
    
    deinit {}
    
    func loadConversations() async {
        let showLoading = Self.shouldShowLoading(conversations: conversations)
        if showLoading {
            isLoading = true
            defer { isLoading = false }
        }

        guard let userId = authService.currentUserId else {
            error = .notAuthenticated
            return
        }
        
        error = nil
        
        // 1. Load from local SwiftData immediately
        do {
            let localConversations = try repository.getConversations()
            applyLocalConversations(localConversations, animated: false)
            AppLogger.info("messaging", "[ConversationsListVM] Loaded \(conversations.count) conversations from local storage")
            
            // Hydrate profiles for local conversations
            await hydrateProfiles(for: localConversations)
        } catch {
            AppLogger.warning("messaging", "[ConversationsListVM] Error loading local conversations: \(error)")
        }
        
        // 2. Sync from remote in background
        Task {
            do {
                try await repository.syncConversations(userId: userId)
                // Re-fetch local data after sync to update UI
                let updatedConversations = try repository.getConversations()
                self.applyLocalConversations(updatedConversations, animated: false)
                
                // Set the pagination offset to match what we have loaded
                currentOffset = self.conversations.count
                
                // Hydrate profiles for updated conversations
                await hydrateProfiles(for: updatedConversations)
            } catch {
                AppLogger.error("messaging", "[ConversationsListVM] Error syncing conversations: \(error)")
            }
        }
    }

    private func hydrateProfiles(for conversations: [ConversationWithDetails]) async {
        guard let currentUserId = authService.currentUserId else { return }
        
        var updatedConversations = conversations
        var hasChanges = false
        
        for i in 0..<updatedConversations.count {
            let convWithDetails = updatedConversations[i]
            let participantIds = convWithDetails.conversation.participants?.map { $0.userId } ?? []
            let otherParticipantIds = participantIds.filter { $0 != currentUserId }
            
            var otherProfiles: [Profile] = []
            for userId in otherParticipantIds {
                if let profile = try? await profileService.fetchProfile(userId: userId) {
                    otherProfiles.append(profile)
                }
            }
            
            if !otherProfiles.isEmpty {
                updatedConversations[i] = ConversationWithDetails(
                    conversation: convWithDetails.conversation,
                    lastMessage: convWithDetails.lastMessage,
                    unreadCount: convWithDetails.unreadCount,
                    otherParticipants: otherProfiles
                )
                hasChanges = true
            }
        }
        
        if hasChanges {
            applyLocalConversations(updatedConversations, animated: false)
        }
    }
    
    func loadMoreConversations() async {
        guard !isLoadingMore, hasMoreConversations,
              let userId = authService.currentUserId else {
            return
        }
        
        isLoadingMore = true
        
        do {
            AppLogger.info("messaging", "[ConversationsListVM] Fetching more conversations at offset \(currentOffset)")
            let fetched = try await conversationService.fetchConversations(userId: userId, limit: pageSize, offset: currentOffset)
            
            // Filter out duplicates to prevent UI glitches
            let existingIds = Set(self.conversations.map { $0.conversation.id })
            let newConversations = fetched.filter { !existingIds.contains($0.conversation.id) }
            
            if !newConversations.isEmpty {
                self.conversations.append(contentsOf: newConversations)
                currentOffset += fetched.count 
                AppLogger.info("messaging", "[ConversationsListVM] Loaded \(newConversations.count) more conversations. New offset: \(currentOffset)")
            } 
            
            // IMPORTANT: Only mark as reached end if the server actually returned fewer than requested
            if fetched.count < pageSize {
                hasMoreConversations = false
                AppLogger.info("messaging", "[ConversationsListVM] Reached the end of the conversation list (fetched \(fetched.count) < \(pageSize))")
            }
        } catch {
            // Don't show error if task was cancelled
            if Task.isCancelled || error is CancellationError || error.localizedDescription.lowercased().contains("cancel") {
                AppLogger.info("messaging", "Load more conversations task was cancelled, ignoring error")
            } else {
                AppLogger.error("messaging", "Error loading more conversations: \(error.localizedDescription)")
                // Don't set error here - just log it
            }
        }
        
        isLoadingMore = false
    }
    
    func refreshConversations() async {
        guard let _ = authService.currentUserId else { return }
        // Reset pagination state so loadMore works correctly after refresh
        currentOffset = 0
        hasMoreConversations = true
        await loadConversations()
    }

    func deleteConversation(_ conversation: Conversation) async {
        // Optimistically remove from the list for responsive UI
        let snapshot = conversations
        
        withAnimation {
            conversations.removeAll { $0.conversation.id == conversation.id }
        }
        
        do {
            try await repository.deleteConversation(id: conversation.id)
            AppLogger.info("messaging", "[ConversationsListVM] Soft-deleted conversation \(conversation.id)")
        } catch {
            // Restore the list on failure so the user can retry
            withAnimation {
                conversations = snapshot
            }
            self.error = AppError.processingError("Failed to delete conversation: \(error.localizedDescription)")
            AppLogger.error("messaging", "[ConversationsListVM] Failed to delete conversation: \(error.localizedDescription)")
        }
    }
    
    // MARK: - Search
    
    private func setupSearchDebounce() {
        $searchText
            .debounce(for: .milliseconds(300), scheduler: RunLoop.main)
            .removeDuplicates()
            .sink { [weak self] query in
                guard let self = self else { return }
                if query.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty {
                    self.searchResults = []
                    self.isSearching = false
                } else {
                    self.performSearch(query: query)
                }
            }
            .store(in: &cancellables)
    }
    
    private func performSearch(query: String) {
        searchTask?.cancel()
        searchTask = Task { [weak self] in
            guard let self = self else { return }
            self.isSearching = true
            
            guard let userId = self.authService.currentUserId else {
                self.isSearching = false
                return
            }
            
            do {
                let messages = try await self.messageService.searchMessages(query: query, userId: userId, limit: 30)
                
                guard !Task.isCancelled else { return }
                
                // Map messages to search results with conversation titles
                let results = messages.map { message -> MessageSearchResult in
                    let title = self.conversationTitle(for: message.conversationId)
                    return MessageSearchResult(
                        message: message,
                        conversationId: message.conversationId,
                        conversationTitle: title
                    )
                }
                
                self.searchResults = results
            } catch {
                if !Task.isCancelled {
                    AppLogger.error("messaging", "[ConversationsListVM] Search failed: \(error.localizedDescription)")
                }
            }
            
            if !Task.isCancelled {
                self.isSearching = false
            }
        }
    }
    
    /// Resolve a conversation title from the loaded conversations list
    private func conversationTitle(for conversationId: UUID) -> String {
        if let detail = conversations.first(where: { $0.conversation.id == conversationId }) {
            // Use group title if available
            if let title = detail.conversation.title, !title.isEmpty {
                return title
            }
            // Otherwise use participant names
            if !detail.otherParticipants.isEmpty {
                return detail.otherParticipants.map { $0.name }.joined(separator: ", ")
            }
        }
        return "Conversation"
    }
    
    // MARK: - Debug Support
    
    /// Get debug information about the current state
    func getDebugInfo() -> String {
        var info = """
        === Conversations List Debug Info ===
        Loaded Conversations: \(conversations.count)
        Is Loading: \(isLoading)
        Is Loading More: \(isLoadingMore)
        Has More: \(hasMoreConversations)
        Current Offset: \(currentOffset)
        Page Size: \(pageSize)
        """
        
        if let error = error {
            info += "\nError: \(error.localizedDescription)"
        }
        
        if !conversations.isEmpty {
            info += "\n\nFirst 5 Conversations:"
            for (index, conv) in conversations.prefix(5).enumerated() {
                info += "\n  \(index + 1). ID: \(conv.conversation.id)"
                info += "\n     Participants: \(conv.otherParticipants.count)"
                info += "\n     Last Message: \(conv.lastMessage?.text.prefix(30) ?? "None")"
            }
        }
        
        return info
    }
}


