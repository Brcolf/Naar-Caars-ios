//
//  MessageOverlayController.swift
//  NaarsCars
//
//  Full-screen overlay presented on long-press, showing a message snapshot
//  with a reaction bar and contextual action list
//

import UIKit

/// Full-screen interaction overlay presented when the user long-presses a message.
///
/// Displays the message snapshot at its original position (scaled 1.05x), a horizontal
/// reaction bar, and a contextual action list. Tapping the backdrop or selecting an
/// action dismisses the overlay with a reverse animation.
final class MessageOverlayController: UIViewController {

    // MARK: - Properties

    private let snapshot: UIView
    private let sourceFrame: CGRect
    private let message: Message
    private let isFromCurrentUser: Bool
    private let currentUserReaction: String?
    private let isConversationFrozen: Bool
    private let onAction: (OverlayAction) -> Void

    private let showDetails: Bool
    private let individualReactions: [MessageReaction]
    private let reactionProfiles: [UUID: Profile]
    private let currentUserId: UUID

    private let reactionBar: ReactionBarView
    private let actionList: OverlayActionListView
    private let detailsRow: ReactionDetailsRowView

    private let backdropBlur: UIVisualEffectView = {
        let blur = UIVisualEffectView(effect: nil)
        blur.translatesAutoresizingMaskIntoConstraints = false
        return blur
    }()

    // MARK: - Init

    init(
        snapshot: UIView,
        sourceFrame: CGRect,
        message: Message,
        isFromCurrentUser: Bool,
        currentUserReaction: String?,
        isConversationFrozen: Bool = false,
        onAction: @escaping (OverlayAction) -> Void,
        showDetails: Bool = false,
        individualReactions: [MessageReaction] = [],
        reactionProfiles: [UUID: Profile] = [:],
        currentUserId: UUID = UUID()
    ) {
        self.snapshot = snapshot
        self.sourceFrame = sourceFrame
        self.message = message
        self.isFromCurrentUser = isFromCurrentUser
        self.currentUserReaction = currentUserReaction
        self.isConversationFrozen = isConversationFrozen
        self.onAction = onAction
        self.showDetails = showDetails
        self.individualReactions = individualReactions
        self.reactionProfiles = reactionProfiles
        self.currentUserId = currentUserId

        self.reactionBar = ReactionBarView(currentUserReaction: currentUserReaction)
        self.actionList = OverlayActionListView(message: message, isFromCurrentUser: isFromCurrentUser, isConversationFrozen: isConversationFrozen)
        self.detailsRow = ReactionDetailsRowView()

        super.init(nibName: nil, bundle: nil)

        modalPresentationStyle = .overFullScreen
        modalTransitionStyle = .crossDissolve
    }

    @available(*, unavailable)
    required init?(coder: NSCoder) {
        fatalError("init(coder:) has not been implemented")
    }

    // MARK: - Lifecycle

    override func viewDidLoad() {
        super.viewDidLoad()
        view.backgroundColor = .clear
        setupBackdrop()
        setupSnapshot()
        setupReactionBar()
        setupDetailsRow()
        setupActionList()
        wireCallbacks()
    }

    override func viewDidAppear(_ animated: Bool) {
        super.viewDidAppear(animated)
        performEntranceAnimation()
    }

    // MARK: - Setup

    private func setupBackdrop() {
        view.addSubview(backdropBlur)
        NSLayoutConstraint.activate([
            backdropBlur.topAnchor.constraint(equalTo: view.topAnchor),
            backdropBlur.leadingAnchor.constraint(equalTo: view.leadingAnchor),
            backdropBlur.trailingAnchor.constraint(equalTo: view.trailingAnchor),
            backdropBlur.bottomAnchor.constraint(equalTo: view.bottomAnchor),
        ])

        let tapGesture = UITapGestureRecognizer(target: self, action: #selector(backdropTapped))
        backdropBlur.addGestureRecognizer(tapGesture)
        backdropBlur.isAccessibilityElement = true
        backdropBlur.accessibilityLabel = NSLocalizedString("accessibility_close", comment: "Close overlay")
        backdropBlur.accessibilityTraits = .button
        backdropBlur.accessibilityIdentifier = "overlay.backdrop.dismiss"
    }

    private func setupSnapshot() {
        snapshot.frame = sourceFrame
        snapshot.transform = .identity
        view.addSubview(snapshot)
    }

    private func setupReactionBar() {
        view.addSubview(reactionBar)

        if isConversationFrozen {
            reactionBar.isHidden = true
            reactionBar.alpha = 0
        }

        // Measure the action list to determine available space
        let reactionBarHeight: CGFloat = 52
        let spacing: CGFloat = 8
        let safeTop = view.safeAreaInsets.top > 0 ? view.safeAreaInsets.top : 54

        // Default position: above the snapshot
        var reactionBarTopY = sourceFrame.minY - spacing - reactionBarHeight

        // If reaction bar would clip the top safe area, place it below the snapshot instead
        if reactionBarTopY < safeTop {
            reactionBarTopY = sourceFrame.maxY + spacing
        }

        reactionBar.frame = CGRect(
            x: 16,
            y: reactionBarTopY,
            width: view.bounds.width - 32,
            height: reactionBarHeight
        )
        // Store initial alpha for animation
        reactionBar.alpha = 0
    }

    private func setupDetailsRow() {
        let shouldShow = showDetails || !individualReactions.isEmpty
        guard shouldShow else {
            detailsRow.isHidden = true
            return
        }

        view.addSubview(detailsRow)
        detailsRow.configure(
            reactions: individualReactions,
            profiles: reactionProfiles,
            currentUserId: currentUserId
        )

        let detailsRowHeight: CGFloat = 100 // sticker (50) + spacing (4) + avatar (24) + padding (22)
        let spacing: CGFloat = 8

        // Position between reaction bar and snapshot
        let reactionBarIsAbove = reactionBar.frame.midY < sourceFrame.midY

        if reactionBarIsAbove {
            // Details row goes below reaction bar, above snapshot
            let detailsTopY = reactionBar.frame.maxY + spacing
            detailsRow.frame = CGRect(
                x: 16,
                y: detailsTopY,
                width: view.bounds.width - 32,
                height: detailsRowHeight
            )

            // Push snapshot down if it overlaps the details row
            if snapshot.frame.minY < detailsRow.frame.maxY + spacing {
                snapshot.frame.origin.y = detailsRow.frame.maxY + spacing
            }
        } else {
            // Reaction bar is below snapshot — details row goes above snapshot
            let detailsBottomY = sourceFrame.minY - spacing
            detailsRow.frame = CGRect(
                x: 16,
                y: detailsBottomY - detailsRowHeight,
                width: view.bounds.width - 32,
                height: detailsRowHeight
            )
        }

        detailsRow.alpha = 0
    }

    private func setupActionList() {
        view.addSubview(actionList)

        let spacing: CGFloat = 8
        let actionListWidth: CGFloat = 220
        let safeBottom = view.safeAreaInsets.bottom > 0 ? view.safeAreaInsets.bottom : 34

        // Measure intrinsic size
        let fittingSize = actionList.systemLayoutSizeFitting(
            CGSize(width: actionListWidth, height: UIView.layoutFittingCompressedSize.height),
            withHorizontalFittingPriority: .required,
            verticalFittingPriority: .fittingSizeLevel
        )

        // Default position: below the snapshot
        var actionListTopY = sourceFrame.maxY + spacing

        // If the reaction bar was placed below the snapshot (adaptive), put the action list above instead
        let reactionBarIsBelow = reactionBar.frame.minY > sourceFrame.midY
        if reactionBarIsBelow {
            actionListTopY = sourceFrame.minY - spacing - fittingSize.height
        }

        // Ensure it doesn't go off screen bottom
        let maxBottomY = view.bounds.height - safeBottom
        if actionListTopY + fittingSize.height > maxBottomY {
            actionListTopY = maxBottomY - fittingSize.height
        }

        // Align horizontally with the message bubble
        let actionListX: CGFloat = isFromCurrentUser
            ? sourceFrame.maxX - actionListWidth
            : sourceFrame.minX

        // Clamp to screen bounds
        let clampedX = max(16, min(actionListX, view.bounds.width - actionListWidth - 16))

        actionList.frame = CGRect(
            x: clampedX,
            y: actionListTopY,
            width: actionListWidth,
            height: fittingSize.height
        )
        // Store initial alpha for animation
        actionList.alpha = 0
    }

    // MARK: - Callbacks

    private func wireCallbacks() {
        reactionBar.onReact = { [weak self] emoji in
            self?.dismissOverlay { self?.onAction(.react(emoji)) }
        }
        reactionBar.onRemoveReaction = { [weak self] in
            self?.dismissOverlay { self?.onAction(.removeReaction) }
        }
        actionList.onAction = { [weak self] action in
            self?.dismissOverlay { self?.onAction(action) }
        }
        detailsRow.onRemoveReaction = { [weak self] _ in
            self?.dismissOverlay { self?.onAction(.removeReaction) }
        }
    }

    // MARK: - Animation

    private func performEntranceAnimation() {
        // Pre-animation state
        snapshot.transform = .identity
        let reactionBarTargetY = reactionBar.frame.origin.y
        let actionListTargetY = actionList.frame.origin.y
        let detailsRowTargetY = detailsRow.frame.origin.y
        let reactionBarIsAbove = reactionBar.frame.midY < sourceFrame.midY
        let snapshotTargetY = snapshot.frame.origin.y

        reactionBar.frame.origin.y += reactionBarIsAbove ? -10 : 10
        actionList.frame.origin.y += reactionBarIsAbove ? 10 : -10
        detailsRow.frame.origin.y += reactionBarIsAbove ? -10 : 10

        let animator = UIViewPropertyAnimator(
            duration: 0.3,
            dampingRatio: 0.85
        )

        animator.addAnimations {
            self.backdropBlur.effect = UIBlurEffect(style: .systemUltraThinMaterial)
            self.snapshot.transform = CGAffineTransform(scaleX: 1.05, y: 1.05)
            self.snapshot.frame.origin.y = snapshotTargetY
            self.reactionBar.alpha = 1
            self.reactionBar.frame.origin.y = reactionBarTargetY
            self.detailsRow.alpha = 1
            self.detailsRow.frame.origin.y = detailsRowTargetY
            self.actionList.alpha = 1
            self.actionList.frame.origin.y = actionListTargetY
        }

        animator.startAnimation()
    }

    private func dismissOverlay(completion: (() -> Void)? = nil) {
        view.endEditing(true)
        let reactionBarIsAbove = reactionBar.frame.midY < sourceFrame.midY

        let animator = UIViewPropertyAnimator(duration: 0.25, dampingRatio: 1.0)

        animator.addAnimations {
            self.backdropBlur.effect = nil
            self.snapshot.transform = .identity
            self.reactionBar.alpha = 0
            self.reactionBar.frame.origin.y += reactionBarIsAbove ? -10 : 10
            self.detailsRow.alpha = 0
            self.detailsRow.frame.origin.y += reactionBarIsAbove ? -10 : 10
            self.actionList.alpha = 0
            self.actionList.frame.origin.y += reactionBarIsAbove ? 10 : -10
        }

        animator.addCompletion { _ in
            self.dismiss(animated: false) {
                completion?()
            }
        }

        animator.startAnimation()
    }

    // MARK: - Actions

    @objc private func backdropTapped() {
        dismissOverlay()
    }
}
