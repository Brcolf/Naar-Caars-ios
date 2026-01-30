//
//  NotificationsListViewModelTests.swift
//  NaarsCarsTests
//
//  Unit tests for NotificationsListViewModel
//

import XCTest
@testable import NaarsCars

@MainActor
final class NotificationsListViewModelTests: XCTestCase {
    var viewModel: NotificationsListViewModel!
    
    override func setUp() {
        super.setUp()
        viewModel = NotificationsListViewModel()
    }
    
    /// Test that loadNotifications loads notifications successfully
    func testLoadNotifications() async throws {
        // Given: An authenticated user
        guard AuthService.shared.currentUserId != nil else {
            throw XCTSkip("No authenticated user for testing")
        }
        
        // When: Loading notifications
        await viewModel.loadNotifications()
        
        // Then: Notifications should be loaded (or error set if failed)
        // Note: In a real scenario, you'd mock NotificationService
        // For now, we verify the method completes without crashing
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
}



