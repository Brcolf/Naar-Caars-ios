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
    
    private let conversationId: UUID
    private let messageService: MessageService
    private var searchTask: Task<Void, Never>?
    private var cancellables = Set<AnyCancellable>()
    
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
            return
        }
        
        searchTask?.cancel()
        searchTask = Task { [weak self] in
            guard let self = self else { return }
            self.isSearchingMessages = true
            
            do {
                let results = try await self.messageService.searchMessagesInConversation(
                    query: query,
                    conversationId: self.conversationId,
                    limit: 50
                )
                
                guard !Task.isCancelled else { return }
                
                self.searchResults = results
                // Start at the last (most recent) result
                self.currentSearchIndex = results.isEmpty ? 0 : results.count - 1
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
            searchTask?.cancel()
        }
    }
}
