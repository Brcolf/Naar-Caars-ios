//
//  BellButton.swift
//  NaarsCars
//
//  Bell icon button with badge for global chrome
//

import SwiftUI
import UIKit

struct BellButton: View {
    @State private var badgeManager = BadgeCountManager.shared
    let action: () -> Void

    var body: some View {
        Button(action: {
            HapticManager.lightImpact()
            action()
        }) {
            ZStack(alignment: .topTrailing) {
                Image(systemName: "bell")
                    .font(.naarsTitle3)
                    .id("app.chrome.bellIcon")

                NotificationBadge(count: badgeManager.counts.bell)
                    .offset(x: 8, y: -4)
                    .id("app.chrome.bellBadge")
            }
        }
        .accessibilityLabel(badgeManager.counts.bell > 0 ? "notifications_bell_unread_accessibility".localized(with: badgeManager.counts.bell) : "notifications_title".localized)
        .accessibilityHint("notifications_bell_hint".localized)
        .accessibilityIdentifier("bell.button")
    }
}

