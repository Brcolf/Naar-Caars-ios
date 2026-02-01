import XCTest
import SwiftUI
@testable import NaarsCars

final class CompletionPromptViewTests: XCTestCase {
    func testCompletionPromptViewInitializes() {
        let view = CompletionPromptView(
            prompt: CompletionPrompt(
                id: UUID(), reminderId: UUID(), requestType: .ride,
                requestId: UUID(), requestTitle: "Ride", dueAt: Date()
            ),
            onConfirm: {},
            onSnooze: {}
        )
        _ = view.body
        XCTAssertTrue(true)
    }
}
