//
//  PersistentImageService.swift
//  NaarsCars
//
//  Persistent disk-based image cache for avatars and request photos
//

import SwiftUI
import Foundation
import ImageIO
import CryptoKit

/// Service for downloading and caching images on disk + in memory.
/// Implements a "Zero-Spinner" experience by storing images in the app's Caches directory
/// and keeping a bounded in-memory cache of decoded (optionally downsampled) images.
///
/// Cache design (bounds + invalidation documented per CLAUDE.md — "any new cache must
/// have documented bounds and invalidation"):
///  - In-memory: `NSCache` keyed by the FULL URL string (+ target pixel size), bounded by
///    `memoryCountLimit` and `memoryCostLimit`; evicted automatically under memory pressure.
///  - On-disk: original downloaded bytes keyed by a SHA256 hex of the FULL URL string (no
///    filename collisions), bounded by `diskMaxBytes` with LRU trim to `diskTrimTargetBytes`
///    and age-based eviction after `diskMaxAge`.
///  - In-flight de-duplication: concurrent requests for the same URL (or same URL + size)
///    share a single download/decode via a serializing `RequestCoordinator` actor.
final class PersistentImageService {

    static let shared = PersistentImageService()

    private let fileManager = FileManager.default
    private let cacheDirectory: URL

    /// Bounded in-memory cache of decoded images, keyed by full URL string (+ pixel size).
    private let memoryCache = NSCache<NSString, UIImage>()

    /// Serializes in-flight request bookkeeping so concurrent callers share one load.
    private let coordinator = RequestCoordinator()

    // MARK: - Cache bounds (documented, no magic numbers)

    /// Max resident decoded images held in memory (NSCache auto-evicts beyond this / under pressure).
    private static let memoryCountLimit = 120
    /// ~60MB decoded-pixel budget held in memory (NSCache cost is bytes).
    private static let memoryCostLimit = 60 * 1_024 * 1_024
    /// Max on-disk budget for cached originals before LRU trim (bytes).
    private static let diskMaxBytes: Int64 = 150 * 1_024 * 1_024
    /// Trim target after eviction crosses `diskMaxBytes` (bytes).
    private static let diskTrimTargetBytes: Int64 = 100 * 1_024 * 1_024
    /// Evict disk entries not accessed within this window (14 days; mirrors offline cache retention).
    private static let diskMaxAge: TimeInterval = 14 * 24 * 60 * 60

    private init() {
        let caches = fileManager.urls(for: .cachesDirectory, in: .userDomainMask).first ?? FileManager.default.temporaryDirectory
        cacheDirectory = caches.appendingPathComponent("PersistentImageCache", isDirectory: true)

        // Create directory if it doesn't exist
        if !fileManager.fileExists(atPath: cacheDirectory.path) {
            try? fileManager.createDirectory(at: cacheDirectory, withIntermediateDirectories: true)
        }

        memoryCache.countLimit = Self.memoryCountLimit
        memoryCache.totalCostLimit = Self.memoryCostLimit
    }

    /// Get an image from cache or download it if not present.
    /// - Parameters:
    ///   - urlString: The URL string of the image (remote https or local file URL).
    ///   - maxPixelSize: When provided, the image is decoded/downsampled so its largest
    ///     dimension is at most this many pixels (display-size decode). When `nil`, the
    ///     full-resolution image is decoded (used by the full-screen image viewer).
    /// - Returns: The decoded `UIImage` if found or downloaded, `nil` otherwise.
    func getImage(for urlString: String, maxPixelSize: CGFloat? = nil) async -> UIImage? {
        guard let url = URL(string: urlString) else { return nil }

        let memKey = memoryCacheKey(urlString, maxPixelSize)

        // 1. In-memory cache hit — no disk read, no re-decode.
        if let cached = memoryCache.object(forKey: memKey as NSString) {
            return cached
        }

        // 2. Join or start the single in-flight task for this key (de-dup).
        let task = await coordinator.imageTask(for: memKey) { [weak self] in
            Task.detached(priority: .userInitiated) { [weak self] () -> UIImage? in
                guard let self else { return nil }
                let image = await self.produceImage(url: url, urlString: urlString, maxPixelSize: maxPixelSize)
                if let image {
                    self.memoryCache.setObject(image, forKey: memKey as NSString, cost: self.memoryCost(of: image))
                }
                await self.coordinator.removeImageTask(memKey)
                return image
            }
        }
        return await task.value
    }

    /// Clear the entire image cache (in-memory + on-disk).
    func clearCache() {
        memoryCache.removeAllObjects()
        try? fileManager.removeItem(at: cacheDirectory)
        try? fileManager.createDirectory(at: cacheDirectory, withIntermediateDirectories: true)
    }

    // MARK: - Image production

    /// Fetch the original bytes (disk/download, de-duplicated) then decode at the requested size.
    private func produceImage(url: URL, urlString: String, maxPixelSize: CGFloat?) async -> UIImage? {
        guard let data = await originalData(url: url, urlString: urlString) else { return nil }
        if let maxPixelSize {
            // Display-size decode: never materialize a full-res bitmap for a small bubble.
            return downsampledImage(data: data, maxPixelSize: maxPixelSize) ?? UIImage(data: data)
        }
        return UIImage(data: data)
    }

    /// De-duplicated fetch of the original image bytes (shared across all requested sizes).
    private func originalData(url: URL, urlString: String) async -> Data? {
        let task = await coordinator.dataTask(for: urlString) { [weak self] in
            Task.detached(priority: .userInitiated) { [weak self] () -> Data? in
                guard let self else { return nil }
                let data = await self.fetchOriginalData(url: url, urlString: urlString)
                await self.coordinator.removeDataTask(urlString)
                return data
            }
        }
        return await task.value
    }

    private func fetchOriginalData(url: URL, urlString: String) async -> Data? {
        // Local files (optimistic, awaiting upload): read directly, never disk-cache them.
        if url.isFileURL {
            return try? Data(contentsOf: url)
        }

        let fileURL = diskURL(for: urlString)

        // 1. Disk cache hit (respecting TTL); touches mtime for LRU.
        if let cached = Self.readValidDiskData(at: fileURL, maxAge: Self.diskMaxAge) {
            return cached
        }

        // 2. Download if not cached.
        do {
            let (data, _) = try await URLSession.shared.data(from: url)
            let saveURL = fileURL
            Task.detached(priority: .utility) { [weak self] in
                try? data.write(to: saveURL, options: .atomic)
                self?.trimDiskCacheIfNeeded()
            }
            return data
        } catch {
            AppLogger.error("images", "Failed to download image: \(error)")
            return nil
        }
    }

    // MARK: - Decoding

    /// Downsample `data` so the resulting image's largest dimension is at most `maxPixelSize`
    /// pixels, decoding at display size rather than full resolution.
    private func downsampledImage(data: Data, maxPixelSize: CGFloat) -> UIImage? {
        let sourceOptions = [kCGImageSourceShouldCache: false] as CFDictionary
        guard let source = CGImageSourceCreateWithData(data as CFData, sourceOptions) else { return nil }
        let options: [CFString: Any] = [
            kCGImageSourceCreateThumbnailFromImageAlways: true,
            kCGImageSourceCreateThumbnailWithTransform: true,
            kCGImageSourceShouldCacheImmediately: true,
            kCGImageSourceThumbnailMaxPixelSize: max(1, maxPixelSize)
        ]
        guard let cgImage = CGImageSourceCreateThumbnailAtIndex(source, 0, options as CFDictionary) else { return nil }
        return UIImage(cgImage: cgImage)
    }

    // MARK: - Disk cache management

    /// Reads disk data if present and within TTL. Evicts stale entries. Touches mtime on hit (LRU).
    private static func readValidDiskData(at fileURL: URL, maxAge: TimeInterval) -> Data? {
        let fm = FileManager.default
        guard fm.fileExists(atPath: fileURL.path) else { return nil }

        if let attrs = try? fm.attributesOfItem(atPath: fileURL.path),
           let modDate = attrs[.modificationDate] as? Date,
           Date().timeIntervalSince(modDate) > maxAge {
            try? fm.removeItem(at: fileURL)
            return nil
        }

        guard let data = try? Data(contentsOf: fileURL) else { return nil }
        // Touch modification date so TTL/LRU reflect last access.
        try? fm.setAttributes([.modificationDate: Date()], ofItemAtPath: fileURL.path)
        return data
    }

    /// Enforce the on-disk budget: evict aged-out entries, then LRU-evict until under the trim target.
    private func trimDiskCacheIfNeeded() {
        let fm = FileManager.default
        let keys: [URLResourceKey] = [.contentModificationDateKey, .totalFileAllocatedSizeKey, .fileSizeKey]
        guard let urls = try? fm.contentsOfDirectory(at: cacheDirectory,
                                                     includingPropertiesForKeys: keys,
                                                     options: [.skipsHiddenFiles]) else { return }

        let now = Date()
        var entries: [(url: URL, size: Int64, date: Date)] = []
        var total: Int64 = 0

        for u in urls {
            let vals = try? u.resourceValues(forKeys: Set(keys))
            let date = vals?.contentModificationDate ?? .distantPast
            // Age-based eviction.
            if now.timeIntervalSince(date) > Self.diskMaxAge {
                try? fm.removeItem(at: u)
                continue
            }
            let size = Int64(vals?.totalFileAllocatedSize ?? vals?.fileSize ?? 0)
            total += size
            entries.append((u, size, date))
        }

        guard total > Self.diskMaxBytes else { return }

        // LRU eviction (oldest access first) down to the trim target.
        for entry in entries.sorted(by: { $0.date < $1.date }) {
            guard total > Self.diskTrimTargetBytes else { break }
            try? fm.removeItem(at: entry.url)
            total -= entry.size
        }
    }

    // MARK: - Keys & cost

    private func memoryCacheKey(_ urlString: String, _ maxPixelSize: CGFloat?) -> String {
        if let maxPixelSize { return "\(urlString)|\(Int(maxPixelSize))" }
        return urlString
    }

    private func diskURL(for urlString: String) -> URL {
        cacheDirectory.appendingPathComponent(sha256Hex(urlString))
    }

    private func sha256Hex(_ string: String) -> String {
        let digest = SHA256.hash(data: Data(string.utf8))
        return digest.map { String(format: "%02x", $0) }.joined()
    }

    /// Approximate decoded byte size (RGBA) used as the NSCache cost.
    private func memoryCost(of image: UIImage) -> Int {
        let scale = image.scale
        let pixels = image.size.width * scale * image.size.height * scale
        return max(1, Int(pixels * 4))
    }
}

/// Serializes in-flight request bookkeeping so concurrent callers share a single
/// download (keyed by URL) and a single decode (keyed by URL + target size).
private actor RequestCoordinator {
    private var imageTasks: [String: Task<UIImage?, Never>] = [:]
    private var dataTasks: [String: Task<Data?, Never>] = [:]

    func imageTask(for key: String, _ make: () -> Task<UIImage?, Never>) -> Task<UIImage?, Never> {
        if let existing = imageTasks[key] { return existing }
        let task = make()
        imageTasks[key] = task
        return task
    }

    func removeImageTask(_ key: String) { imageTasks[key] = nil }

    func dataTask(for key: String, _ make: () -> Task<Data?, Never>) -> Task<Data?, Never> {
        if let existing = dataTasks[key] { return existing }
        let task = make()
        dataTasks[key] = task
        return task
    }

    func removeDataTask(_ key: String) { dataTasks[key] = nil }
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
