//
//  LoadingView.swift
//  NaarsCars
//
//  Loading indicator with optional message
//

import SwiftUI

/// Loading view with animated logo and optional message
struct LoadingView: View {
    var message: String? = nil
    /// Nested in a screen that already draws its own ground (detail and profile loads): no
    /// surface of its own. The default is the opaque full-screen form used at launch, which
    /// has to match the launch screen's background.
    var isEmbedded: Bool = false
    @Environment(\.accessibilityReduceMotion) private var reduceMotion
    @State private var isAnimating = false
    // Starts fully opaque and breathes down: the launch screen shows the same logo at the same
    // size and position, so the hand-off from launch screen to this view has no dim flash.
    @State private var opacity: Double = 1.0
    
    var body: some View {
        VStack(spacing: 24) {
            // Animated full logo
            Image("NaarsLogo")
                .resizable()
                .scaledToFit()
                .frame(width: 200, height: 200)
                .scaleEffect(isAnimating ? 1.1 : 1.0)
                .opacity(opacity)
                .animation(
                    .easeInOut(duration: 1.0)
                    .repeatForever(autoreverses: true),
                    value: isAnimating
                )
                .animation(
                    .easeInOut(duration: 1.5)
                    .repeatForever(autoreverses: true),
                    value: opacity
                )
                .onAppear {
                    // Reduce Motion: hold the logo at full size and opacity (the launch-screen
                    // pose) instead of pulsing it for as long as the load takes.
                    guard !reduceMotion else { return }
                    isAnimating = true
                    opacity = 0.55
                }
            
            if let message = message {
                Text(message)
                    .font(.naarsBody)
                    .foregroundColor(.secondary)
            }
        }
        .frame(maxWidth: .infinity, maxHeight: .infinity)
        // Embedded, the opaque fill showed as a square white slab inset in the grouped ground.
        .background(isEmbedded ? Color.clear : Color.naarsBackgroundSecondary)
    }
}

#Preview {
    LoadingView(message: "Loading...")
}

