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
    @Published var totalSavings: Double = 0
    @Published var totalXP: Int = 0
    @Published var isLoading: Bool = false
    @Published var isDeletingAccount: Bool = false
    @Published var error: AppError?
    
    // MARK: - Private Properties
    
    private let profileService: any ProfileServiceProtocol
    private let authService: any AuthServiceProtocol

    init(
        profileService: any ProfileServiceProtocol = ProfileService.shared,
        authService: any AuthServiceProtocol = AuthService.shared
    ) {
        self.profileService = profileService
        self.authService = authService
    }
    
    // MARK: - Public Methods
    
    /// Load profile data for current user
    /// Fetches profile, reviews, invite codes, rating, and count concurrently
    /// On subsequent calls for the same user, returns cached data immediately.
    /// Use `refreshProfile(userId:)` for pull-to-refresh.
    /// - Parameter userId: The current user's ID
    func loadProfile(userId: UUID) async {
        // If we already have data for this user, skip the network fetch.
        // This prevents 6 concurrent RPCs on every tab switch.
        if profile?.id == userId && !reviews.isEmpty {
            return
        }

        isLoading = true
        error = nil
        defer { isLoading = false }

        do {
            // Fetch all data concurrently using async let
            async let profileTask = profileService.fetchProfile(userId: userId)
            async let reviewsTask = profileService.fetchReviews(forUserId: userId)
            async let ratingTask = profileService.calculateAverageRating(userId: userId)
            async let countTask = profileService.fetchFulfilledCount(userId: userId)
            async let savingsTask = profileService.fetchUserTotalSavings(userId: userId)
            async let xpTask = profileService.fetchUserTotalXP(userId: userId)

            let (fetchedProfile, fetchedReviews, fetchedRating, fetchedCount, fetchedSavings, fetchedXP) = try await (
                profileTask,
                reviewsTask,
                ratingTask,
                countTask,
                savingsTask,
                xpTask
            )

            profile = fetchedProfile
            reviews = fetchedReviews
            averageRating = fetchedRating
            fulfilledCount = fetchedCount
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
        await loadProfile(userId: userId)
    }
    
    // MARK: - Account Actions
    
    /// Upload a new avatar for the current user
    /// - Throws: Error from the upload (caller logs and decides UI feedback)
    func uploadAvatar(imageData: Data, userId: UUID) async throws {
        _ = try await profileService.uploadAvatar(imageData: imageData, userId: userId)
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

