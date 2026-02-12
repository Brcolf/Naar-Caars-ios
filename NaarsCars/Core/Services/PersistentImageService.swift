//
//  PersistentImageService.swift
//  NaarsCars
//
//  Persistent disk-based image cache for avatars and request photos
//

import SwiftUI
import Foundation

/// Service for downloading and caching images on disk
/// Implements a "Zero-Spinner" experience by storing images in the app's Caches directory
final class PersistentImageService {
    
    static let shared = PersistentImageService()
    
    private let fileManager = FileManager.default
    private let cacheDirectory: URL
    
    private init() {
        let caches = fileManager.urls(for: .cachesDirectory, in: .userDomainMask).first!
        cacheDirectory = caches.appendingPathComponent("PersistentImageCache", isDirectory: true)
        
        // Create directory if it doesn't exist
        if !fileManager.fileExists(atPath: cacheDirectory.path) {
            try? fileManager.createDirectory(at: cacheDirectory, withIntermediateDirectories: true)
        }
    }
    
    /// Get an image from cache or download it if not present
    /// - Parameter urlString: The URL string of the image
    /// - Returns: The UIImage if found or downloaded, nil otherwise
    func getImage(for urlString: String) async -> UIImage? {
        guard let url = URL(string: urlString) else { return nil }
        
        // 1. Check disk cache
        let fileName = url.lastPathComponent
        let fileURL = cacheDirectory.appendingPathComponent(fileName)
        
        if fileManager.fileExists(atPath: fileURL.path) {
            if let data = try? Data(contentsOf: fileURL), let image = UIImage(data: data) {
                return image
            }
        }
        
        // 2. Download if not in cache
        do {
            let (data, _) = try await URLSession.shared.data(from: url)
            if let image = UIImage(data: data) {
                // Save to disk cache
                try? data.write(to: fileURL)
                return image
            }
        } catch {
            AppLogger.error("images", "Failed to download image: \(error)")
        }
        
        return nil
    }
    
    /// Clear the entire image cache
    func clearCache() {
        try? fileManager.removeItem(at: cacheDirectory)
        try? fileManager.createDirectory(at: cacheDirectory, withIntermediateDirectories: true)
    }
}

/// A view that displays an image from the persistent cache
struct PersistentAsyncImage: View {
    let urlString: String?
    let placeholder: Image
    
    @State private var image: UIImage?
    @State private var isLoading = false
    
    init(urlString: String?, placeholder: Image = Image(systemName: "person.circle.fill")) {
        self.urlString = urlString
        self.placeholder = placeholder
    }
    
    var body: some View {
        Group {
            if let image = image {
                Image(uiImage: image)
                    .resizable()
            } else {
                placeholder
                    .resizable()
                    .onAppear {
                        loadImage()
                    }
            }
        }
    }
    
    private func loadImage() {
        guard let urlString = urlString, !urlString.isEmpty, !isLoading else { return }
        
        isLoading = true
        Task {
            let cachedImage = await PersistentImageService.shared.getImage(for: urlString)
            await MainActor.run {
                self.image = cachedImage
                self.isLoading = false
            }
        }
    }
}

