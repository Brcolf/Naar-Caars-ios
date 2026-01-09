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
    
    // MARK: - Private Properties
    
    private let profileService = ProfileService.shared
    
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
}

