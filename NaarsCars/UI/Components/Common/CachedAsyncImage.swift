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
    /// Pixels to decode the image's short side at: the shown width of a fit-to-width image or the
    /// side of an aspect-fill square, times the display scale (see `PersistentImageService`).
    /// Nil keeps the full-size image.
    let maxPixelSize: CGFloat?
    let placeholder: () -> Placeholder
    let errorView: () -> ErrorView
    
    @State private var image: UIImage?
    /// The URL `image` was loaded for, so a card that reappears in a lazy stack does not load it again.
    @State private var loadedURL: URL?
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
        // A modifier on a Group applies to each branch, so every switch between the image, the
        // error view and the placeholder starts a new load and cancels the running one. A view
        // inserted into a tab that is not on screen also appears and disappears at once, which
        // cancels its first load. So loadImage writes no state when it starts, and none when it is
        // cancelled: a write either way switched branches, which started the next load, once per
        // frame for as long as the tab stayed hidden.
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
        // No "already loading" guard: the load a new appearance starts must run even while a
        // cancelled one is still returning, or the view keeps whatever that one leaves.
        let urlString = url.absoluteString
        let loaded = await PersistentImageService.shared.getImage(for: urlString, maxPixelSize: maxPixelSize)

        switch CachedImageLoadOutcome(gotImage: loaded != nil, cancelled: Task.isCancelled) {
        case .show:
            withAnimation(.easeIn(duration: 0.2)) {
                self.image = loaded
            }
            loadedURL = url
            hasFailed = false
        case .failed:
            hasFailed = true
        case .unchanged:
            break
        }
    }
}

/// What a finished `CachedAsyncImage` load does to the view.
enum CachedImageLoadOutcome: Equatable {
    /// An image arrived: show it, also when the view went away meanwhile.
    case show
    /// The load failed: show the error view.
    case failed
    /// The load was cancelled before an image arrived (the view left the screen, its tab is not
    /// on screen, or a branch switch restarted the task). Not a failure: nothing changes, and the
    /// next appearance loads again.
    case unchanged

    init(gotImage: Bool, cancelled: Bool) {
        if gotImage {
            self = .show
        } else if cancelled {
            self = .unchanged
        } else {
            self = .failed
        }
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
