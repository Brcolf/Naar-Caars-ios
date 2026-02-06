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
final class ConversationMediaGalleryViewModel: ObservableObject {
    @Published var images: [Message] = []
    @Published var audioMessages: [Message] = []
    @Published var linkMessages: [Message] = []
    
    @Published var isLoadingImages = false
    @Published var isLoadingAudio = false
    @Published var isLoadingLinks = false
    @Published var error: AppError?
    
    let conversationId: UUID
    private let messageService = MessageService.shared
    
    init(conversationId: UUID) {
        self.conversationId = conversationId
    }
    
    func loadImages() async {
        guard !isLoadingImages else { return }
        isLoadingImages = true
        do {
            images = try await messageService.fetchMediaMessages(conversationId: conversationId, type: "image")
        } catch {
            self.error = AppError.processingError(error.localizedDescription)
        }
        isLoadingImages = false
    }
    
    func loadAudio() async {
        guard !isLoadingAudio else { return }
        isLoadingAudio = true
        do {
            audioMessages = try await messageService.fetchMediaMessages(conversationId: conversationId, type: "audio")
        } catch {
            self.error = AppError.processingError(error.localizedDescription)
        }
        isLoadingAudio = false
    }
    
    func loadLinks() async {
        guard !isLoadingLinks else { return }
        isLoadingLinks = true
        do {
            linkMessages = try await messageService.fetchLinkMessages(conversationId: conversationId)
        } catch {
            self.error = AppError.processingError(error.localizedDescription)
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
    @StateObject private var viewModel: ConversationMediaGalleryViewModel
    @State private var selectedTab: MediaTab = .photos
    @State private var selectedImageUrl: URL?
    @State private var showImageViewer = false
    
    init(conversationId: UUID) {
        self.conversationId = conversationId
        _viewModel = StateObject(wrappedValue: ConversationMediaGalleryViewModel(conversationId: conversationId))
    }
    
    var body: some View {
        VStack(spacing: 0) {
            // Tab picker
            Picker("Media Type", selection: $selectedTab) {
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
        .navigationTitle("Media")
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
        .fullScreenCover(isPresented: $showImageViewer) {
            if let imageUrl = selectedImageUrl {
                fullscreenImageViewer(imageUrl: imageUrl)
            }
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
                                    selectedImageUrl = url
                                    showImageViewer = true
                                } label: {
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
                                    .aspectRatio(contentMode: .fill)
                                    .frame(minHeight: 120)
                                    .clipped()
                                }
                                .buttonStyle(PlainButtonStyle())
                                .accessibilityLabel("Photo from \(message.sender?.name ?? "unknown")")
                                .accessibilityHint("Double-tap to view full size")
                            }
                        }
                    }
                }
            }
        }
    }
    
    // MARK: - Audio Tab
    
    private var audioTab: some View {
        Group {
            if viewModel.isLoadingAudio {
                ProgressView()
                    .frame(maxWidth: .infinity, maxHeight: .infinity)
            } else if viewModel.audioMessages.isEmpty {
                EmptyStateView(
                    icon: "waveform",
                    title: "messaging_no_audio".localized,
                    message: "messaging_audio_empty_state".localized
                )
            } else {
                List(viewModel.audioMessages) { message in
                    audioRow(message: message)
                        .listRowBackground(Color.clear)
                }
                .listStyle(.plain)
            }
        }
    }
    
    private func audioRow(message: Message) -> some View {
        HStack(spacing: 12) {
            // Waveform icon
            RoundedRectangle(cornerRadius: 10)
                .fill(Color.naarsPrimary.opacity(0.12))
                .frame(width: 44, height: 44)
                .overlay(
                    Image(systemName: "waveform")
                        .font(.system(size: 18))
                        .foregroundColor(.naarsPrimary)
                )
            
            VStack(alignment: .leading, spacing: 4) {
                Text(message.sender?.name ?? "Unknown")
                    .font(.naarsSubheadline)
                    .fontWeight(.medium)
                    .foregroundColor(.primary)
                
                HStack(spacing: 8) {
                    // Duration
                    if let duration = message.audioDuration {
                        Text(formatDuration(duration))
                            .font(.naarsCaption)
                            .foregroundColor(.secondary)
                    }
                    
                    Text("·")
                        .foregroundColor(.secondary)
                    
                    // Date
                    Text(message.createdAt, style: .date)
                        .font(.naarsCaption)
                        .foregroundColor(.secondary)
                }
            }
            
            Spacer()
        }
        .padding(.vertical, 4)
    }
    
    // MARK: - Links Tab
    
    private var linksTab: some View {
        Group {
            if viewModel.isLoadingLinks {
                ProgressView()
                    .frame(maxWidth: .infinity, maxHeight: .infinity)
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
                Text(message.sender?.name ?? "Unknown")
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
    
    // MARK: - Helpers
    
    private func formatDuration(_ seconds: Double) -> String {
        let minutes = Int(seconds) / 60
        let secs = Int(seconds) % 60
        return String(format: "%d:%02d", minutes, secs)
    }
    
    // MARK: - Fullscreen Image Viewer
    
    @ViewBuilder
    private func fullscreenImageViewer(imageUrl: URL) -> some View {
        ZStack {
            Color.black.ignoresSafeArea()
            
            AsyncImage(url: imageUrl) { phase in
                switch phase {
                case .success(let image):
                    image
                        .resizable()
                        .aspectRatio(contentMode: .fit)
                case .failure:
                    VStack {
                        Image(systemName: "exclamationmark.triangle")
                            .font(.system(size: 40))
                            .foregroundColor(.white.opacity(0.6))
                        Text("messaging_failed_to_load_image".localized)
                            .foregroundColor(.white.opacity(0.6))
                    }
                default:
                    ProgressView()
                        .progressViewStyle(CircularProgressViewStyle(tint: .white))
                }
            }
            
            // Close button
            VStack {
                HStack {
                    Spacer()
                    ShareLink(item: imageUrl) {
                        Image(systemName: "square.and.arrow.up")
                            .font(.naarsCallout).fontWeight(.semibold)
                            .foregroundColor(.white)
                            .padding(10)
                            .background(Circle().fill(Color.black.opacity(0.5)))
                    }
                    .padding(.trailing, 8)
                    
                    Button {
                        showImageViewer = false
                        selectedImageUrl = nil
                    } label: {
                        Image(systemName: "xmark")
                            .font(.system(size: 18, weight: .semibold))
                            .foregroundColor(.white)
                            .padding(12)
                            .background(Circle().fill(Color.black.opacity(0.5)))
                    }
                }
                .padding()
                Spacer()
            }
        }
    }
}

// MARK: - Preview

#Preview {
    NavigationStack {
        ConversationMediaGalleryView(conversationId: UUID())
    }
}
