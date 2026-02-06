//
//  ConversationAvatar.swift
//  NaarsCars
//
//  Avatar view for conversations (single person or group)
//

import SwiftUI

/// Avatar view for conversations (single person or group)
struct ConversationAvatar: View {
    let conversationDetail: ConversationWithDetails
    
    var body: some View {
        Group {
            if conversationDetail.otherParticipants.count == 1, let participant = conversationDetail.otherParticipants.first {
                // Single person avatar
                AvatarView(
                    imageUrl: participant.avatarUrl,
                    name: participant.name,
                    size: 50
                )
            } else if conversationDetail.otherParticipants.count > 1 {
                // Group avatar
                groupAvatarView
            } else {
                // Default avatar
                AvatarView(imageUrl: nil, name: "Unknown", size: 50)
            }
        }
    }
    
    @ViewBuilder
    private var groupAvatarView: some View {
        // Check if group has a custom image
        if let groupImageUrl = conversationDetail.conversation.groupImageUrl,
           let url = URL(string: groupImageUrl) {
            // Show custom group image
            AsyncImage(url: url) { phase in
                switch phase {
                case .empty:
                    defaultGroupAvatar
                case .success(let image):
                    image
                        .resizable()
                        .scaledToFill()
                        .frame(width: 50, height: 50)
                        .clipShape(Circle())
                case .failure:
                    defaultGroupAvatar
                @unknown default:
                    defaultGroupAvatar
                }
            }
        } else if conversationDetail.otherParticipants.count >= 2 {
            // Show stacked avatars (2 participants)
            stackedAvatarsView
        } else {
            defaultGroupAvatar
        }
    }
    
    private var stackedAvatarsView: some View {
        ZStack {
            // Background circle
            Circle()
                .fill(Color(.systemGray5))
                .frame(width: 50, height: 50)
            
            // First participant (bottom-right)
            if let first = conversationDetail.otherParticipants.first {
                AvatarView(
                    imageUrl: first.avatarUrl,
                    name: first.name,
                    size: 30
                )
                .offset(x: 8, y: 8)
            }
            
            // Second participant (top-left)
            if conversationDetail.otherParticipants.count > 1 {
                let second = conversationDetail.otherParticipants[1]
                AvatarView(
                    imageUrl: second.avatarUrl,
                    name: second.name,
                    size: 30
                )
                .offset(x: -8, y: -8)
                .overlay(
                    Circle()
                        .stroke(Color.naarsBackgroundSecondary, lineWidth: 2)
                        .frame(width: 30, height: 30)
                        .offset(x: -8, y: -8)
                )
            }
            
            // Show +N badge if more than 2 other participants
            if conversationDetail.otherParticipants.count > 2 {
                Text("+\(conversationDetail.otherParticipants.count - 2)")
                    .font(.naarsCaption).fontWeight(.bold)
                    .foregroundColor(.white)
                    .padding(Constants.Spacing.xs)
                    .background(Color.naarsPrimary)
                    .clipShape(Circle())
                    .offset(x: 16, y: -16)
            }
        }
        .frame(width: 50, height: 50)
    }
    
    private var defaultGroupAvatar: some View {
        ZStack {
            Circle()
                .fill(Color.naarsPrimary.opacity(0.2))
                .frame(width: 50, height: 50)
            
            Image(systemName: "person.2.fill")
                .foregroundColor(.naarsPrimary)
                .font(.naarsTitle3)
        }
    }
}
