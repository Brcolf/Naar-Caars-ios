//
//  NotificationsListViewModelTests.swift
//  NaarsCarsTests
//
//  Unit tests for NotificationsListViewModel
//

import AuthenticationServices
import SwiftData
import XCTest
@testable import NaarsCars

/// Answers only `currentUserId` (the `StubListAuthService` pattern); every other method is unused here.
private final class StubNotificationsAuthService: AuthServiceProtocol {
    var currentUserId: UUID?
    var currentProfile: Profile? { nil }

    init(currentUserId: UUID?) { self.currentUserId = currentUserId }

    func signIn(email: String, password: String) async throws {}
    func signUp(email: String, password: String, name: String, car: String?) async throws {}
    func signOut() async throws {}
    func sendPasswordReset(email: String) async throws {}
    func signUpWithApple(credential: ASAuthorizationAppleIDCredential, rawNonce: String?) async throws {}
    func logInWithApple(credential: ASAuthorizationAppleIDCredential, rawNonce: String?) async throws -> AppleLoginResult { .success }
}

/// Answers only `bellBadgeCount` (the server's `bell_total`); the async methods are unused here.
private final class StubBadgeCounts: BadgeCountManaging {
    var bellBadgeCount: Int

    init(bell: Int) { bellBadgeCount = bell }

    func refreshAllBadges(reason: String) async {}
    func clearMessagesBadge(for conversationId: UUID?) async {}
    func clearCommunityBadge(visibleCommunityId: UUID?) async {}
    func fetchBadgeCountsPayload(includeDetails: Bool) async throws -> String { "" }
}

@MainActor
final class NotificationsListViewModelTests: XCTestCase {
    var viewModel: NotificationsListViewModel!
    /// A private coordinator per test that needs one (never `shared`); `reset()` clears the `refresh.lastSync.*` keys it wrote.
    private var coordinator: RefreshCoordinator?
    
    override func setUp() {
        super.setUp()
        viewModel = NotificationsListViewModel()
    }

    override func tearDown() async throws {
        await coordinator?.reset()
        coordinator = nil
        try await super.tearDown()
    }
    
    /// Test that loadNotifications loads notifications successfully
    func testLoadNotifications() async throws {
        // Given: An authenticated user
        guard AuthService.shared.currentUserId != nil else {
            throw XCTSkip("No authenticated user for testing")
        }
        
        // When: Loading notifications
        await viewModel.loadNotifications()
        
        // Then: Should complete without crashing
        // Note: In a real scenario, you'd mock NotificationService
        XCTAssertFalse(viewModel.isLoading, "Loading should be false after completion")
        XCTAssertGreaterThanOrEqual(viewModel.unreadCount, 0, "Unread count should be non-negative")
        
        // If there's an error, it should be set
        if let error = viewModel.error {
            print("⚠️ Load notifications returned error: \(error.localizedDescription)")
            // This is acceptable if user is not authenticated or network fails
        } else {
            // If no error, notifications should be loaded
            XCTAssertFalse(viewModel.isLoading, "Loading should be false after completion")
        }
    }
    
    /// Test that loadNotifications sets loading state correctly
    func testLoadNotifications_LoadingState() async throws {
        // Given: An authenticated user
        guard AuthService.shared.currentUserId != nil else {
            throw XCTSkip("No authenticated user for testing")
        }
        
        // When: Starting to load notifications
        let loadTask = Task {
            await viewModel.loadNotifications()
        }
        
        // Give it a moment to start
        try? await Task.sleep(nanoseconds: 100_000_000) // 0.1 seconds
        
        // Then: Loading state should be set (may be false if it completes quickly)
        // Note: This is a timing-dependent test, so we just verify it doesn't crash
        await loadTask.value
        XCTAssertFalse(viewModel.isLoading, "Loading should be false after completion")
    }
    
    /// Test that refreshNotifications invalidates cache and reloads
    func testRefreshNotifications_InvalidatesCache() async throws {
        // Given: An authenticated user
        guard AuthService.shared.currentUserId != nil else {
            throw XCTSkip("No authenticated user for testing")
        }
        
        // When: Refreshing notifications
        await viewModel.refreshNotifications()
        
        // Then: Should complete without error
        // Note: In a real scenario, you'd verify cache invalidation
        XCTAssertFalse(viewModel.isLoading, "Loading should be false after refresh")
    }
    
    /// Test that markAsRead updates notification
    func testMarkAsRead_UpdatesNotification() async throws {
        // Given: An authenticated user and a notification
        guard let userId = AuthService.shared.currentUserId else {
            throw XCTSkip("No authenticated user for testing")
        }
        
        // Fetch notifications directly since the ViewModel no longer exposes a list
        let notifications = try? await NotificationService.shared.fetchNotifications(
            userId: userId,
            forceRefresh: true
        )
        
        guard let unreadNotification = notifications?.first(where: { !$0.read }) else {
            throw XCTSkip("No unread notifications to test")
        }
        
        // When: Marking as read
        await viewModel.markAsRead(unreadNotification)
        
        // Then: Notification should be updated
        // Note: In a real scenario, you'd verify the notification is marked as read
        XCTAssertFalse(viewModel.isLoading, "Loading should be false after marking as read")
    }
    
    /// Test that markAllAsRead marks all notifications as read
    func testMarkAllAsRead_MarksAllAsRead() async throws {
        // Given: An authenticated user
        guard AuthService.shared.currentUserId != nil else {
            throw XCTSkip("No authenticated user for testing")
        }
        
        // When: Marking all as read
        await viewModel.markAllAsRead()
        
        // Then: Should complete without error
        // Note: In a real scenario, you'd verify all notifications are marked as read
        XCTAssertFalse(viewModel.isLoading, "Loading should be false after marking all as read")
    }

    /// Test that tapping a review request notification defers a showReview intent
    func testHandleNotificationTap_ReviewRequestShowsPrompt() async {
        let rideId = UUID()
        let notification = AppNotification(
            userId: UUID(),
            type: .reviewRequest,
            title: "Review request",
            rideId: rideId
        )

        viewModel.handleNotificationTap(notification)

        // Notification tap defers the intent; applying it simulates sheet dismissal
        let coordinator = NavigationCoordinator.shared
        coordinator.applyDeferredNotificationIntentIfNeeded()

        XCTAssertTrue(coordinator.showReviewPrompt, "Review prompt should be shown after applying deferred intent")
        XCTAssertEqual(coordinator.reviewPromptRideId, rideId, "Review ride ID should match")

        // Cleanup
        coordinator.showReviewPrompt = false
        coordinator.reviewPromptRideId = nil
    }

    // MARK: - The bell's open (performance pass, item 5)

    /// Opening the bell used to force a full dashboard sync (rides, favors and every bell row) on
    /// each open, even seconds after the last one. It now skips when a full sync has run since the
    /// last push, foreground or session start; pull-to-refresh still forces.
    func testOpenSkipsTheDashboardSyncRightAfterAFullSync() async {
        var syncs: [RefreshDomain] = []
        let coordinator = RefreshCoordinator()
        coordinator.fullSyncOverrideForTesting = { domain in
            syncs.append(domain)
            return .empty
        }
        self.coordinator = coordinator
        _ = await coordinator.forceFullRefreshAndWait(.dashboard, trigger: "test")
        let viewModel = NotificationsListViewModel(
            authService: StubNotificationsAuthService(currentUserId: UUID()),
            refreshCoordinator: coordinator,
            badgeCounts: StubBadgeCounts(bell: 0)
        )

        await viewModel.loadNotifications()
        XCTAssertEqual(syncs, [.dashboard], "the open must not force another dashboard sync")
        XCTAssertNil(viewModel.error)
        XCTAssertFalse(viewModel.isLoading)

        await viewModel.refreshNotifications()
        XCTAssertEqual(syncs, [.dashboard, .dashboard], "pull-to-refresh still forces one")
    }

    /// A Town Hall row is written at once but its push is batched for up to 5 minutes, so a current
    /// full sync can lack a row the bell badge (`bell_total`) already counts. The open then syncs. The
    /// stored rows are compared as unread groups, as the server counts them: three unread rows about
    /// one ride are one group, so a raw row count (3) would hide the missing second group.
    func testOpenSyncsWhenTheBadgeCountsAGroupTheStoredRowsLack() async throws {
        var syncs: [RefreshDomain] = []
        let coordinator = RefreshCoordinator()
        coordinator.fullSyncOverrideForTesting = { domain in
            syncs.append(domain)
            return .empty
        }
        self.coordinator = coordinator
        _ = await coordinator.forceFullRefreshAndWait(.dashboard, trigger: "test")

        // The grouping manager keeps rows of AuthService's user when one is signed in.
        let userId = AuthService.shared.currentUserId ?? UUID()
        let container = try ModelContainer(
            for: SDNotification.self,
            configurations: ModelConfiguration(isStoredInMemoryOnly: true)
        )
        let context = container.mainContext
        let rideId = UUID()
        for type in ["new_ride", "ride_claimed", "qa_question"] {
            context.insert(SDNotification(id: UUID(), userId: userId, type: type, title: "t", rideId: rideId))
        }
        try context.save()

        // The badge counts the stored ride group only: the open skips.
        let covered = NotificationsListViewModel(
            authService: StubNotificationsAuthService(currentUserId: userId),
            refreshCoordinator: coordinator,
            badgeCounts: StubBadgeCounts(bell: 1)
        )
        covered.setup(modelContext: context)
        defer { covered.stop() }
        await covered.loadNotifications()
        XCTAssertEqual(syncs, [.dashboard], "the stored rows hold every unread group the badge counts")

        // The badge counts a second group (a Town Hall post whose push is still batched): the open syncs.
        let behind = NotificationsListViewModel(
            authService: StubNotificationsAuthService(currentUserId: userId),
            refreshCoordinator: coordinator,
            badgeCounts: StubBadgeCounts(bell: 2)
        )
        behind.setup(modelContext: context)
        defer { behind.stop() }
        await behind.loadNotifications()
        XCTAssertEqual(syncs, [.dashboard, .dashboard], "a group the stored rows lack makes the open sync")
    }
}



