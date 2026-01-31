import XCTest
@testable import NaarsCars

final class PromptQueueTests: XCTestCase {
    func testEnqueueSortsOldestFirst() {
        let older = PromptItem.review(.init(
            id: UUID(), requestType: .ride, requestId: UUID(),
            requestTitle: "Ride", fulfillerId: UUID(), fulfillerName: "Alex",
            createdAt: Date(timeIntervalSince1970: 100)
        ))
        let newer = PromptItem.completion(.init(
            id: UUID(), reminderId: UUID(), requestType: .favor,
            requestId: UUID(), requestTitle: "Favor",
            dueAt: Date(timeIntervalSince1970: 200)
        ))

        var queue = PromptQueue()
        queue.enqueue(newer)
        queue.enqueue(older)

        XCTAssertEqual(queue.dequeue(), older)
        XCTAssertEqual(queue.dequeue(), newer)
    }

    func testEnqueueDedupesById() {
        let id = UUID()
        let prompt = PromptItem.review(.init(
            id: id, requestType: .ride, requestId: UUID(),
            requestTitle: "Ride", fulfillerId: UUID(), fulfillerName: "Alex",
            createdAt: Date()
        ))

        var queue = PromptQueue()
        queue.enqueue(prompt)
        queue.enqueue(prompt)

        XCTAssertEqual(queue.count, 1)
    }
}
