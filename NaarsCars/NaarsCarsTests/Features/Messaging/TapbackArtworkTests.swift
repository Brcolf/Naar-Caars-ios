import XCTest
@testable import NaarsCars

final class TapbackArtworkTests: XCTestCase {
    func testIsHahaRecognizesLaughEmoji() {
        XCTAssertTrue(TapbackArtwork.isHaha("😂"))
    }

    func testIsHahaRejectsOtherEmoji() {
        XCTAssertFalse(TapbackArtwork.isHaha("❤️"))
        XCTAssertFalse(TapbackArtwork.isHaha("👍"))
        XCTAssertFalse(TapbackArtwork.isHaha("🔥"))
    }

    func testHahaImageReturnsNonNilAtAllSizes() {
        let sizes: [CGFloat] = [13, 22, 28]
        for size in sizes {
            let image = TapbackArtwork.hahaImage(pointSize: size)
            XCTAssertNotNil(image, "Expected HAHA image at pointSize \(size)")
        }
    }

    func testHahaImageScalesWithPointSize() {
        let small = TapbackArtwork.hahaImage(pointSize: 13)
        let large = TapbackArtwork.hahaImage(pointSize: 28)
        XCTAssertGreaterThan(large.size.width, small.size.width)
    }

    func testHahaImageRenderingMode() {
        let image = TapbackArtwork.hahaImage(pointSize: 22)
        XCTAssertEqual(image.renderingMode, .alwaysOriginal)
    }
}
