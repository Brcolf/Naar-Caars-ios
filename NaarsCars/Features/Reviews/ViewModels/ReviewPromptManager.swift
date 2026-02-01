//
//  ReviewPromptManager.swift
//  NaarsCars
//
//  Manager for review prompts (immediately after event time)
//

import Foundation
internal import Combine

/// Manager for review prompts
/// Checks for pending reviews immediately after event time
@MainActor
final class ReviewPromptManager: ObservableObject {
    
    // MARK: - Singleton
    
    static let shared = ReviewPromptManager()
    
    // MARK: - Published Properties
    
    @Published var pendingPrompt: PendingReviewPrompt?
    
    // MARK: - Private Properties
    
    private let reviewService = ReviewService.shared
    private let authService = AuthService.shared
    private let profileService = ProfileService.shared
    
    // MARK: - Types
    
    struct PendingReviewPrompt: Identifiable {
        let id: UUID
        let requestType: String
        let requestId: UUID
        let requestTitle: String
        let fulfillerId: UUID
        let fulfillerName: String
        
        var requestItemId: UUID {
            return requestId
        }
    }
    
    // MARK: - Initialization
    
    private init() {}
    
    // MARK: - Public Methods
    
    /// Check for pending review prompts
    /// Should be called when app becomes active or user navigates to main tab
    func checkForPendingPrompts() async {
        guard let userId = authService.currentUserId else {
            pendingPrompt = nil
            return
        }
        
        do {
            let prompts = try await reviewService.findPendingReviewPrompts(userId: userId)
            
            // Show first prompt (oldest)
            if let firstPrompt = prompts.first {
                pendingPrompt = PendingReviewPrompt(
                    id: firstPrompt.requestId, // Use requestId as identifier
                    requestType: firstPrompt.requestType,
                    requestId: firstPrompt.requestId,
                    requestTitle: firstPrompt.requestTitle,
                    fulfillerId: firstPrompt.fulfillerId,
                    fulfillerName: firstPrompt.fulfillerName
                )
            } else {
                pendingPrompt = nil
            }
        } catch {
            print("❌ Error checking for review prompts: \(error.localizedDescription)")
            pendingPrompt = nil
        }
    }
    
    /// Clear current prompt (when user submits or skips)
    func clearPrompt() {
        pendingPrompt = nil
    }

    /// Load a specific prompt from a push/deep link
    func loadPrompt(rideId: UUID? = nil, favorId: UUID? = nil) async {
        guard let userId = authService.currentUserId else {
            pendingPrompt = nil
            return
        }
        
        do {
            if let rideId = rideId {
                let ride = try await RideService.shared.fetchRide(id: rideId)
                guard ride.userId == userId, let fulfillerId = ride.claimedBy else { return }
                let fulfillerName = (try? await profileService.fetchProfile(userId: fulfillerId))?.name ?? "Someone"
                
                pendingPrompt = PendingReviewPrompt(
                    id: rideId,
                    requestType: "ride",
                    requestId: rideId,
                    requestTitle: "\(ride.pickup) → \(ride.destination)",
                    fulfillerId: fulfillerId,
                    fulfillerName: fulfillerName
                )
                return
            }
            
            if let favorId = favorId {
                let favor = try await FavorService.shared.fetchFavor(id: favorId)
                guard favor.userId == userId, let fulfillerId = favor.claimedBy else { return }
                let fulfillerName = (try? await profileService.fetchProfile(userId: fulfillerId))?.name ?? "Someone"
                
                pendingPrompt = PendingReviewPrompt(
                    id: favorId,
                    requestType: "favor",
                    requestId: favorId,
                    requestTitle: favor.title,
                    fulfillerId: fulfillerId,
                    fulfillerName: fulfillerName
                )
                return
            }
        } catch {
            print("❌ Error loading review prompt: \(error.localizedDescription)")
            pendingPrompt = nil
        }
    }
}

