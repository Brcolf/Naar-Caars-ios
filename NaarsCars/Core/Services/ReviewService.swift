//
//  ReviewService.swift
//  NaarsCars
//
//  Service for review operations
//

import Foundation
import Supabase
import UIKit

/// Service for review operations
/// Handles creating reviews, uploading images, and posting to Town Hall
final class ReviewService {
    
    // MARK: - Singleton
    
    static let shared = ReviewService()
    
    // MARK: - Private Properties
    
    private let supabase = SupabaseService.shared.client
    private let townHallService = TownHallService.shared
    private let profileService = ProfileService.shared
    
    // MARK: - Initialization
    
    private init() {}
    
    // MARK: - Create Review
    
    /// Create a review for a completed request
    /// - Parameters:
    ///   - requestType: "ride" or "favor"
    ///   - requestId: Request ID
    ///   - fulfillerId: User ID of the fulfiller (claimer)
    ///   - reviewerId: User ID of the reviewer (poster)
    ///   - rating: Rating (1-5)
    ///   - comment: Optional review comment
    ///   - imageData: Optional image data to upload
    /// - Returns: Created review
    /// - Throws: AppError if creation fails
    func createReview(
        requestType: String,
        requestId: UUID,
        fulfillerId: UUID,
        reviewerId: UUID,
        rating: Int,
        comment: String?,
        imageData: Data? = nil
    ) async throws -> Review {
        // Validate rating
        guard rating >= 1 && rating <= 5 else {
            throw AppError.invalidInput("Rating must be between 1 and 5")
        }
        
        // Upload image if provided
        var imageUrl: String? = nil
        if let imageData = imageData {
            imageUrl = try await uploadReviewImage(imageData: imageData, reviewId: UUID())
        }
        
        // Create review record
        let newReview = Review(
            reviewerId: reviewerId,
            fulfillerId: fulfillerId,
            rideId: requestType == "ride" ? requestId : nil,
            favorId: requestType == "favor" ? requestId : nil,
            rating: rating,
            comment: comment?.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty == false ? comment?.trimmingCharacters(in: .whitespacesAndNewlines) : nil,
            imageUrl: imageUrl
        )
        
        // Insert review
        let response = try await supabase
            .from("reviews")
            .insert(newReview)
            .select()
            .single()
            .execute()
        
        // Decode created review
        let decoder = createDecoder()
        let review: Review = try decoder.decode(Review.self, from: response.data)
        
        // Mark request as reviewed
        let tableName = requestType == "ride" ? "rides" : "favors"
        try await supabase
            .from(tableName)
            .update(["reviewed": true])
            .eq("id", value: requestId.uuidString)
            .execute()
        
        // Town Hall post is created automatically by the handle_new_review database trigger
        
        // Clear any pending review_request notifications for this request
        await NotificationService.shared.markReviewRequestAsRead(
            requestType: requestType,
            requestId: requestId
        )
        
        AppLogger.info("reviews", "Created review: \(review.id)")
        return review
    }
    
    /// Skip a review (mark as skipped)
    /// - Parameters:
    ///   - requestType: "ride" or "favor"
    ///   - requestId: Request ID
    /// - Throws: AppError if skip fails
    func skipReview(
        requestType: String,
        requestId: UUID
    ) async throws {
        let tableName = requestType == "ride" ? "rides" : "favors"
        
        // Mark review as skipped
        let updates: [String: AnyCodable] = [
            "review_skipped": AnyCodable(true),
            "review_skipped_at": AnyCodable(ISO8601DateFormatter().string(from: Date()))
        ]
        
        try await supabase
            .from(tableName)
            .update(updates)
            .eq("id", value: requestId.uuidString)
            .execute()

        // Clear any pending review_request notifications for this request
        await NotificationService.shared.markReviewRequestAsRead(
            requestType: requestType,
            requestId: requestId
        )
        
        AppLogger.info("reviews", "Skipped review for request: \(requestId)")
    }
    
    /// Check if user can still review a request (within 7 days of completion)
    /// - Parameters:
    ///   - requestType: "ride" or "favor"
    ///   - requestId: Request ID
    /// - Returns: True if can still review, false otherwise
    func canStillReview(
        requestType: String,
        requestId: UUID
    ) async throws -> Bool {
        let tableName = requestType == "ride" ? "rides" : "favors"
        
        // Fetch request to check completion time
        let response = try await supabase
            .from(tableName)
            .select("updated_at, review_skipped_at")
            .eq("id", value: requestId.uuidString)
            .single()
            .execute()
        
        struct RequestInfo: Codable {
            let updatedAt: Date
            let reviewSkippedAt: Date?
            
            enum CodingKeys: String, CodingKey {
                case updatedAt = "updated_at"
                case reviewSkippedAt = "review_skipped_at"
            }
        }
        
        let requestInfo = try createDecoder().decode(RequestInfo.self, from: response.data)
        
        // Use skipped_at if available, otherwise use updated_at (completion time)
        let referenceDate = requestInfo.reviewSkippedAt ?? requestInfo.updatedAt
        let daysSince = Date().timeIntervalSince(referenceDate) / 86400 // 86400 seconds = 1 day
        
        // Can review within 7 days
        return daysSince <= 7.0
    }
    
    // MARK: - Private Helpers
    
    /// Create decoder with custom date formatting for Supabase
    private func createDecoder() -> JSONDecoder {
        DateDecoderFactory.makeMessagingDecoder()
    }
    
    /// Upload review image to Supabase Storage
    /// - Parameters:
    ///   - imageData: Image data to upload
    ///   - reviewId: Review ID for filename
    /// - Returns: Public URL of uploaded image
    /// - Throws: AppError if upload fails
    private func uploadReviewImage(imageData: Data, reviewId: UUID) async throws -> String {
        // Compress image (use messageImage preset for reviews - 1200px, 500KB)
        guard let uiImage = UIImage(data: imageData) else {
            throw AppError.invalidInput("Invalid image data")
        }
        
        guard let compressedData = await ImageCompressor.compressAsync(uiImage, preset: .messageImage) else {
            throw AppError.processingError("Failed to compress image")
        }
        
        // Upload to review-images bucket (or use town-hall-images if review-images doesn't exist)
        let fileName = "\(reviewId.uuidString).jpg"
        let bucketName = "review-images" // Will create migration for this bucket
        
        var actualBucket = bucketName
        do {
            try await supabase.storage
                .from(bucketName)
                .upload(
                    fileName,
                    data: compressedData,
                    options: FileOptions(contentType: "image/jpeg", upsert: true)
                )
        } catch {
            // If bucket doesn't exist, try town-hall-images as fallback
            actualBucket = "town-hall-images"
            try await supabase.storage
                .from(actualBucket)
                .upload(
                    fileName,
                    data: compressedData,
                    options: FileOptions(contentType: "image/jpeg", upsert: true)
                )
        }
        
        // Get public URL from the bucket that was actually used
        let publicUrl = try supabase.storage
            .from(actualBucket)
            .getPublicURL(path: fileName)
        
        // Append cache-busting query parameter
        let timestamp = Int(Date().timeIntervalSince1970)
        let urlWithCacheBust = "\(publicUrl.absoluteString)?t=\(timestamp)"
        
        return urlWithCacheBust
    }
    
    /// Create a Town Hall post for a review
    /// - Parameters:
    ///   - review: The review to post
    ///   - fulfillerId: User ID of the fulfiller
    /// - Throws: AppError if post creation fails
    private func createTownHallPostForReview(review: Review, fulfillerId: UUID) async throws {
        // Fetch fulfiller profile for display name
        let fulfillerProfile = try? await profileService.fetchProfile(userId: fulfillerId)
        let fulfillerName = fulfillerProfile?.name ?? "Someone"
        
        // Format review content for Town Hall
        var content = "⭐ \(review.rating)/5 - \(fulfillerName)\n\n"
        if let comment = review.comment, !comment.isEmpty {
            content += comment
        }
        
        // Create Town Hall post
        // Note: TownHallService.createSystemPost doesn't support imageUrl parameter
        // We'll need to use createPost instead or extend createSystemPost
        let post = try await townHallService.createPost(
            userId: review.reviewerId,
            content: content,
            imageUrl: review.imageUrl
        )
        
        AppLogger.info("reviews", "Created Town Hall post for review: \(post.id)")
    }
}

extension ReviewService: ReviewServiceProtocol {}

