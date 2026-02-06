//
//  ScrollToBottomButton.swift
//  NaarsCars
//
//  Floating button to scroll to the bottom of the conversation
//

import SwiftUI

/// Floating button to scroll to the bottom of the conversation
struct ScrollToBottomButton: View {
    let unreadCount: Int
    let action: () -> Void
    
    var body: some View {
        Button(action: {
            let generator = UIImpactFeedbackGenerator(style: .light)
            generator.impactOccurred()
            action()
        }) {
            ZStack(alignment: .topTrailing) {
                Circle()
                    .fill(Color.naarsBackgroundSecondary)
                    .frame(width: 44, height: 44)
                    .shadow(color: .black.opacity(0.15), radius: 8, x: 0, y: 4)
                    .overlay(
                        Image(systemName: "chevron.down")
                            .font(.naarsCallout).fontWeight(.semibold)
                            .foregroundColor(.naarsPrimary)
                    )
                
                // Unread badge
                if unreadCount > 0 {
                    Text(unreadCount > 99 ? "99+" : "\(unreadCount)")
                        .font(.naarsCaption).fontWeight(.bold)
                        .foregroundColor(.white)
                        .padding(.horizontal, 6)
                        .padding(.vertical, 2)
                        .background(Color.naarsPrimary)
                        .clipShape(Capsule())
                        .offset(x: 8, y: -8)
                }
            }
        }
        .buttonStyle(PlainButtonStyle())
        .accessibilityIdentifier("messages.scrollToBottom")
    }
}

#Preview("Scroll Button") {
    VStack(spacing: 20) {
        ScrollToBottomButton(unreadCount: 0, action: {})
        ScrollToBottomButton(unreadCount: 5, action: {})
        ScrollToBottomButton(unreadCount: 150, action: {})
    }
    .padding()
    .background(Color(.systemGray5))
}
