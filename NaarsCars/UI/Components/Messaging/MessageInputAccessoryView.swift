//
//  MessageInputAccessoryView.swift
//  NaarsCars
//
//  UIKit input accessory view for the conversation screen.
//  Replaces the SwiftUI MessageInputBar when used inside MessagesViewController
//  to enable interactive keyboard dismissal.
//

import UIKit
import AVFoundation

// MARK: - Delegate Protocol

protocol MessageInputDelegate: AnyObject {
    func inputBar(_ bar: MessageInputAccessoryView, didSendText text: String)
    func inputBar(_ bar: MessageInputAccessoryView, didSendEditedText text: String, messageId: UUID)
    func inputBarDidRequestImagePicker(_ bar: MessageInputAccessoryView)
    func inputBarDidRequestCamera(_ bar: MessageInputAccessoryView)
    func inputBar(_ bar: MessageInputAccessoryView, didRecordAudio url: URL, duration: Double)
    func inputBar(_ bar: MessageInputAccessoryView, didShareLocation lat: Double, lon: Double, name: String?)
    func inputBarDidCancelReply(_ bar: MessageInputAccessoryView)
    func inputBarDidCancelEdit(_ bar: MessageInputAccessoryView)
    func inputBarDidChangeTypingState(_ bar: MessageInputAccessoryView)
}

// MARK: - MessageInputAccessoryView

final class MessageInputAccessoryView: UIView {

    // MARK: Public API

    weak var delegate: MessageInputDelegate?

    var currentText: String {
        get { textView.text ?? "" }
        set {
            textView.text = newValue
            placeholderLabel.isHidden = !newValue.isEmpty
            updateSendButtonState()
            invalidateIntrinsicContentSize()
        }
    }

    func setReplyContext(name: String, preview: String) {
        guard replyName != name || replyPreview != preview else { return }
        replyName = name
        replyPreview = preview
        editMessageId = nil
        editOriginalText = nil
        showReplyBanner()
    }

    func clearReplyContext() {
        guard replyName != nil else { return }
        replyName = nil
        replyPreview = nil
        hideContextBanner()
    }

    func setEditContext(text: String, messageId: UUID) {
        guard editMessageId != messageId else { return }
        editMessageId = messageId
        editOriginalText = text
        replyName = nil
        replyPreview = nil
        showEditBanner()
        currentText = text
    }

    func clearEditContext() {
        guard editMessageId != nil else { return }
        editMessageId = nil
        editOriginalText = nil
        currentText = ""
        hideContextBanner()
    }

    func setImagePreview(_ image: UIImage?) {
        guard imagePreviewView.image !== image else { return }
        if let image {
            imagePreviewView.image = image
            imagePreviewContainer.isHidden = false
        } else {
            imagePreviewView.image = nil
            imagePreviewContainer.isHidden = true
        }
        invalidateIntrinsicContentSize()
    }

    // MARK: Private State

    private var replyName: String?
    private var replyPreview: String?
    private var editMessageId: UUID?
    private var editOriginalText: String?

    // Audio recording
    private var audioRecorder: AVAudioRecorder?
    private var recordingURL: URL?
    private var recordingStartDate: Date?
    private var recordingTimer: Timer?
    private var recordingDuration: TimeInterval = 0
    private var isRecording = false

    // Typing throttle
    private var lastTypingSignalAt: Date = .distantPast
    private var previousTextLength: Int = 0

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

    override init(frame: CGRect) {
        super.init(frame: frame)
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

        NSLayoutConstraint.activate([
            bannerAccentBar.leadingAnchor.constraint(equalTo: contextBanner.leadingAnchor, constant: 12),
            bannerAccentBar.topAnchor.constraint(equalTo: contextBanner.topAnchor, constant: 10),
            bannerAccentBar.bottomAnchor.constraint(equalTo: contextBanner.bottomAnchor, constant: -10),
            bannerAccentBar.widthAnchor.constraint(equalToConstant: 3),

            bannerTitleLabel.leadingAnchor.constraint(equalTo: bannerAccentBar.trailingAnchor, constant: 10),
            bannerTitleLabel.topAnchor.constraint(equalTo: contextBanner.topAnchor, constant: 10),
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
            guard let self else { return }
            self.delegate?.inputBarDidRequestCamera(self)
        }

        let photos = UIAction(
            title: "messaging_menu_photo".localized,
            image: UIImage(systemName: "photo.on.rectangle.angled")
        ) { [weak self] _ in
            guard let self else { return }
            self.delegate?.inputBarDidRequestImagePicker(self)
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
            guard let self else { return }
            self.delegate?.inputBar(self, didShareLocation: 0, lon: 0, name: nil)
            // Note: The actual location picker is presented by the delegate
            // via UIHostingController from the view controller. The 0,0
            // coordinates are a sentinel — the VC intercepts this and shows
            // the picker instead of sending.
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

        let text = currentText.trimmingCharacters(in: .whitespacesAndNewlines)

        if let editId = editMessageId {
            guard !text.isEmpty else { return }
            delegate?.inputBar(self, didSendEditedText: text, messageId: editId)
            clearEditContext()
        } else {
            guard !text.isEmpty || imagePreviewView.image != nil else { return }
            let textToSend = currentText
            currentText = ""
            setImagePreview(nil)
            delegate?.inputBar(self, didSendText: textToSend)
        }
    }

    private func updateSendButtonState() {
        let hasText = !(currentText.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty)
        let hasImage = imagePreviewView.image != nil
        let enabled = hasText || hasImage
        sendButton.isEnabled = enabled
        sendButton.tintColor = enabled ? .naarsPrimary : .systemGray
    }

    // MARK: Context Banners

    private func showReplyBanner() {
        bannerTitleLabel.text = "\("messaging_replying_to".localized) \(replyName ?? "")"
        bannerPreviewLabel.text = replyPreview
        showBannerAnimated(contextBanner, heightConstraint: contextBannerHeightConstraint, height: contextBannerHeight())
    }

    private func showEditBanner() {
        bannerTitleLabel.text = "messaging_editing_message".localized
        bannerPreviewLabel.text = editOriginalText
        showBannerAnimated(contextBanner, heightConstraint: contextBannerHeightConstraint, height: contextBannerHeight())
    }

    private func hideContextBanner() {
        hideBannerAnimated(contextBanner, heightConstraint: contextBannerHeightConstraint)
    }

    @objc private func bannerCancelTapped() {
        if editMessageId != nil {
            delegate?.inputBarDidCancelEdit(self)
            clearEditContext()
        } else if replyName != nil {
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
        if isRecording {
            stopAndSendRecording()
        } else {
            startRecording()
        }
    }

    private func startRecording() {
        Task { @MainActor in
            let granted: Bool
            if #available(iOS 17, *) {
                granted = await AVAudioApplication.requestRecordPermission()
            } else {
                granted = await withCheckedContinuation { continuation in
                    AVAudioSession.sharedInstance().requestRecordPermission { result in
                        continuation.resume(returning: result)
                    }
                }
            }
            if granted {
                beginRecording()
            } else {
                showMicPermissionAlert()
            }
        }
    }

    private func beginRecording() {
        do {
            let audioSession = AVAudioSession.sharedInstance()
            try audioSession.setCategory(.playAndRecord, mode: .default)
            try audioSession.setActive(true)

            let tempDir = FileManager.default.temporaryDirectory
            let fileName = "audio_\(UUID().uuidString).m4a"
            let url = tempDir.appendingPathComponent(fileName)
            recordingURL = url

            let settings: [String: Any] = [
                AVFormatIDKey: Int(kAudioFormatMPEG4AAC),
                AVSampleRateKey: 44100.0,
                AVNumberOfChannelsKey: 1,
                AVEncoderAudioQualityKey: AVAudioQuality.high.rawValue,
            ]

            audioRecorder = try AVAudioRecorder(url: url, settings: settings)
            audioRecorder?.record()

            isRecording = true
            recordingDuration = 0
            recordingStartDate = Date()

            // Show recording banner
            showBannerAnimated(recordingBanner, heightConstraint: recordingBannerHeightConstraint, height: recordingBannerHeight())

            // Hide input row during recording
            inputRow.alpha = 0.3
            inputRow.isUserInteractionEnabled = false

            // Start duration timer
            recordingTimer = Timer.scheduledTimer(withTimeInterval: 1.0, repeats: true) { [weak self] _ in
                guard let self, let start = self.recordingStartDate else { return }
                self.recordingDuration = Date().timeIntervalSince(start)
                self.recordingDurationLabel.text = self.formatDuration(self.recordingDuration)
            }

            // Pulsing animation for recording dot
            startDotPulsing()

            // Haptic feedback
            let generator = UIImpactFeedbackGenerator(style: .medium)
            generator.impactOccurred()
        } catch {
            AppLogger.error("messaging", "Failed to start recording: \(error.localizedDescription)")
        }
    }

    @objc private func stopAndSendRecording() {
        guard let recorder = audioRecorder, let url = recordingURL else { return }

        recorder.stop()
        recordingTimer?.invalidate()
        recordingTimer = nil

        let duration = recordingStartDate.map { Date().timeIntervalSince($0) } ?? recordingDuration

        isRecording = false
        stopDotPulsing()
        hideBannerAnimated(recordingBanner, heightConstraint: recordingBannerHeightConstraint)
        inputRow.alpha = 1
        inputRow.isUserInteractionEnabled = true

        if duration >= 1.0 {
            delegate?.inputBar(self, didRecordAudio: url, duration: duration)
        }

        audioRecorder = nil
        recordingURL = nil
        recordingStartDate = nil
        recordingDuration = 0

        try? AVAudioSession.sharedInstance().setActive(false, options: .notifyOthersOnDeactivation)
    }

    @objc private func cancelRecordingTapped() {
        cancelRecording()
    }

    private func cancelRecording() {
        audioRecorder?.stop()
        audioRecorder?.deleteRecording()
        recordingTimer?.invalidate()
        recordingTimer = nil

        isRecording = false
        stopDotPulsing()
        hideBannerAnimated(recordingBanner, heightConstraint: recordingBannerHeightConstraint)
        inputRow.alpha = 1
        inputRow.isUserInteractionEnabled = true

        audioRecorder = nil
        recordingURL = nil
        recordingStartDate = nil
        recordingDuration = 0

        try? AVAudioSession.sharedInstance().setActive(false, options: .notifyOthersOnDeactivation)
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

    private func showMicPermissionAlert() {
        guard let vc = findViewController() else { return }
        let alert = UIAlertController(
            title: "messaging_microphone_access_title".localized,
            message: "messaging_microphone_access_message".localized,
            preferredStyle: .alert
        )
        alert.addAction(UIAlertAction(title: "messaging_open_settings".localized, style: .default) { _ in
            if let url = URL(string: UIApplication.openSettingsURLString) {
                UIApplication.shared.open(url)
            }
        })
        alert.addAction(UIAlertAction(title: "common_cancel".localized, style: .cancel))
        vc.present(alert, animated: true)
    }

    // MARK: Typing Signal

    private func signalTypingIfNeeded(oldLength: Int, newLength: Int, newText: String) {
        let trimmed = newText.trimmingCharacters(in: .whitespacesAndNewlines)
        guard !trimmed.isEmpty else { return }
        guard newLength >= oldLength else { return }
        guard newLength >= 2 else { return }

        let now = Date()
        guard now.timeIntervalSince(lastTypingSignalAt) >= Constants.Timing.typingSignalThreshold else { return }
        lastTypingSignalAt = now
        delegate?.inputBarDidChangeTypingState(self)
    }

    // MARK: Helpers

    private func findViewController() -> UIViewController? {
        var responder: UIResponder? = self
        while let next = responder?.next {
            if let vc = next as? UIViewController { return vc }
            responder = next
        }
        return nil
    }

    // MARK: Cleanup

    func tearDown() {
        if isRecording {
            cancelRecording()
        }
    }
}

// MARK: - UITextViewDelegate

extension MessageInputAccessoryView: UITextViewDelegate {

    func textViewDidChange(_ textView: UITextView) {
        let oldLength = previousTextLength
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

        signalTypingIfNeeded(oldLength: oldLength, newLength: textView.text.count, newText: textView.text)
        previousTextLength = textView.text.count
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
