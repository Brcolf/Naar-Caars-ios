import SwiftUI

public struct SectionHighlightModifier: ViewModifier {
    public let isHighlighted: Bool

    public func body(content: Content) -> some View {
        content
            .background(
                RoundedRectangle(cornerRadius: 12)
                    .fill(isHighlighted ? Color.naarsWarning.opacity(0.12) : Color.clear)
            )
            .overlay(
                RoundedRectangle(cornerRadius: 12)
                    .stroke(isHighlighted ? Color.naarsWarning.opacity(0.6) : Color.clear, lineWidth: 2)
            )
    }
}

extension View {
    public func requestHighlight(_ isHighlighted: Bool) -> some View {
        modifier(SectionHighlightModifier(isHighlighted: isHighlighted))
    }
}

