//
//  NotificationBadge.swift
//  NaarsCars
//
//  Notification badge component for tab bar
//

import SwiftUI

/// Notification badge component for displaying unread count
struct NotificationBadge: View {
    let count: Int
    
    var body: some View {
        if count > 0 {
            Text(count > 99 ? "99+" : "\(count)")
                .font(.naarsCaption).fontWeight(.semibold)
                .foregroundColor(.white)
                .padding(.horizontal, count > 9 ? 5 : 6)
                .padding(.vertical, 2)
                .background(Color.naarsPrimary)
                .clipShape(Capsule())
        }
    }
}

#Preview {
    HStack(spacing: 20) {
        NotificationBadge(count: 0)
        NotificationBadge(count: 5)
        NotificationBadge(count: 99)
        NotificationBadge(count: 150)
    }
    .padding()
}





