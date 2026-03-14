//
//  ImageBubbleView.swift
//  NaarsCars
//
//  UIKit image bubble — async loading via PersistentImageService + local fallback
//

import UIKit

/// Pure UIKit image bubble with generation-counter cell-reuse safety.
final class ImageBubbleView: UIView {

    // MARK: - Subviews

    private let imageView = UIImageView()
    private let spinner = UIActivityIndicatorView(style: .medium)
    private let retryImageView = UIImageView()

    // MARK: - State

    private var loadGeneration: UInt64 = 0
    private var onTap: ((URL) -> Void)?
    private var imageURL: URL?
    private var lastLocalPath: String?
    private var lastRemoteUrl: String?
    private var imageWidth: Int?
    private var imageHeight: Int?

    // MARK: - Constants

    private let maxSize: CGFloat = 220
    private let cornerRad: CGFloat = 18

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
        layer.cornerRadius = cornerRad
        clipsToBounds = true
        backgroundColor = .systemGray5

        imageView.contentMode = .scaleAspectFill
        imageView.clipsToBounds = true
        addSubview(imageView)

        spinner.hidesWhenStopped = true
        addSubview(spinner)

        let retryConfig = UIImage.SymbolConfiguration(pointSize: 24, weight: .medium)
        retryImageView.image = UIImage(systemName: "arrow.clockwise", withConfiguration: retryConfig)
        retryImageView.tintColor = .secondaryLabel
        retryImageView.isHidden = true
        addSubview(retryImageView)

        let tap = UITapGestureRecognizer(target: self, action: #selector(handleTap))
        addGestureRecognizer(tap)
    }

    // MARK: - Configure

    /// Configure with a remote URL string and optional image dimensions for aspect-ratio sizing.
    func configure(remoteUrl: String, imageWidth: Int?, imageHeight: Int?, onTap: ((URL) -> Void)? = nil) {
        self.imageWidth = imageWidth
        self.imageHeight = imageHeight
        configure(remoteUrl: remoteUrl, onTap: onTap)
    }

    /// Configure with a remote URL string.
    func configure(remoteUrl: String, onTap: ((URL) -> Void)? = nil) {
        self.onTap = onTap

        // Skip redundant load — same URL already displayed
        if remoteUrl == lastRemoteUrl && imageView.image != nil && !imageView.isHidden {
            return
        }

        self.imageURL = URL(string: remoteUrl)
        self.lastRemoteUrl = remoteUrl
        self.lastLocalPath = nil

        showLoading()

        loadGeneration &+= 1
        let gen = loadGeneration

        Task { [weak self] in
            let img = await PersistentImageService.shared.getImage(for: remoteUrl)
            guard let self, self.loadGeneration == gen else { return }
            if let img {
                self.showImage(img)
            } else {
                self.showError()
            }
        }
    }

    /// Configure with a local attachment path and optional image dimensions for aspect-ratio sizing.
    func configure(localPath: String, imageWidth: Int?, imageHeight: Int?, onTap: ((URL) -> Void)? = nil) {
        self.imageWidth = imageWidth
        self.imageHeight = imageHeight
        configure(localPath: localPath, onTap: onTap)
    }

    /// Configure with a local attachment path.
    func configure(localPath: String, onTap: ((URL) -> Void)? = nil) {
        self.onTap = onTap

        // Skip redundant load — same path already displayed
        if localPath == lastLocalPath && imageView.image != nil && !imageView.isHidden {
            return
        }

        let fileURL = LocalAttachmentStorage.fileURL(for: localPath)
        self.imageURL = fileURL
        self.lastLocalPath = localPath
        self.lastRemoteUrl = nil

        showLoading()

        loadGeneration &+= 1
        let gen = loadGeneration

        Task.detached(priority: .userInitiated) { [weak self] in
            let img: UIImage? = {
                guard let data = try? Data(contentsOf: fileURL) else { return nil }
                return UIImage(data: data)
            }()
            await MainActor.run {
                guard let self, self.loadGeneration == gen else { return }
                if let img {
                    self.showImage(img)
                } else {
                    self.showError()
                }
            }
        }
    }

    // MARK: - States

    private func showLoading() {
        imageView.image = nil
        imageView.isHidden = true
        retryImageView.isHidden = true
        spinner.startAnimating()
    }

    private func showImage(_ image: UIImage) {
        imageView.image = image
        imageView.isHidden = false
        retryImageView.isHidden = true
        spinner.stopAnimating()

        isAccessibilityElement = true
        accessibilityLabel = NSLocalizedString("messaging_photo", comment: "")
        accessibilityTraits = [.image, .button]
        accessibilityHint = NSLocalizedString("accessibility_tap_to_view", comment: "")
    }

    private func showError() {
        imageView.image = nil
        imageView.isHidden = true
        retryImageView.isHidden = false
        spinner.stopAnimating()

        isAccessibilityElement = true
        accessibilityLabel = NSLocalizedString("messaging_image_failed", comment: "")
        accessibilityTraits = .button
        accessibilityHint = NSLocalizedString("accessibility_tap_to_retry", comment: "")
    }

    // MARK: - Layout

    override func layoutSubviews() {
        super.layoutSubviews()
        let b = bounds
        imageView.frame = b
        spinner.center = CGPoint(x: b.midX, y: b.midY)
        retryImageView.sizeToFit()
        retryImageView.center = CGPoint(x: b.midX, y: b.midY)
    }

    override func sizeThatFits(_ size: CGSize) -> CGSize {
        guard let w = imageWidth, let h = imageHeight, w > 0, h > 0 else {
            // Legacy fallback: square
            let side = min(size.width, maxSize)
            return CGSize(width: side, height: side)
        }
        let aspectRatio = CGFloat(h) / CGFloat(w)
        var width = min(CGFloat(w), min(size.width, maxSize))
        var height = width * aspectRatio
        // Cap height at 300pt — but recalculate width to maintain aspect ratio
        if height > 300 {
            height = 300
            width = height / aspectRatio
        }
        return CGSize(width: width, height: height)
    }

    // MARK: - Reuse

    func prepareForReuse() {
        loadGeneration &+= 1
        imageView.image = nil
        imageView.isHidden = true
        retryImageView.isHidden = true
        spinner.stopAnimating()
        onTap = nil
        imageURL = nil
        lastLocalPath = nil
        lastRemoteUrl = nil
        imageWidth = nil
        imageHeight = nil
    }

    // MARK: - Tap

    @objc private func handleTap() {
        // If in error state, retry the load instead of opening the viewer
        if !retryImageView.isHidden {
            retryLoad()
            return
        }
        guard let url = imageURL else { return }
        onTap?(url)
    }

    private func retryLoad() {
        if let remoteUrl = lastRemoteUrl {
            configure(remoteUrl: remoteUrl, imageWidth: imageWidth, imageHeight: imageHeight, onTap: onTap)
        } else if let localPath = lastLocalPath {
            configure(localPath: localPath, imageWidth: imageWidth, imageHeight: imageHeight, onTap: onTap)
        }
    }
}
