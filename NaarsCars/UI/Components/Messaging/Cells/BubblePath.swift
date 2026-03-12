//
//  BubblePath.swift
//  NaarsCars
//
//  CGPath factory for iMessage-style bubble shape — used by UIKit cell views
//

import UIKit

/// Generates a CGPath for an iMessage-style chat bubble with optional tail.
enum BubblePath {

    /// Create a CGPath for the bubble background.
    /// - Parameters:
    ///   - rect: The bounding rect of the bubble.
    ///   - isFromCurrentUser: Right-aligned with tail on bottom-right when true.
    ///   - showTail: Whether to show the tail (last message in series).
    /// - Returns: A CGPath suitable for a CAShapeLayer.
    static func make(in rect: CGRect, isFromCurrentUser: Bool, showTail: Bool) -> CGPath {
        let cornerRadius: CGFloat = 18
        let tailWidth: CGFloat = 6
        let tailHeight: CGFloat = 8

        let path = CGMutablePath()

        if showTail {
            if isFromCurrentUser {
                // Rounded rect occupying left portion
                let bubbleRect = CGRect(x: 0, y: 0, width: rect.width - tailWidth, height: rect.height)
                path.addRoundedRect(in: bubbleRect, cornerWidth: cornerRadius, cornerHeight: cornerRadius)

                // Tail on bottom-right
                path.move(to: CGPoint(x: rect.width - tailWidth, y: rect.height - tailHeight - 4))
                path.addQuadCurve(
                    to: CGPoint(x: rect.width, y: rect.height),
                    control: CGPoint(x: rect.width - tailWidth + 2, y: rect.height - 2)
                )
                path.addQuadCurve(
                    to: CGPoint(x: rect.width - tailWidth - 4, y: rect.height),
                    control: CGPoint(x: rect.width - tailWidth - 2, y: rect.height)
                )
                path.closeSubpath()
            } else {
                // Rounded rect shifted right by tailWidth
                let bubbleRect = CGRect(x: tailWidth, y: 0, width: rect.width - tailWidth, height: rect.height)
                path.addRoundedRect(in: bubbleRect, cornerWidth: cornerRadius, cornerHeight: cornerRadius)

                // Tail on bottom-left
                path.move(to: CGPoint(x: tailWidth, y: rect.height - tailHeight - 4))
                path.addQuadCurve(
                    to: CGPoint(x: 0, y: rect.height),
                    control: CGPoint(x: tailWidth - 2, y: rect.height - 2)
                )
                path.addQuadCurve(
                    to: CGPoint(x: tailWidth + 4, y: rect.height),
                    control: CGPoint(x: tailWidth + 2, y: rect.height)
                )
                path.closeSubpath()
            }
        } else {
            // No tail — just a rounded rectangle
            path.addRoundedRect(in: rect, cornerWidth: cornerRadius, cornerHeight: cornerRadius)
        }

        return path
    }
}
