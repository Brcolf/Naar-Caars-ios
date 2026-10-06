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
    /// Render as an inset rounded card (dashboard, profile) instead of a full-bleed panel.
    var isCard: Bool = false
    
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
                .fixedSize(horizontal: false, vertical: true)
                .padding(.horizontal)
            
            if let actionTitle = actionTitle, let action = action {
                PrimaryButton(title: actionTitle, action: action)
                    .padding(.horizontal)
            }
        }
        .padding(.vertical, 32)
        .frame(maxWidth: .infinity, maxHeight: .infinity)
        // Only the card variant draws a surface. Full-screen and nested uses take the ground
        // they sit on; the old opaque card color showed as a gray slab under the nav bar.
        .background(isCard ? Color.naarsCardBackground : Color.clear)
        .clipShape(RoundedRectangle(cornerRadius: isCard ? Constants.Radius.card : 0))
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