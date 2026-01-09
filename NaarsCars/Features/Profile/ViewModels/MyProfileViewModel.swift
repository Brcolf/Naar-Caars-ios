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
    @Published var currentInviteCode: InviteCodeWithInvitee?
    @Published var inviteStats: InviteStats?
    @Published var averageRating: Double?
    @Published var fulfilledCount: Int = 0
    @Published var isLoading: Bool = false
    @Published var error: AppError?
    
    // MARK: - Private Properties
    
    private let profileService = ProfileService.shared
    private let inviteService = InviteService.shared
    private let rateLimiter = RateLimiter.shared
    
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
            async let inviteCodeTask = inviteService.fetchCurrentInviteCode(userId: userId)
            async let inviteStatsTask = inviteService.getInviteStats(userId: userId)
            async let ratingTask = profileService.calculateAverageRating(userId: userId)
            async let countTask = profileService.fetchFulfilledCount(userId: userId)
            
            // Wait for all tasks to complete
            let (fetchedProfile, fetchedReviews, fetchedCode, fetchedStats, fetchedRating, fetchedCount) = try await (
                profileTask,
                reviewsTask,
                inviteCodeTask,
                inviteStatsTask,
                ratingTask,
                countTask
            )
            
            // Update published properties
            profile = fetchedProfile
            reviews = fetchedReviews
            currentInviteCode = fetchedCode
            inviteStats = fetchedStats
            averageRating = fetchedRating
            fulfilledCount = fetchedCount
            
        } catch {
            self.error = error as? AppError ?? AppError.unknown(error.localizedDescription)
        }
    }
    
    /// Generate a new invite code for the user (with invitation statement)
    /// - Parameters:
    ///   - userId: The current user's ID
    ///   - inviteStatement: Statement explaining who they're inviting and why
    func generateInviteCode(userId: UUID, inviteStatement: String) async {
        do {
            let newCode = try await inviteService.generateInviteCode(
                userId: userId,
                inviteStatement: inviteStatement
            )
            
            // Convert to InviteCodeWithInvitee (no invitee yet since it's new)
            let enrichedCode = InviteCodeWithInvitee(
                inviteCode: newCode,
                inviteeName: nil
            )
            
            // Replace current code (only one at a time)
            currentInviteCode = enrichedCode
            
            // Refresh stats
            inviteStats = try await inviteService.getInviteStats(userId: userId)
        } catch let appError as AppError {
            self.error = appError
        } catch {
            self.error = AppError.unknown(error.localizedDescription)
        }
    }
    
    /// Generate a bulk invite code (admin only)
    /// - Parameter userId: The admin user's ID
    func generateBulkInviteCode(userId: UUID) async {
        do {
            let newCode = try await inviteService.generateBulkInviteCode(userId: userId)
            
            // Convert to InviteCodeWithInvitee
            let enrichedCode = InviteCodeWithInvitee(
                inviteCode: newCode,
                inviteeName: nil
            )
            
            // For admins, bulk codes are separate from regular codes
            // We could store this separately if needed, but for now just return it
            // The UI will handle showing bulk codes differently
            currentInviteCode = enrichedCode
        } catch let appError as AppError {
            self.error = appError
        } catch {
            self.error = AppError.unknown(error.localizedDescription)
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

