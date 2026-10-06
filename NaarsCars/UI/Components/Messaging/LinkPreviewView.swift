//
//  LinkPreviewView.swift
//  NaarsCars
//
//  Link preview component for messages with URLs
//

import SwiftUI
import LinkPresentation
import UIKit

/// Model for link preview metadata
struct LinkPreviewData: Equatable, Sendable {
    let url: URL
    let title: String?
    let description: String?
    let imageData: Data?
    let siteName: String?
    
    init(url: URL, title: String? = nil, description: String? = nil, imageData: Data? = nil, siteName: String? = nil) {
        self.url = url
        self.title = title
        self.description = description
        self.imageData = imageData
        self.siteName = siteName
    }
}

/// Service for fetching link preview metadata.
///
/// Cache bounds and invalidation: at most `maxCachedPreviews` entries and
/// `maxCachedImageBytes` of og:image bytes, evicted by NSCache (count/cost limits
/// and memory pressure); a successful preview is otherwise kept for the process
/// lifetime because a URL's metadata is effectively immutable for a session.
/// Failed fetches are cached for `failureTTL` so scrolling past a dead link does
/// not refetch on every cell configure. Concurrent requests for one URL join a
/// single in-flight task, and each fetch gets its own `LPMetadataProvider`
/// (the provider is a one-shot object; reusing one throws an
/// NSInternalInconsistencyException on the second fetch).
actor LinkPreviewService {
    static let shared = LinkPreviewService()

    private final class CacheEntry: Sendable {
        let preview: LinkPreviewData
        /// Set only for failed fetches, which are retried once this passes.
        let expiresAt: Date?

        init(preview: LinkPreviewData, expiresAt: Date?) {
            self.preview = preview
            self.expiresAt = expiresAt
        }
    }

    private static let maxCachedPreviews = 100
    private static let maxCachedImageBytes = 8 * 1024 * 1024
    private static let failureTTL: TimeInterval = 60

    private let cache: NSCache<NSURL, CacheEntry> = {
        let cache = NSCache<NSURL, CacheEntry>()
        cache.countLimit = LinkPreviewService.maxCachedPreviews
        cache.totalCostLimit = LinkPreviewService.maxCachedImageBytes
        return cache
    }()
    private var inFlight: [URL: Task<CacheEntry, Never>] = [:]

    private init() {}

    /// Extract URLs from text
    nonisolated func extractURLs(from text: String) -> [URL] {
        let detector = try? NSDataDetector(types: NSTextCheckingResult.CheckingType.link.rawValue)
        let matches = detector?.matches(in: text, options: [], range: NSRange(text.startIndex..., in: text)) ?? []
        
        // Same rule as URLDetectionCache (one helper): the detector's URL, web links only, and
        // https for a link typed without a scheme, so every card can be opened and previewed.
        return matches.compactMap { URLDetectionCache.webURL(for: $0, in: text) }
    }
    
    /// Fetch link preview metadata
    func fetchPreview(for url: URL) async -> LinkPreviewData? {
        let key = url as NSURL

        // Check cache first (expired failure entries fall through to a refetch)
        if let cached = cache.object(forKey: key) {
            if let expiresAt = cached.expiresAt, expiresAt <= Date() {
                cache.removeObject(forKey: key)
            } else {
                return cached.preview
            }
        }

        // Join an in-flight fetch for the same URL
        if let existing = inFlight[url] {
            return await existing.value.preview
        }

        let task = Task { await Self.loadPreview(for: url) }
        inFlight[url] = task
        let entry = await task.value
        inFlight[url] = nil

        cache.setObject(entry, forKey: key, cost: entry.preview.imageData?.count ?? 0)
        return entry.preview
    }

    /// One fetch with a fresh one-shot provider. Runs off the actor so a slow
    /// page does not block cache lookups for other URLs.
    private static func loadPreview(for url: URL) async -> CacheEntry {
        let metadataProvider = LPMetadataProvider()
        do {
            let metadata = try await metadataProvider.startFetchingMetadata(for: url)

            var imageData: Data? = nil
            if let imageProvider = metadata.imageProvider {
                imageData = await loadImageData(from: imageProvider)
            }

            let preview = LinkPreviewData(
                url: url,
                title: metadata.title,
                description: nil, // LPMetadataProvider doesn't provide description directly
                imageData: imageData,
                siteName: metadata.url?.host
            )
            return CacheEntry(preview: preview, expiresAt: nil)
        } catch {
            // Return basic preview on error, cached briefly to avoid refetch storms
            let fallback = LinkPreviewData(
                url: url,
                title: nil,
                description: nil,
                imageData: nil,
                siteName: url.host
            )
            return CacheEntry(preview: fallback, expiresAt: Date().addingTimeInterval(failureTTL))
        }
    }

    private static func loadImageData(from provider: NSItemProvider) async -> Data? {
        let image: UIImage? = await withCheckedContinuation { continuation in
            if provider.canLoadObject(ofClass: UIImage.self) {
                provider.loadObject(ofClass: UIImage.self) { object, _ in
                    continuation.resume(returning: object as? UIImage)
                }
            } else {
                continuation.resume(returning: nil)
            }
        }
        guard let image else { return nil }
        // Compress off the calling thread to avoid blocking main/UI
        return await Task.detached(priority: .utility) {
            image.jpegData(compressionQuality: 0.8)
        }.value
    }
}

/// Link preview card view
struct LinkPreviewView: View {
    let url: URL
    let isFromCurrentUser: Bool
    
    @State private var preview: LinkPreviewData?
    @State private var isLoading = true
    
    var body: some View {
        Button(action: openLink) {
            HStack(spacing: 10) {
                // Image thumbnail (if available)
                if let data = preview?.imageData, let image = UIImage(data: data) {
                    Image(uiImage: image)
                        .resizable()
                        .aspectRatio(contentMode: .fill)
                        .frame(width: 60, height: 60)
                        .clipShape(RoundedRectangle(cornerRadius: 8))
                } else {
                    linkIcon
                }
                
                // Link info
                VStack(alignment: .leading, spacing: 4) {
                    if let title = preview?.title, !title.isEmpty {
                        Text(title)
                            .font(.naarsFootnote).fontWeight(.medium)
                            .foregroundColor(isFromCurrentUser ? .white : .primary)
                            .lineLimit(2)
                    }
                    
                    Text(preview?.siteName ?? url.host ?? url.absoluteString)
                        .font(.naarsCaption)
                        .foregroundColor(isFromCurrentUser ? .white.opacity(0.7) : .secondary)
                        .lineLimit(1)
                }
                
                Spacer(minLength: 0)
                
                // Chevron
                Image(systemName: "chevron.right")
                    .font(.naarsFootnote).fontWeight(.medium)
                    .foregroundColor(isFromCurrentUser ? .white.opacity(0.5) : .secondary)
            }
            .padding(10)
            .background(
                RoundedRectangle(cornerRadius: 12)
                    .fill(isFromCurrentUser ? Color.white.opacity(0.15) : Color.naarsCardBackground)
            )
            .frame(maxWidth: 260)
        }
        .buttonStyle(PlainButtonStyle())
        .task {
            await loadPreview()
        }
    }
    
    private var linkIcon: some View {
        RoundedRectangle(cornerRadius: 8)
            .fill(isFromCurrentUser ? Color.white.opacity(0.2) : Color(.systemGray5))
            .frame(width: 60, height: 60)
            .overlay(
                Image(systemName: "link")
                    .font(.naarsTitle3)
                    .foregroundColor(isFromCurrentUser ? .white.opacity(0.6) : .secondary)
            )
    }
    
    private func loadPreview() async {
        isLoading = true
        preview = await LinkPreviewService.shared.fetchPreview(for: url)
        isLoading = false
    }
    
    private func openLink() {
        Task { @MainActor in
            await UIApplication.shared.open(url)
        }
    }
}

/// Compact inline link preview
struct InlineLinkPreview: View {
    let url: URL
    let isFromCurrentUser: Bool
    
    var body: some View {
        Button(action: {
            Task { @MainActor in
                await UIApplication.shared.open(url)
            }
        }) {
            HStack(spacing: 6) {
                Image(systemName: "link")
                    .font(.naarsFootnote)
                
                Text(url.host ?? url.absoluteString)
                    .font(.naarsFootnote)
                    .lineLimit(1)
            }
            .foregroundColor(isFromCurrentUser ? .white.opacity(0.9) : .naarsPrimary)
            .padding(.horizontal, 10)
            .padding(.vertical, 6)
            .background(
                Capsule()
                    .fill(isFromCurrentUser ? Color.white.opacity(0.2) : Color.naarsPrimary.opacity(0.1))
            )
        }
        .buttonStyle(PlainButtonStyle())
    }
}

// MARK: - Preview

#Preview("Link Preview") {
    VStack(spacing: 16) {
        LinkPreviewView(
            url: URL(string: "https://apple.com")!,
            isFromCurrentUser: false
        )
        
        LinkPreviewView(
            url: URL(string: "https://google.com")!,
            isFromCurrentUser: true
        )
        .background(Color.naarsPrimary)
        .cornerRadius(12)
    }
    .padding()
}

#Preview("Inline Link") {
    VStack(spacing: 16) {
        InlineLinkPreview(
            url: URL(string: "https://apple.com/iphone")!,
            isFromCurrentUser: false
        )
        
        InlineLinkPreview(
            url: URL(string: "https://google.com")!,
            isFromCurrentUser: true
        )
    }
    .padding()
}

