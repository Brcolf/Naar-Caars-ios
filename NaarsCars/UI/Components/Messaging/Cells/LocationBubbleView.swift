//
//  LocationBubbleView.swift
//  NaarsCars
//
//  UIKit location bubble — map snapshot + pin overlay + location name
//

import UIKit
import MapKit

/// Pure UIKit location bubble with MapSnapshotCache and generation counter.
final class LocationBubbleView: MessageBubbleContentView {

    // MARK: - Subviews

    private let mapImageView = UIImageView()
    private let pinImageView = UIImageView()
    private let spinner = UIActivityIndicatorView(style: .medium)
    private let nameContainer = UIView()
    private let pinIconView = UIImageView()
    private let nameLabel = UILabel()

    // MARK: - State

    private var loadGeneration: UInt64 = 0
    private var latitude: Double = 0
    private var longitude: Double = 0
    /// True between configure() and prepareForReuse(), i.e. while the coordinate is real.
    private var isConfigured = false

    // MARK: - Constants

    private let mapWidth: CGFloat = 200
    private let mapHeight: CGFloat = 120
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
        layer.borderWidth = 1
        layer.borderColor = UIColor.systemGray4.cgColor

        mapImageView.contentMode = .scaleAspectFill
        mapImageView.clipsToBounds = true
        mapImageView.backgroundColor = .systemGray5
        addSubview(mapImageView)

        let pinConfig = UIImage.SymbolConfiguration(pointSize: 28, weight: .bold)
        pinImageView.image = UIImage(systemName: "mappin.circle.fill", withConfiguration: pinConfig)
        pinImageView.tintColor = .systemRed
        pinImageView.layer.shadowColor = UIColor.black.cgColor
        pinImageView.layer.shadowOpacity = 0.25
        pinImageView.layer.shadowOffset = CGSize(width: 0, height: 2)
        pinImageView.layer.shadowRadius = 2
        addSubview(pinImageView)

        spinner.hidesWhenStopped = true
        addSubview(spinner)

        nameContainer.backgroundColor = .secondarySystemBackground
        addSubview(nameContainer)

        let locConfig = UIImage.SymbolConfiguration(textStyle: .footnote)
        pinIconView.image = UIImage(systemName: "location.fill", withConfiguration: locConfig)
        pinIconView.tintColor = UIColor.naarsPrimary
        nameContainer.addSubview(pinIconView)

        nameLabel.font = .preferredFont(forTextStyle: .footnote)
        nameLabel.textColor = .label
        nameLabel.numberOfLines = 2
        nameContainer.addSubview(nameLabel)

        let tap = UITapGestureRecognizer(target: self, action: #selector(openInMaps))
        addGestureRecognizer(tap)
    }

    // MARK: - Configure

    func configure(latitude: Double, longitude: Double, name: String?) {
        self.latitude = latitude
        self.longitude = longitude
        nameLabel.text = name ?? "messaging_shared_location".localized
        isConfigured = true

        isAccessibilityElement = true
        accessibilityLabel = nameLabel.text
        accessibilityTraits = .button
        accessibilityHint = "accessibility_tap_to_open_maps".localized

        mapImageView.image = nil
        spinner.startAnimating()
        loadSnapshot()

        setNeedsLayout()
    }

    /// Loads the map image for the current coordinate in the current appearance. The cache is
    /// keyed by interface style, so a map rendered in light mode is not reused in dark mode.
    private func loadSnapshot() {
        loadGeneration &+= 1
        let gen = loadGeneration
        let coord = CLLocationCoordinate2D(latitude: latitude, longitude: longitude)
        let style = traitCollection.userInterfaceStyle

        Task { [weak self] in
            let img = await MapSnapshotCache.shared.snapshot(for: coord, style: style)
            guard let self, self.loadGeneration == gen else { return }
            self.mapImageView.image = img
            self.spinner.stopAnimating()
        }
    }

    // MARK: - Layout

    override func layoutSubviews() {
        super.layoutSubviews()
        let b = bounds
        let nameHeight: CGFloat = 36
        mapImageView.frame = CGRect(x: 0, y: 0, width: b.width, height: b.height - nameHeight)

        pinImageView.sizeToFit()
        pinImageView.center = CGPoint(x: mapImageView.bounds.midX, y: mapImageView.bounds.midY)
        spinner.center = pinImageView.center

        nameContainer.frame = CGRect(x: 0, y: b.height - nameHeight, width: b.width, height: nameHeight)

        let iconSize: CGFloat = 16
        pinIconView.frame = CGRect(x: 10, y: (nameHeight - iconSize) / 2, width: iconSize, height: iconSize)
        let labelX = pinIconView.frame.maxX + 6
        nameLabel.frame = CGRect(x: labelX, y: 0, width: b.width - labelX - 10, height: nameHeight)
    }

    override func sizeThatFits(_ size: CGSize) -> CGSize {
        return CGSize(width: mapWidth, height: mapHeight + 36)
    }

    // MARK: - Reuse

    func prepareForReuse() {
        loadGeneration &+= 1
        mapImageView.image = nil
        spinner.stopAnimating()
        nameLabel.text = nil
        isConfigured = false
    }

    // MARK: - Actions

    @objc private func openInMaps() {
        // `ll` alone only centres the map. With `q` Maps drops a pin labelled with the shared
        // place, so directions to the pickup point are one tap away.
        var components = URLComponents(string: "https://maps.apple.com/")
        let name = nameLabel.text ?? ""
        let label = name.isEmpty ? "messaging_shared_location".localized : name
        components?.queryItems = [
            URLQueryItem(name: "ll", value: "\(latitude),\(longitude)"),
            URLQueryItem(name: "q", value: label)
        ]
        guard let url = components?.url else { return }
        if UIApplication.shared.canOpenURL(url) {
            Task { @MainActor in
                await UIApplication.shared.open(url)
            }
        }
    }

    // MARK: - Trait changes

    override func traitCollectionDidChange(_ previousTraitCollection: UITraitCollection?) {
        super.traitCollectionDidChange(previousTraitCollection)
        if traitCollection.hasDifferentColorAppearance(comparedTo: previousTraitCollection) {
            layer.borderColor = UIColor.systemGray4.cgColor
        }
        // Light / dark switch while the bubble is on screen: fetch the map for the new style.
        if isConfigured, let previous = previousTraitCollection,
           previous.userInterfaceStyle != traitCollection.userInterfaceStyle {
            loadSnapshot()
        }
    }
}
