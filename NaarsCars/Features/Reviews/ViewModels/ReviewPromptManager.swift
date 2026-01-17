//
//  ReviewPromptManager.swift
//  NaarsCars
//
//  Manager for review prompts (30 minutes after request time)
//

import Foundation
internal import Combine

/// Manager for review prompts
/// Checks for pending reviews 30 minutes after request time
@MainActor
final class ReviewPromptManager: ObservableObject {
    
    // MARK: - Singleton
    
    static let shared = ReviewPromptManager()
    
    // MARK: - Published Properties
    
    @Published var pendingPrompt: PendingReviewPrompt?
    
    // MARK: - Private Properties
    
    private let reviewService = ReviewService.shared
    private let authService = AuthService.shared
    
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
}

