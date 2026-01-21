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
                
                // Image
                AsyncImage(url: imageUrl) { phase in
                    switch phase {
                    case .empty:
                        ProgressView()
                            .progressViewStyle(CircularProgressViewStyle(tint: .white))
                            .scaleEffect(1.5)
                    case .success(let image):
                        image
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
                    case .failure:
                        VStack(spacing: 12) {
                            Image(systemName: "exclamationmark.triangle")
                                .font(.system(size: 40))
                                .foregroundColor(.white.opacity(0.6))
                            Text("Failed to load image")
                                .font(.naarsBody)
                                .foregroundColor(.white.opacity(0.6))
                        }
                    @unknown default:
                        EmptyView()
                    }
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
                                        .font(.system(size: 22))
                                    Text("Share")
                                        .font(.system(size: 12))
                                }
                                .foregroundColor(.white)
                            }
                            
                            // Save button
                            Button(action: saveImage) {
                                VStack(spacing: 6) {
                                    Image(systemName: "arrow.down.to.line")
                                        .font(.system(size: 22))
                                    Text("Save")
                                        .font(.system(size: 12))
                                }
                                .foregroundColor(.white)
                            }
                        }
                        .padding(.bottom, 40)
                    }
                    .transition(.opacity)
                }
            }
        }
        .statusBar(hidden: !showControls)
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
        Task {
            guard let data = try? Data(contentsOf: imageUrl),
                  let image = UIImage(data: data) else { return }
            
            await MainActor.run {
                let activityVC = UIActivityViewController(activityItems: [image], applicationActivities: nil)
                
                if let windowScene = UIApplication.shared.connectedScenes.first as? UIWindowScene,
                   let rootViewController = windowScene.windows.first?.rootViewController {
                    rootViewController.present(activityVC, animated: true)
                }
            }
        }
    }
    
    private func saveImage() {
        Task {
            guard let data = try? Data(contentsOf: imageUrl),
                  let image = UIImage(data: data) else { return }
            
            UIImageWriteToSavedPhotosAlbum(image, nil, nil, nil)
            
            // Haptic feedback
            let generator = UINotificationFeedbackGenerator()
            generator.notificationOccurred(.success)
        }
    }
}

// MARK: - Preview

#Preview {
    ImageViewerView(
        imageUrl: URL(string: "https://picsum.photos/800/600")!,
        onDismiss: {}
    )
}

