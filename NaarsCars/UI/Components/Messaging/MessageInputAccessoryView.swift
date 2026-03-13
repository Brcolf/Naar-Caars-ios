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

    func setReplyContext(_ context: ReplyContext) {
        controller.setReplyContext(context)
        showReplyBanner(name: context.senderName, preview: context.text)
    }

    func clearReplyContext() {
        controller.cancelReply()
        hideContextBanner()
    }

    func setEditContext(text: String, messageId: UUID) {
        controller.startEditing(messageId: messageId, text: text)
        textView.text = text
        placeholderLabel.isHidden = !text.isEmpty
        showEditBanner(text: text)
        updateSendButtonState()
        invalidateIntrinsicContentSize()
    }

    func clearEditContext() {
        controller.cancelEditing()
        textView.text = ""
        placeholderLabel.isHidden = false
        hideContextBanner()
        updateSendButtonState()
        invalidateIntrinsicContentSize()
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
        l.numberOfLines = 2
        l.translatesAutoresizingMaskIntoConstraints = false
        return l
    }()

    private lazy var bannerCancelButton: UIButton = {
        let b = UIButton(type: .system)
        let config = UIImage.SymbolConfiguration(textStyle: .title3)
        b.setImage(UIImage(systemName: "xmark.circle.fill", withConfiguration: config), for: .normal)
        b.tintColor = .secondaryLabel
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
        l.translatesAutoresizingMaskIntoConstraints = false
        return l
    }()

    private let recordingDurationLabel: UILabel = {
        let l = UILabel()
        l.text = "0:00.0"
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
        let config = UIImage.SymbolConfiguration(textStyle: .title2)
        b.setImage(UIImage(systemName: "plus.circle.fill", withConfiguration: config), for: .normal)
        b.tintColor = .naarsPrimary
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
        tv.textContainerInset = UIEdgeInsets(top: 8, left: 8, bottom: 8, right: 8)
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
        let config = UIImage.SymbolConfiguration(textStyle: .title2)
        b.setImage(UIImage(systemName: "arrow.up.circle.fill", withConfiguration: config), for: .normal)
        b.tintColor = .systemGray
        b.isEnabled = false
        b.translatesAutoresizingMaskIntoConstraints = false
        b.addTarget(self, action: #selector(sendTapped), for: .touchUpInside)
        b.accessibilityIdentifier = "message.send"
        b.accessibilityLabel = "messaging_send".localized
        return b
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

    override func layoutSubviews() {
        super.layoutSubviews()

        // Update border color on trait change
        textViewContainer.layer.borderColor = UIColor.quaternaryLabel.cgColor

        // Update text scroll state
        let textHeight = clampedTextHeight()
        textView.isScrollEnabled = textHeight >= maxTextHeight
        textViewHeightConstraint.constant = textHeight
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
        inputRow.addSubview(sendButton)

        textViewContainer.addSubview(textView)
        textViewContainer.addSubview(placeholderLabel)

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
            textViewContainer.trailingAnchor.constraint(equalTo: sendButton.leadingAnchor, constant: -8),

            // Text view inside container
            textView.topAnchor.constraint(equalTo: textViewContainer.topAnchor),
            textView.leadingAnchor.constraint(equalTo: textViewContainer.leadingAnchor),
            textView.trailingAnchor.constraint(equalTo: textViewContainer.trailingAnchor),
            textView.bottomAnchor.constraint(equalTo: textViewContainer.bottomAnchor),
            textViewHeightConstraint,

            // Placeholder
            placeholderLabel.leadingAnchor.constraint(equalTo: textView.leadingAnchor, constant: 13),
            placeholderLabel.centerYAnchor.constraint(equalTo: textView.centerYAnchor),

            // Send button
            sendButton.trailingAnchor.constraint(equalTo: inputRow.trailingAnchor, constant: -12),
            sendButton.bottomAnchor.constraint(equalTo: inputRow.bottomAnchor, constant: -8),
            sendButton.widthAnchor.constraint(equalToConstant: 32),
            sendButton.heightAnchor.constraint(equalToConstant: 32),
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
        invalidateIntrinsicContentSize()
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

    private func formatDuration(_ seconds: TimeInterval) -> String {
        let mins = Int(seconds) / 60
        let secs = Int(seconds) % 60
        let tenths = Int((seconds * 10).truncatingRemainder(dividingBy: 10))
        return String(format: "%d:%02d.%d", mins, secs, tenths)
    }

    // MARK: - Send Button State

    private func updateSendButtonState() {
        let hasText = !(textView.text ?? "").trimmingCharacters(in: .whitespacesAndNewlines).isEmpty
        let hasImage = !imagePreviewContainer.isHidden
        let enabled = hasText || hasImage
        sendButton.isEnabled = enabled
        sendButton.tintColor = enabled ? .naarsPrimary : .systemGray
    }

    // MARK: Cleanup

    func tearDown() {
        if controller.isRecording {
            controller.cancelRecording()
        }
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
