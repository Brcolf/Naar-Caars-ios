import UIKit

// MARK: - BubblePath

/// UIBezierPath factory for message bubble shapes.
///
/// UIKit implementation of the iMessage-style bubble shape.
/// It produces a single continuous path for a rounded-rectangle bubble with an optional
/// iMessage-style tail on the last message in a series.
///
/// - Sent messages:    tail on bottom-right
/// - Received messages: tail on bottom-left
enum BubblePath {

    // MARK: - Constants

    private static let cornerRadius: CGFloat = 18
    private static let tailWidth: CGFloat = 6   // horizontal extent of the tail from the bubble edge
    private static let tailHeight: CGFloat = 8  // vertical extent the tail drops below the bubble base

    // MARK: - Public API

    /// Returns the bubble path for `rect`.
    ///
    /// When `showTail` is `true` the rect is inset on the tail side by `tailWidth` so the
    /// overall bounding box still fits within `rect`. The tail then extends back out to the
    /// edge of `rect`.
    ///
    /// - Parameters:
    ///   - rect:              The full bounding rectangle for the bubble (including tail space).
    ///   - isFromCurrentUser: `true` → sent bubble (tail bottom-right); `false` → received (tail bottom-left).
    ///   - showTail:          Whether to append the directional tail.
    static func path(in rect: CGRect, isFromCurrentUser: Bool, showTail: Bool) -> UIBezierPath {
        if showTail {
            return isFromCurrentUser
                ? sentBubblePath(in: rect)
                : receivedBubblePath(in: rect)
        } else {
            return taillessBubblePath(in: rect)
        }
    }

    // MARK: - Private helpers

    /// Rounded rectangle with no tail — fills `rect` exactly.
    private static func taillessBubblePath(in rect: CGRect) -> UIBezierPath {
        UIBezierPath(roundedRect: rect, cornerRadius: cornerRadius)
    }

    /// Sent bubble: body occupies `rect` minus `tailWidth` on the right; tail points bottom-right.
    private static func sentBubblePath(in rect: CGRect) -> UIBezierPath {
        let r = cornerRadius
        let tw = tailWidth
        let th = tailHeight

        // The bubble body sits in [0 .. width-tw] × [0 .. height]
        let bodyRect = CGRect(x: rect.minX,
                              y: rect.minY,
                              width: rect.width - tw,
                              height: rect.height)

        // We build a single continuous path that traces the full outline
        // (body rounded-rect + tail) clockwise from the top-left corner.
        let path = UIBezierPath()

        let minX = bodyRect.minX
        let minY = bodyRect.minY
        let maxX = bodyRect.maxX  // right edge of body (= rect.maxX - tw)
        let maxY = bodyRect.maxY  // bottom of body (= rect.maxY)

        // Top-left corner
        path.move(to: CGPoint(x: minX + r, y: minY))

        // Top edge → top-right corner
        path.addLine(to: CGPoint(x: maxX - r, y: minY))
        path.addArc(withCenter: CGPoint(x: maxX - r, y: minY + r),
                    radius: r,
                    startAngle: -.pi / 2,
                    endAngle: 0,
                    clockwise: true)

        // Right edge — tail root begins ~(tailHeight + 4) from the bottom
        let tailRootY = maxY - th - 4
        path.addLine(to: CGPoint(x: maxX, y: tailRootY))

        // Tail: curves from tail root out to the tip (rect.maxX, rect.maxY),
        // then back inward to just left of the tail root on the bottom edge.
        // Mirrors the SwiftUI quad-curves using cubic Bézier equivalents.
        //
        // Segment 1: tail root → tip  (down-right)
        let tipX = rect.maxX
        let tipY = rect.maxY
        path.addCurve(to: CGPoint(x: tipX, y: tipY),
                      controlPoint1: CGPoint(x: maxX, y: maxY - 2),
                      controlPoint2: CGPoint(x: maxX + tw / 2, y: maxY - 1))

        // Segment 2: tip → re-entry point on the bottom edge  (left, slightly above bottom)
        let reentryX = maxX - 4
        path.addCurve(to: CGPoint(x: reentryX, y: maxY),
                      controlPoint1: CGPoint(x: maxX + tw / 2 - 1, y: maxY),
                      controlPoint2: CGPoint(x: reentryX + 1, y: maxY))

        // Bottom edge (right → left)
        path.addLine(to: CGPoint(x: minX + r, y: maxY))

        // Bottom-left corner
        path.addArc(withCenter: CGPoint(x: minX + r, y: maxY - r),
                    radius: r,
                    startAngle: .pi / 2,
                    endAngle: .pi,
                    clockwise: true)

        // Left edge → top-left corner
        path.addLine(to: CGPoint(x: minX, y: minY + r))
        path.addArc(withCenter: CGPoint(x: minX + r, y: minY + r),
                    radius: r,
                    startAngle: .pi,
                    endAngle: -.pi / 2,
                    clockwise: true)

        path.close()
        return path
    }

    /// Received bubble: body occupies `[tw .. width] × [0 .. height]`; tail points bottom-left.
    private static func receivedBubblePath(in rect: CGRect) -> UIBezierPath {
        let r = cornerRadius
        let tw = tailWidth
        let th = tailHeight

        // Body sits in [tw .. rect.maxX] × [0 .. height]
        let bodyRect = CGRect(x: rect.minX + tw,
                              y: rect.minY,
                              width: rect.width - tw,
                              height: rect.height)

        let path = UIBezierPath()

        let minX = bodyRect.minX  // left edge of body (= rect.minX + tw)
        let minY = bodyRect.minY
        let maxX = bodyRect.maxX
        let maxY = bodyRect.maxY

        // Top-left corner of body
        path.move(to: CGPoint(x: minX + r, y: minY))

        // Top edge → top-right corner
        path.addLine(to: CGPoint(x: maxX - r, y: minY))
        path.addArc(withCenter: CGPoint(x: maxX - r, y: minY + r),
                    radius: r,
                    startAngle: -.pi / 2,
                    endAngle: 0,
                    clockwise: true)

        // Right edge → bottom-right corner
        path.addLine(to: CGPoint(x: maxX, y: maxY - r))
        path.addArc(withCenter: CGPoint(x: maxX - r, y: maxY - r),
                    radius: r,
                    startAngle: 0,
                    endAngle: .pi / 2,
                    clockwise: true)

        // Bottom edge (right → left), stopping before the tail re-entry
        let reentryX = minX + 4
        path.addLine(to: CGPoint(x: reentryX, y: maxY))

        // Tail: mirrors the sent-bubble tail but mirrored horizontally.
        //
        // Segment 2 (reversed draw order for winding): re-entry → tip  (down-left)
        let tipX = rect.minX
        let tipY = rect.maxY
        path.addCurve(to: CGPoint(x: tipX, y: tipY),
                      controlPoint1: CGPoint(x: reentryX - 1, y: maxY),
                      controlPoint2: CGPoint(x: tipX + tw / 2 - 1, y: maxY))

        // Segment 1 (reversed): tip → tail root on the left edge
        let tailRootY = maxY - th - 4
        path.addCurve(to: CGPoint(x: minX, y: tailRootY),
                      controlPoint1: CGPoint(x: tipX + tw / 2, y: maxY - 1),
                      controlPoint2: CGPoint(x: minX, y: maxY - 2))

        // Left edge (up) → top-left corner arc
        path.addLine(to: CGPoint(x: minX, y: minY + r))
        path.addArc(withCenter: CGPoint(x: minX + r, y: minY + r),
                    radius: r,
                    startAngle: .pi,
                    endAngle: -.pi / 2,
                    clockwise: true)

        path.close()
        return path
    }
}
