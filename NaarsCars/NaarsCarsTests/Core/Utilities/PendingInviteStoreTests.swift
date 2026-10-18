//
//  PendingInviteStoreTests.swift
//  NaarsCarsTests
//
//  The invite code kept for a signed-out visitor until it is redeemed
//

import XCTest
@testable import NaarsCars

final class PendingInviteStoreTests: XCTestCase {
    private var suiteName: String!
    private var defaults: UserDefaults!
    private var now = Date(timeIntervalSince1970: 1_790_000_000)

    override func setUp() {
        super.setUp()
        suiteName = "PendingInviteStoreTests.\(UUID().uuidString)"
        defaults = UserDefaults(suiteName: suiteName)
    }

    override func tearDown() {
        defaults.removePersistentDomain(forName: suiteName)
        defaults = nil
        suiteName = nil
        super.tearDown()
    }

    private func makeStore() -> PendingInviteStore {
        PendingInviteStore(defaults: defaults, now: { [unowned self] in self.now })
    }

    func testSave_StoresNormalizedCode() {
        let store = makeStore()
        store.save("nc7k · 2pq9-xa")
        XCTAssertEqual(store.peek(), "NC7K2PQ9XA")
    }

    func testPeek_DoesNotClear() {
        let store = makeStore()
        store.save("NC7K2PQ9XA")
        XCTAssertEqual(store.peek(), "NC7K2PQ9XA")
        XCTAssertEqual(store.peek(), "NC7K2PQ9XA")
    }

    func testClearIfMatches_OnlyClearsTheSameCode() {
        let store = makeStore()
        store.save("NC7K2PQ9XA")
        store.clearIfMatches("NC2222222A")
        XCTAssertEqual(store.peek(), "NC7K2PQ9XA")
        store.clearIfMatches("NC7K2PQ9XA")
        XCTAssertNil(defaults.object(forKey: PendingInviteStore.codeKey))
        XCTAssertNil(defaults.object(forKey: PendingInviteStore.savedAtKey))
    }

    func testPeek_ExpiresAfterSevenDays() {
        let store = makeStore()
        store.save("NC7K2PQ9XA")
        now = now.addingTimeInterval(Constants.Community.pendingInviteLifetime + 1)
        XCTAssertNil(store.peek())
        XCTAssertNil(defaults.object(forKey: PendingInviteStore.codeKey))
        XCTAssertNil(defaults.object(forKey: PendingInviteStore.savedAtKey))
    }

    func testClear_RemovesBothKeys() {
        let store = makeStore()
        store.save("NC7K2PQ9XA")
        store.clear()
        XCTAssertNil(defaults.object(forKey: PendingInviteStore.codeKey))
        XCTAssertNil(defaults.object(forKey: PendingInviteStore.savedAtKey))
    }
}
