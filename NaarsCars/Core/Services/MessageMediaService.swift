//
//  MessageMediaService.swift
//  NaarsCars
//
//  Service for message media operations
//

import Foundation
import Supabase
import UIKit
import OSLog

/// Service for message media operations
/// Handles uploading and managing message images, audio, and other media
final class MessageMediaService {
    
    // MARK: - Singleton
    
    static let shared = MessageMediaService()
    
    // MARK: - Private Properties
    
    private let supabase = SupabaseService.shared.client
    
    // MARK: - Initialization
    
    private init() {}
    
    // MARK: - Image Upload
    
    /// Upload message image to storage
    /// - Parameters:
    ///   - imageData: The image data to upload
    ///   - conversationId: The conversation ID
    ///   - fromId: The sender's user ID
    /// - Returns: Public URL of uploaded image
    /// - Throws: AppError if upload fails
    func uploadMessageImage(imageData: Data, conversationId: UUID, fromId: UUID) async throws -> String {
        // Compress image using messageImage preset
        guard let uiImage = UIImage(data: imageData) else {
            throw AppError.invalidInput("Invalid image data")
        }
        
        guard let compressedData = await ImageCompressor.compressAsync(uiImage, preset: .messageImage) else {
            throw AppError.processingError("Failed to compress image")
        }
        
        // Upload to message-images bucket
        // Store in a folder per conversation for better organization
        let fileName = "\(conversationId.uuidString)/\(UUID().uuidString).jpg"
        
        try await supabase.storage
            .from("message-images")
            .upload(
                path: fileName,
                file: compressedData,
                options: FileOptions(contentType: "image/jpeg", upsert: false)
            )
        
        // Get public URL
        let publicUrl = try supabase.storage
            .from("message-images")
            .getPublicURL(path: fileName)
        
        AppLogger.info("messaging", "Uploaded image, public URL: \(publicUrl.absoluteString)")
        return publicUrl.absoluteString
    }
    
    // MARK: - Audio Upload
    
    /// Upload audio message to storage
    /// - Parameters:
    ///   - audioData: The audio file data
    ///   - conversationId: The conversation ID
    ///   - fromId: The sender user ID
    /// - Returns: Public URL of uploaded audio
    func uploadAudioMessage(audioData: Data, conversationId: UUID, fromId: UUID) async throws -> String {
        // Upload to audio-messages bucket
        let fileName = "\(conversationId.uuidString)/\(UUID().uuidString).m4a"
        
        try await supabase.storage
            .from("audio-messages")
            .upload(
                path: fileName,
                file: audioData,
                options: FileOptions(contentType: "audio/m4a", upsert: false)
            )
        
        // Get public URL
        let publicUrl = try await supabase.storage
            .from("audio-messages")
            .getPublicURL(path: fileName)
        
        return publicUrl.absoluteString
    }
}
