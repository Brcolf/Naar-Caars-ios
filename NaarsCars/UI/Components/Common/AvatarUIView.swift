//
//  AvatarUIView.swift
//  NaarsCars
//
//  UIKit circular avatar with async image loading and initials fallback
//

import UIKit

/// Pure UIKit circular avatar — async image via PersistentImageService, initials fallback.
final class AvatarUIView: UIView {

    // MARK: - Subviews

    private let imageView = UIImageView()
    private let initialsLabel = UILabel()

    // MARK: - Generation counter (cell-reuse safety)

    private var loadGeneration: UInt64 = 0

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
        clipsToBounds = true

        imageView.contentMode = .scaleAspectFill
        imageView.clipsToBounds = true
        addSubview(imageView)

        initialsLabel.textAlignment = .center
        initialsLabel.textColor = .white
        initialsLabel.adjustsFontSizeToFitWidth = true
        initialsLabel.minimumScaleFactor = 0.5
        addSubview(initialsLabel)
    }

    // MARK: - Layout

    override func layoutSubviews() {
        super.layoutSubviews()
        let b = bounds
        imageView.frame = b
        initialsLabel.frame = b
        layer.cornerRadius = b.width / 2
        imageView.layer.cornerRadius = b.width / 2
        initialsLabel.font = .systemFont(ofSize: b.width * 0.4, weight: .semibold)
    }

    override func sizeThatFits(_ size: CGSize) -> CGSize {
        return CGSize(width: size.width, height: size.width) // always square
    }

    // MARK: - Configure

    func configure(imageUrl: String?, name: String, size: CGFloat) {
        frame.size = CGSize(width: size, height: size)

        let initials = Self.initials(from: name)
        initialsLabel.text = initials
        backgroundColor = UIColor.naarsPrimary

        isAccessibilityElement = true
        accessibilityLabel = name
        accessibilityTraits = .image

        loadGeneration &+= 1
        let gen = loadGeneration

        if let urlString = imageUrl, !urlString.isEmpty {
            imageView.isHidden = false
            initialsLabel.isHidden = true
            imageView.image = nil

            Task { [weak self] in
                let img = await PersistentImageService.shared.getImage(for: urlString)
                guard let self, self.loadGeneration == gen else { return }
                if let img {
                    self.imageView.image = img
                } else {
                    self.imageView.isHidden = true
                    self.initialsLabel.isHidden = false
                }
            }
        } else {
            imageView.isHidden = true
            imageView.image = nil
            initialsLabel.isHidden = false
        }
    }

    // MARK: - Reuse

    func prepareForReuse() {
        loadGeneration &+= 1
        imageView.image = nil
        imageView.isHidden = true
        initialsLabel.isHidden = false
        initialsLabel.text = nil
    }

    // MARK: - Helpers

    private static func initials(from name: String) -> String {
        let parts = name.split(separator: " ")
        if parts.count >= 2 {
            return (String(parts[0].prefix(1)) + String(parts[parts.count - 1].prefix(1))).uppercased()
        }
        return String(name.prefix(2)).uppercased()
    }
}
