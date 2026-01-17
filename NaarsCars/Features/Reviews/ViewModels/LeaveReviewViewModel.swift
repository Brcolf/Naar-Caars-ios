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
    
    private let reviewService = ReviewService.shared
    private let authService = AuthService.shared
    
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
        guard let reviewerId = authService.currentUserId else {
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
                
                guard let compressedData = ImageCompressor.compress(reviewImage, preset: .messageImage) else {
                    throw AppError.processingError("Failed to compress image")
                }
                imageData = compressedData
            }
            
            // Create review
            let review = try await reviewService.createReview(
                requestType: requestType,
                requestId: requestId,
                fulfillerId: fulfillerId,
                reviewerId: reviewerId,
                rating: rating,
                comment: comment.isEmpty ? nil : comment,
                imageData: imageData
            )
            
            return review
        } catch {
            self.error = error as? AppError ?? AppError.unknown(error.localizedDescription)
            throw error
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
            try await reviewService.skipReview(
                requestType: requestType,
                requestId: requestId
            )
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

