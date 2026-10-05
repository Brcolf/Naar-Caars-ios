//
//  NaarsCarsTests.swift
//  NaarsCarsTests
//
//  Created by Brendan Colford on 1/4/26.
//
//  Target sanity test. Kept as XCTest so the unit test target uses a single framework;
//  mixing in Swift Testing requires SWIFT_TESTING_XCTEST_INTEROP_MODE=limited since
//  Xcode 26.4 (see CLAUDE.md → Testing Expectations).
//

import XCTest

final class NaarsCarsTests: XCTestCase {

    func testTargetLoads() {
        XCTAssertTrue(true, "NaarsCarsTests target is wired and runs")
    }

}
