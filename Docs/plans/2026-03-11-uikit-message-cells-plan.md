# UIKit Message Cell Migration — Implementation Plan

> **For agentic workers:** REQUIRED: Use superpowers:subagent-driven-development (if subagents available) or superpowers:executing-plans to implement this plan. Steps use checkbox (`- [ ]`) syntax for tracking.

**Goal:** Replace SwiftUI `MessageBubble` + `UIHostingConfiguration` cell rendering with pure UIKit cells to eliminate 700–1600ms frame drops on keyboard appearance, achieving pixel-perfect iMessage visual fidelity.

**Architecture:** Incremental 5-layer migration — standalone UIKit cell views → cell container with gestures → collection view integration swap → interaction overlay → thread view + cleanup. Each layer is a commit boundary. The `UIHostingConfiguration` is eliminated; cells use native UIKit views configured via `MessageCellConfig` structs and communicate via `MessageCellDelegate` protocol.

**Tech Stack:** UIKit (cells, gestures, overlay), Combine (async observation for audio), AVFoundation (audio playback), MapKit (location snapshots), LinkPresentation (link previews), CAShapeLayer + UIBezierPath (bubble geometry)

**Spec:** `Docs/plans/2026-03-11-uikit-message-cells-design.md`

---

## Chunk 1: Prerequisites + Layer 1 (Standalone UIKit Cell Views)

These tasks create new files only — no existing code is modified. All views are standalone `UIView` subclasses that can be built and verified independently.

### Task 1: Extract URLDetectionCache + Add UIColor Extensions

**Files:**
- Create: `NaarsCars/Core/Utilities/URLDetectionCache.swift`
- Modify: `NaarsCars/UI/Styles/ColorTheme.swift` — add `UIColor` equivalents

- [ ] **Step 1: Extract URLDetectionCache**

Copy the `URLDetectionCache` class from `NaarsCars/UI/Components/Messaging/MessageBubble.swift` (lines 1194–1221) to a new standalone file. Change access from `private` to `internal`.

```swift
// NaarsCars/Core/Utilities/URLDetectionCache.swift
import Foundation

/// Thread-safe URL detection cache using NSDataDetector.
/// Avoids re-parsing message text on every view evaluation.
final class URLDetectionCache: @unchecked Sendable {
    static let shared = URLDetectionCache()

    private let lock = NSLock()
    private var cache: [String: [URL]] = [:]
    private let detector: NSDataDetector? = {
        try? NSDataDetector(types: NSTextCheckingResult.CheckingType.link.rawValue)
    }()

    func urls(for text: String) -> [URL] {
        lock.lock()
        defer { lock.unlock() }
        if let cached = cache[text] { return cached }
        guard let detector else { return [] }
        let range = NSRange(text.startIndex..., in: text)
        let results = detector.matches(in: text, range: range).compactMap { $0.url }
        cache[text] = results
        return results
    }
}
```

- [ ] **Step 2: Add UIColor equivalents to ColorTheme.swift**

Add a `UIColor` extension block mirroring the existing `Color` extensions. These are needed by the UIKit cell views.

Add after the existing `extension Color { ... }` block (before the `UIColor` hex extension):

```swift
// MARK: - UIColor Brand Equivalents (for UIKit cell views)

extension UIColor {
    static let naarsPrimary = UIColor { traitCollection in
        traitCollection.userInterfaceStyle == .dark
            ? UIColor(hex: "C97A64") : UIColor(hex: "B5634B")
    }
    static let naarsCardBackground = UIColor { traitCollection in
        traitCollection.userInterfaceStyle == .dark
            ? UIColor(hex: "2C2C2C") : UIColor(hex: "FFFFFF")
    }
    static let naarsBackgroundSecondary = UIColor { traitCollection in
        traitCollection.userInterfaceStyle == .dark
            ? UIColor(hex: "1E1E1E") : UIColor(hex: "FFFFFF")
    }
}
```

- [ ] **Step 3: Build to verify**

Run: `xcodebuild -project NaarsCars/NaarsCars.xcodeproj -scheme NaarsCars -configuration Debug -destination 'generic/platform=iOS' build 2>&1 | grep -E "error:|BUILD"`
Expected: BUILD SUCCEEDED

- [ ] **Step 4: Commit**

```bash
git add NaarsCars/Core/Utilities/URLDetectionCache.swift NaarsCars/UI/Styles/ColorTheme.swift
git commit -m "refactor: extract URLDetectionCache and add UIColor brand equivalents for UIKit cell migration"
```

---

### Task 2: BubblePath

**Files:**
- Create: `NaarsCars/UI/Components/Messaging/Cells/BubblePath.swift`

The bubble shape is the visual foundation. Must match existing `BubbleShape` in `MessageBubble.swift` (lines 961–1073) — same corner radius (18pt), same tail geometry, ported from SwiftUI `Path` to `UIBezierPath`.

- [ ] **Step 1: Create BubblePath.swift**

```swift
// NaarsCars/UI/Components/Messaging/Cells/BubblePath.swift
import UIKit

/// Generates iMessage-style bubble paths with optional tail.
/// Port of the SwiftUI BubbleShape to UIBezierPath.
enum BubblePath {
    /// Returns a bubble path for the given rect.
    /// - Parameters:
    ///   - rect: The bounding rect for the bubble
    ///   - isFromCurrentUser: Sent (right tail) vs received (left tail)
    ///   - showTail: Whether to show the tail (last message in series)
    /// - Returns: A continuous UIBezierPath
    static func path(in rect: CGRect, isFromCurrentUser: Bool, showTail: Bool) -> UIBezierPath {
        let cornerRadius: CGFloat = 18
        let tailWidth: CGFloat = 8
        let tailHeight: CGFloat = 6
        let tailCorner: CGFloat = 2

        // Bubble body inset to leave room for tail
        let bodyRect: CGRect
        if showTail {
            bodyRect = isFromCurrentUser
                ? CGRect(x: rect.minX, y: rect.minY, width: rect.width - tailWidth, height: rect.height - tailHeight)
                : CGRect(x: rect.minX + tailWidth, y: rect.minY, width: rect.width - tailWidth, height: rect.height - tailHeight)
        } else {
            bodyRect = CGRect(x: rect.minX, y: rect.minY, width: rect.width, height: rect.height)
        }

        let path = UIBezierPath()
        let minX = bodyRect.minX
        let minY = bodyRect.minY
        let maxX = bodyRect.maxX
        let maxY = bodyRect.maxY

        if isFromCurrentUser {
            // Start at top-left + cornerRadius
            path.move(to: CGPoint(x: minX + cornerRadius, y: minY))
            // Top edge
            path.addLine(to: CGPoint(x: maxX - cornerRadius, y: minY))
            // Top-right corner
            path.addQuadCurve(to: CGPoint(x: maxX, y: minY + cornerRadius),
                              controlPoint: CGPoint(x: maxX, y: minY))
            // Right edge
            path.addLine(to: CGPoint(x: maxX, y: maxY - cornerRadius))

            if showTail {
                // Bottom-right with tail — smooth curve into tail
                path.addQuadCurve(to: CGPoint(x: maxX, y: maxY - tailCorner),
                                  controlPoint: CGPoint(x: maxX, y: maxY - tailCorner))
                // Tail curves out and down
                path.addCurve(to: CGPoint(x: maxX + tailWidth, y: maxY + tailHeight),
                              controlPoint1: CGPoint(x: maxX + tailWidth * 0.1, y: maxY),
                              controlPoint2: CGPoint(x: maxX + tailWidth * 0.8, y: maxY + tailHeight * 0.6))
                // Tail curves back to bottom edge
                path.addCurve(to: CGPoint(x: maxX - cornerRadius * 0.5, y: maxY),
                              controlPoint1: CGPoint(x: maxX + tailWidth * 0.3, y: maxY + tailHeight),
                              controlPoint2: CGPoint(x: maxX, y: maxY))
            } else {
                // Standard bottom-right corner
                path.addQuadCurve(to: CGPoint(x: maxX - cornerRadius, y: maxY),
                                  controlPoint: CGPoint(x: maxX, y: maxY))
            }

            // Bottom edge
            path.addLine(to: CGPoint(x: minX + cornerRadius, y: maxY))
            // Bottom-left corner
            path.addQuadCurve(to: CGPoint(x: minX, y: maxY - cornerRadius),
                              controlPoint: CGPoint(x: minX, y: maxY))
            // Left edge
            path.addLine(to: CGPoint(x: minX, y: minY + cornerRadius))
            // Top-left corner
            path.addQuadCurve(to: CGPoint(x: minX + cornerRadius, y: minY),
                              controlPoint: CGPoint(x: minX, y: minY))
        } else {
            // Received message — mirror horizontally (tail on left)
            path.move(to: CGPoint(x: maxX - cornerRadius, y: minY))
            // Top edge (right to left)
            path.addLine(to: CGPoint(x: minX + cornerRadius, y: minY))
            // Top-left corner
            path.addQuadCurve(to: CGPoint(x: minX, y: minY + cornerRadius),
                              controlPoint: CGPoint(x: minX, y: minY))
            // Left edge
            path.addLine(to: CGPoint(x: minX, y: maxY - cornerRadius))

            if showTail {
                // Bottom-left with tail
                path.addQuadCurve(to: CGPoint(x: minX, y: maxY - tailCorner),
                                  controlPoint: CGPoint(x: minX, y: maxY - tailCorner))
                path.addCurve(to: CGPoint(x: minX - tailWidth, y: maxY + tailHeight),
                              controlPoint1: CGPoint(x: minX - tailWidth * 0.1, y: maxY),
                              controlPoint2: CGPoint(x: minX - tailWidth * 0.8, y: maxY + tailHeight * 0.6))
                path.addCurve(to: CGPoint(x: minX + cornerRadius * 0.5, y: maxY),
                              controlPoint1: CGPoint(x: minX - tailWidth * 0.3, y: maxY + tailHeight),
                              controlPoint2: CGPoint(x: minX, y: maxY))
            } else {
                path.addQuadCurve(to: CGPoint(x: minX + cornerRadius, y: maxY),
                                  controlPoint: CGPoint(x: minX, y: maxY))
            }

            // Bottom edge
            path.addLine(to: CGPoint(x: maxX - cornerRadius, y: maxY))
            // Bottom-right corner
            path.addQuadCurve(to: CGPoint(x: maxX, y: maxY - cornerRadius),
                              controlPoint: CGPoint(x: maxX, y: maxY))
            // Right edge
            path.addLine(to: CGPoint(x: maxX, y: minY + cornerRadius))
            // Top-right corner
            path.addQuadCurve(to: CGPoint(x: maxX - cornerRadius, y: minY),
                              controlPoint: CGPoint(x: maxX, y: minY))
        }

        path.close()
        return path
    }
}
```

- [ ] **Step 2: Add to Xcode project and build**

Add the file to the Xcode project target. Build to verify compilation.

- [ ] **Step 3: Commit**

```bash
git add NaarsCars/UI/Components/Messaging/Cells/BubblePath.swift
git commit -m "feat: add BubblePath — UIBezierPath port of BubbleShape for UIKit cells"
```

---

### Task 3: MessageCellConfig + MessageCellDelegate

**Files:**
- Create: `NaarsCars/UI/Components/Messaging/Cells/MessageCellConfig.swift`

The shared config struct and delegate protocol used by all cell views.

- [ ] **Step 1: Create MessageCellConfig.swift**

```swift
// NaarsCars/UI/Components/Messaging/Cells/MessageCellConfig.swift
import Foundation

/// Configuration passed to MessageCellView for rendering a message.
struct MessageCellConfig {
    let message: Message
    let isFromCurrentUser: Bool
    let showAvatar: Bool
    let isFirstInSeries: Bool
    let isLastInSeries: Bool
    let isGroupConversation: Bool
    let totalParticipants: Int
    let participantProfiles: [Profile]
    let showReplyPreview: Bool
    let replySpine: (showTop: Bool, showBottom: Bool)?
    let isHighlighted: Bool
    let shouldAnimate: Bool

    /// Derived: whether this message failed to send
    var isFailed: Bool { message.sendStatus == .failed }
}

/// Delegate protocol for message cell interactions.
/// The collection view coordinator conforms to this.
protocol MessageCellDelegate: AnyObject {
    func messageCellDidLongPress(_ cell: MessageCellView, message: Message)
    func messageCellDidTapReaction(_ cell: MessageCellView, message: Message, reaction: String?)
    func messageCellDidSwipeToReply(_ cell: MessageCellView, message: Message)
    func messageCellDidTapImage(_ cell: MessageCellView, url: URL)
    func messageCellDidTapReplyPreview(_ cell: MessageCellView, replyToId: UUID)
    func messageCellDidTapRetry(_ cell: MessageCellView, message: Message)
}
```

Note: `MessageCellView` is forward-declared here — it will be created in Task 9. The file will compile once Task 9 is complete. For now, this establishes the contract.

- [ ] **Step 2: Add to Xcode project and build**

Build will produce a "cannot find type 'MessageCellView'" error for the delegate protocol. This is expected until Task 9.

- [ ] **Step 3: Commit**

```bash
git add NaarsCars/UI/Components/Messaging/Cells/MessageCellConfig.swift
git commit -m "feat: add MessageCellConfig and MessageCellDelegate protocol"
```

---

### Task 4: TextBubbleView

**Files:**
- Create: `NaarsCars/UI/Components/Messaging/Cells/TextBubbleView.swift`

Reference: `MessageBubble.messageBubbleView` (lines 621–629 of MessageBubble.swift)

- [ ] **Step 1: Create TextBubbleView.swift**

```swift
// NaarsCars/UI/Components/Messaging/Cells/TextBubbleView.swift
import UIKit

/// Renders a text message with a bubble-shaped background.
final class TextBubbleView: UIView {
    private let textLabel = UILabel()
    private let bubbleLayer = CAShapeLayer()
    private var isFromCurrentUser = false
    private var showTail = false

    override init(frame: CGRect) {
        super.init(frame: frame)
        layer.insertSublayer(bubbleLayer, at: 0)
        textLabel.numberOfLines = 0
        textLabel.font = .preferredFont(forTextStyle: .body)
        addSubview(textLabel)
    }

    required init?(coder: NSCoder) { fatalError() }

    func configure(text: String, isFromCurrentUser: Bool, showTail: Bool) {
        self.isFromCurrentUser = isFromCurrentUser
        self.showTail = showTail
        textLabel.text = text
        textLabel.textColor = isFromCurrentUser ? .white : .label
        bubbleLayer.fillColor = isFromCurrentUser
            ? UIColor.naarsPrimary.cgColor
            : UIColor.systemGray5.cgColor
        setNeedsLayout()
    }

    override func layoutSubviews() {
        super.layoutSubviews()
        let padding = UIEdgeInsets(top: 10, left: 14, bottom: 10, right: 14)
        textLabel.frame = bounds.inset(by: padding)
        bubbleLayer.path = BubblePath.path(in: bounds, isFromCurrentUser: isFromCurrentUser, showTail: showTail).cgPath
        bubbleLayer.frame = bounds
    }

    override func sizeThatFits(_ size: CGSize) -> CGSize {
        let padding = UIEdgeInsets(top: 10, left: 14, bottom: 10, right: 14)
        let maxTextWidth = size.width - padding.left - padding.right
        let textSize = textLabel.sizeThatFits(CGSize(width: maxTextWidth, height: .greatestFiniteMagnitude))
        return CGSize(
            width: textSize.width + padding.left + padding.right,
            height: textSize.height + padding.top + padding.bottom
        )
    }

    func prepareForReuse() {
        textLabel.text = nil
    }
}
```

- [ ] **Step 2: Add to Xcode project and build**
- [ ] **Step 3: Commit**

```bash
git add NaarsCars/UI/Components/Messaging/Cells/TextBubbleView.swift
git commit -m "feat: add TextBubbleView — UIKit text bubble with BubblePath background"
```

---

### Task 5: ImageBubbleView

**Files:**
- Create: `NaarsCars/UI/Components/Messaging/Cells/ImageBubbleView.swift`

Reference: `MessageBubble.messageImageView` (lines 732–764) and `localImageView` (lines 643–696)

- [ ] **Step 1: Create ImageBubbleView.swift**

Handles both remote images (via PersistentImageService) and local images (via LocalAttachmentStorage). Uses generation counter for cell-reuse safety.

```swift
// NaarsCars/UI/Components/Messaging/Cells/ImageBubbleView.swift
import UIKit

/// Renders an image message with loading/error states.
final class ImageBubbleView: UIView {
    private let imageView = UIImageView()
    private let spinner = UIActivityIndicatorView(style: .medium)
    private let retryIcon = UIImageView(image: UIImage(systemName: "arrow.clockwise.circle"))
    private var loadGeneration: UInt64 = 0
    private let maxImageSize = CGSize(width: 220, height: 220)
    var onImageTap: ((URL) -> Void)?
    private var currentURL: URL?

    override init(frame: CGRect) {
        super.init(frame: frame)
        imageView.contentMode = .scaleAspectFill
        imageView.clipsToBounds = true
        imageView.layer.cornerRadius = 18
        imageView.isUserInteractionEnabled = true
        addSubview(imageView)
        spinner.hidesWhenStopped = true
        addSubview(spinner)
        retryIcon.tintColor = .secondaryLabel
        retryIcon.isHidden = true
        retryIcon.isUserInteractionEnabled = true
        retryIcon.addGestureRecognizer(UITapGestureRecognizer(target: self, action: #selector(retryTapped)))
        addSubview(retryIcon)
        imageView.addGestureRecognizer(UITapGestureRecognizer(target: self, action: #selector(imageTapped)))
    }

    required init?(coder: NSCoder) { fatalError() }

    func configure(message: Message) {
        loadGeneration &+= 1
        let gen = loadGeneration
        imageView.image = nil
        retryIcon.isHidden = true

        // Local image (still uploading)
        if let localPath = message.localAttachmentPath, message.imageUrl == nil {
            if let data = LocalAttachmentStorage.load(path: localPath), let img = UIImage(data: data) {
                imageView.image = img
                spinner.stopAnimating()
            } else {
                showPlaceholder()
            }
            return
        }

        // Remote image
        guard let urlStr = message.imageUrl, let url = URL(string: urlStr) else { return }
        currentURL = url

        // Sync cache check
        Task { @MainActor in
            if let cached = await PersistentImageService.shared.getImage(for: urlStr) {
                guard self.loadGeneration == gen else { return }
                self.imageView.image = cached
                self.spinner.stopAnimating()
            } else {
                self.showPlaceholder()
                // Async load
                if let loaded = await PersistentImageService.shared.getImage(for: urlStr) {
                    guard self.loadGeneration == gen else { return }
                    UIView.transition(with: self.imageView, duration: 0.2, options: .transitionCrossDissolve) {
                        self.imageView.image = loaded
                    }
                    self.spinner.stopAnimating()
                } else {
                    guard self.loadGeneration == gen else { return }
                    self.spinner.stopAnimating()
                    self.retryIcon.isHidden = false
                }
            }
        }
    }

    private func showPlaceholder() {
        imageView.backgroundColor = .systemGray5
        spinner.startAnimating()
    }

    @objc private func imageTapped() {
        if let url = currentURL { onImageTap?(url) }
    }

    @objc private func retryTapped() {
        retryIcon.isHidden = true
        // Re-trigger by incrementing generation and re-calling configure would be needed,
        // but the delegate handles retry via MessageCellDelegate
    }

    override func layoutSubviews() {
        super.layoutSubviews()
        imageView.frame = bounds
        spinner.center = CGPoint(x: bounds.midX, y: bounds.midY)
        retryIcon.frame = CGRect(x: bounds.midX - 20, y: bounds.midY - 20, width: 40, height: 40)
    }

    override func sizeThatFits(_ size: CGSize) -> CGSize {
        // Cap at maxImageSize, maintain aspect ratio if image is available
        if let image = imageView.image {
            let aspect = image.size.width / image.size.height
            let width = min(maxImageSize.width, size.width * 0.7)
            let height = min(width / aspect, maxImageSize.height)
            return CGSize(width: width, height: height)
        }
        return CGSize(width: min(maxImageSize.width, size.width * 0.7), height: 150)
    }

    func prepareForReuse() {
        loadGeneration &+= 1
        imageView.image = nil
        imageView.backgroundColor = nil
        spinner.stopAnimating()
        retryIcon.isHidden = true
        currentURL = nil
    }
}
```

- [ ] **Step 2: Add to Xcode project and build**
- [ ] **Step 3: Commit**

```bash
git add NaarsCars/UI/Components/Messaging/Cells/ImageBubbleView.swift
git commit -m "feat: add ImageBubbleView — UIKit image cell with async loading and generation counter"
```

---

### Task 6: AudioBubbleView

**Files:**
- Create: `NaarsCars/UI/Components/Messaging/Cells/AudioBubbleView.swift`

Reference: `MessageBubble.AudioMessageContentView` (lines 1112–1189) and `AudioPlaybackState` (lines 1077–1109)

- [ ] **Step 1: Create AudioBubbleView.swift**

Uses Combine subscription to `MessageAudioPlayer.shared`, filtered to this specific audio URL.

```swift
// NaarsCars/UI/Components/Messaging/Cells/AudioBubbleView.swift
import UIKit
import Combine

/// Renders an audio message with waveform visualization and play/pause control.
final class AudioBubbleView: UIView {
    private let playButton = UIButton(type: .system)
    private let durationLabel = UILabel()
    private let waveformContainer = UIView()
    private var waveformBars: [CAShapeLayer] = []
    private let bubbleLayer = CAShapeLayer()
    private var cancellable: AnyCancellable?
    private var audioUrlString: String?
    private var isFromCurrentUser = false
    private var totalDuration: Double = 0
    private let waveformHeights: [CGFloat] = [10, 14, 18, 12, 22, 16, 20, 12, 24, 14, 18, 10, 16, 22, 12, 20, 14, 18, 12, 16]

    override init(frame: CGRect) {
        super.init(frame: frame)
        layer.insertSublayer(bubbleLayer, at: 0)
        playButton.addTarget(self, action: #selector(togglePlayback), for: .touchUpInside)
        addSubview(playButton)
        durationLabel.font = .monospacedDigitSystemFont(ofSize: 12, weight: .medium)
        addSubview(durationLabel)
        addSubview(waveformContainer)
        setupWaveformBars()
    }

    required init?(coder: NSCoder) { fatalError() }

    private func setupWaveformBars() {
        for _ in waveformHeights {
            let bar = CAShapeLayer()
            bar.cornerRadius = 1.5
            waveformContainer.layer.addSublayer(bar)
            waveformBars.append(bar)
        }
    }

    func configure(audioUrl: String?, duration: Double, isFromCurrentUser: Bool) {
        self.audioUrlString = audioUrl
        self.totalDuration = duration
        self.isFromCurrentUser = isFromCurrentUser

        let tint: UIColor = isFromCurrentUser ? .white : .label
        playButton.tintColor = tint
        durationLabel.textColor = isFromCurrentUser ? .white.withAlphaComponent(0.8) : .secondaryLabel
        bubbleLayer.fillColor = isFromCurrentUser
            ? UIColor.naarsPrimary.cgColor
            : UIColor.systemGray5.cgColor

        updatePlaybackState(isPlaying: false, progress: 0)
        durationLabel.text = formatDuration(duration)

        // Subscribe to audio player updates for this URL
        cancellable?.cancel()
        cancellable = MessageAudioPlayer.shared.objectWillChange
            .receive(on: RunLoop.main)
            .sink { [weak self] _ in
                guard let self, let url = self.audioUrlString else { return }
                let player = MessageAudioPlayer.shared
                let isThisPlaying = player.isPlaying && player.currentUrl?.absoluteString == url
                self.updatePlaybackState(isPlaying: isThisPlaying, progress: isThisPlaying ? player.progress : 0)
                if isThisPlaying {
                    let elapsed = player.duration * player.progress
                    self.durationLabel.text = self.formatDuration(elapsed) + " / " + self.formatDuration(self.totalDuration)
                } else {
                    self.durationLabel.text = self.formatDuration(self.totalDuration)
                }
            }

        setNeedsLayout()
    }

    private func updatePlaybackState(isPlaying: Bool, progress: Double) {
        let icon = isPlaying ? "pause.circle.fill" : "play.circle.fill"
        playButton.setImage(UIImage(systemName: icon, withConfiguration: UIImage.SymbolConfiguration(pointSize: 28)), for: .normal)

        let activeColor = isFromCurrentUser ? UIColor.white : UIColor.naarsPrimary
        let inactiveColor = isFromCurrentUser ? UIColor.white.withAlphaComponent(0.4) : UIColor.systemGray3
        let filledCount = Int(progress * Double(waveformBars.count))
        for (i, bar) in waveformBars.enumerated() {
            bar.fillColor = (i < filledCount ? activeColor : inactiveColor).cgColor
        }
    }

    @objc private func togglePlayback() {
        guard let url = audioUrlString else { return }
        MessageAudioPlayer.shared.togglePlayback(urlString: url)
    }

    private func formatDuration(_ seconds: Double) -> String {
        let mins = Int(seconds) / 60
        let secs = Int(seconds) % 60
        return String(format: "%d:%02d", mins, secs)
    }

    override func layoutSubviews() {
        super.layoutSubviews()
        bubbleLayer.path = BubblePath.path(in: bounds, isFromCurrentUser: isFromCurrentUser, showTail: false).cgPath
        bubbleLayer.frame = bounds

        let padding: CGFloat = 12
        playButton.frame = CGRect(x: padding, y: (bounds.height - 32) / 2, width: 32, height: 32)

        let barSpacing: CGFloat = 3
        let barWidth: CGFloat = 3
        let waveX = playButton.frame.maxX + 8
        let waveWidth = CGFloat(waveformBars.count) * (barWidth + barSpacing) - barSpacing
        waveformContainer.frame = CGRect(x: waveX, y: padding, width: waveWidth, height: bounds.height - padding * 2)

        for (i, bar) in waveformBars.enumerated() {
            let h = waveformHeights[i]
            let x = CGFloat(i) * (barWidth + barSpacing)
            let y = (waveformContainer.bounds.height - h) / 2
            let rect = CGRect(x: x, y: y, width: barWidth, height: h)
            bar.path = UIBezierPath(roundedRect: rect, cornerRadius: 1.5).cgPath
            bar.frame = waveformContainer.bounds
        }

        let durationX = waveX + waveWidth + 8
        durationLabel.sizeToFit()
        durationLabel.frame.origin = CGPoint(x: durationX, y: (bounds.height - durationLabel.frame.height) / 2)
    }

    override func sizeThatFits(_ size: CGSize) -> CGSize {
        CGSize(width: min(260, size.width * 0.7), height: 52)
    }

    func prepareForReuse() {
        cancellable?.cancel()
        cancellable = nil
        audioUrlString = nil
    }
}
```

- [ ] **Step 2: Add to Xcode project and build**
- [ ] **Step 3: Commit**

```bash
git add NaarsCars/UI/Components/Messaging/Cells/AudioBubbleView.swift
git commit -m "feat: add AudioBubbleView — UIKit audio cell with Combine playback subscription"
```

---

### Task 7: LocationBubbleView

**Files:**
- Create: `NaarsCars/UI/Components/Messaging/Cells/LocationBubbleView.swift`

Reference: `MessageBubble.locationMessageView` (lines 779–819) and `LocationSnapshotView` (lines 877–906)

- [ ] **Step 1: Create LocationBubbleView.swift**

Uses `MapSnapshotCache.shared` with generation counter.

```swift
// NaarsCars/UI/Components/Messaging/Cells/LocationBubbleView.swift
import UIKit
import MapKit

/// Renders a location message with map snapshot and name label.
final class LocationBubbleView: UIView {
    private let mapImageView = UIImageView()
    private let pinImageView = UIImageView(image: UIImage(systemName: "mappin.circle.fill"))
    private let nameContainer = UIView()
    private let nameIcon = UIImageView(image: UIImage(systemName: "location.fill"))
    private let nameLabel = UILabel()
    private var loadGeneration: UInt64 = 0
    private var coordinate: CLLocationCoordinate2D?

    override init(frame: CGRect) {
        super.init(frame: frame)
        layer.cornerRadius = 18
        clipsToBounds = true
        layer.borderWidth = 1
        layer.borderColor = UIColor.systemGray4.cgColor

        mapImageView.contentMode = .scaleAspectFill
        mapImageView.backgroundColor = .systemGray5
        addSubview(mapImageView)

        pinImageView.tintColor = .systemRed
        pinImageView.contentMode = .scaleAspectFit
        addSubview(pinImageView)

        nameContainer.backgroundColor = UIColor.naarsBackgroundSecondary
        addSubview(nameContainer)

        nameIcon.tintColor = .naarsPrimary
        nameIcon.contentMode = .scaleAspectFit
        nameContainer.addSubview(nameIcon)

        nameLabel.font = .preferredFont(forTextStyle: .caption1)
        nameLabel.textColor = .label
        nameLabel.lineBreakMode = .byTruncatingTail
        nameContainer.addSubview(nameLabel)

        addGestureRecognizer(UITapGestureRecognizer(target: self, action: #selector(openInMaps)))
    }

    required init?(coder: NSCoder) { fatalError() }

    func configure(latitude: Double, longitude: Double, locationName: String?) {
        loadGeneration &+= 1
        let gen = loadGeneration
        let coord = CLLocationCoordinate2D(latitude: latitude, longitude: longitude)
        self.coordinate = coord
        nameLabel.text = locationName ?? "Shared location"
        mapImageView.image = nil

        Task { @MainActor in
            if let snapshot = await MapSnapshotCache.shared.snapshot(for: coord) {
                guard self.loadGeneration == gen else { return }
                self.mapImageView.image = snapshot
            }
        }
        setNeedsLayout()
    }

    @objc private func openInMaps() {
        guard let coord = coordinate else { return }
        let url = URL(string: "maps://?ll=\(coord.latitude),\(coord.longitude)")!
        UIApplication.shared.open(url)
    }

    override func layoutSubviews() {
        super.layoutSubviews()
        let nameHeight: CGFloat = 32
        mapImageView.frame = CGRect(x: 0, y: 0, width: bounds.width, height: bounds.height - nameHeight)
        pinImageView.frame = CGRect(x: bounds.midX - 16, y: mapImageView.frame.midY - 16, width: 32, height: 32)
        nameContainer.frame = CGRect(x: 0, y: bounds.height - nameHeight, width: bounds.width, height: nameHeight)
        nameIcon.frame = CGRect(x: 8, y: (nameHeight - 16) / 2, width: 16, height: 16)
        nameLabel.frame = CGRect(x: 28, y: 0, width: bounds.width - 36, height: nameHeight)
    }

    override func sizeThatFits(_ size: CGSize) -> CGSize {
        CGSize(width: min(220, size.width * 0.7), height: 152)
    }

    func prepareForReuse() {
        loadGeneration &+= 1
        mapImageView.image = nil
        coordinate = nil
    }
}
```

- [ ] **Step 2: Add to Xcode project and build**
- [ ] **Step 3: Commit**

```bash
git add NaarsCars/UI/Components/Messaging/Cells/LocationBubbleView.swift
git commit -m "feat: add LocationBubbleView — UIKit location cell with map snapshot cache"
```

---

### Task 8: Supporting Cell Views (SystemMessage, Unsent, ReadReceipt, ReactionBadge, ReplyPreview, DateSeparator, AvatarUIView, LinkPreview)

**Files:**
- Create: `NaarsCars/UI/Components/Messaging/Cells/SystemMessageView.swift`
- Create: `NaarsCars/UI/Components/Messaging/Cells/UnsentMessageView.swift`
- Create: `NaarsCars/UI/Components/Messaging/Cells/ReadReceiptView.swift`
- Create: `NaarsCars/UI/Components/Messaging/Cells/ReactionBadgeView.swift`
- Create: `NaarsCars/UI/Components/Messaging/Cells/ReplyPreviewView.swift`
- Create: `NaarsCars/UI/Components/Messaging/Cells/DateSeparatorCell.swift`
- Create: `NaarsCars/UI/Components/Messaging/Cells/LinkPreviewBubbleView.swift`
- Create: `NaarsCars/UI/Components/Common/AvatarUIView.swift`

These are all smaller views. Build them as a batch since they have no interdependencies.

- [ ] **Step 1: Create SystemMessageView.swift**

Reference: `MessageBubble.systemMessageView` (lines 304–353)

```swift
// NaarsCars/UI/Components/Messaging/Cells/SystemMessageView.swift
import UIKit

/// Centered pill showing system event (e.g. "Group created by...")
final class SystemMessageView: UIView {
    private let iconView = UIImageView()
    private let label = UILabel()
    private let pillBackground = UIView()

    override init(frame: CGRect) {
        super.init(frame: frame)
        pillBackground.backgroundColor = .naarsCardBackground
        pillBackground.layer.cornerRadius = 12
        addSubview(pillBackground)
        iconView.tintColor = .secondaryLabel
        iconView.contentMode = .scaleAspectFit
        pillBackground.addSubview(iconView)
        label.font = .preferredFont(forTextStyle: .caption1)
        label.textColor = .secondaryLabel
        label.textAlignment = .center
        label.numberOfLines = 0
        pillBackground.addSubview(label)
    }

    required init?(coder: NSCoder) { fatalError() }

    func configure(text: String) {
        label.text = text
        iconView.image = UIImage(systemName: Self.iconName(for: text))
        setNeedsLayout()
    }

    private static func iconName(for text: String) -> String {
        if text.contains("created by") { return "sparkles" }
        if text.contains("removed the group name") { return "pencil.slash" }
        if text.contains("back to the conversation") { return "person.badge.plus" }
        if text.contains("added") || text.contains("joined") { return "person.badge.plus" }
        if text.contains("left") || text.contains("removed") { return "person.badge.minus" }
        if text.contains("name") { return "pencil" }
        if text.contains("created") { return "sparkles" }
        return "info.circle"
    }

    override func layoutSubviews() {
        super.layoutSubviews()
        let maxWidth = bounds.width * 0.8
        let labelSize = label.sizeThatFits(CGSize(width: maxWidth - 36, height: .greatestFiniteMagnitude))
        let pillWidth = labelSize.width + 36
        let pillHeight = labelSize.height + 12
        pillBackground.frame = CGRect(
            x: (bounds.width - pillWidth) / 2,
            y: (bounds.height - pillHeight) / 2,
            width: pillWidth, height: pillHeight
        )
        iconView.frame = CGRect(x: 8, y: (pillHeight - 14) / 2, width: 14, height: 14)
        label.frame = CGRect(x: 26, y: 6, width: pillWidth - 34, height: labelSize.height)
    }

    override func sizeThatFits(_ size: CGSize) -> CGSize {
        let labelSize = label.sizeThatFits(CGSize(width: size.width * 0.8 - 36, height: .greatestFiniteMagnitude))
        return CGSize(width: size.width, height: labelSize.height + 28)
    }

    func prepareForReuse() { label.text = nil }
}
```

- [ ] **Step 2: Create UnsentMessageView.swift**

Reference: `MessageBubble.unsentMessageView` (lines 276–300)

```swift
// NaarsCars/UI/Components/Messaging/Cells/UnsentMessageView.swift
import UIKit

/// Strikethrough indicator for unsent messages.
final class UnsentMessageView: UIView {
    private let iconView = UIImageView(image: UIImage(systemName: "nosign"))
    private let label = UILabel()
    private let container = UIView()

    override init(frame: CGRect) {
        super.init(frame: frame)
        container.layer.cornerRadius = 18
        container.layer.borderWidth = 1
        container.layer.borderColor = UIColor.systemGray4.cgColor
        addSubview(container)
        iconView.tintColor = .secondaryLabel
        iconView.contentMode = .scaleAspectFit
        container.addSubview(iconView)
        label.font = .preferredFont(forTextStyle: .caption1)
        label.textColor = .secondaryLabel
        container.addSubview(label)
    }

    required init?(coder: NSCoder) { fatalError() }

    func configure(isFromCurrentUser: Bool) {
        label.text = isFromCurrentUser
            ? NSLocalizedString("messaging_you_unsent_a_message", comment: "")
            : NSLocalizedString("messaging_this_message_was_unsent", comment: "")
        label.font = .italicSystemFont(ofSize: UIFont.preferredFont(forTextStyle: .caption1).pointSize)
        setNeedsLayout()
    }

    override func layoutSubviews() {
        super.layoutSubviews()
        let labelSize = label.sizeThatFits(CGSize(width: bounds.width - 80, height: .greatestFiniteMagnitude))
        let containerWidth = labelSize.width + 46
        let containerHeight = labelSize.height + 20
        container.frame = CGRect(
            x: bounds.width / 2 - containerWidth / 2,
            y: (bounds.height - containerHeight) / 2,
            width: containerWidth, height: containerHeight
        )
        iconView.frame = CGRect(x: 14, y: (containerHeight - 14) / 2, width: 14, height: 14)
        label.frame = CGRect(x: 32, y: 10, width: labelSize.width, height: labelSize.height)
    }

    override func sizeThatFits(_ size: CGSize) -> CGSize {
        let labelSize = label.sizeThatFits(CGSize(width: size.width - 80, height: .greatestFiniteMagnitude))
        return CGSize(width: size.width, height: labelSize.height + 32)
    }

    func prepareForReuse() { label.text = nil }
}
```

- [ ] **Step 3: Create ReadReceiptView.swift**

Reference: `MessageBubble.dmReadReceiptIndicator` and `groupReadReceiptIndicator` (lines 162–248)

```swift
// NaarsCars/UI/Components/Messaging/Cells/ReadReceiptView.swift
import UIKit

/// Displays read receipt status: checkmarks for DMs, avatar thumbnails for groups.
final class ReadReceiptView: UIView {
    private let stackView = UIStackView()
    private let countLabel = UILabel()

    override init(frame: CGRect) {
        super.init(frame: frame)
        stackView.axis = .horizontal
        stackView.spacing = -4
        addSubview(stackView)
        countLabel.font = .systemFont(ofSize: 9)
        countLabel.textColor = .secondaryLabel
    }

    required init?(coder: NSCoder) { fatalError() }

    func configure(message: Message, totalParticipants: Int, isGroup: Bool, profiles: [Profile]) {
        stackView.arrangedSubviews.forEach { $0.removeFromSuperview() }
        countLabel.removeFromSuperview()

        let status = deriveStatus(message: message, totalParticipants: totalParticipants)

        switch status {
        case .failed:
            addIcon("exclamationmark.circle.fill", color: .systemRed, size: 14)
        case .sending:
            addIcon("clock", color: .secondaryLabel.withAlphaComponent(0.6), size: 12)
        case .sent:
            addIcon("checkmark", color: .secondaryLabel, size: 12, bold: true)
        case .delivered:
            if isGroup {
                addGroupAvatars(message: message, profiles: profiles, color: .secondaryLabel)
            } else {
                addIcon("checkmark", color: .secondaryLabel, size: 12, bold: true)
                addIcon("checkmark", color: .secondaryLabel, size: 12, bold: true)
            }
        case .read:
            if isGroup {
                addGroupAvatars(message: message, profiles: profiles, color: .naarsPrimary)
            } else {
                addIcon("checkmark", color: .naarsPrimary, size: 12, bold: true)
                addIcon("checkmark", color: .naarsPrimary, size: 12, bold: true)
            }
        }
        setNeedsLayout()
    }

    private enum Status { case failed, sending, sent, delivered, read }

    private func deriveStatus(message: Message, totalParticipants: Int) -> Status {
        if let s = message.sendStatus {
            switch s {
            case .failed: return .failed
            case .sending: return .sending
            case .sent: return .sent
            case .delivered: return .delivered
            case .read: return .read
            }
        }
        let readByOthers = message.readBy.filter { $0 != message.fromId }
        if message.readBy.isEmpty { return .sending }
        if readByOthers.isEmpty { return .sent }
        if totalParticipants > 1 && readByOthers.count >= totalParticipants - 1 { return .read }
        return .delivered
    }

    private func addIcon(_ name: String, color: UIColor, size: CGFloat, bold: Bool = false) {
        let config = UIImage.SymbolConfiguration(pointSize: size, weight: bold ? .semibold : .regular)
        let iv = UIImageView(image: UIImage(systemName: name, withConfiguration: config))
        iv.tintColor = color
        stackView.addArrangedSubview(iv)
    }

    private func addGroupAvatars(message: Message, profiles: [Profile], color: UIColor) {
        let readers = message.readBy.filter { $0 != message.fromId }
        let readerProfiles = profiles.filter { readers.contains($0.id) }
        if readerProfiles.isEmpty {
            addIcon("checkmark", color: color, size: 12, bold: true)
            addIcon("checkmark", color: color, size: 12, bold: true)
            return
        }
        for profile in readerProfiles.prefix(5) {
            let avatar = AvatarUIView(frame: CGRect(x: 0, y: 0, width: 14, height: 14))
            avatar.configure(imageUrl: profile.avatarUrl, name: profile.name, size: 14)
            avatar.layer.borderWidth = 1
            avatar.layer.borderColor = UIColor.systemBackground.cgColor
            stackView.addArrangedSubview(avatar)
        }
        if readerProfiles.count > 5 {
            countLabel.text = "+\(readerProfiles.count - 5)"
            stackView.addArrangedSubview(countLabel)
        }
    }

    override func layoutSubviews() {
        super.layoutSubviews()
        stackView.frame = bounds
    }

    override func sizeThatFits(_ size: CGSize) -> CGSize {
        stackView.systemLayoutSizeFitting(size)
    }

    func prepareForReuse() {
        stackView.arrangedSubviews.forEach { $0.removeFromSuperview() }
    }
}
```

- [ ] **Step 4: Create ReactionBadgeView.swift**

Reference: `MessageBubble.reactionBadge` (lines 823–849) and `reactionOverlay` (lines 853–872)

```swift
// NaarsCars/UI/Components/Messaging/Cells/ReactionBadgeView.swift
import UIKit

/// Emoji capsule badge showing reactions on a message.
final class ReactionBadgeView: UIView {
    private let stackView = UIStackView()
    private let countLabel = UILabel()
    private let backgroundPill = UIView()
    var onTap: (() -> Void)?
    var onLongPress: (() -> Void)?

    override init(frame: CGRect) {
        super.init(frame: frame)
        backgroundPill.backgroundColor = .systemBackground.withAlphaComponent(0.9)
        backgroundPill.layer.shadowColor = UIColor.black.cgColor
        backgroundPill.layer.shadowOpacity = 0.1
        backgroundPill.layer.shadowOffset = CGSize(width: 0, height: 1)
        backgroundPill.layer.shadowRadius = 3
        addSubview(backgroundPill)
        stackView.axis = .horizontal
        stackView.spacing = 2
        backgroundPill.addSubview(stackView)
        countLabel.font = .systemFont(ofSize: 12)
        countLabel.textColor = .secondaryLabel
        addGestureRecognizer(UITapGestureRecognizer(target: self, action: #selector(tapped)))
        let lp = UILongPressGestureRecognizer(target: self, action: #selector(longPressed))
        lp.minimumPressDuration = 0.3
        addGestureRecognizer(lp)
    }

    required init?(coder: NSCoder) { fatalError() }

    func configure(reactions: MessageReactions?) {
        stackView.arrangedSubviews.forEach { $0.removeFromSuperview() }
        guard let reactions, !reactions.reactions.isEmpty else {
            isHidden = true
            return
        }
        isHidden = false
        let sorted = reactions.sortedReactions
        for (emoji, count, _) in sorted.prefix(5) {
            let lbl = UILabel()
            lbl.text = emoji
            lbl.font = .systemFont(ofSize: 16)
            stackView.addArrangedSubview(lbl)
            if count > 1 {
                countLabel.text = "\(count)"
                stackView.addArrangedSubview(countLabel)
            }
        }
        setNeedsLayout()
    }

    @objc private func tapped() { onTap?() }
    @objc private func longPressed(_ gr: UILongPressGestureRecognizer) {
        if gr.state == .began { onLongPress?() }
    }

    override func layoutSubviews() {
        super.layoutSubviews()
        let size = stackView.systemLayoutSizeFitting(UIView.layoutFittingCompressedSize)
        let pillSize = CGSize(width: size.width + 12, height: size.height + 6)
        backgroundPill.frame = CGRect(origin: .zero, size: pillSize)
        backgroundPill.layer.cornerRadius = pillSize.height / 2
        stackView.frame = backgroundPill.bounds.insetBy(dx: 6, dy: 3)
    }

    override func sizeThatFits(_ size: CGSize) -> CGSize {
        let s = stackView.systemLayoutSizeFitting(UIView.layoutFittingCompressedSize)
        return CGSize(width: s.width + 12, height: s.height + 6)
    }

    func prepareForReuse() {
        stackView.arrangedSubviews.forEach { $0.removeFromSuperview() }
        isHidden = true
    }
}
```

- [ ] **Step 5: Create ReplyPreviewView.swift**

Reference: `MessageBubble` lines 910–956

```swift
// NaarsCars/UI/Components/Messaging/Cells/ReplyPreviewView.swift
import UIKit

/// Quoted reply preview shown above a message bubble.
final class ReplyPreviewView: UIView {
    private let accentBar = UIView()
    private let senderLabel = UILabel()
    private let previewLabel = UILabel()
    private let photoIcon = UIImageView(image: UIImage(systemName: "photo"))
    var onTap: ((UUID) -> Void)?
    private var replyToId: UUID?

    override init(frame: CGRect) {
        super.init(frame: frame)
        layer.cornerRadius = 10
        accentBar.layer.cornerRadius = 1.5
        addSubview(accentBar)
        senderLabel.font = .preferredFont(forTextStyle: .footnote).bold()
        addSubview(senderLabel)
        previewLabel.font = .preferredFont(forTextStyle: .footnote)
        previewLabel.textColor = .secondaryLabel
        previewLabel.lineBreakMode = .byTruncatingTail
        previewLabel.numberOfLines = 2
        addSubview(previewLabel)
        photoIcon.tintColor = .secondaryLabel
        photoIcon.contentMode = .scaleAspectFit
        photoIcon.isHidden = true
        addSubview(photoIcon)
        addGestureRecognizer(UITapGestureRecognizer(target: self, action: #selector(tapped)))
    }

    required init?(coder: NSCoder) { fatalError() }

    func configure(replyContext: ReplyContext, isFromCurrentUser: Bool) {
        replyToId = replyContext.id
        senderLabel.text = replyContext.senderName
        previewLabel.text = replyContext.text.isEmpty
            ? NSLocalizedString("messaging_menu_photo", comment: "") : replyContext.text
        photoIcon.isHidden = replyContext.imageUrl == nil
        let tint: UIColor = isFromCurrentUser ? .white.withAlphaComponent(0.8) : .naarsPrimary
        accentBar.backgroundColor = tint
        senderLabel.textColor = tint
        backgroundColor = isFromCurrentUser
            ? UIColor.white.withAlphaComponent(0.15)
            : UIColor.systemGray5
        setNeedsLayout()
    }

    @objc private func tapped() {
        if let id = replyToId { onTap?(id) }
    }

    override func layoutSubviews() {
        super.layoutSubviews()
        accentBar.frame = CGRect(x: 8, y: 6, width: 3, height: bounds.height - 12)
        let textX: CGFloat = 17
        senderLabel.frame = CGRect(x: textX, y: 6, width: bounds.width - textX - 8, height: 16)
        previewLabel.frame = CGRect(x: textX, y: 22, width: bounds.width - textX - 8, height: bounds.height - 28)
        if !photoIcon.isHidden {
            photoIcon.frame = CGRect(x: bounds.width - 22, y: 6, width: 14, height: 14)
        }
    }

    override func sizeThatFits(_ size: CGSize) -> CGSize {
        CGSize(width: min(size.width * 0.75, 280), height: 48)
    }

    func prepareForReuse() {
        senderLabel.text = nil
        previewLabel.text = nil
        replyToId = nil
    }
}

private extension UIFont {
    func bold() -> UIFont {
        guard let descriptor = fontDescriptor.withSymbolicTraits(.traitBold) else { return self }
        return UIFont(descriptor: descriptor, size: 0)
    }
}
```

- [ ] **Step 6: Create DateSeparatorCell.swift**

Reference: `ConversationDetailView.DateSeparatorView` (lines 1136–1182)

```swift
// NaarsCars/UI/Components/Messaging/Cells/DateSeparatorCell.swift
import UIKit

/// Day separator cell for the message list.
final class DateSeparatorCell: UICollectionViewCell {
    private let label = UILabel()
    private let pill = UIView()

    override init(frame: CGRect) {
        super.init(frame: frame)
        pill.backgroundColor = .naarsCardBackground
        pill.layer.cornerRadius = 12
        contentView.addSubview(pill)
        label.font = .preferredFont(forTextStyle: .footnote)
        label.textColor = .secondaryLabel
        label.textAlignment = .center
        pill.addSubview(label)
    }

    required init?(coder: NSCoder) { fatalError() }

    func configure(date: Date) {
        label.text = Self.formatDate(date)
        setNeedsLayout()
    }

    private static func formatDate(_ date: Date) -> String {
        let cal = Calendar.current
        if cal.isDateInToday(date) { return NSLocalizedString("messaging_today", comment: "") }
        if cal.isDateInYesterday(date) { return NSLocalizedString("messaging_yesterday", comment: "") }
        let daysDiff = cal.dateComponents([.day], from: date, to: Date()).day ?? 0
        if daysDiff < 7 {
            let fmt = DateFormatter()
            fmt.dateFormat = "EEEE"
            return fmt.string(from: date)
        }
        let fmt = DateFormatter()
        fmt.dateFormat = cal.component(.year, from: date) == cal.component(.year, from: Date())
            ? "MMM d" : "MMM d, yyyy"
        return fmt.string(from: date)
    }

    override func layoutSubviews() {
        super.layoutSubviews()
        label.sizeToFit()
        let pillSize = CGSize(width: label.frame.width + 24, height: label.frame.height + 8)
        pill.frame = CGRect(
            x: (contentView.bounds.width - pillSize.width) / 2,
            y: (contentView.bounds.height - pillSize.height) / 2,
            width: pillSize.width, height: pillSize.height
        )
        label.center = CGPoint(x: pill.bounds.midX, y: pill.bounds.midY)
    }

    override func preferredLayoutAttributesFitting(_ layoutAttributes: UICollectionViewLayoutAttributes) -> UICollectionViewLayoutAttributes {
        let attrs = super.preferredLayoutAttributesFitting(layoutAttributes)
        attrs.size.height = 44
        return attrs
    }
}
```

- [ ] **Step 7: Create LinkPreviewBubbleView.swift**

Reference: `LinkPreviewView.swift` (lines 1–253 of existing file)

```swift
// NaarsCars/UI/Components/Messaging/Cells/LinkPreviewBubbleView.swift
import UIKit

/// Renders a link preview card with thumbnail, title, and domain.
final class LinkPreviewBubbleView: UIView {
    private let thumbnailView = UIImageView()
    private let titleLabel = UILabel()
    private let domainLabel = UILabel()
    private let chevron = UIImageView(image: UIImage(systemName: "chevron.right"))
    private let container = UIView()
    private var loadGeneration: UInt64 = 0
    private var linkURL: URL?
    private let showFullPreview: Bool

    init(frame: CGRect = .zero) {
        self.showFullPreview = UserDefaults.standard.bool(forKey: "messaging_showLinkPreviews")
        super.init(frame: frame)
        container.layer.cornerRadius = 12
        container.layer.borderWidth = 1
        container.layer.borderColor = UIColor.systemGray4.cgColor
        container.clipsToBounds = true
        addSubview(container)

        thumbnailView.contentMode = .scaleAspectFill
        thumbnailView.clipsToBounds = true
        container.addSubview(thumbnailView)

        titleLabel.font = .preferredFont(forTextStyle: .footnote).bold()
        titleLabel.numberOfLines = 2
        container.addSubview(titleLabel)

        domainLabel.font = .preferredFont(forTextStyle: .caption2)
        domainLabel.textColor = .secondaryLabel
        container.addSubview(domainLabel)

        chevron.tintColor = .secondaryLabel
        chevron.contentMode = .scaleAspectFit
        container.addSubview(chevron)

        addGestureRecognizer(UITapGestureRecognizer(target: self, action: #selector(openLink)))
    }

    required init?(coder: NSCoder) { fatalError() }

    func configure(url: URL, isFromCurrentUser: Bool) {
        loadGeneration &+= 1
        let gen = loadGeneration
        linkURL = url
        domainLabel.text = url.host
        titleLabel.text = nil
        thumbnailView.image = nil

        container.backgroundColor = isFromCurrentUser
            ? UIColor.white.withAlphaComponent(0.15)
            : UIColor.systemGray6

        guard showFullPreview else {
            // Compact mode — just show domain
            setNeedsLayout()
            return
        }

        Task { @MainActor in
            // Attempt to fetch link metadata via LinkPreviewService
            // (LinkPreviewService is the existing @MainActor class in LinkPreviewView.swift)
            guard self.loadGeneration == gen else { return }
            // For now, show compact. Full metadata integration in Layer 3.
            self.setNeedsLayout()
        }
    }

    @objc private func openLink() {
        guard let url = linkURL else { return }
        UIApplication.shared.open(url)
    }

    override func layoutSubviews() {
        super.layoutSubviews()
        container.frame = bounds
        if showFullPreview && thumbnailView.image != nil {
            thumbnailView.frame = CGRect(x: 0, y: 0, width: 60, height: bounds.height)
            titleLabel.frame = CGRect(x: 68, y: 8, width: bounds.width - 88, height: 32)
            domainLabel.frame = CGRect(x: 68, y: 42, width: bounds.width - 88, height: 16)
        } else {
            thumbnailView.frame = .zero
            let iconSize: CGFloat = 16
            let domainX: CGFloat = 12
            domainLabel.frame = CGRect(x: domainX, y: (bounds.height - 16) / 2, width: bounds.width - domainX - 28, height: 16)
        }
        chevron.frame = CGRect(x: bounds.width - 20, y: (bounds.height - 12) / 2, width: 12, height: 12)
    }

    override func sizeThatFits(_ size: CGSize) -> CGSize {
        if showFullPreview && thumbnailView.image != nil {
            return CGSize(width: min(280, size.width * 0.7), height: 64)
        }
        return CGSize(width: min(200, size.width * 0.5), height: 32)
    }

    func prepareForReuse() {
        loadGeneration &+= 1
        titleLabel.text = nil
        domainLabel.text = nil
        thumbnailView.image = nil
        linkURL = nil
    }
}

private extension UIFont {
    func bold() -> UIFont {
        guard let descriptor = fontDescriptor.withSymbolicTraits(.traitBold) else { return self }
        return UIFont(descriptor: descriptor, size: 0)
    }
}
```

- [ ] **Step 8: Create AvatarUIView.swift**

Reference: `AvatarView.swift` (existing SwiftUI component, ~144 lines)

```swift
// NaarsCars/UI/Components/Common/AvatarUIView.swift
import UIKit

/// UIKit avatar view — circular image with initials fallback.
final class AvatarUIView: UIView {
    private let imageView = UIImageView()
    private let initialsLabel = UILabel()
    private var loadGeneration: UInt64 = 0
    private var currentSize: CGFloat = 0

    override init(frame: CGRect) {
        super.init(frame: frame)
        clipsToBounds = true
        backgroundColor = .systemGray5
        imageView.contentMode = .scaleAspectFill
        addSubview(imageView)
        initialsLabel.textAlignment = .center
        initialsLabel.textColor = .white
        addSubview(initialsLabel)
    }

    required init?(coder: NSCoder) { fatalError() }

    func configure(imageUrl: String?, name: String, size: CGFloat) {
        currentSize = size
        layer.cornerRadius = size / 2

        // Initials fallback
        let parts = name.split(separator: " ")
        let initials: String
        if parts.count >= 2 {
            initials = String(parts[0].prefix(1) + parts[1].prefix(1)).uppercased()
        } else {
            initials = String(name.prefix(2)).uppercased()
        }
        initialsLabel.text = initials
        initialsLabel.font = .systemFont(ofSize: size * 0.4, weight: .medium)
        imageView.image = nil

        loadGeneration &+= 1
        let gen = loadGeneration

        guard let urlStr = imageUrl, !urlStr.isEmpty else { return }

        Task { @MainActor in
            if let img = await PersistentImageService.shared.getImage(for: urlStr) {
                guard self.loadGeneration == gen else { return }
                self.imageView.image = img
            }
        }
    }

    override func layoutSubviews() {
        super.layoutSubviews()
        imageView.frame = bounds
        initialsLabel.frame = bounds
    }

    func prepareForReuse() {
        loadGeneration &+= 1
        imageView.image = nil
        initialsLabel.text = nil
    }
}
```

- [ ] **Step 9: Add all files to Xcode project and build**

Add all 8 new files to the Xcode project target. Build to verify compilation. Note: `ReadReceiptView` references `AvatarUIView`, so both must be in the project.

Expected: BUILD SUCCEEDED (these files have no dependency on `MessageCellView` yet — the delegate protocol in `MessageCellConfig.swift` will produce a warning but not an error since it's a protocol, not a concrete type).

- [ ] **Step 10: Commit**

```bash
git add NaarsCars/UI/Components/Messaging/Cells/ NaarsCars/UI/Components/Common/AvatarUIView.swift
git commit -m "feat: add all UIKit cell subviews — system, unsent, read receipt, reaction badge, reply preview, date separator, link preview, avatar"
```

---

## Chunk 2: Layer 2 (MessageCellView Container + Gestures)

### Task 9: MessageCellView

**Files:**
- Create: `NaarsCars/UI/Components/Messaging/Cells/MessageCellView.swift`

This is the top-level container that composes all content views from Layer 1, handles layout, and owns gesture recognizers.

- [ ] **Step 1: Create MessageCellView.swift**

```swift
// NaarsCars/UI/Components/Messaging/Cells/MessageCellView.swift
import UIKit

/// Top-level UIView for rendering a message cell. Composes content subviews,
/// handles layout and gesture recognition. Replaces the SwiftUI MessageBubble.
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
    private var replyPreview: ReplyPreviewView?
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
                av.configure(imageUrl: msg.sender?.avatarUrl, name: msg.sender?.name ?? NSLocalizedString("messaging_deleted_user", comment: ""), size: 28)
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
            lbl.text = msg.sender?.name ?? NSLocalizedString("messaging_deleted_user", comment: "")
        }

        // Reply preview
        if config.showReplyPreview, let replyContext = msg.replyToMessage {
            let rp = replyPreview ?? {
                let v = ReplyPreviewView()
                addSubview(v)
                replyPreview = v
                return v
            }()
            rp.isHidden = false
            rp.configure(replyContext: replyContext, isFromCurrentUser: config.isFromCurrentUser)
            rp.onTap = { [weak self] id in
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
            view.configure(latitude: lat, longitude: lon, locationName: msg.locationName)
        } else if msg.imageUrl != nil || msg.localAttachmentPath != nil {
            let view = imageBubble ?? {
                let v = ImageBubbleView()
                addSubview(v)
                imageBubble = v
                return v
            }()
            view.isHidden = false
            view.configure(message: msg)
            view.onImageTap = { [weak self] url in
                guard let self, let config = self.config else { return }
                self.delegate?.messageCellDidTapImage(self, url: url)
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
        let rb = reactionBadge ?? {
            let v = ReactionBadgeView()
            addSubview(v)
            reactionBadge = v
            return v
        }()
        rb.configure(reactions: msg.reactions)
        rb.onTap = { [weak self] in
            guard let self, let config = self.config else { return }
            let currentUserId = AuthService.shared.currentUserId
            let hasReacted = msg.reactions?.reactions.values.contains { $0.contains(where: { $0 == currentUserId }) } ?? false
            if hasReacted {
                self.delegate?.messageCellDidTapReaction(self, message: config.message, reaction: nil)
            } else {
                self.delegate?.messageCellDidLongPress(self, message: config.message)
            }
        }
        rb.onLongPress = { [weak self] in
            guard let self, let config = self.config else { return }
            self.delegate?.messageCellDidTapReaction(self, message: config.message, reaction: "__details__")
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
                l.text = NSLocalizedString("messaging_edited", comment: "")
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
            rr.configure(
                message: config.message,
                totalParticipants: config.totalParticipants,
                isGroup: config.isGroupConversation,
                profiles: config.participantProfiles
            )
        }
    }

    private func showFailedRetry() {
        let lbl = failedRetryLabel ?? {
            let l = UILabel()
            l.font = .preferredFont(forTextStyle: .caption1)
            l.textColor = .systemRed
            l.text = "⚠ " + NSLocalizedString("messaging_not_sent_tap_to_retry", comment: "")
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

        // Content bubble
        let contentView = activeContentView()
        if let cv = contentView {
            let cvSize = cv.sizeThatFits(CGSize(width: maxBubbleWidth, height: .greatestFiniteMagnitude))
            let x = config.isFromCurrentUser
                ? bounds.width - cvSize.width
                : avatarSize + avatarSpacing
            cv.frame = CGRect(x: x, y: y, width: cvSize.width, height: cvSize.height)

            // Reaction badge
            if let rb = reactionBadge, !rb.isHidden {
                let rbSize = rb.sizeThatFits(.zero)
                let rbX = config.isFromCurrentUser ? cv.frame.minX : cv.frame.maxX - rbSize.width
                rb.frame = CGRect(x: rbX, y: cv.frame.minY - rbSize.height / 2, width: rbSize.width, height: rbSize.height)
            }

            y = cv.frame.maxY + 4
        }

        // Timestamp row
        if let ts = timestampLabel, !ts.isHidden {
            ts.sizeToFit()
            var rowX = config.isFromCurrentUser
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

        // Avatar (bottom-aligned with content)
        if let av = avatarView, !av.isHidden, config.isLastInSeries {
            let contentBottom = contentView?.frame.maxY ?? y
            av.frame = CGRect(x: 0, y: contentBottom - 28, width: 28, height: 28)
        }
    }

    private func activeContentView() -> UIView? {
        [textBubble, imageBubble, audioBubble, locationBubble, linkPreviewBubble]
            .compactMap { $0 }
            .first { !$0.isHidden }
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
        // Content
        if let cv = activeContentView() {
            height += cv.sizeThatFits(CGSize(width: maxBubbleWidth, height: .greatestFiniteMagnitude)).height + 4
        }
        // Timestamp
        if timestampLabel?.isHidden == false { height += 18 }
        // Failed
        if failedRetryLabel?.isHidden == false { height += 18 }
        // Padding
        let verticalPadding: CGFloat = config.isLastInSeries ? 12 : 2
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
        longPressGesture.require(toFail: panGesture) // Long-press cancels if pan starts
        addGestureRecognizer(longPressGesture)

        tapGesture = UITapGestureRecognizer(target: self, action: #selector(handleTap))
        tapGesture.require(toFail: panGesture)
        tapGesture.require(toFail: longPressGesture)
        addGestureRecognizer(tapGesture)
    }

    @objc private func handlePan(_ gr: UIPanGestureRecognizer) {
        guard let config else { return }
        let translation = gr.translation(in: self)
        let horizontal = abs(translation.x)
        let vertical = abs(translation.y)

        switch gr.state {
        case .changed:
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

            // Apply offset to content
            activeContentView()?.transform = CGAffineTransform(translationX: swipeOffset, y: 0)

        case .ended, .cancelled:
            if abs(swipeOffset) >= swipeThreshold {
                delegate?.messageCellDidSwipeToReply(self, message: config.message)
            }

            let animator = UIViewPropertyAnimator(duration: 0.3, dampingRatio: 0.7) {
                self.activeContentView()?.transform = .identity
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
        }
        let workItem = DispatchWorkItem { [weak self] in
            guard let self, let config = self.config, !config.isLastInSeries else { return }
            self.timestampLabel?.isHidden = true
            self.editedLabel?.isHidden = true
            self.readReceipt?.isHidden = true
            self.setNeedsLayout()
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
    func gestureRecognizerShouldBegin(_ gestureRecognizer: UIGestureRecognizer) -> Bool {
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
```

- [ ] **Step 2: Add to Xcode project and build**

Expected: BUILD SUCCEEDED. All subviews from Task 3–8 are referenced. The `MessageCellDelegate` protocol in `MessageCellConfig.swift` now has a concrete type to reference.

- [ ] **Step 3: Commit**

```bash
git add NaarsCars/UI/Components/Messaging/Cells/MessageCellView.swift
git commit -m "feat: add MessageCellView — UIKit cell container with composition, layout, and gestures"
```

---

## Chunk 3: Layer 3 (Collection View Integration Swap)

This is the performance-critical layer where `UIHostingConfiguration` is replaced with native UIKit cells.

### Task 10: Rewrite MessagesCollectionView

**Files:**
- Modify: `NaarsCars/UI/Components/Messaging/MessagesCollectionView.swift`

Replace the `UIHostingConfiguration` cell registration with native `MessageCellView` cells. Change the snapshot item type from `UUID` to `MessageListItem`. Wire `MessageCellDelegate` through the coordinator.

- [ ] **Step 1: Rewrite MessagesCollectionView.swift**

Read the current file thoroughly first (`NaarsCars/UI/Components/Messaging/MessagesCollectionView.swift`). The key changes:

1. Remove `messageCellContent: (Message, MessageCellConfiguration) -> AnyView` parameter
2. Add `participantProfiles`, `isGroupConversation`, `totalParticipants` parameters
3. Add delegate callback closures: `onLongPress`, `onSwipeReply`, `onImageTap`, `onReplyPreviewTap`, `onRetry`, `onReactionTap`
4. Change `MessageCollectionViewCell` to host a `MessageCellView` (not `UIHostingConfiguration`)
5. Change snapshot item type from `UUID` to `MessageListItem`
6. Add `DateSeparatorCell` registration
7. Coordinator conforms to `MessageCellDelegate`
8. Build `MessageCellConfig` in the cell registration closure from the coordinator's stored data

This is a complete rewrite of the file. Read the existing file first, then replace it entirely. Keep the same flipped-transform trick, diffable data source, debounced apply, scroll delegate, and prefetch.

The key difference in cell configuration:

```swift
// OLD (SwiftUI hosting):
cell.contentConfiguration = UIHostingConfiguration { swiftUIView }.margins(.all, 0)

// NEW (native UIKit):
let cellView = (cell as? MessageContentCell)?.messageCellView
let config = MessageCellConfig(
    message: message,
    isFromCurrentUser: message.fromId == AuthService.shared.currentUserId,
    showAvatar: isGroup && message.fromId != AuthService.shared.currentUserId,
    isFirstInSeries: cellConfig.isFirstInSeries,
    isLastInSeries: cellConfig.isLastInSeries,
    isGroupConversation: isGroup,
    totalParticipants: totalParticipants,
    participantProfiles: profiles,
    showReplyPreview: true,
    replySpine: replySpineForMessage(message),
    isHighlighted: false,
    shouldAnimate: false
)
cellView?.configure(with: config)
cellView?.delegate = self
```

- [ ] **Step 2: Build to verify**
- [ ] **Step 3: Commit**

```bash
git add NaarsCars/UI/Components/Messaging/MessagesCollectionView.swift
git commit -m "feat: replace UIHostingConfiguration with native UIKit cells in MessagesCollectionView"
```

### Task 11: Update ConversationDetailView

**Files:**
- Modify: `NaarsCars/Features/Messaging/Views/ConversationDetailView.swift`

Update the `messagesListView` to pass raw data instead of the `messageCellContent` closure. Remove dead code related to cell building.

- [ ] **Step 1: Update MessagesCollectionView usage**

In the `messagesListView` computed property, replace the `MessagesCollectionView(...)` call. Remove the `messageCellContent` closure parameter. Add the new parameters and callbacks.

- [ ] **Step 2: Remove dead code**

Remove `createMessageBubble()`, `messageBubbleSnapshot()`, `replyChainContextForMessage()`, `replyChainContext(at:)` helper functions. These are no longer called.

- [ ] **Step 3: Build and test**

Build the project. Launch the app, open a conversation. Verify:
- All message types render correctly
- Scroll performance is smooth
- Keyboard appearance does not cause frame drops
- Messages load from local cache and from network

- [ ] **Step 4: Commit**

```bash
git add NaarsCars/Features/Messaging/Views/ConversationDetailView.swift
git commit -m "feat: wire ConversationDetailView to native UIKit cells, remove SwiftUI cell building code"
```

---

## Chunk 4: Layer 4 (Interaction Overlay)

### Task 12: OverlayAction Enum + ReactionBarView

**Files:**
- Create: `NaarsCars/UI/Components/Messaging/Overlay/OverlayAction.swift`
- Create: `NaarsCars/UI/Components/Messaging/Overlay/ReactionBarView.swift`

- [ ] **Step 1: Create OverlayAction.swift**

```swift
// NaarsCars/UI/Components/Messaging/Overlay/OverlayAction.swift
import Foundation

/// Actions the user can take from the message interaction overlay.
enum OverlayAction {
    case react(String)
    case removeReaction
    case reply
    case copy
    case edit
    case unsend
    case deleteForMe
    case report
}
```

- [ ] **Step 2: Create ReactionBarView.swift**

Horizontal scrolling reaction strip with 21 reactions.

```swift
// NaarsCars/UI/Components/Messaging/Overlay/ReactionBarView.swift
import UIKit

/// Horizontal scrolling reaction bar (iMessage Tapback-style).
final class ReactionBarView: UIView {
    private let scrollView = UIScrollView()
    private let stackView = UIStackView()
    private var selectedReaction: String?
    var onReact: ((String) -> Void)?
    var onRemoveReaction: (() -> Void)?

    private let allReactions = [
        "❤️", "👍", "👎", "😂", "‼️", "❓",
        "🔥", "😍", "😢", "😮", "😡", "🎉",
        "🤔", "👀", "🙏", "💯", "🤣", "😊",
        "👏", "💪", "✨"
    ]

    override init(frame: CGRect) {
        super.init(frame: frame)
        backgroundColor = .clear
        let blur = UIVisualEffectView(effect: UIBlurEffect(style: .systemUltraThinMaterial))
        blur.layer.cornerRadius = 24
        blur.clipsToBounds = true
        addSubview(blur)
        blur.translatesAutoresizingMaskIntoConstraints = false
        NSLayoutConstraint.activate([
            blur.topAnchor.constraint(equalTo: topAnchor),
            blur.bottomAnchor.constraint(equalTo: bottomAnchor),
            blur.leadingAnchor.constraint(equalTo: leadingAnchor),
            blur.trailingAnchor.constraint(equalTo: trailingAnchor),
        ])

        scrollView.showsHorizontalScrollIndicator = false
        blur.contentView.addSubview(scrollView)

        stackView.axis = .horizontal
        stackView.spacing = 4
        stackView.alignment = .center
        scrollView.addSubview(stackView)

        for emoji in allReactions {
            let btn = UIButton(type: .system)
            btn.setTitle(emoji, for: .normal)
            btn.titleLabel?.font = .systemFont(ofSize: 24)
            btn.addTarget(self, action: #selector(reactionTapped(_:)), for: .touchUpInside)
            btn.widthAnchor.constraint(equalToConstant: 40).isActive = true
            btn.heightAnchor.constraint(equalToConstant: 40).isActive = true
            stackView.addArrangedSubview(btn)
        }
    }

    required init?(coder: NSCoder) { fatalError() }

    func configure(currentReaction: String?) {
        self.selectedReaction = currentReaction
        for case let btn as UIButton in stackView.arrangedSubviews {
            let isSelected = btn.title(for: .normal) == currentReaction
            btn.transform = isSelected ? CGAffineTransform(scaleX: 1.15, y: 1.15) : .identity
            btn.backgroundColor = isSelected ? .systemGray5 : .clear
            btn.layer.cornerRadius = 20
        }
    }

    @objc private func reactionTapped(_ sender: UIButton) {
        guard let emoji = sender.title(for: .normal) else { return }
        HapticManager.selectionChanged()
        if emoji == selectedReaction {
            onRemoveReaction?()
        } else {
            onReact?(emoji)
        }
    }

    override func layoutSubviews() {
        super.layoutSubviews()
        scrollView.frame = bounds.insetBy(dx: 4, dy: 0)
        let contentSize = stackView.systemLayoutSizeFitting(UIView.layoutFittingCompressedSize)
        stackView.frame = CGRect(origin: .zero, size: contentSize)
        scrollView.contentSize = contentSize
    }

    override func sizeThatFits(_ size: CGSize) -> CGSize {
        CGSize(width: min(size.width - 32, 320), height: 48)
    }
}
```

- [ ] **Step 3: Build, commit**

```bash
git add NaarsCars/UI/Components/Messaging/Overlay/
git commit -m "feat: add OverlayAction enum and ReactionBarView for message interaction overlay"
```

### Task 13: OverlayActionListView + MessageOverlayController

**Files:**
- Create: `NaarsCars/UI/Components/Messaging/Overlay/OverlayActionListView.swift`
- Create: `NaarsCars/UI/Components/Messaging/Overlay/MessageOverlayController.swift`

- [ ] **Step 1: Create OverlayActionListView.swift**

Conditional action rows based on message ownership and state. Reference: `MessageInteractionOverlay.swift` (existing, 161 lines).

- [ ] **Step 2: Create MessageOverlayController.swift**

UIViewController with blur backdrop, positioned snapshot, reaction bar above, action list below. Adaptive positioning (clips safe area → flip layout). Entrance/dismissal animations. `onAction` completion handler.

Key coordinate approach: The source frame passed in is already in window coordinates (captured via `cell.convert(cell.bounds, to: nil)`). The snapshot view is placed at that frame, then scaled 1.02× during the entrance animation.

- [ ] **Step 3: Wire long-press in MessagesCollectionView coordinator**

Update the coordinator's `messageCellDidLongPress` to:
1. Get the cell's window-space frame via `cell.convert(cell.bounds, to: nil)`
2. Snapshot the cell
3. Call the `onLongPress` closure with the message, frame, and snapshot

Update `ConversationDetailView` to present `MessageOverlayController` from the `onLongPress` callback, with the `OverlayAction` handler that translates actions to state mutations.

- [ ] **Step 4: Build, test long-press on all message types**
- [ ] **Step 5: Commit**

```bash
git add NaarsCars/UI/Components/Messaging/Overlay/
git commit -m "feat: add MessageOverlayController with reaction bar, action list, and adaptive positioning"
```

---

## Chunk 5: Layer 5 (Thread View + Cleanup)

### Task 14: Extract MessageThreadViewModel

**Files:**
- Create: `NaarsCars/Features/Messaging/ViewModels/MessageThreadViewModel.swift`
- Modify: `NaarsCars/Features/Messaging/Views/ConversationDetailView.swift` — remove inline definition

- [ ] **Step 1: Extract MessageThreadViewModel**

Copy `MessageThreadViewModel` class from `ConversationDetailView.swift` (lines ~1214–1268) to its own file. No logic changes.

- [ ] **Step 2: Remove from ConversationDetailView.swift**
- [ ] **Step 3: Build, commit**

```bash
git add NaarsCars/Features/Messaging/ViewModels/MessageThreadViewModel.swift
git commit -m "refactor: extract MessageThreadViewModel to its own file"
```

### Task 15: MessageThreadViewController + Representable

**Files:**
- Create: `NaarsCars/Features/Messaging/Views/MessageThreadViewController.swift`
- Create: `NaarsCars/Features/Messaging/Views/MessageThreadRepresentable.swift`
- Modify: `NaarsCars/Features/Messaging/Views/ConversationDetailView.swift` — update `.fullScreenCover` to use representable

- [ ] **Step 1: Create MessageThreadViewController.swift**

UIViewController with:
- UICollectionView (same layout as main list, but NOT flipped — normal top-to-bottom)
- Same cell registrations (MessageContentCell, DateSeparatorCell)
- Header: parent message as a cell
- MessageInputBar embedded via child UIHostingController at the bottom
- Keyboard observation via `UIResponder.keyboardWillShowNotification` to adjust `additionalSafeAreaInsets`
- Combine subscriptions to `MessageThreadViewModel.$replies` and `$parentMessage`
- Conforms to `MessageCellDelegate`

- [ ] **Step 2: Create MessageThreadRepresentable.swift**

```swift
// NaarsCars/Features/Messaging/Views/MessageThreadRepresentable.swift
import SwiftUI

struct MessageThreadRepresentable: UIViewControllerRepresentable {
    let conversationId: UUID
    let parentMessageId: UUID
    let conversationViewModel: ConversationDetailViewModel
    let isGroup: Bool
    let totalParticipants: Int
    let participantProfiles: [Profile]

    func makeUIViewController(context: Context) -> MessageThreadViewController {
        MessageThreadViewController(
            conversationId: conversationId,
            parentMessageId: parentMessageId,
            conversationViewModel: conversationViewModel,
            isGroup: isGroup,
            totalParticipants: totalParticipants,
            participantProfiles: participantProfiles
        )
    }

    func updateUIViewController(_ uiViewController: MessageThreadViewController, context: Context) {}
}
```

- [ ] **Step 3: Update ConversationDetailView**

Replace the `.fullScreenCover` that presents `MessageThreadView` with `MessageThreadRepresentable`.

- [ ] **Step 4: Build, test thread view**
- [ ] **Step 5: Commit**

```bash
git add NaarsCars/Features/Messaging/Views/MessageThread*.swift
git commit -m "feat: add MessageThreadViewController with UIKit cells and keyboard-aware input bar"
```

### Task 16: Delete Dead Code

**Files:**
- Delete: `NaarsCars/UI/Components/Messaging/MessageBubble.swift`
- Delete: `NaarsCars/UI/Components/Messaging/MessageInteractionOverlay.swift`
- Delete: `NaarsCars/UI/Components/Messaging/ReactionPicker.swift`
- Modify: `NaarsCars/Features/Messaging/Views/ConversationDetailView.swift` — remove remaining dead code

- [ ] **Step 1: Delete MessageBubble.swift (1,356 lines)**

Remove the file from the project and filesystem.

- [ ] **Step 2: Delete MessageInteractionOverlay.swift (161 lines)**

This also deletes the `BlurView` defined inside it. Verify no other files reference `BlurView` first.

- [ ] **Step 3: Delete ReactionPicker.swift (92 lines)**

- [ ] **Step 4: Clean up ConversationDetailView.swift**

Remove:
- `showInteractionOverlay` and `interactionMessage` state variables
- `interactionOverlayContent` computed property
- The ZStack overlay layer with `BlurView`
- `ReplyThreadSpineView` nested struct
- `DateSeparatorView` nested struct
- `MessageThreadView` struct
- `ThreadParent` struct
- Any remaining helper functions only used by the deleted code

- [ ] **Step 5: Build the full project**

Run: `xcodebuild -project NaarsCars/NaarsCars.xcodeproj -scheme NaarsCars -configuration Debug -destination 'generic/platform=iOS' build`
Expected: BUILD SUCCEEDED with no warnings from the messaging module.

- [ ] **Step 6: Run existing tests**

Run: `xcodebuild test -project NaarsCars/NaarsCars.xcodeproj -scheme NaarsCars -destination 'platform=iOS Simulator,name=iPhone 16'`
Expected: All existing tests pass. No messaging-related test failures.

- [ ] **Step 7: Commit**

```bash
git add -A
git commit -m "chore: delete MessageBubble, MessageInteractionOverlay, ReactionPicker — migration complete"
```

---

## Final Verification Checklist

After all tasks are complete, manually verify on device:

- [ ] **Text messages** — sent and received, with and without tails
- [ ] **Image messages** — remote, local (uploading), cache hit vs miss
- [ ] **Audio messages** — play/pause, waveform progress, duration display
- [ ] **Location messages** — map snapshot, pin, tap opens Maps
- [ ] **Link previews** — full card and compact inline, tap opens Safari
- [ ] **System messages** — group created, member added/removed, name changed
- [ ] **Unsent messages** — both sent and received variants
- [ ] **Reactions** — add, remove, badge display, details sheet
- [ ] **Read receipts** — sending, sent, delivered, read (DM and group)
- [ ] **Reply preview** — tap scrolls to original, accent bar styling
- [ ] **Swipe-to-reply** — both directions, haptic at threshold, spring release
- [ ] **Long-press overlay** — blur, positioned snapshot, reaction bar, all action buttons
- [ ] **Thread view** — parent message, replies, send reply, keyboard handling
- [ ] **Keyboard appearance** — frame drops should be <50ms (down from 700-1600ms)
- [ ] **Group conversations** — sender names, avatars, group read receipts
- [ ] **DM conversations** — no avatars, DM read receipts
- [ ] **Failed messages** — retry tap, error styling
- [ ] **Scroll performance** — smooth scrolling through 50+ messages
- [ ] **Dark mode** — all colors adapt correctly
