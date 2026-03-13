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
                    size: 56,
                    userId: participant.id
                )
            } else if conversationDetail.otherParticipants.count > 1 {
                // Group avatar
                groupAvatarView
            } else {
                // Default avatar
                AvatarView(imageUrl: nil, name: "Unknown", size: 56)
            }
        }
        .accessibilityElement(children: .ignore)
        .accessibilityLabel(conversationDetail.otherParticipants.map { $0.name }.joined(separator: ", "))
        .accessibilityAddTraits(.isImage)
    }
    
    @ViewBuilder
    private var groupAvatarView: some View {
        // Check if group has a custom image
        if let groupImageUrl = conversationDetail.conversation.groupImageUrl,
           let url = URL(string: groupImageUrl) {
            // Show custom group image
            CachedAsyncImage(
                url: url,
                placeholder: { defaultGroupAvatar },
                errorView: { defaultGroupAvatar }
            )
            .scaledToFill()
            .frame(width: 56, height: 56)
            .clipShape(Circle())
        } else if !conversationDetail.otherParticipants.isEmpty {
            // Show composite group avatar
            GroupAvatarComposite(
                participants: conversationDetail.otherParticipants.map {
                    .init(imageUrl: $0.avatarUrl, name: $0.name)
                },
                size: 56
            )
        } else {
            defaultGroupAvatar
        }
    }
    
    private var defaultGroupAvatar: some View {
        ZStack {
            Circle()
                .fill(Color.naarsPrimary.opacity(0.2))
                .frame(width: 56, height: 56)
            
            Image(systemName: "person.2.fill")
                .foregroundColor(.naarsPrimary)
                .font(.naarsTitle3)
        }
    }
}
