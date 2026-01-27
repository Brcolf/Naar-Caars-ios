//
//  ThrottlerTests.swift
//  NaarsCarsTests
//
//  Unit tests for Throttler
//

import XCTest
@testable import NaarsCars

@MainActor
final class ThrottlerTests: XCTestCase {
    private var throttler: Throttler!

    override func setUp() {
        super.setUp()
        throttler = Throttler.shared
    }

    func testRunExecutesImmediatelyWhenNotThrottled() async {
        let expectation = XCTestExpectation(description: "Operation runs immediately")
        let start = Date()

        await throttler.run(key: "immediate", minimumInterval: 0.5) {
            let elapsed = Date().timeIntervalSince(start)
            XCTAssertLessThan(elapsed, 0.2, "Expected immediate execution")
            expectation.fulfill()
        }

        await fulfillment(of: [expectation], timeout: 1.0)
    }

    func testRunCoalescesCallsWithinInterval() async {
        let expectation = XCTestExpectation(description: "Operations are coalesced")
        expectation.expectedFulfillmentCount = 2

        let counter = Counter()

        await throttler.run(key: "coalesce", minimumInterval: 0.2) {
            await counter.increment()
            expectation.fulfill()
        }

        await throttler.run(key: "coalesce", minimumInterval: 0.2) {
            await counter.increment()
            expectation.fulfill()
        }

        await throttler.run(key: "coalesce", minimumInterval: 0.2) {
            await counter.increment()
            expectation.fulfill()
        }

        await fulfillment(of: [expectation], timeout: 1.0)
        let value = await counter.value
        XCTAssertEqual(value, 2, "Expected leading + trailing execution")
    }

    func testRunDelaysTrailingExecutionUntilInterval() async {
        let expectation = XCTestExpectation(description: "Trailing execution is delayed")
        expectation.expectedFulfillmentCount = 2

        let tracker = TimeTracker()
        let start = Date()

        await throttler.run(key: "delay", minimumInterval: 0.3) {
            await tracker.record(Date().timeIntervalSince(start))
            expectation.fulfill()
        }

        await throttler.run(key: "delay", minimumInterval: 0.3) {
            await tracker.record(Date().timeIntervalSince(start))
            expectation.fulfill()
        }

        await fulfillment(of: [expectation], timeout: 2.0)
        let times = await tracker.values
        XCTAssertEqual(times.count, 2)
        XCTAssertGreaterThanOrEqual(times[1], 0.3, "Trailing execution should wait for interval")
    }
}

private actor Counter {
    private var count = 0

    func increment() {
        count += 1
    }

    var value: Int { count }
}

private actor TimeTracker {
    private var values: [TimeInterval] = []

    func record(_ value: TimeInterval) {
        values.append(value)
    }
}
