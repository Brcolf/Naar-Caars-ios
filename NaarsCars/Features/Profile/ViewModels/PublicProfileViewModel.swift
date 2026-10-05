//
//  PublicProfileViewModel.swift
//  NaarsCars
//
//  View model for viewing other users' profiles
//

import Foundation
import SwiftUI
internal import Combine

/// View model for viewing public profiles
@MainActor
final class PublicProfileViewModel: ObservableObject {
    
    // MARK: - Published Properties
    
    @Published var profile: Profile?
    @Published var reviews: [Review] = []
    @Published var averageRating: Double?
    @Published var fulfilledCount: Int = 0
    @Published var isLoading: Bool = false
    @Published var error: AppError?
    @Published var isBlocking: Bool = false
    @Published var didBlock: Bool = false
    
    // MARK: - Private Properties
    
    private let profileService: any ProfileServiceProtocol
    private let messageService: any MessageServiceProtocol
    private let conversationService: any ConversationServiceProtocol

    init(
        profileService: any ProfileServiceProtocol = ProfileService.shared,
        messageService: any MessageServiceProtocol = MessageService.shared,
        conversationService: any ConversationServiceProtocol = ConversationService.shared
    ) {
        self.profileService = profileService
        self.messageService = messageService
        self.conversationService = conversationService
    }
    
    // MARK: - Public Methods
    
    /// Load profile data for a user
    /// Checks cache before fetching
    /// - Parameter userId: The user ID to load
    func loadProfile(userId: UUID) async {
        isLoading = true
        error = nil
        defer { isLoading = false }
        
        do {
            // Check cache first
            if let cached = await CacheManager.shared.getCachedProfile(id: userId) {
                profile = cached
            } else {
                profile = try await profileService.fetchProfile(userId: userId)
            }
            
            // Fetch additional data concurrently
            async let reviewsTask = profileService.fetchReviews(forUserId: userId)
            async let ratingTask = profileService.calculateAverageRating(userId: userId)
            async let countTask = profileService.fetchFulfilledCount(userId: userId)
            
            let (fetchedReviews, fetchedRating, fetchedCount) = try await (
                reviewsTask,
                ratingTask,
                countTask
            )
            
            reviews = fetchedReviews
            averageRating = fetchedRating
            fulfilledCount = fetchedCount
            
        } catch {
            self.error = error as? AppError ?? AppError.unknown(error.localizedDescription)
        }
    }
    
    // MARK: - Block / Message
    
    /// Seed `didBlock` from the locally cached blocked-user set
    func refreshBlockedStatus(userId: UUID) {
        didBlock = messageService.isBlocked(userId)
    }
    
    /// Block `userId` on behalf of `currentUserId`. Throws on failure (caller shows the alert).
    func blockUser(currentUserId: UUID, userId: UUID) async throws {
        isBlocking = true
        defer { isBlocking = false }
        try await messageService.blockUser(
            blockerId: currentUserId,
            blockedId: userId,
            reason: "Blocked from profile"
        )
        didBlock = true
    }
    
    /// Find or create the direct conversation with `otherUserId`.
    /// - Returns: The conversation ID, or nil on failure (logged)
    func openDirectConversation(currentUserId: UUID, otherUserId: UUID) async -> UUID? {
        do {
            let conversation = try await conversationService.getOrCreateDirectConversation(
                userId: currentUserId,
                otherUserId: otherUserId
            )
            return conversation.id
        } catch {
            AppLogger.error("profile", "Error creating conversation: \(error.localizedDescription)")
            return nil
        }
    }
}

