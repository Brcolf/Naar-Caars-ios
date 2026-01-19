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
    @State private var isAnimating = false
    @State private var opacity: Double = 0.3
    
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
                    isAnimating = true
                    opacity = 1.0
                }
            
            if let message = message {
                Text(message)
                    .font(.body)
                    .foregroundColor(.secondary)
            }
        }
        .frame(maxWidth: .infinity, maxHeight: .infinity)
        .background(Color(.systemBackground))
    }
}

#Preview {
    LoadingView(message: "Loading...")
}

