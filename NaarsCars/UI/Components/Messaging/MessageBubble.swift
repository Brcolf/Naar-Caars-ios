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
    var onLongPress: (() -> Void)? = nil
    var onReactionTap: ((String) -> Void)? = nil
    
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
                    
                    // Message image (if any)
                    if let imageUrl = message.imageUrl, let url = URL(string: imageUrl) {
                        AsyncImage(url: url) { phase in
                            switch phase {
                            case .empty:
                                ProgressView()
                                    .frame(width: 200, height: 200)
                            case .success(let image):
                                image
                                    .resizable()
                                    .scaledToFit()
                                    .frame(maxWidth: 200, maxHeight: 200)
                                    .cornerRadius(8)
                            case .failure:
                                Image(systemName: "photo")
                                    .resizable()
                                    .scaledToFit()
                                    .frame(width: 100, height: 100)
                                    .foregroundColor(.gray)
                            @unknown default:
                                EmptyView()
                            }
                        }
                        .padding(.bottom, message.text.isEmpty ? 0 : 4)
                    }
                    
                    // Message text (only show if not empty)
                    if !message.text.isEmpty {
                        Text(message.text)
                            .font(.naarsBody)
                            .foregroundColor(isFromCurrentUser ? .white : .primary)
                            .padding(.horizontal, 12)
                            .padding(.vertical, 8)
                            .background(
                                RoundedRectangle(cornerRadius: 16)
                                    .fill(isFromCurrentUser ? Color.naarsPrimary : Color(.systemGray5))
                            )
                    }
                    
                    // Reactions (if any)
                    if let reactions = message.reactions, !reactions.reactions.isEmpty {
                        HStack(spacing: 4) {
                            ForEach(reactions.sortedReactions.prefix(5), id: \.reaction) { reactionData in
                                Button(action: {
                                    onReactionTap?(reactionData.reaction)
                                }) {
                                    HStack(spacing: 2) {
                                        Text(reactionData.reaction)
                                            .font(.system(size: 14))
                                        if reactionData.count > 1 {
                                            Text("\(reactionData.count)")
                                                .font(.system(size: 10))
                                                .foregroundColor(.secondary)
                                        }
                                    }
                                    .padding(.horizontal, 6)
                                    .padding(.vertical, 3)
                                    .background(
                                        RoundedRectangle(cornerRadius: 12)
                                            .fill(Color(.systemGray5))
                                    )
                                }
                                .buttonStyle(PlainButtonStyle())
                            }
                        }
                        .padding(.top, 4)
                    }
                    
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
            .onLongPressGesture {
                onLongPress?()
            }
        }
    }
}

#Preview {
    let sampleMessage1 = Message(
        conversationId: UUID(),
        fromId: UUID(),
        text: "Hello! I can help with your ride request.",
        sender: Profile(id: UUID(), name: "John Doe", email: "john@example.com")
    )
    
    let sampleMessage2 = Message(
        conversationId: UUID(),
        fromId: UUID(),
        text: "Thanks! That would be great."
    )
    
    return VStack(spacing: 16) {
        MessageBubble(
            message: sampleMessage1,
            isFromCurrentUser: false
        )
        
        MessageBubble(
            message: sampleMessage2,
            isFromCurrentUser: true
        )
    }
    .padding()
}



