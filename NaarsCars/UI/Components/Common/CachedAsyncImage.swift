//
//  CachedAsyncImage.swift
//  NaarsCars
//
//  Drop-in replacement for AsyncImage with disk caching via PersistentImageService.
//  Provides smooth fade-in transitions and consistent placeholder/error states.
//

import SwiftUI

/// A cached version of AsyncImage that checks disk cache before network fetch.
/// Provides a smooth opacity transition when the image loads.
struct CachedAsyncImage<Placeholder: View, ErrorView: View>: View {
    let url: URL?
    /// Longest side, in pixels, to decode the image at (the shown size times the display scale).
    /// Nil keeps the full-size image.
    let maxPixelSize: CGFloat?
    let placeholder: () -> Placeholder
    let errorView: () -> ErrorView
    
    @State private var image: UIImage?
    /// The URL `image` was loaded for, so a card that reappears in a lazy stack does not load it again.
    @State private var loadedURL: URL?
    @State private var isLoading = false
    @State private var hasFailed = false
    
    init(
        url: URL?,
        maxPixelSize: CGFloat? = nil,
        @ViewBuilder placeholder: @escaping () -> Placeholder = { ProgressView() },
        @ViewBuilder errorView: @escaping () -> ErrorView = {
            Image(systemName: "photo")
                .foregroundColor(.secondary)
        }
    ) {
        self.url = url
        self.maxPixelSize = maxPixelSize
        self.placeholder = placeholder
        self.errorView = errorView
    }
    
    var body: some View {
        Group {
            if let image = image {
                Image(uiImage: image)
                    .resizable()
                    .transition(.opacity.animation(.easeIn(duration: 0.2)))
            } else if hasFailed {
                errorView()
            } else {
                placeholder()
            }
        }
        .task(id: url) {
            await loadImage()
        }
    }
    
    private func loadImage() async {
        guard let url = url else {
            hasFailed = true
            return
        }
        
        if image != nil, loadedURL == url { return }
        guard !isLoading else { return }
        isLoading = true
        hasFailed = false
        
        let urlString = url.absoluteString
        let loaded = await PersistentImageService.shared.getImage(for: urlString, maxPixelSize: maxPixelSize)
        
        if let loaded {
            withAnimation(.easeIn(duration: 0.2)) {
                self.image = loaded
            }
            loadedURL = url
        } else {
            hasFailed = true
        }
        
        isLoading = false
    }
}

// MARK: - Convenience initializer matching AsyncImage API

extension CachedAsyncImage where Placeholder == ProgressView<EmptyView, EmptyView>, ErrorView == Image {
    /// Simple initializer matching common AsyncImage usage
    init(url: URL?) {
        self.init(
            url: url,
            placeholder: { ProgressView() },
            errorView: { Image(systemName: "photo") }
        )
    }
}
