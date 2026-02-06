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
    let placeholder: () -> Placeholder
    let errorView: () -> ErrorView
    
    @State private var image: UIImage?
    @State private var isLoading = false
    @State private var hasFailed = false
    
    init(
        url: URL?,
        @ViewBuilder placeholder: @escaping () -> Placeholder = { ProgressView() },
        @ViewBuilder errorView: @escaping () -> ErrorView = {
            Image(systemName: "photo")
                .foregroundColor(.secondary)
        }
    ) {
        self.url = url
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
        
        guard !isLoading else { return }
        isLoading = true
        hasFailed = false
        
        let urlString = url.absoluteString
        let loaded = await PersistentImageService.shared.getImage(for: urlString)
        
        if let loaded {
            withAnimation(.easeIn(duration: 0.2)) {
                self.image = loaded
            }
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
