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

    @Environment(\.dynamicTypeSize) private var dynamicTypeSize

    /// Name plus the muted bell. One line with a trailing ellipsis at standard sizes; two lines
    /// at accessibility sizes. Sized by its text, so it follows Dynamic Type (the previous
    /// fixed 20-pt row clipped the name at larger sizes).
    private var titleLabel: some View {
        HStack(spacing: Constants.Spacing.xs) {
            Text(conversationTitle)
                .font(.naarsBody)
                .fontWeight(conversationDetail.unreadCount > 0 ? .semibold : .regular)
                .foregroundColor(.primary)
                .lineLimit(dynamicTypeSize.isAccessibilitySize ? 2 : 1)
                .truncationMode(.tail)

            if isMuted {
                Image(systemName: "bell.slash.fill")
                    .font(.naarsCaption)
                    .foregroundColor(.secondary)
            }
        }
    }

    @ViewBuilder
    private var timeLabel: some View {
        if let lastMessage = conversationDetail.lastMessage {
            Text(lastMessage.createdAt.conversationListTimestampString)
                .font(.naarsCaption)
                .foregroundColor(.secondary)
                .fixedSize(horizontal: true, vertical: false)
        }
    }

    var body: some View {
        HStack(spacing: 12) {
            // Avatar on left
            ConversationAvatar(conversationDetail: conversationDetail)
                .frame(width: 56, height: 56)
            
            // Main content: Title, preview, and time
            VStack(alignment: .leading, spacing: Constants.Spacing.xs) {
                // Title and time row. At accessibility text sizes the name gets the full width
                // and the time moves under it: side by side, the time (which never truncates)
                // squeezed the name down to "…".
                if dynamicTypeSize.isAccessibilitySize {
                    VStack(alignment: .leading, spacing: 2) {
                        titleLabel
                        timeLabel
                    }
                } else {
                    HStack(alignment: .firstTextBaseline, spacing: Constants.Spacing.sm) {
                        titleLabel
                        Spacer(minLength: 8)
                        timeLabel
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
                        NotificationBadge(count: conversationDetail.unreadCount, style: isMuted ? .muted : .alert)
                    }
                }
            }
        }
        .padding(.vertical, 11)
        .contentShape(Rectangle()) // Make entire row tappable
        .accessibilityElement(children: .combine)
        .accessibilityLabel(conversationRowAccessibilityLabel)
        // The unread count is state, not a usage hint: as the value it is still spoken when
        // VoiceOver hints are turned off.
        .accessibilityValue(conversationDetail.unreadCount > 0
            ? "messaging_unread_count_accessibility".localized(with: conversationDetail.unreadCount)
            : "")
    }
    
    /// Generate preview text for the message
    private func messagePreviewText(_ message: Message) -> String {
        if MessageService.shared.isBlocked(message.fromId) {
            return "messaging_blocked_user_message".localized
        }
        if message.isAudioMessage {
            return "messaging_voice_message".localized
        } else if message.isLocationMessage {
            return message.locationName ?? "messaging_shared_location".localized
        } else if message.imageUrl != nil && message.text.isEmpty {
            return "messaging_photo".localized
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
        return "common_unknown".localized
    }

    private var conversationRowAccessibilityLabel: String {
        var parts: [String] = [conversationTitle]
        if isMuted { parts.append("messaging_muted".localized) }
        if let lastMessage = conversationDetail.lastMessage {
            parts.append(messagePreviewText(lastMessage))
            parts.append(lastMessage.createdAt.timeAgoString)
        }
        return parts.joined(separator: ", ")
    }
}
