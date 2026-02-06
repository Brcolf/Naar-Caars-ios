//
//  ConversationRow.swift
//  NaarsCars
//
//  Conversation row component (iMessage-style)
//

import SwiftUI

/// Conversation row component (iMessage-style)
struct ConversationRow: View {
    let conversationDetail: ConversationWithDetails
    var isMuted: Bool = false
    
    var body: some View {
        HStack(spacing: 12) {
            // Avatar on left
            ConversationAvatar(conversationDetail: conversationDetail)
                .frame(width: 50, height: 50)
            
            // Main content: Title, preview, and time
            VStack(alignment: .leading, spacing: Constants.Spacing.xs) {
                // Title and time row
                HStack(alignment: .top, spacing: Constants.Spacing.sm) {
                    // Title with fade effect for long names
                    // Use geometry reader to calculate available width
                    GeometryReader { geometry in
                        HStack(spacing: Constants.Spacing.xs) {
                            FadingTitleText(
                                text: conversationTitle,
                                maxWidth: geometry.size.width - (isMuted ? 80 : 60) // Reserve space for mute icon
                            )
                            .font(.naarsBody)
                            .fontWeight(conversationDetail.unreadCount > 0 ? .semibold : .regular)
                            .foregroundColor(.primary)
                            
                            // Muted indicator
                            if isMuted {
                                Image(systemName: "bell.slash.fill")
                                    .font(.naarsCaption)
                                    .foregroundColor(.secondary)
                            }
                            
                            Spacer(minLength: 8)
                        }
                    }
                    .frame(height: 20)
                    
                    // Time on right
                    if let lastMessage = conversationDetail.lastMessage {
                        Text(lastMessage.createdAt.timeAgoString)
                            .font(.naarsCaption)
                            .foregroundColor(.secondary)
                            .fixedSize(horizontal: true, vertical: false)
                    }
                }
                
                // Message preview (up to 2 lines)
                HStack(alignment: .top, spacing: Constants.Spacing.sm) {
                    // Preview text with icon for media messages
                    if let lastMessage = conversationDetail.lastMessage {
                        HStack(spacing: Constants.Spacing.xs) {
                            // Show icon for media messages
                            if lastMessage.isAudioMessage {
                                Image(systemName: "waveform")
                                    .font(.naarsCaption)
                                    .foregroundColor(.secondary)
                            } else if lastMessage.isLocationMessage {
                                Image(systemName: "location.fill")
                                    .font(.naarsCaption)
                                    .foregroundColor(.secondary)
                            } else if lastMessage.imageUrl != nil && lastMessage.text.isEmpty {
                                Image(systemName: "photo")
                                    .font(.naarsCaption)
                                    .foregroundColor(.secondary)
                            }
                            
                            Text(messagePreviewText(lastMessage))
                                .font(.naarsSubheadline)
                                .foregroundColor(.secondary)
                                .lineLimit(2)
                                .multilineTextAlignment(.leading)
                        }
                        .frame(maxWidth: .infinity, alignment: .leading)
                    } else {
                        Text("messaging_no_messages_yet".localized)
                            .font(.naarsSubheadline)
                            .foregroundColor(.secondary)
                            .italic()
                            .frame(maxWidth: .infinity, alignment: .leading)
                    }
                    
                    // Unread badge (if any)
                    if conversationDetail.unreadCount > 0 {
                        Text("\(conversationDetail.unreadCount)")
                            .font(.caption2)
                            .fontWeight(.semibold)
                            .foregroundColor(.white)
                            .padding(.horizontal, 6)
                            .padding(.vertical, 2)
                            .background(isMuted ? Color.secondary : Color.naarsPrimary)
                            .clipShape(Capsule())
                            .fixedSize(horizontal: true, vertical: false)
                    }
                }
            }
        }
        .padding(.vertical, 8)
        .contentShape(Rectangle()) // Make entire row tappable
    }
    
    /// Generate preview text for the message
    private func messagePreviewText(_ message: Message) -> String {
        if message.isAudioMessage {
            return "messaging_voice_message".localized
        } else if message.isLocationMessage {
            return message.locationName ?? "messaging_shared_location".localized
        } else if message.imageUrl != nil && message.text.isEmpty {
            return "Photo"
        } else {
            return message.text
        }
    }
    
    private var conversationTitle: String {
        // Priority 1: Group name (if conversation has a title)
        if let title = conversationDetail.conversation.title, !title.isEmpty {
            return title
        }
        
        // Priority 2: Participant names (comma-separated)
        if !conversationDetail.otherParticipants.isEmpty {
            let names = conversationDetail.otherParticipants.map { $0.name }
            return names.joined(separator: ", ")
        }
        
        // Fallback
        return "Unknown"
    }
}

/// Text view with fade effect for long content (iMessage-style)
/// Ensures text aligns left and fades to the right
struct FadingTitleText: View {
    let text: String
    let maxWidth: CGFloat
    
    var body: some View {
        ZStack(alignment: .leading) {
            // Full text (starts from left, may overflow)
            Text(text)
                .lineLimit(1)
                .frame(maxWidth: .infinity, alignment: .leading)
            
            // Overlay gradient for fade effect (on the right side)
            HStack(spacing: 0) {
                Spacer()
                LinearGradient(
                    gradient: Gradient(stops: [
                        .init(color: Color.naarsBackgroundSecondary.opacity(0), location: 0.0),
                        .init(color: Color.naarsBackgroundSecondary.opacity(0.5), location: 0.3),
                        .init(color: Color.naarsBackgroundSecondary, location: 0.8)
                    ]),
                    startPoint: .leading,
                    endPoint: .trailing
                )
                .frame(width: 40)
            }
            .allowsHitTesting(false)
        }
        .frame(width: maxWidth, alignment: .leading)
        .clipped()
    }
}
