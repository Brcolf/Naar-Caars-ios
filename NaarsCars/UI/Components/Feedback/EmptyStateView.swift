//
//  EmptyStateView.swift
//  NaarsCars
//
//  Empty state view with icon, title, message, and optional action
//

import SwiftUI

/// Empty state view for when there's no content to display
struct EmptyStateView: View {
    let icon: String
    let title: String
    let message: String
    var actionTitle: String? = nil
    var action: (() -> Void)? = nil
    /// Optional custom image name from assets (uses SF Symbol if nil)
    var customImage: String? = nil
    
    var body: some View {
        VStack(spacing: 16) {
            // Use custom image or SF Symbol
            if let customImage = customImage {
                Image(customImage)
                    .resizable()
                    .scaledToFit()
                    .frame(width: 120, height: 120)
            } else {
                Image(systemName: icon)
                    .font(.system(size: 64))
                    .foregroundColor(.secondary)
            }
            
            Text(title)
                .font(.naarsTitle3)
                .foregroundColor(.primary)
            
            Text(message)
                .font(.naarsBody)
                .foregroundColor(.secondary)
                .multilineTextAlignment(.center)
                .padding(.horizontal)
            
            if let actionTitle = actionTitle, let action = action {
                PrimaryButton(title: actionTitle, action: action)
                    .padding(.horizontal)
            }
        }
        .frame(maxWidth: .infinity, maxHeight: .infinity)
        .background(Color(.systemBackground))
    }
}

#Preview("SF Symbol") {
    EmptyStateView(
        icon: "car.fill",
        title: "No Rides Available",
        message: "There are no ride requests at this time. Check back later!",
        actionTitle: "Refresh",
        action: {}
    )
}

#Preview("Custom Image") {
    EmptyStateView(
        icon: "",
        title: "No Rides Yet",
        message: "Be the first to request or offer a ride in your community!",
        customImage: "SupremeLeader"
    )
}