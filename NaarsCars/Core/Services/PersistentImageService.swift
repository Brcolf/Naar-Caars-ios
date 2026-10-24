//
//  PersistentImageService.swift
//  NaarsCars
//
//  Persistent disk-based image cache for avatars and request photos
//

import SwiftUI
import UIKit
import ImageIO
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

    /// Decoded, display-sized images, for callers that pass `maxPixelSize` only. A card that
    /// scrolls back in, or the same avatar on twenty cards, reuses one bitmap instead of reading
    /// the file again and having Core Animation decode it at full camera size on every
    /// appearance. Keyed by the disk cache's file name and the pixel size (never a signed URL),
    /// bounded by `Constants.Storage.imageMemoryCacheMaxBytes` (cost = bitmap bytes), emptied on
    /// a memory warning and by `clearCache()`.
    private let memoryCache: NSCache<NSString, UIImage> = {
        let cache = NSCache<NSString, UIImage>()
        cache.totalCostLimit = Constants.Storage.imageMemoryCacheMaxBytes
        return cache
    }()
    private var memoryWarningObserver: NSObjectProtocol?
    
    private init() {
        let caches = fileManager.urls(for: .cachesDirectory, in: .userDomainMask).first ?? FileManager.default.temporaryDirectory
        cacheDirectory = caches.appendingPathComponent("PersistentImageCache", isDirectory: true)
        
        // Create directory if it doesn't exist
        if !fileManager.fileExists(atPath: cacheDirectory.path) {
            try? fileManager.createDirectory(at: cacheDirectory, withIntermediateDirectories: true)
        }

        let memoryCache = self.memoryCache
        memoryWarningObserver = NotificationCenter.default.addObserver(
            forName: UIApplication.didReceiveMemoryWarningNotification,
            object: nil,
            queue: nil
        ) { _ in
            memoryCache.removeAllObjects()
        }
    }
    
    /// Get an image from cache or download it if not present
    /// - Parameters:
    ///   - urlString: The URL string of the image
    ///   - maxPixelSize: The pixels the caller shows the image's short side at (a fit-to-width
    ///     card's width, an aspect-fill square's side). When set, the image is decoded off the main
    ///     thread with its short side at this size, or at the source's own size when that is
    ///     smaller (never upscaled), and kept in the memory cache, so the same URL and size returns
    ///     the same instance. Nil returns the full-size, lazily decoded image
    ///     as before, not memory-cached (the full-screen viewer, and the message bubbles, which
    ///     downsample themselves).
    /// - Returns: The UIImage if found or downloaded, nil otherwise
    func getImage(for urlString: String, maxPixelSize: CGFloat? = nil) async -> UIImage? {
        guard let url = URL(string: urlString) else { return nil }

        // The key is the stored URL's file name, never the signed URL's.
        let fileName = url.lastPathComponent
        let fileURL = cacheDirectory.appendingPathComponent(fileName)
        let pixelCap: Int? = maxPixelSize.flatMap { $0.isFinite && $0 >= 1 ? Int($0.rounded(.up)) : nil }
        let memoryKey: NSString? = pixelCap.map { "\(fileName)@\($0)" as NSString }

        // 0. Memory cache (display-sized requests only)
        if let memoryKey, let hit = memoryCache.object(forKey: memoryKey) {
            return hit
        }

        // 1. Check disk cache (off-main via detached task)
        let cachedImage = await Task.detached(priority: .userInitiated) {
            guard FileManager.default.fileExists(atPath: fileURL.path),
                  let data = try? Data(contentsOf: fileURL) else {
                return nil as UIImage?
            }
            return PersistentImageService.makeImage(from: data, maxPixelSize: pixelCap)
        }.value

        if let cachedImage {
            remember(cachedImage, forKey: memoryKey)
            return cachedImage
        }

        // 2. Download if not in cache, from the resolved (possibly signed) URL
        let downloadURL = await urlResolver.resolvedURL(for: url)
        do {
            let (data, _) = try await downloadSession.data(from: downloadURL)
            let image: UIImage?
            if pixelCap != nil {
                image = await Task.detached(priority: .userInitiated) {
                    PersistentImageService.makeImage(from: data, maxPixelSize: pixelCap)
                }.value
            } else {
                image = UIImage(data: data)
            }
            if let image {
                // Save to disk cache (off-main)
                let saveURL = fileURL
                Task.detached(priority: .utility) {
                    try? data.write(to: saveURL, options: .atomic)
                }
                remember(image, forKey: memoryKey)
                return image
            }
        } catch {
            // Domain and code only: a URLError's description carries the (signed) failing URL.
            let ns = error as NSError
            AppLogger.error("images", "Failed to download image: \(ns.domain) \(ns.code)")
        }

        return nil
    }

    /// With a pixel size, ImageIO decodes straight to a bitmap whose short side is that size (or
    /// the source's own when smaller: never upscaled), applies the EXIF orientation and decodes now
    /// (on the calling, background, thread), so Core Animation has nothing left to decode when the
    /// image is shown. Without one, the lazily decoded full-size image, as before.
    private static func makeImage(from data: Data, maxPixelSize: Int?) -> UIImage? {
        guard let maxPixelSize else { return UIImage(data: data) }
        let sourceOptions = [kCGImageSourceShouldCache: false] as CFDictionary
        guard let source = CGImageSourceCreateWithData(data as CFData, sourceOptions) else {
            return UIImage(data: data)
        }
        let thumbnailOptions: [CFString: Any] = [
            kCGImageSourceCreateThumbnailFromImageAlways: true,
            kCGImageSourceCreateThumbnailWithTransform: true,
            kCGImageSourceShouldCacheImmediately: true,
            kCGImageSourceThumbnailMaxPixelSize: thumbnailLongSide(of: source, shortSide: maxPixelSize)
        ]
        if let cgImage = CGImageSourceCreateThumbnailAtIndex(source, 0, thumbnailOptions as CFDictionary) {
            return UIImage(cgImage: cgImage)
        }
        return UIImage(data: data)
    }

    /// `kCGImageSourceThumbnailMaxPixelSize` caps the long side, but callers show the short side
    /// at full size: a fit-to-width card shows a portrait photo's width, and an aspect-fill circle
    /// shows the short side of any avatar. Capping the long side at the shown size decoded a
    /// 945x2048 screenshot at 664x1440 for a 987-pixel card. So the long side asked for is the one
    /// that gives the short side `shortSide` pixels, and never more than the source's own long side.
    /// A source whose size cannot be read keeps `shortSide` as the cap on the long side.
    private static func thumbnailLongSide(of source: CGImageSource, shortSide: Int) -> Int {
        guard let properties = CGImageSourceCopyPropertiesAtIndex(source, 0, nil) as? [CFString: Any],
              let width = (properties[kCGImagePropertyPixelWidth] as? NSNumber)?.intValue,
              let height = (properties[kCGImagePropertyPixelHeight] as? NSNumber)?.intValue,
              width > 0, height > 0 else {
            return shortSide
        }
        let long = max(width, height)
        let short = min(width, height)
        let needed = (Double(shortSide) * Double(long) / Double(short)).rounded(.up)
        return min(long, Int(needed))
    }

    private func remember(_ image: UIImage, forKey key: NSString?) {
        guard let key else { return }
        let cost = image.cgImage.map { $0.bytesPerRow * $0.height }
            ?? Int(image.size.width * image.scale * image.size.height * image.scale * 4)
        memoryCache.setObject(image, forKey: key, cost: cost)
    }
    
    /// Clear the entire image cache
    func clearCache() {
        memoryCache.removeAllObjects()
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

