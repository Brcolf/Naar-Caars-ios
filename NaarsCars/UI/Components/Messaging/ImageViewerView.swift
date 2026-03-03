//
//  ImageViewerView.swift
//  NaarsCars
//
//  Fullscreen image viewer with zoom and pan gestures
//

import SwiftUI

/// Fullscreen image viewer with zoom and pan
struct ImageViewerView: View {
    let imageUrl: URL
    let onDismiss: () -> Void
    
    @State private var scale: CGFloat = 1.0
    @State private var lastScale: CGFloat = 1.0
    @State private var offset: CGSize = .zero
    @State private var lastOffset: CGSize = .zero
    @State private var showControls = true
    @GestureState private var dragOffset: CGSize = .zero
    @State private var loadedImage: UIImage?
    @State private var loadFailed = false
    
    private let minScale: CGFloat = 1.0
    private let maxScale: CGFloat = 5.0
    
    var body: some View {
        GeometryReader { geometry in
            ZStack {
                // Background
                Color.black
                    .ignoresSafeArea()
                    .onTapGesture {
                        withAnimation(.easeInOut(duration: 0.2)) {
                            showControls.toggle()
                        }
                    }
                
                // Image (loaded via PersistentImageService disk cache)
                if let uiImage = loadedImage {
                    Image(uiImage: uiImage)
                        .resizable()
                        .aspectRatio(contentMode: .fit)
                        .scaleEffect(scale)
                        .offset(x: offset.width + dragOffset.width, y: offset.height + dragOffset.height)
                        .gesture(combinedGesture)
                        .onTapGesture(count: 2) {
                            // Double tap to zoom in/out
                            withAnimation(.spring(response: 0.3, dampingFraction: 0.7)) {
                                if scale > 1.0 {
                                    scale = 1.0
                                    offset = .zero
                                } else {
                                    scale = 2.5
                                }
                            }
                        }
                        .onTapGesture {
                            withAnimation(.easeInOut(duration: 0.2)) {
                                showControls.toggle()
                            }
                        }
                } else if loadFailed {
                    VStack(spacing: 12) {
                        Image(systemName: "exclamationmark.triangle")
                            .font(.system(size: 40))
                            .foregroundColor(.white.opacity(0.6))
                        Text("messaging_failed_to_load_image".localized)
                            .font(.naarsBody)
                            .foregroundColor(.white.opacity(0.6))
                    }
                } else {
                    ProgressView()
                        .progressViewStyle(CircularProgressViewStyle(tint: .white))
                        .scaleEffect(1.5)
                }
                
                // Controls overlay
                if showControls {
                    VStack {
                        // Top bar
                        HStack {
                            Spacer()
                            
                            // Close button
                            Button(action: onDismiss) {
                                Image(systemName: "xmark")
                                    .font(.system(size: 18, weight: .semibold))
                                    .foregroundColor(.white)
                                    .padding(12)
                                    .background(Circle().fill(Color.black.opacity(0.5)))
                            }
                        }
                        .padding()
                        
                        Spacer()
                        
                        // Bottom bar with actions
                        HStack(spacing: 40) {
                            // Share button
                            Button(action: shareImage) {
                                VStack(spacing: 6) {
                                    Image(systemName: "square.and.arrow.up")
                                        .font(.naarsTitle2)
                                    Text("common_share".localized)
                                        .font(.naarsFootnote)
                                }
                                .foregroundColor(.white)
                            }
                            .disabled(loadedImage == nil)
                            .opacity(loadedImage != nil ? 1.0 : 0.4)

                            // Save button
                            Button(action: saveImage) {
                                VStack(spacing: 6) {
                                    Image(systemName: "arrow.down.to.line")
                                        .font(.naarsTitle2)
                                    Text("common_save".localized)
                                        .font(.naarsFootnote)
                                }
                                .foregroundColor(.white)
                            }
                            .disabled(loadedImage == nil)
                            .opacity(loadedImage != nil ? 1.0 : 0.4)
                        }
                        .padding(.bottom, 40)
                    }
                    .transition(.opacity)
                }
            }
        }
        .statusBar(hidden: !showControls)
        .task {
            let loaded = await PersistentImageService.shared.getImage(for: imageUrl.absoluteString)
            if let loaded {
                withAnimation(.easeIn(duration: 0.2)) {
                    self.loadedImage = loaded
                }
            } else {
                loadFailed = true
            }
        }
    }
    
    // MARK: - Gestures
    
    private var combinedGesture: some Gesture {
        SimultaneousGesture(
            // Magnification gesture
            MagnifyGesture()
                .onChanged { value in
                    let newScale = lastScale * value.magnification
                    scale = min(max(newScale, minScale), maxScale)
                }
                .onEnded { _ in
                    lastScale = scale
                    // Reset offset if zoomed out
                    if scale <= 1.0 {
                        withAnimation(.spring(response: 0.3, dampingFraction: 0.7)) {
                            offset = .zero
                        }
                    }
                },
            // Drag gesture (only when zoomed)
            DragGesture()
                .updating($dragOffset) { value, state, _ in
                    if scale > 1.0 {
                        state = value.translation
                    }
                }
                .onEnded { value in
                    if scale > 1.0 {
                        offset.width += value.translation.width
                        offset.height += value.translation.height
                        lastOffset = offset
                    } else {
                        // Swipe down to dismiss when not zoomed
                        if value.translation.height > 100 && abs(value.translation.width) < 100 {
                            onDismiss()
                        }
                    }
                }
        )
    }
    
    // MARK: - Actions
    
    private func shareImage() {
        guard let image = loadedImage else { return }
        let activityVC = UIActivityViewController(activityItems: [image], applicationActivities: nil)

        if let windowScene = UIApplication.shared.connectedScenes.first as? UIWindowScene,
           let rootViewController = windowScene.windows.first?.rootViewController {
            rootViewController.present(activityVC, animated: true)
        }
    }

    private func saveImage() {
        guard let image = loadedImage else { return }
        UIImageWriteToSavedPhotosAlbum(image, nil, nil, nil)

        // Haptic feedback
        let generator = UINotificationFeedbackGenerator()
        generator.notificationOccurred(.success)
    }
}

// MARK: - Preview

#Preview {
    ImageViewerView(
        imageUrl: URL(string: "https://picsum.photos/800/600")!,
        onDismiss: {}
    )
}


