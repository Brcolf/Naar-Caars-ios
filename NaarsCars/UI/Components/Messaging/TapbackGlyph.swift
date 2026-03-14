import UIKit

enum TapbackGlyph {
    private static let mapping: [(emoji: String, symbol: String, color: UIColor)] = [
        ("\u{2764}\u{FE0F}", "heart.fill",            .systemRed),
        ("\u{1F44D}",        "hand.thumbsup.fill",    .systemYellow),
        ("\u{1F44E}",        "hand.thumbsdown.fill",  .systemGray),
        ("\u{1F602}",        "face.smiling",          .systemGreen),
        ("\u{203C}\u{FE0F}", "exclamationmark.2",     .systemOrange),
        ("\u{2753}",         "questionmark",           .systemPurple),
    ]

    static func image(for reaction: String, pointSize: CGFloat) -> UIImage? {
        guard let entry = mapping.first(where: { $0.emoji == reaction }) else { return nil }
        let config = UIImage.SymbolConfiguration(pointSize: pointSize, weight: .medium)
        guard let symbol = UIImage(systemName: entry.symbol, withConfiguration: config) else { return nil }
        return symbol.withTintColor(entry.color, renderingMode: .alwaysOriginal)
    }
}
