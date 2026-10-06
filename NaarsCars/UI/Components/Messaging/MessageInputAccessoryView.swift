//
//  MessageInputAccessoryView.swift
//  NaarsCars
//
//  UIKit input accessory view for the conversation screen.
//  Replaces the SwiftUI MessageInputBar when used inside MessagesViewController
//  to enable interactive keyboard dismissal.
//

import UIKit

// MARK: - Delegate Protocol

protocol MessageInputDelegate: AnyObject {
    func inputBar(_ bar: MessageInputAccessoryView, didSendText text: String)
    func inputBar(_ bar: MessageInputAccessoryView, didSendEditedText text: String, messageId: UUID)
    func inputBarDidRequestImagePicker(_ bar: MessageInputAccessoryView)
    func inputBarDidRequestCamera(_ bar: MessageInputAccessoryView)
    func inputBar(_ bar: MessageInputAccessoryView, didRecordAudio url: URL, duration: Double)
    func inputBarDidCancelReply(_ bar: MessageInputAccessoryView)
    func inputBarDidCancelEdit(_ bar: MessageInputAccessoryView)
    func inputBarDidChangeTypingState(_ bar: MessageInputAccessoryView)
}

// MARK: - MessageInputAccessoryView

final class MessageInputAccessoryView: UIView {

    // MARK: Public API

    weak var delegate: MessageInputDelegate?
    let controller: InputBarController
    /// Called when the bar is attached to a window or laid out at a new size, so the hosting
    /// controller can keep the message list clear of the bar (see
    /// `MessagesViewController.updateComposerOverlapInset`).
    var onGeometryChange: (() -> Void)?

    func setReplyContext(_ context: ReplyContext) {
        controller.setReplyContext(context)
        showReplyBanner(name: context.senderName, preview: context.text)
        focusTextViewDeferred()
    }

    /// Reply and Edit raise the keyboard, as in iMessage. Both setters are called from
    /// `MessagesViewControllerRepresentable.updateUIViewController` (inside a SwiftUI update
    /// pass), so the focus change is deferred one run-loop turn. The text view lives in the
    /// docked inputAccessoryView, so the bar stays attached when it takes focus.
    /// True while the composer's text view holds keyboard focus.
    var isEditingText: Bool { textView.isFirstResponder }

    private func focusTextViewDeferred() {
        DispatchQueue.main.async { [weak self] in
            self?.textView.becomeFirstResponder()
        }
    }

    func clearReplyContext() {
        controller.cancelReply()
        hideContextBanner()
    }

    func setEditContext(text: String, messageId: UUID) {
        controller.startEditing(messageId: messageId, text: text)
        textView.text = text
        // Caret at the end of the existing text (UTF-16 length is the NSRange unit).
        textView.selectedRange = NSRange(location: (text as NSString).length, length: 0)
        placeholderLabel.isHidden = !text.isEmpty
        showEditBanner(text: text)
        updateSendButtonState()
        syncTextHeight()
        focusTextViewDeferred()
    }

    func clearEditContext() {
        controller.cancelEditing()
        textView.text = ""
        placeholderLabel.isHidden = false
        hideContextBanner()
        updateSendButtonState()
        syncTextHeight()
    }

    func setImagePreview(_ image: UIImage?) {
        if let image {
            imagePreviewView.image = image
            imagePreviewContainer.isHidden = false
            controller.setImage(image)
        } else {
            imagePreviewView.image = nil
            imagePreviewContainer.isHidden = true
            controller.clearAttachment()
        }
        updateSendButtonState()
        invalidateIntrinsicContentSize()
    }

    /// Puts a draft back after its send was refused before a bubble existed (see
    /// `InputBarController.restoreDraft`). `sendTapped` has already emptied the bar; nothing
    /// the user has typed or attached since is overwritten.
    func restoreDraft(text: String, image: UIImage?) {
        guard !controller.isEditing else { return }
        controller.restoreDraft(text: text, image: image)
        if (textView.text ?? "").isEmpty, !controller.currentText.isEmpty {
            textView.text = controller.currentText
            // Caret at the end of the restored text (UTF-16 length is the NSRange unit).
            textView.selectedRange = NSRange(location: (controller.currentText as NSString).length, length: 0)
        }
        if imagePreviewContainer.isHidden, let preview = controller.attachmentState.previewImage {
            imagePreviewView.image = preview
            imagePreviewContainer.isHidden = false
        }
        updateSendButtonState()
        syncTextHeight()
    }

    // MARK: Private State

    // Text view height tracking
    private let minTextHeight: CGFloat = 36
    private let maxTextLines: Int = 5
    private var maxTextHeight: CGFloat = 120

    // MARK: Subviews

    private let blurView: UIVisualEffectView = {
        let blur = UIBlurEffect(style: .systemMaterial)
        let v = UIVisualEffectView(effect: blur)
        v.translatesAutoresizingMaskIntoConstraints = false
        return v
    }()

    private let separator: UIView = {
        let v = UIView()
        v.backgroundColor = .separator
        v.translatesAutoresizingMaskIntoConstraints = false
        return v
    }()

    // Context banner (reply / edit)
    private let contextBanner: UIView = {
        let v = UIView()
        v.translatesAutoresizingMaskIntoConstraints = false
        v.isHidden = true
        v.clipsToBounds = true
        return v
    }()

    private let bannerAccentBar: UIView = {
        let v = UIView()
        v.backgroundColor = .naarsPrimary
        v.layer.cornerRadius = 1.5
        v.translatesAutoresizingMaskIntoConstraints = false
        return v
    }()

    private let bannerTitleLabel: UILabel = {
        let l = UILabel()
        l.font = .preferredFont(forTextStyle: .footnote).withWeight(.semibold)
        l.textColor = .naarsPrimary
        l.translatesAutoresizingMaskIntoConstraints = false
        return l
    }()

    private let bannerPreviewLabel: UILabel = {
        let l = UILabel()
        l.font = .preferredFont(forTextStyle: .footnote)
        l.textColor = .secondaryLabel
        // One line: the banner is a fixed 52 pt row, so a second line was drawn half clipped.
        l.numberOfLines = 1
        l.lineBreakMode = .byTruncatingTail
        l.translatesAutoresizingMaskIntoConstraints = false
        return l
    }()

    private lazy var bannerCancelButton: UIButton = {
        let b = UIButton(type: .system)
        let config = UIImage.SymbolConfiguration(textStyle: .title3)
        b.setImage(UIImage(systemName: "xmark.circle.fill", withConfiguration: config), for: .normal)
        b.tintColor = .secondaryLabel
        b.accessibilityLabel = "common_cancel".localized
        b.translatesAutoresizingMaskIntoConstraints = false
        b.addTarget(self, action: #selector(bannerCancelTapped), for: .touchUpInside)
        return b
    }()

    // Recording banner
    private let recordingBanner: UIView = {
        let v = UIView()
        v.translatesAutoresizingMaskIntoConstraints = false
        v.isHidden = true
        v.clipsToBounds = true
        return v
    }()

    private let recordingDot: UIView = {
        let v = UIView()
        v.backgroundColor = .systemRed
        v.layer.cornerRadius = 5
        v.translatesAutoresizingMaskIntoConstraints = false
        return v
    }()

    private let recordingLabel: UILabel = {
        let l = UILabel()
        l.text = "messaging_recording".localized
        l.font = .preferredFont(forTextStyle: .subheadline).withWeight(.medium)
        l.textColor = .label
        // The banner is one fixed-height row: at large text sizes the label gives way to the
        // timer and buttons instead of running under them.
        l.adjustsFontSizeToFitWidth = true
        l.minimumScaleFactor = 0.6
        l.setContentCompressionResistancePriority(.defaultLow, for: .horizontal)
        l.translatesAutoresizingMaskIntoConstraints = false
        return l
    }()

    private let recordingDurationLabel: UILabel = {
        let l = UILabel()
        l.text = "0:00"
        l.font = .monospacedSystemFont(ofSize: 14, weight: .semibold)
        l.textColor = .systemRed
        l.translatesAutoresizingMaskIntoConstraints = false
        return l
    }()

    private lazy var recordingCancelButton: UIButton = {
        let b = UIButton(type: .system)
        b.setTitle("common_cancel".localized, for: .normal)
        b.titleLabel?.font = .preferredFont(forTextStyle: .subheadline).withWeight(.medium)
        b.tintColor = .secondaryLabel
        b.translatesAutoresizingMaskIntoConstraints = false
        b.addTarget(self, action: #selector(cancelRecordingTapped), for: .touchUpInside)
        return b
    }()

    private lazy var recordingSendButton: UIButton = {
        let b = UIButton(type: .system)
        let config = UIImage.SymbolConfiguration(textStyle: .title2)
        b.setImage(UIImage(systemName: "arrow.up.circle.fill", withConfiguration: config), for: .normal)
        b.tintColor = .naarsPrimary
        b.accessibilityLabel = "messaging_send".localized
        b.translatesAutoresizingMaskIntoConstraints = false
        b.addTarget(self, action: #selector(stopAndSendRecording), for: .touchUpInside)
        return b
    }()

    // Image preview
    private let imagePreviewContainer: UIView = {
        let v = UIView()
        v.translatesAutoresizingMaskIntoConstraints = false
        v.isHidden = true
        return v
    }()

    private let imagePreviewView: UIImageView = {
        let iv = UIImageView()
        iv.contentMode = .scaleAspectFit
        iv.layer.cornerRadius = 8
        iv.clipsToBounds = true
        iv.translatesAutoresizingMaskIntoConstraints = false
        return iv
    }()

    private lazy var imagePreviewDismiss: UIButton = {
        let b = UIButton(type: .system)
        let config = UIImage.SymbolConfiguration(pointSize: 18, weight: .medium)
        b.setImage(UIImage(systemName: "xmark.circle.fill", withConfiguration: config), for: .normal)
        b.tintColor = .systemGray
        b.accessibilityLabel = "messaging_remove_photo_accessibility".localized
        b.translatesAutoresizingMaskIntoConstraints = false
        b.addTarget(self, action: #selector(clearImagePreview), for: .touchUpInside)
        return b
    }()

    // Input row
    private let inputRow: UIView = {
        let v = UIView()
        v.translatesAutoresizingMaskIntoConstraints = false
        return v
    }()

    private lazy var plusButton: UIButton = {
        let b = UIButton(type: .system)
        // Neutral grey circle with a label-coloured plus, as in iMessage; the brand colour is
        // reserved for the send button.
        let config = UIImage.SymbolConfiguration(paletteColors: [.label, .tertiarySystemFill])
            .applying(UIImage.SymbolConfiguration(textStyle: .title2))
        b.setImage(UIImage(systemName: "plus.circle.fill", withConfiguration: config), for: .normal)
        b.showsMenuAsPrimaryAction = true
        b.menu = buildPlusMenu()
        b.translatesAutoresizingMaskIntoConstraints = false
        b.accessibilityLabel = "messaging_menu_add".localized
        return b
    }()

    private let textViewContainer: UIView = {
        let v = UIView()
        v.layer.cornerRadius = 20
        v.layer.borderWidth = 1
        v.layer.borderColor = UIColor.quaternaryLabel.cgColor
        v.clipsToBounds = true
        v.translatesAutoresizingMaskIntoConstraints = false
        return v
    }()

    private lazy var textView: UITextView = {
        let tv = UITextView()
        tv.font = .preferredFont(forTextStyle: .body)
        // Trailing inset keeps text clear of the send button in the capsule's corner.
        tv.textContainerInset = UIEdgeInsets(top: 8, left: 8, bottom: 8, right: 36)
        tv.isScrollEnabled = false
        tv.backgroundColor = .clear
        tv.delegate = self
        tv.translatesAutoresizingMaskIntoConstraints = false
        tv.accessibilityIdentifier = "message.input"
        tv.accessibilityLabel = "messaging_input_label".localized
        return tv
    }()

    private let placeholderLabel: UILabel = {
        let l = UILabel()
        l.text = "messaging_placeholder".localized
        l.font = .preferredFont(forTextStyle: .body)
        l.textColor = .placeholderText
        l.translatesAutoresizingMaskIntoConstraints = false
        return l
    }()

    private lazy var sendButton: UIButton = {
        let b = UIButton(type: .system)
        // iMessage: the send button lives inside the text capsule and exists only while there
        // is something to send (it used to sit outside the field, grey when disabled). A white
        // arrow on the brand colour, at a fixed size so it always fits the one-line capsule.
        let config = UIImage.SymbolConfiguration(pointSize: 22, weight: .regular)
            .applying(UIImage.SymbolConfiguration(paletteColors: [.white, .naarsPrimary]))
        b.setImage(UIImage(systemName: "arrow.up.circle.fill", withConfiguration: config), for: .normal)
        b.isEnabled = false
        b.isHidden = true
        b.translatesAutoresizingMaskIntoConstraints = false
        b.addTarget(self, action: #selector(sendTapped), for: .touchUpInside)
        b.accessibilityIdentifier = "message.send"
        b.accessibilityLabel = "messaging_send".localized
        return b
    }()

    /// Characters left, shown above the send button once the text is near the length limit
    /// (red and negative when over it, with the send button disabled). The limit used to be
    /// discovered only by sending: the message was refused and the draft was gone.
    private let characterCountLabel: UILabel = {
        let l = UILabel()
        l.font = .monospacedDigitSystemFont(
            ofSize: UIFont.preferredFont(forTextStyle: .caption2).pointSize,
            weight: .medium
        )
        l.textAlignment = .center
        // The column beside the text is 36 pt wide; large text sizes shrink to fit it.
        l.adjustsFontSizeToFitWidth = true
        l.minimumScaleFactor = 0.5
        l.isHidden = true
        l.translatesAutoresizingMaskIntoConstraints = false
        l.accessibilityIdentifier = "message.characterCount"
        return l
    }()

    // Constraints
    private var textViewHeightConstraint: NSLayoutConstraint!
    private var contextBannerHeightConstraint: NSLayoutConstraint!
    private var recordingBannerHeightConstraint: NSLayoutConstraint!

    // MARK: Init

    init(controller: InputBarController) {
        self.controller = controller
        super.init(frame: .zero)
        autoresizingMask = .flexibleHeight
        setupViews()
        computeMaxTextHeight()
        observeRecordingState()
    }

    required init?(coder: NSCoder) { fatalError() }

    // MARK: Intrinsic Content Size

    override var intrinsicContentSize: CGSize {
        CGSize(width: UIView.noIntrinsicMetric, height: calculateHeight())
    }

    private func calculateHeight() -> CGFloat {
        var height: CGFloat = 0

        // Separator (hairline)
        height += 1.0 / UIScreen.main.scale

        // Context banner
        if !contextBanner.isHidden {
            height += contextBannerHeight()
        }

        // Recording banner
        if !recordingBanner.isHidden {
            height += recordingBannerHeight()
        }

        // Image preview
        if !imagePreviewContainer.isHidden {
            height += 108 + 8 // 100pt image + 8pt padding
        }

        // Input row (text view + padding)
        let textHeight = clampedTextHeight()
        height += textHeight + 16 // 8pt top + 8pt bottom padding

        return height
    }

    private func clampedTextHeight() -> CGFloat {
        let fittingSize = textView.sizeThatFits(CGSize(width: textView.frame.width > 0 ? textView.frame.width : 200, height: .greatestFiniteMagnitude))
        return min(max(fittingSize.height, minTextHeight), maxTextHeight)
    }

    private func contextBannerHeight() -> CGFloat { 52 }
    private func recordingBannerHeight() -> CGFloat { 48 }

    // MARK: Layout

    override func didMoveToWindow() {
        super.didMoveToWindow()
        onGeometryChange?()
    }

    override func layoutSubviews() {
        super.layoutSubviews()
        onGeometryChange?()

        // Update border color on trait change
        textViewContainer.layer.borderColor = UIColor.quaternaryLabel.cgColor

        // Update text scroll state
        let textHeight = clampedTextHeight()
        textView.isScrollEnabled = textHeight >= maxTextHeight
        textViewHeightConstraint.constant = textHeight

        // Self-heal the placeholder and send button if the text changed without a delegate
        // callback (programmatic resets, input-session replays).
        updateSendButtonState()
    }

    override func traitCollectionDidChange(_ previousTraitCollection: UITraitCollection?) {
        super.traitCollectionDidChange(previousTraitCollection)
        textViewContainer.layer.borderColor = UIColor.quaternaryLabel.cgColor
    }

    // MARK: Setup

    private func setupViews() {
        // Background blur
        addSubview(blurView)
        NSLayoutConstraint.activate([
            blurView.topAnchor.constraint(equalTo: topAnchor),
            blurView.leadingAnchor.constraint(equalTo: leadingAnchor),
            blurView.trailingAnchor.constraint(equalTo: trailingAnchor),
            blurView.bottomAnchor.constraint(equalTo: bottomAnchor),
        ])

        // Main stack container
        let stack = UIStackView()
        stack.axis = .vertical
        stack.spacing = 0
        stack.translatesAutoresizingMaskIntoConstraints = false
        addSubview(stack)
        NSLayoutConstraint.activate([
            stack.topAnchor.constraint(equalTo: topAnchor),
            stack.leadingAnchor.constraint(equalTo: leadingAnchor),
            stack.trailingAnchor.constraint(equalTo: trailingAnchor),
            stack.bottomAnchor.constraint(equalTo: safeAreaLayoutGuide.bottomAnchor),
        ])

        // 1. Separator
        stack.addArrangedSubview(separator)
        separator.heightAnchor.constraint(equalToConstant: 1.0 / UIScreen.main.scale).isActive = true

        // 2. Context banner
        setupContextBanner()
        stack.addArrangedSubview(contextBanner)
        contextBannerHeightConstraint = contextBanner.heightAnchor.constraint(equalToConstant: 0)
        contextBannerHeightConstraint.isActive = true

        // 3. Recording banner
        setupRecordingBanner()
        stack.addArrangedSubview(recordingBanner)
        recordingBannerHeightConstraint = recordingBanner.heightAnchor.constraint(equalToConstant: 0)
        recordingBannerHeightConstraint.isActive = true

        // 4. Image preview
        setupImagePreview()
        stack.addArrangedSubview(imagePreviewContainer)

        // 5. Input row
        setupInputRow()
        stack.addArrangedSubview(inputRow)
    }

    private func setupContextBanner() {
        contextBanner.addSubview(bannerAccentBar)
        contextBanner.addSubview(bannerTitleLabel)
        contextBanner.addSubview(bannerPreviewLabel)
        contextBanner.addSubview(bannerCancelButton)

        // Vertical padding constraints use .defaultHigh so they yield to
        // the height=0 constraint when the banner is hidden, avoiding
        // "Unable to simultaneously satisfy constraints" warnings.
        let accentTop = bannerAccentBar.topAnchor.constraint(equalTo: contextBanner.topAnchor, constant: 10)
        accentTop.priority = .defaultHigh
        let accentBottom = bannerAccentBar.bottomAnchor.constraint(equalTo: contextBanner.bottomAnchor, constant: -10)
        accentBottom.priority = .defaultHigh
        let titleTop = bannerTitleLabel.topAnchor.constraint(equalTo: contextBanner.topAnchor, constant: 10)
        titleTop.priority = .defaultHigh

        NSLayoutConstraint.activate([
            bannerAccentBar.leadingAnchor.constraint(equalTo: contextBanner.leadingAnchor, constant: 12),
            accentTop,
            accentBottom,
            bannerAccentBar.widthAnchor.constraint(equalToConstant: 3),

            bannerTitleLabel.leadingAnchor.constraint(equalTo: bannerAccentBar.trailingAnchor, constant: 10),
            titleTop,
            bannerTitleLabel.trailingAnchor.constraint(lessThanOrEqualTo: bannerCancelButton.leadingAnchor, constant: -8),

            bannerPreviewLabel.leadingAnchor.constraint(equalTo: bannerTitleLabel.leadingAnchor),
            bannerPreviewLabel.topAnchor.constraint(equalTo: bannerTitleLabel.bottomAnchor, constant: 2),
            bannerPreviewLabel.trailingAnchor.constraint(lessThanOrEqualTo: bannerCancelButton.leadingAnchor, constant: -8),

            bannerCancelButton.trailingAnchor.constraint(equalTo: contextBanner.trailingAnchor, constant: -12),
            bannerCancelButton.centerYAnchor.constraint(equalTo: contextBanner.centerYAnchor),
            bannerCancelButton.widthAnchor.constraint(equalToConstant: 28),
            bannerCancelButton.heightAnchor.constraint(equalToConstant: 28),
        ])
    }

    private func setupRecordingBanner() {
        recordingBanner.addSubview(recordingDot)
        recordingBanner.addSubview(recordingLabel)
        recordingBanner.addSubview(recordingDurationLabel)
        recordingBanner.addSubview(recordingCancelButton)
        recordingBanner.addSubview(recordingSendButton)

        NSLayoutConstraint.activate([
            recordingDot.leadingAnchor.constraint(equalTo: recordingBanner.leadingAnchor, constant: 16),
            recordingDot.centerYAnchor.constraint(equalTo: recordingBanner.centerYAnchor),
            recordingDot.widthAnchor.constraint(equalToConstant: 10),
            recordingDot.heightAnchor.constraint(equalToConstant: 10),

            recordingLabel.leadingAnchor.constraint(equalTo: recordingDot.trailingAnchor, constant: 8),
            recordingLabel.centerYAnchor.constraint(equalTo: recordingBanner.centerYAnchor),
            recordingLabel.trailingAnchor.constraint(lessThanOrEqualTo: recordingDurationLabel.leadingAnchor, constant: -8),

            recordingSendButton.trailingAnchor.constraint(equalTo: recordingBanner.trailingAnchor, constant: -12),
            recordingSendButton.centerYAnchor.constraint(equalTo: recordingBanner.centerYAnchor),

            recordingCancelButton.trailingAnchor.constraint(equalTo: recordingSendButton.leadingAnchor, constant: -8),
            recordingCancelButton.centerYAnchor.constraint(equalTo: recordingBanner.centerYAnchor),

            recordingDurationLabel.trailingAnchor.constraint(equalTo: recordingCancelButton.leadingAnchor, constant: -12),
            recordingDurationLabel.centerYAnchor.constraint(equalTo: recordingBanner.centerYAnchor),
        ])
    }

    private func setupImagePreview() {
        imagePreviewContainer.addSubview(imagePreviewView)
        imagePreviewContainer.addSubview(imagePreviewDismiss)

        let heightConstraint = imagePreviewContainer.heightAnchor.constraint(equalToConstant: 108)
        heightConstraint.priority = .defaultHigh
        heightConstraint.isActive = true

        NSLayoutConstraint.activate([
            imagePreviewView.leadingAnchor.constraint(equalTo: imagePreviewContainer.leadingAnchor, constant: 16),
            imagePreviewView.topAnchor.constraint(equalTo: imagePreviewContainer.topAnchor, constant: 8),
            imagePreviewView.heightAnchor.constraint(equalToConstant: 100),
            imagePreviewView.widthAnchor.constraint(lessThanOrEqualToConstant: 100),

            imagePreviewDismiss.leadingAnchor.constraint(equalTo: imagePreviewView.trailingAnchor, constant: -12),
            imagePreviewDismiss.topAnchor.constraint(equalTo: imagePreviewView.topAnchor, constant: -4),
        ])
    }

    private func setupInputRow() {
        inputRow.addSubview(plusButton)
        inputRow.addSubview(textViewContainer)

        textViewContainer.addSubview(textView)
        textViewContainer.addSubview(placeholderLabel)
        // Last, so it sits above the full-size text view and receives its taps.
        textViewContainer.addSubview(sendButton)
        textViewContainer.addSubview(characterCountLabel)

        textViewHeightConstraint = textView.heightAnchor.constraint(equalToConstant: minTextHeight)
        textViewHeightConstraint.priority = .defaultHigh

        NSLayoutConstraint.activate([
            // Plus button
            plusButton.leadingAnchor.constraint(equalTo: inputRow.leadingAnchor, constant: 12),
            plusButton.bottomAnchor.constraint(equalTo: inputRow.bottomAnchor, constant: -8),
            plusButton.widthAnchor.constraint(equalToConstant: 32),
            plusButton.heightAnchor.constraint(equalToConstant: 32),

            // Text view container
            textViewContainer.leadingAnchor.constraint(equalTo: plusButton.trailingAnchor, constant: 8),
            textViewContainer.topAnchor.constraint(equalTo: inputRow.topAnchor, constant: 8),
            textViewContainer.bottomAnchor.constraint(equalTo: inputRow.bottomAnchor, constant: -8),
            textViewContainer.trailingAnchor.constraint(equalTo: inputRow.trailingAnchor, constant: -12),

            // Text view inside container
            textView.topAnchor.constraint(equalTo: textViewContainer.topAnchor),
            textView.leadingAnchor.constraint(equalTo: textViewContainer.leadingAnchor),
            textView.trailingAnchor.constraint(equalTo: textViewContainer.trailingAnchor),
            textView.bottomAnchor.constraint(equalTo: textViewContainer.bottomAnchor),
            textViewHeightConstraint,

            // Placeholder
            placeholderLabel.leadingAnchor.constraint(equalTo: textView.leadingAnchor, constant: 13),
            placeholderLabel.centerYAnchor.constraint(equalTo: textView.centerYAnchor),
            placeholderLabel.trailingAnchor.constraint(lessThanOrEqualTo: textViewContainer.trailingAnchor, constant: -40),

            // Send button: bottom-trailing corner of the capsule, 36-pt tap target
            sendButton.trailingAnchor.constraint(equalTo: textViewContainer.trailingAnchor),
            sendButton.bottomAnchor.constraint(equalTo: textViewContainer.bottomAnchor),
            sendButton.widthAnchor.constraint(equalToConstant: 36),
            sendButton.heightAnchor.constraint(equalToConstant: 36),

            // Character counter: in the same trailing column, just above the send button. It
            // only shows near the limit, when the text view is already at its full height.
            characterCountLabel.centerXAnchor.constraint(equalTo: sendButton.centerXAnchor),
            characterCountLabel.bottomAnchor.constraint(equalTo: sendButton.topAnchor),
            characterCountLabel.widthAnchor.constraint(lessThanOrEqualToConstant: 34),
        ])
    }

    private func computeMaxTextHeight() {
        let font = textView.font ?? .preferredFont(forTextStyle: .body)
        let lineHeight = font.lineHeight
        let insets = textView.textContainerInset
        maxTextHeight = lineHeight * CGFloat(maxTextLines) + insets.top + insets.bottom
    }

    // MARK: Plus Menu

    private func buildPlusMenu() -> UIMenu {
        let camera = UIAction(
            title: "photo_source_camera".localized,
            image: UIImage(systemName: "camera.fill")
        ) { [weak self] _ in
            self?.controller.onCameraRequested?()
        }

        let photos = UIAction(
            title: "messaging_menu_photo".localized,
            image: UIImage(systemName: "photo.on.rectangle.angled")
        ) { [weak self] _ in
            self?.controller.onImagePickerRequested?()
        }

        let voiceNote = UIAction(
            title: "messaging_menu_voice_note".localized,
            image: UIImage(systemName: "mic.fill")
        ) { [weak self] _ in
            self?.toggleRecording()
        }

        let location = UIAction(
            title: "messaging_menu_location".localized,
            image: UIImage(systemName: "location.fill")
        ) { [weak self] _ in
            self?.controller.onLocationPickerRequested?()
        }

        return UIMenu(children: [camera, photos, voiceNote, location])
    }

    // MARK: Send

    @objc private func sendTapped() {
        // Over the length limit the send would be refused: keep the draft in the field. The
        // button is disabled in that state; this is the backstop.
        guard InputBarController.remainingCharacters(for: textView.text ?? "") >= 0 else { return }

        // Spring scale animation
        UIView.animate(withDuration: 0.15, delay: 0, usingSpringWithDamping: 0.5, initialSpringVelocity: 0, options: []) {
            self.sendButton.transform = CGAffineTransform(scaleX: 0.8, y: 0.8)
        } completion: { _ in
            UIView.animate(withDuration: 0.2, delay: 0, usingSpringWithDamping: 0.6, initialSpringVelocity: 0, options: []) {
                self.sendButton.transform = .identity
            }
        }

        controller.send()

        // Sync UIKit state after controller reset
        textView.text = ""
        placeholderLabel.isHidden = false
        imagePreviewView.image = nil
        imagePreviewContainer.isHidden = true
        hideContextBanner()
        updateSendButtonState()
        syncTextHeight()
    }

    /// Re-measures the text view after its text was set in code. `textViewDidChange` is not called
    /// for programmatic changes, so the height constraint kept the old value: after sending a
    /// three-line message the empty composer stayed three lines tall until the next keystroke.
    private func syncTextHeight() {
        let newHeight = clampedTextHeight()
        if textViewHeightConstraint.constant != newHeight {
            textViewHeightConstraint.constant = newHeight
        }
        textView.isScrollEnabled = newHeight >= maxTextHeight
        invalidateIntrinsicContentSize()
        setNeedsLayout()
        superview?.layoutIfNeeded()
    }

    // MARK: Context Banners

    private func showReplyBanner(name: String, preview: String) {
        bannerTitleLabel.text = "\("messaging_replying_to".localized) \(name)"
        bannerPreviewLabel.text = preview
        showBannerAnimated(contextBanner, heightConstraint: contextBannerHeightConstraint, height: contextBannerHeight())
    }

    private func showEditBanner(text: String) {
        bannerTitleLabel.text = "messaging_editing_message".localized
        bannerPreviewLabel.text = text
        showBannerAnimated(contextBanner, heightConstraint: contextBannerHeightConstraint, height: contextBannerHeight())
    }

    private func hideContextBanner() {
        hideBannerAnimated(contextBanner, heightConstraint: contextBannerHeightConstraint)
    }

    @objc private func bannerCancelTapped() {
        if case .editing = controller.mode {
            delegate?.inputBarDidCancelEdit(self)
            clearEditContext()
        } else if case .replying = controller.mode {
            delegate?.inputBarDidCancelReply(self)
            clearReplyContext()
        }
    }

    // MARK: Banner Animation Helpers

    private func showBannerAnimated(_ banner: UIView, heightConstraint: NSLayoutConstraint, height: CGFloat) {
        banner.alpha = 0
        banner.isHidden = false
        heightConstraint.constant = height
        UIView.animate(withDuration: 0.25, delay: 0, options: .curveEaseOut) {
            banner.alpha = 1
            self.superview?.layoutIfNeeded()
        }
        invalidateIntrinsicContentSize()
    }

    private func hideBannerAnimated(_ banner: UIView, heightConstraint: NSLayoutConstraint) {
        UIView.animate(withDuration: 0.2, delay: 0, options: .curveEaseOut) {
            banner.alpha = 0
            heightConstraint.constant = 0
            self.superview?.layoutIfNeeded()
        } completion: { _ in
            banner.isHidden = true
        }
        invalidateIntrinsicContentSize()
    }

    // MARK: Image Preview

    @objc private func clearImagePreview() {
        setImagePreview(nil)
    }

    // MARK: Audio Recording

    private func toggleRecording() {
        if controller.isRecording {
            controller.stopRecording()
        } else {
            controller.startRecording()
        }
    }

    @objc private func stopAndSendRecording() {
        controller.stopRecording()
    }

    @objc private func cancelRecordingTapped() {
        controller.cancelRecording()
    }

    /// Recording state lives in the `@Observable` `InputBarController`. Nothing in this bar read
    /// it, so the banner below (pulsing dot, timer, Cancel, send) was never shown: a voice note
    /// started from the "+" menu recorded with no feedback and could only be stopped by opening
    /// the menu again. Same re-registering pattern as `MessageThreadViewController`.
    private func observeRecordingState() {
        withObservationTracking {
            _ = controller.isRecording
            _ = controller.recordingDuration
        } onChange: { [weak self] in
            Task { @MainActor [weak self] in
                guard let self else { return }
                self.applyRecordingState()
                self.observeRecordingState()
            }
        }
    }

    private func applyRecordingState() {
        if controller.isRecording {
            showRecordingBanner()
        } else {
            hideRecordingBanner()
        }
        recordingDurationLabel.text = formatDuration(controller.recordingDuration)
    }

    private func showRecordingBanner() {
        guard recordingBanner.isHidden else { return }
        showBannerAnimated(recordingBanner, heightConstraint: recordingBannerHeightConstraint, height: recordingBannerHeight())
        inputRow.alpha = 0.3
        inputRow.isUserInteractionEnabled = false
        startDotPulsing()
        let generator = UIImpactFeedbackGenerator(style: .medium)
        generator.impactOccurred()
    }

    private func hideRecordingBanner() {
        guard !recordingBanner.isHidden else { return }
        hideBannerAnimated(recordingBanner, heightConstraint: recordingBannerHeightConstraint)
        inputRow.alpha = 1
        inputRow.isUserInteractionEnabled = true
        stopDotPulsing()
    }

    private func startDotPulsing() {
        UIView.animate(withDuration: 0.5, delay: 0, options: [.autoreverse, .repeat, .curveEaseInOut]) {
            self.recordingDot.alpha = 0.3
        }
    }

    private func stopDotPulsing() {
        recordingDot.layer.removeAllAnimations()
        recordingDot.alpha = 1.0
    }

    /// "0:07". The recorder publishes its duration once a second, so tenths would never move.
    private func formatDuration(_ seconds: TimeInterval) -> String {
        let total = max(0, Int(seconds))
        return String(format: "%d:%02d", total / 60, total % 60)
    }

    // MARK: - Send Button State

    private func updateSendButtonState() {
        // Keep the placeholder tied to the text at every point that re-evaluates the field.
        // Setting it separately at each call site let it show through text that arrived
        // while a send was resetting the field (hardware-keyboard input racing the tap).
        placeholderLabel.isHidden = !(textView.text ?? "").isEmpty
        let hasText = !(textView.text ?? "").trimmingCharacters(in: .whitespacesAndNewlines).isEmpty
        let hasImage = !imagePreviewContainer.isHidden
        let hasContent = hasText || hasImage
        // Over the length limit the button stays visible but disabled, and the counter says
        // why: sending would be refused and the draft lost.
        let remaining = InputBarController.remainingCharacters(for: textView.text ?? "")
        sendButton.isEnabled = hasContent && remaining >= 0
        sendButton.isHidden = !hasContent

        let showsCount = remaining <= InputBarController.characterCountThreshold
        characterCountLabel.isHidden = !showsCount
        if showsCount {
            characterCountLabel.text = "\(remaining)"
            characterCountLabel.textColor = remaining < 0 ? .systemRed : .secondaryLabel
            characterCountLabel.accessibilityLabel = InputBarController.characterCountAccessibilityText(remaining: remaining)
        }
    }

    // MARK: Cleanup

    func tearDown() {
        if controller.isRecording {
            controller.cancelRecording()
        }
    }
}

// MARK: - Microphone access

extension UIViewController {
    /// Explains a denied microphone permission and offers the app's page in Settings.
    func presentMicrophoneAccessAlert() {
        let alert = UIAlertController(
            title: "messaging_microphone_access_title".localized,
            message: "messaging_microphone_access_message".localized,
            preferredStyle: .alert
        )
        alert.addAction(UIAlertAction(title: "common_cancel".localized, style: .cancel))
        alert.addAction(UIAlertAction(title: "messaging_open_settings".localized, style: .default) { _ in
            guard let url = URL(string: UIApplication.openSettingsURLString) else { return }
            UIApplication.shared.open(url)
        })
        present(alert, animated: true)
    }
}

// MARK: - UITextViewDelegate

extension MessageInputAccessoryView: UITextViewDelegate {

    func textViewDidChange(_ textView: UITextView) {
        placeholderLabel.isHidden = !textView.text.isEmpty
        updateSendButtonState()

        // Recalculate height
        let newHeight = clampedTextHeight()
        if textViewHeightConstraint.constant != newHeight {
            textViewHeightConstraint.constant = newHeight
            textView.isScrollEnabled = newHeight >= maxTextHeight
            invalidateIntrinsicContentSize()
            superview?.layoutIfNeeded()
        }

        controller.updateText(textView.text)
    }
}

// MARK: - UIFont Weight Helper

private extension UIFont {
    func withWeight(_ weight: UIFont.Weight) -> UIFont {
        let descriptor = fontDescriptor.addingAttributes([
            .traits: [UIFontDescriptor.TraitKey.weight: weight]
        ])
        return UIFont(descriptor: descriptor, size: pointSize)
    }
}
