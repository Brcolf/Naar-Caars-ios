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
    }

    // MARK: - Configure (DM mode)

    func configure(message: Message, isFailed: Bool, totalParticipants: Int) {
        let status = Self.deriveStatus(message: message, isFailed: isFailed, totalParticipants: totalParticipants)
        self.currentStatus = status
        self.isGroupMode = false

        hideAll()
        switch status {
        case .failed:
            failedIcon.isHidden = false
        case .sending:
            clockIcon.isHidden = false
        case .sent:
            singleCheck.isHidden = false
        case .delivered:
            doubleCheck1.isHidden = false
            doubleCheck2.isHidden = false
            doubleCheck1.tintColor = .secondaryLabel
            doubleCheck2.tintColor = .secondaryLabel
        case .read:
            doubleCheck1.isHidden = false
            doubleCheck2.isHidden = false
            doubleCheck1.tintColor = UIColor.naarsPrimary
            doubleCheck2.tintColor = UIColor.naarsPrimary
        }

        setNeedsLayout()
    }

    // MARK: - Configure (group mode with avatars)

    func configureGroup(message: Message, isFailed: Bool, totalParticipants: Int, readByProfiles: [Profile]) {
        let status = Self.deriveStatus(message: message, isFailed: isFailed, totalParticipants: totalParticipants)
        self.currentStatus = status

        hideAll()

        if status == .read && !readByProfiles.isEmpty {
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
            switch status {
            case .failed:
                failedIcon.isHidden = false
            case .sending:
                clockIcon.isHidden = false
            case .sent:
                singleCheck.isHidden = false
            case .delivered:
                doubleCheck1.isHidden = false
                doubleCheck2.isHidden = false
                doubleCheck1.tintColor = .secondaryLabel
                doubleCheck2.tintColor = .secondaryLabel
            case .read:
                doubleCheck1.isHidden = false
                doubleCheck2.isHidden = false
                doubleCheck1.tintColor = UIColor.naarsPrimary
                doubleCheck2.tintColor = UIColor.naarsPrimary
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
        switch currentStatus {
        case .delivered, .read:
            return CGSize(width: 24, height: 14) // double check
        default:
            return CGSize(width: 14, height: 14) // single icon
        }
    }

    // MARK: - Reuse

    func prepareForReuse() {
        hideAll()
        isGroupMode = false
    }

    // MARK: - Helpers

    private func hideAll() {
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
        // Use the durable sendStatus first
        if let status = message.sendStatus {
            switch status {
            case .failed: return .failed
            case .sending: return .sending
            case .sent: return .sent
            case .delivered: return .delivered
            case .read: return .read
            }
        }

        if isFailed { return .failed }

        // Fallback: derive from readBy array
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
}
