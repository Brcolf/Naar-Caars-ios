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

    /// Configure with a remote URL string.
    func configure(remoteUrl: String, onTap: ((URL) -> Void)? = nil) {
        self.onTap = onTap
        self.imageURL = URL(string: remoteUrl)

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

    /// Configure with a local attachment path.
    func configure(localPath: String, onTap: ((URL) -> Void)? = nil) {
        self.onTap = onTap
        let fileURL = LocalAttachmentStorage.fileURL(for: localPath)
        self.imageURL = fileURL

        if let data = try? Data(contentsOf: fileURL), let img = UIImage(data: data) {
            showImage(img)
        } else {
            showError()
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
    }

    private func showError() {
        imageView.image = nil
        imageView.isHidden = true
        retryImageView.isHidden = false
        spinner.stopAnimating()
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
        let side = min(size.width, maxSize)
        return CGSize(width: side, height: side)
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
    }

    // MARK: - Tap

    @objc private func handleTap() {
        guard let url = imageURL else { return }
        onTap?(url)
    }
}
