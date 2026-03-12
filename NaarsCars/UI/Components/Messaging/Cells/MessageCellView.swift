//
//  MessageCellView.swift
//  NaarsCars
//
//  Top-level UIView for rendering a message cell. Composes content subviews,
//  handles layout and gesture recognition. Replaces the SwiftUI MessageBubble.
//

import UIKit

final class MessageCellView: UIView {

    // MARK: - Subviews (lazily created)

    private var textBubble: TextBubbleView?
    private var imageBubble: ImageBubbleView?
    private var audioBubble: AudioBubbleView?
    private var locationBubble: LocationBubbleView?
    private var linkPreviewBubble: LinkPreviewBubbleView?
    private var systemMessage: SystemMessageView?
    private var unsentMessage: UnsentMessageView?

    private var avatarView: AvatarUIView?
    private var senderNameLabel: UILabel?
    private var replyPreview: ReplyPreviewUIView?
    private var reactionBadge: ReactionBadgeView?
    private var readReceipt: ReadReceiptView?
    private var timestampLabel: UILabel?
    private var editedLabel: UILabel?
    private var failedRetryLabel: UILabel?
    private let replyArrowIcon = UIImageView(image: UIImage(systemName: "arrowshape.turn.up.left.fill"))

    // Reply spine
    private let spineLayer = CAShapeLayer()

    // MARK: - State

    private var config: MessageCellConfig?
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
    }

    required init?(coder: NSCoder) { fatalError() }

    // MARK: - Configuration

    func configure(with config: MessageCellConfig) {
        self.config = config
        let msg = config.message

        // Hide all content views first
        hideAllContent()

        if msg.isUnsent {
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
            backgroundColor = UIColor.naarsPrimary.withAlphaComponent(0.12)
            UIView.animate(withDuration: 1.5, delay: 0.3, options: .curveEaseOut) {
                self.backgroundColor = .clear
            }
        } else {
            backgroundColor = .clear
        }

        setNeedsLayout()
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

    private func showSystem(msg: Message) {
        let view = systemMessage ?? {
            let v = SystemMessageView()
            addSubview(v)
            systemMessage = v
            return v
        }()
        view.isHidden = false
        view.configure(text: msg.text)
    }

    private func showRegular(config: MessageCellConfig) {
        let msg = config.message

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
                    imageUrl: msg.sender?.avatarUrl,
                    name: msg.sender?.name ?? "messaging_deleted_user".localized,
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
            lbl.text = msg.sender?.name ?? "messaging_deleted_user".localized
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
        if msg.isAudioMessage, let audioUrl = msg.audioUrl {
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
                view.configure(localPath: localPath) { [weak self] url in
                    guard let self else { return }
                    self.delegate?.messageCellDidTapImage(self, url: url)
                }
            } else if let remoteUrl = msg.imageUrl {
                view.configure(remoteUrl: remoteUrl) { [weak self] url in
                    guard let self else { return }
                    self.delegate?.messageCellDidTapImage(self, url: url)
                }
            }
        }

        // Text bubble (show if text is non-empty and not audio/location)
        if !msg.text.isEmpty && !msg.isAudioMessage && !msg.isLocationMessage {
            let view = textBubble ?? {
                let v = TextBubbleView()
                addSubview(v)
                textBubble = v
                return v
            }()
            view.isHidden = false
            view.configure(text: msg.text, isFromCurrentUser: config.isFromCurrentUser, showTail: config.isLastInSeries)
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
        if let reactions = msg.reactions, !reactions.reactions.isEmpty {
            let rb = reactionBadge ?? {
                let v = ReactionBadgeView()
                addSubview(v)
                reactionBadge = v
                return v
            }()
            rb.isHidden = false
            rb.configure(reactions: reactions)
            rb.onReactionTap = { [weak self] reaction in
                guard let self, let config = self.config else { return }
                let currentUserId = AuthService.shared.currentUserId
                let hasReacted = reactions.reactions.values.contains { $0.contains(where: { $0 == currentUserId }) }
                if hasReacted {
                    self.delegate?.messageCellDidTapReaction(self, message: config.message, reaction: nil)
                } else {
                    self.delegate?.messageCellDidLongPress(self, message: config.message)
                }
            }
            rb.onReactionLongPress = { [weak self] reaction in
                guard let self, let config = self.config else { return }
                self.delegate?.messageCellDidTapReaction(self, message: config.message, reaction: "__details__")
            }
        }

        // Timestamp + read receipt (last in series)
        if config.isLastInSeries || timestampLabel?.isHidden == false {
            showTimestamp(config: config)
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
    }

    private func showTimestamp(config: MessageCellConfig) {
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

        if config.isFromCurrentUser {
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

    private func hideAllContent() {
        textBubble?.isHidden = true
        imageBubble?.isHidden = true
        audioBubble?.isHidden = true
        locationBubble?.isHidden = true
        linkPreviewBubble?.isHidden = true
        systemMessage?.isHidden = true
        unsentMessage?.isHidden = true
        avatarView?.isHidden = true
        senderNameLabel?.isHidden = true
        replyPreview?.isHidden = true
        reactionBadge?.isHidden = true
        readReceipt?.isHidden = true
        timestampLabel?.isHidden = true
        editedLabel?.isHidden = true
        failedRetryLabel?.isHidden = true
        spineLayer.isHidden = true
    }

    private func isSystemMessage(_ msg: Message) -> Bool {
        if msg.messageType == .system { return true }
        let patterns = ["has been added to the conversation", "has joined the conversation",
                        "left the conversation", "removed", "updated the group",
                        "changed the group name", "created the group"]
        return patterns.contains { msg.text.contains($0) }
    }

    // MARK: - Layout

    override func layoutSubviews() {
        super.layoutSubviews()
        guard let config else { return }

        // System and unsent messages are centered
        if config.message.isUnsent {
            unsentMessage?.frame = bounds
            return
        }
        if isSystemMessage(config.message) {
            systemMessage?.frame = bounds
            return
        }

        // Regular message layout
        let maxBubbleWidth = bounds.width * 0.7
        let avatarSize: CGFloat = config.showAvatar ? 28 : 0
        let avatarSpacing: CGFloat = config.showAvatar ? 8 : 0
        var y: CGFloat = 0

        // Sender name
        if let lbl = senderNameLabel, !lbl.isHidden {
            let x = avatarSize + avatarSpacing + 12
            lbl.frame = CGRect(x: x, y: y, width: maxBubbleWidth, height: 16)
            y += 18
        }

        // Reply preview
        if let rp = replyPreview, !rp.isHidden {
            let rpSize = rp.sizeThatFits(CGSize(width: maxBubbleWidth, height: .greatestFiniteMagnitude))
            let x = config.isFromCurrentUser
                ? bounds.width - rpSize.width
                : avatarSize + avatarSpacing
            rp.frame = CGRect(x: x, y: y, width: rpSize.width, height: rpSize.height)
            y += rpSize.height + 2
        }

        // Content bubbles (may have multiple: e.g. text + link preview, image + caption)
        let contentViews = visibleContentViews()
        var primaryContentView: UIView?
        for cv in contentViews {
            let cvSize = cv.sizeThatFits(CGSize(width: maxBubbleWidth, height: .greatestFiniteMagnitude))
            let x = config.isFromCurrentUser
                ? bounds.width - cvSize.width
                : avatarSize + avatarSpacing
            cv.frame = CGRect(x: x, y: y, width: cvSize.width, height: cvSize.height)
            y = cv.frame.maxY + 2
            if primaryContentView == nil { primaryContentView = cv }
        }
        if !contentViews.isEmpty { y += 2 }

        // Reaction badge (anchored to first content view)
        if let primary = primaryContentView, let rb = reactionBadge, !rb.isHidden {
            let rbSize = rb.sizeThatFits(.zero)
            let rbX = config.isFromCurrentUser ? primary.frame.minX : primary.frame.maxX - rbSize.width
            rb.frame = CGRect(x: rbX, y: primary.frame.minY - rbSize.height / 2, width: rbSize.width, height: rbSize.height)
        }

        // Reply arrow icon position (to the side of the first content bubble)
        if let cv = primaryContentView {
            let arrowSize: CGFloat = 24
            let arrowY = cv.frame.midY - arrowSize / 2
            if config.isFromCurrentUser {
                replyArrowIcon.frame = CGRect(x: cv.frame.minX - arrowSize - 8, y: arrowY, width: arrowSize, height: arrowSize)
            } else {
                replyArrowIcon.frame = CGRect(x: cv.frame.maxX + 8, y: arrowY, width: arrowSize, height: arrowSize)
            }
        }

        // Timestamp row
        if let ts = timestampLabel, !ts.isHidden {
            ts.sizeToFit()
            let rowX = config.isFromCurrentUser
                ? bounds.width - ts.frame.width - 4
                : avatarSize + avatarSpacing + 4
            ts.frame.origin = CGPoint(x: rowX, y: y)

            if let el = editedLabel, !el.isHidden {
                el.sizeToFit()
                el.frame.origin = CGPoint(x: ts.frame.maxX + 4, y: y)
            }

            if let rr = readReceipt, !rr.isHidden {
                let rrSize = rr.sizeThatFits(CGSize(width: 100, height: 20))
                let lastX = (editedLabel?.isHidden == false ? editedLabel!.frame.maxX : ts.frame.maxX) + 4
                rr.frame = CGRect(x: lastX, y: y, width: rrSize.width, height: rrSize.height)
            }
        }

        // Failed retry
        if let fr = failedRetryLabel, !fr.isHidden {
            fr.sizeToFit()
            let x = config.isFromCurrentUser ? bounds.width - fr.frame.width - 4 : avatarSize + avatarSpacing + 4
            fr.frame.origin = CGPoint(x: x, y: y)
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
            path.addLine(to: CGPoint(x: spineX, y: bottomY))
            spineLayer.path = path.cgPath
            spineLayer.frame = bounds
        }
    }

    private func visibleContentViews() -> [UIView] {
        [textBubble, imageBubble, audioBubble, locationBubble, linkPreviewBubble]
            .compactMap { $0 }
            .filter { !$0.isHidden }
    }

    override func sizeThatFits(_ size: CGSize) -> CGSize {
        guard let config else { return .zero }

        if config.message.isUnsent {
            return unsentMessage?.sizeThatFits(size) ?? .zero
        }
        if isSystemMessage(config.message) {
            return systemMessage?.sizeThatFits(size) ?? .zero
        }

        let maxBubbleWidth = size.width * 0.7
        var height: CGFloat = 0

        // Sender name
        if senderNameLabel?.isHidden == false { height += 18 }
        // Reply preview
        if let rp = replyPreview, !rp.isHidden {
            height += rp.sizeThatFits(CGSize(width: maxBubbleWidth, height: .greatestFiniteMagnitude)).height + 2
        }
        // Content — sum all visible content views
        let cvs = visibleContentViews()
        for cv in cvs {
            height += cv.sizeThatFits(CGSize(width: maxBubbleWidth, height: .greatestFiniteMagnitude)).height + 2
        }
        if !cvs.isEmpty { height += 2 }
        // Timestamp
        if timestampLabel?.isHidden == false { height += 18 }
        // Failed
        if failedRetryLabel?.isHidden == false { height += 18 }
        // Padding
        let verticalPadding: CGFloat = config.isLastInSeries ? 8 : 2
        height += verticalPadding

        // Reaction badge offset
        if reactionBadge?.isHidden == false { height += 10 }

        return CGSize(width: size.width, height: height)
    }

    // MARK: - Gestures

    private func setupGestures() {
        panGesture = UIPanGestureRecognizer(target: self, action: #selector(handlePan))
        panGesture.delegate = self
        addGestureRecognizer(panGesture)

        longPressGesture = UILongPressGestureRecognizer(target: self, action: #selector(handleLongPress))
        longPressGesture.minimumPressDuration = 0.5
        // No require(toFail:) — pan and long-press coexist. Pan activates via
        // horizontal direction lock in gestureRecognizerShouldBegin; long-press
        // has its own 0.5s duration gate. Per spec: "Pan and long-press coexist."
        addGestureRecognizer(longPressGesture)

        tapGesture = UITapGestureRecognizer(target: self, action: #selector(handleTap))
        tapGesture.require(toFail: panGesture)
        tapGesture.require(toFail: longPressGesture)
        addGestureRecognizer(tapGesture)
    }

    @objc private func handlePan(_ gr: UIPanGestureRecognizer) {
        guard let config else { return }
        let translation = gr.translation(in: self)

        switch gr.state {
        case .changed:
            let horizontal = abs(translation.x)
            let vertical = abs(translation.y)
            guard horizontal > vertical * 2 else { return }
            let raw = translation.x

            if !config.isFromCurrentUser && raw > 0 {
                swipeOffset = min(raw * 0.6, swipeThreshold * 1.2)
            } else if config.isFromCurrentUser && raw < 0 {
                swipeOffset = max(raw * 0.6, -swipeThreshold * 1.2)
            }

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
        guard gr.state == .began, let config else { return }
        HapticManager.heavyImpact()
        delegate?.messageCellDidLongPress(self, message: config.message)
    }

    @objc private func handleTap(_ gr: UITapGestureRecognizer) {
        guard let config else { return }

        if config.isFailed {
            delegate?.messageCellDidTapRetry(self, message: config.message)
            return
        }

        // Toggle timestamp for 2 seconds
        timestampHideWorkItem?.cancel()
        if timestampLabel?.isHidden == true {
            showTimestamp(config: config)
            setNeedsLayout()
            onIntrinsicSizeChanged?()
        }
        let workItem = DispatchWorkItem { [weak self] in
            guard let self, let config = self.config, !config.isLastInSeries else { return }
            self.timestampLabel?.isHidden = true
            self.editedLabel?.isHidden = true
            self.readReceipt?.isHidden = true
            self.setNeedsLayout()
            self.onIntrinsicSizeChanged?()
        }
        timestampHideWorkItem = workItem
        DispatchQueue.main.asyncAfter(deadline: .now() + 2, execute: workItem)
    }

    // MARK: - Reuse

    func prepareForReuse() {
        config = nil
        hasAnimatedEntrance = false
        swipeOffset = 0
        timestampHideWorkItem?.cancel()
        textBubble?.prepareForReuse()
        imageBubble?.prepareForReuse()
        audioBubble?.prepareForReuse()
        locationBubble?.prepareForReuse()
        linkPreviewBubble?.prepareForReuse()
        systemMessage?.prepareForReuse()
        unsentMessage?.prepareForReuse()
        avatarView?.prepareForReuse()
        reactionBadge?.prepareForReuse()
        readReceipt?.prepareForReuse()
        replyPreview?.prepareForReuse()
        hideAllContent()
        alpha = 1
        transform = .identity
    }
}

// MARK: - UIGestureRecognizerDelegate

extension MessageCellView: UIGestureRecognizerDelegate {
    override func gestureRecognizerShouldBegin(_ gestureRecognizer: UIGestureRecognizer) -> Bool {
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
