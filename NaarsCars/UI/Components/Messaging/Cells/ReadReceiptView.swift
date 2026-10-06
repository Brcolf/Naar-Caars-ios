//
//  ReadReceiptView.swift
//  NaarsCars
//
//  UIKit read receipt — checkmarks for DMs, avatar thumbnails for groups
//

import UIKit

/// Displays read receipt status: checkmarks (DM) or small avatars (group).
final class ReadReceiptView: UIView {

    // MARK: - Read Status

    enum ReadStatus {
        case failed
        case sending
        case sent
        case delivered
        case read
    }

    // MARK: - Subviews

    private let statusContainer = UIView()
    private let singleCheck = UIImageView()
    private let doubleCheck1 = UIImageView()
    private let doubleCheck2 = UIImageView()
    private let clockIcon = UIImageView()
    private let failedIcon = UIImageView()
    /// iMessage-style status text ("Delivered" / "Read") used for one-to-one threads and for
    /// groups until someone has read the message. The checkmark icons are kept for group mode.
    private let statusLabel = UILabel()
    private var avatarViews: [AvatarUIView] = []

    // MARK: - State

    private var isGroupMode = false
    private var currentStatus: ReadStatus = .sending

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
        addSubview(statusContainer)

        let captionConfig = UIImage.SymbolConfiguration(textStyle: .caption1, scale: .small)
        let checkBold = UIImage.SymbolConfiguration(textStyle: .caption1, scale: .small).applying(UIImage.SymbolConfiguration(weight: .semibold))

        clockIcon.image = UIImage(systemName: "clock", withConfiguration: captionConfig)
        clockIcon.tintColor = UIColor.secondaryLabel.withAlphaComponent(0.6)
        statusContainer.addSubview(clockIcon)

        singleCheck.image = UIImage(systemName: "checkmark", withConfiguration: checkBold)
        singleCheck.tintColor = .secondaryLabel
        statusContainer.addSubview(singleCheck)

        doubleCheck1.image = UIImage(systemName: "checkmark", withConfiguration: checkBold)
        statusContainer.addSubview(doubleCheck1)

        doubleCheck2.image = UIImage(systemName: "checkmark", withConfiguration: checkBold)
        statusContainer.addSubview(doubleCheck2)

        let failConfig = UIImage.SymbolConfiguration(textStyle: .footnote)
        failedIcon.image = UIImage(systemName: "exclamationmark.circle.fill", withConfiguration: failConfig)
        failedIcon.tintColor = .systemRed
        statusContainer.addSubview(failedIcon)

        statusLabel.font = .preferredFont(forTextStyle: .caption1)
        statusLabel.adjustsFontForContentSizeCategory = true
        statusLabel.textColor = .secondaryLabel
        addSubview(statusLabel)
    }

    /// Localized footer text for a status, iMessage wording.
    private static func statusText(for status: ReadStatus) -> String {
        switch status {
        case .failed: return "messaging_status_not_delivered".localized
        case .sending: return "messaging_status_sending".localized
        case .sent, .delivered: return "messaging_status_delivered".localized
        case .read: return "messaging_status_read".localized
        }
    }

    private func showStatusText(_ status: ReadStatus) {
        statusLabel.text = Self.statusText(for: status)
        statusLabel.textColor = status == .failed ? .systemRed : .secondaryLabel
        statusLabel.isHidden = false
    }

    // MARK: - Configure (DM mode)

    func configure(message: Message, isFailed: Bool, totalParticipants: Int) {
        let status = Self.deriveStatus(message: message, isFailed: isFailed, totalParticipants: totalParticipants)
        self.currentStatus = status
        self.isGroupMode = false

        hideAll()
        showStatusText(status)

        isAccessibilityElement = true
        accessibilityTraits = .staticText
        accessibilityIdentifier = "message.readReceipt"
        switch status {
        case .failed:
            accessibilityLabel = "accessibility_status_failed".localized
        case .sending:
            accessibilityLabel = "accessibility_status_sending".localized
        case .sent:
            accessibilityLabel = "accessibility_status_sent".localized
        case .delivered:
            accessibilityLabel = "accessibility_status_delivered".localized
        case .read:
            accessibilityLabel = "accessibility_status_read".localized
        }

        setNeedsLayout()
    }

    // MARK: - Configure (group mode with avatars)

    func configureGroup(message: Message, isFailed: Bool, totalParticipants: Int, readByProfiles: [Profile]) {
        let status = Self.deriveStatus(message: message, isFailed: isFailed, totalParticipants: totalParticipants)
        self.currentStatus = status

        hideAll()

        if (status == .delivered || status == .read) && !readByProfiles.isEmpty {
            isGroupMode = true
            // Show mini avatars for readers
            let maxAvatars = min(readByProfiles.count, 3)
            ensureAvatarViews(count: maxAvatars)
            for (i, profile) in readByProfiles.prefix(maxAvatars).enumerated() {
                let av = avatarViews[i]
                av.configure(imageUrl: profile.avatarUrl, name: profile.name, size: 16)
                av.isHidden = false
            }
        } else {
            isGroupMode = false
            showStatusText(status)
        }

        isAccessibilityElement = true
        accessibilityTraits = .staticText
        if isGroupMode && !readByProfiles.isEmpty {
            let names = readByProfiles.prefix(3).map { $0.name }.joined(separator: ", ")
            accessibilityLabel = "accessibility_read_by".localized(with: names)
        } else {
            switch status {
            case .failed:
                accessibilityLabel = "accessibility_status_failed".localized
            case .sending:
                accessibilityLabel = "accessibility_status_sending".localized
            case .sent:
                accessibilityLabel = "accessibility_status_sent".localized
            case .delivered:
                accessibilityLabel = "accessibility_status_delivered".localized
            case .read:
                accessibilityLabel = "accessibility_status_read".localized
            }
        }

        setNeedsLayout()
    }

    // MARK: - Layout

    override func layoutSubviews() {
        super.layoutSubviews()
        let b = bounds

        if isGroupMode {
            statusContainer.frame = .zero
            var x: CGFloat = 0
            for av in avatarViews where !av.isHidden {
                av.frame = CGRect(x: x, y: (b.height - 16) / 2, width: 16, height: 16)
                x += 12 // overlapping
            }
        } else {
            statusContainer.frame = b
            statusLabel.frame = b
            let iconSize: CGFloat = 14
            let midY = b.height / 2

            clockIcon.frame = CGRect(x: 0, y: midY - iconSize / 2, width: iconSize, height: iconSize)
            failedIcon.frame = CGRect(x: 0, y: midY - iconSize / 2, width: iconSize, height: iconSize)
            singleCheck.frame = CGRect(x: 0, y: midY - iconSize / 2, width: iconSize, height: iconSize)
            doubleCheck1.frame = CGRect(x: 0, y: midY - iconSize / 2, width: iconSize, height: iconSize)
            doubleCheck2.frame = CGRect(x: iconSize - 4, y: midY - iconSize / 2, width: iconSize, height: iconSize)
        }
    }

    override func sizeThatFits(_ size: CGSize) -> CGSize {
        if isGroupMode {
            let visibleCount = avatarViews.filter { !$0.isHidden }.count
            let w = visibleCount > 0 ? CGFloat(visibleCount - 1) * 12 + 16 : 0
            return CGSize(width: w, height: 16)
        }
        let text = statusLabel.sizeThatFits(CGSize(width: size.width, height: .greatestFiniteMagnitude))
        return CGSize(width: ceil(text.width), height: max(ceil(text.height), 14))
    }

    // MARK: - Reuse

    func prepareForReuse() {
        hideAll()
        isGroupMode = false
        // Reset excess avatar views to prevent stale state
        for av in avatarViews {
            av.prepareForReuse()
        }
    }

    // MARK: - Helpers

    private func hideAll() {
        statusLabel.isHidden = true
        clockIcon.isHidden = true
        failedIcon.isHidden = true
        singleCheck.isHidden = true
        doubleCheck1.isHidden = true
        doubleCheck2.isHidden = true
        for av in avatarViews { av.isHidden = true }
    }

    private func ensureAvatarViews(count: Int) {
        while avatarViews.count < count {
            let av = AvatarUIView()
            addSubview(av)
            avatarViews.append(av)
        }
    }

    static func deriveStatus(message: Message, isFailed: Bool, totalParticipants: Int) -> ReadStatus {
        // The durable sendStatus is authoritative only while the send is in flight or failed.
        // Every stored message carries "sent" (MessagingMapper default), so returning it here
        // meant read receipts never progressed past the single checkmark (2026-10-05).
        switch message.sendStatus {
        case .failed?: return .failed
        case .sending?: return .sending
        case .delivered?: return .delivered
        case .read?: return .read
        case .sent?, nil: break
        }

        if isFailed { return .failed }

        // Server-accepted: derive delivered/read from who has read it.
        let readByOthers = message.readBy.filter { $0 != message.fromId }
        let otherParticipants = max(totalParticipants - 1, 0)

        if readByOthers.isEmpty {
            return .sent
        } else if otherParticipants > 0 && readByOthers.count >= otherParticipants {
            return .read
        } else {
            return .delivered
        }
    }
}
