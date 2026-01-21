//
//  LinkPreviewView.swift
//  NaarsCars
//
//  Link preview component for messages with URLs
//

import SwiftUI
import LinkPresentation

/// Model for link preview metadata
struct LinkPreviewData: Equatable, Sendable {
    let url: URL
    let title: String?
    let description: String?
    let imageUrl: URL?
    let siteName: String?
    
    init(url: URL, title: String? = nil, description: String? = nil, imageUrl: URL? = nil, siteName: String? = nil) {
        self.url = url
        self.title = title
        self.description = description
        self.imageUrl = imageUrl
        self.siteName = siteName
    }
}

/// Service for fetching link preview metadata
@MainActor
class LinkPreviewService {
    static let shared = LinkPreviewService()
    
    private var cache: [URL: LinkPreviewData] = [:]
    private let metadataProvider = LPMetadataProvider()
    
    private init() {}
    
    /// Extract URLs from text
    func extractURLs(from text: String) -> [URL] {
        let detector = try? NSDataDetector(types: NSTextCheckingResult.CheckingType.link.rawValue)
        let matches = detector?.matches(in: text, options: [], range: NSRange(text.startIndex..., in: text)) ?? []
        
        return matches.compactMap { match -> URL? in
            guard let range = Range(match.range, in: text) else { return nil }
            let urlString = String(text[range])
            return URL(string: urlString)
        }
    }
    
    /// Fetch link preview metadata
    func fetchPreview(for url: URL) async -> LinkPreviewData? {
        // Check cache first
        if let cached = cache[url] {
            return cached
        }
        
        // Fetch metadata
        do {
            let metadata = try await metadataProvider.startFetchingMetadata(for: url)
            
            var imageUrl: URL? = nil
            if let imageProvider = metadata.imageProvider {
                // Try to get the image URL from the provider
                imageUrl = metadata.url
            }
            
            let preview = LinkPreviewData(
                url: url,
                title: metadata.title,
                description: nil, // LPMetadataProvider doesn't provide description directly
                imageUrl: imageUrl,
                siteName: metadata.url?.host
            )
            
            cache[url] = preview
            return preview
        } catch {
            // Return basic preview on error
            return LinkPreviewData(
                url: url,
                title: nil,
                description: nil,
                imageUrl: nil,
                siteName: url.host
            )
        }
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
                if let imageUrl = preview?.imageUrl {
                    AsyncImage(url: imageUrl) { phase in
                        switch phase {
                        case .success(let image):
                            image
                                .resizable()
                                .aspectRatio(contentMode: .fill)
                                .frame(width: 60, height: 60)
                                .clipShape(RoundedRectangle(cornerRadius: 8))
                        default:
                            linkIcon
                        }
                    }
                } else {
                    linkIcon
                }
                
                // Link info
                VStack(alignment: .leading, spacing: 4) {
                    if let title = preview?.title, !title.isEmpty {
                        Text(title)
                            .font(.system(size: 13, weight: .medium))
                            .foregroundColor(isFromCurrentUser ? .white : .primary)
                            .lineLimit(2)
                    }
                    
                    Text(preview?.siteName ?? url.host ?? url.absoluteString)
                        .font(.system(size: 11))
                        .foregroundColor(isFromCurrentUser ? .white.opacity(0.7) : .secondary)
                        .lineLimit(1)
                }
                
                Spacer(minLength: 0)
                
                // Chevron
                Image(systemName: "chevron.right")
                    .font(.system(size: 12, weight: .medium))
                    .foregroundColor(isFromCurrentUser ? .white.opacity(0.5) : .secondary)
            }
            .padding(10)
            .background(
                RoundedRectangle(cornerRadius: 12)
                    .fill(isFromCurrentUser ? Color.white.opacity(0.15) : Color(.systemGray6))
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
                    .font(.system(size: 20))
                    .foregroundColor(isFromCurrentUser ? .white.opacity(0.6) : .secondary)
            )
    }
    
    private func loadPreview() async {
        isLoading = true
        preview = await LinkPreviewService.shared.fetchPreview(for: url)
        isLoading = false
    }
    
    private func openLink() {
        UIApplication.shared.open(url)
    }
}

/// Compact inline link preview
struct InlineLinkPreview: View {
    let url: URL
    let isFromCurrentUser: Bool
    
    var body: some View {
        Button(action: { UIApplication.shared.open(url) }) {
            HStack(spacing: 6) {
                Image(systemName: "link")
                    .font(.system(size: 12))
                
                Text(url.host ?? url.absoluteString)
                    .font(.system(size: 13))
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

