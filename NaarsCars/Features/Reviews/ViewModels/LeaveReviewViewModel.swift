//
//  LeaveReviewViewModel.swift
//  NaarsCars
//
//  View model for leaving a review
//

import Foundation
import SwiftUI
internal import Combine
import PhotosUI

struct LeaveReviewDependencies {
    let currentUserId: () -> UUID?
    let createReview: (
        _ requestType: String,
        _ requestId: UUID,
        _ fulfillerId: UUID,
        _ reviewerId: UUID,
        _ rating: Int,
        _ comment: String?,
        _ imageData: Data?
    ) async throws -> Review
    let skipReview: (_ requestType: String, _ requestId: UUID) async throws -> Void
    let refreshBadges: (String) async -> Void
    let fetchReviewPostId: (UUID) async -> UUID?
    let navigateToTownHall: (UUID) -> Void

    @MainActor
    static func live() -> LeaveReviewDependencies {
        live(
            authService: AuthService.shared,
            reviewService: ReviewService.shared,
            badgeManager: BadgeCountManager.shared
        )
    }

    @MainActor
    static func live(
        authService: any AuthServiceProtocol,
        reviewService: any ReviewServiceProtocol,
        badgeManager: any BadgeCountManaging
    ) -> LeaveReviewDependencies {
        return LeaveReviewDependencies(
            currentUserId: { authService.currentUserId },
            createReview: { requestType, requestId, fulfillerId, reviewerId, rating, comment, imageData in
                try await reviewService.createReview(
                    requestType: requestType,
                    requestId: requestId,
                    fulfillerId: fulfillerId,
                    reviewerId: reviewerId,
                    rating: rating,
                    comment: comment,
                    imageData: imageData
                )
            },
            skipReview: { requestType, requestId in
                try await reviewService.skipReview(
                    requestType: requestType,
                    requestId: requestId
                )
            },
            refreshBadges: { reason in
                await badgeManager.refreshAllBadges(reason: reason)
            },
            fetchReviewPostId: { reviewId in
                do {
                    return try await TownHallService.shared.fetchPostIdForReview(reviewId: reviewId)
                } catch {
                    AppLogger.error("townhall", "Failed to fetch review post ID: \(error.localizedDescription)")
                    return nil
                }
            },
            navigateToTownHall: { postId in
                NotificationCenter.default.post(
                    name: NSNotification.Name("navigateToTownHall"),
                    object: nil,
                    userInfo: [
                        "postId": postId,
                        "mode": NavigationCoordinator.TownHallNavigationTarget.Mode.openComments.rawValue
                    ]
                )
            }
        )
    }
}

/// View model for leaving a review
@MainActor
final class LeaveReviewViewModel: ObservableObject {
    
    // MARK: - Published Properties
    
    @Published var rating: Int = 0
    @Published var comment: String = ""
    @Published var selectedPhoto: PhotosPickerItem?
    @Published var reviewImage: UIImage?
    @Published var isSubmitting: Bool = false
    @Published var isUploadingImage: Bool = false
    @Published var error: AppError?
    
    // MARK: - Private Properties
    
    private let dependencies: LeaveReviewDependencies

    nonisolated init(dependencies: LeaveReviewDependencies) {
        self.dependencies = dependencies
    }
    
    convenience init() {
        self.init(dependencies: .live())
    }
    
    // MARK: - Public Methods
    
    /// Submit review
    /// - Parameters:
    ///   - requestType: "ride" or "favor"
    ///   - requestId: Request ID
    ///   - fulfillerId: User ID of the fulfiller
    /// - Returns: Created review if successful
    /// - Throws: AppError if submission fails
    func submitReview(
        requestType: String,
        requestId: UUID,
        fulfillerId: UUID
    ) async throws -> Review {
        guard let reviewerId = dependencies.currentUserId() else {
            throw AppError.notAuthenticated
        }
        
        // Validate rating
        guard rating >= 1 && rating <= 5 else {
            throw AppError.invalidInput("Please select a rating")
        }
        
        isSubmitting = true
        error = nil
        defer { isSubmitting = false }
        
        do {
            // Compress image if selected
            var imageData: Data? = nil
            if let reviewImage = reviewImage {
                isUploadingImage = true
                defer { isUploadingImage = false }
                
                guard let compressedData = await ImageCompressor.compressAsync(reviewImage, preset: .messageImage) else {
                    throw AppError.processingError("Failed to compress image")
                }
                imageData = compressedData
            }
            
            // Create review
            let review = try await dependencies.createReview(
                requestType,
                requestId,
                fulfillerId,
                reviewerId,
                rating,
                comment.isEmpty ? nil : comment,
                imageData
            )

            await dependencies.refreshBadges("reviewSubmitted")
            return review
        } catch {
            self.error = error as? AppError ?? AppError.unknown(error.localizedDescription)
            throw error
        }
    }

    func navigateToReviewPost(reviewId: UUID) async {
        let maxAttempts = 4
        for attempt in 0..<maxAttempts {
            if let postId = await dependencies.fetchReviewPostId(reviewId) {
                dependencies.navigateToTownHall(postId)
                return
            }

            if attempt < maxAttempts - 1 {
                try? await Task.sleep(nanoseconds: 300_000_000)
            }
        }
    }
    
    /// Skip review
    /// - Parameters:
    ///   - requestType: "ride" or "favor"
    ///   - requestId: Request ID
    /// - Throws: AppError if skip fails
    func skipReview(
        requestType: String,
        requestId: UUID
    ) async throws {
        isSubmitting = true
        error = nil
        defer { isSubmitting = false }
        
        do {
            try await dependencies.skipReview(requestType, requestId)
        } catch {
            self.error = error as? AppError ?? AppError.unknown(error.localizedDescription)
            throw error
        }
    }
    
    /// Handle photo selection
    /// - Parameter item: Selected PhotosPickerItem
    func handlePhotoSelection(_ item: PhotosPickerItem?) async {
        guard let item = item else {
            reviewImage = nil
            return
        }
        
        isUploadingImage = true
        defer { isUploadingImage = false }
        
        // Load image data
        guard let data = try? await item.loadTransferable(type: Data.self),
              let uiImage = UIImage(data: data) else {
            error = AppError.unknown("Failed to load image")
            return
        }
        
        // Store image (will be compressed on submit)
        reviewImage = uiImage
    }
}

