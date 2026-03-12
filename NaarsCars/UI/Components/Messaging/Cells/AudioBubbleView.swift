//
//  AudioBubbleView.swift
//  NaarsCars
//
//  UIKit audio waveform bubble — Combine subscription to MessageAudioPlayer
//

import UIKit
internal import Combine

/// Pure UIKit audio bubble with waveform visualization and play/pause.
final class AudioBubbleView: UIView {

    // MARK: - Subviews

    private let playButton = UIButton(type: .system)
    private let durationLabel = UILabel()
    private let bubbleLayer = CAShapeLayer()
    private var barLayers: [CAShapeLayer] = []

    // MARK: - State

    private var audioUrl: String = ""
    private var totalDuration: Double = 0
    private var isFromCurrentUser = false
    private var cancellable: AnyCancellable?

    // MARK: - Constants

    private let barCount = 20
    private let barWidth: CGFloat = 3
    private let barSpacing: CGFloat = 2
    private let barHeights: [CGFloat] = [10, 14, 18, 12, 22, 16, 20, 12, 24, 14, 18, 10, 16, 22, 12, 20, 14, 18, 12, 16]
    private let hPad: CGFloat = 12
    private let vPad: CGFloat = 10
    private let playButtonSize: CGFloat = 40

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
        layer.insertSublayer(bubbleLayer, at: 0)

        playButton.addTarget(self, action: #selector(togglePlayback), for: .touchUpInside)
        addSubview(playButton)

        // Create waveform bar layers
        for _ in 0..<barCount {
            let bar = CAShapeLayer()
            bar.cornerRadius = 1
            layer.addSublayer(bar)
            barLayers.append(bar)
        }

        durationLabel.font = .monospacedDigitSystemFont(ofSize: UIFont.preferredFont(forTextStyle: .footnote).pointSize, weight: .medium)
        durationLabel.textAlignment = .right
        addSubview(durationLabel)
    }

    // MARK: - Configure

    func configure(audioUrl: String, duration: Double, isFromCurrentUser: Bool) {
        self.audioUrl = audioUrl
        self.totalDuration = duration
        self.isFromCurrentUser = isFromCurrentUser

        let primaryColor = isFromCurrentUser ? UIColor.white : UIColor.naarsPrimary
        let bgColor = isFromCurrentUser ? UIColor.naarsPrimary : UIColor.systemGray5

        bubbleLayer.fillColor = bgColor.cgColor
        playButton.tintColor = primaryColor

        // Play button background
        playButton.backgroundColor = isFromCurrentUser
            ? UIColor.white.withAlphaComponent(0.2)
            : UIColor.naarsPrimary.withAlphaComponent(0.1)
        playButton.layer.cornerRadius = playButtonSize / 2

        durationLabel.textColor = isFromCurrentUser
            ? UIColor.white.withAlphaComponent(0.8)
            : UIColor.secondaryLabel

        isAccessibilityElement = true
        accessibilityTraits = .button

        subscribeToPlayer()
        updateUI(isPlaying: false, progress: 0)
        setNeedsLayout()
    }

    // MARK: - Combine

    private func subscribeToPlayer() {
        cancellable?.cancel()
        let player = MessageAudioPlayer.shared
        cancellable = player.objectWillChange
            .receive(on: RunLoop.main)
            .sink { [weak self] _ in
                guard let self else { return }
                let isCurrent = player.currentUrl?.absoluteString == self.audioUrl
                let playing = isCurrent && player.isPlaying
                let progress = isCurrent ? player.progress : 0
                self.updateUI(isPlaying: playing, progress: progress)
            }
    }

    private func updateUI(isPlaying: Bool, progress: Double) {
        let iconName = isPlaying ? "pause.fill" : "play.fill"
        let config = UIImage.SymbolConfiguration(pointSize: 18, weight: .regular)
        playButton.setImage(UIImage(systemName: iconName, withConfiguration: config), for: .normal)

        let statusText = isPlaying
            ? NSLocalizedString("accessibility_audio_playing", comment: "")
            : NSLocalizedString("accessibility_audio_paused", comment: "")
        accessibilityLabel = "\(statusText), \(durationLabel.text ?? "")"
        accessibilityHint = NSLocalizedString("accessibility_tap_to_toggle", comment: "")

        // Waveform fill
        let filledCount = Int(progress * Double(barCount))
        for (i, bar) in barLayers.enumerated() {
            let played = i < filledCount
            if isFromCurrentUser {
                bar.fillColor = UIColor.white.withAlphaComponent(played ? 1.0 : 0.4).cgColor
            } else {
                bar.fillColor = UIColor.naarsPrimary.withAlphaComponent(played ? 1.0 : 0.3).cgColor
            }
        }

        // Duration label
        let dur = totalDuration > 0 ? totalDuration : 0
        if progress > 0 && dur > 0 {
            let elapsed = dur * progress
            durationLabel.text = "\(Self.fmt(elapsed)) / \(Self.fmt(dur))"
        } else {
            durationLabel.text = Self.fmt(dur)
        }
    }

    // MARK: - Layout

    override func layoutSubviews() {
        super.layoutSubviews()
        let b = bounds
        let path = UIBezierPath(roundedRect: b, cornerRadius: 18).cgPath
        bubbleLayer.path = path

        playButton.frame = CGRect(x: hPad, y: (b.height - playButtonSize) / 2, width: playButtonSize, height: playButtonSize)

        let waveX = playButton.frame.maxX + 12
        let waveH: CGFloat = 30
        let waveY = (b.height - waveH) / 2
        for (i, bar) in barLayers.enumerated() {
            let h = barHeights[i]
            let x = waveX + CGFloat(i) * (barWidth + barSpacing)
            let y = waveY + (waveH - h) / 2
            let rect = CGRect(x: x, y: y, width: barWidth, height: h)
            bar.path = UIBezierPath(roundedRect: rect, cornerRadius: 1).cgPath
        }

        let durSize = durationLabel.sizeThatFits(CGSize(width: 100, height: 20))
        durationLabel.frame = CGRect(
            x: b.width - hPad - durSize.width,
            y: (b.height - durSize.height) / 2,
            width: durSize.width,
            height: durSize.height
        )
    }

    override func sizeThatFits(_ size: CGSize) -> CGSize {
        let waveWidth = CGFloat(barCount) * (barWidth + barSpacing) - barSpacing
        let durWidth: CGFloat = 70
        let w = hPad + playButtonSize + 12 + waveWidth + 12 + durWidth + hPad
        return CGSize(width: min(w, size.width), height: playButtonSize + vPad * 2)
    }

    // MARK: - Reuse

    func prepareForReuse() {
        cancellable?.cancel()
        cancellable = nil
        audioUrl = ""
        for bar in barLayers {
            bar.fillColor = UIColor.clear.cgColor
        }
    }

    // MARK: - Actions

    @objc private func togglePlayback() {
        MessageAudioPlayer.shared.togglePlayback(urlString: audioUrl)
    }

    // MARK: - Helpers

    private static func fmt(_ seconds: Double) -> String {
        let m = Int(seconds) / 60
        let s = Int(seconds) % 60
        return String(format: "%d:%02d", m, s)
    }

    // MARK: - Trait changes

    override func traitCollectionDidChange(_ previousTraitCollection: UITraitCollection?) {
        super.traitCollectionDidChange(previousTraitCollection)
        if traitCollection.hasDifferentColorAppearance(comparedTo: previousTraitCollection) {
            bubbleLayer.fillColor = isFromCurrentUser
                ? UIColor.naarsPrimary.cgColor
                : UIColor.systemGray5.cgColor
        }
    }
}
