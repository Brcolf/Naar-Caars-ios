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
    private var center: NotificationCenter!

    override func setUp() {
        super.setUp()
        suiteName = "PendingInviteStoreTests.\(UUID().uuidString)"
        defaults = UserDefaults(suiteName: suiteName)
        center = NotificationCenter()
    }

    override func tearDown() {
        defaults.removePersistentDomain(forName: suiteName)
        defaults = nil
        suiteName = nil
        center = nil
        super.tearDown()
    }

    private func makeStore() -> PendingInviteStore {
        PendingInviteStore(defaults: defaults, now: { [unowned self] in self.now }, notificationCenter: center)
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

    // MARK: - didChange

    private func countPosts(_ body: () -> Void) -> Int {
        var count = 0
        let token = center.addObserver(forName: PendingInviteStore.didChange, object: nil, queue: nil) { _ in
            count += 1
        }
        body()
        center.removeObserver(token)
        return count
    }

    func testSave_PostsDidChange() {
        let store = makeStore()
        XCTAssertEqual(countPosts { store.save("NC7K2PQ9XA") }, 1)
        // An input that normalizes to nothing stores nothing and posts nothing.
        XCTAssertEqual(countPosts { store.save(" - ") }, 0)
    }

    func testClear_PostsDidChangeOnlyWhenACodeWasStored() {
        let store = makeStore()
        XCTAssertEqual(countPosts { store.clear() }, 0)
        store.save("NC7K2PQ9XA")
        XCTAssertEqual(countPosts { store.clearIfMatches("NC2222222A") }, 0)
        XCTAssertEqual(countPosts { store.clearIfMatches("NC7K2PQ9XA") }, 1)
        store.save("NC7K2PQ9XA")
        XCTAssertEqual(countPosts { store.clear() }, 1)
        XCTAssertEqual(countPosts { store.clear() }, 0)
    }
}

// MARK: - IncomingLinkHandler
//
// Join links handed to the scene: the code is saved first, then routed by launch state.

@MainActor
final class IncomingLinkHandlerTests: XCTestCase {
    private let coordinator = NavigationCoordinator.shared
    private let code = "NC7K2PQ9XA"
    private var suiteName = ""
    private var defaults: UserDefaults!
    private var store: PendingInviteStore!
    private var state: LaunchState = .initializing

    override func setUp() {
        super.setUp()
        suiteName = "IncomingLinkHandlerTests.\(UUID().uuidString)"
        defaults = UserDefaults(suiteName: suiteName)
        store = PendingInviteStore(defaults: defaults, notificationCenter: NotificationCenter())
        state = .initializing
        coordinator.resetNavigation()
        coordinator.selectedTab = .requests
    }

    override func tearDown() {
        defaults.removePersistentDomain(forName: suiteName)
        defaults = nil
        store = nil
        coordinator.resetNavigation()
        coordinator.selectedTab = .requests
        super.tearDown()
    }

    private func makeHandler() -> IncomingLinkHandler {
        IncomingLinkHandler(store: store, coordinator: coordinator, launchState: { [unowned self] in self.state })
    }

    private func joinURL(_ code: String) -> URL {
        URL(string: "https://naarscars.com/join#\(code)")!
    }

    private var routedToJoin: Bool {
        if case .joinCommunity = coordinator.pendingIntent { return true }
        return false
    }

    func testAuthenticated_SavesCodeAndRoutesJoinIntent() {
        state = .ready(.authenticated)
        let decision = makeHandler().handle(joinURL(code))
        XCTAssertEqual(decision, .route)
        XCTAssertEqual(store.peek(), code)
        XCTAssertTrue(routedToJoin)
        XCTAssertEqual(coordinator.pendingIntent?.targetTab, .explore)
    }

    func testGuest_SavesCodeAndRoutesJoinIntent() {
        state = .ready(.guest)
        XCTAssertEqual(makeHandler().handle(joinURL(code)), .route)
        XCTAssertEqual(store.peek(), code)
        XCTAssertTrue(routedToJoin)
    }

    func testSignedOut_SavesCodeWithoutRouting() {
        state = .ready(.unauthenticated)
        XCTAssertEqual(makeHandler().handle(joinURL(code)), .saveOnly)
        XCTAssertEqual(store.peek(), code)
        XCTAssertNil(coordinator.pendingIntent)
    }

    func testNeedsApplication_SavesCodeWithoutRouting() {
        state = .ready(.needsApplication)
        XCTAssertEqual(makeHandler().handle(joinURL(code)), .saveOnly)
        XCTAssertEqual(store.peek(), code)
        XCTAssertNil(coordinator.pendingIntent)
        for other: AuthState in [.pendingApproval, .banned, .loading] {
            XCTAssertEqual(IncomingLinkHandler.decision(for: .ready(other)), .saveOnly)
        }
    }

    func testNotReady_DefersAndReplaysOnceWhenGuest() {
        state = .initializing
        let handler = makeHandler()
        XCTAssertEqual(handler.handle(joinURL(code)), .defer)
        XCTAssertEqual(store.peek(), code)
        XCTAssertNil(coordinator.pendingIntent)

        handler.launchStateDidChange(.checkingAuth)
        XCTAssertNil(coordinator.pendingIntent, "still not ready: stays deferred")

        handler.launchStateDidChange(.ready(.guest))
        XCTAssertTrue(routedToJoin)

        coordinator.resetNavigation()
        handler.launchStateDidChange(.ready(.guest))
        XCTAssertNil(coordinator.pendingIntent, "a deferred link is replayed once")
    }

    func testNotReady_AuthenticatedReplayDoesNotRouteTwice() {
        state = .checkingAuth
        let handler = makeHandler()
        XCTAssertEqual(handler.handle(joinURL(code)), .defer)
        handler.launchStateDidChange(.ready(.authenticated))
        // MainTabView's offerPendingInviteIfNeeded opens My communities from the store.
        XCTAssertNil(coordinator.pendingIntent)
        XCTAssertEqual(store.peek(), code)
        XCTAssertEqual(IncomingLinkHandler.replayDecision(for: .ready(.authenticated)), .saveOnly)
        XCTAssertEqual(IncomingLinkHandler.replayDecision(for: .failed(AppError.unknown("x"))), .defer)
    }

    func testNonJoinURL_IsIgnoredAndSavesNothing() {
        state = .ready(.authenticated)
        let handler = makeHandler()
        XCTAssertNil(handler.handle(URL(string: "https://naarscars.com/other")!))
        XCTAssertNil(handler.handle(URL(string: "https://naarscars.com/join?code=\(code)")!))
        XCTAssertNil(store.peek())
        XCTAssertNil(coordinator.pendingIntent)
    }

    func testSecondLinkReplacesTheSavedCode() {
        state = .ready(.unauthenticated)
        let handler = makeHandler()
        handler.handle(joinURL(code))
        handler.handle(joinURL("NC2222222A"))
        XCTAssertEqual(store.peek(), "NC2222222A")
    }

    // MARK: - MyCommunitiesView's store-change rule

    func testStoreChange_OpensJoinWhenVisibleWithNoSheet() {
        XCTAssertEqual(
            MyCommunitiesView.joinCodeToOpenOnStoreChange(storedCode: code, hasSheet: false, isVisible: true),
            code
        )
    }

    func testStoreChange_NeverOpensUnderASheetOrWhenHidden() {
        XCTAssertNil(MyCommunitiesView.joinCodeToOpenOnStoreChange(storedCode: code, hasSheet: true, isVisible: true))
        XCTAssertNil(MyCommunitiesView.joinCodeToOpenOnStoreChange(storedCode: code, hasSheet: false, isVisible: false))
        XCTAssertNil(MyCommunitiesView.joinCodeToOpenOnStoreChange(storedCode: nil, hasSheet: false, isVisible: true))
    }

    func testStoreChange_HiddenByATabSwitch_OpensJoinOnNextAppear() {
        XCTAssertTrue(MyCommunitiesView.opensJoinOnNextAppear(storedCode: code, isVisible: false, screenPushedOnTop: false))
    }

    func testStoreChange_NeverDefersUnderAPushedScreenOrWhenVisibleOrWithNoCode() {
        XCTAssertFalse(MyCommunitiesView.opensJoinOnNextAppear(storedCode: code, isVisible: false, screenPushedOnTop: true))
        XCTAssertFalse(MyCommunitiesView.opensJoinOnNextAppear(storedCode: code, isVisible: true, screenPushedOnTop: false))
        XCTAssertFalse(MyCommunitiesView.opensJoinOnNextAppear(storedCode: nil, isVisible: false, screenPushedOnTop: false))
    }
}

// MARK: - ViewedCommunityStore

/// The listed community a guest last looked at, offered on Get started after sign-up.
final class ViewedCommunityStoreTests: XCTestCase {
    private var suiteName: String!
    private var defaults: UserDefaults!
    private var now = Date(timeIntervalSince1970: 1_790_000_000)
    private let communityId = UUID(uuidString: "5C000000-0000-4000-8000-000000000001")!

    override func setUp() {
        super.setUp()
        suiteName = "ViewedCommunityStoreTests.\(UUID().uuidString)"
        defaults = UserDefaults(suiteName: suiteName)
    }

    override func tearDown() {
        defaults.removePersistentDomain(forName: suiteName)
        defaults = nil
        suiteName = nil
        super.tearDown()
    }

    private func makeStore() -> ViewedCommunityStore {
        ViewedCommunityStore(defaults: defaults, now: { [unowned self] in self.now })
    }

    func testSaveAndPeek() {
        let store = makeStore()
        store.save(id: communityId, name: "Ballard Neighbors", joinPolicy: "approve")

        XCTAssertEqual(
            store.peek(),
            ViewedCommunity(id: communityId, name: "Ballard Neighbors", joinPolicy: "approve", savedAt: now)
        )
        XCTAssertNotNil(store.peek(), "peek does not clear")
        XCTAssertNotNil(defaults.data(forKey: ViewedCommunityStore.key))
    }

    func testExpiresAfterSevenDays() {
        let store = makeStore()
        store.save(id: communityId, name: "Ballard Neighbors", joinPolicy: "invite")

        now = now.addingTimeInterval(Constants.Community.viewedCommunityLifetime)
        XCTAssertNotNil(store.peek(), "still kept at exactly the lifetime")

        now = now.addingTimeInterval(1)
        XCTAssertNil(store.peek())
        XCTAssertNil(defaults.object(forKey: ViewedCommunityStore.key), "an expired community is removed")
    }

    func testClear() {
        let store = makeStore()
        store.save(id: communityId, name: "Ballard Neighbors", joinPolicy: "approve")
        store.clear()

        XCTAssertNil(store.peek())
        XCTAssertNil(defaults.object(forKey: ViewedCommunityStore.key))
        store.clear()   // nothing stored: still fine
    }
}
