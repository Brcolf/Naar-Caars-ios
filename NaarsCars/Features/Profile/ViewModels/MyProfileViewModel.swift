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
    @Published var error: AppError?
    
    // MARK: - Private Properties
    
    private let profileService: any ProfileServiceProtocol

    init(profileService: any ProfileServiceProtocol = ProfileService.shared) {
        self.profileService = profileService
    }
    
    // MARK: - Public Methods
    
    /// Load profile data for current user
    /// Fetches profile, reviews, invite codes, rating, and count concurrently
    /// - Parameter userId: The current user's ID
    func loadProfile(userId: UUID) async {
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
}

