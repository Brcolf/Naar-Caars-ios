//
//  MessageBubble.swift
//  NaarsCars
//
//  Message bubble component for chat (iMessage-style)
//

import SwiftUI
import AVFoundation
import MapKit
import UIKit
internal import Combine

/// Message bubble component with iMessage-style design
struct MessageBubble: View {
    let message: Message
    let isFromCurrentUser: Bool
    
    /// Whether to show the sender's avatar (for group chats)
    var showAvatar: Bool = false
    
    /// Whether this is the first message in a consecutive series from the same sender
    var isFirstInSeries: Bool = true
    
    /// Whether this is the last message in a consecutive series from the same sender
    var isLastInSeries: Bool = true
    
    /// Whether to animate this message (for new messages)
    var shouldAnimate: Bool = false
    
    /// Total participant count for group read receipts
    var totalParticipants: Int = 2

    /// Whether to show the reply preview (for thread views)
    var showReplyPreview: Bool = true

    /// Optional reply spine details for main thread threading
    var replySpine: (showTop: Bool, showBottom: Bool)? = nil
    
    /// Whether this message failed to send
    var isFailed: Bool = false
    
    var onLongPress: (() -> Void)? = nil
    var onReactionTap: ((String) -> Void)? = nil
    var onReply: (() -> Void)? = nil
    var onCopy: (() -> Void)? = nil
    var onDelete: (() -> Void)? = nil
    var onEdit: (() -> Void)? = nil
    var onUnsend: (() -> Void)? = nil
    var onImageTap: ((URL) -> Void)? = nil
    var onReport: (() -> Void)? = nil
    var onReplyPreviewTap: ((UUID) -> Void)? = nil
    /// Callback when a failed message is tapped for retry
    var onRetry: (() -> Void)? = nil
    var isHighlighted: Bool = false
    
    // Animation states
    @State private var hasAppeared = false
    @State private var showContextMenu = false
    @State private var showTimestampOverride = false
    @ObservedObject private var audioPlayer = MessageAudioPlayer.shared
    @AppStorage("messaging_showLinkPreviews") private var showLinkPreviews = true
    
    // Swipe-to-reply state
    @State private var swipeOffset: CGFloat = 0
    @State private var isSwipingToReply = false
    private let swipeThreshold: CGFloat = 60
    private let waveformHeights: [CGFloat] = [10, 14, 18, 12, 22, 16, 20, 12, 24, 14, 18, 10, 16, 22, 12, 20, 14, 18, 12, 16]
    private let bubbleMaxWidth: CGFloat = UIScreen.main.bounds.width * 0.7
    private let replyPreviewMaxWidth: CGFloat = UIScreen.main.bounds.width * 0.75

    private var replySpineOffset: CGFloat {
        if isFromCurrentUser {
            return 6
        }
        return showAvatar ? -22 : -6
    }
    
    /// Extract URLs from message text (cached to avoid re-running NSDataDetector on every render)
    private var detectedURLs: [URL] {
        Self.urlCache.urls(for: message.text)
    }
    
    /// Shared URL detection cache to avoid expensive NSDataDetector on every SwiftUI body evaluation
    private static let urlCache = URLDetectionCache()
    
    /// Check if message is a system message (announcement)
    private var isSystemMessage: Bool {
        // Check for system message patterns
        let systemPatterns = [
            "has been added to the conversation",
            "has joined the conversation",
            "left the conversation",
            "removed",
            "updated the group",
            "changed the group name",
            "created the group"
        ]
        return systemPatterns.contains { message.text.contains($0) }
    }
    
    /// Read receipt status
    private enum ReadStatus {
        case failed     // Message failed to send
        case sending    // No read_by yet (optimistic)
        case sent       // Only sender in read_by
        case delivered  // At least one other person received
        case read       // All participants have read
    }
    
    private var readStatus: ReadStatus {
        // Check if the message is marked as failed
        if isFailed {
            return .failed
        }
        
        // Filter out the sender to correctly calculate who else has read the message
        let readByOthers = message.readBy.filter { $0 != message.fromId }
        let otherParticipants = max(totalParticipants - 1, 0)
        
        if message.readBy.isEmpty {
            return .sending
        } else if readByOthers.isEmpty {
            return .sent
        } else if otherParticipants > 0 && readByOthers.count >= otherParticipants {
            return .read
        } else {
            return .delivered
        }
    }
    
    /// Read receipt indicator view
    private var readReceiptIndicator: some View {
        Group {
            switch readStatus {
            case .failed:
                // Red exclamation circle for failed
                Image(systemName: "exclamationmark.circle.fill")
                    .font(.naarsFootnote)
                    .foregroundColor(.red)
            case .sending:
                // Clock icon for sending
                Image(systemName: "clock")
                    .font(.naarsCaption)
                    .foregroundColor(.secondary.opacity(0.6))
            case .sent:
                // Single checkmark for sent
                Image(systemName: "checkmark")
                    .font(.naarsCaption).fontWeight(.semibold)
                    .foregroundColor(.secondary)
            case .delivered:
                // Double checkmark (gray) for delivered
                HStack(spacing: -4) {
                    Image(systemName: "checkmark")
                        .font(.naarsCaption).fontWeight(.semibold)
                    Image(systemName: "checkmark")
                        .font(.naarsCaption).fontWeight(.semibold)
                }
                .foregroundColor(.secondary)
            case .read:
                // Double checkmark (blue) for read
                HStack(spacing: -4) {
                    Image(systemName: "checkmark")
                        .font(.naarsCaption).fontWeight(.semibold)
                    Image(systemName: "checkmark")
                        .font(.naarsCaption).fontWeight(.semibold)
                }
                .foregroundColor(.naarsPrimary)
            }
        }
    }
    
    var body: some View {
        if message.isUnsent {
            unsentMessageView
                .transition(.opacity.combined(with: .scale(scale: 0.95)))
        } else if isSystemMessage {
            systemMessageView
                .transition(.opacity.combined(with: .scale(scale: 0.95)))
        } else {
            regularMessageView
                .scaleEffect(hasAppeared ? 1.0 : 0.8)
                .opacity(hasAppeared ? 1.0 : 0.0)
                .offset(x: hasAppeared ? 0 : (isFromCurrentUser ? 50 : -50))
                .onAppear {
                    if shouldAnimate && !hasAppeared {
                        withAnimation(.spring(response: 0.35, dampingFraction: 0.7)) {
                            hasAppeared = true
                        }
                    } else {
                        hasAppeared = true
                    }
                }
        }
    }
    
    // MARK: - Unsent Message View
    
    private var unsentMessageView: some View {
        HStack {
            if isFromCurrentUser { Spacer(minLength: 60) }
            
            HStack(spacing: 6) {
                Image(systemName: "nosign")
                    .font(.naarsFootnote)
                    .foregroundColor(.secondary)
                
                Text(isFromCurrentUser ? "messaging_you_unsent_a_message".localized : "messaging_this_message_was_unsent".localized)
                    .font(.naarsCaption)
                    .italic()
                    .foregroundColor(.secondary)
            }
            .padding(.horizontal, 14)
            .padding(.vertical, 10)
            .background(
                RoundedRectangle(cornerRadius: 18)
                    .strokeBorder(Color(.systemGray4), lineWidth: 1)
            )
            
            if !isFromCurrentUser { Spacer(minLength: 60) }
        }
        .padding(.vertical, isLastInSeries ? 8 : 2)
    }
    
    // MARK: - System Message View
    
    private var systemMessageView: some View {
        HStack {
            Spacer()
            
            HStack(spacing: 6) {
                // Icon based on message type
                Image(systemName: systemMessageIcon)
                    .font(.naarsCaption)
                    .foregroundColor(.secondary)
                
                Text(message.text)
                    .font(.naarsCaption)
                    .foregroundColor(.secondary)
                    .multilineTextAlignment(.center)
            }
            .padding(.horizontal, 12)
            .padding(.vertical, 6)
            .background(
                Capsule()
                    .fill(Color.naarsCardBackground)
            )
            
            Spacer()
        }
        .padding(.vertical, 8)
    }
    
    private var systemMessageIcon: String {
        if message.text.contains("added") || message.text.contains("joined") {
            return "person.badge.plus"
        } else if message.text.contains("left") || message.text.contains("removed") {
            return "person.badge.minus"
        } else if message.text.contains("photo") || message.text.contains("image") {
            return "photo"
        } else if message.text.contains("name") {
            return "pencil"
        } else if message.text.contains("created") {
            return "sparkles"
        }
        return "info.circle"
    }
    
    // MARK: - Regular Message View
    
    private var regularMessageView: some View {
        HStack(alignment: .bottom, spacing: Constants.Spacing.sm) {
            // Reply indicator (shown when swiping)
            if !isFromCurrentUser && swipeOffset > 20 {
                Image(systemName: "arrowshape.turn.up.left.fill")
                    .font(.naarsCallout)
                    .foregroundColor(.naarsPrimary)
                    .opacity(min(1.0, swipeOffset / swipeThreshold))
                    .scaleEffect(min(1.0, swipeOffset / swipeThreshold))
            }
            
            // Avatar (for received messages in group chats)
            if !isFromCurrentUser && showAvatar {
                if isLastInSeries {
                    // Show avatar for last message in series
                    if let sender = message.sender {
                        AvatarView(
                            imageUrl: sender.avatarUrl,
                            name: sender.name,
                            size: 28
                        )
                    } else {
                        // Placeholder avatar
                        Circle()
                            .fill(Color(.systemGray4))
                            .frame(width: 28, height: 28)
                    }
                } else {
                    // Spacer to maintain alignment
                    Spacer()
                        .frame(width: 28)
                }
            }
            
            if isFromCurrentUser {
                Spacer(minLength: 60)
            }
            
            VStack(alignment: isFromCurrentUser ? .trailing : .leading, spacing: 2) {
                // Sender name (only for received messages in group chats)
                if !isFromCurrentUser && totalParticipants > 2 && isFirstInSeries, let sender = message.sender {
                    Text(sender.name)
                        .font(.naarsCaption)
                        .fontWeight(.medium)
                        .foregroundColor(.secondary)
                        .padding(.leading, 12)
                        .padding(.bottom, 2)
                }
                
                // Replied-to message preview
                if showReplyPreview, let replyContext = message.replyToMessage {
                    Button {
                        onReplyPreviewTap?(replyContext.id)
                    } label: {
                        ReplyPreviewView(
                            senderName: replyContext.senderName,
                            text: replyContext.text,
                            hasImage: replyContext.imageUrl != nil,
                            isFromCurrentUser: isFromCurrentUser
                        )
                        .frame(maxWidth: replyPreviewMaxWidth, alignment: .leading)
                    }
                    .buttonStyle(PlainButtonStyle())
                    .padding(.bottom, 2)
                }
                
                // Message content
                VStack(alignment: isFromCurrentUser ? .trailing : .leading, spacing: Constants.Spacing.xs) {
                    // Audio message
                    if message.isAudioMessage, let audioUrl = message.audioUrl {
                        audioMessageView(audioUrl: audioUrl, duration: message.audioDuration ?? 0)
                    }
                    
                    // Location message
                    else if message.isLocationMessage, let lat = message.latitude, let lon = message.longitude {
                        locationMessageView(latitude: lat, longitude: lon, name: message.locationName)
                    }
                    
                    // Message image (if any)
                    else if let imageUrl = message.imageUrl, let url = URL(string: imageUrl) {
                        messageImageView(url: url)
                    }
                    
                    // Message text bubble (only show if not empty)
                    if !message.text.isEmpty && !message.isAudioMessage && !message.isLocationMessage {
                        messageBubbleView
                            .frame(maxWidth: bubbleMaxWidth, alignment: isFromCurrentUser ? .trailing : .leading)
                    }
                    
                    // Link preview (if URL detected and no image)
                    if message.imageUrl == nil && !message.isAudioMessage && !message.isLocationMessage, let firstUrl = detectedURLs.first {
                        if showLinkPreviews {
                            LinkPreviewView(url: firstUrl, isFromCurrentUser: isFromCurrentUser)
                        } else {
                            InlineLinkPreview(url: firstUrl, isFromCurrentUser: isFromCurrentUser)
                        }
                    }
                }
                
                // Reactions (if any)
                if let reactions = message.reactions, !reactions.reactions.isEmpty {
                    reactionsView(reactions: reactions)
                }
                
                // Failed state: show retry prompt
                if isFailed && isFromCurrentUser {
                    HStack(spacing: Constants.Spacing.xs) {
                        Image(systemName: "exclamationmark.circle.fill")
                            .font(.naarsFootnote)
                            .foregroundColor(.red)
                        Text("messaging_not_sent_tap_to_retry".localized)
                            .font(.naarsCaption).fontWeight(.medium)
                            .foregroundColor(.red)
                    }
                    .padding(.horizontal, 4)
                    .padding(.top, 2)
                    .accessibilityElement(children: .combine)
                    .accessibilityLabel("Message failed to send")
                    .accessibilityHint("Double-tap to retry sending this message")
                    .onTapGesture {
                        onRetry?()
                    }
                }
                // Timestamp and read receipt (only for last message in series)
                else if isLastInSeries || showTimestampOverride {
                    HStack(spacing: Constants.Spacing.xs) {
                        Text(message.createdAt.messageTimestampString)
                            .font(.naarsCaption)
                            .foregroundColor(.secondary)
                        
                        // Edited indicator
                        if message.isEdited {
                            Text("messaging_edited".localized)
                                .font(.naarsCaption)
                                .foregroundColor(.secondary)
                        }
                        
                        // Read receipt indicator (only for sent messages)
                        if isFromCurrentUser {
                            readReceiptIndicator
                        }
                        
                        if isFromCurrentUser && totalParticipants > 2 && readStatus == .read {
                            let readByOthersCount = message.readBy.filter { $0 != message.fromId }.count
                            Text(String(format: "messaging_read_by_count".localized, readByOthersCount))
                                .font(.naarsCaption)
                                .foregroundColor(.secondary)
                        }
                    }
                    .padding(.horizontal, 4)
                    .padding(.top, 2)
                }
            }
            .overlay(
                RoundedRectangle(cornerRadius: 14)
                    .fill(Color.naarsPrimary.opacity(isHighlighted ? 0.08 : 0))
            )
            .overlay(
                RoundedRectangle(cornerRadius: 14)
                    .stroke(Color.naarsPrimary.opacity(isHighlighted ? 0.6 : 0), lineWidth: 1.5)
            )
            .overlay(alignment: isFromCurrentUser ? .trailing : .leading) {
                if let replySpine = replySpine {
                    ReplyThreadSpineView(
                        showTop: replySpine.showTop,
                        showBottom: replySpine.showBottom
                    )
                    .frame(width: 10)
                    .offset(x: replySpineOffset)
                    .padding(.vertical, 6)
                }
            }
            .opacity(isFailed ? 0.7 : 1.0)
            .animation(.easeInOut(duration: 0.2), value: isHighlighted)
            
            if !isFromCurrentUser {
                Spacer(minLength: 60)
            }
            
            // Reply indicator (shown when swiping from right)
            if isFromCurrentUser && swipeOffset < -20 {
                Image(systemName: "arrowshape.turn.up.left.fill")
                    .font(.naarsCallout)
                    .foregroundColor(.naarsPrimary)
                    .opacity(min(1.0, abs(swipeOffset) / swipeThreshold))
                    .scaleEffect(min(1.0, abs(swipeOffset) / swipeThreshold))
            }
        }
        .offset(x: swipeOffset)
        .gesture(
            DragGesture(minimumDistance: 40, coordinateSpace: .local)
                .onChanged { value in
                    let horizontal = abs(value.translation.width)
                    let vertical = abs(value.translation.height)
                    
                    // Only activate if gesture is predominantly horizontal (> 2:1 ratio)
                    guard horizontal > vertical * 2 else { return }
                    
                    let translation = value.translation.width
                    
                    if !isFromCurrentUser && translation > 0 {
                        swipeOffset = min(translation * 0.6, swipeThreshold * 1.2)
                    } else if isFromCurrentUser && translation < 0 {
                        swipeOffset = max(translation * 0.6, -swipeThreshold * 1.2)
                    }
                    
                    if abs(swipeOffset) >= swipeThreshold && !isSwipingToReply {
                        isSwipingToReply = true
                        UIImpactFeedbackGenerator(style: .medium).impactOccurred()
                    } else if abs(swipeOffset) < swipeThreshold {
                        isSwipingToReply = false
                    }
                }
                .onEnded { _ in
                    if abs(swipeOffset) >= swipeThreshold {
                        onReply?()
                    }
                    withAnimation(.spring(response: 0.3, dampingFraction: 0.7)) {
                        swipeOffset = 0
                        isSwipingToReply = false
                    }
                }
        )
        .padding(.vertical, isLastInSeries ? 8 : 2)
        .contentShape(Rectangle())
        .onTapGesture {
            toggleTimestamp()
        }
        .contextMenu {
            // Reactions quick access
            Button {
                onLongPress?()
            } label: {
                Label("React", systemImage: "face.smiling")
            }
            
            // Reply
            if onReply != nil {
                Button {
                    onReply?()
                } label: {
                    Label("Reply", systemImage: "arrowshape.turn.up.left")
                }
            }
            
            // Copy text
            if !message.text.isEmpty {
                Button {
                    UIPasteboard.general.string = message.text
                    let generator = UINotificationFeedbackGenerator()
                    generator.notificationOccurred(.success)
                    onCopy?()
                } label: {
                    Label("Copy", systemImage: "doc.on.doc")
                }
            }
            
            // Edit (only for own text messages)
            if isFromCurrentUser, onEdit != nil, !message.text.isEmpty, !message.isAudioMessage, !message.isLocationMessage {
                Button {
                    onEdit?()
                } label: {
                    Label("Edit", systemImage: "pencil")
                }
            }
            
            Divider()
            
            // Unsend (only for own messages within 15 minutes)
            if isFromCurrentUser, onUnsend != nil, message.canUnsend {
                Button(role: .destructive) {
                    onUnsend?()
                } label: {
                    Label("Unsend", systemImage: "arrow.uturn.backward")
                }
            }
            
            // Delete (only for own messages)
            if isFromCurrentUser && onDelete != nil {
                Button(role: .destructive) {
                    onDelete?()
                } label: {
                    Label("Delete", systemImage: "trash")
                }
            }
            
            // Report (only for other users' messages)
            if !isFromCurrentUser {
                Divider()
                
                Button(role: .destructive) {
                    onReport?()
                } label: {
                    Label("Report", systemImage: "exclamationmark.triangle")
                }
            }
        }
        // Long press is handled by .contextMenu above — no separate gesture needed
    }
    
    private func toggleTimestamp() {
        showTimestampOverride.toggle()
        if showTimestampOverride {
            DispatchQueue.main.asyncAfter(deadline: .now() + 2.0) {
                if showTimestampOverride {
                    showTimestampOverride = false
                }
            }
        }
    }
    
    // MARK: - Message Bubble
    
    private var messageBubbleView: some View {
        Text(message.text)
            .font(.naarsBody)
            .foregroundColor(isFromCurrentUser ? .white : .primary)
            .multilineTextAlignment(.leading)
            .padding(.horizontal, 14)
            .padding(.vertical, 10)
            .background(bubbleBackground)
    }
    
    private var bubbleBackground: some View {
        // iMessage-style bubble with tail effect
        BubbleShape(
            isFromCurrentUser: isFromCurrentUser,
            showTail: isLastInSeries
        )
        .fill(isFromCurrentUser ? Color.naarsPrimary : Color(.systemGray5))
    }
    
    // MARK: - Message Image
    
    private func messageImageView(url: URL) -> some View {
        Button(action: {
            onImageTap?(url)
        }) {
            AsyncImage(url: url, transaction: Transaction(animation: nil)) { phase in
                switch phase {
                case .empty:
                    RoundedRectangle(cornerRadius: 12)
                        .fill(Color(.systemGray5))
                        .frame(width: 200, height: 150)
                        .overlay(ProgressView())
                case .success(let image):
                    image
                        .resizable()
                        .scaledToFit()
                        .frame(maxWidth: 220, maxHeight: 220)
                        .clipShape(RoundedRectangle(cornerRadius: 12))
                case .failure:
                    RoundedRectangle(cornerRadius: 12)
                        .fill(Color(.systemGray5))
                        .frame(width: 200, height: 150)
                        .overlay(
                            VStack(spacing: Constants.Spacing.xs) {
                                Image(systemName: "arrow.clockwise")
                                    .foregroundColor(.secondary)
                                Text("Tap to retry")
                                    .font(.caption2)
                                    .foregroundColor(.secondary)
                            }
                        )
                @unknown default:
                    EmptyView()
                }
            }
        }
        .buttonStyle(PlainButtonStyle())
    }
    
    // MARK: - Audio Message View
    
    private func audioMessageView(audioUrl: String, duration: Double) -> some View {
        let isCurrent = audioPlayer.currentUrl?.absoluteString == audioUrl
        let isPlaying = isCurrent && audioPlayer.isPlaying
        let progress = isCurrent ? audioPlayer.progress : 0
        let totalDuration = duration > 0 ? duration : (isCurrent ? audioPlayer.duration : 0)
        
        return HStack(spacing: 12) {
            // Play/Pause button
            Button(action: {
                audioPlayer.togglePlayback(urlString: audioUrl)
            }) {
                Image(systemName: isPlaying ? "pause.fill" : "play.fill")
                    .font(.system(size: 18))
                    .foregroundColor(isFromCurrentUser ? .white : .naarsPrimary)
                    .frame(width: 40, height: 40)
                    .background(
                        Circle()
                            .fill(isFromCurrentUser ? Color.white.opacity(0.2) : Color.naarsPrimary.opacity(0.1))
                    )
            }
            
            // Waveform visualization placeholder
            HStack(spacing: 2) {
                ForEach(waveformHeights.indices, id: \.self) { i in
                    RoundedRectangle(cornerRadius: 1)
                        .fill(isFromCurrentUser ? Color.white.opacity(i < Int(progress * Double(waveformHeights.count)) ? 1.0 : 0.4) : Color.naarsPrimary.opacity(i < Int(progress * Double(waveformHeights.count)) ? 1.0 : 0.3))
                        .frame(width: 3, height: waveformHeights[i])
                }
            }
            .frame(height: 30)
            
            // Duration
            Text(durationLabel(totalDuration: totalDuration, progress: progress))
                .font(.naarsFootnote).fontWeight(.medium)
                .foregroundColor(isFromCurrentUser ? .white.opacity(0.8) : .secondary)
        }
        .padding(.horizontal, 12)
        .padding(.vertical, 10)
        .background(
            RoundedRectangle(cornerRadius: 18)
                .fill(isFromCurrentUser ? Color.naarsPrimary : Color(.systemGray5))
        )
    }
    
    private func durationLabel(totalDuration: Double, progress: Double) -> String {
        if totalDuration > 0 && progress > 0 {
            let elapsed = totalDuration * progress
            return "\(formatDuration(elapsed)) / \(formatDuration(totalDuration))"
        }
        return formatDuration(totalDuration)
    }
    
    private func formatDuration(_ seconds: Double) -> String {
        let minutes = Int(seconds) / 60
        let secs = Int(seconds) % 60
        return String(format: "%d:%02d", minutes, secs)
    }
    
    // MARK: - Location Message View
    
    private func locationMessageView(latitude: Double, longitude: Double, name: String?) -> some View {
        Button(action: {
            // Open in Maps
            let url = URL(string: "maps://?ll=\(latitude),\(longitude)")!
            if UIApplication.shared.canOpenURL(url) {
                Task { @MainActor in
                    await UIApplication.shared.open(url)
                }
            }
        }) {
            VStack(alignment: .leading, spacing: 0) {
                LocationSnapshotView(
                    coordinate: CLLocationCoordinate2D(latitude: latitude, longitude: longitude)
                )
                .frame(width: 200, height: 120)
                .clipShape(RoundedRectangle(cornerRadius: 12))
                
                // Location name
                HStack(spacing: 6) {
                    Image(systemName: "location.fill")
                        .font(.naarsFootnote)
                        .foregroundColor(.naarsPrimary)
                    
                    Text(name ?? "Shared Location")
                        .font(.naarsFootnote).fontWeight(.medium)
                        .foregroundColor(.primary)
                        .lineLimit(2)
                }
                .padding(.horizontal, 10)
                .padding(.vertical, 8)
                .frame(width: 200, alignment: .leading)
                .background(Color.naarsBackgroundSecondary)
            }
            .clipShape(RoundedRectangle(cornerRadius: 12))
            .overlay(
                RoundedRectangle(cornerRadius: 12)
                    .stroke(Color(.systemGray4), lineWidth: 1)
            )
        }
        .buttonStyle(PlainButtonStyle())
    }
    
    // MARK: - Reactions View
    
    private func reactionsView(reactions: MessageReactions) -> some View {
        HStack(spacing: Constants.Spacing.xs) {
            ForEach(reactions.sortedReactions.prefix(5), id: \.reaction) { reactionData in
                Button(action: {
                    let generator = UIImpactFeedbackGenerator(style: .light)
                    generator.impactOccurred()
                    onReactionTap?(reactionData.reaction)
                }) {
                    HStack(spacing: 2) {
                        Text(reactionData.reaction)
                            .font(.naarsSubheadline)
                        if reactionData.count > 1 {
                            Text("\(reactionData.count)")
                                .font(.naarsCaption).fontWeight(.medium)
                                .foregroundColor(.secondary)
                        }
                    }
                    .padding(.horizontal, 8)
                    .padding(.vertical, 4)
                    .background(
                        Capsule()
                            .fill(Color(.systemGray5))
                            .shadow(color: .black.opacity(0.1), radius: 2, x: 0, y: 1)
                    )
                }
                .buttonStyle(PlainButtonStyle())
                .accessibilityLabel("\(reactionData.reaction) reaction, \(reactionData.count)")
                .accessibilityHint("Double-tap to toggle this reaction")
            }
        }
        .padding(.top, 4)
    }
}

// MARK: - Location Snapshot View

struct LocationSnapshotView: View {
    let coordinate: CLLocationCoordinate2D
    
    @State private var snapshotImage: UIImage?
    
    var body: some View {
        ZStack {
            if let image = snapshotImage {
                Image(uiImage: image)
                    .resizable()
                    .scaledToFill()
            } else {
                RoundedRectangle(cornerRadius: 12)
                    .fill(Color(.systemGray5))
                    .overlay(ProgressView())
            }
            
            Image(systemName: "mappin.circle.fill")
                .font(.naarsTitle)
                .foregroundColor(.red)
                .shadow(color: .black.opacity(0.25), radius: 2, x: 0, y: 2)
        }
        .clipped()
        .task {
            if snapshotImage == nil {
                snapshotImage = await MapSnapshotCache.shared.snapshot(for: coordinate)
            }
        }
    }
}

// MARK: - Reply Preview View

/// Shows a preview of the message being replied to
struct ReplyPreviewView: View {
    let senderName: String
    let text: String
    let hasImage: Bool
    let isFromCurrentUser: Bool
    
    var body: some View {
        HStack(spacing: Constants.Spacing.sm) {
            // Vertical accent bar
            RoundedRectangle(cornerRadius: 2)
                .fill(isFromCurrentUser ? Color.white.opacity(0.6) : Color.naarsPrimary)
                .frame(width: 3)
            
            VStack(alignment: .leading, spacing: 2) {
                // Sender name
                Text(senderName)
                    .font(.naarsFootnote).fontWeight(.semibold)
                    .foregroundColor(isFromCurrentUser ? .white.opacity(0.9) : .naarsPrimary)
                    .lineLimit(1)
                
                // Preview content
                HStack(spacing: Constants.Spacing.xs) {
                    if hasImage {
                        Image(systemName: "photo")
                            .font(.naarsCaption)
                            .foregroundColor(isFromCurrentUser ? .white.opacity(0.7) : .primary.opacity(0.6))
                    }
                    
                    Text(text.isEmpty ? "Photo" : text)
                        .font(.naarsFootnote)
                        .foregroundColor(isFromCurrentUser ? .white.opacity(0.7) : .primary.opacity(0.6))
                        .lineLimit(3)
                }
            }
            
            Spacer(minLength: 0)
        }
        .padding(.horizontal, 10)
        .padding(.vertical, 6)
        .frame(maxWidth: 260)
        .background(
            RoundedRectangle(cornerRadius: 10)
                .fill(isFromCurrentUser ? Color.white.opacity(0.15) : Color(.systemGray5))
        )
    }
}

// MARK: - Bubble Shape

/// Custom bubble shape with optional tail (iMessage-style)
struct BubbleShape: Shape {
    let isFromCurrentUser: Bool
    let showTail: Bool
    
    func path(in rect: CGRect) -> Path {
        let cornerRadius: CGFloat = 18
        let tailWidth: CGFloat = 6
        let tailHeight: CGFloat = 8
        
        var path = Path()
        
        if showTail {
            if isFromCurrentUser {
                // Right-aligned bubble with tail on bottom-right
                path.addRoundedRect(
                    in: CGRect(x: 0, y: 0, width: rect.width - tailWidth, height: rect.height),
                    cornerSize: CGSize(width: cornerRadius, height: cornerRadius)
                )
                
                // Tail
                path.move(to: CGPoint(x: rect.width - tailWidth, y: rect.height - tailHeight - 4))
                path.addQuadCurve(
                    to: CGPoint(x: rect.width, y: rect.height),
                    control: CGPoint(x: rect.width - tailWidth + 2, y: rect.height - 2)
                )
                path.addQuadCurve(
                    to: CGPoint(x: rect.width - tailWidth - 4, y: rect.height),
                    control: CGPoint(x: rect.width - tailWidth - 2, y: rect.height)
                )
                path.closeSubpath()
            } else {
                // Left-aligned bubble with tail on bottom-left
                path.addRoundedRect(
                    in: CGRect(x: tailWidth, y: 0, width: rect.width - tailWidth, height: rect.height),
                    cornerSize: CGSize(width: cornerRadius, height: cornerRadius)
                )
                
                // Tail
                path.move(to: CGPoint(x: tailWidth, y: rect.height - tailHeight - 4))
                path.addQuadCurve(
                    to: CGPoint(x: 0, y: rect.height),
                    control: CGPoint(x: tailWidth - 2, y: rect.height - 2)
                )
                path.addQuadCurve(
                    to: CGPoint(x: tailWidth + 4, y: rect.height),
                    control: CGPoint(x: tailWidth + 2, y: rect.height)
                )
                path.closeSubpath()
            }
        } else {
            // No tail - just rounded rectangle
            path.addRoundedRect(
                in: rect,
                cornerSize: CGSize(width: cornerRadius, height: cornerRadius)
            )
        }
        
        return path
    }
}

// MARK: - URL Detection Cache

/// Thread-safe cache for NSDataDetector results to avoid expensive regex on every SwiftUI body evaluation
private final class URLDetectionCache: @unchecked Sendable {
    private var cache: [String: [URL]] = [:]
    private let lock = NSLock()
    private static let detector: NSDataDetector? = {
        try? NSDataDetector(types: NSTextCheckingResult.CheckingType.link.rawValue)
    }()
    
    func urls(for text: String) -> [URL] {
        lock.lock()
        if let cached = cache[text] {
            lock.unlock()
            return cached
        }
        lock.unlock()
        
        let matches = Self.detector?.matches(in: text, options: [], range: NSRange(text.startIndex..., in: text)) ?? []
        let urls = matches.compactMap { match -> URL? in
            guard let range = Range(match.range, in: text) else { return nil }
            return URL(string: String(text[range]))
        }
        
        lock.lock()
        cache[text] = urls
        lock.unlock()
        
        return urls
    }
}

// MARK: - Preview

#Preview("Regular Messages") {
    VStack(spacing: Constants.Spacing.md) {
        // Received message with avatar
        MessageBubble(
            message: Message(
                conversationId: UUID(),
                fromId: UUID(),
                text: "Hello! I can help with your ride request. Let me know when you need to be picked up.",
                sender: Profile(id: UUID(), name: "John Doe", email: "john@example.com")
            ),
            isFromCurrentUser: false,
            showAvatar: true,
            isFirstInSeries: true,
            isLastInSeries: true
        )
        
        // Sent message
        MessageBubble(
            message: Message(
                conversationId: UUID(),
                fromId: UUID(),
                text: "Thanks! That would be great. 🙏"
            ),
            isFromCurrentUser: true,
            isFirstInSeries: true,
            isLastInSeries: true
        )
        
        // System message
        MessageBubble(
            message: Message(
                conversationId: UUID(),
                fromId: UUID(),
                text: "John Doe has been added to the conversation"
            ),
            isFromCurrentUser: false
        )
    }
    .padding()
}

#Preview("Consecutive Messages") {
    VStack(spacing: 0) {
        // First in series
        MessageBubble(
            message: Message(
                conversationId: UUID(),
                fromId: UUID(),
                text: "Hey!",
                sender: Profile(id: UUID(), name: "Jane", email: "jane@example.com")
            ),
            isFromCurrentUser: false,
            showAvatar: true,
            isFirstInSeries: true,
            isLastInSeries: false
        )
        
        // Middle
        MessageBubble(
            message: Message(
                conversationId: UUID(),
                fromId: UUID(),
                text: "How are you?",
                sender: Profile(id: UUID(), name: "Jane", email: "jane@example.com")
            ),
            isFromCurrentUser: false,
            showAvatar: true,
            isFirstInSeries: false,
            isLastInSeries: false
        )
        
        // Last in series
        MessageBubble(
            message: Message(
                conversationId: UUID(),
                fromId: UUID(),
                text: "Let me know if you need anything",
                sender: Profile(id: UUID(), name: "Jane", email: "jane@example.com")
            ),
            isFromCurrentUser: false,
            showAvatar: true,
            isFirstInSeries: false,
            isLastInSeries: true
        )
    }
    .padding()
}
