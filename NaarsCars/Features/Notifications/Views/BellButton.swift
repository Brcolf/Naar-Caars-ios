//
//  BellButton.swift
//  NaarsCars
//
//  Bell icon button with badge for global chrome
//

import SwiftUI
import UIKit

struct BellButton: View {
    @ObservedObject private var badgeManager = BadgeCountManager.shared
    let action: () -> Void

    var body: some View {
        Button(action: {
            let generator = UIImpactFeedbackGenerator(style: .light)
            generator.prepare()
            generator.impactOccurred()
            action()
        }) {
            ZStack(alignment: .topTrailing) {
                Image(systemName: "bell")
                    .font(.title3)
                    .id("app.chrome.bellIcon")

                if badgeManager.bellBadgeCount > 0 {
                    Text(badgeText)
                        .font(.caption2)
                        .fontWeight(.semibold)
                        .foregroundColor(.white)
                        .padding(.horizontal, 6)
                        .padding(.vertical, 2)
                        .background(Color.red)
                        .clipShape(Capsule())
                        .offset(x: 6, y: -2)
                        .id("app.chrome.bellBadge")
                }
            }
        }
        .accessibilityLabel("Notifications")
        .accessibilityIdentifier("bell.button")
    }

    private var badgeText: String {
        if badgeManager.bellBadgeCount > 99 {
            return "99+"
        }
        return "\(badgeManager.bellBadgeCount)"
    }
}

