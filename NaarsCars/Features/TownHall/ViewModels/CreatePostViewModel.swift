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
    private let authService: any AuthServiceProtocol

    init(authService: any AuthServiceProtocol = AuthService.shared) {
        self.authService = authService
    }
    
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
        // No size check here: the compressor scales any photo down to the preset's 2048 px, so a
        // 24 or 48 MP camera photo is resized, not refused.
        // Compress image using messageImage preset (2.5MB max, 2048px max dimension)
        guard let imageData = await ImageCompressor.compressAsync(image, preset: .messageImage) else {
            throw AppError.invalidInput("profile_image_too_large".localized)
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

