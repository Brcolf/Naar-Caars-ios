//
//  CreatePostViewModel.swift
//  NaarsCars
//
//  ViewModel for creating town hall posts
//

import Foundation
import SwiftUI
import Supabase
internal import Combine

/// ViewModel for creating town hall posts
@MainActor
final class CreatePostViewModel: ObservableObject {
    
    // MARK: - Published Properties
    
    @Published var content: String = ""
    @Published var selectedImage: UIImage?
    @Published var imageUrl: String?
    @Published var isLoading: Bool = false
    @Published var error: AppError?
    
    // MARK: - Computed Properties
    
    var characterCount: Int {
        content.count
    }
    
    var remainingCharacters: Int {
        500 - characterCount
    }
    
    var canPost: Bool {
        !content.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty &&
        characterCount <= 500 &&
        !isLoading
    }
    
    // MARK: - Private Properties
    
    private let townHallService = TownHallService.shared
    private let authService = AuthService.shared
    
    // MARK: - Public Methods
    
    /// Validate and post content
    /// - Returns: Created post if successful
    /// - Throws: AppError if validation or posting fails
    func validateAndPost() async throws -> TownHallPost {
        // Validate content
        let trimmedContent = content.trimmingCharacters(in: .whitespacesAndNewlines)
        
        guard !trimmedContent.isEmpty else {
            throw AppError.invalidInput("Post content cannot be empty")
        }
        
        guard trimmedContent.count <= 500 else {
            throw AppError.invalidInput("Post content must be 500 characters or less")
        }
        
        guard let userId = authService.currentUserId else {
            throw AppError.notAuthenticated
        }
        
        // Check rate limit (handled by service, but we can check here too)
        isLoading = true
        error = nil
        defer { isLoading = false }
        
        do {
            // Upload image if present
            var uploadedImageUrl: String? = nil
            if let image = selectedImage {
                uploadedImageUrl = try await uploadImage(image)
            }
            
            // Create post
            let post = try await townHallService.createPost(
                userId: userId,
                content: trimmedContent,
                imageUrl: uploadedImageUrl
            )
            
            // Reset form
            content = ""
            selectedImage = nil
            imageUrl = nil
            
            return post
        } catch {
            self.error = error as? AppError ?? AppError.processingError(error.localizedDescription)
            throw error
        }
    }
    
    /// Upload image to Supabase storage
    /// - Parameter image: Image to upload
    /// - Returns: Image URL if successful
    /// - Throws: AppError if upload fails
    private func uploadImage(_ image: UIImage) async throws -> String {
        // Check image size before compression
        let imageSize = image.size
        let maxDimension: CGFloat = 1200
        let imageMaxDimension = max(imageSize.width, imageSize.height)
        
        if imageMaxDimension > maxDimension * 2 {
            throw AppError.invalidInput("Image is too large. Please select a smaller image (max 2400px on longest side).")
        }
        
        // Compress image using messageImage preset (500KB max, 1200px max dimension)
        guard let imageData = ImageCompressor.compress(image, preset: .messageImage) else {
            throw AppError.invalidInput("Image is too large to compress. Please select a smaller image or try a different photo.")
        }
        
        // Generate unique filename
        let filename = "\(UUID().uuidString).jpg"
        let path = filename
        
        // Upload to Supabase storage
        try await SupabaseService.shared.client.storage
            .from("town-hall-images")
            .upload(
                path: path,
                file: imageData,
                options: FileOptions(contentType: "image/jpeg", upsert: false)
            )
        
        // Get public URL
        let url = try SupabaseService.shared.client.storage
            .from("town-hall-images")
            .getPublicURL(path: path)
        
        return url.absoluteString
    }
    
    /// Remove selected image
    func removeImage() {
        selectedImage = nil
        imageUrl = nil
    }
}

