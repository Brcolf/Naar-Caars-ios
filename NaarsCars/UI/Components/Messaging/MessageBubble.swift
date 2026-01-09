//
//  MessageBubble.swift
//  NaarsCars
//
//  Message bubble component for chat
//

import SwiftUI

/// Message bubble component
struct MessageBubble: View {
    let message: Message
    let isFromCurrentUser: Bool
    
    /// Check if message is an announcement (e.g., "User has been added to the conversation")
    private var isAnnouncement: Bool {
        message.text.contains("has been added to the conversation") ||
        message.text.contains("has joined the conversation")
    }
    
    var body: some View {
        if isAnnouncement {
            // Announcement style: centered, greyed out
            HStack {
                Spacer()
                Text(message.text)
                    .font(.naarsCaption)
                    .foregroundColor(.secondary)
                    .italic()
                    .padding(.horizontal, 12)
                    .padding(.vertical, 6)
                Spacer()
            }
            .padding(.vertical, 4)
        } else {
            // Regular message style
            HStack {
                if isFromCurrentUser {
                    Spacer()
                }
                
                VStack(alignment: isFromCurrentUser ? .trailing : .leading, spacing: 4) {
                    // Show sender name for group chats (if not from current user)
                    if !isFromCurrentUser, let sender = message.sender {
                        Text(sender.name)
                            .font(.naarsCaption)
                            .foregroundColor(.secondary)
                            .padding(.horizontal, 4)
                    }
                    
                    // Message text
                    Text(message.text)
                        .font(.naarsBody)
                        .foregroundColor(isFromCurrentUser ? .white : .primary)
                        .padding(.horizontal, 12)
                        .padding(.vertical, 8)
                        .background(
                            RoundedRectangle(cornerRadius: 16)
                                .fill(isFromCurrentUser ? Color.naarsPrimary : Color(.systemGray5))
                        )
                    
                    // Timestamp
                    Text(message.createdAt.timeAgoString)
                        .font(.naarsCaption)
                        .foregroundColor(.secondary)
                        .padding(.horizontal, 4)
                }
                .frame(maxWidth: UIScreen.main.bounds.width * 0.75, alignment: isFromCurrentUser ? .trailing : .leading)
                
                if !isFromCurrentUser {
                    Spacer()
                }
            }
        }
    }
}

#Preview {
    VStack(spacing: 16) {
        MessageBubble(
            message: Message(
                conversationId: UUID(),
                fromId: UUID(),
                text: "Hello! I can help with your ride request.",
                sender: Profile(id: UUID(), name: "John Doe", email: "john@example.com")
            ),
            isFromCurrentUser: false
        )
        
        MessageBubble(
            message: Message(
                conversationId: UUID(),
                fromId: UUID(),
                text: "Thanks! That would be great.",
                sender: nil
            ),
            isFromCurrentUser: true
        )
    }
    .padding()
}



