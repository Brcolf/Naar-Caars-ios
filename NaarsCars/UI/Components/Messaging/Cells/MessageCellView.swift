//
//  MessageCellView.swift
//  NaarsCars
//
//  Top-level UIView for rendering a message cell. Composes content subviews,
//  handles layout and gesture recognition.
//

import UIKit

final class MessageCellView: UIView {

    // MARK: - Subviews (lazily created)

    private var textBubble: TextBubbleView?
    private var emojiBubble: EmojiBubbleView?
    private var imageBubble: ImageBubbleView?
    private var audioBubble: AudioBubbleView?
    private var locationBubble: LocationBubbleView?
    private var linkPreviewBubble: LinkPreviewBubbleView?
    private var systemMessage: SystemMessageView?
    private var unsentMessage: UnsentMessageView?
    private var moderationHiddenMessage: ModerationHiddenMessageView?

    private var avatarView: AvatarUIView?
    private var senderNameLabel: UILabel?
    private var replyPreview: ReplyPreviewUIView?
    private var reactionStickerBadge: ReactionStickerBadgeView?
    private var readReceipt: ReadReceiptView?
    private var timestampLabel: UILabel?
    private var editedLabel: UILabel?
    private var failedRetryLabel: UILabel?
    private var replyCountLabel: UILabel?
    private let replyArrowIcon = UIImageView(image: UIImage(systemName: "arrowshape.turn.up.left.fill"))

    // Reply spine
    private let spineLayer = CAShapeLayer()

    // MARK: - State

    private var config: MessageCellConfig?

    // MARK: - Layout Size Cache
    // sizeThatFits() owns measurement and populates this cache.
    // layoutSubviews() reads cached values to avoid duplicate measurement.
    private var cachedContentSizes: [ObjectIdentifier: CGSize] = [:]
    private var cachedFitWidth: CGFloat = 0
    /// Set to true by configure(). Cleared after the first successful layoutSubviews pass.
    /// When true, layoutSubviews performs a full layout; when false, it skips if bounds unchanged.
    private var layoutInvalidated: Bool = true
    private var lastLayoutBounds: CGRect = .zero
    weak var delegate: MessageCellDelegate?

    /// Called when the cell's intrinsic size changes (e.g. timestamp toggle).
    /// The hosting cell should invalidate its collection view layout.
    var onIntrinsicSizeChanged: (() -> Void)?

    // Gesture state
    private var swipeOffset: CGFloat = 0
    private var isSwipingToReply = false
    private let swipeThreshold: CGFloat = 60
    private var timestampHideWorkItem: DispatchWorkItem?
    private var hasAnimatedEntrance = false

    // Gesture recognizers
    private var panGesture: UIPanGestureRecognizer!
    private var longPressGesture: UILongPressGestureRecognizer!
    private var tapGesture: UITapGestureRecognizer!

    override init(frame: CGRect) {
        super.init(frame: frame)
        setupGestures()
        replyArrowIcon.tintColor = .naarsPrimary
        replyArrowIcon.alpha = 0
        addSubview(replyArrowIcon)
        layer.addSublayer(spineLayer)
        spineLayer.strokeColor = UIColor.secondaryLabel.withAlphaComponent(0.35).cgColor
        spineLayer.lineWidth = 2
        spineLayer.fillColor = nil
        spineLayer.lineCap = .round
    }

    required init?(coder: NSCoder) { fatalError() }

    // MARK: - Configuration

    func configure(with config: MessageCellConfig) {
        self.config = config
        cachedContentSizes.removeAll(keepingCapacity: true)
        layoutInvalidated = true
        let msg = config.message

        // Hide all content views first
        hideAllContent()

        if msg.isModerationHidden {
            showModerationHidden(config: config)
        } else if msg.isUnsent {
            showUnsent(config: config)
        } else if isSystemMessage(msg) {
            showSystem(msg: msg)
        } else {
            showRegular(config: config)
        }

        // Entrance animation
        if config.shouldAnimate && !hasAnimatedEntrance {
            alpha = 0
            transform = CGAffineTransform(translationX: config.isFromCurrentUser ? 50 : -50, y: 0)
                .scaledBy(x: 0.8, y: 0.8)
            UIView.animate(withDuration: 0.35, delay: 0, usingSpringWithDamping: 0.7, initialSpringVelocity: 0) {
                self.alpha = 1
                self.transform = .identity
            }
            hasAnimatedEntrance = true
        } else if !hasAnimatedEntrance {
            alpha = 1
            transform = .identity
            hasAnimatedEntrance = true
        }

        // Highlight flash (scroll-to-reply)
        if config.isHighlighted {
            // Search / reply-jump target: strong enough to be seen, held long enough to be read.
            backgroundColor = UIColor.naarsPrimary.withAlphaComponent(0.28)
            UIView.animate(withDuration: 2.0, delay: 1.2, options: .curveEaseOut) {
                self.backgroundColor = .clear
            }
        } else {
            backgroundColor = .clear
        }

        updateAccessibility(config: config)

        setNeedsLayout()
    }

    // MARK: - Accessibility

    /// The cell is a container: its children stay separate elements because image, audio,
    /// link preview and retry each have their own action and identifier. The first content
    /// bubble also says who wrote the message, when, and whether it was edited or has replies
    /// (alignment and colour were the only cues), and carries the actions that are otherwise
    /// gesture-only. The time is part of that label, so the tap-revealed time label is not
    /// listed as an element.
    private func updateAccessibility(config: MessageCellConfig) {
        isAccessibilityElement = false
        let contentViews = visibleContentViews()
        let message = config.message
        let isRegular = !MessageOverlayAvailability.isPlaceholder(message)

        for (index, view) in contentViews.enumerated() {
            let isPrimary = isRegular && index == 0
            if let bubble = view as? MessageBubbleContentView {
                bubble.accessibilityContextPrefix = isPrimary ? accessibilitySenderText(config: config) : nil
                bubble.accessibilityContextSuffix = isPrimary ? accessibilityDetailText(config: config) : nil
            }
            view.accessibilityCustomActions = isPrimary ? accessibilityActions(config: config) : nil
        }

        // Another member's system line offers Report through the long press; give VoiceOver
        // the same route. (Own lines and every other placeholder offer nothing.)
        if message.messageType == .system,
           MessageOverlayAvailability.canPresentOverlay(for: message, isFromCurrentUser: config.isFromCurrentUser) {
            systemMessage?.accessibilityCustomActions = [
                UIAccessibilityCustomAction(name: "messaging_report_message".localized) { [weak self] _ in
                    guard let self, let config = self.config else { return false }
                    self.delegate?.messageCellDidLongPress(self, message: config.message)
                    return true
                }
            ]
        } else {
            systemMessage?.accessibilityCustomActions = nil
        }

        accessibilityElements = contentViews
            + [moderationHiddenMessage, systemMessage, unsentMessage, reactionStickerBadge, readReceipt, failedRetryLabel, replyPreview]
                .compactMap { $0 }
                .filter { !$0.isHidden }
    }

    /// "You" for own messages, otherwise the sender's name.
    private func accessibilitySenderText(config: MessageCellConfig) -> String {
        if config.isFromCurrentUser { return "messaging_you".localized }
        let senderProfile = config.message.sender ?? config.participantProfiles.first { $0.id == config.message.fromId }
        return senderProfile?.name ?? "messaging_deleted_user".localized
    }

    /// Time, "Edited" and the reply count, spoken after the bubble's own content.
    private func accessibilityDetailText(config: MessageCellConfig) -> String {
        var parts = [config.message.createdAt.messageTimestampString]
        if config.message.isEdited { parts.append("messaging_edited".localized) }
        if config.replyCount > 0 { parts.append(Self.replyCountText(config.replyCount)) }
        return parts.joined(separator: ", ")
    }

    /// VoiceOver equivalents of the swipe, long-press and tap gestures. They call the same
    /// delegate methods the gestures do; reactions, copy, edit, unsend, delete and report are
    /// reached through the overlay the second action opens.
    private func accessibilityActions(config: MessageCellConfig) -> [UIAccessibilityCustomAction] {
        var actions: [UIAccessibilityCustomAction] = []
        if allowsReply(config) {
            actions.append(UIAccessibilityCustomAction(name: "Reply".localized) { [weak self] _ in
                guard let self, let config = self.config else { return false }
                self.delegate?.messageCellDidSwipeToReply(self, message: config.message)
                return true
            })
        }
        if MessageOverlayAvailability.canPresentOverlay(for: config.message, isFromCurrentUser: config.isFromCurrentUser) {
            actions.append(UIAccessibilityCustomAction(name: "messaging_accessibility_react_and_more".localized) { [weak self] _ in
                guard let self, let config = self.config else { return false }
                self.delegate?.messageCellDidLongPress(self, message: config.message)
                return true
            })
        }
        if !config.isInThread, config.message.replyToId != nil || config.replyCount > 0 {
            actions.append(UIAccessibilityCustomAction(name: "messaging_view_thread".localized) { [weak self] _ in
                guard let self, let config = self.config else { return false }
                self.delegate?.messageCellDidTapViewThread(self, message: config.message)
                return true
            })
        }
        return actions
    }

    /// Reply is offered for a real message that has reached the server, and not inside the
    /// reply thread (no nested replies). A system line, a placeholder or a message that is
    /// still sending or failed has nothing to reply to.
    private func allowsReply(_ config: MessageCellConfig) -> Bool {
        !config.isInThread && MessageOverlayAvailability.allowsServerActions(for: config.message)
    }

    // MARK: - Content Display

    private func showUnsent(config: MessageCellConfig) {
        let view = unsentMessage ?? {
            let v = UnsentMessageView()
            addSubview(v)
            unsentMessage = v
            return v
        }()
        view.isHidden = false
        view.configure(isFromCurrentUser: config.isFromCurrentUser)
    }

    private func showModerationHidden(config: MessageCellConfig) {
        let view = moderationHiddenMessage ?? {
            let v = ModerationHiddenMessageView()
            addSubview(v)
            moderationHiddenMessage = v
            return v
        }()
        view.isHidden = false
        view.configure(reason: config.message.hiddenReason)
    }

    private func showSystem(msg: Message) {
        let view = systemMessage ?? {
            let v = SystemMessageView()
            addSubview(v)
            systemMessage = v
            return v
        }()
        view.isHidden = false
        view.configure(text: msg.text, action: msg.resolvedSystemAction)
    }

    private func showRegular(config: MessageCellConfig) {
        let msg = config.message

        // Resolve sender profile: prefer the joined sender, fall back to
        // participantProfiles so group members show real names even when
        // the Supabase join returns nil (RLS, deleted row, etc.).
        let senderProfile = msg.sender ?? config.participantProfiles.first { $0.id == msg.fromId }

        // Avatar
        if config.showAvatar {
            let av = avatarView ?? {
                let v = AvatarUIView()
                addSubview(v)
                avatarView = v
                return v
            }()
            av.isHidden = false
            if config.isLastInSeries {
                av.configure(
                    imageUrl: senderProfile?.avatarUrl,
                    name: senderProfile?.name ?? "messaging_deleted_user".localized,
                    size: 28
                )
            } else {
                av.isHidden = true // Spacer for alignment
            }
        }

        // Sender name (group, first in series, received)
        if !config.isFromCurrentUser && config.isGroupConversation && config.isFirstInSeries {
            let lbl = senderNameLabel ?? {
                let l = UILabel()
                l.font = .preferredFont(forTextStyle: .caption1)
                l.textColor = .secondaryLabel
                addSubview(l)
                senderNameLabel = l
                return l
            }()
            lbl.isHidden = false
            lbl.text = senderProfile?.name ?? "messaging_deleted_user".localized
        }

        // Reply preview
        if config.showReplyPreview, let replyContext = msg.replyToMessage {
            let rp = replyPreview ?? {
                let v = ReplyPreviewUIView()
                addSubview(v)
                replyPreview = v
                return v
            }()
            rp.isHidden = false
            rp.configure(reply: replyContext, isFromCurrentUser: config.isFromCurrentUser) { [weak self] id in
                guard let self, let config = self.config else { return }
                self.delegate?.messageCellDidTapReplyPreview(self, replyToId: id)
            }
        }

        // Content
        if msg.isAudioMessage {
            // A voice note is an audio bubble from the moment it is recorded. While it uploads,
            // and if the send fails, there is no server URL yet: play the local recording. (The
            // row used to fall through to the image branch, which drew the .m4a as a failed
            // image.) With neither URL the bubble is shown with playback disabled.
            let audioUrl = msg.audioUrl
                ?? msg.localAttachmentPath.map { LocalAttachmentStorage.fileURL(for: $0).absoluteString }
                ?? ""
            let view = audioBubble ?? {
                let v = AudioBubbleView()
                addSubview(v)
                audioBubble = v
                return v
            }()
            view.isHidden = false
            view.configure(audioUrl: audioUrl, duration: msg.audioDuration ?? 0, isFromCurrentUser: config.isFromCurrentUser)
        } else if msg.isLocationMessage, let lat = msg.latitude, let lon = msg.longitude {
            let view = locationBubble ?? {
                let v = LocationBubbleView()
                addSubview(v)
                locationBubble = v
                return v
            }()
            view.isHidden = false
            view.configure(latitude: lat, longitude: lon, name: msg.locationName)
        } else if msg.imageUrl != nil || msg.localAttachmentPath != nil {
            let view = imageBubble ?? {
                let v = ImageBubbleView()
                addSubview(v)
                imageBubble = v
                return v
            }()
            view.isHidden = false
            if let localPath = msg.localAttachmentPath {
                view.configure(localPath: localPath, imageWidth: msg.imageWidth, imageHeight: msg.imageHeight) { [weak self] url in
                    guard let self else { return }
                    self.delegate?.messageCellDidTapImage(self, url: url)
                }
            } else if let remoteUrl = msg.imageUrl {
                view.configure(remoteUrl: remoteUrl, imageWidth: msg.imageWidth, imageHeight: msg.imageHeight) { [weak self] url in
                    guard let self else { return }
                    self.delegate?.messageCellDidTapImage(self, url: url)
                }
            }
        }

        // Text bubble (show if text is non-empty and not audio/location)
        if !msg.text.isEmpty && !msg.isAudioMessage && !msg.isLocationMessage {
            let emojiResult = isEmojiOnlyMessage(msg.text)
            if emojiResult.isEmojiOnly {
                let view = emojiBubble ?? {
                    let v = EmojiBubbleView()
                    addSubview(v)
                    emojiBubble = v
                    return v
                }()
                view.isHidden = false
                view.configure(text: msg.text, emojiCount: emojiResult.count)
            } else {
                let view = textBubble ?? {
                    let v = TextBubbleView()
                    addSubview(v)
                    textBubble = v
                    return v
                }()
                view.isHidden = false
                view.configure(text: msg.text, isFromCurrentUser: config.isFromCurrentUser, showTail: config.isLastInSeries)
            }
        }

        // Link preview
        if msg.imageUrl == nil && !msg.isAudioMessage && !msg.isLocationMessage {
            let urls = URLDetectionCache.shared.urls(for: msg.text)
            if let firstUrl = urls.first {
                let view = linkPreviewBubble ?? {
                    let v = LinkPreviewBubbleView()
                    addSubview(v)
                    linkPreviewBubble = v
                    return v
                }()
                view.isHidden = false
                view.configure(url: firstUrl, isFromCurrentUser: config.isFromCurrentUser)
            }
        }

        // Reactions
        if let individualReactions = msg.individualReactions, !individualReactions.isEmpty {
            let badge = reactionStickerBadge ?? {
                let v = ReactionStickerBadgeView()
                addSubview(v)
                reactionStickerBadge = v
                return v
            }()
            badge.isHidden = false
            let currentUserId = AuthService.shared.currentUserId ?? UUID()
            badge.configure(reactions: individualReactions, currentUserId: currentUserId)
            badge.onTap = { [weak self] in
                guard let self, let config = self.config else { return }
                self.delegate?.messageCellDidTapReactionBadge(self, message: config.message)
            }
        } else {
            reactionStickerBadge?.isHidden = true
        }

        // Footer row (iMessage): "Edited" whenever edited, the delivery status under the
        // newest outgoing message only, and the time only while revealed by a tap. There is
        // no per-series timestamp any more; time headers come from the date separators.
        if config.message.isEdited || (config.isFromCurrentUser && config.isLastOutgoingMessage && !config.isFailed) {
            showFooter(config: config, revealTime: false)
        }

        // Failed retry
        if config.isFailed && config.isFromCurrentUser {
            showFailedRetry()
        }

        // Reply spine
        if let spine = config.replySpine {
            spineLayer.isHidden = false
            // Path will be drawn in layoutSubviews
        } else {
            spineLayer.isHidden = true
        }

        // Reply count label
        if config.replyCount > 0 {
            let label = replyCountLabel ?? {
                let l = UILabel()
                l.font = .preferredFont(forTextStyle: .caption1)
                l.textColor = .naarsPrimary
                let tap = UITapGestureRecognizer(target: self, action: #selector(handleReplyCountTap))
                l.addGestureRecognizer(tap)
                l.isUserInteractionEnabled = true
                addSubview(l)
                replyCountLabel = l
                return l
            }()
            label.isHidden = false
            label.text = Self.replyCountText(config.replyCount)
        } else {
            replyCountLabel?.isHidden = true
        }
    }

    private static func replyCountText(_ count: Int) -> String {
        count == 1
            ? "messaging_1_reply".localized
            : "messaging_n_replies".localized(with: count)
    }

    /// Height of a one-line caption row (sender name, "Not sent. Tap to retry", reply count).
    /// Derived from the label's own font so the row grows with Dynamic Type (18 pt at the
    /// default size, as before). Used by both sizeThatFits and layoutSubviews so the measured
    /// cell height and the laid-out content cannot diverge.
    private func captionRowHeight(for label: UILabel?) -> CGFloat {
        let font = label?.font ?? UIFont.preferredFont(forTextStyle: .caption1)
        return ceil(font.lineHeight) + 3
    }

    /// Whether the footer row (time / edited / delivery status) occupies a line.
    private var isFooterRowVisible: Bool {
        timestampLabel?.isHidden == false || editedLabel?.isHidden == false || readReceipt?.isHidden == false
    }

    /// Footer row height; follows Dynamic Type so the caption is never clipped.
    private var footerRowHeight: CGFloat {
        ceil(UIFont.preferredFont(forTextStyle: .caption1).lineHeight) + 2
    }

    private func showFooter(config: MessageCellConfig, revealTime: Bool) {
        if revealTime {
            let lbl = timestampLabel ?? {
                let l = UILabel()
                l.font = .preferredFont(forTextStyle: .caption1)
                l.textColor = .secondaryLabel
                addSubview(l)
                timestampLabel = l
                return l
            }()
            lbl.isHidden = false
            lbl.text = config.message.createdAt.messageTimestampString
        }

        if config.message.isEdited {
            let el = editedLabel ?? {
                let l = UILabel()
                l.font = .preferredFont(forTextStyle: .caption1)
                l.textColor = .secondaryLabel
                l.text = "messaging_edited".localized
                addSubview(l)
                editedLabel = l
                return l
            }()
            el.isHidden = false
        }

        if config.isFromCurrentUser && config.isLastOutgoingMessage && !config.isFailed {
            let rr = readReceipt ?? {
                let v = ReadReceiptView()
                addSubview(v)
                readReceipt = v
                return v
            }()
            rr.isHidden = false
            if config.isGroupConversation {
                let readByProfiles = config.participantProfiles.filter { profile in
                    config.message.readBy.contains(profile.id) && profile.id != config.message.fromId
                }
                rr.configureGroup(
                    message: config.message,
                    isFailed: config.isFailed,
                    totalParticipants: config.totalParticipants,
                    readByProfiles: readByProfiles
                )
            } else {
                rr.configure(
                    message: config.message,
                    isFailed: config.isFailed,
                    totalParticipants: config.totalParticipants
                )
            }
        }
    }

    private func showFailedRetry() {
        let lbl = failedRetryLabel ?? {
            let l = UILabel()
            l.font = .preferredFont(forTextStyle: .caption1)
            l.textColor = .systemRed
            l.text = "\u{26A0} " + "messaging_not_sent_tap_to_retry".localized
            l.isUserInteractionEnabled = true
            l.addGestureRecognizer(UITapGestureRecognizer(target: self, action: #selector(retryTapped)))
            l.isAccessibilityElement = true
            l.accessibilityLabel = "messaging_not_sent_tap_to_retry".localized
            l.accessibilityTraits = .button
            l.accessibilityIdentifier = "message.retryButton"
            addSubview(l)
            failedRetryLabel = l
            return l
        }()
        lbl.isHidden = false
    }

    @objc private func retryTapped() {
        guard let config else { return }
        delegate?.messageCellDidTapRetry(self, message: config.message)
    }

    @objc private func handleReplyCountTap() {
        guard let config else { return }
        delegate?.messageCellDidTapViewThread(self, message: config.message)
    }

    private func hideAllContent() {
        textBubble?.isHidden = true
        emojiBubble?.isHidden = true
        imageBubble?.isHidden = true
        audioBubble?.isHidden = true
        locationBubble?.isHidden = true
        linkPreviewBubble?.isHidden = true
        systemMessage?.isHidden = true
        unsentMessage?.isHidden = true
        moderationHiddenMessage?.isHidden = true
        avatarView?.isHidden = true
        senderNameLabel?.isHidden = true
        replyPreview?.isHidden = true
        reactionStickerBadge?.isHidden = true
        readReceipt?.isHidden = true
        timestampLabel?.isHidden = true
        editedLabel?.isHidden = true
        failedRetryLabel?.isHidden = true
        replyCountLabel?.isHidden = true
        spineLayer.isHidden = true
    }

    private func isSystemMessage(_ msg: Message) -> Bool {
        msg.messageType == .system
    }

    // MARK: - Layout

    override func layoutSubviews() {
        super.layoutSubviews()
        guard let config else { return }

        // Skip layout if nothing changed — bounds same and no configure() since last pass
        if !layoutInvalidated && bounds == lastLayoutBounds { return }

        // Width changed since sizeThatFits — invalidate cached sizes
        if cachedFitWidth > 0 && abs(bounds.width - cachedFitWidth) > 1 {
            cachedContentSizes.removeAll(keepingCapacity: true)
        }

        lastLayoutBounds = bounds
        layoutInvalidated = false

        // Moderation, system, and unsent placeholders are centered
        if config.message.isModerationHidden {
            moderationHiddenMessage?.frame = bounds
            return
        }
        if config.message.isUnsent {
            unsentMessage?.frame = bounds
            return
        }
        if isSystemMessage(config.message) {
            systemMessage?.frame = bounds
            return
        }

        // Regular message layout — uses cached sizes from sizeThatFits() when available
        let maxBubbleWidth = bounds.width * 0.75
        let avatarSize: CGFloat = config.showAvatar ? 28 : 0
        let avatarSpacing: CGFloat = config.showAvatar ? 8 : 0
        let topPadding: CGFloat = config.isFirstInSeries ? 8 : 2
        var y: CGFloat = topPadding

        // Sender name
        if let lbl = senderNameLabel, !lbl.isHidden {
            let x = avatarSize + avatarSpacing + 12
            let rowHeight = captionRowHeight(for: lbl)
            lbl.frame = CGRect(x: x, y: y, width: maxBubbleWidth, height: rowHeight - 2)
            y += rowHeight
        }

        // Reply preview — use cached size or fall back to measurement
        if let rp = replyPreview, !rp.isHidden {
            let rpSize = cachedContentSizes[ObjectIdentifier(rp)]
                ?? rp.sizeThatFits(CGSize(width: maxBubbleWidth, height: .greatestFiniteMagnitude))
            let x = config.isFromCurrentUser
                ? bounds.width - rpSize.width
                : avatarSize + avatarSpacing
            rp.frame = CGRect(x: x, y: y, width: rpSize.width, height: rpSize.height)
            y += rpSize.height + 2
        }

        // Content bubbles — use cached sizes or fall back to measurement
        let contentViews = visibleContentViews()
        var primaryContentView: UIView?
        for cv in contentViews {
            let fitWidth = (cv is EmojiBubbleView) ? bounds.width : maxBubbleWidth
            let cvSize = cachedContentSizes[ObjectIdentifier(cv)]
                ?? cv.sizeThatFits(CGSize(width: fitWidth, height: .greatestFiniteMagnitude))
            let x = config.isFromCurrentUser
                ? bounds.width - cvSize.width
                : avatarSize + avatarSpacing
            cv.frame = CGRect(x: x, y: y, width: cvSize.width, height: cvSize.height)
            y = cv.frame.maxY + 2
            if primaryContentView == nil { primaryContentView = cv }
        }
        if !contentViews.isEmpty { y += 2 }

        // Reaction badge — use cached size or fall back
        if let primary = primaryContentView, let rb = reactionStickerBadge, !rb.isHidden {
            let rbSize = cachedContentSizes[ObjectIdentifier(rb)]
                ?? rb.sizeThatFits(.zero)
            let rbX = config.isFromCurrentUser ? primary.frame.minX + 4 : primary.frame.maxX - rbSize.width - 4
            rb.frame = CGRect(x: rbX, y: primary.frame.minY - rbSize.height * 0.6, width: rbSize.width, height: rbSize.height)
        }

        // Reply arrow icon position (to the side of the first content bubble)
        if let cv = primaryContentView {
            let arrowSize: CGFloat = 24
            let arrowY = cv.frame.midY - arrowSize / 2
            // The content slides right, so the arrow sits in the space it vacates: just left of
            // an outgoing bubble, and at the leading edge for an incoming one (it used to sit to
            // the right of incoming bubbles, where the sliding bubble covered it).
            if config.isFromCurrentUser {
                replyArrowIcon.frame = CGRect(x: cv.frame.minX - arrowSize - 8, y: arrowY, width: arrowSize, height: arrowSize)
            } else {
                replyArrowIcon.frame = CGRect(x: 8, y: arrowY, width: arrowSize, height: arrowSize)
            }
        }

        // Footer row ("3:45 PM" · "Edited" · "Delivered") — fixed-height labels, sizeToFit is
        // cheap. The whole group is right-aligned for outgoing messages, left-aligned otherwise.
        if isFooterRowVisible {
            var items: [UIView] = []
            if let ts = timestampLabel, !ts.isHidden { ts.sizeToFit(); items.append(ts) }
            if let el = editedLabel, !el.isHidden { el.sizeToFit(); items.append(el) }
            if let rr = readReceipt, !rr.isHidden {
                rr.frame.size = rr.sizeThatFits(CGSize(width: 160, height: footerRowHeight))
                items.append(rr)
            }
            let gap: CGFloat = 4
            let totalWidth = items.reduce(0) { $0 + $1.frame.width } + gap * CGFloat(max(items.count - 1, 0))
            var x = config.isFromCurrentUser
                ? bounds.width - totalWidth - 4
                : avatarSize + avatarSpacing + 4
            let rowHeight = footerRowHeight
            for item in items {
                item.frame = CGRect(x: x, y: y + (rowHeight - item.frame.height) / 2, width: item.frame.width, height: item.frame.height)
                x += item.frame.width + gap
            }
            y += rowHeight
        }

        // Failed retry — advances by the same row height sizeThatFits reserved for it
        if let fr = failedRetryLabel, !fr.isHidden {
            fr.sizeToFit()
            let x = config.isFromCurrentUser ? bounds.width - fr.frame.width - 4 : avatarSize + avatarSpacing + 4
            fr.frame.origin = CGPoint(x: x, y: y)
            y += captionRowHeight(for: fr)
        }

        // Reply count label — same rule
        if let rcl = replyCountLabel, !rcl.isHidden {
            rcl.sizeToFit()
            let rclX = config.isFromCurrentUser
                ? bounds.width - rcl.frame.width - 4
                : avatarSize + avatarSpacing + 4
            rcl.frame.origin = CGPoint(x: rclX, y: y)
            y += captionRowHeight(for: rcl)
        }

        // Avatar (bottom-aligned with last content view)
        if let av = avatarView, !av.isHidden, config.isLastInSeries {
            let contentBottom = contentViews.last?.frame.maxY ?? y
            av.frame = CGRect(x: 0, y: contentBottom - 28, width: 28, height: 28)
        }

        // Reply spine
        if !spineLayer.isHidden, let spine = config.replySpine, let cv = contentViews.first {
            let spineX: CGFloat = config.isFromCurrentUser
                ? cv.frame.maxX + 4
                : (avatarSize > 0 ? avatarSize / 2 : cv.frame.minX - 4)
            let topY = spine.showTop ? 0 : cv.frame.midY * 0.35
            let bottomY = spine.showBottom ? bounds.height : cv.frame.midY + (bounds.height - cv.frame.midY) * 0.65

            let path = UIBezierPath()
            path.move(to: CGPoint(x: spineX, y: topY))

            if !spine.showTop && spine.showBottom {
                let controlY = topY + (bottomY - topY) * 0.3
                path.addQuadCurve(to: CGPoint(x: spineX, y: bottomY),
                                  controlPoint: CGPoint(x: spineX + (config.isFromCurrentUser ? 6 : -6), y: controlY))
            } else if spine.showTop && !spine.showBottom {
                let controlY = topY + (bottomY - topY) * 0.7
                path.addQuadCurve(to: CGPoint(x: spineX, y: bottomY),
                                  controlPoint: CGPoint(x: spineX + (config.isFromCurrentUser ? 6 : -6), y: controlY))
            } else {
                path.addLine(to: CGPoint(x: spineX, y: bottomY))
            }

            spineLayer.path = path.cgPath
            spineLayer.frame = bounds
        }
    }

    private func visibleContentViews() -> [UIView] {
        [textBubble, emojiBubble, imageBubble, audioBubble, locationBubble, linkPreviewBubble]
            .compactMap { $0 }
            .filter { !$0.isHidden }
    }

    override func sizeThatFits(_ size: CGSize) -> CGSize {
        guard let config else { return .zero }

        if config.message.isModerationHidden {
            return moderationHiddenMessage?.sizeThatFits(size) ?? .zero
        }
        if config.message.isUnsent {
            return unsentMessage?.sizeThatFits(size) ?? .zero
        }
        if isSystemMessage(config.message) {
            return systemMessage?.sizeThatFits(size) ?? .zero
        }

        // Populate cache for layoutSubviews() to consume
        cachedFitWidth = size.width
        cachedContentSizes.removeAll(keepingCapacity: true)

        let maxBubbleWidth = size.width * 0.75
        var height: CGFloat = 0

        // Sender name
        if let lbl = senderNameLabel, !lbl.isHidden { height += captionRowHeight(for: lbl) }
        // Reply preview
        if let rp = replyPreview, !rp.isHidden {
            let rpSize = rp.sizeThatFits(CGSize(width: maxBubbleWidth, height: .greatestFiniteMagnitude))
            cachedContentSizes[ObjectIdentifier(rp)] = rpSize
            height += rpSize.height + 2
        }
        // Content — sum all visible content views
        let cvs = visibleContentViews()
        for cv in cvs {
            let fitWidth = (cv is EmojiBubbleView) ? size.width : maxBubbleWidth
            let cvSize = cv.sizeThatFits(CGSize(width: fitWidth, height: .greatestFiniteMagnitude))
            cachedContentSizes[ObjectIdentifier(cv)] = cvSize
            height += cvSize.height + 2
        }
        if !cvs.isEmpty { height += 2 }
        // Footer row (time / edited / delivery status)
        if isFooterRowVisible { height += footerRowHeight }
        // Failed
        if let fr = failedRetryLabel, !fr.isHidden { height += captionRowHeight(for: fr) }
        // Reply count
        if let rcl = replyCountLabel, !rcl.isHidden { height += captionRowHeight(for: rcl) }
        // Padding
        let topPadding: CGFloat = config.isFirstInSeries ? 8 : 2
        let bottomPadding: CGFloat = 2
        height += topPadding + bottomPadding

        // Reaction badge offset
        if reactionStickerBadge?.isHidden == false { height += 10 }

        return CGSize(width: size.width, height: height)
    }

    // MARK: - Gestures

    private func setupGestures() {
        panGesture = UIPanGestureRecognizer(target: self, action: #selector(handlePan))
        panGesture.delegate = self
        addGestureRecognizer(panGesture)

        longPressGesture = UILongPressGestureRecognizer(target: self, action: #selector(handleLongPress))
        longPressGesture.minimumPressDuration = 0.3
        // No require(toFail:) — pan and long-press coexist. Pan activates via
        // horizontal direction lock in gestureRecognizerShouldBegin; long-press
        // has its own 0.3s duration gate. Per spec: "Pan and long-press coexist."
        addGestureRecognizer(longPressGesture)

        tapGesture = UITapGestureRecognizer(target: self, action: #selector(handleTap))
        tapGesture.require(toFail: panGesture)
        tapGesture.require(toFail: longPressGesture)
        addGestureRecognizer(tapGesture)
    }

    @objc private func handlePan(_ gr: UIPanGestureRecognizer) {
        guard let config, !config.message.isModerationHidden else { return }
        let translation = gr.translation(in: self)

        switch gr.state {
        case .changed:
            let horizontal = abs(translation.x)
            let vertical = abs(translation.y)
            guard horizontal > vertical * 2 else { return }
            let raw = translation.x

            // Swipe right to reply for both senders, as in iMessage. Own bubbles used to need a
            // swipe left, so the familiar gesture did nothing on them. A leftward drag clamps
            // to zero, which also clears the offset if the finger comes back past its start.
            swipeOffset = min(max(raw, 0) * 0.6, swipeThreshold * 1.2)

            if abs(swipeOffset) >= swipeThreshold && !isSwipingToReply {
                isSwipingToReply = true
                HapticManager.mediumImpact()
            } else if abs(swipeOffset) < swipeThreshold {
                isSwipingToReply = false
            }

            // Update reply arrow
            let progress = min(1.0, abs(swipeOffset) / swipeThreshold)
            replyArrowIcon.alpha = progress
            replyArrowIcon.transform = CGAffineTransform(scaleX: progress, y: progress)

            // Apply offset to all content views
            for cv in visibleContentViews() {
                cv.transform = CGAffineTransform(translationX: swipeOffset, y: 0)
            }

        case .ended, .cancelled:
            if abs(swipeOffset) >= swipeThreshold {
                delegate?.messageCellDidSwipeToReply(self, message: config.message)
            }

            let animator = UIViewPropertyAnimator(duration: 0.3, dampingRatio: 0.7) {
                for cv in self.visibleContentViews() {
                    cv.transform = .identity
                }
                self.replyArrowIcon.alpha = 0
                self.replyArrowIcon.transform = .identity
            }
            animator.startAnimation()
            swipeOffset = 0
            isSwipingToReply = false

        default: break
        }
    }

    @objc private func handleLongPress(_ gr: UILongPressGestureRecognizer) {
        // No overlay for rows it has nothing to offer: the user's own system lines and unsent
        // or hidden placeholders (see gestureRecognizerShouldBegin).
        guard gr.state == .began, let config,
              MessageOverlayAvailability.canPresentOverlay(for: config.message, isFromCurrentUser: config.isFromCurrentUser) else { return }
        HapticManager.heavyImpact()
        delegate?.messageCellDidLongPress(self, message: config.message)
    }

    @objc private func handleTap(_ gr: UITapGestureRecognizer) {
        guard let config else { return }

        if config.message.isModerationHidden {
            return
        }

        if config.isFailed {
            delegate?.messageCellDidTapRetry(self, message: config.message)
            return
        }

        // If this message is part of a thread, open the thread view (inside the thread itself
        // there is nothing to open, so the tap reveals the time like any other bubble)
        if !config.isInThread, config.message.replyToId != nil || config.replyCount > 0 {
            delegate?.messageCellDidTapViewThread(self, message: config.message)
            return
        }

        // Reveal the time for 2 seconds (iMessage reveals on drag; tap is the equivalent here).
        // Only the time label is temporary — "Edited" and the delivery status keep their own rules.
        timestampHideWorkItem?.cancel()
        if timestampLabel?.isHidden != false {
            showFooter(config: config, revealTime: true)
            setNeedsLayout()
            onIntrinsicSizeChanged?()
        }
        let workItem = DispatchWorkItem { [weak self] in
            guard let self else { return }
            self.timestampLabel?.isHidden = true
            self.setNeedsLayout()
            self.onIntrinsicSizeChanged?()
        }
        timestampHideWorkItem = workItem
        DispatchQueue.main.asyncAfter(deadline: .now() + 2, execute: workItem)
    }

    // MARK: - Reuse

    func prepareForReuse() {
        config = nil
        backgroundColor = .clear
        layer.removeAllAnimations()
        hasAnimatedEntrance = false
        swipeOffset = 0
        isSwipingToReply = false
        timestampHideWorkItem?.cancel()
        timestampHideWorkItem = nil
        textBubble?.prepareForReuse()
        emojiBubble?.prepareForReuse()
        imageBubble?.prepareForReuse()
        audioBubble?.prepareForReuse()
        locationBubble?.prepareForReuse()
        linkPreviewBubble?.prepareForReuse()
        systemMessage?.prepareForReuse()
        unsentMessage?.prepareForReuse()
        moderationHiddenMessage?.prepareForReuse()
        avatarView?.prepareForReuse()
        reactionStickerBadge?.prepareForReuse()
        readReceipt?.prepareForReuse()
        replyPreview?.prepareForReuse()
        replyCountLabel?.isHidden = true
        hideAllContent()
        alpha = 1
        transform = .identity
    }
}

// MARK: - UIGestureRecognizerDelegate

extension MessageCellView: UIGestureRecognizerDelegate {
    override func gestureRecognizerShouldBegin(_ gestureRecognizer: UIGestureRecognizer) -> Bool {
        if config?.message.isModerationHidden == true,
           (gestureRecognizer === panGesture || gestureRecognizer === longPressGesture) {
            return false
        }
        if let config {
            // Nothing can be done to an unsent placeholder or the user's own system line
            // (another member's keeps Report), and a message that is not on the server yet
            // cannot be replied to: no menu, no reply swipe.
            if gestureRecognizer === longPressGesture,
               !MessageOverlayAvailability.canPresentOverlay(for: config.message, isFromCurrentUser: config.isFromCurrentUser) {
                return false
            }
            if gestureRecognizer === panGesture, !allowsReply(config) {
                return false
            }
        }
        if gestureRecognizer === panGesture {
            let velocity = panGesture.velocity(in: self)
            // Only begin if predominantly horizontal
            return abs(velocity.x) > abs(velocity.y) * 2
        }
        return true
    }

    func gestureRecognizer(_ gestureRecognizer: UIGestureRecognizer, shouldRecognizeSimultaneouslyWith other: UIGestureRecognizer) -> Bool {
        // Don't conflict with collection view scroll
        return false
    }
}

/// Displays a placeholder for a moderation-hidden message.
final class ModerationHiddenMessageView: UIView {

    // MARK: - Subviews

    private let iconView = UIImageView()
    private let titleLabel = UILabel()
    private let subtitleLabel = UILabel()
    private let borderLayer = CAShapeLayer()

    // MARK: - State

    private var hiddenReason: String?

    // MARK: - Init

    override init(frame: CGRect) {
        super.init(frame: frame)
        setup()
    }

    required init?(coder: NSCoder) {
        super.init(coder: coder)
        setup()
    }

    private func setup() {
        borderLayer.fillColor = UIColor.systemOrange.withAlphaComponent(0.08).cgColor
        borderLayer.strokeColor = UIColor.systemOrange.withAlphaComponent(0.5).cgColor
        borderLayer.lineWidth = 1
        layer.addSublayer(borderLayer)

        let iconConfig = UIImage.SymbolConfiguration(textStyle: .caption1)
        iconView.image = UIImage(systemName: "eye.slash", withConfiguration: iconConfig)
        iconView.tintColor = .systemOrange
        addSubview(iconView)

        titleLabel.font = .preferredFont(forTextStyle: .caption1).withWeight(.semibold)
        titleLabel.textColor = .label
        titleLabel.text = "messaging_moderation_hidden_title".localized
        titleLabel.numberOfLines = 1
        addSubview(titleLabel)

        subtitleLabel.font = .preferredFont(forTextStyle: .caption2)
        subtitleLabel.textColor = .secondaryLabel
        subtitleLabel.text = "messaging_moderation_hidden_subtitle".localized
        subtitleLabel.numberOfLines = 0
        addSubview(subtitleLabel)

        isAccessibilityElement = true
        accessibilityTraits = .staticText
        accessibilityIdentifier = "message.moderationHiddenPlaceholder"
    }

    // MARK: - Configure

    func configure(reason: String?) {
        hiddenReason = reason?.trimmingCharacters(in: .whitespacesAndNewlines)
        if let hiddenReason, !hiddenReason.isEmpty {
            accessibilityLabel = "messaging_moderation_hidden_accessibility_with_reason".localized(with: hiddenReason)
        } else {
            accessibilityLabel = "messaging_moderation_hidden_accessibility".localized
        }
        accessibilityHint = subtitleLabel.text
        setNeedsLayout()
    }

    // MARK: - Layout

    override func layoutSubviews() {
        super.layoutSubviews()
        let b = bounds
        let cornerRadius: CGFloat = 18
        borderLayer.path = UIBezierPath(roundedRect: b, cornerRadius: cornerRadius).cgPath

        let hPad: CGFloat = 14
        let vPad: CGFloat = 10
        let spacing: CGFloat = 8
        let labelSpacing: CGFloat = 2
        let iconSize: CGFloat = 16

        let contentWidth = max(0, b.width - (hPad * 2) - iconSize - spacing)
        let titleSize = titleLabel.sizeThatFits(CGSize(width: contentWidth, height: .greatestFiniteMagnitude))
        let subtitleSize = subtitleLabel.sizeThatFits(CGSize(width: contentWidth, height: .greatestFiniteMagnitude))
        let totalLabelHeight = titleSize.height + labelSpacing + subtitleSize.height

        iconView.frame = CGRect(
            x: hPad,
            y: vPad,
            width: iconSize,
            height: iconSize
        )

        let labelX = iconView.frame.maxX + spacing
        titleLabel.frame = CGRect(
            x: labelX,
            y: vPad,
            width: contentWidth,
            height: titleSize.height
        )
        subtitleLabel.frame = CGRect(
            x: labelX,
            y: titleLabel.frame.maxY + labelSpacing,
            width: contentWidth,
            height: subtitleSize.height
        )

        let iconOffset = max(0, (totalLabelHeight - iconSize) / 2)
        iconView.frame.origin.y += iconOffset
    }

    override func sizeThatFits(_ size: CGSize) -> CGSize {
        let hPad: CGFloat = 14
        let vPad: CGFloat = 10
        let spacing: CGFloat = 8
        let labelSpacing: CGFloat = 2
        let iconSize: CGFloat = 16
        let fittingWidth = size.width > 0 ? size.width : 260
        let contentWidth = max(0, fittingWidth - (hPad * 2) - iconSize - spacing)
        let titleSize = titleLabel.sizeThatFits(CGSize(width: contentWidth, height: .greatestFiniteMagnitude))
        let subtitleSize = subtitleLabel.sizeThatFits(CGSize(width: contentWidth, height: .greatestFiniteMagnitude))
        let height = vPad + titleSize.height + labelSpacing + subtitleSize.height + vPad
        return CGSize(width: fittingWidth, height: max(height, iconSize + vPad * 2))
    }

    // MARK: - Reuse

    func prepareForReuse() {
        hiddenReason = nil
        accessibilityLabel = nil
        accessibilityHint = nil
    }

    // MARK: - Trait changes

    override func traitCollectionDidChange(_ previousTraitCollection: UITraitCollection?) {
        super.traitCollectionDidChange(previousTraitCollection)
        if traitCollection.hasDifferentColorAppearance(comparedTo: previousTraitCollection) {
            borderLayer.fillColor = UIColor.systemOrange.withAlphaComponent(0.08).cgColor
            borderLayer.strokeColor = UIColor.systemOrange.withAlphaComponent(0.5).cgColor
        }
    }
}

private extension UIFont {
    func withWeight(_ weight: UIFont.Weight) -> UIFont {
        let descriptor = fontDescriptor.addingAttributes([
            .traits: [UIFontDescriptor.TraitKey.weight: weight]
        ])
        return UIFont(descriptor: descriptor, size: pointSize)
    }
}

// MARK: - Bubble accessibility context

/// Base class of the content bubbles (text, emoji, image, audio, location).
///
/// Each bubble owns its accessibility label (the text, "Photo", "Voice message, paused, 0:07").
/// `MessageCellView` adds who sent the message before it and the time, "Edited" and reply count
/// after it, so VoiceOver reads one complete element. The label is composed in the getter
/// because the image and audio bubbles update their own label later (load finished, playback
/// state), which would overwrite a label composed once at configure time.
class MessageBubbleContentView: UIView {

    /// Spoken before the bubble's own label: "You" or the sender's name.
    var accessibilityContextPrefix: String?
    /// Spoken after the bubble's own label: time, "Edited", reply count.
    var accessibilityContextSuffix: String?

    override var accessibilityLabel: String? {
        get {
            let parts = [accessibilityContextPrefix, super.accessibilityLabel, accessibilityContextSuffix]
                .compactMap { $0 }
                .filter { !$0.isEmpty }
            return parts.isEmpty ? nil : parts.joined(separator: ", ")
        }
        set { super.accessibilityLabel = newValue }
    }
}
