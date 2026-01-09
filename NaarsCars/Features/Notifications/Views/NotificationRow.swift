//
//  NotificationRow.swift
//  NaarsCars
//
//  Notification row component
//

import SwiftUI

/// Notification row component for displaying individual notifications
struct NotificationRow: View {
    let notification: AppNotification
    let onTap: () -> Void
    
    var body: some View {
        Button(action: onTap) {
            HStack(spacing: 12) {
                // Icon
                Image(systemName: notification.type.icon)
                    .font(.title3)
                    .foregroundColor(notification.read ? .secondary : .naarsPrimary)
                    .frame(width: 40, height: 40)
                    .background(
                        Circle()
                            .fill(notification.read ? Color.gray.opacity(0.1) : Color.naarsPrimary.opacity(0.1))
                    )
                
                // Content
                VStack(alignment: .leading, spacing: 4) {
                    HStack {
                        Text(notification.title)
                            .font(.naarsHeadline)
                            .foregroundColor(notification.read ? .secondary : .primary)
                        
                        Spacer()
                        
                        if notification.pinned {
                            Image(systemName: "pin.fill")
                                .font(.caption)
                                .foregroundColor(.naarsPrimary)
                        }
                    }
                    
                    if let body = notification.body {
                        Text(body)
                            .font(.naarsBody)
                            .foregroundColor(.secondary)
                            .lineLimit(2)
                    }
                    
                    Text(notification.createdAt.timeAgoString)
                        .font(.naarsCaption)
                        .foregroundColor(.secondary)
                }
                
                // Unread indicator
                if !notification.read {
                    Circle()
                        .fill(Color.naarsPrimary)
                        .frame(width: 8, height: 8)
                }
            }
            .padding()
            .background(
                RoundedRectangle(cornerRadius: 12)
                    .fill(notification.read ? Color(.systemBackground) : Color.naarsPrimary.opacity(0.05))
            )
        }
        .buttonStyle(PlainButtonStyle())
    }
}

#Preview {
    VStack(spacing: 12) {
        NotificationRow(
            notification: AppNotification(
                userId: UUID(),
                type: .message,
                title: "New Message",
                body: "You have a new message from John Doe",
                read: false
            ),
            onTap: {}
        )
        
        NotificationRow(
            notification: AppNotification(
                userId: UUID(),
                type: .rideClaimed,
                title: "Ride Claimed",
                body: "Your ride request has been claimed",
                read: true
            ),
            onTap: {}
        )
        
        NotificationRow(
            notification: AppNotification(
                userId: UUID(),
                type: .announcement,
                title: "Important Announcement",
                body: "This is a pinned announcement",
                read: false,
                pinned: true
            ),
            onTap: {}
        )
    }
    .padding()
}



