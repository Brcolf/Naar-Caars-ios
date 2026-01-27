//
//  ConversationsListViewModel.swift
//  NaarsCars
//
//  ViewModel for conversations list
//

import Foundation
import UIKit
import SwiftUI
internal import Combine

/// ViewModel for conversations list
@MainActor
final class ConversationsListViewModel: ObservableObject {
    @Published var conversations: [ConversationWithDetails] = []
    @Published var isLoading: Bool = false
    @Published var isLoadingMore: Bool = false
    @Published var hasMoreConversations: Bool = true
    @Published var error: AppError?
    @Published var latestToast: InAppMessageToast?
    
    private let messageService = MessageService.shared
    private let profileService = ProfileService.shared
    private let repository = MessagingRepository.shared
    private let authService = AuthService.shared
    private var cancellables = Set<AnyCancellable>()
    private let pageSize = 10
    private var currentOffset = 0
    private var isMessagesTabActive = false
    private var activeConversationId: UUID?
    
    init() {
        setupThreadVisibilityObservers()
        setupUnreadCountObservers()
        setupLocalObservation()
    }

    private func setupLocalObservation() {
        repository.getConversationsPublisher()
            .sink { [weak self] updatedConversations in
                withAnimation(.easeInOut) {
                    self?.conversations = updatedConversations
                }
            }
            .store(in: &cancellables)
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
            print("✅ [ConversationsListVM] Applied server-side unread counts to list and local storage")
            try? repository.save()
            // Force a UI refresh
            objectWillChange.send()
        }
    }
    
    deinit {}
    
    func loadConversations() async {
        guard let userId = authService.currentUserId else {
            error = .notAuthenticated
            return
        }
        
        isLoading = true
        error = nil
        
        // 1. Load from local SwiftData immediately
        do {
            let localConversations = try repository.getConversations()
            self.conversations = localConversations
            print("📱 [ConversationsListVM] Loaded \(conversations.count) conversations from local storage")
            
            // Hydrate profiles for local conversations
            await hydrateProfiles(for: localConversations)
        } catch {
            print("⚠️ [ConversationsListVM] Error loading local conversations: \(error)")
        }
        
        // 2. Sync from remote in background
        Task {
            do {
                try await repository.syncConversations(userId: userId)
                // Re-fetch local data after sync to update UI
                let updatedConversations = try repository.getConversations()
                self.conversations = updatedConversations
                
                // Hydrate profiles for updated conversations
                await hydrateProfiles(for: updatedConversations)
            } catch {
                print("🔴 [ConversationsListVM] Error syncing conversations: \(error)")
            }
        }
        
        isLoading = false
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
            self.conversations = updatedConversations
        }
    }
    
    func loadMoreConversations() async {
        guard !isLoadingMore, hasMoreConversations,
              let userId = authService.currentUserId else {
            return
        }
        
        isLoadingMore = true
        
        do {
            print("🔄 [ConversationsListVM] Fetching more conversations at offset \(currentOffset)")
            let fetched = try await messageService.fetchConversations(userId: userId, limit: pageSize, offset: currentOffset)
            
            // Filter out duplicates to prevent UI glitches
            let existingIds = Set(self.conversations.map { $0.conversation.id })
            let newConversations = fetched.filter { !existingIds.contains($0.conversation.id) }
            
            if !newConversations.isEmpty {
                self.conversations.append(contentsOf: newConversations)
                currentOffset += fetched.count 
                print("✅ [ConversationsListVM] Loaded \(newConversations.count) more conversations. New offset: \(currentOffset)")
            } 
            
            // IMPORTANT: Only mark as reached end if the server actually returned fewer than requested
            if fetched.count < pageSize {
                hasMoreConversations = false
                print("ℹ️ [ConversationsListVM] Reached the end of the conversation list (fetched \(fetched.count) < \(pageSize))")
            }
        } catch {
            // Don't show error if task was cancelled
            if Task.isCancelled || error is CancellationError || error.localizedDescription.lowercased().contains("cancel") {
                print("ℹ️ Load more conversations task was cancelled, ignoring error")
            } else {
                print("🔴 Error loading more conversations: \(error.localizedDescription)")
                // Don't set error here - just log it
            }
        }
        
        isLoadingMore = false
    }
    
    func refreshConversations() async {
        guard let userId = authService.currentUserId else { return }
        // (Cache invalidation removed as part of SwiftData migration)
        await loadConversations()
    }

    func deleteConversation(_ conversation: Conversation) async {
        do {
            try await repository.deleteConversation(id: conversation.id)
            // Local observation will update the list automatically
        } catch {
            self.error = AppError.processingError("Failed to delete conversation: \(error.localizedDescription)")
        }
    }
    
    
    func setMessagesTabActive(_ isActive: Bool) {
        isMessagesTabActive = isActive
        if !isActive {
            latestToast = nil
        }
    }

    private func setupThreadVisibilityObservers() {
        NotificationCenter.default.publisher(for: .messageThreadDidAppear)
            .compactMap { $0.userInfo?["conversationId"] as? UUID }
            .sink { [weak self] conversationId in
                self?.activeConversationId = conversationId
                self?.latestToast = nil
            }
            .store(in: &cancellables)

        NotificationCenter.default.publisher(for: .messageThreadDidDisappear)
            .sink { [weak self] _ in
                self?.activeConversationId = nil
            }
            .store(in: &cancellables)
    }

    private func updateToastIfNeeded(for message: Message, in conversation: ConversationWithDetails) {
        guard UIApplication.shared.applicationState == .active else {
            print("ℹ️ [ConversationsListVM] Toast suppressed (app not active)")
            return
        }
        guard isMessagesTabActive else {
            print("ℹ️ [ConversationsListVM] Toast suppressed (Messages tab inactive)")
            return
        }
        guard activeConversationId == nil else {
            print("ℹ️ [ConversationsListVM] Toast suppressed (thread active)")
            return
        }

        let sender = conversation.otherParticipants.first(where: { $0.id == message.fromId })
        let senderName = sender?.name ?? "Someone"
        let senderAvatarUrl = sender?.avatarUrl

        latestToast = InAppMessageToast(
            id: message.id,
            conversationId: message.conversationId,
            messageId: message.id,
            senderName: senderName,
            senderAvatarUrl: senderAvatarUrl,
            messagePreview: toastPreviewText(for: message),
            receivedAt: Date()
        )
        print("✅ [ConversationsListVM] Showing in-app toast for \(message.conversationId)")
    }

    private func toastPreviewText(for message: Message) -> String {
        if message.isAudioMessage {
            return "Voice message"
        }
        if message.isLocationMessage {
            return message.locationName ?? "Shared location"
        }
        if message.imageUrl != nil && message.text.isEmpty {
            return "Photo"
        }
        return message.text
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

struct InAppMessageToast: Identifiable, Equatable {
    let id: UUID
    let conversationId: UUID
    let messageId: UUID
    let senderName: String
    let senderAvatarUrl: String?
    let messagePreview: String
    let receivedAt: Date
}

extension Notification.Name {
    static let messageThreadDidAppear = Notification.Name("messageThreadDidAppear")
    static let messageThreadDidDisappear = Notification.Name("messageThreadDidDisappear")
}

