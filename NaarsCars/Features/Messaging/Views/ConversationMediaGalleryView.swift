//
//  ConversationMediaGalleryView.swift
//  NaarsCars
//
//  Media gallery for browsing photos, audio, and links in a conversation
//

import SwiftUI
internal import Combine

// MARK: - ViewModel

@MainActor
@Observable final class ConversationMediaGalleryViewModel {
    var images: [Message] = []
    var audioMessages: [Message] = []
    var linkMessages: [Message] = []

    var isLoadingImages = false
    var isLoadingAudio = false
    var isLoadingLinks = false
    var error: AppError?
    /// Per-tab load failures, so a failed fetch shows an error with Retry instead of the
    /// "No photos" empty state. Cleared when that tab loads again.
    var didFailLoadingImages = false
    var didFailLoadingAudio = false
    var didFailLoadingLinks = false

    let conversationId: UUID
    private let messageService = MessageService.shared

    init(conversationId: UUID) {
        self.conversationId = conversationId
    }

    func loadImages() async {
        guard !isLoadingImages else { return }
        isLoadingImages = true
        didFailLoadingImages = false
        do {
            images = try await messageService.fetchMediaMessages(conversationId: conversationId, type: "image")
        } catch {
            self.error = AppError.processingError(error.localizedDescription)
            didFailLoadingImages = true
        }
        isLoadingImages = false
    }

    func loadAudio() async {
        guard !isLoadingAudio else { return }
        isLoadingAudio = true
        didFailLoadingAudio = false
        do {
            audioMessages = try await messageService.fetchMediaMessages(conversationId: conversationId, type: "audio")
        } catch {
            self.error = AppError.processingError(error.localizedDescription)
            didFailLoadingAudio = true
        }
        isLoadingAudio = false
    }

    func loadLinks() async {
        guard !isLoadingLinks else { return }
        isLoadingLinks = true
        didFailLoadingLinks = false
        do {
            linkMessages = try await messageService.fetchLinkMessages(conversationId: conversationId)
        } catch {
            self.error = AppError.processingError(error.localizedDescription)
            didFailLoadingLinks = true
        }
        isLoadingLinks = false
    }
}

// MARK: - Media Tab

enum MediaTab: String, CaseIterable {
    case photos = "Photos"
    case audio = "Audio"
    case links = "Links"

    var localizedTitle: String {
        switch self {
        case .photos: return "messaging_media_photos".localized
        case .audio: return "messaging_media_audio".localized
        case .links: return "messaging_media_links".localized
        }
    }
}

// MARK: - Gallery View

struct ConversationMediaGalleryView: View {
    let conversationId: UUID
    @State private var viewModel: ConversationMediaGalleryViewModel
    @State private var selectedTab: MediaTab = .photos
    /// The photo open in the full-screen viewer. Presenting from the item (instead of a Bool
    /// plus a separate optional URL) means the viewer can never open before its URL is set.
    @State private var viewerImage: GalleryViewerImage?

    init(conversationId: UUID) {
        self.conversationId = conversationId
        _viewModel = State(initialValue: ConversationMediaGalleryViewModel(conversationId: conversationId))
    }
    
    var body: some View {
        VStack(spacing: 0) {
            // Tab picker
            Picker("messaging_media_type_picker".localized, selection: $selectedTab) {
                ForEach(MediaTab.allCases, id: \.self) { tab in
                    Text(tab.localizedTitle).tag(tab)
                }
            }
            .pickerStyle(.segmented)
            .padding(.horizontal)
            .padding(.vertical, 12)
            
            // Tab content
            switch selectedTab {
            case .photos:
                photosTab
            case .audio:
                audioTab
            case .links:
                linksTab
            }
        }
        .background(Color.naarsBackgroundSecondary)
        .navigationTitle("messaging_media_title".localized)
        .navigationBarTitleDisplayMode(.inline)
        .task {
            await viewModel.loadImages()
        }
        .onChange(of: selectedTab) { _, newTab in
            Task {
                switch newTab {
                case .photos:
                    if viewModel.images.isEmpty && !viewModel.isLoadingImages {
                        await viewModel.loadImages()
                    }
                case .audio:
                    if viewModel.audioMessages.isEmpty && !viewModel.isLoadingAudio {
                        await viewModel.loadAudio()
                    }
                case .links:
                    if viewModel.linkMessages.isEmpty && !viewModel.isLoadingLinks {
                        await viewModel.loadLinks()
                    }
                }
            }
        }
        .fullScreenCover(item: $viewerImage) { item in
            ImageViewerView(imageUrl: item.url, onDismiss: {
                viewerImage = nil
            })
        }
    }
    
    // MARK: - Photos Tab
    
    private let photoColumns = [
        GridItem(.flexible(), spacing: 2),
        GridItem(.flexible(), spacing: 2),
        GridItem(.flexible(), spacing: 2)
    ]
    
    private var photosTab: some View {
        Group {
            if viewModel.isLoadingImages {
                ProgressView()
                    .frame(maxWidth: .infinity, maxHeight: .infinity)
            } else if viewModel.didFailLoadingImages && viewModel.images.isEmpty {
                // A failed fetch is not "No Photos": say so and offer Retry.
                ErrorView(
                    error: "messaging_media_load_failed".localized,
                    retryAction: { Task { await viewModel.loadImages() } }
                )
            } else if viewModel.images.isEmpty {
                EmptyStateView(
                    icon: "photo.on.rectangle",
                    title: "messaging_no_photos".localized,
                    message: "messaging_photos_empty_state".localized
                )
            } else {
                ScrollView {
                    LazyVGrid(columns: photoColumns, spacing: 2) {
                        ForEach(viewModel.images) { message in
                            if let urlString = message.imageUrl, let url = URL(string: urlString) {
                                Button {
                                    viewerImage = GalleryViewerImage(url: url)
                                } label: {
                                    // A square cell with the photo scaled to fill it and the
                                    // overflow clipped. Forcing a 1:1 ratio on the resizable
                                    // image itself squashed every non-square photo.
                                    Color.clear
                                        .aspectRatio(1, contentMode: .fit)
                                        .overlay {
                                            CachedAsyncImage(
                                                url: url,
                                                placeholder: {
                                                    Color(.systemGray6)
                                                        .overlay(
                                                            ProgressView()
                                                                .scaleEffect(0.6)
                                                        )
                                                },
                                                errorView: {
                                                    Color(.systemGray5)
                                                        .overlay(
                                                            Image(systemName: "exclamationmark.triangle")
                                                                .foregroundColor(.secondary)
                                                        )
                                                }
                                            )
                                            .scaledToFill()
                                        }
                                        .clipped()
                                        .contentShape(Rectangle())
                                }
                                .buttonStyle(PlainButtonStyle())
                                .accessibilityLabel("messaging_media_photo_from_accessibility".localized(with: message.sender?.name ?? "common_unknown".localized))
                                .accessibilityHint("messaging_media_view_full_size_hint".localized)
                            }
                        }
                    }
                }
            }
        }
    }
    
    // MARK: - Audio Tab
    
    /// Voice notes that can be played. A row without an audio URL would look tappable and do
    /// nothing, so it is not listed.
    private var playableAudioMessages: [Message] {
        viewModel.audioMessages.filter { $0.audioUrl != nil }
    }

    private var audioTab: some View {
        Group {
            if viewModel.isLoadingAudio {
                ProgressView()
                    .frame(maxWidth: .infinity, maxHeight: .infinity)
            } else if viewModel.didFailLoadingAudio && viewModel.audioMessages.isEmpty {
                ErrorView(
                    error: "messaging_media_load_failed".localized,
                    retryAction: { Task { await viewModel.loadAudio() } }
                )
            } else if playableAudioMessages.isEmpty {
                EmptyStateView(
                    icon: "waveform",
                    title: "messaging_no_audio".localized,
                    message: "messaging_audio_empty_state".localized
                )
            } else {
                List(playableAudioMessages) { message in
                    GalleryAudioRow(message: message)
                        .listRowBackground(Color.clear)
                }
                .listStyle(.plain)
            }
        }
    }

    // MARK: - Links Tab
    
    private var linksTab: some View {
        Group {
            if viewModel.isLoadingLinks {
                ProgressView()
                    .frame(maxWidth: .infinity, maxHeight: .infinity)
            } else if viewModel.didFailLoadingLinks && viewModel.linkMessages.isEmpty {
                ErrorView(
                    error: "messaging_media_load_failed".localized,
                    retryAction: { Task { await viewModel.loadLinks() } }
                )
            } else if viewModel.linkMessages.isEmpty {
                EmptyStateView(
                    icon: "link",
                    title: "messaging_no_links".localized,
                    message: "messaging_links_empty_state".localized
                )
            } else {
                List(viewModel.linkMessages) { message in
                    linkRow(message: message)
                        .listRowBackground(Color.clear)
                }
                .listStyle(.plain)
            }
        }
    }
    
    private func linkRow(message: Message) -> some View {
        let urls = LinkPreviewService.shared.extractURLs(from: message.text)
        
        return VStack(alignment: .leading, spacing: 8) {
            // Sender and date
            HStack {
                Text(message.sender?.name ?? "common_unknown".localized)
                    .font(.naarsCaption)
                    .fontWeight(.medium)
                    .foregroundColor(.secondary)
                
                Spacer()
                
                Text(message.createdAt, style: .date)
                    .font(.naarsCaption)
                    .foregroundColor(.secondary)
            }
            
            // Message text preview
            if !message.text.isEmpty {
                Text(message.text)
                    .font(.naarsSubheadline)
                    .foregroundColor(.primary)
                    .lineLimit(2)
            }
            
            // Link previews
            ForEach(urls, id: \.absoluteString) { url in
                LinkPreviewView(url: url, isFromCurrentUser: false)
            }
        }
        .padding(.vertical, 4)
    }

}

// MARK: - Supporting Types

/// The photo shown in the full-screen viewer, as an item for `fullScreenCover(item:)`.
private struct GalleryViewerImage: Identifiable {
    let url: URL
    var id: String { url.absoluteString }
}

/// A voice note in the gallery's Audio tab. Tapping the row plays or pauses it through the
/// shared `MessageAudioPlayer`, the player the transcript's audio bubbles use. The rows used
/// to be static, so the tab listed voice notes that could not be played.
private struct GalleryAudioRow: View {
    let message: Message
    @StateObject private var player = MessageAudioPlayer.shared

    private var isCurrent: Bool {
        guard let audioUrl = message.audioUrl else { return false }
        return player.currentUrl?.absoluteString == audioUrl
    }

    private var isPlaying: Bool {
        isCurrent && player.isPlaying
    }

    private var senderName: String {
        message.sender?.name ?? "common_unknown".localized
    }

    var body: some View {
        Button {
            if let audioUrl = message.audioUrl {
                player.togglePlayback(urlString: audioUrl)
            }
        } label: {
            HStack(spacing: 12) {
                // Play / pause
                RoundedRectangle(cornerRadius: Constants.Radius.md)
                    .fill(Color.naarsPrimary.opacity(0.12))
                    .frame(width: 44, height: 44)
                    .overlay(
                        Image(systemName: isPlaying ? "pause.fill" : "play.fill")
                            .font(.naarsHeadline)
                            .foregroundColor(.naarsPrimary)
                    )

                VStack(alignment: .leading, spacing: 4) {
                    Text(senderName)
                        .font(.naarsSubheadline)
                        .fontWeight(.medium)
                        .foregroundColor(.primary)

                    HStack(spacing: 8) {
                        // Duration (elapsed / total while this note is playing)
                        if let duration = message.audioDuration {
                            Text(durationText(total: duration))
                                .font(.naarsCaption)
                                .foregroundColor(.secondary)
                                .monospacedDigit()

                            Text("·")
                                .foregroundColor(.secondary)
                        }

                        // Date
                        Text(message.createdAt, style: .date)
                            .font(.naarsCaption)
                            .foregroundColor(.secondary)
                    }
                }

                Spacer()
            }
            .padding(.vertical, 4)
            .contentShape(Rectangle())
        }
        .buttonStyle(.plain)
        .accessibilityLabel("messaging_media_voice_from_accessibility".localized(with: senderName))
        .accessibilityValue(message.audioDuration.map { durationText(total: $0) } ?? "")
        .accessibilityHint("accessibility_tap_to_toggle".localized)
        .accessibilityAddTraits(.startsMediaSession)
    }

    private func durationText(total: Double) -> String {
        guard isCurrent, player.progress > 0 else { return Self.format(total) }
        return "\(Self.format(total * player.progress)) / \(Self.format(total))"
    }

    private static func format(_ seconds: Double) -> String {
        let minutes = Int(seconds) / 60
        let secs = Int(seconds) % 60
        return String(format: "%d:%02d", minutes, secs)
    }
}

// MARK: - Preview

#Preview {
    NavigationStack {
        ConversationMediaGalleryView(conversationId: UUID())
    }
}
