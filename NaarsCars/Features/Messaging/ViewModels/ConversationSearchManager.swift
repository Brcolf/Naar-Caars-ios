//
//  ConversationSearchManager.swift
//  NaarsCars
//
//  Manages in-conversation search state and logic
//

import Foundation
internal import Combine

/// Manages in-conversation message search state and logic
@MainActor
final class ConversationSearchManager: ObservableObject {
    @Published var searchText: String = ""
    @Published var searchResults: [Message] = []
    @Published var currentSearchIndex: Int = 0
    @Published var isSearchActive: Bool = false
    @Published var isSearchingMessages: Bool = false
    @Published var isLoadingOlderSearchResults: Bool = false
    @Published var canLoadOlderSearchResults: Bool = false
    
    private let conversationId: UUID
    private let messageService: MessageService
    private var searchTask: Task<Void, Never>?
    private var cancellables = Set<AnyCancellable>()
    private let searchPageSize = Constants.PageSizes.searchInConversation
    private var reachedOldestSearchResult = false
    
    init(conversationId: UUID, messageService: MessageService? = nil) {
        self.conversationId = conversationId
        self.messageService = messageService ?? .shared
        setupSearchDebounce()
    }
    
    deinit {
        searchTask?.cancel()
    }
    
    // MARK: - Setup
    
    private func setupSearchDebounce() {
        $searchText
            .debounce(for: .milliseconds(300), scheduler: RunLoop.main)
            .removeDuplicates()
            .sink { [weak self] query in
                guard let self = self else { return }
                if query.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty {
                    self.searchResults = []
                    self.currentSearchIndex = 0
                    self.isSearchingMessages = false
                    self.isLoadingOlderSearchResults = false
                    self.canLoadOlderSearchResults = false
                    self.reachedOldestSearchResult = false
                } else {
                    self.searchInConversation()
                }
            }
            .store(in: &cancellables)
    }
    
    // MARK: - Search
    
    /// Search for messages matching the search text within this conversation
    func searchInConversation() {
        let query = searchText.trimmingCharacters(in: .whitespacesAndNewlines)
        guard !query.isEmpty else {
            searchResults = []
            currentSearchIndex = 0
            canLoadOlderSearchResults = false
            reachedOldestSearchResult = false
            return
        }
        
        searchTask?.cancel()
        searchTask = Task { [weak self] in
            guard let self = self else { return }
            self.isSearchingMessages = true
            self.isLoadingOlderSearchResults = false
            self.canLoadOlderSearchResults = false
            self.reachedOldestSearchResult = false
            
            do {
                let results = try await self.messageService.searchMessagesInConversation(
                    query: query,
                    conversationId: self.conversationId,
                    limit: self.searchPageSize
                )
                
                guard !Task.isCancelled else { return }
                
                self.searchResults = results
                // Start at the last (most recent) result
                self.currentSearchIndex = results.isEmpty ? 0 : results.count - 1
                self.reachedOldestSearchResult = results.count < self.searchPageSize
                self.canLoadOlderSearchResults = !results.isEmpty && !self.reachedOldestSearchResult
            } catch {
                if !Task.isCancelled {
                    AppLogger.error("messaging", "[ConversationSearchManager] In-conversation search failed: \(error.localizedDescription)")
                }
            }
            
            if !Task.isCancelled {
                self.isSearchingMessages = false
            }
        }
    }

    /// Load older matching results (created before the current oldest match).
    func loadOlderSearchResults() {
        guard !isLoadingOlderSearchResults,
              !isSearchingMessages,
              canLoadOlderSearchResults,
              !reachedOldestSearchResult else {
            return
        }

        let query = searchText.trimmingCharacters(in: .whitespacesAndNewlines)
        guard !query.isEmpty, let oldestResultDate = searchResults.first?.createdAt else { return }

        Task { [weak self] in
            guard let self else { return }
            self.isLoadingOlderSearchResults = true
            defer { self.isLoadingOlderSearchResults = false }

            do {
                let olderResults = try await self.messageService.searchMessagesInConversation(
                    query: query,
                    conversationId: self.conversationId,
                    limit: self.searchPageSize,
                    before: oldestResultDate
                )
                guard !Task.isCancelled else { return }

                let existingIds = Set(self.searchResults.map(\.id))
                let uniqueOlder = olderResults.filter { !existingIds.contains($0.id) }

                if !uniqueOlder.isEmpty {
                    self.searchResults.insert(contentsOf: uniqueOlder, at: 0)
                    self.currentSearchIndex += uniqueOlder.count
                }

                self.reachedOldestSearchResult = olderResults.count < self.searchPageSize || uniqueOlder.isEmpty
                self.canLoadOlderSearchResults = !self.reachedOldestSearchResult
            } catch {
                if !Task.isCancelled {
                    AppLogger.warning("messaging", "[ConversationSearchManager] Failed to load older search results: \(error.localizedDescription)")
                }
            }
        }
    }
    
    /// Navigate to the next search result (newer message)
    func nextSearchResult() {
        guard !searchResults.isEmpty else { return }
        currentSearchIndex = (currentSearchIndex + 1) % searchResults.count
    }
    
    /// Navigate to the previous search result (older message)
    func previousSearchResult() {
        guard !searchResults.isEmpty else { return }
        currentSearchIndex = (currentSearchIndex - 1 + searchResults.count) % searchResults.count
    }
    
    /// The currently focused search result message ID
    var currentSearchResultId: UUID? {
        guard !searchResults.isEmpty,
              currentSearchIndex >= 0,
              currentSearchIndex < searchResults.count else { return nil }
        return searchResults[currentSearchIndex].id
    }
    
    /// Toggle search mode on/off
    func toggleSearch() {
        isSearchActive.toggle()
        if !isSearchActive {
            searchText = ""
            searchResults = []
            currentSearchIndex = 0
            isSearchingMessages = false
            isLoadingOlderSearchResults = false
            canLoadOlderSearchResults = false
            reachedOldestSearchResult = false
            searchTask?.cancel()
        }
    }
}
