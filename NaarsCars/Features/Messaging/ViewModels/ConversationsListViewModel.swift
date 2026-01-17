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
    private let logger = MessagingLogger.shared
    private var cancellables = Set<AnyCancellable>()
    private let pageSize = 10
    private var currentOffset = 0
    
    // Race condition detection
    private var activeLoadTasks: Set<String> = []
    private var loadAttemptCount: Int = 0
    private var lastLoadStartTime: Date?
    
    // Task management for cancellation
    private var currentLoadTask: Task<Void, Never>?
    
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
        // Cancel any existing load task
        currentLoadTask?.cancel()
        
        // Detect potential race conditions
        if activeLoadTasks.contains("loadConversations") {
            await logger.log("⚠️ RACE CONDITION: loadConversations called while another load is in progress", level: .race)
        }
        
        activeLoadTasks.insert("loadConversations")
        loadAttemptCount += 1
        lastLoadStartTime = Date()
        
        guard let userId = authService.currentUserId else {
            error = .notAuthenticated
            activeLoadTasks.remove("loadConversations")
            currentLoadTask = nil
            return
        }
        
        isLoading = true
        error = nil
        currentOffset = 0
        hasMoreConversations = true
        
        // Create a new task and store it
        currentLoadTask = Task {
            do {
                let fetched = try await messageService.fetchConversations(userId: userId, limit: pageSize, offset: currentOffset)
                
                // Check if task was cancelled
                try Task.checkCancellation()
                
                // Update UI on main actor
                await MainActor.run {
                    self.conversations = fetched
                    self.currentOffset = fetched.count
                    self.hasMoreConversations = fetched.count == pageSize
                }
                
                // Only log if we got unexpected results (0 conversations is suspicious)
                if fetched.isEmpty {
                    await logger.log("⚠️ Loaded 0 conversations (may indicate an issue)", level: .warning)
                }
            } catch is CancellationError {
                // Task was cancelled (view disappeared, etc.) - don't show error
                await logger.log("Load conversations cancelled", level: .warning)
            } catch {
                await MainActor.run {
                    self.error = AppError.processingError(error.localizedDescription)
                }
                await logger.logError(error, context: "loadConversations")
            }
            
            await MainActor.run {
                self.isLoading = false
                self.activeLoadTasks.remove("loadConversations")
                
                // Only log slow operations
                if let startTime = self.lastLoadStartTime {
                    let duration = Date().timeIntervalSince(startTime)
                    if duration > 2.0 {
                        Task {
                            await self.logger.log("🐌 Load took \(String(format: "%.2f", duration))s", level: .performance)
                        }
                    }
                }
            }
        }
        
        // Wait for task to complete
        await currentLoadTask?.value
    }
    
    func loadMoreConversations() async {
        // Detect potential race conditions
        if activeLoadTasks.contains("loadMoreConversations") {
            await logger.log("⚠️ RACE CONDITION: loadMoreConversations called while another pagination load is in progress", level: .race)
            return
        }
        
        guard !isLoadingMore, hasMoreConversations,
              let userId = authService.currentUserId else {
            return
        }
        
        activeLoadTasks.insert("loadMoreConversations")
        isLoadingMore = true
        
        do {
            let fetched = try await messageService.fetchConversations(userId: userId, limit: pageSize, offset: currentOffset)
            self.conversations.append(contentsOf: fetched)
            currentOffset += fetched.count
            hasMoreConversations = fetched.count == pageSize
            
            await logger.log("✅ Loaded \(fetched.count) more conversations (total: \(conversations.count))", level: .success)
        } catch is CancellationError {
            // Task was cancelled - don't show error
            await logger.log("Load more conversations cancelled", level: .warning)
        } catch {
            await logger.logError(error, context: "loadMoreConversations")
            // Don't set error here - just log it
        }
        
        isLoadingMore = false
        activeLoadTasks.remove("loadMoreConversations")
    }
    
    func refreshConversations() async {
        // Removed verbose logging - only errors will be logged via loadConversations
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
                        // Removed verbose logging - only log errors
                        await self?.loadConversations()
                    }
                },
                onUpdate: { [weak self] _ in
                    Task { @MainActor [weak self] in
                        // Removed verbose logging - only log errors
                        await self?.loadConversations()
                    }
                },
                onDelete: { [weak self] _ in
                    Task { @MainActor [weak self] in
                        // Removed verbose logging - only log errors
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
        if conversations.contains(where: { $0.conversation.id == updatedConversation.id }) {
            // Reload to get updated details
            Task {
                await loadConversations()
            }
        }
    }
    
    private func handleConversationDelete(_ deletedConversation: Conversation) {
        conversations.removeAll { $0.conversation.id == deletedConversation.id }
    }
    
    // MARK: - Debug Helpers
    
    /// Get debugging information about the current state
    func getDebugInfo() async -> String {
        var info = """
        === ConversationsListViewModel Debug Info ===
        Conversations loaded: \(conversations.count)
        Is loading: \(isLoading)
        Is loading more: \(isLoadingMore)
        Has more: \(hasMoreConversations)
        Current offset: \(currentOffset)
        Load attempts: \(loadAttemptCount)
        Active tasks: \(activeLoadTasks)
        Error: \(error?.localizedDescription ?? "none")
        
        """
        
        info += await logger.getActiveOperationsSummary()
        return info
    }
}

