//
//  MyProfileViewModel.swift
//  NaarsCars
//
//  View model for current user's profile view
//

import Foundation
import SwiftUI
internal import Combine

/// View model for managing current user's profile data
@MainActor
final class MyProfileViewModel: ObservableObject {
    
    // MARK: - Published Properties
    
    @Published var profile: Profile?
    @Published var reviews: [Review] = []
    @Published var averageRating: Double?
    @Published var fulfilledCount: Int = 0
    @Published var reviewCount: Int = 0
    @Published var totalSavings: Double = 0
    @Published var totalXP: Int = 0
    @Published var isLoading: Bool = false
    @Published var isDeletingAccount: Bool = false
    @Published var error: AppError?
    
    // MARK: - Private Properties
    
    private let profileService: any ProfileServiceProtocol
    private let authService: any AuthServiceProtocol
    /// nil reads `CommunityContext.shared` when needed (it is main-actor isolated).
    private let communityContext: CommunityContext?
    private let communityAdminService: any CommunityAdminServiceProtocol

    init(
        profileService: any ProfileServiceProtocol = ProfileService.shared,
        authService: any AuthServiceProtocol = AuthService.shared,
        communityContext: CommunityContext? = nil,
        communityAdminService: any CommunityAdminServiceProtocol = CommunityService.shared
    ) {
        self.profileService = profileService
        self.authService = authService
        self.communityContext = communityContext
        self.communityAdminService = communityAdminService
    }
    
    // MARK: - Public Methods
    
    /// Load profile data for current user
    /// Fetches profile, reviews, invite codes, rating, and count concurrently
    /// On subsequent calls for the same user, returns cached data immediately.
    /// Use `refreshProfile(userId:)` for pull-to-refresh.
    /// - Parameter userId: The current user's ID
    /// - Parameter force: Reload even when data for this user is already loaded. Used after the
    ///   user's own change (pull-to-refresh, profile edit, new photo); without it those paths
    ///   hit the tab-switch guard and showed stale data.
    func loadProfile(userId: UUID, force: Bool = false) async {
        // If we already have data for this user, skip the network fetch.
        // This prevents 6 concurrent RPCs on every tab switch.
        if !force && profile?.id == userId && !reviews.isEmpty {
            return
        }

        isLoading = true
        error = nil
        defer { isLoading = false }

        do {
            // Fetch all data concurrently using async let
            async let profileTask = profileService.fetchProfile(userId: userId)
            async let reviewsTask = profileService.fetchReviews(forUserId: userId)
            async let statsTask = profileService.fetchProfileStats(userId: userId)
            async let savingsTask = profileService.fetchUserTotalSavings(userId: userId)
            async let xpTask = profileService.fetchUserTotalXP(userId: userId)

            let (fetchedProfile, fetchedReviews, stats, fetchedSavings, fetchedXP) = try await (
                profileTask,
                reviewsTask,
                statsTask,
                savingsTask,
                xpTask
            )

            profile = fetchedProfile
            reviews = fetchedReviews
            averageRating = stats.averageRating
            fulfilledCount = stats.fulfilledCount
            reviewCount = stats.reviewCount
            totalSavings = fetchedSavings
            totalXP = fetchedXP

        } catch {
            self.error = error as? AppError ?? AppError.unknown(error.localizedDescription)
        }
    }
    
    /// Refresh profile data (for pull-to-refresh)
    /// - Parameter userId: The current user's ID
    func refreshProfile(userId: UUID) async {
        // Invalidate cache first
        if let profileId = profile?.id {
            await CacheManager.shared.invalidateProfile(id: profileId)
        }
        
        // Reload data
        await loadProfile(userId: userId, force: true)
    }
    
    // MARK: - Account Actions
    
    /// Upload a new avatar for the current user
    /// - Throws: Error from the upload (caller logs and decides UI feedback)
    func uploadAvatar(imageData: Data, userId: UUID) async throws {
        // The upload only stores the file. The profile row has to point at the returned URL
        // (it carries a cache-buster), or the new photo never appears anywhere.
        let avatarUrl = try await profileService.uploadAvatar(imageData: imageData, userId: userId)
        try await profileService.updateProfile(
            userId: userId,
            name: nil,
            phoneNumber: nil,
            car: nil,
            avatarUrl: avatarUrl,
            shouldUpdateAvatar: true
        )
    }
    
    /// Names of the communities deleting this account closes (decision A3): the ones this user
    /// owns alone with no unbanned co-owner or admin to take over. Shown before the final confirmation; the server
    /// applies A3 whatever the client shows, so a failure here never blocks deletion.
    func communitiesClosedByDeletion() async -> [String] {
        guard let userId = authService.currentUserId else { return [] }
        let memberships = (communityContext ?? CommunityContext.shared).memberships
        let service = communityAdminService
        let profiles = profileService
        let closed = await AccountDeletionCommunityCheck.communitiesClosed(
            byDeleting: userId,
            memberships: memberships,
            fetchActiveMembers: { communityId in
                try await service.fetchCommunityMembers(
                    communityId: communityId,
                    status: .active,
                    limit: Constants.Community.membersPageSize,
                    offset: 0
                )
            },
            fetchUnbannedMemberIds: { communityId, candidates in
                // search_community_members leaves out banned accounts (and accounts blocked either way,
                // which only makes the warning show where it need not). One found candidate is enough.
                for candidate in candidates {
                    let found = try await profiles.searchCommunityMembers(
                        query: candidate.name,
                        communityId: communityId,
                        limit: Constants.Community.successorSearchLimit
                    )
                    if found.contains(where: { $0.id == candidate.id }) {
                        return [candidate.id]
                    }
                }
                return []
            }
        )
        return closed.map(\.name)
    }

    /// Delete the current user's account (App Store requirement — keep reachable).
    /// - Returns: `false` when there is no signed-in user (nothing was attempted), `true` on success
    /// - Throws: Error from the deletion (caller shows the failure alert)
    @discardableResult
    func deleteAccount() async throws -> Bool {
        guard let userId = authService.currentUserId else {
            return false
        }

        isDeletingAccount = true
        defer { isDeletingAccount = false }

        do {
            try await profileService.deleteAccount(userId: userId)
            return true
        } catch {
            AppLogger.error("profile", "Error deleting account: \(error.localizedDescription)")
            throw error
        }
    }
}

