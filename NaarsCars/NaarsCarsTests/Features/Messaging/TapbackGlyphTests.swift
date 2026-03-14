import XCTest
@testable import NaarsCars

final class TapbackGlyphTests: XCTestCase {
    func testCoreReactionsReturnImages() {
        let coreReactions = ["\u{2764}\u{FE0F}", "\u{1F44D}", "\u{1F44E}", "\u{1F602}", "\u{203C}\u{FE0F}", "\u{2753}"]
        for reaction in coreReactions {
            let image = TapbackGlyph.image(for: reaction, pointSize: 13)
            XCTAssertNotNil(image, "Expected SF Symbol image for core reaction \(reaction)")
        }
    }

    func testExtendedReactionsReturnNil() {
        let extended = ["\u{1F525}", "\u{1F44F}", "\u{1F622}", "\u{1F4AF}", "\u{1F389}"]
        for reaction in extended {
            let image = TapbackGlyph.image(for: reaction, pointSize: 13)
            XCTAssertNil(image, "Expected nil for extended reaction \(reaction)")
        }
    }

    func testImageRenderingMode() {
        let image = TapbackGlyph.image(for: "\u{2764}\u{FE0F}", pointSize: 13)
        XCTAssertEqual(image?.renderingMode, .alwaysOriginal)
    }

    func testDifferentPointSizes() {
        let small = TapbackGlyph.image(for: "\u{1F44D}", pointSize: 13)
        let large = TapbackGlyph.image(for: "\u{1F44D}", pointSize: 22)
        XCTAssertNotNil(small)
        XCTAssertNotNil(large)
        XCTAssertGreaterThan(large!.size.width, small!.size.width)
    }
}
