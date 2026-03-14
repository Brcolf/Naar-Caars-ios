import UIKit

enum TapbackArtwork {
    /// Returns true if this reaction should be rendered as custom "HA HA" artwork instead of emoji.
    static func isHaha(_ reaction: String) -> Bool {
        reaction == "😂"
    }

    /// Renders the custom "HA HA" artwork at the specified point size.
    /// Uses `UIGraphicsImageRenderer` with screen scale for crisp rendering on retina displays.
    static func hahaImage(pointSize: CGFloat) -> UIImage {
        let font = UIFont.systemFont(ofSize: pointSize * 0.45, weight: .black)
        let text = "HA\nHA"
        let paragraphStyle = NSMutableParagraphStyle()
        paragraphStyle.alignment = .center
        paragraphStyle.lineSpacing = -pointSize * 0.08
        let attributes: [NSAttributedString.Key: Any] = [
            .font: font,
            .foregroundColor: UIColor.systemBlue,
            .paragraphStyle: paragraphStyle
        ]
        let attrString = NSAttributedString(string: text, attributes: attributes)
        let textSize = attrString.boundingRect(
            with: CGSize(width: pointSize, height: .greatestFiniteMagnitude),
            options: [.usesLineFragmentOrigin],
            context: nil
        ).size

        let canvasSize = CGSize(
            width: ceil(max(textSize.width, pointSize * 0.8)),
            height: ceil(max(textSize.height, pointSize))
        )
        let renderer = UIGraphicsImageRenderer(size: canvasSize)
        let image = renderer.image { _ in
            let drawRect = CGRect(
                x: (canvasSize.width - textSize.width) / 2,
                y: (canvasSize.height - textSize.height) / 2,
                width: textSize.width,
                height: textSize.height
            )
            attrString.draw(in: drawRect)
        }
        return image.withRenderingMode(.alwaysOriginal)
    }
}

// MARK: - Temporary compatibility (remove after Tasks 8, 9, 12)
enum TapbackGlyph {
    static func image(for reaction: String, pointSize: CGFloat) -> UIImage? {
        guard TapbackArtwork.isHaha(reaction) else { return nil }
        return TapbackArtwork.hahaImage(pointSize: pointSize)
    }
}
