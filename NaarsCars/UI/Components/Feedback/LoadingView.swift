//
//  LoadingView.swift
//  NaarsCars
//
//  Loading indicator with optional message
//

import SwiftUI

/// Loading view with spinner and optional message
struct LoadingView: View {
    var message: String? = nil
    
    var body: some View {
        VStack(spacing: 16) {
            ProgressView()
                .scaleEffect(1.2)
            
            if let message = message {
                Text(message)
                    .font(.body)
                    .foregroundColor(.secondary)
            }
        }
        .frame(maxWidth: .infinity, maxHeight: .infinity)
        .background(Color.gray.opacity(0.1))
    }
}

#Preview {
    LoadingView(message: "Loading...")
}

