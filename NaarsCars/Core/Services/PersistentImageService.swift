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

    /// Turns a stored URL into the URL to download from (a signed URL for the private-to-be buckets).
    /// Internal so tests can inject a stub; the result is never stored or logged.
    var urlResolver: any StorageURLResolving = StorageURLSigner.shared

    /// Every download goes through this session: no URLCache, so a signed URL never reaches disk.
    var downloadSession: URLSession = .signedStorageDownload
    
    private init() {
        let caches = fileManager.urls(for: .cachesDirectory, in: .userDomainMask).first ?? FileManager.default.temporaryDirectory
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

        // 1. Check disk cache (off-main via detached task). The key is the stored URL's
        // file name, never the signed URL's.
        let fileName = url.lastPathComponent
        let fileURL = cacheDirectory.appendingPathComponent(fileName)

        let cachedImage = await Task.detached(priority: .userInitiated) {
            guard FileManager.default.fileExists(atPath: fileURL.path),
                  let data = try? Data(contentsOf: fileURL),
                  let image = UIImage(data: data) else {
                return nil as UIImage?
            }
            return image
        }.value

        if let cachedImage { return cachedImage }

        // 2. Download if not in cache, from the resolved (possibly signed) URL
        let downloadURL = await urlResolver.resolvedURL(for: url)
        do {
            let (data, _) = try await downloadSession.data(from: downloadURL)
            if let image = UIImage(data: data) {
                // Save to disk cache (off-main)
                let saveURL = fileURL
                Task.detached(priority: .utility) {
                    try? data.write(to: saveURL)
                }
                return image
            }
        } catch {
            // Domain and code only: a URLError's description carries the (signed) failing URL.
            let ns = error as NSError
            AppLogger.error("images", "Failed to download image: \(ns.domain) \(ns.code)")
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

