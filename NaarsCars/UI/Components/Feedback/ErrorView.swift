//
//  ErrorView.swift
//  NaarsCars
//
//  Error display with retry action
//

import SwiftUI

/// Error view with message and retry button
struct ErrorView: View {
    let error: String
    let retryAction: (() -> Void)?
    
    init(error: String, retryAction: (() -> Void)? = nil) {
        self.error = error
        self.retryAction = retryAction
    }
    
    var body: some View {
        VStack(spacing: 16) {
            Image(systemName: "exclamationmark.triangle")
                .font(.system(size: 48))
                .foregroundColor(.naarsError)
            
            Text("Error")
                .font(.naarsTitle2)
                .foregroundColor(.primary)
            
            Text(error)
                .font(.naarsBody)
                .foregroundColor(.secondary)
                .multilineTextAlignment(.center)
                .padding(.horizontal)
            
            if let retryAction = retryAction {
                PrimaryButton(title: "Retry", action: retryAction)
                    .padding(.horizontal)
            }
        }
        .frame(maxWidth: .infinity, maxHeight: .infinity)
        .background(Color(.systemBackground))
    }
}

#Preview {
    ErrorView(error: "Failed to load data. Please check your connection and try again.", retryAction: {})
}

