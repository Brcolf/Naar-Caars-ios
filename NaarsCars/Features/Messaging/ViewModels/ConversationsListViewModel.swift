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
@Observable final class ConversationsListViewModel {
    var conversations: [ConversationWithDetails] = [] {
        didSet { recomputeFilteredConversations() }
    }
    private(set) var filteredConversations: [ConversationWithDetails] = []
    var isLoading: Bool = false
    var isLoadingMore: Bool = false
    var hasMoreConversations: Bool = true
    var error: AppError?

    // MARK: - Search State
    var searchText: String = "" {
        didSet {
            recomputeFilteredConversations()
            scheduleSearchDebounce()
        }
    }
    var searchResults: [MessageSearchResult] = []
    var isSearching: Bool = false
    
    private let conversationService: any ConversationServiceProtocol
    private let profileService: any ProfileServiceProtocol
    private let messageService: any MessageServiceProtocol
    private let repository = MessagingRepository.shared
    private let authService: any AuthServiceProtocol
    private var cancellables = Set<AnyCancellable>()
    private let pageSize = 10
    private var currentOffset = 0
    private var searchTask: Task<Void, Never>?
    private var loadTask: Task<Void, Never>?
    private var lastRemoteSyncAt: Date = .distantPast
    
    init(
        conversationService: any ConversationServiceProtocol = ConversationService.shared,
        profileService: any ProfileServiceProtocol = ProfileService.shared,
        messageService: any MessageServiceProtocol = MessageService.shared,
        authService: any AuthServiceProtocol = AuthService.shared
    ) {
        self.conversationService = conversationService
        self.profileService = profileService
        self.messageService = messageService
        self.authService = authService
        setupUnreadCountObservers()
        setupLocalObservation()
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
        // Filter out conversations the user has soft-deleted, then filter blocked
        let visible = filterBlockedConversations(filterHiddenConversations(updatedConversations))

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

    /// Hide conversations where every other participant is blocked.
    /// Group conversations with at least one non-blocked participant remain visible.
    private func filterBlockedConversations(_ conversations: [ConversationWithDetails]) -> [ConversationWithDetails] {
        conversations.filter { convo in
            let others = convo.otherParticipants
            guard !others.isEmpty else { return true }
            // Keep the conversation if at least one participant is NOT blocked
            return others.contains { !MessageService.shared.isBlocked($0.id) }
        }
    }
    
    private func recomputeFilteredConversations() {
        let newFiltered: [ConversationWithDetails]
        if searchText.isEmpty {
            newFiltered = conversations
        } else {
            let query = searchText.lowercased()
            newFiltered = conversations.filter { convo in
                // Search in conversation title
                if let title = convo.conversation.title?.lowercased(),
                   title.contains(query) {
                    return true
                }
                // Search in participant names
                let participantNames = convo.otherParticipants.map { $0.name.lowercased() }
                if participantNames.contains(where: { $0.contains(query) }) {
                    return true
                }
                // Search in last message
                if let lastMessage = convo.lastMessage?.text.lowercased(),
                   lastMessage.contains(query) {
                    return true
                }
                return false
            }
        }
        // Skip re-assignment if unchanged to avoid redundant objectWillChange emission
        guard newFiltered != filteredConversations else { return }
        filteredConversations = newFiltered
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

        // Un-hide conversations that have unread messages but are currently hidden.
        // This covers messages that arrived while the app was closed.
        if let userId = authService.currentUserId {
            let loadedIds = Set(conversations.map { $0.conversation.id })
            let hiddenIds = conversationService.getHiddenConversationIds(for: userId)
            for detail in details where detail.unreadCount > 0 && !loadedIds.contains(detail.conversationId) {
                if hiddenIds.contains(detail.conversationId) {
                    conversationService.unhideConversationForUser(conversationId: detail.conversationId, userId: userId)
                    AppLogger.info("messaging", "[ConversationsListVM] Unhid conversation \(detail.conversationId) with \(detail.unreadCount) unread")
                    // Trigger a re-sync so the conversation reappears
                    Task { [weak self] in await self?.refreshConversations() }
                    return
                }
            }
        }

        var hasChanges = false
        var changedConversationIds = Set<UUID>()
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
                changedConversationIds.insert(conversationId)
            }
        }

        if hasChanges {
            AppLogger.info("messaging", "[ConversationsListVM] Applied server-side unread counts to list and local storage")
            try? repository.save(changedConversationIds: changedConversationIds)
        }
    }
    
    deinit {}

    /// Call from view onDisappear to cancel in-flight work so VM can tear down safely.
    func stop() {
        AppLogger.info("messaging", "[ConversationsListVM] stop() called; cancelling loadTask and searchTask")
        loadTask?.cancel()
        loadTask = nil
        searchTask?.cancel()
        searchTask = nil
        searchDebounceTask?.cancel()
        searchDebounceTask = nil
    }

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
        
        let now = Date()
        guard now.timeIntervalSince(lastRemoteSyncAt) >= Constants.Timing.messagingListRemoteSyncMinInterval else {
            return
        }
        lastRemoteSyncAt = now

        // 2. Sync from remote in background (stored so we can cancel on disappear)
        loadTask?.cancel()
        loadTask = Task { @MainActor in
            defer { loadTask = nil }
            do {
                try await repository.syncConversations(userId: userId)
                guard !Task.isCancelled else { return }
                let updatedConversations = try repository.getConversations()
                self.applyLocalConversations(updatedConversations, animated: false)
                currentOffset = self.conversations.count
                hasMoreConversations = true // Reset so pagination can continue after sync
                await hydrateProfiles(for: updatedConversations)
            } catch {
                if !Task.isCancelled {
                    AppLogger.error("messaging", "[ConversationsListVM] Error syncing conversations: \(error)")
                }
            }
        }
    }

    private func hydrateProfiles(for conversations: [ConversationWithDetails]) async {
        guard let currentUserId = authService.currentUserId else { return }
        guard !conversations.isEmpty else { return }

        let allOtherParticipantIds = Set(
            conversations.flatMap { conversation in
                (conversation.conversation.participants ?? [])
                    .map(\.userId)
                    .filter { $0 != currentUserId }
            }
        )
        guard !allOtherParticipantIds.isEmpty else { return }

        let profiles: [Profile]
        do {
            profiles = try await profileService.fetchProfiles(userIds: Array(allOtherParticipantIds))
        } catch {
            AppLogger.warning("messaging", "[ConversationsListVM] Batch profile hydration failed: \(error.localizedDescription)")
            return
        }
        let profilesById = Dictionary(uniqueKeysWithValues: profiles.map { ($0.id, $0) })

        var updatedConversations = conversations
        var hasChanges = false
        
        for i in 0..<updatedConversations.count {
            let convWithDetails = updatedConversations[i]
            let participantIds = convWithDetails.conversation.participants?.map { $0.userId } ?? []
            let otherParticipantIds = participantIds.filter { $0 != currentUserId }

            let otherProfiles = otherParticipantIds.compactMap { profilesById[$0] }
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
                AppLogger.info("messaging", "[ConversationsListVM] Loaded \(newConversations.count) more conversations")
            }

            // Always advance the offset to avoid re-fetching the same page
            currentOffset += fetched.count

            // End of list: server returned fewer than requested, OR a full
            // page of duplicates (no forward progress — prevents stuck spinner)
            if fetched.count < pageSize || newConversations.isEmpty {
                hasMoreConversations = false
                AppLogger.info("messaging", "[ConversationsListVM] Reached the end of the conversation list (fetched=\(fetched.count), new=\(newConversations.count), pageSize=\(pageSize))")
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
        lastRemoteSyncAt = .distantPast
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
    
    private var searchDebounceTask: Task<Void, Never>?

    private func scheduleSearchDebounce() {
        searchDebounceTask?.cancel()
        let query = searchText.trimmingCharacters(in: .whitespacesAndNewlines)
        if query.isEmpty {
            searchResults = []
            isSearching = false
            return
        }
        searchDebounceTask = Task { [weak self] in
            try? await Task.sleep(nanoseconds: 300_000_000)
            guard !Task.isCancelled else { return }
            self?.performSearch(query: query)
        }
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
