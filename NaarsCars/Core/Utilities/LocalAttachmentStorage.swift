//
//  LocalAttachmentStorage.swift
//  NaarsCars
//
//  Utility for saving and loading local message attachments (images, audio)
//  before they are uploaded to the server.
//

import Foundation

/// Manages local file storage for message attachments pending upload
enum LocalAttachmentStorage {
    
    /// Base directory for message attachments in the app's Caches folder
    private static var baseDirectory: URL {
        let caches = FileManager.default.urls(for: .cachesDirectory, in: .userDomainMask).first!
        return caches.appendingPathComponent("message-attachments", isDirectory: true)
    }
    
    /// Save data to a local file and return the relative path
    /// - Parameters:
    ///   - data: The file data to save
    ///   - extension: The file extension (e.g. "jpg", "m4a")
    /// - Returns: The relative path within the attachments directory, or nil on failure
    static func save(data: Data, extension ext: String) -> String? {
        let directory = baseDirectory
        
        // Ensure directory exists
        try? FileManager.default.createDirectory(at: directory, withIntermediateDirectories: true)
        
        let fileName = "\(UUID().uuidString).\(ext)"
        let fileURL = directory.appendingPathComponent(fileName)
        
        do {
            try data.write(to: fileURL, options: .atomic)
            return fileName
        } catch {
            AppLogger.error("messaging", "Failed to save local attachment: \(error.localizedDescription)")
            return nil
        }
    }
    
    /// Load data from a local attachment path
    /// - Parameter path: The relative path (file name) within the attachments directory
    /// - Returns: The file data, or nil if not found
    static func load(path: String) -> Data? {
        let fileURL = baseDirectory.appendingPathComponent(path)
        return try? Data(contentsOf: fileURL)
    }
    
    /// Get the full file URL for a local attachment path
    /// - Parameter path: The relative path (file name) within the attachments directory
    /// - Returns: The full file URL
    static func fileURL(for path: String) -> URL {
        baseDirectory.appendingPathComponent(path)
    }
    
    /// Delete a local attachment file
    /// - Parameter path: The relative path (file name) within the attachments directory
    static func delete(path: String) {
        let fileURL = baseDirectory.appendingPathComponent(path)
        try? FileManager.default.removeItem(at: fileURL)
    }
    
    /// Clean up all local attachments (e.g. on logout)
    static func deleteAll() {
        try? FileManager.default.removeItem(at: baseDirectory)
    }
}
